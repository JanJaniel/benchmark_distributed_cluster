# Schritt-für-Schritt Setup-Anleitung für Distributed Arroyo Cluster

## Vorbereitung (auf deinem lokalen Rechner)

1. **Repository vorbereiten**
   ```bash
   cd /home/jan/BA/Bachelorarbeit
   git add benchmark_distributed_cluster
   git commit -m "Add distributed cluster configuration"
   git push
   ```

## Phase 1: SSH-Keys einrichten (von b1pc10 aus)

1. **Auf b1pc10 (Controller) einloggen**
   ```bash
   ssh jan@192.168.2.70
   ```

2. **Repository clonen**
   ```bash
   cd ~
   git clone [dein-repo-url] Bachelorarbeit
   cd Bachelorarbeit/benchmark_distributed_cluster
   ```

3. **SSH-Key generieren (falls noch nicht vorhanden)**
   ```bash
   ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
   ```

4. **SSH-Keys auf alle Worker kopieren**
   ```bash
   # Für jeden Worker (b1pc11 bis b1pc19)
   ssh-copy-id jan@192.168.2.71
   ssh-copy-id jan@192.168.2.72
   ssh-copy-id jan@192.168.2.73
   ssh-copy-id jan@192.168.2.74
   ssh-copy-id jan@192.168.2.75
   ssh-copy-id jan@192.168.2.76
   ssh-copy-id jan@192.168.2.77
   ssh-copy-id jan@192.168.2.78
   ssh-copy-id jan@192.168.2.79
   ```

5. **SSH-Verbindungen testen**
   ```bash
   # Test-Script ausführen
   ./scripts/setup-ssh-keys.sh
   ```

## Phase 2: Docker Installation

### Option A: Automatisch (empfohlen)
Von b1pc10 aus:
```bash
cd ~/Bachelorarbeit/benchmark_distributed_cluster
./scripts/setup-cluster.sh
# Das Script installiert Docker automatisch auf allen Nodes
```

### Option B: Manuell auf jedem Pi
Falls das automatische Setup nicht funktioniert:

1. **Auf jedem Pi einzeln einloggen und Docker installieren**
   ```bash
   # Auf b1pc10
   ssh jan@192.168.2.70
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker jan
   exit

   # Auf b1pc11  
   ssh jan@192.168.2.71
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker jan
   exit

   # ... und so weiter für alle Pis
   ```

2. **WICHTIG: Nach Docker Installation ausloggen und wieder einloggen!**

## Phase 3: Cluster Setup (von b1pc10)

1. **Repository auf alle Nodes kopieren**
   ```bash
   cd ~/Bachelorarbeit/benchmark_distributed_cluster

   # Auf alle Worker kopieren
   for i in {71..79}; do
     echo "Copying to 192.168.2.$i"
     ssh jan@192.168.2.$i "mkdir -p ~/Bachelorarbeit"
     scp -r ~/Bachelorarbeit/benchmark_distributed_cluster jan@192.168.2.$i:~/Bachelorarbeit/
   done
   ```

2. **Docker Images bauen**
   
   Auf b1pc10 (Controller):
   ```bash
   cd ~/Bachelorarbeit/benchmark_distributed_cluster
   docker build -t arroyo-pi:latest -f docker/arroyo/Dockerfile docker/arroyo
   docker build -t nexmark-generator:latest -f docker/nexmark-generator/Dockerfile docker/nexmark-generator
   ```

   Auf allen Workern (parallel):
   ```bash
   for i in {71..79}; do
     ssh jan@192.168.2.$i "cd ~/Bachelorarbeit/benchmark_distributed_cluster && docker build -t arroyo-pi:latest -f docker/arroyo/Dockerfile docker/arroyo" &
   done
   wait
   ```

3. **Controller Services starten (auf b1pc10)**
   ```bash
   cd ~/Bachelorarbeit/benchmark_distributed_cluster/deploy/controller
   docker compose up -d
   ```

