#!/bin/bash
# Проверка Redis Cluster — подключение через -c (кластерный режим)

set -e

echo "=== Запись данных ==="
redis-cli -c -p 7001 SET session:user123 "active"
redis-cli -c -p 7001 SET session:user456 "active"
redis-cli -c -p 7001 SET session:user789 "active"

echo ""
echo "=== Чтение данных ==="
redis-cli -c -p 7001 GET session:user123
redis-cli -c -p 7001 GET session:user456
redis-cli -c -p 7001 GET session:user789

echo ""
echo "=== Статус кластера ==="
redis-cli -p 7001 cluster nodes

echo ""
echo "=== Остановка кластера ==="
cd src_2 && docker compose down -v
