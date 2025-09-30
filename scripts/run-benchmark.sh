#!/bin/bash
# Run distributed benchmark on Arroyo cluster

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# If not running in Docker, re-run this script inside Docker
if [ ! -f /.dockerenv ]; then
    echo "Running benchmark inside Docker container..."
    # Run as root to avoid permission issues with SSH keys
    exec docker run --rm -it \
        --user root \
        -v "$PROJECT_ROOT":/benchmark \
        -v "$HOME/.ssh:/root/.ssh:ro" \
        -e CLUSTER_USER="$USER" \
        --network host \
        -w /benchmark \
        --entrypoint /bin/bash \
        arroyo-pi:latest \
        /benchmark/scripts/run-benchmark.sh "$@"
fi

source "$SCRIPT_DIR/cluster-env.sh"

# Default values
EVENTS_PER_SECOND=50000
TOTAL_EVENTS=10000000
QUERIES="q1,q2,q3,q5,q7,q8"
PARALLELISM=9

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --events-per-second)
            EVENTS_PER_SECOND="$2"
            shift 2
            ;;
        --total-events)
            TOTAL_EVENTS="$2"
            shift 2
            ;;
        --queries)
            QUERIES="$2"
            shift 2
            ;;
        --parallelism)
            PARALLELISM="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--events-per-second N] [--total-events N] [--queries q1,q2,...] [--parallelism N]"
            exit 1
            ;;
    esac
done

# Generate timestamp for log and metrics files
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/benchmark_${TIMESTAMP}.log"
METRICS_FILE="$PROJECT_ROOT/metrics_${TIMESTAMP}.json"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log messages to both console and file
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