4. **Warten bis Services bereit sind**
   ```bash
   sleep 30
   # Check ob Arroyo läuft
   curl http://localhost:8000/health
   ```

5. **Kafka Topics erstellen**
   ```bash
   docker exec kafka kafka-topics --create --if-not-exists \
     --bootstrap-server localhost:19092 \
     --topic nexmark-person \
     --partitions 9 \
     --replication-factor 1

   docker exec kafka kafka-topics --create --if-not-exists \
     --bootstrap-server localhost:19092 \
     --topic nexmark-auction \
     --partitions 9 \
     --replication-factor 1

   docker exec kafka kafka-topics --create --if-not-exists \
     --bootstrap-server localhost:19092 \
     --topic nexmark-bid \
     --partitions 9 \
     --replication-factor 1
   ```

6. **Worker starten**
   ```bash
   # Worker 1 (b1pc11)
   ssh jan@192.168.2.71 "cd ~/Bachelorarbeit/benchmark_distributed_cluster/deploy/worker && NODE_ID=worker-1 WORKER_ID=1 docker compose up -d"

   # Worker 2 (b1pc12)
   ssh jan@192.168.2.72 "cd ~/Bachelorarbeit/benchmark_distributed_cluster/deploy/worker && NODE_ID=worker-2 WORKER_ID=2 docker compose up -d"

   # ... und so weiter, oder automatisiert:
   for i in {1..9}; do
     ip=$((70 + i))
     ssh jan@192.168.2.$ip "cd ~/Bachelorarbeit/benchmark_distributed_cluster/deploy/worker && NODE_ID=worker-$i WORKER_ID=$i docker compose up -d"
   done
   ```

## Phase 4: Erster Test mit Query 1

1. **Nexmark Generator starten**
   ```bash
   cd ~/Bachelorarbeit/benchmark_distributed_cluster
   docker run -d --rm \
     --name nexmark-generator \
     --network host \
     -e KAFKA_BROKER=192.168.2.70:9094 \
     -e EVENTS_PER_SECOND=10000 \
     -e TOTAL_EVENTS=100000 \
     -v $(pwd)/nexmark-generator-deterministic.py:/app/generator/nexmark-generator-deterministic.py:ro \
     nexmark-generator:latest
   ```

2. **Query 1 submitten**
   ```bash
   # Query lesen und anpassen
   QUERY=$(cat queries/nexmark_q1.sql | sed 's/localhost:9092/192.168.2.70:9094/g')

   # Query via API submitten
   curl -X POST http://localhost:8001/api/v1/pipelines \
     -H "Content-Type: application/json" \
     -d @- <<EOF
   {
     "name": "nexmark_q1_test",
     "query": "$QUERY",
     "parallelism": 9
   }
   EOF
   ```

3. **Status überprüfen**
   - Web UI: http://192.168.2.70:8000
   - Workers Status: `curl http://192.168.2.70:8001/api/v1/workers`
   - Pipeline Status: `curl http://192.168.2.70:8001/api/v1/pipelines`

4. **Metriken monitoren**
   ```bash
   cd ~/Bachelorarbeit/benchmark_distributed_cluster/monitoring
   python3 collect-metrics.py
   ```

## Troubleshooting

### Docker Permission Error
```bash
# Neu einloggen oder:
newgrp docker
```

### Services nicht erreichbar
```bash
# Logs auf Controller checken
docker compose logs -f

# Worker Logs checken
ssh jan@192.168.2.71 "cd ~/Bachelorarbeit/benchmark_distributed_cluster/deploy/worker && docker compose logs"
```

### Worker verbindet sich nicht
- Firewall prüfen
- IPs in docker-compose.yml prüfen
- Controller gRPC Port (9190) muss erreichbar sein

## Cleanup (nach Tests)
```bash
cd ~/Bachelorarbeit/benchmark_distributed_cluster
./scripts/teardown-cluster.sh
```