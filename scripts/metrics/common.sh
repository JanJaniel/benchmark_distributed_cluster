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
    sleep "$duration"
    local after=$(get_kafka_topic_offset "$broker" "$topic")

    # Use awk for all arithmetic to handle large numbers and decimals
    local throughput=$(awk "BEGIN {printf \"%.2f\", ($after - $before) / $duration}")

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
        sum=$(awk "BEGIN {printf \"%.2f\", $sum + $val}")
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo "0"
    else
        awk "BEGIN {printf \"%.2f\", $sum / $count}"
    fi
}

# Calculate minimum from array of numbers
# Usage: calculate_min "sample1 sample2 sample3 ..."
calculate_min() {
    local samples="$1"
    local min=""

    for val in $samples; do
        if [ -z "$min" ]; then
            min=$val
        else
            # Use awk for float comparison
            local is_less=$(awk "BEGIN {print ($val < $min) ? 1 : 0}")
            if [ "$is_less" -eq 1 ]; then
                min=$val
            fi
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
        if [ -z "$max" ]; then
            max=$val
        else
            # Use awk for float comparison
            local is_greater=$(awk "BEGIN {print ($val > $max) ? 1 : 0}")
            if [ "$is_greater" -eq 1 ]; then
                max=$val
            fi
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
        local diff=$(awk "BEGIN {printf \"%.4f\", $val - $avg}")
        sum_sq_diff=$(awk "BEGIN {printf \"%.4f\", $sum_sq_diff + ($diff * $diff)}")
        count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        echo "0"
    else
        # sqrt(sum_sq_diff / count)
        local variance=$(awk "BEGIN {printf \"%.4f\", $sum_sq_diff / $count}")
        # Calculate square root with proper precision
        local stddev=$(awk "BEGIN {printf \"%.2f\", sqrt($variance)}")
        echo "$stddev"
    fi
}
