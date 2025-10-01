#!/bin/bash
# Detailed diagnostic script for Arroyo API issues

echo "=== Detailed Arroyo Diagnostics ==="

echo -e "\n1. Docker container details:"
docker ps -a | grep arroyo

echo -e "\n2. Port mapping inspection:"
echo "Container port mappings:"
docker port arroyo-controller

echo -e "\n3. Testing API on different ports:"
echo "   - Testing API on port 8000 (maps to internal 5115):"
curl -s http://localhost:8000/api/v1/workers | jq '.' 2>/dev/null || echo "    Failed on port 8000"

echo -e "\n4. Container logs (last 30 lines):"
docker logs arroyo-controller --tail 30

echo -e "\n5. Check what's listening inside the container:"
echo "Processes running in container:"
docker exec arroyo-controller ps aux | grep -v "ps aux" || echo "Failed to list processes"

echo -e "\n6. Environment variables in container:"
docker exec arroyo-controller env | grep -E "ARROYO|PORT|AWS" | sort

echo -e "\n7. Test API from inside the container:"
docker exec arroyo-controller sh -c "curl -s http://localhost:5115/api/v1/workers || echo 'API not accessible from inside container'"

echo -e "\n8. Network configuration:"
docker inspect arroyo-controller | jq '.[0].NetworkSettings.Ports'

echo -e "\n9. Check if workers are connected:"
# Try the internal port since external might not work
WORKERS=$(docker exec arroyo-controller curl -s http://localhost:5115/api/v1/workers 2>/dev/null)
if [ ! -z "$WORKERS" ]; then
    echo "Workers found:"
    echo "$WORKERS" | jq '.'
else
    echo "No workers found or API not accessible"
fi

echo -e "\n10. Docker images available:"
docker images | grep -E "arroyo|nexmark"