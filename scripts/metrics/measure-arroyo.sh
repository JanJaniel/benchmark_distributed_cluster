#!/bin/bash
# Arroyo-specific metrics collection

# Note: NOT using set -e to see all errors
# set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../cluster-env.sh"
source "$SCRIPT_DIR/common.sh"

echo "=== measure-arroyo.sh started ===" >&2
echo "Script location: $0" >&2
echo "Working directory: $(pwd)" >&2
echo "Parameters received:" >&2
echo "  PIPELINE_ID: $1" >&2
echo "  OUTPUT_TOPIC: $2" >&2
echo "  INPUT_TOPICS: $3" >&2
echo "  STEADY_STATE_WAIT: $4" >&2
echo "  SAMPLE_INTERVAL: $5" >&2
echo "  MEASUREMENT_DURATION: $6" >&2

# Usage: measure-arroyo.sh <pipeline_id> <output_topic> <input_topics_csv> [steady_state_wait] [sample_interval] [measurement_duration]
PIPELINE_ID=$1
OUTPUT_TOPIC=$2
INPUT_TOPICS_CSV=$3  # Can be single topic or comma-separated list
STEADY_STATE_WAIT=${4:-30}      # Default: wait 30s for steady state
SAMPLE_INTERVAL=${5:-10}        # Default: sample every 10s
MEASUREMENT_DURATION=${6:-120}  # Default: measure for 120s total

if [ -z "$PIPELINE_ID" ] || [ -z "$OUTPUT_TOPIC" ] || [ -z "$INPUT_TOPICS_CSV" ]; then
    echo "Usage: $0 <pipeline_id> <output_topic> <input_topics_csv> [steady_state_wait] [sample_interval] [measurement_duration]"
    exit 1
fi

# Convert comma-separated topics to array
IFS=',' read -ra INPUT_TOPICS <<< "$INPUT_TOPICS_CSV"

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

# Wait for pipeline job to start running
echo "Waiting for pipeline job to start..." >&2
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    JOB_DATA=$(get_job_status)
    JOB_STATE=$(echo "$JOB_DATA" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p' | head -1)

    if [ "$JOB_STATE" = "Running" ]; then
        echo "✓ Job is running" >&2
        break
    elif [ "$JOB_STATE" = "Failed" ]; then
        echo "ERROR: Pipeline job failed to start (state: $JOB_STATE)" >&2
        exit 1
    fi

    echo "  Job state: $JOB_STATE, waiting... (${WAIT_COUNT}s/${MAX_WAIT}s)" >&2
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ "$JOB_STATE" != "Running" ]; then
    echo "ERROR: Pipeline job did not start within ${MAX_WAIT}s (state: $JOB_STATE)" >&2
    exit 1
fi

# Wait for steady state
if [ "$STEADY_STATE_WAIT" -gt 0 ]; then
    echo "Waiting ${STEADY_STATE_WAIT}s for steady state..." >&2
    sleep "$STEADY_STATE_WAIT"
fi

# Capture start CPU time across all worker nodes
echo "Capturing initial CPU metrics..." >&2
START_TIME=$(date +%s)
TOTAL_CPU_START=0
for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    # Get CPU time in seconds from /proc/stat (sum of user + system time across all cores)
    CPU_TIME=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${WORKER_IP} "awk '/^cpu / {print (\$2+\$3+\$4)/100}' /proc/stat" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law\|exact distribution" || echo "0")
    TOTAL_CPU_START=$(awk "BEGIN {print $TOTAL_CPU_START + $CPU_TIME}")
done

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

# Collect throughput samples continuously for the measurement duration
echo "Collecting samples every ${SAMPLE_INTERVAL}s for ${MEASUREMENT_DURATION}s..." >&2
OUTPUT_SAMPLES=()
INPUT_SAMPLES=()
SAMPLE_TIMESTAMPS=()

MEASUREMENT_START=$(date +%s)
MEASUREMENT_END=$((MEASUREMENT_START + MEASUREMENT_DURATION))
SAMPLE_COUNT=0

