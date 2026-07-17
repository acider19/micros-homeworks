# Тест Failover

## Что происходит при падении мастера

Redis Cluster использует Gossip-протокол для обмена состоянием. Когда мастер не отвечает дольше `cluster-node-timeout` (5 сек по умолчанию), кластер:

1. Помечает мастера как `fail` в своей таблице
2. Реплика этого шарда проводит выборы (election)
3. Реплика становится новым мастером
4. Кластер обновляет таблицу слотов

Envoy автоматически опрашивает кластер (`cluster_refresh_rate: 1s`) и обновляет свою таблицу. Клиент вообще ничего не замечает.

---

## Ручной тест

### Шаг 1: Записываем данные

```bash
redis-cli -p 6390 SET failover:test "important-data"
# → OK
```

### Шаг 2: Определяем, какой шард и мастер

```bash
# Узнаём слот ключа (выполняем на VM, не через Envoy)
orb -m redis-vm1 bash -c "redis-cli -p 6379 CLUSTER KEYSLOT failover:test"
# → 4778

# Смотрим, какой мастер отвечает за этот слот
orb -m redis-vm1 bash -c "redis-cli -p 6379 CLUSTER NODES" | grep master
```

Из вывода `CLUSTER NODES` находим ноду, чей диапазон слотов включает 4778. Запоминаем её IP и порт.

### Шаг 3: Убиваем мастера

```bash
# Замени на реальный IP и VM
orb -m redis-vm1 sudo kill -9 $(pgrep -f 'redis-server.*:6379')
```

### Шаг 4: Ждём failover

```bash
sleep 10
```

Пять секунд — таймаут кластера, ещё пять — на сам election и обновление таблицы.

### Шаг 5: Проверяем кластер

```bash
redis-cli -p 6390 CLUSTER INFO | grep cluster_state
# cluster_state:ok
```

Если `cluster_state:fail` — что-то пошло не так. Проверяем `CLUSTER NODES`: все ли ноды видят друг друга.

### Шаг 6: Читаем данные

```bash
redis-cli -p 6390 GET failover:test
# → "important-data"
```

Данные доступны — реплика подхватила роль мастера.

### Шаг 7: Восстанавливаем убитого мастера

```bash
# Запускаем Redis обратно как реплику
orb -m redis-vm1 sudo redis-server /etc/redis/redis-6379.conf --daemonize yes
```

Redis автоматически присоединится к кластеру как реплика. Проверяем:

```bash
redis-cli -p 6390 CLUSTER NODES
```

---

## Автоматический тест

Скрипт `scripts/test-failover.sh` делает всё вышеперечисленное автоматически:

```bash
bash scripts/test-failover.sh
```

Что делает скрипт:
1. Записывает тестовый ключ через Envoy
2. Определяет какая VM является мастером шарда
3. Убивает Redis-процесс на этой VM
4. Ждёт 10 секунд
5. Проверяет, что кластер в состоянии `ok`
6. Читает данные — они должны быть доступны
7. Восстанавливает убитого мастера как реплику

---

## Что смотреть в логах

Если failover не работает, проверяем:

```bash
# Логи Redis на новом мастере
orb -m redis-vm2 redis-cli -p 6379 CONFIG GET logfile
orb -m redis-vm2 sudo tail -50 /var/log/redis/redis.log

# Состояние кластера
redis-cli -p 6390 CLUSTER NODES | grep -E "master|slave|fail"
```

Типичные проблемы:
- `cluster_node_timeout` слишком мал — кластер не успевает определить падение
- Сетевая проблема между VM — Gossip-пакеты не доходят
- Все мастера на одной VM — при падении VM теряется весь шард
