# Мониторинг

## Стек

| Компонент | Роль | Порт |
|---|---|---|
| Prometheus | Сбор и хранение метрик | 9090 |
| Grafana | Визуализация, дашборды, алерты | 3000 |
| redis_exporter | Экспорт метрик Redis в формат Prometheus | 9121/9122 |

---

## Запуск

Redis exporters подключаются к VM по IP. Перед запуском узнай IP мастер-ноды:

```bash
VM1_IP=$(orb info redis-vm1 2>&1 | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)

cd src/monitoring
REDIS_MASTER_ADDR="redis://$VM1_IP:6379" \
REDIS_REPLICA_ADDR="redis://$VM1_IP:6380" \
docker compose up -d
```

Проверяем:

```bash
docker compose ps
# prometheus    Up
# grafana       Up
# redis-exporter-master   Up
# redis-exporter-replica  Up
```

---

## Доступ

| Сервис | URL | Логин |
|---|---|---|
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | — |
| Envoy metrics | http://localhost:9901/stats | — |

---

## Prometheus

### Конфигурация (`src/monitoring/prometheus.yml`)

```yaml
scrape_configs:
  - job_name: envoy
    metrics_path: /stats
    params:
      format: [prometheus]
    static_configs:
      - targets: ["host.docker.internal:9901"]

  - job_name: redis
    static_configs:
      - targets: ["redis-exporter-master:9121"]
      - targets: ["redis-exporter-replica:9122"]
```

Envoy отдаёт метрики на `:9901/stats`. Redis Exporter подключается к Redis и экспортит метрики в формате Prometheus.

### Проверка targets

Открой http://localhost:9090/targets — все target должны быть в статусе UP.

### Частые проблемы

| Проблема | Решение |
|---|---|
| Envoy DOWN, "unsupported character in float" | Нужен `params: format: [prometheus]` в prometheus.yml |
| Redis exporter DOWN, "connection refused" | Добавить `--web.listen-address=:9122` если порт отличается от 9121 |
| Envoy DOWN, "404 Not Found" | Проверить `metrics_path: /stats` |

---

## Grafana

### Дашборд Envoy Redis Proxy

Открой Grafana → Dashboards → Envoy Redis Proxy.

Панели:

| Панель | Что показывает | PromQL |
|---|---|---|
| Total Requests/sec | Общий трафик | `rate(envoy_cluster_redis_cluster_upstream_rq_total[1m])` |
| Success (2xx) | Успешные запросы | `rate(envoy_cluster_redis_cluster_upstream_rq_xx[1m])` |
| Retries | Перенаправления MOVED/ASK | `rate(envoy_cluster_redis_cluster_upstream_rq_retry[1m])` |
| Active Connections | Активные соединения | `envoy_cluster_redis_cluster_upstream_cx_active` |
| Healthy Hosts | Здоровые ноды | `envoy_cluster_redis_cluster_health_flags_healthy` |

### Дашборд Redis Cluster

Открой Grafana → Dashboards → Redis Cluster.

Панели:

| Панель | Что показывает | PromQL |
|---|---|---|
| Ops/sec | Операции в секунду | `rate(redis_commands_processed_total[1m])` |
| Memory Usage | Потребление памяти | `redis_memory_used_bytes` |
| Connected Clients | Подключённые клиенты | `redis_connected_clients` |
| Hit Rate | Процент попаданий в кэш | `redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)` |
| Key Expirations | Истёкшие ключи | `rate(redis_expired_keys_total[1m])` |

---

## Добавление нового Redis Exporter

Если нужно мониторить ещё один инстанс Redis, добавь в `src/monitoring/docker-compose.yaml`:

```yaml
  redis-exporter-new:
    image: oliver006/redis_exporter:v1.61.0
    command:
      - "--redis.addr=redis://<VM-IP>:<PORT>"
      - "--redis.password=redis-secret"
    ports:
      - "9123:9123"
```

И в `src/monitoring/prometheus.yml`:

```yaml
  - job_name: redis
    static_configs:
      - targets: ["redis-exporter-new:9123"]
```

---

## Остановка

```bash
cd src/monitoring
docker compose down
```
