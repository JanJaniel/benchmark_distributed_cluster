#!/bin/bash
# Cluster environment configuration

# Controller node (b1pc10)
CONTROLLER_IP="192.168.2.70"
CONTROLLER_HOST="b1pc10"

# Worker nodes (b1pc11-b1pc19)
WORKER_BASE_IP="192.168.2"
WORKER_START_OCTET=71

# Number of workers
NUM_WORKERS=9

# Default user
CLUSTER_USER="jan"

# Service ports
KAFKA_PORT=9094
ARROYO_WEB_PORT=8000
ARROYO_API_PORT=8001
ARROYO_GRPC_PORT=9190
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001

# Helper function to get worker IP
get_worker_ip() {
    local worker_num=$1
    echo "${WORKER_BASE_IP}.$((WORKER_START_OCTET + worker_num - 1))"
}

# Helper function to get worker hostname
get_worker_host() {
    local worker_num=$1
    echo "b1pc$((worker_num + 10))"
}

# Helper function to execute command on all workers
exec_on_workers() {
    local cmd=$1
    for i in $(seq 1 $NUM_WORKERS); do
        local ip=$(get_worker_ip $i)
        local host=$(get_worker_host $i)
        echo "Executing on $host ($ip): $cmd"
        ssh ${CLUSTER_USER}@${ip} "$cmd"
    done
}

# Helper function to execute command on all nodes (controller + workers)
exec_on_all() {
    local cmd=$1
    echo "Executing on controller ($CONTROLLER_IP): $cmd"
    ssh ${CLUSTER_USER}@${CONTROLLER_IP} "$cmd"
    exec_on_workers "$cmd"
}