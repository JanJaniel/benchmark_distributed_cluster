#!/bin/bash
# Run distributed benchmark on Arroyo cluster

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# If not running in Docker, re-run this script inside a container with SSH client
if [ ! -f /.dockerenv ]; then
    echo "Running benchmark orchestration script..."
    # Use debian:bullseye-slim which has bash, curl, ssh, jq
    exec docker run --rm -i \
        --user root \
        -v "$PROJECT_ROOT":/benchmark \
        -v "$HOME/.ssh:/root/.ssh:ro" \
        -e CLUSTER_USER="$USER" \
        --network host \
        -w /benchmark/scripts \
        --entrypoint /bin/bash \
        debian:bullseye-slim \
        -c "apt-get update -qq && apt-get install -y -qq curl jq openssh-client > /dev/null 2>&1 && /benchmark/scripts/run-benchmark.sh \"\$@\"" -- "$@"
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

# Cleanup old containers and pipelines before starting
log "========================================="
log "Pre-flight Cleanup"
log "========================================="
log "Stopping old containers..."

# Stop and remove old containers
ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} << 'EOF' 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law" | tee -a "$LOG_FILE"
docker stop metrics-collector 2>/dev/null || true
docker rm metrics-collector 2>/dev/null || true
docker stop nexmark-generator 2>/dev/null || true
docker rm nexmark-generator 2>/dev/null || true
EOF

log "✅ Old containers cleaned up"

# Delete old pipelines
log "Cleaning up old pipelines..."
PIPELINE_COUNT=$(curl -s http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines | grep -o '"id"' | wc -l)
if [ "$PIPELINE_COUNT" -gt 0 ]; then
    log "Found $PIPELINE_COUNT old pipeline(s), deleting..."
    PIPELINE_IDS=$(curl -s http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines | grep -oP '"id":"[^"]*"' | cut -d'"' -f4)
    for pid in $PIPELINE_IDS; do
        # First stop the pipeline's job
        JOB_ID=$(curl -s "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/$pid/jobs" | grep -oP '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ -n "$JOB_ID" ]; then
            log "  Stopping job $JOB_ID for pipeline: $pid"
            # Use pipeline-level stop endpoint (correct Arroyo API)
            STOP_RESPONSE=$(curl -s -X PATCH "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/$pid" \
                -H "Content-Type: application/json" \
                -d '{"stop": "immediate"}')
            # Show response if there's an error
            if echo "$STOP_RESPONSE" | grep -qi "error"; then
                log "    ⚠ Stop response: $STOP_RESPONSE"
            fi

            # Wait for job to reach terminal state
            for i in {1..10}; do
                JOB_STATE=$(curl -s "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/$pid/jobs" | grep -oP '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
                log "    Current state: $JOB_STATE (attempt $i/10)"
                if [ "$JOB_STATE" = "Stopped" ] || [ "$JOB_STATE" = "Failed" ] || [ "$JOB_STATE" = "Finished" ]; then
                    log "    ✓ Job reached terminal state: $JOB_STATE"
                    break
                fi
                sleep 1
            done

            # Show final state before delete attempt
            if [ "$JOB_STATE" != "Stopped" ] && [ "$JOB_STATE" != "Failed" ] && [ "$JOB_STATE" != "Finished" ]; then
                log "    ⚠ Job still in state: $JOB_STATE after 10s wait"
            fi
        fi

        # Now delete the pipeline
        log "  Deleting pipeline: $pid"
        DELETE_RESPONSE=$(curl -s -X DELETE "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/$pid")
        if echo "$DELETE_RESPONSE" | grep -qi "error"; then
            log "    ⚠ Delete failed: $DELETE_RESPONSE"
        fi
    done
    log "✅ Old pipelines deleted"
else
    log "✅ No old pipelines to clean up"
fi

log ""
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
ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} << EOF 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law" | tee -a "$LOG_FILE"
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

    echo ""
    echo "Stopping benchmark components..."

    # Stop metrics collector
    echo "Stopping metrics collector..."
    ssh ${CLUSTER_USER}@${CONTROLLER_IP} "docker stop metrics-collector 2>/dev/null || true" >/dev/null 2>&1

    # Stop nexmark generator
    echo "Stopping data generator..."
    ssh ${CLUSTER_USER}@${CONTROLLER_IP} "docker stop nexmark-generator 2>/dev/null || true" >/dev/null 2>&1

    echo "✅ Cleanup completed"
    echo "Metrics saved to: $METRICS_FILE"
    echo "Logs saved to: $LOG_FILE"

    # Kill background monitoring loop if running
    jobs -p | xargs -r kill 2>/dev/null

    exit 0
}