# Start logging
{
log "========================================="
log "Running Distributed Benchmark"
log "========================================="
log "Timestamp: $(date)"
log "Events per second: $EVENTS_PER_SECOND"
log "Total events: $TOTAL_EVENTS"
log "Queries: $QUERIES"
log "Parallelism: $PARALLELISM"
log "Log file: $LOG_FILE"
log ""

# Start metrics collector in background using Docker
log "Starting metrics collector..."
ssh ${CLUSTER_USER}@${CONTROLLER_IP} << EOF 2>&1 | tee -a "$LOG_FILE"
docker run -d --rm \
    --name metrics-collector \
    --network host \
    -v ~/benchmark_distributed_cluster/config:/app/config:ro \
    -v ~/benchmark_distributed_cluster:/app/output \
    metrics-collector:latest \
    python collect-metrics.py \
    --config /app/config/cluster-topology.yaml \
    --interval 5 \
    --output /app/output/metrics_${TIMESTAMP}.json
EOF

# Get container ID for cleanup
METRICS_CONTAINER="metrics-collector"
log "Metrics collector started in Docker container"
log "Metrics will be saved to: $METRICS_FILE"

# Track if cleanup has been done
CLEANUP_DONE=false

# Cleanup function to stop all components
cleanup() {
    # Prevent multiple cleanup runs
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true
    
    log ""
    log "Stopping benchmark components..."
    
    # Stop metrics collector
    log "Stopping metrics collector..."
    ssh ${CLUSTER_USER}@${CONTROLLER_IP} "docker stop $METRICS_CONTAINER 2>/dev/null || true" >> "$LOG_FILE" 2>&1
    
    # Stop nexmark generator  
    log "Stopping data generator..."
    ssh ${CLUSTER_USER}@${CONTROLLER_IP} "docker stop nexmark-generator 2>/dev/null || true" >> "$LOG_FILE" 2>&1
    
    log "Cleanup completed"
    log "Metrics saved to: $METRICS_FILE"
    log "Logs saved to: $LOG_FILE"
    exit 0
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Start data generator
log "Starting Nexmark data generator..."
ssh ${CLUSTER_USER}@${CONTROLLER_IP} << EOF 2>&1 | tee -a "$LOG_FILE"
cd ~/benchmark_distributed_cluster
docker run -d --rm \
    --name nexmark-generator \
    --network host \
    -e KAFKA_BROKER=${CONTROLLER_IP}:${KAFKA_PORT} \
    -e EVENTS_PER_SECOND=${EVENTS_PER_SECOND} \
    -e TOTAL_EVENTS=${TOTAL_EVENTS} \
    -v \$(pwd)/nexmark-generator-deterministic.py:/app/generator/nexmark-generator-deterministic.py:ro \
    nexmark-generator:latest
EOF

# Function to submit a query
submit_query() {
    local query_name=$1
    local query_file="$PROJECT_ROOT/queries/nexmark_${query_name}.sql"
    
    if [ ! -f "$query_file" ]; then
        log "❌ Query file not found: $query_file"
        return 1
    fi
    
    log "Submitting query: $query_name"
    
    # Read and modify the query
    local query_content=$(cat "$query_file")
    
    # Update Kafka broker address
    query_content="${query_content//localhost:9092/${CONTROLLER_IP}:${KAFKA_PORT}}"
    query_content="${query_content//bootstrap_servers = 'localhost:9092'/bootstrap_servers = '${CONTROLLER_IP}:${KAFKA_PORT}'}"
    query_content="${query_content//'bootstrap.servers' = 'localhost:9092'/'bootstrap.servers' = '${CONTROLLER_IP}:${KAFKA_PORT}'}"
    
    # Create JSON payload
    local json_payload=$(jq -n \
        --arg name "nexmark_${query_name}_distributed" \
        --arg query "$query_content" \
        --argjson parallelism "$PARALLELISM" \
        '{
            name: $name,
            query: $query,
            parallelism: $parallelism
        }')
    
    # Submit to Arroyo
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines")
    
    local pipeline_id=$(echo "$response" | jq -r '.id // empty')
    
    if [ -z "$pipeline_id" ]; then
        log "❌ Failed to create pipeline for $query_name"
        log "Response: $response"
        # Also save full response to log for debugging
        echo "Full API Response for $query_name:" >> "$LOG_FILE"
        echo "$response" >> "$LOG_FILE"
        return 1
    fi
    
    log "✅ Pipeline created: $pipeline_id"
    return 0
}

# Submit all queries
log ""
log "Submitting queries..."
IFS=',' read -ra QUERY_ARRAY <<< "$QUERIES"
PIPELINE_IDS=()

for query in "${QUERY_ARRAY[@]}"; do
    if submit_query "$query"; then
        PIPELINE_IDS+=("$pipeline_id")
    fi
done

# Give metrics collector time to start
sleep 2

# Monitor execution
log ""
log "Monitoring benchmark execution..."
log "Press Ctrl+C to stop monitoring (benchmark will continue running)"
log "Comprehensive metrics are being collected in: $METRICS_FILE"

# Function to get pipeline metrics
get_metrics() {
    local pipeline_id=$1
    curl -s "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/${pipeline_id}/metrics"
}

# Function to display comprehensive metrics from collector output
display_comprehensive_metrics() {
    # Get latest metrics from remote file
    local latest_metrics=$(ssh ${CLUSTER_USER}@${CONTROLLER_IP} "tail -1 ~/benchmark_distributed_cluster/metrics_${TIMESTAMP}.json 2>/dev/null" | jq -r '. // empty' 2>/dev/null)
    if [ ! -z "$latest_metrics" ]; then
        # Extract worker count
        local worker_count=$(echo "$latest_metrics" | jq -r '.summary.active_workers // 0')
        log "Active Workers: $worker_count"
    fi
}

# Monitor loop
start_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    log ""
    log "--- Metrics at ${elapsed}s ---"
    
    # Display comprehensive metrics from collector
    display_comprehensive_metrics
    
    # Display pipeline-specific metrics
    total_events=0
    total_rate=0
    
    for pid in "${PIPELINE_IDS[@]}"; do
        metrics=$(get_metrics "$pid")
        if [ ! -z "$metrics" ]; then
            events=$(echo "$metrics" | jq -r '.events_processed // 0')
            rate=$(echo "$metrics" | jq -r '.events_per_second // 0')
            log "Pipeline $pid: $events events, $rate events/sec"
            total_events=$((total_events + events))
            total_rate=$(echo "$total_rate + $rate" | bc)
        fi
    done
    
    if [ ${#PIPELINE_IDS[@]} -gt 1 ]; then
        log "---"
        log "Total: $total_events events, $total_rate events/sec"
    fi
    
    sleep 5
done

} 2>&1  # End of logging block - this ensures all output is captured