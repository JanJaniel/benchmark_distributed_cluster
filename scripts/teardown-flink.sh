#!/bin/bash
# Teardown Flink cluster on Raspberry Pi nodes

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/cluster-env.sh"

echo "========================================="
echo "Tearing down Flink Cluster"
echo "========================================="
echo ""

# Stop TaskManagers on workers
echo "Stopping Flink TaskManagers..."
for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    echo "  Stopping TaskManager on worker $i ($WORKER_IP)..."
    ssh -o LogLevel=ERROR ${CLUSTER_USER}@${WORKER_IP} \
        "cd ~/flink-deploy && docker-compose down 2>/dev/null || true"
done
echo "✅ All TaskManagers stopped"
echo ""

# Stop JobManager on controller
echo "Stopping Flink JobManager on controller..."
ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} \
    "cd ~/flink-deploy && docker-compose down 2>/dev/null || true"
echo "✅ JobManager stopped"
echo ""

echo "========================================="
echo "Flink Cluster Teardown Complete"
echo "========================================="
echo ""
echo "Note: Kafka infrastructure remains running for faster system switching."
echo "Note: Flink Docker image remains on nodes for faster restarts."
echo ""
echo "To completely stop Kafka/MinIO:"
echo "  ssh picocluster@192.168.2.70 'cd ~/benchmark_distributed_cluster/deploy/controller && docker compose down'"
echo ""
echo "To remove Flink images from all nodes:"
echo "  for i in {1..9}; do ssh picocluster@192.168.2.7\$i 'docker rmi flink-nexmark:latest'; done"
echo "  ssh picocluster@192.168.2.70 'docker rmi flink-nexmark:latest'"
echo ""
