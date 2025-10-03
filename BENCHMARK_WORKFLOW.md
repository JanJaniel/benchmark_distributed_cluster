# Complete Benchmark Workflow: Arroyo → Flink

This guide provides the exact step-by-step workflow for benchmarking both systems.

---

## Prerequisites

1. SSH access to controller (192.168.2.70)
2. All 10 Pis powered on and accessible
3. SSH keys already set up between nodes

---

## Phase 1: Benchmark Arroyo

### Step 1: Connect to Controller
```bash
ssh picocluster@192.168.2.70
cd ~/benchmark_distributed_cluster
```

### Step 2: Deploy Arroyo Cluster
```bash
./scripts/setup-cluster.sh
```

**What this does:**
- Builds `arroyo-pi:latest` Docker image
- Starts Kafka, Zookeeper, MinIO on controller
- Starts Arroyo controller on controller
- Starts 9 Arroyo workers on Pi2-10
- Creates Kafka topics
- **Time:** ~5-10 minutes

**Expected output:**
```
✅ Arroyo controller started
✅ All 9 workers started
✅ Cluster is ready!
Arroyo API: http://192.168.2.70:8001
```

### Step 3: Verify Arroyo Cluster
```bash
# Check cluster status
curl -s http://192.168.2.70:8001/api/v1/workers | jq
```

**Expected:** Should show 9 workers

### Step 4: Run Quick Test (Optional but Recommended)
```bash
# Test just q1 to verify everything works (~3 minutes)
./scripts/run-benchmark.sh --system arroyo --queries q1
```

**Expected output:**
```
ARROYO BENCHMARK RESULTS
Query: q1
Input:  ~2000 events/sec
Output: ~2000 events/sec
Core-seconds: 10-20
```

### Step 5: Run Full Arroyo Benchmark
```bash
# Run all 7 queries (~30-40 minutes total)
./scripts/run-benchmark.sh --system arroyo
```

**What this does:**
- Runs queries: q1, q2, q3, q4, q5, q7, q8 (sequentially)
- Each query: 30s warmup + 120s measurement = ~3 minutes
- Collects: throughput, CPU, latency metrics
- Saves results to: `benchmark_results_YYYYMMDD_HHMMSS.txt`

**Expected duration:** ~30-40 minutes

### Step 6: Save Arroyo Results
```bash
# Copy results to safe location
cp benchmark_results_*.txt arroyo_results.txt
cat arroyo_results.txt
```

**Example output:**
```
==========================================
ARROYO BENCHMARK RESULTS
==========================================

Query      Input Rate           Output Throughput    Core×Time
---------- -------------------- -------------------- ---------------
q1         2000.45 events/sec   2005.03 events/sec   13 core-sec
q2         2052.61 events/sec   9.04 events/sec      15 core-sec
q3         206.12 events/sec    150.57 events/sec    18 core-sec
...
```

### Step 7: Teardown Arroyo
```bash
./scripts/teardown-cluster.sh
```

**Prompts you'll see:**
1. `Remove all data volumes? (y/n):` → **Press 'n'** (keep Kafka data for Flink)
2. `Remove project files from all nodes? (y/n):` → **Press 'n'** (need them for Flink)

**What this does:**
- Stops all Arroyo workers
- Stops Arroyo controller
- **Stops Kafka, Zookeeper, MinIO** (but keeps data if you said 'n')

---

## Phase 2: Benchmark Flink

### Step 8: Deploy Flink Cluster
```bash
./scripts/setup-flink.sh
```

**What this does:**
1. Checks if Kafka is running → starts it if needed
2. Builds `flink-nexmark:latest` Docker image (**Maven build ~5-10 minutes**)
3. Distributes image to all 10 nodes
4. Starts Flink JobManager on controller
5. Starts 9 Flink TaskManagers on Pi2-10
6. Verifies cluster readiness

**Time:** ~15-20 minutes (first time due to Maven build)

**Expected output:**
```
✅ Flink image built
✅ Image distributed to all nodes
✅ JobManager started
✅ All TaskManagers started
TaskManagers registered: 9 / 9
✅ Flink cluster is ready!
Flink Web UI: http://192.168.2.70:8081
```

**Important:** The Maven build is SLOW on Raspberry Pi - be patient!

### Step 9: Verify Flink Cluster
```bash
# Check Flink cluster status
curl -s http://192.168.2.70:8081/taskmanagers | jq

# Or open in browser (if you have GUI access)
# http://192.168.2.70:8081
```

**Expected:** Should show 9 TaskManagers

### Step 10: Run Quick Test (Optional but Recommended)
```bash
# Test just q1 to verify everything works (~3 minutes)
./scripts/run-benchmark.sh --system flink --queries q1
```

**Expected output:**
```
FLINK BENCHMARK RESULTS
Query: q1
Input:  ~2000 events/sec
Output: ~2000 events/sec
Core-seconds: 15-25
```

### Step 11: Run Full Flink Benchmark
```bash
# Run all 7 queries (~30-40 minutes total)
./scripts/run-benchmark.sh --system flink
```

**What this does:**
- Runs same 7 queries as Arroyo
- Submits Flink jobs via `flink run -d -c <query-class>`
- Collects same metrics (throughput, CPU)
- Saves results to: `benchmark_results_YYYYMMDD_HHMMSS.txt`

**Expected duration:** ~30-40 minutes

### Step 12: Save Flink Results
```bash
# Copy results to safe location
cp benchmark_results_*.txt flink_results.txt
cat flink_results.txt
```