while [ $(date +%s) -lt $MEASUREMENT_END ]; do
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    SAMPLE_START=$(date +%s)
    REMAINING=$((MEASUREMENT_END - SAMPLE_START))

    echo "  Sample $SAMPLE_COUNT (${REMAINING}s remaining)..." >&2

    # Measure all input topics in parallel
    if [ ${#INPUT_TOPICS[@]} -eq 1 ]; then
        echo "    Measuring input & output throughput simultaneously (${SAMPLE_INTERVAL}s)..." >&2
    else
        echo "    Measuring ${#INPUT_TOPICS[@]} input topics & output simultaneously (${SAMPLE_INTERVAL}s)..." >&2
    fi

    # Start measuring all input topics in parallel
    INPUT_PIDS=()
    for idx in "${!INPUT_TOPICS[@]}"; do
        TOPIC="${INPUT_TOPICS[$idx]}"
        measure_topic_throughput "$KAFKA_BROKER" "$TOPIC" "$SAMPLE_INTERVAL" > /tmp/input_${idx}_$$.txt &
        INPUT_PIDS+=($!)
    done

    # Start measuring output topic
    measure_topic_throughput "$KAFKA_BROKER" "$OUTPUT_TOPIC" "$SAMPLE_INTERVAL" > /tmp/output_$$.txt &
    OUTPUT_PID=$!

    # Wait for all to complete
    for pid in "${INPUT_PIDS[@]}"; do
        wait $pid
    done
    wait $OUTPUT_PID

    # Sum up all input topics
    TOTAL_INPUT=0
    for idx in "${!INPUT_TOPICS[@]}"; do
        TOPIC_THROUGHPUT=$(cat /tmp/input_${idx}_$$.txt)
        TOTAL_INPUT=$((TOTAL_INPUT + TOPIC_THROUGHPUT))
    done

    OUTPUT_THROUGHPUT=$(cat /tmp/output_$$.txt)

    echo "    Input: $TOTAL_INPUT events/sec (total), Output: $OUTPUT_THROUGHPUT events/sec" >&2

    OUTPUT_SAMPLES+=($OUTPUT_THROUGHPUT)
    INPUT_SAMPLES+=($TOTAL_INPUT)
    SAMPLE_TIMESTAMPS+=($SAMPLE_START)
done

NUM_SAMPLES=${#OUTPUT_SAMPLES[@]}

echo "All samples collected successfully" >&2

# Capture end CPU time across all worker nodes
echo "Capturing final CPU metrics..." >&2
END_TIME=$(date +%s)
TOTAL_CPU_END=0
for i in $(seq 1 $NUM_WORKERS); do
    WORKER_IP=$(get_worker_ip $i)
    CPU_TIME=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${WORKER_IP} "awk '/^cpu / {print (\$2+\$3+\$4)/100}' /proc/stat" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law\|exact distribution" || echo "0")
    TOTAL_CPU_END=$(awk "BEGIN {print $TOTAL_CPU_END + $CPU_TIME}")
done

# Calculate CPU metrics
ELAPSED_TIME=$((END_TIME - START_TIME))
CPU_TIME_USED=$(awk "BEGIN {print $TOTAL_CPU_END - $TOTAL_CPU_START}")
# Core-seconds = CPU time used across all nodes
CORE_SECONDS=$(awk "BEGIN {printf \"%.0f\", $CPU_TIME_USED}")

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

# Build input topics JSON array
INPUT_TOPICS_JSON="["
for idx in "${!INPUT_TOPICS[@]}"; do
    if [ $idx -gt 0 ]; then
        INPUT_TOPICS_JSON+=","
    fi
    INPUT_TOPICS_JSON+="\"${INPUT_TOPICS[$idx]}\""
done
INPUT_TOPICS_JSON+="]"

# Output JSON with all metrics
cat <<EOF
{
  "pipeline_id": "$PIPELINE_ID",
  "job_id": "$JOB_ID",
  "job_state": "$JOB_STATE",
  "tasks": $TASKS,
  "input_topics": $INPUT_TOPICS_JSON,
  "output_topic": "$OUTPUT_TOPIC",
  "sample_interval_sec": $SAMPLE_INTERVAL,
  "measurement_duration_sec": $MEASUREMENT_DURATION,
  "num_samples": $NUM_SAMPLES,
  "cpu_metrics": {
    "core_seconds": $CORE_SECONDS,
    "elapsed_time_sec": $ELAPSED_TIME,
    "worker_nodes": $NUM_WORKERS
  },
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
