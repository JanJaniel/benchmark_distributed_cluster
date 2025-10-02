#!/bin/bash
# Common functions for metrics collection across different stream processing engines

# Get total offset (message count) for a Kafka topic
# Usage: get_kafka_topic_offset <broker> <topic>
get_kafka_topic_offset() {
    local broker=$1
    local topic=$2

    ssh ${CLUSTER_USER}@${CONTROLLER_IP} "docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list $broker \
        --topic $topic 2>/dev/null" | awk -F: '{sum+=$NF} END {print sum+0}'
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

    local diff=$((after - before))
    local throughput=$((diff / duration))

    echo "$throughput"
}

# Check if Kafka topic exists
# Usage: kafka_topic_exists <broker> <topic>
kafka_topic_exists() {
    local broker=$1
    local topic=$2

    local topics=$(ssh ${CLUSTER_USER}@${CONTROLLER_IP} "docker exec kafka kafka-topics \
        --bootstrap-server $broker \
        --list 2>/dev/null")

    echo "$topics" | grep -q "^${topic}$"
    return $?
}