### Step 13: Teardown Flink
```bash
./scripts/teardown-flink.sh
```

**What this does:**
- Stops all 9 Flink TaskManagers
- Stops Flink JobManager
- **Leaves Kafka running** (no prompts)
- **Leaves Flink image on nodes** (for faster re-deployment)

---

## Phase 3: Compare Results

### Step 14: Compare Both Systems
```bash
# View side-by-side comparison
echo "=== ARROYO ==="
cat arroyo_results.txt

echo ""
echo "=== FLINK ==="
cat flink_results.txt
```

### Step 15: Copy Results to Local Machine
```bash
# From your local machine (not on Pi):
scp picocluster@192.168.2.70:~/benchmark_distributed_cluster/arroyo_results.txt .
scp picocluster@192.168.2.70:~/benchmark_distributed_cluster/flink_results.txt .
```

---

## Phase 4: Final Cleanup (Optional)

### Step 16: Stop All Remaining Services
```bash
# Stop Kafka/MinIO if still running
ssh picocluster@192.168.2.70 \
  'cd ~/benchmark_distributed_cluster/deploy/controller && docker compose down'
```

### Step 17: Remove Docker Images (Optional - Saves Space)
```bash
# Remove Arroyo images from all nodes
for i in {1..9}; do
  ssh picocluster@192.168.2.7$i 'docker rmi arroyo-pi:latest'
done
ssh picocluster@192.168.2.70 'docker rmi arroyo-pi:latest'

# Remove Flink images from all nodes
for i in {1..9}; do
  ssh picocluster@192.168.2.7$i 'docker rmi flink-nexmark:latest'
done
ssh picocluster@192.168.2.70 'docker rmi flink-nexmark:latest'
```

---

## Troubleshooting

### Arroyo Issues

**Problem: Workers not connecting**
```bash
# Check worker logs
ssh picocluster@192.168.2.71 "docker logs arroyo-worker-worker-1"

# Check if workers can reach controller
ssh picocluster@192.168.2.71 "curl -s http://192.168.2.70:8001/health"
```

**Problem: Query timeout**
```bash
# Check Arroyo controller logs
ssh picocluster@192.168.2.70 "cd ~/benchmark_distributed_cluster/deploy/controller && docker compose logs arroyo-controller"
```

### Flink Issues

**Problem: Maven build fails**
```bash
# Check if you have enough disk space
df -h

# Try building manually to see full error
cd ~/benchmark_distributed_cluster/flink-queries
docker build -t flink-nexmark:latest .
```

**Problem: TaskManagers not registering**
```bash
# Check TaskManager logs
ssh picocluster@192.168.2.71 "docker logs flink-worker-1"

# Check if TaskManager can reach JobManager
ssh picocluster@192.168.2.71 "curl -s http://192.168.2.70:8081"
```

**Problem: Job submission fails**
```bash
# Check JobManager logs
ssh picocluster@192.168.2.70 "docker logs flink-jobmanager"

# List running containers
ssh picocluster@192.168.2.70 "docker ps"
```

### General Issues

**Problem: Out of memory**
```bash
# Check memory usage on controller
ssh picocluster@192.168.2.70 "free -h"

# Check memory usage on worker
ssh picocluster@192.168.2.71 "free -h"
```

**Problem: Kafka not accessible**
```bash
# Check Kafka status
ssh picocluster@192.168.2.70 \
  "docker exec kafka kafka-topics --bootstrap-server localhost:19092 --list"
```

---

## Quick Reference Commands

### Status Checks
```bash
# Arroyo
curl -s http://192.168.2.70:8001/api/v1/workers | jq

# Flink
curl -s http://192.168.2.70:8081/taskmanagers | jq

# Kafka topics
ssh picocluster@192.168.2.70 \
  "docker exec kafka kafka-topics --bootstrap-server localhost:19092 --list"
```

### Log Viewing
```bash
# Arroyo controller
ssh picocluster@192.168.2.70 "docker logs -f arroyo-controller"

# Arroyo worker
ssh picocluster@192.168.2.71 "docker logs -f arroyo-worker-worker-1"

# Flink JobManager
ssh picocluster@192.168.2.70 "docker logs -f flink-jobmanager"

# Flink TaskManager
ssh picocluster@192.168.2.71 "docker logs -f flink-worker-1"
```

### Container Status
```bash
# Check all containers on controller
ssh picocluster@192.168.2.70 "docker ps"

# Check all containers on worker 1
ssh picocluster@192.168.2.71 "docker ps"
```

---

## Timeline Summary

| Phase | Task | Duration |
|-------|------|----------|
| 1.1 | Deploy Arroyo | 5-10 min |
| 1.2 | Test Arroyo (q1) | 3 min |
| 1.3 | Benchmark Arroyo (all queries) | 30-40 min |
| 1.4 | Teardown Arroyo | 2 min |
| 2.1 | Deploy Flink (includes build) | 15-20 min |
| 2.2 | Test Flink (q1) | 3 min |
| 2.3 | Benchmark Flink (all queries) | 30-40 min |
| 2.4 | Teardown Flink | 2 min |
| **Total** | | **~90-120 min** |

---

## Notes

- **Kafka remains running** between systems for faster switching
- **Docker images persist** on nodes for faster re-deployment
- **Results are timestamped** - you can run multiple benchmarks
- **CPU sampling** happens every 5 seconds during measurement
- **Decimal throughput** is supported for low-output queries (q5, q7)

Good luck with your benchmarks! 🚀
