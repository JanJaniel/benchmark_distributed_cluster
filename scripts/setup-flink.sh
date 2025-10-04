#!/bin/bash
# Setup Flink cluster on Raspberry Pi nodes

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/cluster-env.sh"

echo "========================================="
echo "Setting up Flink Cluster"
echo "========================================="
echo ""

# Check if Kafka is running, if not start it
echo "Checking Kafka status..."
KAFKA_RUNNING=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "docker ps -q -f name=kafka" || echo "")
if [ -z "$KAFKA_RUNNING" ]; then
    echo "Kafka not running, starting Kafka infrastructure..."
    ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} << 'EOF'
cd ~/benchmark_distributed_cluster/deploy/controller
docker compose up -d kafka zookeeper minio
EOF
    echo "Waiting for Kafka to be ready..."
    sleep 20
    echo "✅ Kafka infrastructure started"
else
    echo "✅ Kafka already running"
fi
echo ""

# Build Flink Docker image
echo "Building Flink Docker image..."
cd "$SCRIPT_DIR/../flink-queries"
docker build -t flink-nexmark:latest .
echo "✅ Flink image built"
echo ""

# Save and distribute image to all nodes
echo "Saving Flink image to tarball..."
docker save flink-nexmark:latest | gzip > /tmp/flink-nexmark.tar.gz
echo "✅ Image saved"
echo ""

echo "Distributing Flink image to all nodes..."

# Load on controller (image is already here since we built it locally)
echo "  Loading image on controller..."
docker load < /tmp/flink-nexmark.tar.gz

# Copy and load on workers
for i in $(seq 1 $NUM_WORKERS); do
    NODE_IP=$(get_worker_ip $i)
    echo "  [$i/$NUM_WORKERS] Copying to worker $i ($NODE_IP)..."
    scp -o LogLevel=ERROR /tmp/flink-nexmark.tar.gz ${CLUSTER_USER}@${NODE_IP}:/tmp/
    echo "  [$i/$NUM_WORKERS] Loading image on worker $i..."
    ssh -o LogLevel=ERROR ${CLUSTER_USER}@${NODE_IP} "docker load < /tmp/flink-nexmark.tar.gz && rm /tmp/flink-nexmark.tar.gz"
    echo "  [$i/$NUM_WORKERS] ✅ Worker $i complete"
done

# Clean up local tarball after ALL nodes are done
rm /tmp/flink-nexmark.tar.gz
echo "✅ Image distributed to all nodes"
echo ""

# Deploy docker-compose files
echo "Deploying Flink docker-compose files..."

# Controller (JobManager)
echo "  Deploying JobManager to controller..."
ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "mkdir -p ~/flink-deploy"
scp -o LogLevel=ERROR "$SCRIPT_DIR/../deploy/controller-flink/docker-compose.yml" \
    ${CLUSTER_USER}@${CONTROLLER_IP}:~/flink-deploy/docker-compose.yml

# Workers (TaskManagers)
for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    echo "  Deploying TaskManager to worker $i ($WORKER_IP)..."
    ssh -o LogLevel=ERROR ${CLUSTER_USER}@${WORKER_IP} "mkdir -p ~/flink-deploy"
    scp -o LogLevel=ERROR "$SCRIPT_DIR/../deploy/worker-flink/docker-compose.yml" \
        ${CLUSTER_USER}@${WORKER_IP}:~/flink-deploy/docker-compose.yml
done

echo "✅ Docker-compose files deployed"
echo ""

# Start Flink JobManager on controller
echo "Starting Flink JobManager on controller..."
ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} \
    "cd ~/flink-deploy && docker compose up -d"
echo "✅ JobManager started"
echo ""

# Wait for JobManager to be ready
echo "Waiting for JobManager to be ready..."
sleep 10