# Set trap to cleanup on exit - use SIGINT for Ctrl+C
trap 'cleanup; exit 130' INT
trap 'cleanup' EXIT TERM

# Start data generator
log "Starting Nexmark data generator..."
GENERATOR_CONTAINER_ID=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} << EOF 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law"
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
)

if [ -n "$GENERATOR_CONTAINER_ID" ]; then
    log "✅ Nexmark generator started (Container ID: ${GENERATOR_CONTAINER_ID:0:12})"
    log "   Generating $EVENTS_PER_SECOND events/sec, $TOTAL_EVENTS total events"

    # Start background monitoring of generator
    (
        sleep 5  # Wait for generator to start
        while ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "docker ps | grep -q nexmark-generator" 2>/dev/null; do
            LAST_LINE=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "docker logs nexmark-generator 2>&1 | tail -1" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi")
            if echo "$LAST_LINE" | grep -q "events/sec"; then
                echo "[Generator] $LAST_LINE" | tee -a "$LOG_FILE"
            fi
            sleep 10
        done
    ) &
    MONITOR_PID=$!
else
    log "❌ Failed to start Nexmark generator"
    exit 1
fi
log ""

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

    # Export pipeline_id so it's accessible outside the function (not local!)
    pipeline_id=$(echo "$response" | jq -r '.id // empty')

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

# Measure throughput for each pipeline
log ""
log "========================================="
log "Measuring Throughput"
log "========================================="

# Array to store all metrics for summary
ALL_METRICS=()

