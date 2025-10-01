#!/bin/bash
# Script to diagnose Arroyo API issues (without web UI checks)

echo "=== Checking Arroyo Controller Status ==="

# Check if controller is running
echo -e "\n1. Checking Docker containers on controller:"
docker ps | grep arroyo

# Check API endpoints
echo -e "\n2. Checking Arroyo API endpoints:"
echo "   - Workers endpoint:"
curl -s http://localhost:8001/api/v1/workers | jq '.' 2>/dev/null || echo "Workers endpoint failed"

echo -e "\n   - Pipelines endpoint:"
curl -s http://localhost:8001/api/v1/pipelines | jq '.' 2>/dev/null || echo "Pipelines endpoint failed"

# Check controller logs for errors
echo -e "\n3. Recent controller error logs:"
docker logs arroyo-controller 2>&1 | grep -i error | tail -5

# Test basic API functionality
echo -e "\n4. Testing pipeline creation API:"
# Create a simple test query
TEST_QUERY=$(cat <<'EOF'
{
  "name": "test_pipeline",
  "query": "CREATE TABLE test (id INT) WITH (connector = 'impulse', event_rate = '10'); SELECT * FROM test;",
  "parallelism": 1
}
EOF
)

echo "   Sending test query..."
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$TEST_QUERY" \
  http://localhost:8001/api/v1/pipelines)

echo "   Response: $RESPONSE"

# Check Docker images
echo -e "\n5. Checking Docker images:"
docker images | grep arroyo