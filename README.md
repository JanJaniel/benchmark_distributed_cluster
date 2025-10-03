# Distributed Stream Processing Benchmark on Raspberry Pi

This repository contains a complete benchmarking infrastructure for comparing distributed stream processing systems (Apache Arroyo and Apache Flink) on a Raspberry Pi cluster.

## Architecture Overview

### Shared Infrastructure
- **Pi1 (Controller)**: Runs Kafka, data generator, and either Arroyo controller or Flink JobManager
- **Pi2-Pi10 (Workers)**: Run either Arroyo workers or Flink TaskManagers
- **Storage**: MinIO provides S3-compatible storage for Arroyo checkpoints
- **Messaging**: Kafka with 9 partitions per topic for parallel consumption

### Supported Systems
- **Apache Arroyo v0.11.0**: Rust-based streaming engine with SQL support
- **Apache Flink 1.18.1**: JVM-based streaming engine with Table API

## Prerequisites

1. **Hardware**: 10 Raspberry Pi devices (4GB+ RAM recommended)
2. **Network**: All Pis on same network with static IPs (192.168.2.70-79)
3. **OS**: Raspberry Pi OS 64-bit on all devices
4. **User**: `picocluster` user with sudo access on all Pis

## Quick Start

### 1. Setup SSH Keys (Run from Pi1)
```bash
cd scripts
./setup-ssh-keys.sh
```

### 2. Deploy System (Choose One)

**For Apache Arroyo:**
```bash
./scripts/setup-cluster.sh
```

**For Apache Flink:**
```bash
./scripts/setup-flink.sh
```

This will:
- Build Docker images
- Distribute images to all nodes
- Start controller and worker containers
- Create Kafka topics (Arroyo only)
- Verify cluster readiness

### 3. Run Benchmark

**Arroyo:**
```bash
./scripts/run-benchmark.sh --system arroyo
```

**Flink:**
```bash
./scripts/run-benchmark.sh --system flink
```

**Optional parameters:**
```bash
./scripts/run-benchmark.sh --system flink \
  --events-per-second 10000 \
  --total-events 10000000 \
  --queries q1,q2,q3,q4,q5,q7,q8 \
  --parallelism 9
```

### 4. View Results
Results are saved in `benchmark_results_YYYYMMDD_HHMMSS.txt`

### 5. Teardown

**Arroyo:**
```bash
./scripts/teardown-cluster.sh
```

**Flink:**
```bash
./scripts/teardown-flink.sh
```

## Detailed Setup

### Network Configuration

Ensure all Pis have static IPs:
- Pi1: 192.168.2.70 (Controller)
- Pi2: 192.168.2.71 (Worker 1)
- Pi3: 192.168.2.72 (Worker 2)
- ... continuing to ...
- Pi10: 192.168.2.79 (Worker 9)

### Docker Installation

The setup script will install Docker automatically. If manual installation is needed:
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

### Service Endpoints

- **Arroyo Web UI**: http://192.168.2.70:8000 (Note: No web UI in distributed mode)
- **Arroyo API**: http://192.168.2.70:8001
- **MinIO Console**: http://192.168.2.70:9001 (user/pass: minioadmin/minioadmin)
- **Kafka Broker**: 192.168.2.70:9094

## How It Works

### True Distributed Processing

1. **Single Submission**: Queries are submitted once to the controller
2. **Automatic Distribution**: Arroyo splits queries into 9 parallel subtasks
3. **Worker Processing**: Each worker processes 1/9th of the data
4. **Result Aggregation**: Controller combines results from all workers

### Query Submission

Queries are submitted with parallelism=9:
```json
{
  "name": "nexmark_q1_distributed",
  "query": "SELECT ...",
  "parallelism": 9
}
```

### Data Flow

1. Generator produces events to Kafka (9 partitions)
2. Each worker consumes from assigned partitions
3. Workers process data in parallel
4. Results are aggregated at controller

## Monitoring

### Real-time Monitoring
```bash
python monitoring/collect-metrics.py
```

### Save Metrics to File
```bash
python monitoring/collect-metrics.py -o metrics.json
```

### One-time Metrics Collection
```bash
python monitoring/collect-metrics.py --once
```

## Teardown

### Stop Cluster (Preserve Data)
```bash
./scripts/teardown-cluster.sh
# Answer 'n' when asked about removing volumes
```

### Complete Cleanup
```bash
./scripts/teardown-cluster.sh
# Answer 'y' to remove all data and project files
```

## Troubleshooting

### Check Service Logs

Controller services:
```bash
ssh picocluster@192.168.2.70 "cd ~/benchmark_distributed_cluster/deploy/controller && docker compose logs -f"
```

Worker services:
```bash
ssh picocluster@192.168.2.71 "cd ~/benchmark_distributed_cluster/deploy/worker && docker compose logs -f"
```

### Verify Worker Connection
```bash
curl http://192.168.2.70:8001/api/v1/workers
```

### Common Issues

1. **Workers not connecting**: Check firewall rules, ensure gRPC port 9190 is accessible
2. **Out of memory**: Reduce parallelism or events per second
3. **Kafka connection errors**: Verify Kafka is running and accessible
4. **API not accessible**: Ensure controller is using `arroyo-pi:latest` image
5. **Controller crashes**: Check memory limits and use custom ARM64 image

### Minimal System Impact

All components run in Docker containers:
- **No system packages installed** (except Docker)
- **No language runtimes on host**
- **Easy cleanup** with `docker compose down`
- **Resource isolated** via Docker limits

### Resource Usage per Pi

- **Pi1**: ~2GB RAM (Kafka, MinIO, Arroyo Controller)
- **Pi2-10**: ~1GB RAM each (Arroyo Workers only)
- **Network**: Internal cluster traffic only
- **Storage**: ~1GB for containers and data

### Security Considerations

- All services bind to internal IPs only
- SSH key-based authentication
- MinIO uses access keys (change in production)
- No external network access required

## Customization

### Adjust Parallelism
Edit `config/cluster-topology.yaml`:
```yaml
benchmark:
  parallelism: 9  # Change based on worker count
```

### Change Memory Limits
Edit Docker Compose files to adjust resource limits:
```yaml
environment:
  ARROYO__MEMORY_PER_SLOT_MB: 768  # Adjust based on Pi RAM
```

### Add More Workers
1. Add new worker to `config/cluster-topology.yaml`
2. Update scripts to include new IP
3. Increase Kafka partitions to match worker count
