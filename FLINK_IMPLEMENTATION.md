# Flink Implementation Summary

This document describes the Flink benchmarking infrastructure added to this repository.

## What Was Built

### 1. Flink Queries (`flink-queries/`)
- **Location**: `/flink-queries/src/main/java/nexmark/`
- **Source**: Copied from `flink-java` reference implementation
- **Key Changes**:
  - `NexmarkTables.java`: Modified to read Kafka broker from environment variable `KAFKA_BOOTSTRAP_SERVERS`
  - Default: `localhost:9092` (for local testing)
  - Production: `192.168.2.70:9094` (set in docker-compose)

### 2. Docker Infrastructure
- **Dockerfile**: `/flink-queries/Dockerfile`
  - Multi-stage build (Maven + Flink runtime)
  - Builds JAR with all 7 queries
  - Final image: `flink-nexmark:latest`

- **Controller**: `/deploy/controller-flink/docker-compose.yml`
  - Runs Flink JobManager
  - Exposes port 8081 (Web UI)
  - Connects to Kafka at `192.168.2.70:9094`

- **Workers**: `/deploy/worker-flink/docker-compose.yml`
  - Runs Flink TaskManager
  - Container name: `flink-worker-${NODE_ID}` (1-9)
  - 4 task slots per worker (36 total)
  - Connects to JobManager at `192.168.2.70`

### 3. Deployment Scripts
- **`scripts/setup-flink.sh`**:
  - Builds Flink Docker image
  - Distributes to all 10 nodes
  - Starts JobManager on controller
  - Starts 9 TaskManagers on workers
  - Verifies cluster readiness

- **`scripts/teardown-flink.sh`**:
  - Stops all TaskManagers
  - Stops JobManager
  - Leaves Docker image for faster restarts

### 4. Measurement Script
- **`scripts/metrics/measure-flink.sh`**:
  - Submits Flink job via `flink run -d -c <query-class>`
  - Waits for job to start running
  - Continuous CPU sampling (every 5s)
  - Measures Kafka throughput (input/output topics)
  - Cancels job after measurement
  - Outputs JSON metrics (same format as Arroyo)

### 5. Modified Files
- **`scripts/run-benchmark.sh`**:
  - Added `--system` parameter (arroyo|flink)
  - Conditional logic for:
    - Job cleanup (Arroyo pipelines vs Flink jobs)
    - Query submission (REST API vs JAR submit)
    - Measurement script selection
    - Job cancellation
  - Default: `arroyo` (backward compatible)

- **`.gitignore`**:
  - Excludes reference folders: `/flink-java`, `/flink_project`
  - Includes our implementation: `/flink-queries` (except `/flink-queries/target/`)

- **`README.md`**:
  - Updated to mention both systems
  - Added Flink-specific instructions

## Architecture

```
Controller (192.168.2.70):
├── Kafka + Zookeeper (shared)
├── Generator (shared)
└── Flink JobManager (port 8081)

Workers (192.168.2.71-79):
└── Flink TaskManager (flink-worker-1 to flink-worker-9)
```

## Query Mapping

| Query | Class | Type | Input Topics | Output Topic |
|-------|-------|------|--------------|--------------|
| q1 | NexmarkQ1SQL | SQL | nexmark-bid | nexmark-q1-results |
| q2 | NexmarkQ2SQL | SQL | nexmark-bid | nexmark-q2-results |
| q3 | NexmarkQ3SQL | SQL | nexmark-person, nexmark-auction | nexmark-q3-results |
| q4 | NexmarkQ4SQL | SQL | nexmark-auction, nexmark-bid | nexmark-q4-results |
| q5 | NexmarkQ5 | DataStream | nexmark-bid | nexmark-q5-results |
| q7 | NexmarkQ7 | DataStream | nexmark-bid | nexmark-q7-results |
| q8 | NexmarkQ8 | DataStream | nexmark-person, nexmark-auction | nexmark-q8-results |

## Usage

### Deploy Flink
```bash
./scripts/setup-flink.sh
```

### Run Benchmark
```bash
./scripts/run-benchmark.sh --system flink
```

### Check Flink Web UI
```
http://192.168.2.70:8081
```

### Teardown
```bash
./scripts/teardown-flink.sh
```

## Metrics Collected

Same format as Arroyo:
- **Throughput**: Input/output events per second
- **CPU**: Core-seconds (continuous sampling every 5s)
- **Job Info**: Job ID, state, task count
- **Output**: JSON + text table summary

## Key Differences from Arroyo

1. **Job Submission**:
   - Arroyo: REST API with SQL string
   - Flink: CLI tool with compiled JAR

2. **Query Language**:
   - Arroyo: Pure SQL
   - Flink: SQL (q1-q4) + DataStream API (q5, q7, q8)

3. **Container Names**:
   - Arroyo: `arroyo-worker-worker-1`
   - Flink: `flink-worker-1`

4. **CPU Measurement**:
   - Both: `docker stats <container-name>`
   - Same continuous sampling approach

## Testing Status

⚠️ **Not yet tested** - implementation is complete but needs debugging:
1. Build Flink Docker image
2. Deploy to cluster
3. Run test query (q1)
4. Full benchmark suite
5. Compare results with Arroyo

## Known Limitations

1. **No persistent storage**: Flink doesn't use MinIO (stateless queries)
2. **Fixed Kafka broker**: Hardcoded to `192.168.2.70:9094` in environment
3. **Java 11 required**: Maven build needs JDK 11+
4. **Build time**: Maven build in Docker takes ~5-10 minutes

## Next Steps

1. Test Flink deployment on cluster
2. Debug any connectivity issues (Kafka, JobManager)
3. Run benchmark and compare with Arroyo
4. Document performance differences
5. Consider optimizations (parallelism, slots, memory)
