# Complete Dependency List for Distributed Benchmark

This document lists all software and dependencies needed for the distributed stream processing benchmark on 10 Raspberry Pis.

## Host System Requirements (Minimal)

### Operating System
- **Raspberry Pi OS** (64-bit, Debian-based)
- Kernel 5.15 or newer

### Only Two Software Packages on Host
1. **Docker Engine** (version 20.10+)
2. **Docker Compose** (version 2.0+)

That's it! Everything else runs inside containers.

## Containerized Components

### 1. Infrastructure Services (Pi1 Only)

#### Apache Kafka
- **Image**: confluentinc/cp-kafka:7.5.0 (ARM64 compatible)
- **Dependencies**: Zookeeper (included)
- **Memory**: 512-768MB
- **Purpose**: Message broker for streaming data

#### MinIO
- **Image**: minio/minio:latest
- **Memory**: 256MB
- **Purpose**: S3-compatible storage for checkpoints

### 2. Stream Processing Engines

#### Apache Arroyo
- **Version**: 0.11.0 (ARM64 binary)
- **Base Image**: debian:bookworm-slim
- **Dependencies**: None (single static binary)
- **Memory**: 1-2GB per node
- **Purpose**: Distributed stream processing

#### Apache Flink
- **Version**: 1.18.1
- **Base Image**: flink:1.18.1-scala_2.12
- **Build Dependencies** (in Dockerfile):
  - Maven 3.8 + OpenJDK 11 (build stage)
  - Java Libraries: Flink SQL, Kafka connector, Jackson JSON
- **Runtime Dependencies**: Java 11 (included in flink image)
- **Memory**: 1.6GB per node
- **Purpose**: Alternative stream processor for comparison

### 3. Data Generation

#### Nexmark Generator
- **Base Image**: python:3.10-slim-bookworm
- **Python Libraries**:
  - kafka-python >= 2.0.2
  - confluent-kafka >= 2.3.0
  - numpy >= 1.24.0
  - pyyaml >= 6.0
  - psutil >= 5.9.0
- **Memory**: 256MB
- **Purpose**: Generate benchmark data

## Network Requirements

### Ports Used (System-Dependent)

**Shared (both systems):**
- **9094**: Kafka external listener
- **9000**: MinIO S3 API
- **9001**: MinIO Console
- **2181**: Zookeeper (internal)

**Arroyo-specific:**
- **8000**: Arroyo Web UI
- **8001**: Arroyo HTTP API
- **9190**: Arroyo gRPC (worker communication)

**Flink-specific:**
- **8081**: Flink Web Dashboard
- **6123**: Flink RPC (JobManager communication)

### Network Configuration
- Static IP addresses (192.168.2.42-51)
- All Pis on same subnet
- SSH access between nodes (port 22)

## Security Considerations

### Authentication
- SSH key-based authentication only
- MinIO access keys (configurable)
- No external network access required

### Isolation
- All services run in Docker containers
- Resource limits enforced by Docker
- Network isolation via Docker networks

## Resource Usage Summary

### Per Pi Resource Requirements

#### Pi1 (Controller)
- **RAM**: 2-2.5GB total
  - Kafka: 768MB
  - MinIO: 256MB
  - Arroyo Controller: 1GB
  - System overhead: 512MB
- **Storage**: 2GB for containers + data
- **CPU**: Variable (2-4 cores during operation)

#### Pi2-10 (Workers)
- **RAM**: 1-1.5GB total
  - Arroyo Worker: 1GB
  - System overhead: 512MB
- **Storage**: 1GB for containers
- **CPU**: Variable (1-4 cores during processing)

## Installation Summary

The entire deployment requires only:

```bash
# 1. Install Docker (one-time per Pi)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# 2. Choose and deploy system (from Pi1)
# For Arroyo:
./scripts/setup-cluster.sh

# OR for Flink:
./scripts/setup-flink.sh
```

## Cleanup

Complete removal leaves no trace:

```bash
# Remove all containers and data
# For Arroyo:
./scripts/teardown-cluster.sh

# OR for Flink:
./scripts/teardown-flink.sh

# Optional: Remove Docker
sudo apt-get purge docker-ce docker-ce-cli containerd.io
```

## Advantages for Shared Infrastructure

1. **Zero System Modifications**: Only Docker installed
2. **Complete Isolation**: All components containerized
3. **Easy Cleanup**: Single command removes everything
4. **No Language Runtimes**: No Python/Java/Node on host
5. **No Package Conflicts**: Containers have own dependencies
6. **Resource Control**: Docker enforces limits

This approach ensures your benchmark has minimal impact on the shared Raspberry Pi infrastructure while still providing a fully functional distributed stream processing environment.