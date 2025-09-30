#!/bin/bash
# Test script to verify setup locally before deploying to Pis

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Testing Distributed Cluster Setup Locally"
echo "========================================="

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first."
    exit 1
fi

echo "✅ Docker is installed"

# Build images
echo -e "\nBuilding Docker images..."
cd "$PROJECT_ROOT"

echo "Building Arroyo image..."
docker build -t arroyo-pi:latest -f docker/arroyo/Dockerfile docker/arroyo

echo "Building Nexmark generator image..."
docker build -t nexmark-generator:latest -f docker/nexmark-generator/Dockerfile docker/nexmark-generator

# Test MinIO
echo -e "\nTesting MinIO..."
docker run -d --name test-minio \
    -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=minioadmin \
    -e MINIO_ROOT_PASSWORD=minioadmin \
    minio/minio:latest server /data --console-address ":9001"

sleep 5

# Create test bucket
docker run --rm --link test-minio:minio \
    minio/mc:latest \
    sh -c "mc alias set local http://minio:9000 minioadmin minioadmin && mc mb local/test-bucket"

echo "✅ MinIO is working"

# Cleanup
echo -e "\nCleaning up test containers..."
docker stop test-minio
docker rm test-minio

echo -e "\n✅ Local testing complete!"
echo "Images are ready for deployment to Raspberry Pis"