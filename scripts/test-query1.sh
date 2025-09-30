#!/bin/bash
# Schnelltest mit Query 1

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/cluster-env.sh"

echo "========================================="
echo "Query 1 Test - Distributed Arroyo"
echo "========================================="

# Prüfe ob Controller läuft
echo "1. Checking controller health..."
if ! curl -f http://$CONTROLLER_IP:8000/health >/dev/null 2>&1; then
    echo "❌ Controller not healthy! Please run setup first."
    exit 1
fi
echo "✅ Controller is healthy"

# Prüfe Worker
echo -e "\n2. Checking workers..."
WORKERS=$(curl -s http://$CONTROLLER_IP:8001/api/v1/workers | jq -r '. | length // 0')
echo "Connected workers: $WORKERS"
if [ "$WORKERS" -lt 5 ]; then
    echo "⚠️  Warning: Only $WORKERS workers connected (expected 9)"
fi

# Starte Generator mit weniger Events für Test
echo -e "\n3. Starting data generator (test mode: 100k events)..."
docker stop nexmark-generator 2>/dev/null || true
docker run -d --rm \
    --name nexmark-generator \
    --network host \
    -e KAFKA_BROKER=${CONTROLLER_IP}:${KAFKA_PORT} \
    -e EVENTS_PER_SECOND=10000 \
    -e TOTAL_EVENTS=100000 \
    -v $(dirname $SCRIPT_DIR)/nexmark-generator-deterministic.py:/app/generator/nexmark-generator-deterministic.py:ro \
    nexmark-generator:latest

echo "✅ Generator started"

# Query 1 vorbereiten
echo -e "\n4. Preparing Query 1..."
QUERY_FILE="$(dirname $SCRIPT_DIR)/queries/nexmark_q1.sql"

if [ ! -f "$QUERY_FILE" ]; then
    echo "❌ Query file not found: $QUERY_FILE"
    exit 1
fi

# Query anpassen für richtige Kafka IP
QUERY_CONTENT=$(cat "$QUERY_FILE" | sed "s/localhost:9092/${CONTROLLER_IP}:${KAFKA_PORT}/g")

# Query submitten
echo -e "\n5. Submitting Query 1 to Arroyo..."
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines \
    -d @- <<EOF
{
    "name": "nexmark_q1_test_$(date +%s)",
    "query": "$QUERY_CONTENT",
    "parallelism": 9
}
EOF
)

PIPELINE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

if [ -z "$PIPELINE_ID" ]; then
    echo "❌ Failed to create pipeline!"
    echo "Response: $RESPONSE"
    exit 1
fi

echo "✅ Pipeline created: $PIPELINE_ID"

# Monitor für 30 Sekunden
echo -e "\n6. Monitoring pipeline for 30 seconds..."
echo "You can also check:"
echo "  - Web UI: http://${CONTROLLER_IP}:8000"
echo "  - MinIO: http://${CONTROLLER_IP}:9001 (minioadmin/minioadmin)"
echo ""

for i in {1..6}; do
    sleep 5
    
    # Pipeline Metriken holen
    JOBS=$(curl -s http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/${PIPELINE_ID}/jobs)
    JOB_ID=$(echo "$JOBS" | jq -r '.data[0].id // empty')
    
    if [ ! -z "$JOB_ID" ]; then
        METRICS=$(curl -s http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/jobs/${JOB_ID}/metrics 2>/dev/null || echo "{}")
        EVENTS=$(echo "$METRICS" | jq -r '.events_processed // 0')
        RATE=$(echo "$METRICS" | jq -r '.events_per_second // 0')
        
        echo "[$(date +%H:%M:%S)] Events processed: $EVENTS, Rate: $RATE events/sec"
    fi
done

# Cleanup Option
echo -e "\n========================================="
echo "Test completed!"
echo ""
read -p "Stop pipeline and generator? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Stopping pipeline..."
    curl -X DELETE http://${CONTROLLER_IP}:${ARROYO_API_PORT}/api/v1/pipelines/${PIPELINE_ID}
    
    echo "Stopping generator..."
    docker stop nexmark-generator
    
    echo "✅ Cleanup complete"
fi

echo ""
echo "Next steps:"
echo "1. Run full benchmark: ./run-benchmark.sh"
echo "2. Check worker logs if needed:"
echo "   ssh jan@192.168.2.71 'docker logs arroyo-worker-worker-1'"