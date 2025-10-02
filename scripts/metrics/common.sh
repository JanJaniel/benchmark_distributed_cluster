#!/bin/bash
# Common functions for metrics collection across different stream processing engines

# Get total offset (message count) for a Kafka topic
# Usage: get_kafka_topic_offset <broker> <topic>
get_kafka_topic_offset() {
    local broker=$1
    local topic=$2

    ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list $broker \
        --topic $topic 2>/dev/null" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law\|exact distribution" | awk -F: '{sum+=$NF} END {print sum+0}'
}

# Measure throughput by sampling topic offset over time
# Usage: measure_topic_throughput <broker> <topic> <sample_duration_seconds>
measure_topic_throughput() {
    local broker=$1
    local topic=$2
    local duration=${3:-10}

    local before=$(get_kafka_topic_offset "$broker" "$topic")
    echo "    DEBUG: Topic $topic - offset before: $before" >&2
    sleep "$duration"
    local after=$(get_kafka_topic_offset "$broker" "$topic")
    echo "    DEBUG: Topic $topic - offset after: $after" >&2

    local diff=$((after - before))
    local throughput=$((diff / duration))
    echo "    DEBUG: Topic $topic - diff: $diff, throughput: $throughput" >&2

    echo "$throughput"
}

# Check if Kafka topic exists
# Usage: kafka_topic_exists <broker> <topic>
kafka_topic_exists() {
    local broker=$1
    local topic=$2

    local topics=$(ssh -o LogLevel=ERROR ${CLUSTER_USER}@${CONTROLLER_IP} "docker exec kafka kafka-topics \
        --bootstrap-server $broker \
        --list 2>/dev/null" 2>&1 | grep -v "^Linux\|^Debian\|programs included\|Wi-Fi is currently\|The programs\|ABSOLUTELY NO WARRANTY\|permitted by law\|exact distribution")

    echo "$topics" | grep -q "^${topic}$"
    return $?
}

# Calculate average from array of numbers
# Usage: calculate_average "sample1 sample2 sample3 ..."
calculate_average() {
    local samples="$1"
    local count=0
    local sum=0

    for val in $samples; do
        sum=$((sum + val))
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo "0"
    else
        echo $((sum / count))
    fi
}

# Calculate minimum from array of numbers
# Usage: calculate_min "sample1 sample2 sample3 ..."
calculate_min() {
    local samples="$1"
    local min=""

    for val in $samples; do
        if [ -z "$min" ] || [ $val -lt $min ]; then
            min=$val
        fi
    done

    echo "${min:-0}"
}

# Calculate maximum from array of numbers
# Usage: calculate_max "sample1 sample2 sample3 ..."
calculate_max() {
    local samples="$1"
    local max=""

    for val in $samples; do
        if [ -z "$max" ] || [ $val -gt $max ]; then
            max=$val
        fi
    done

    echo "${max:-0}"
}

# Calculate standard deviation from array of numbers
# Usage: calculate_stddev "sample1 sample2 sample3 ..." <average>
calculate_stddev() {
    local samples="$1"
    local avg=$2
    local count=0
    local sum_sq_diff=0

    for val in $samples; do
        local diff=$((val - avg))
        sum_sq_diff=$((sum_sq_diff + diff * diff))
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo "0"
    else
        # sqrt(sum_sq_diff / count)
        local variance=$((sum_sq_diff / count))
        # Simple integer square root using awk
        local stddev=$(awk "BEGIN {print int(sqrt($variance))}")
        echo "$stddev"
    fi
}
