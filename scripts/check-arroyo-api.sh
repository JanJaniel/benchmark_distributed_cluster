#!/bin/bash
# Detailed diagnostic script for Arroyo API issues

echo "=== Detailed Arroyo Diagnostics ==="

echo -e "\n1. Docker container details:"
docker ps -a | grep arroyo

echo -e "\n2. Port mapping inspection:"
echo "Container port mappings:"
docker port arroyo-controller

echo -e "\n3. Testing API on different ports:"
echo "   - Testing API on port 8001 (maps to internal 5114):"
curl -s http://localhost:8001/api/v1/workers | jq '.' 2>/dev/null || echo "    Failed on port 8001"
echo "   - Testing without /api/v1 path:"
curl -s http://localhost:8001/workers | jq '.' 2>/dev/null || echo "    Failed without /api/v1"
echo "   - Testing raw HTTP response on 8001:"
curl -I http://localhost:8001 2>&1 | head -3

echo -e "\n4. Container logs (last 30 lines):"
docker logs arroyo-controller --tail 30

echo -e "\n5. Check what's listening inside the container:"
echo "Processes running in container:"
docker exec arroyo-controller ps aux | grep -v "ps aux" || echo "Failed to list processes"

echo -e "\n6. Environment variables in container:"
docker exec arroyo-controller env | grep -E "ARROYO|PORT|AWS" | sort

echo -e "\n7. Test API from inside the container:"
docker exec arroyo-controller sh -c "curl -s http://localhost:5114/api/v1/workers || echo 'API not accessible from inside container on 5114'"
echo "   - Testing port 5115 inside container:"
docker exec arroyo-controller sh -c "curl -s http://localhost:5115/api/v1/workers || echo 'API not accessible from inside container on 5115'"
echo "   - Check if curl exists in container:"
docker exec arroyo-controller which curl || echo "curl not found in container"

echo -e "\n8. Network configuration:"
docker inspect arroyo-controller | jq '.[0].NetworkSettings.Ports'

echo -e "\n9. Check if workers are connected:"
# Try the internal port since external might not work
WORKERS=$(docker exec arroyo-controller curl -s http://localhost:5114/api/v1/workers 2>/dev/null)
if [ ! -z "$WORKERS" ]; then
    echo "Workers found:"
    echo "$WORKERS" | jq '.'
else
    echo "No workers found or API not accessible"
fi

echo -e "\n10. Check if Arroyo binary is running properly:"
docker exec arroyo-controller sh -c "pgrep -a arroyo || echo 'No arroyo process found'"

echo -e "\n11. Check Docker network mode:"
docker inspect arroyo-controller | grep -A5 "NetworkMode"

echo -e "\n12. Test with wget instead of curl from inside:"
docker exec arroyo-controller sh -c "wget -O- -q http://localhost:5114/api/v1/workers 2>&1 || echo 'wget also failed'"

echo -e "\n13. Check if any process is listening on ports:"
docker exec arroyo-controller sh -c "netstat -tln 2>/dev/null || ss -tln 2>/dev/null || echo 'No netstat/ss available'"

echo -e "\n14. Try accessing controller's gRPC port (9190):"
curl -s http://localhost:9190 2>&1 | head -3

echo -e "\n15. Check container's hosts file:"
docker exec arroyo-controller cat /etc/hosts | grep -v "^#"

echo -e "\n16. Test from another container in same network:"
docker run --rm --network container:arroyo-controller alpine sh -c "apk add -q curl && curl -s http://localhost:5114/api/v1/workers || echo 'Failed from alpine container'"

echo -e "\n17. Docker images available:"
docker images | grep -E "arroyo|nexmark"