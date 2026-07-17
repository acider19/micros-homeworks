# Настройка Envoy

Пошаговая инструкция по настройке Envoy как прокси для Redis Cluster.

---

## Зачем Envoy

Redis Cluster работает через слоты. Если клиент отправляет запрос на не тот шард, Redis отвечает `MOVED` и клиент должен переподключиться. Обычные балансировщики (HAProxy, nginx) не понимают этот протокол — они просто пробрасывают `MOVED` клиенту.

Envoy работает иначе:
-他知道, какие слоты на каких серверах
- При `MOVED` сам перенаправляет запрос
- Клиент получает `OK` и не знает про кластер

---

## Конфигурация Envoy

Основной файл: `src/envoy.yaml`

### Listener (слушатель)

```yaml
static_resources:
  listeners:
  - name: redis_listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 6390         # сюда подключается клиент
    filter_chains:
    - filters:
      - name: envoy.filters.network.redis_proxy
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.redis_proxy.v3.RedisProxy
          stat_prefix: redis_proxy
          settings:
            op_timeout: 5s
            enable_redirection: true   # Envoy сам обрабатывает MOVED/ASK
          prefix_routes:
            catch_all_route:
              cluster: redis_cluster
```

Ключевые моменты:

| Параметр | Значение | Зачем |
|---|---|---|
| `port_value: 6390` | Порт Envoy | Клиент подключается сюда |
| `enable_redirection: true` | Включить обработку MOVED | Без этого MOVED уходит клиенту |
| `op_timeout: 5s` | Таймаут операции | Если Redis не ответил за 5 сек |

### Cluster (кластер бэкендов)

```yaml
  clusters:
  - name: redis_cluster
    connect_timeout: 3s
    cluster_type:
      name: envoy.clusters.redis      # вот это ключевое
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.clusters.redis.v3.RedisClusterConfig
        cluster_refresh_rate: 30s     # как часто опрашивать CLUSTER SLOTS
    load_assignment:
      cluster_name: redis_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: <VM1-IP>     # seed-ноды
                port_value: 6379
        - endpoint:
            address:
              socket_address:
                address: <VM2-IP>
                port_value: 6379
        - endpoint:
            address:
              socket_address:
                address: <VM3-IP>
                port_value: 6379
```

На что обратить внимание:

- `cluster_type: envoy.clusters.redis` — без этого Envoy думает, что это обычный TCP-бэкенд
- `cluster_refresh_rate: 30s` — Envoy опрашивает `CLUSTER SLOTS` каждые 30 секунд
- Seed-ноды — три мастера. Envoy подключается к ним и через `CLUSTER SLOTS` узнаёт обо всём кластере

### Admin (метрики)

```yaml
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
```

Метрики доступны на `http://localhost:9901/stats`.

---

## Запуск

### Через Docker Compose

```bash
cd src
docker compose up -d
```

### Проверка, что Envoy запущен

```bash
docker compose -f src/docker-compose.yaml ps
# Должен быть Up

curl -s http://localhost:9901/ready
# should be: LIVE
```

### Тест прозрачного проксирования

```bash
# Записываем — клиент не знает про кластер
redis-cli -p 6390 SET session:user123 "active"
# → OK

# Читаем
redis-cli -p 6390 GET session:user123
# → "active"

# Пробуем ключ, который попадёт в другой шард
redis-cli -p 6390 SET session:user456 "active"
# → OK (Envoy перенаправил на правильный шард)
```

### Что происходит при SET

1. Клиент отправляет `SET session:user123 "active"` на `localhost:6390` (Envoy)
2. Envoy считает хеш ключа, определяет слот
3. Смотрит в таблицу: «этот слот на VM2:6379»
4. Перенаправляет запрос на VM2
5. VM2 сохраняет данные, отвечает `OK`
6. Envoy пробрасывает `OK` клиенту
7. Клиент видит `OK` и не знает, что данные на VM2

---

## Просмотр метрик

```bash
# Все Redis-метрики
curl -s 'http://localhost:9901/stats?usedonly' | grep redis

# Ключевые:
# redis.redis_proxy.command.set.success  — успешные SET
# redis.redis_proxy.command.get.success  — успешные GET
# cluster.redis_cluster.membership_total — сколько нод нашёл Envoy (6)
```

---

## Остановка

```bash
cd src
docker compose down
```
