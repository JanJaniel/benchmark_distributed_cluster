#!/bin/bash
# Flink-specific metrics collection

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/../cluster-env.sh"
source "$SCRIPT_DIR/common.sh"

echo "=== measure-flink.sh started ===" >&2
echo "Script location: $0" >&2
echo "Working directory: $(pwd)" >&2
echo "Parameters received:" >&2
echo "  QUERY: $1" >&2
echo "  INPUT_TOPICS: $2" >&2
echo "  OUTPUT_TOPIC: $3" >&2
echo "  STEADY_STATE_WAIT: $4" >&2
echo "  SAMPLE_INTERVAL: $5" >&2
echo "  MEASUREMENT_DURATION: $6" >&2

# Usage: measure-flink.sh <query> <input_topics_csv> <output_topic> [steady_state_wait] [sample_interval] [measurement_duration]
QUERY=$1
INPUT_TOPICS_CSV=$2
OUTPUT_TOPIC=$3
STEADY_STATE_WAIT=${4:-30}
SAMPLE_INTERVAL=${5:-10}
MEASUREMENT_DURATION=${6:-120}

if [ -z "$QUERY" ] || [ -z "$INPUT_TOPICS_CSV" ] || [ -z "$OUTPUT_TOPIC" ]; then
    echo "Usage: $0 <query> <input_topics_csv> <output_topic> [steady_state_wait] [sample_interval] [measurement_duration]"
    exit 1
fi

# Convert comma-separated topics to array
IFS=',' read -ra INPUT_TOPICS <<< "$INPUT_TOPICS_CSV"

KAFKA_BROKER="localhost:19092"
FLINK_API="http://${CONTROLLER_IP}:8081"

# Determine query class name
case $QUERY in
    q1|q2|q3|q4)
        QUERY_CLASS="nexmark.queries.NexmarkQ${QUERY#q}SQL"
        ;;
    q5|q7|q8)
        QUERY_CLASS="nexmark.queries.NexmarkQ${QUERY#q}"
        ;;
    *)
        echo "ERROR: Invalid query: $QUERY" >&2
        exit 1
        ;;
esac

# Submit Flink job
echo "Submitting Flink job for $QUERY..." >&2
echo "  Query class: $QUERY_CLASS" >&2

JOB_OUTPUT=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} \
    "docker exec flink-jobmanager flink run -d -c $QUERY_CLASS /opt/flink/usrlib/nexmark.jar" 2>&1)

# Extract job ID
JOB_ID=$(echo "$JOB_OUTPUT" | grep -oP 'Job has been submitted with JobID \K[a-f0-9]+' | head -1)

if [ -z "$JOB_ID" ]; then
    echo "ERROR: Failed to submit Flink job" >&2
    echo "Output: $JOB_OUTPUT" >&2
    exit 1
fi

echo "✓ Job submitted with ID: $JOB_ID" >&2

# Wait for job to start running
echo "Waiting for job to start running..." >&2
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    JOB_STATUS=$(curl -s "$FLINK_API/jobs/$JOB_ID" | grep -oP '"state":"\K[^"]+' | head -1)

    if [ "$JOB_STATUS" = "RUNNING" ]; then
        echo "✓ Job is running" >&2
        break
    elif [ "$JOB_STATUS" = "FAILED" ] || [ "$JOB_STATUS" = "CANCELED" ]; then
        echo "ERROR: Job failed to start (state: $JOB_STATUS)" >&2
        exit 1
    fi

    echo "  Job state: $JOB_STATUS, waiting... (${WAIT_COUNT}s/${MAX_WAIT}s)" >&2
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ "$JOB_STATUS" != "RUNNING" ]; then
    echo "ERROR: Job did not start within ${MAX_WAIT}s (state: $JOB_STATUS)" >&2
    exit 1
fi

# Wait for steady state
if [ "$STEADY_STATE_WAIT" -gt 0 ]; then
    echo "Waiting ${STEADY_STATE_WAIT}s for steady state..." >&2
    sleep "$STEADY_STATE_WAIT"
fi

# Start continuous CPU sampling in background
echo "Starting continuous CPU sampling (every 5s during measurement)..." >&2
START_TIME=$(date +%s)
CPU_SAMPLE_INTERVAL=5

# First, check what containers exist on one worker
WORKER_IP=$(get_worker_ip 1)
echo "  DEBUG: Checking Docker containers on worker 1 ($WORKER_IP)..." >&2
CONTAINERS=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${WORKER_IP} "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law\|exact distribution" || echo "none")
echo "$CONTAINERS" >&2

# Background function to continuously sample CPU
CPU_SAMPLES_FILE="/tmp/cpu_samples_$$.txt"
rm -f "$CPU_SAMPLES_FILE"

(
    # Sample CPU every CPU_SAMPLE_INTERVAL seconds for the duration of measurement
    END_SAMPLE_TIME=$((START_TIME + MEASUREMENT_DURATION))
    while [ $(date +%s) -lt $END_SAMPLE_TIME ]; do
        TOTAL_CPU=0
        for i in $(seq 1 $NUM_WORKERS); do
            WORKER_IP=$(get_worker_ip $i)
            CPU_PCT=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${WORKER_IP} "docker stats --no-stream --format '{{.CPUPerc}}' flink-worker-${i} 2>/dev/null | sed 's/%//'" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law\|exact distribution" || echo "0")
            if [ -z "$CPU_PCT" ] || ! [[ "$CPU_PCT" =~ ^[0-9.]+$ ]]; then
                CPU_PCT=0
            fi
            TOTAL_CPU=$(awk "BEGIN {print $TOTAL_CPU + $CPU_PCT}")
        done
        echo "$TOTAL_CPU" >> "$CPU_SAMPLES_FILE"
        sleep $CPU_SAMPLE_INTERVAL
    done
) &
CPU_SAMPLER_PID=$!

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
        # Cancel the job
        ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "docker exec flink-jobmanager flink cancel $JOB_ID" >/dev/null 2>&1
        exit 1
    fi
    echo "  Topic not ready yet, waiting... (${WAIT_COUNT}/${MAX_WAIT}s)" >&2
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
done
echo "✓ Output topic exists" >&2