for pid in "${PIPELINE_IDS[@]}"; do
    # Determine output topic from query name
    # For now, hardcoded for q1, will need to be extracted from query
    OUTPUT_TOPIC="nexmark-q1-results"

    log "Pipeline: $pid"
    log "Output Topic: $OUTPUT_TOPIC"
    log ""

    # Run Arroyo metrics measurement with multiple samples
    # Parameters: pipeline_id, output_topic, steady_state_wait, sample_duration, num_samples
    log "Running measurement script..."
    log "  Parameters: pid=$pid, topic=$OUTPUT_TOPIC, steady_state=30s, sample=10s, samples=10"

    # Test reading the script
    log "  First 5 lines of script:"
    head -5 ${SCRIPT_DIR}/metrics/measure-arroyo.sh | while IFS= read -r line; do
        log "    $line"
    done

    # Test SSH connectivity
    log "  Testing SSH to controller..."
    SSH_TEST=$(ssh -o LogLevel=ERROR -o ConnectTimeout=5 ${CLUSTER_USER}@${CONTROLLER_IP} "echo 'SSH works'" 2>&1)
    SSH_EXIT=$?
    log "  SSH test exit code: $SSH_EXIT"
    log "  SSH test output: $SSH_TEST"

    # Test if we can reach the API
    log "  Testing API connectivity..."
    API_TEST=$(curl -s --connect-timeout 5 "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/${pid}/jobs" 2>&1 | head -c 100)
    log "  API response (first 100 chars): $API_TEST"

    # Try running the script with bash explicitly and capture everything
    # Note: Script needs 30s steady state + 10 samples * 10s = 130s minimum
    log "  Calling measure-arroyo.sh (this will take ~2-3 minutes)..."
    bash ${SCRIPT_DIR}/metrics/measure-arroyo.sh "$pid" "$OUTPUT_TOPIC" 30 10 10 > /tmp/metrics_output.txt 2>&1 &
    SCRIPT_PID=$!
    log "  Script running with PID: $SCRIPT_PID, waiting for completion..."

    # Wait for script to complete (no timeout - let it run)
    wait $SCRIPT_PID 2>/dev/null
    MEASURE_EXIT_CODE=$?
    METRICS_JSON=$(cat /tmp/metrics_output.txt 2>/dev/null || echo "")
    log "  Script completed with exit code: $MEASURE_EXIT_CODE"
    log "  Output length: ${#METRICS_JSON} characters"

    # Show first 500 chars of output for debugging
    if [ ${#METRICS_JSON} -gt 0 ]; then
        log "  First 500 chars of output:"
        echo "$METRICS_JSON" | head -c 500 | while IFS= read -r line; do
            log "    $line"
        done
    fi

    log "Measurement script completed with exit code: $MEASURE_EXIT_CODE"

    if [ $MEASURE_EXIT_CODE -ne 0 ]; then
        log "❌ Measurement script failed"
    fi

    # Show all output from measurement script
    log "Measurement output:"
    echo "$METRICS_JSON" | while IFS= read -r line; do
        log "  $line"
    done

    # Stop the pipeline after measurement
    log "Stopping pipeline $pid..."
    curl -s -X PATCH "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/$pid" \
        -H "Content-Type: application/json" \
        -d '{"stop": "immediate"}' >/dev/null
    log "✅ Pipeline stop requested"

    # Extract and display metrics
    AVG_THROUGHPUT=$(echo "$METRICS_JSON" | grep '"average"' | sed -n 's/.*: \([0-9]*\).*/\1/p')
    MIN_THROUGHPUT=$(echo "$METRICS_JSON" | grep '"min"' | sed -n 's/.*: \([0-9]*\).*/\1/p')
    MAX_THROUGHPUT=$(echo "$METRICS_JSON" | grep '"max"' | sed -n 's/.*: \([0-9]*\).*/\1/p')
    STDDEV=$(echo "$METRICS_JSON" | grep '"stddev"' | sed -n 's/.*: \([0-9]*\).*/\1/p')
    JOB_ID=$(echo "$METRICS_JSON" | grep '"job_id"' | sed -n 's/.*: "\([^"]*\)".*/\1/p')
    JOB_STATE=$(echo "$METRICS_JSON" | grep '"job_state"' | sed -n 's/.*: "\([^"]*\)".*/\1/p')
    TASKS=$(echo "$METRICS_JSON" | grep '"tasks"' | sed -n 's/.*: \([0-9]*\).*/\1/p')
    NUM_SAMPLES=$(echo "$METRICS_JSON" | grep '"num_samples"' | sed -n 's/.*: \([0-9]*\).*/\1/p')

    log "========================================="
    log "Results for Pipeline $pid"
    log "========================================="
    log ""
    log "Job Information:"
    log "  Job ID: $JOB_ID"
    log "  Job State: $JOB_STATE"
    log "  Tasks: $TASKS"
    log ""
    log "Throughput Statistics ($NUM_SAMPLES samples):"
    log "  Average: $AVG_THROUGHPUT events/sec"
    log "  Minimum: $MIN_THROUGHPUT events/sec"
    log "  Maximum: $MAX_THROUGHPUT events/sec"
    log "  Std Dev: ±$STDDEV events/sec"
    log ""
    log "Full metrics JSON:"
    PIPELINE_METRICS=$(echo "$METRICS_JSON" | grep '^{')
    echo "$PIPELINE_METRICS" | tee -a "$LOG_FILE"

    # Store metrics for summary
    ALL_METRICS+=("$PIPELINE_METRICS")

    log ""
done

log "========================================="
log "Benchmark Complete"
log "========================================="

# Create summary results file
SUMMARY_FILE="$PROJECT_ROOT/benchmark_results_$(date +%Y%m%d_%H%M%S).json"

# Build summary with query results
{
    echo "{"
    echo "  \"benchmark_info\": {"
    echo "    \"timestamp\": \"$(date -Iseconds)\","
    echo "    \"events_per_second\": $EVENTS_PER_SECOND,"
    echo "    \"total_events\": $TOTAL_EVENTS,"
    echo "    \"parallelism\": $PARALLELISM"
    echo "  },"
    echo "  \"queries\": ["

    # Add each query result
    for i in "${!ALL_METRICS[@]}"; do
        echo "    ${ALL_METRICS[$i]}"
        # Add comma if not last element
        if [ $i -lt $((${#ALL_METRICS[@]} - 1)) ]; then
            echo ","
        fi
    done

    echo "  ]"
    echo "}"
} > "$SUMMARY_FILE"

log "Summary saved to: $SUMMARY_FILE"
log "Logs saved to: $LOG_FILE"

# Exit successfully - cleanup will be called by trap
exit 0

} 2>&1  # End of main logging block