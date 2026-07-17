#!/bin/bash
# Создание Redis Cluster на OrbStack VM

set -e

echo "=== Получение IP VM ==="
VM1_IP=$(orb info redis-vm1 2>&1 | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)
VM2_IP=$(orb info redis-vm2 2>&1 | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)
VM3_IP=$(orb info redis-vm3 2>&1 | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)

echo "VM1: $VM1_IP"
echo "VM2: $VM2_IP"
echo "VM3: $VM3_IP"

echo ""
echo "=== Создание кластера (3 шарда × 1 реплика) ==="
orb -m redis-vm1 sudo bash -c "echo yes | redis-cli --cluster create \
  $VM1_IP:6379 $VM2_IP:6379 $VM3_IP:6379 \
  $VM3_IP:6380 $VM1_IP:6380 $VM2_IP:6380 \
  --cluster-replicas 1"

echo ""
echo "=== Статус кластера ==="
orb -m redis-vm1 bash -c "redis-cli -p 6379 cluster info"

echo ""
echo "=== Узлы кластера ==="
orb -m redis-vm1 bash -c "redis-cli -p 6379 cluster nodes"

echo ""
echo "=== Запуск Envoy ==="
cd src

# Обновляем IP в envoy.yaml
python3 -c "
import re
with open('envoy.yaml', 'r') as f:
    content = f.read()
ips = ['$VM1_IP', '$VM2_IP', '$VM3_IP']
old_ips = re.findall(r'192\.168\.\d+\.\d+', content)
for i, old in enumerate(old_ips):
    if i < len(ips):
        content = content.replace(old, ips[i], 1)
with open('envoy.yaml', 'w') as f:
    f.write(content)
print('IP обновлены:', ips)
"

docker compose up -d
cd ..

sleep 3

echo ""
echo "=== Проверка через Envoy ==="
redis-cli -p 6390 SET session:user123 "active"
redis-cli -p 6390 GET session:user123

echo ""
echo "Готово! Envoy слушает на порту 6390"