# Simple measurement: sample once over the entire duration
echo "Measuring throughput over ${MEASUREMENT_DURATION}s..." >&2

MEASUREMENT_START=$(date +%s)

# Measure all input topics in parallel
if [ ${#INPUT_TOPICS[@]} -eq 1 ]; then
    echo "  Measuring input & output simultaneously..." >&2
else
    echo "  Measuring ${#INPUT_TOPICS[@]} input topics & output simultaneously..." >&2
fi

# Start measuring all input topics in parallel
INPUT_PIDS=()
for idx in "${!INPUT_TOPICS[@]}"; do
    TOPIC="${INPUT_TOPICS[$idx]}"
    measure_topic_throughput "$KAFKA_BROKER" "$TOPIC" "$MEASUREMENT_DURATION" > /tmp/input_${idx}_$$.txt &
    INPUT_PIDS+=($!)
done

# Start measuring output topic
measure_topic_throughput "$KAFKA_BROKER" "$OUTPUT_TOPIC" "$MEASUREMENT_DURATION" > /tmp/output_$$.txt &
OUTPUT_PID=$!

# Wait for all to complete
for pid in "${INPUT_PIDS[@]}"; do
    wait $pid
done
wait $OUTPUT_PID

# Sum up all input topics (use awk for float support)
TOTAL_INPUT=0
for idx in "${!INPUT_TOPICS[@]}"; do
    TOPIC_THROUGHPUT=$(cat /tmp/input_${idx}_$$.txt)
    TOTAL_INPUT=$(awk "BEGIN {printf \"%.2f\", $TOTAL_INPUT + $TOPIC_THROUGHPUT}")
done

OUTPUT_THROUGHPUT=$(cat /tmp/output_$$.txt)

echo "  Input: $TOTAL_INPUT events/sec (average over ${MEASUREMENT_DURATION}s)" >&2
echo "  Output: $OUTPUT_THROUGHPUT events/sec (average over ${MEASUREMENT_DURATION}s)" >&2

# Store as single sample
OUTPUT_SAMPLES=($OUTPUT_THROUGHPUT)
INPUT_SAMPLES=($TOTAL_INPUT)
SAMPLE_TIMESTAMPS=($MEASUREMENT_START)
NUM_SAMPLES=1

echo "All samples collected successfully" >&2

# Wait for CPU sampler to finish and calculate average
echo "Processing CPU samples..." >&2
wait $CPU_SAMPLER_PID 2>/dev/null || true
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))

# Calculate average CPU from all samples
if [ -f "$CPU_SAMPLES_FILE" ] && [ -s "$CPU_SAMPLES_FILE" ]; then
    NUM_CPU_SAMPLES=$(wc -l < "$CPU_SAMPLES_FILE")
    TOTAL_CPU_SUM=0
    while read -r cpu_val; do
        TOTAL_CPU_SUM=$(awk "BEGIN {printf \"%.2f\", $TOTAL_CPU_SUM + $cpu_val}")
    done < "$CPU_SAMPLES_FILE"

    AVG_CPU_PCT=$(awk "BEGIN {printf \"%.2f\", $TOTAL_CPU_SUM / $NUM_CPU_SAMPLES}")
    echo "  Collected $NUM_CPU_SAMPLES CPU samples, average CPU %: ${AVG_CPU_PCT}" >&2

    # Clean up
    rm -f "$CPU_SAMPLES_FILE"
else
    echo "  WARNING: No CPU samples collected" >&2
    AVG_CPU_PCT=0
fi

# Calculate CPU metrics
CORE_SECONDS=$(awk "BEGIN {printf \"%.0f\", ($AVG_CPU_PCT * $ELAPSED_TIME) / 100}")

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

# Get job metrics
JOB_DATA=$(curl -s "$FLINK_API/jobs/$JOB_ID")
TASKS=$(echo "$JOB_DATA" | grep -oP '"total":\K[0-9]+' | head -1)
JOB_STATE=$(echo "$JOB_DATA" | grep -oP '"state":"\K[^"]+' | head -1)

# Build input topics JSON array
INPUT_TOPICS_JSON="["
for idx in "${!INPUT_TOPICS[@]}"; do
    if [ $idx -gt 0 ]; then
        INPUT_TOPICS_JSON+=","
    fi
    INPUT_TOPICS_JSON+="\"${INPUT_TOPICS[$idx]}\""
done
INPUT_TOPICS_JSON+="]"

# Cancel the Flink job
echo "Canceling Flink job $JOB_ID..." >&2
ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} \
    "docker exec flink-jobmanager flink cancel $JOB_ID" >/dev/null 2>&1 || true

# Output JSON with all metrics
cat <<EOF
{
  "query": "$QUERY",
  "job_id": "$JOB_ID",
  "job_state": "$JOB_STATE",
  "tasks": ${TASKS:-0},
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
  "input_throughput_events_per_sec": $AVG_INPUT,
  "output_throughput_events_per_sec": $AVG_OUTPUT,
  "timestamp": $(date +%s)
}
EOF
