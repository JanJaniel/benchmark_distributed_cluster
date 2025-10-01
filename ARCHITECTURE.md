# Distributed Cluster Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Pi1 - Controller Node                          │
│                            (192.168.2.70)                                │
│                                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  ┌────────────────┐ │
│  │   Kafka     │  │    MinIO     │  │  Arroyo    │  │    Nexmark     │ │
│  │   Broker    │  │  S3 Storage  │  │ Controller │  │   Generator    │ │
│  │   :9094     │  │    :9000     │  │   :8001    │  │                │ │
│  └──────┬──────┘  └──────┬───────┘  └─────┬──────┘  └────────┬───────┘ │
│         │                 │                 │                   │         │
│         │                 │                 │                   │         │
│  ┌──────┴─────────────────┴─────────────────┴───────────────────┴─────┐ │
│  │                         Docker Network (host)                       │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────┬───────────────────────────────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    │                     │                     │
                    │     Physical Network (192.168.2.0/24)     │
                    │                                           │
    ┌───────────────┴───┐  ┌────────────┴──┐  ┌───────────────┴───┐
    │                   │  │               │  │                   │
┌───┴────────────┐  ┌───┴────────────┐  ┌─┴─┴────────────┐  ┌───┴────────────┐
│  Pi2 - Worker 1│  │  Pi3 - Worker 2│  │ Pi4 - Worker 3 │  │Pi5-10 Workers │
│ (192.168.2.71) │  │ (192.168.2.72) │  │(192.168.2.73)  │  │(.74-.79)      │
│                │  │                │  │                │  │               │
│ ┌─────────────┐│  │ ┌─────────────┐│  │ ┌─────────────┐│  │┌─────────────┐│
│ │   Arroyo    ││  │ │   Arroyo    ││  │ │   Arroyo    ││  ││   Arroyo    ││
│ │   Worker    ││  │ │   Worker    ││  │ │   Worker    ││  ││   Worker    ││
│ │   Task      ││  │ │   Task      ││  │ │   Task      ││  ││   Task      ││
│ └─────────────┘│  │ └─────────────┘│  │ └─────────────┘│  │└─────────────┘│
└────────────────┘  └────────────────┘  └────────────────┘  └───────────────┘
```

## Data Flow

### 1. Data Generation Phase
```
Nexmark Generator (Pi1)
        │
        ├──→ Kafka Topic: nexmark-person (9 partitions)
        ├──→ Kafka Topic: nexmark-auction (9 partitions)
        └──→ Kafka Topic: nexmark-bid (9 partitions)
```

### 2. Query Distribution
```
User submits query to Arroyo Controller
        │
        ├──→ Controller creates execution plan
        ├──→ Splits query into 9 parallel subtasks
        └──→ Assigns subtasks to workers via gRPC
```

### 3. Parallel Processing
```
Worker 1: Processes partitions [0]      ─┐
Worker 2: Processes partitions [1]      ─┤
Worker 3: Processes partitions [2]      ─┤
Worker 4: Processes partitions [3]      ─┤─→ Aggregated Results
Worker 5: Processes partitions [4]      ─┤
Worker 6: Processes partitions [5]      ─┤
Worker 7: Processes partitions [6]      ─┤
Worker 8: Processes partitions [7]      ─┤
Worker 9: Processes partitions [8]      ─┘
```

### 4. State Management
```
Each Worker:
    ├──→ Local state in memory
    ├──→ Periodic checkpoints to MinIO
    └──→ Recovery from MinIO on failure
```

## Communication Patterns

### Controller ↔ Workers
- **Protocol**: gRPC (port 9190)
- **Purpose**: Task assignment, health checks, metrics
- **Direction**: Bidirectional

### Workers → Kafka
- **Protocol**: Kafka protocol (port 9094)
- **Purpose**: Consume streaming data
- **Pattern**: Each worker consumes specific partitions

### Workers → MinIO
- **Protocol**: S3 API (port 9000)
- **Purpose**: Store/retrieve checkpoints
- **Pattern**: Periodic writes, reads on recovery

## Query Execution Example

### Nexmark Q1 (Currency Conversion)
```sql
SELECT 
    auction,
    bidder,
    price * 0.85 as price_eur,
    event_time
FROM nexmark_bid
```

**Execution Plan:**
1. Controller receives query
2. Creates 9 parallel tasks (one per partition)
3. Each worker:
   - Reads from assigned Kafka partition
   - Applies currency conversion
   - Outputs results
4. Results aggregated at controller

## Scalability Characteristics

### Horizontal Scaling
- **Workers**: Add more Pis (up to partition count)
- **Partitions**: Increase for more parallelism
- **Throughput**: Linear with worker count

### Vertical Scaling
- **Memory**: Adjust Docker limits
- **CPU**: Use all cores per Pi
- **Network**: Gigabit ethernet recommended

## Fault Tolerance

### Component Failures
- **Worker failure**: Controller redistributes tasks
- **Controller failure**: Workers pause, resume on recovery
- **Kafka failure**: Buffering in workers
- **MinIO failure**: Processing continues, checkpoints fail

### Recovery Mechanisms
1. **Checkpoints**: Periodic state snapshots
2. **Exactly-once**: Kafka offset tracking
3. **Automatic restart**: Docker restart policies
4. **Health monitoring**: Built-in health checks

## Performance Considerations

### Network Bandwidth
```
Event Size: ~100 bytes
Events/sec: 50,000 total (5,556 per worker)
Network per worker: ~556 KB/s input + overhead
Total cluster network: ~5 MB/s
```

### Memory Usage
```
Controller: 
  - Arroyo: 1GB
  - Kafka: 768MB
  - MinIO: 256MB
  
Workers:
  - Arroyo: 1GB per node
  - State: Variable based on query
```

### CPU Requirements
```
Controller: 2-4 cores during operation
Workers: 1-4 cores based on query complexity
```

## Monitoring Points

1. **API Health**: http://192.168.2.70:8001/health
2. **Worker Status**: http://192.168.2.70:8001/api/v1/workers
3. **Pipeline Metrics**: http://192.168.2.70:8001/api/v1/pipelines/{id}/metrics
4. **Kafka Metrics**: JMX on port 9101
5. **System Metrics**: Docker stats on each node

## Implementation Notes

- **Controller Image**: Uses custom `arroyo-pi:latest` ARM64 image
- **Worker Images**: Use `arroyo-pi:latest` ARM64 image
- **API Port**: 8001 (not 8000) for all API calls
- **No Web UI**: In distributed mode, only API is available