# Start Flink TaskManagers on workers
echo "Starting Flink TaskManagers on workers..."
for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    echo "  Starting TaskManager on worker $i ($WORKER_IP)..."
    ssh -o LogLevel=ERROR ${CLUSTER_USER}@${WORKER_IP} \
        "cd ~/flink-deploy && NODE_ID=$i WORKER_IP=$WORKER_IP docker compose up -d"
done
echo "✅ All TaskManagers started"
echo ""

# Wait for cluster to be fully ready
echo "Waiting for Flink cluster to be fully ready..."
sleep 15

# Check cluster status
echo "Checking Flink cluster status..."
echo ""
echo "  Testing JobManager REST API..."
REST_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://${CONTROLLER_IP}:8081/overview" 2>&1)
HTTP_CODE=$(echo "$REST_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)

if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ JobManager REST API accessible at http://${CONTROLLER_IP}:8081"
else
    echo "  ❌ JobManager REST API not responding (HTTP $HTTP_CODE)"
    echo "  Debug: Check JobManager logs with: ssh ${CLUSTER_USER}@${CONTROLLER_IP} 'docker logs flink-jobmanager'"
fi
echo ""

echo "  Testing JobManager RPC port..."
# Try with nc first, fallback to netstat/ss if nc is not available
if command -v nc &> /dev/null; then
    if nc -z -w 2 ${CONTROLLER_IP} 6123 2>/dev/null; then
        echo "  ✅ JobManager RPC port 6123 is open"
    else
        echo "  ❌ JobManager RPC port 6123 not accessible"
    fi
elif command -v netstat &> /dev/null; then
    if ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "netstat -tuln | grep -q ':6123.*LISTEN'" 2>/dev/null; then
        echo "  ✅ JobManager RPC port 6123 is listening"
    else
        echo "  ❌ JobManager RPC port 6123 not listening"
    fi
elif command -v ss &> /dev/null; then
    if ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "ss -tuln | grep -q ':6123.*LISTEN'" 2>/dev/null; then
        echo "  ✅ JobManager RPC port 6123 is listening"
    else
        echo "  ❌ JobManager RPC port 6123 not listening"
    fi
else
    echo "  ⚠️  Cannot test port (nc/netstat/ss not available) - assuming OK"
fi
echo ""

echo "  Querying registered TaskManagers..."
TASKMANAGERS=$(curl -s "http://${CONTROLLER_IP}:8081/taskmanagers" | grep -o '"id"' | wc -l || echo "0")
echo "  TaskManagers registered: $TASKMANAGERS / $NUM_WORKERS"
echo ""

if [ "$TASKMANAGERS" -eq "$NUM_WORKERS" ]; then
    echo "✅ Flink cluster is ready!"
else
    echo "⚠️  Warning: Expected $NUM_WORKERS TaskManagers but found $TASKMANAGERS"
    echo ""
    echo "Debugging tips:"
    echo "  1. Check JobManager logs:"
    echo "     ssh ${CLUSTER_USER}@${CONTROLLER_IP} 'docker logs flink-jobmanager | tail -50'"
    echo ""
    echo "  2. Check a worker's logs (replace 1 with worker number):"
    echo "     ssh ${CLUSTER_USER}@192.168.2.71 'docker logs flink-worker-1 | tail -50'"
    echo ""
    echo "  3. Verify network connectivity from worker to JobManager:"
    echo "     ssh ${CLUSTER_USER}@192.168.2.71 'nc -zv 192.168.2.70 6123'"
    echo ""
    echo "  4. Check if containers are running:"
    echo "     ssh ${CLUSTER_USER}@${CONTROLLER_IP} 'docker ps | grep flink'"
fi

echo ""
echo "========================================="
echo "Flink Cluster Setup Complete"
echo "========================================="
echo ""
echo "Flink Web UI: http://${CONTROLLER_IP}:8081"
echo ""
echo "To run benchmarks:"
echo "  ./scripts/run-benchmark.sh flink"
echo ""
echo "To teardown the cluster:"
echo "  ./scripts/teardown-flink.sh"
echo ""
