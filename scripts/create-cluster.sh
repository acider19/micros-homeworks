#!/bin/bash
# Создание Redis Cluster — 3 шарда × (1 мастер + 1 реплика) = 6 нод

set -e

echo "=== Запуск всех нод ==="
cd src_2 && docker compose up -d
cd ..

echo ""
echo "=== Ожидание запуска (5 сек) ==="
sleep 5

echo ""
echo "=== Получение IP нод в Docker-сети ==="
IP_S1=$(docker inspect src_2-shard1-master-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
IP_S2=$(docker inspect src_2-shard2-master-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
IP_S3=$(docker inspect src_2-shard3-master-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
IP_R1=$(docker inspect src_2-shard1-replica-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
IP_R2=$(docker inspect src_2-shard2-replica-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
IP_R3=$(docker inspect src_2-shard3-replica-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

echo "Shard1 master: $IP_S1"
echo "Shard2 master: $IP_S2"
echo "Shard3 master: $IP_S3"
echo "Shard1 replica: $IP_R1"
echo "Shard2 replica: $IP_R2"
echo "Shard3 replica: $IP_R3"

echo ""
echo "=== Создание кластера (изнутри контейнера) ==="
docker exec src_2-shard1-master-1 sh -c "echo yes | redis-cli --cluster create $IP_S1:6379 $IP_S2:6379 $IP_S3:6379 $IP_R1:6379 $IP_R2:6379 $IP_R3:6379 --cluster-replicas 1"

echo ""
echo "=== Статус кластера ==="
redis-cli -p 7001 cluster info

echo ""
echo "=== Узлы кластера ==="
redis-cli -p 7001 cluster nodes
