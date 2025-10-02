#!/bin/bash
# Arroyo-specific metrics collection

# Note: NOT using set -e to see all errors
# set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../cluster-env.sh"
source "$SCRIPT_DIR/common.sh"

echo "=== measure-arroyo.sh started ===" >&2

# Usage: measure-arroyo.sh <pipeline_id> <output_topic> <input_topic> [steady_state_wait] [sample_duration] [num_samples]
PIPELINE_ID=$1
OUTPUT_TOPIC=$2
INPUT_TOPIC=$3
STEADY_STATE_WAIT=${4:-30}  # Default: wait 30s for steady state
SAMPLE_DURATION=${5:-10}     # Default: sample for 10s each
NUM_SAMPLES=${6:-10}         # Default: collect 10 samples

if [ -z "$PIPELINE_ID" ] || [ -z "$OUTPUT_TOPIC" ] || [ -z "$INPUT_TOPIC" ]; then
    echo "Usage: $0 <pipeline_id> <output_topic> <input_topic> [steady_state_wait] [sample_duration] [num_samples]"
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

# Collect multiple throughput samples for both input and output
echo "Collecting $NUM_SAMPLES samples (${SAMPLE_DURATION}s each)..." >&2
OUTPUT_SAMPLES=()
INPUT_SAMPLES=()
SAMPLE_TIMESTAMPS=()

for i in $(seq 1 $NUM_SAMPLES); do
    echo "  Sample $i/$NUM_SAMPLES..." >&2

    SAMPLE_START=$(date +%s)
    echo "    Measuring input & output throughput simultaneously (${SAMPLE_DURATION}s)..." >&2

    # Measure both topics in parallel using temp files
    measure_topic_throughput "$KAFKA_BROKER" "$INPUT_TOPIC" "$SAMPLE_DURATION" > /tmp/input_$$.txt &
    INPUT_PID=$!
    measure_topic_throughput "$KAFKA_BROKER" "$OUTPUT_TOPIC" "$SAMPLE_DURATION" > /tmp/output_$$.txt &
    OUTPUT_PID=$!

    # Wait for both to complete
    wait $INPUT_PID
    wait $OUTPUT_PID

    INPUT_THROUGHPUT=$(cat /tmp/input_$$.txt)
    OUTPUT_THROUGHPUT=$(cat /tmp/output_$$.txt)

    echo "    Input: $INPUT_THROUGHPUT events/sec, Output: $OUTPUT_THROUGHPUT events/sec" >&2

    OUTPUT_SAMPLES+=($OUTPUT_THROUGHPUT)
    INPUT_SAMPLES+=($INPUT_THROUGHPUT)
    SAMPLE_TIMESTAMPS+=($SAMPLE_START)
done

echo "All samples collected successfully" >&2

# Calculate statistics for output
OUTPUT_SAMPLES_STR="${OUTPUT_SAMPLES[*]}"
AVG_OUTPUT=$(calculate_average "$OUTPUT_SAMPLES_STR")
MIN_OUTPUT=$(calculate_min "$OUTPUT_SAMPLES_STR")
MAX_OUTPUT=$(calculate_max "$OUTPUT_SAMPLES_STR")
STDDEV_OUTPUT=$(calculate_stddev "$OUTPUT_SAMPLES_STR" "$AVG_OUTPUT")

# Calculate statistics for input
INPUT_SAMPLES_STR="${INPUT_SAMPLES[*]}"
AVG_INPUT=$(calculate_average "$INPUT_SAMPLES_STR")
MIN_INPUT=$(calculate_min "$INPUT_SAMPLES_STR")
MAX_INPUT=$(calculate_max "$INPUT_SAMPLES_STR")
STDDEV_INPUT=$(calculate_stddev "$INPUT_SAMPLES_STR" "$AVG_INPUT")

# Get additional job metrics
JOB_DATA=$(get_job_status)
JOB_ID=$(echo "$JOB_DATA" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
TASKS=$(echo "$JOB_DATA" | sed -n 's/.*"tasks":\([0-9]*\).*/\1/p' | head -1)

# Format samples array for JSON
SAMPLES_JSON="["
for i in "${!OUTPUT_SAMPLES[@]}"; do
    if [ $i -gt 0 ]; then
        SAMPLES_JSON+=","
    fi
    SAMPLES_JSON+="{\"sample_num\":$((i+1)),\"input\":${INPUT_SAMPLES[$i]},\"output\":${OUTPUT_SAMPLES[$i]},\"timestamp\":${SAMPLE_TIMESTAMPS[$i]}}"
done
SAMPLES_JSON+="]"

# Output JSON with all metrics
cat <<EOF
{
  "pipeline_id": "$PIPELINE_ID",
  "job_id": "$JOB_ID",
  "job_state": "$JOB_STATE",
  "tasks": $TASKS,
  "input_topic": "$INPUT_TOPIC",
  "output_topic": "$OUTPUT_TOPIC",
  "sample_duration_sec": $SAMPLE_DURATION,
  "num_samples": $NUM_SAMPLES,
  "total_measurement_time_sec": $((SAMPLE_DURATION * NUM_SAMPLES)),
  "input_throughput": {
    "average": $AVG_INPUT,
    "min": $MIN_INPUT,
    "max": $MAX_INPUT,
    "stddev": $STDDEV_INPUT
  },
  "output_throughput": {
    "average": $AVG_OUTPUT,
    "min": $MIN_OUTPUT,
    "max": $MAX_OUTPUT,
    "stddev": $STDDEV_OUTPUT
  },
  "samples": $SAMPLES_JSON,
  "timestamp": $(date +%s)
}
EOF
