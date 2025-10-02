#!/bin/bash
# Arroyo-specific metrics collection

# Note: NOT using set -e to see all errors
# set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../cluster-env.sh"
source "$SCRIPT_DIR/common.sh"

echo "=== measure-arroyo.sh started ===" >&2

# Usage: measure-arroyo.sh <pipeline_id> <output_topic> [steady_state_wait] [sample_duration] [num_samples]
PIPELINE_ID=$1
OUTPUT_TOPIC=$2
STEADY_STATE_WAIT=${3:-30}  # Default: wait 30s for steady state
SAMPLE_DURATION=${4:-10}     # Default: sample for 10s each
NUM_SAMPLES=${5:-10}         # Default: collect 10 samples

if [ -z "$PIPELINE_ID" ] || [ -z "$OUTPUT_TOPIC" ]; then
    echo "Usage: $0 <pipeline_id> <output_topic> [steady_state_wait] [sample_duration] [num_samples]"
    exit 1
fi

KAFKA_BROKER="localhost:19092"  # Internal broker address (from inside kafka container)

# Function to get job status
get_job_status() {
    curl -s "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/${PIPELINE_ID}/jobs"
}

# Function to extract job state
get_job_state() {
    local job_data=$(get_job_status)
    echo "$job_data" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p' | head -1
}

# Check if pipeline job is running
echo "Checking pipeline status..." >&2
JOB_DATA=$(get_job_status)
echo "Job API response: $JOB_DATA" >&2
JOB_STATE=$(echo "$JOB_DATA" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p' | head -1)
echo "Extracted job state: '$JOB_STATE'" >&2

if [ "$JOB_STATE" != "Running" ]; then
    echo "ERROR: Pipeline job is not running (state: $JOB_STATE)" >&2
    echo "0"
    exit 1
fi

echo "✓ Job is running" >&2

# Wait for steady state
if [ "$STEADY_STATE_WAIT" -gt 0 ]; then
    echo "Waiting ${STEADY_STATE_WAIT}s for steady state..." >&2
    sleep "$STEADY_STATE_WAIT"
fi

# Wait for output topic to exist (retry up to 60 seconds)
echo "Waiting for output topic: $OUTPUT_TOPIC" >&2
echo "Using Kafka broker: $KAFKA_BROKER" >&2
WAIT_COUNT=0
MAX_WAIT=60
while ! kafka_topic_exists "$KAFKA_BROKER" "$OUTPUT_TOPIC"; do
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        echo "ERROR: Output topic '$OUTPUT_TOPIC' did not appear after ${MAX_WAIT}s" >&2
        echo "Listing all topics:" >&2
        ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "docker exec kafka kafka-topics --bootstrap-server $KAFKA_BROKER --list 2>/dev/null" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law\|exact distribution" >&2
        exit 1
    fi
    echo "  Topic not ready yet, waiting... (${WAIT_COUNT}/${MAX_WAIT}s)" >&2
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
done
echo "✓ Output topic exists" >&2

# Collect multiple throughput samples
echo "Collecting $NUM_SAMPLES samples (${SAMPLE_DURATION}s each)..." >&2
SAMPLES=()
SAMPLE_TIMESTAMPS=()

for i in $(seq 1 $NUM_SAMPLES); do
    echo "  Sample $i/$NUM_SAMPLES..." >&2

    SAMPLE_START=$(date +%s)
    echo "    Measuring throughput (${SAMPLE_DURATION}s)..." >&2
    THROUGHPUT=$(measure_topic_throughput "$KAFKA_BROKER" "$OUTPUT_TOPIC" "$SAMPLE_DURATION")
    echo "    Measurement complete" >&2

    SAMPLES+=($THROUGHPUT)
    SAMPLE_TIMESTAMPS+=($SAMPLE_START)

    echo "    → $THROUGHPUT events/sec" >&2
done

echo "All samples collected successfully" >&2

# Calculate statistics
SAMPLES_STR="${SAMPLES[*]}"
AVG_THROUGHPUT=$(calculate_average "$SAMPLES_STR")
MIN_THROUGHPUT=$(calculate_min "$SAMPLES_STR")
MAX_THROUGHPUT=$(calculate_max "$SAMPLES_STR")
STDDEV_THROUGHPUT=$(calculate_stddev "$SAMPLES_STR" "$AVG_THROUGHPUT")

# Get additional job metrics
JOB_DATA=$(get_job_status)
JOB_ID=$(echo "$JOB_DATA" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
TASKS=$(echo "$JOB_DATA" | sed -n 's/.*"tasks":\([0-9]*\).*/\1/p' | head -1)

# Format samples array for JSON
SAMPLES_JSON="["
for i in "${!SAMPLES[@]}"; do
    if [ $i -gt 0 ]; then
        SAMPLES_JSON+=","
    fi
    SAMPLES_JSON+="{\"sample_num\":$((i+1)),\"throughput\":${SAMPLES[$i]},\"timestamp\":${SAMPLE_TIMESTAMPS[$i]}}"
done
SAMPLES_JSON+="]"

# Output JSON with all metrics
cat <<EOF
{
  "pipeline_id": "$PIPELINE_ID",
  "job_id": "$JOB_ID",
  "job_state": "$JOB_STATE",
  "tasks": $TASKS,
  "output_topic": "$OUTPUT_TOPIC",
  "sample_duration_sec": $SAMPLE_DURATION,
  "num_samples": $NUM_SAMPLES,
  "total_measurement_time_sec": $((SAMPLE_DURATION * NUM_SAMPLES)),
  "throughput": {
    "average": $AVG_THROUGHPUT,
    "min": $MIN_THROUGHPUT,
    "max": $MAX_THROUGHPUT,
    "stddev": $STDDEV_THROUGHPUT
  },
  "samples": $SAMPLES_JSON,
  "timestamp": $(date +%s)
}
EOF
