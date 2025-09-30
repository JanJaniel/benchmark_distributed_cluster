#!/bin/bash
# Run distributed benchmark on Arroyo cluster

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
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

echo "========================================="
echo "Running Distributed Benchmark"
echo "========================================="
echo "Events per second: $EVENTS_PER_SECOND"
echo "Total events: $TOTAL_EVENTS"
echo "Queries: $QUERIES"
echo "Parallelism: $PARALLELISM"
echo ""

# Check cluster health
echo "Checking cluster health..."
if ! curl -f http://$CONTROLLER_IP:$ARROYO_WEB_PORT/health >/dev/null 2>&1; then
    echo "❌ Arroyo controller is not healthy"
    exit 1
fi

# Start data generator
echo "Starting Nexmark data generator..."
ssh ${CLUSTER_USER}@${CONTROLLER_IP} << EOF
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
        echo "❌ Query file not found: $query_file"
        return 1
    fi
    
    echo "Submitting query: $query_name"
    
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
        echo "❌ Failed to create pipeline for $query_name"
        echo "Response: $response"
        return 1
    fi
    
    echo "✅ Pipeline created: $pipeline_id"
    return 0
}

# Submit all queries
echo -e "\nSubmitting queries..."
IFS=',' read -ra QUERY_ARRAY <<< "$QUERIES"
PIPELINE_IDS=()

for query in "${QUERY_ARRAY[@]}"; do
    if submit_query "$query"; then
        PIPELINE_IDS+=("$pipeline_id")
    fi
done

# Monitor execution
echo -e "\nMonitoring benchmark execution..."
echo "Press Ctrl+C to stop monitoring (benchmark will continue running)"

# Function to get pipeline metrics
get_metrics() {
    local pipeline_id=$1
    curl -s "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/${pipeline_id}/metrics"
}

# Monitor loop
start_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    echo -e "\n--- Metrics at ${elapsed}s ---"
    
    for pid in "${PIPELINE_IDS[@]}"; do
        metrics=$(get_metrics "$pid")
        if [ ! -z "$metrics" ]; then
            events=$(echo "$metrics" | jq -r '.events_processed // 0')
            rate=$(echo "$metrics" | jq -r '.events_per_second // 0')
            echo "Pipeline $pid: $events events, $rate events/sec"
        fi
    done
    
    sleep 5
done