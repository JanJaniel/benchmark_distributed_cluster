#!/bin/bash
# Teardown distributed Arroyo cluster

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/cluster-env.sh"

echo "========================================="
echo "Tearing Down Distributed Arroyo Cluster"
echo "========================================="

# Function to stop services on a node
stop_services() {
    local ip=$1
    local hostname=$2
    local compose_dir=$3
    
    echo "Stopping services on $hostname ($ip)..."
    
    ssh ${CLUSTER_USER}@${ip} << EOF
if [ -d "$compose_dir" ]; then
    cd "$compose_dir"
    docker compose down -v
else
    echo "Compose directory not found: $compose_dir"
fi
EOF
}

# Stop data generator if running
echo "Stopping data generator..."
ssh ${CLUSTER_USER}@${CONTROLLER_IP} "docker stop nexmark-generator 2>/dev/null || true"

# Stop all worker nodes
echo -e "\nStopping worker nodes..."
for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    WORKER_HOST=$(get_worker_host $i)
    stop_services $WORKER_IP $WORKER_HOST "~/benchmark_distributed_cluster/deploy/worker"
done

# Stop controller services
echo -e "\nStopping controller services..."
stop_services $CONTROLLER_IP $CONTROLLER_HOST "~/benchmark_distributed_cluster/deploy/controller"

# Optional: Clean up data
read -p "Remove all data volumes? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up data volumes..."
    
    # Clean controller
    ssh ${CLUSTER_USER}@${CONTROLLER_IP} << 'EOF'
docker volume rm $(docker volume ls -q | grep -E "(kafka|zookeeper|minio|arroyo)") 2>/dev/null || true
EOF
    
    # Clean workers
    for i in $(seq 1 $NUM_WORKERS); do
        WORKER_IP=$(get_worker_ip $i)
        ssh ${CLUSTER_USER}@${WORKER_IP} "docker volume prune -f" 2>/dev/null || true
    done
fi

# Optional: Remove project files from workers only (keep on controller)
read -p "Remove project files from worker nodes? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing project files from workers..."

    # Remove from workers only
    exec_on_workers "rm -rf ~/benchmark_distributed_cluster"
fi

echo -e "\n========================================="
echo "Cluster Teardown Complete"
echo "========================================="