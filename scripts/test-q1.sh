#!/bin/bash
# Simple script to test Nexmark Q1 submission

echo "=== Testing Nexmark Q1 Submission ==="

# Source cluster environment
source "$(dirname "$0")/cluster-env.sh"

# Check if controller is reachable
echo "1. Checking controller API..."
curl -s http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/workers > /dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: Cannot reach Arroyo API at ${CONTROLLER_IP}:${ARROYO_API_PORT}"
    exit 1
fi
echo "✓ Controller API is reachable"

# Read Q1 query
QUERY_FILE="$(dirname "$0")/../queries/nexmark_q1.sql"
if [ ! -f "$QUERY_FILE" ]; then
    echo "ERROR: Query file not found: $QUERY_FILE"
    exit 1
fi

# Read and modify the query
QUERY_CONTENT=$(cat "$QUERY_FILE")

# Update Kafka broker address
QUERY_CONTENT="${QUERY_CONTENT//localhost:9092/${CONTROLLER_IP}:${KAFKA_PORT}}"

# Create JSON payload
JSON_PAYLOAD=$(jq -n \
    --arg name "nexmark_q1_test_$(date +%s)" \
    --arg query "$QUERY_CONTENT" \
    --argjson parallelism 9 \
    '{
        name: $name,
        query: $query,
        parallelism: $parallelism
    }')

echo -e "\n2. Submitting Q1 query..."
echo "Query name: nexmark_q1_test_$(date +%s)"
echo "Parallelism: 9"

# Submit to Arroyo
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines")

# Check response
PIPELINE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

if [ -z "$PIPELINE_ID" ]; then
    echo "❌ Failed to create pipeline"
    echo "Response: $RESPONSE"
    exit 1
else
    echo "✅ Pipeline created successfully!"
    echo "Pipeline ID: $PIPELINE_ID"
fi

# Check pipeline status
echo -e "\n3. Checking pipeline status..."
STATUS_RESPONSE=$(curl -s "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/${PIPELINE_ID}")
echo "Pipeline status:"
echo "$STATUS_RESPONSE" | jq '.'

# Check workers
echo -e "\n4. Connected workers:"
curl -s "http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/workers" | jq '.'

echo -e "\nDone! You can monitor the pipeline at: http://${CONTROLLER_IP}:8000"