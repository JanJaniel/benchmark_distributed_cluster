#!/bin/bash
# Setup script for distributed Arroyo cluster on 10 Raspberry Pis

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load cluster configuration
source "$SCRIPT_DIR/cluster-env.sh"

echo "========================================="
echo "Setting up Distributed Arroyo Cluster"
echo "========================================="

# Function to check SSH connectivity
check_ssh() {
    local ip=$1
    echo -n "Checking SSH to $ip... "
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no picocluster@$ip "echo 'OK'" >/dev/null 2>&1; then
        echo "✓"
        return 0
    else
        echo "✗"
        return 1
    fi
}

# Function to install Docker on a Pi
install_docker() {
    local ip=$1
    local hostname=$2
    
    echo "Checking Docker on $hostname ($ip)..."
    
    if ssh picocluster@$ip "docker --version" >/dev/null 2>&1; then
        echo "Docker already installed on $hostname"
    else
        echo "Installing Docker on $hostname..."
        ssh picocluster@$ip "curl -fsSL https://get.docker.com | sudo sh"
        ssh picocluster@$ip "sudo usermod -aG docker picocluster"
        echo "Docker installed. Please ensure user has logged out and back in."
    fi
}

# Step 1: Check SSH connectivity to all nodes
echo -e "\n1. Checking SSH connectivity..."
FAILED=0

check_ssh $CONTROLLER_IP || FAILED=1

for i in {1..9}; do
    WORKER_IP=$(get_worker_ip $i)
    check_ssh $WORKER_IP || FAILED=1
done

if [ $FAILED -eq 1 ]; then
    echo -e "\n❌ SSH connectivity check failed!"
    echo "Please ensure:"
    echo "  1. All Pis are powered on and connected to the network"
    echo "  2. SSH keys are properly set up (run setup-ssh-keys.sh)"
    exit 1
fi

echo -e "\n✅ All nodes are accessible"

# Step 2: Install Docker on all nodes
echo -e "\n2. Installing Docker on all nodes..."

install_docker $CONTROLLER_IP "pi1"

for i in {1..9}; do
    WORKER_IP=$(get_worker_ip $i)
    install_docker $WORKER_IP "pi$((i+1))"
done

# Step 3: Copy project files to all nodes
echo -e "\n3. Copying project files to all nodes..."

# Check if we're running on the controller node
CURRENT_IP=$(hostname -I | awk '{print $1}')

# Controller node - only copy if we're not already on the controller
if [[ "$CURRENT_IP" != "$CONTROLLER_IP" ]]; then
    echo "Copying files to controller (pi1)..."
    ssh picocluster@$CONTROLLER_IP "mkdir -p ~/benchmark_distributed_cluster"
    scp -r "$PROJECT_ROOT"/* picocluster@$CONTROLLER_IP:~/benchmark_distributed_cluster/
else
    echo "Skipping controller copy (running on controller node)"
fi

# Worker nodes
for i in {1..9}; do
    WORKER_IP=$(get_worker_ip $i)
    echo "Copying files to worker pi$((i+1))..."
    ssh picocluster@$WORKER_IP "mkdir -p ~/benchmark_distributed_cluster"
    scp -r "$PROJECT_ROOT"/* picocluster@$WORKER_IP:~/benchmark_distributed_cluster/
done

# Step 4: Build Docker images
echo -e "\n4. Building Docker images..."

# Build on controller (images will be used locally)
echo "Building Arroyo image on controller..."
ssh picocluster@$CONTROLLER_IP "cd ~/benchmark_distributed_cluster && docker build -t arroyo-pi:latest -f docker/arroyo/Dockerfile docker/arroyo"

# Build on each worker
for i in {1..9}; do
    WORKER_IP=$(get_worker_ip $i)
    echo "Building Arroyo image on worker pi$((i+1))..."
    ssh picocluster@$WORKER_IP "cd ~/benchmark_distributed_cluster && docker build -t arroyo-pi:latest -f docker/arroyo/Dockerfile docker/arroyo" &
done

# Wait for all builds to complete
wait

# Step 5: Start controller services
echo -e "\n5. Starting controller services on pi1..."

ssh picocluster@$CONTROLLER_IP "cd ~/benchmark_distributed_cluster/deploy/controller && docker compose up -d"

# Wait for services to be ready
echo "Waiting for controller services to start..."
sleep 30

# Check controller health
echo "Checking controller health..."
if curl -f -L http://$CONTROLLER_IP:8000 >/dev/null 2>&1; then
    echo "✅ Arroyo controller is healthy"
else
    echo "⚠️  Arroyo controller may still be starting up"
    echo "You can check the Web UI at: http://$CONTROLLER_IP:8000"
    echo "Check logs with: ssh picocluster@$CONTROLLER_IP 'cd ~/benchmark_distributed_cluster/deploy/controller && docker compose logs'"
fi

# Step 6: Start worker nodes
echo -e "\n6. Starting worker nodes..."

for i in {1..9}; do
    WORKER_IP=$(get_worker_ip $i)
    NODE_ID="worker-$i"
    WORKER_ID="$i"
    
    echo "Starting worker on pi$((i+1))..."
    ssh picocluster@$WORKER_IP "cd ~/benchmark_distributed_cluster/deploy/worker && NODE_ID=$NODE_ID WORKER_ID=$WORKER_ID docker compose up -d"
done

# Step 7: Wait for all workers to connect
echo -e "\n7. Waiting for workers to connect..."
sleep 20

# Step 8: Create Kafka topics
echo -e "\n8. Creating Kafka topics..."

ssh picocluster@$CONTROLLER_IP << 'EOF'
docker exec kafka kafka-topics --create --if-not-exists \
    --bootstrap-server localhost:19092 \
    --topic nexmark-person \
    --partitions 9 \
    --replication-factor 1

docker exec kafka kafka-topics --create --if-not-exists \
    --bootstrap-server localhost:19092 \
    --topic nexmark-auction \
    --partitions 9 \
    --replication-factor 1

docker exec kafka kafka-topics --create --if-not-exists \
    --bootstrap-server localhost:19092 \
    --topic nexmark-bid \
    --partitions 9 \
    --replication-factor 1
EOF

# Step 9: Verify cluster status
echo -e "\n9. Verifying cluster status..."

echo -e "\n========================================="
echo "Cluster Setup Complete!"
echo "========================================="
echo ""
echo "Access points:"
echo "  - Arroyo Web UI: http://$CONTROLLER_IP:8000"
echo "  - MinIO Console: http://$CONTROLLER_IP:9001"
echo "  - Kafka Broker: $CONTROLLER_IP:9094"
echo ""
echo "Next steps:"
echo "  - Run benchmark with: ./scripts/run-benchmark.sh"
echo ""