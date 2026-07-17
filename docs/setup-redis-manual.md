# Настройка Redis на VM

Пошаговая инструкция по развёртыванию Redis Cluster на трёх OrbStack VM.

---

## Шаг 1: Создание VM

Создаём три Ubuntu VM через OrbStack:

```bash
orb create ubuntu redis-vm1
orb create ubuntu redis-vm2
orb create ubuntu redis-vm3
```

Проверяем, что все три запущены:

```bash
orb list
```

Узнаём IP каждой VM:

```bash
orb info redis-vm1 | grep -i ip
orb info redis-vm2 | grep -i ip
orb info redis-vm3 | grep -i ip
```

IP понадобятся для настройки кластера и Envoy.

---

## Шаг 2: Установка Redis

Подключаемся к каждой VM и ставим Redis:

```bash
for vm in redis-vm1 redis-vm2 redis-vm3; do
  orb -m "$vm" sudo apt-get update
  orb -m "$vm" sudo apt-get install -y redis-server
done
```

Проверяем, что Redis установлен:

```bash
for vm in redis-vm1 redis-vm2 redis-vm3; do
  orb -m "$vm" redis-server --version
done
```

---

## Шаг 3: Конфигурация

На каждой VM нужно создать **два** конфига — для мастера (порт 6379) и реплики (порт 6380).

### Конфиг мастера (redis-6379.conf)

```bash
orb -m redis-vm1 sudo tee /etc/redis/redis-6379.conf <<EOF
port 6379
bind 0.0.0.0
protected-mode no
cluster-enabled yes
cluster-config-file nodes-6379.conf
cluster-node-timeout 5000
appendonly yes
EOF
```

### Конфиг реплики (redis-6380.conf)

```bash
orb -m redis-vm1 sudo tee /etc/redis/redis-6380.conf <<EOF
port 6380
bind 0.0.0.0
protected-mode no
cluster-enabled yes
cluster-config-file nodes-6380.conf
cluster-node-timeout 5000
appendonly yes
EOF
```

### Ключевые параметры

| Параметр | Значение | Зачем |
|---|---|---|
| `port` | 6379 / 6380 | Два инстанса на одной VM |
| `bind 0.0.0.0` | — | Слушаем на всех интерфейсах (иначе VM не видят друг друга) |
| `protected-mode no` | — | Разрешаем внешние подключения без пароля |
| `cluster-enabled yes` | — | Включаем режим кластера |
| `cluster-config-file` | nodes-6379.conf | Файл с информацией о кластере (создаётся автоматически) |
| `cluster-node-timeout` | 5000 | Таймаут: через 5 сек без ответа нода считается упавшей |
| `appendonly yes` | — | AOF-персистенция (данные не теряются при рестарте) |

---

## Шаг 4: Запуск Redis

Запускаем по два инстанса на каждой VM:

```bash
for vm in redis-vm1 redis-vm2 redis-vm3; do
  orb -m "$vm" sudo redis-server /etc/redis/redis-6379.conf --daemonize yes
  orb -m "$vm" sudo redis-server /etc/redis/redis-6380.conf --daemonize yes
done
```

Проверяем, что все 6 нод отвечают:

```bash
for vm in redis-vm1 redis-vm2 redis-vm3; do
  echo "=== $vm ==="
  orb -m "$vm" redis-cli -p 6379 ping
  orb -m "$vm" redis-cli -p 6380 ping
done
```

Ожидаемый вывод: `PONG` на каждом порту.

---

## Шаг 5: Создание кластера

Теперь нужно сказать Redis-нодам: «вы — кластер, вот ваши соседи».

### Через скрипт

```bash
bash scripts/create-cluster-vm.sh
```

### Руками

Узнаём IP каждой VM:

```bash
VM1_IP=$(orb info redis-vm1 | grep -i ip | awk '{print $2}')
VM2_IP=$(orb info redis-vm2 | grep -i ip | awk '{print $2}')
VM3_IP=$(orb info redis-vm3 | grep -i ip | awk '{print $2}')
```

Создаём кластер (запускаем с любой VM):

```bash
orb -m redis-vm1 redis-cli --cluster create \
  "$VM1_IP":6379 \
  "$VM2_IP":6379 \
  "$VM3_IP":6379 \
  "$VM1_IP":6380 \
  "$VM2_IP":6380 \
  "$VM3_IP":6380 \
  --cluster-replicas 1
```

Флаг `--cluster-replicas 1` означает: «у каждого мастера должна быть одна реплика». Redis сам определит, какая нода будет мастером, а какая — репликой.

На вопрос `Can I set the above configuration?` отвечаем `yes`.

---

## Шаг 6: Проверка

```bash
# Состояние кластера
orb -m redis-vm1 redis-cli -p 6379 cluster info | grep cluster_state
# cluster_state:ok

# Все ноды
orb -m redis-vm1 redis-cli -p 6379 cluster nodes
```

Ожидаемый вывод `cluster nodes` — 6 строк, каждая с флагами `master` или `slave`:

```
<id1> <VM1-IP>:6379@16379 master - 0 ... 0-5460
<id2> <VM2-IP>:6379@16379 master - 0 ... 5461-10922
<id3> <VM3-IP>:6379@16379 master - 0 ... 10923-16383
<id4> <VM1-IP>:6380@16380 slave <id3> ...
<id5> <VM2-IP>:6380@16380 slave <id1> ...
<id6> <VM3-IP>:6380@16380 slave <id2> ...
```

### Тест записи (напрямую через кластер)

```bash
orb -m redis-vm1 redis-cli -c -p 6379 SET test:hello "world"
# → OK

orb -m redis-vm1 redis-cli -c -p 6379 GET test:hello
# → "world"
```

Флаг `-c` включает кластерный режим — клиент сам обрабатывает `MOVED`.

---

## Шаг 7: Остановка

```bash
for vm in redis-vm1 redis-vm2 redis-vm3; do
  orb -m "$vm" sudo killall redis-server
done
```

Если нужно полностью удалить VM:

```bash
orb delete redis-vm1 --yes
orb delete redis-vm2 --yes
orb delete redis-vm3 --yes
```
