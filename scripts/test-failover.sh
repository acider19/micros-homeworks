#!/usr/bin/env bash
set -euo pipefail

ENVOY_PORT=6390
TEST_KEY="test:failover:$(date +%s)"
TEST_VALUE="hello-failover-$(date +%s)"

echo "=== Тест failover Redis Cluster ==="

echo ""
echo "1. Записываем тестовые данные через Envoy"
VAL=$(redis-cli -p "$ENVOY_PORT" SET "$TEST_KEY" "$TEST_VALUE")
echo "   SET $TEST_KEY $TEST_VALUE → $VAL"

echo ""
echo "2. Читаем данные обратно"
VAL=$(redis-cli -p "$ENVOY_PORT" GET "$TEST_KEY")
echo "   GET $TEST_KEY → $VAL"

echo ""
echo "3. Определяем шард и мастера"
SLOT=$(orb -m redis-vm1 bash -c "redis-cli -p 6379 CLUSTER KEYSLOT $TEST_KEY")
echo "   Слот ключа: $SLOT"

echo ""
echo "   Мастеры кластера:"
orb -m redis-vm1 bash -c "redis-cli -p 6379 CLUSTER NODES" | grep "master" | while IFS= read -r line; do
  ADDR=$(echo "$line" | awk '{print $2}')
  SLOTS=$(echo "$line" | awk '{print $NF}')
  echo "     $ADDR → $SLOTS"
done

echo ""
echo "4. Определяем мастера шарда с нашим ключом"
MASTER_LINE=$(orb -m redis-vm1 bash -c "redis-cli -p 6379 CLUSTER NODES" | grep "master" | while IFS= read -r line; do
  SLOTS=$(echo "$line" | awk '{print $NF}')
  if echo "$SLOTS" | grep -qE "\[?[0-9]+-[0-9]+\]?"; then
    START=$(echo "$SLOTS" | grep -oE '[0-9]+' | head -1)
    END=$(echo "$SLOTS" | grep -oE '[0-9]+' | tail -1)
    if [ "$SLOT" -ge "$START" ] && [ "$SLOT" -le "$END" ]; then
      echo "$line"
      break
    fi
  fi
done)

MASTER_ADDR=$(echo "$MASTER_LINE" | awk '{print $2}')
MASTER_HOST=$(echo "$MASTER_ADDR" | cut -d: -f1)
MASTER_PORT=$(echo "$MASTER_ADDR" | cut -d: -f2 | cut -d@ -f1)

# Определяем номер VM по IP
for i in 1 2 3; do
  VM_IP=$(orb info "redis-vm$i" 2>&1 | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)
  if [ "$VM_IP" = "$MASTER_HOST" ]; then
    VM_NUM=$i
    break
  fi
done

echo "   Мастер: $MASTER_HOST:$MASTER_PORT (redis-vm$VM_NUM)"

echo ""
echo "5. Убиваем мастера"
orb -m "redis-vm$VM_NUM" bash -c "sudo kill -9 \$(pgrep -f 'redis-server.*:$MASTER_PORT' | head -1)"
echo "   Killed redis-server on $MASTER_HOST:$MASTER_PORT"

echo ""
echo "6. Ждём 10 сек для failover..."
sleep 10

echo ""
echo "7. Проверяем доступность кластера"
CLUSTER_STATE=$(orb -m redis-vm1 bash -c "redis-cli -p 6379 CLUSTER INFO" 2>/dev/null | grep cluster_state)
echo "   $CLUSTER_STATE"

echo ""
echo "8. Читаем данные через Envoy после failover"
VAL=$(redis-cli -p "$ENVOY_PORT" GET "$TEST_KEY" 2>/dev/null || echo "ERROR")
if [ "$VAL" = "$TEST_VALUE" ]; then
  echo "   GET $TEST_KEY → $VAL ✓ Данные доступны!"
else
  echo "   GET $TEST_KEY → $VAL ✗ Данные не читаются"
fi

echo ""
echo "9. Восстанавливаем убитого мастера как реплику"
echo "   Запускаем redis-server на $MASTER_HOST:$MASTER_PORT..."
orb -m "redis-vm$VM_NUM" sudo redis-server /etc/redis/"$MASTER_PORT"/redis.conf --daemonize yes

echo "   Ждём 5 сек..."
sleep 5

NEW_LINE=$(orb -m redis-vm1 bash -c "redis-cli -p 6379 CLUSTER NODES" | grep "$MASTER_HOST" | head -1)
echo "   Нода после восстановления: $NEW_LINE"

echo ""
echo "=== Failover тест завершён ==="
echo ""
echo "Очистка: redis-cli -p $ENVOY_PORT DEL $TEST_KEY"
redis-cli -p "$ENVOY_PORT" DEL "$TEST_KEY" >/dev/null 2>&1 || true
