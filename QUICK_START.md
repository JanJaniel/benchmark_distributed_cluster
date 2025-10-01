# Quick Start - Die wichtigsten Befehle

## Schritt 1: Auf Controller (b1pc10) einloggen
```bash
ssh picocluster@192.168.2.70
cd ~/Bachelorarbeit/benchmark_distributed_cluster
```

## Schritt 2: SSH-Keys einrichten (einmalig)
```bash
# SSH Key generieren
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

# Auf alle Worker kopieren (Password wird gefragt)
for i in {71..79}; do ssh-copy-id picocluster@192.168.2.$i; done
```

## Schritt 3: Docker auf allen Pis installieren (einmalig)
```bash
# Auf Controller
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker picocluster
exit

# Neu einloggen und dann auf allen Workern installieren
ssh picocluster@192.168.2.70
for i in {71..79}; do
  ssh picocluster@192.168.2.$i "curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker picocluster"
done
```

## Schritt 4: Repository auf alle Nodes kopieren
```bash
# Von Controller aus
for i in {71..79}; do
  ssh picocluster@192.168.2.$i "mkdir -p ~/Bachelorarbeit"
  scp -r ~/Bachelorarbeit/benchmark_distributed_cluster picocluster@192.168.2.$i:~/Bachelorarbeit/
done
```

## Schritt 5: Cluster starten
```bash
# Docker Images bauen (auf Controller)
cd ~/Bachelorarbeit/benchmark_distributed_cluster
docker build -t arroyo-pi:latest -f docker/arroyo/Dockerfile docker/arroyo

# Controller Services starten
cd deploy/controller
docker compose up -d

# Warten
sleep 30

# Worker starten (alle auf einmal)
cd ~/Bachelorarbeit/benchmark_distributed_cluster
for i in {1..9}; do
  ip=$((70 + i))
  ssh picocluster@192.168.2.$ip "cd ~/Bachelorarbeit/benchmark_distributed_cluster/deploy/worker && NODE_ID=worker-$i WORKER_ID=$i docker compose up -d"
done
```

## Schritt 6: Query 1 testen
```bash
cd ~/Bachelorarbeit/benchmark_distributed_cluster
./scripts/test-query1.sh
```

## Wichtige URLs
- Arroyo Web UI: http://192.168.2.70:8000
- MinIO Console: http://192.168.2.70:9001 (minioadmin/minioadmin)

## Status prüfen
```bash
# Controller Status
docker ps

# Worker Status (z.B. für Worker 1)
ssh picocluster@192.168.2.71 "docker ps"

# Arroyo Cluster Status
curl http://192.168.2.70:8001/api/v1/workers | jq
```

## Logs anschauen
```bash
# Controller Logs
cd ~/Bachelorarbeit/benchmark_distributed_cluster/deploy/controller
docker compose logs -f arroyo-controller

# Worker Logs (z.B. Worker 1)
ssh picocluster@192.168.2.71 "docker logs -f arroyo-worker-worker-1"
```

## Alles stoppen
```bash
cd ~/Bachelorarbeit/benchmark_distributed_cluster
./scripts/teardown-cluster.sh
```