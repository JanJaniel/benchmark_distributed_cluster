#!/bin/bash
# Arroyo-specific metrics collection

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../cluster-env.sh"
source "$SCRIPT_DIR/common.sh"

# Usage: measure-arroyo.sh <pipeline_id> <output_topic> [steady_state_wait] [sample_duration]
PIPELINE_ID=$1
OUTPUT_TOPIC=$2
STEADY_STATE_WAIT=${3:-30}  # Default: wait 30s for steady state
SAMPLE_DURATION=${4:-10}     # Default: sample for 10s

if [ -z "$PIPELINE_ID" ] || [ -z "$OUTPUT_TOPIC" ]; then
    echo "Usage: $0 <pipeline_id> <output_topic> [steady_state_wait] [sample_duration]"
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
JOB_STATE=$(get_job_state)

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

# Check if output topic exists
echo "Checking output topic: $OUTPUT_TOPIC" >&2
if ! kafka_topic_exists "$KAFKA_BROKER" "$OUTPUT_TOPIC"; then
    echo "WARNING: Output topic '$OUTPUT_TOPIC' does not exist yet" >&2
    echo "0"
    exit 0
fi

# Measure throughput
echo "Measuring throughput (sampling for ${SAMPLE_DURATION}s)..." >&2
THROUGHPUT=$(measure_topic_throughput "$KAFKA_BROKER" "$OUTPUT_TOPIC" "$SAMPLE_DURATION")

# Get additional job metrics
JOB_DATA=$(get_job_status)
JOB_ID=$(echo "$JOB_DATA" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
TASKS=$(echo "$JOB_DATA" | sed -n 's/.*"tasks":\([0-9]*\).*/\1/p' | head -1)

# Output JSON with all metrics
cat <<EOF
{
  "pipeline_id": "$PIPELINE_ID",
  "job_id": "$JOB_ID",
  "job_state": "$JOB_STATE",
  "tasks": $TASKS,
  "output_topic": "$OUTPUT_TOPIC",
  "throughput_events_per_sec": $THROUGHPUT,
  "sample_duration_sec": $SAMPLE_DURATION,
  "timestamp": $(date +%s)
}
EOF
