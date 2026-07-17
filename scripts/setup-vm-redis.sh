#!/bin/bash
# Создание 3 OrbStack VM и установка Redis (2 инстанса на каждой)

set -e

echo "=== Создание VM ==="
orb create ubuntu redis-vm1 2>&1 | tail -1
orb create ubuntu redis-vm2 2>&1 | tail -1
orb create ubuntu redis-vm3 2>&1 | tail -1

echo ""
echo "=== Ожидание запуска VM (10 сек) ==="
sleep 10

echo ""
echo "=== Установка Redis на всех VM ==="
for vm in redis-vm1 redis-vm2 redis-vm3; do
  echo "--- $vm ---"
  orb -m $vm sudo apt update -qq 2>&1 | tail -1
  orb -m $vm sudo apt install -y -qq redis-server 2>&1 | tail -2
done

echo ""
echo "=== Настройка Redis (2 инстанса на каждой VM) ==="

# VM1: Shard1 master (:6379) + Shard2 replica (:6380)
orb -m redis-vm1 sudo bash -c 'mkdir -p /etc/redis/6379 /etc/redis/6380 /var/lib/redis/6379 /var/lib/redis/6380 /var/log/redis'
orb -m redis-vm1 sudo bash -c 'cat > /etc/redis/6379/redis.conf << EOF
protected-mode no
bind 0.0.0.0
port 6379
daemonize yes
dir /var/lib/redis/6379
dbfilename dump.rdb
cluster-enabled yes
cluster-config-file nodes-6379.conf
cluster-node-timeout 5000
appendonly yes
appendfilename appendonly-6379.aof
logfile /var/log/redis/redis-6379.log
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF'
orb -m redis-vm1 sudo bash -c 'cat > /etc/redis/6380/redis.conf << EOF
protected-mode no
bind 0.0.0.0
port 6380
daemonize yes
dir /var/lib/redis/6380
dbfilename dump.rdb
cluster-enabled yes
cluster-config-file nodes-6380.conf
cluster-node-timeout 5000
appendonly yes
appendfilename appendonly-6380.aof
logfile /var/log/redis/redis-6380.log
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF'

# VM2: Shard2 master (:6379) + Shard3 replica (:6380)
orb -m redis-vm2 sudo bash -c 'mkdir -p /etc/redis/6379 /etc/redis/6380 /var/lib/redis/6379 /var/lib/redis/6380 /var/log/redis'
orb -m redis-vm2 sudo bash -c 'cat > /etc/redis/6379/redis.conf << EOF
protected-mode no
bind 0.0.0.0
port 6379
daemonize yes
dir /var/lib/redis/6379
dbfilename dump.rdb
cluster-enabled yes
cluster-config-file nodes-6379.conf
cluster-node-timeout 5000
appendonly yes
appendfilename appendonly-6379.aof
logfile /var/log/redis/redis-6379.log
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF'
orb -m redis-vm2 sudo bash -c 'cat > /etc/redis/6380/redis.conf << EOF
protected-mode no
bind 0.0.0.0
port 6380
daemonize yes
dir /var/lib/redis/6380
dbfilename dump.rdb
cluster-enabled yes
cluster-config-file nodes-6380.conf
cluster-node-timeout 5000
appendonly yes
appendfilename appendonly-6380.aof
logfile /var/log/redis/redis-6380.log
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF'

# VM3: Shard3 master (:6379) + Shard1 replica (:6380)
orb -m redis-vm3 sudo bash -c 'mkdir -p /etc/redis/6379 /etc/redis/6380 /var/lib/redis/6379 /var/lib/redis/6380 /var/log/redis'
orb -m redis-vm3 sudo bash -c 'cat > /etc/redis/6379/redis.conf << EOF
protected-mode no
bind 0.0.0.0
port 6379
daemonize yes
dir /var/lib/redis/6379
dbfilename dump.rdb
cluster-enabled yes
cluster-config-file nodes-6379.conf
cluster-node-timeout 5000
appendonly yes
appendfilename appendonly-6379.aof
logfile /var/log/redis/redis-6379.log
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF'
orb -m redis-vm3 sudo bash -c 'cat > /etc/redis/6380/redis.conf << EOF
protected-mode no
bind 0.0.0.0
port 6380
daemonize yes
dir /var/lib/redis/6380
dbfilename dump.rdb
cluster-enabled yes
cluster-config-file nodes-6380.conf
cluster-node-timeout 5000
appendonly yes
appendfilename appendonly-6380.aof
logfile /var/log/redis/redis-6380.log
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF'

echo ""
echo "=== Запуск Redis на всех VM ==="
for vm in redis-vm1 redis-vm2 redis-vm3; do
  orb -m $vm sudo systemctl stop redis-server 2>/dev/null || true
  orb -m $vm sudo redis-server /etc/redis/6379/redis.conf
  orb -m $vm sudo redis-server /etc/redis/6380/redis.conf
done

echo ""
echo "=== Проверка PING ==="
for vm in redis-vm1 redis-vm2 redis-vm3; do
  echo -n "$vm: "
  orb -m $vm bash -c "redis-cli -p 6379 ping && redis-cli -p 6380 ping"
done

echo ""
echo "=== IP VM ==="
for vm in redis-vm1 redis-vm2 redis-vm3; do
  orb info $vm 2>&1 | grep -E "name|ipv4" | head -2
done

echo ""
echo "Готово! Теперь запустите: bash scripts/create-cluster-vm.sh"
