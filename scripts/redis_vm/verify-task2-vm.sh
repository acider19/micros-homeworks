#!/bin/bash
# Проверка Redis Cluster через Envoy

set -e

echo "=== Запись данных ==="
redis-cli -p 6390 SET session:user123 "active"
redis-cli -p 6390 SET session:user456 "active"
redis-cli -p 6390 SET session:user789 "active"

echo ""
echo "=== Чтение данных ==="
redis-cli -p 6390 GET session:user123
redis-cli -p 6390 GET session:user456
redis-cli -p 6390 GET session:user789

echo ""
echo "=== Статистика Envoy ==="
curl -s 'http://localhost:9901/stats?usedonly' | grep -E "redis|cluster" | grep -v "envoyproxy"

echo ""
echo "=== Остановка ==="
cd src_2_vm && docker compose down
cd ..

echo ""
echo "Остановка Redis на VM..."
for vm in redis-vm1 redis-vm2 redis-vm3; do
  orb -m $vm sudo killall redis-server 2>/dev/null || true
done

echo "Удаление VM..."
orb delete redis-vm1 --yes 2>/dev/null || true
orb delete redis-vm2 --yes 2>/dev/null || true
orb delete redis-vm3 --yes 2>/dev/null || true

echo "Готово!"
