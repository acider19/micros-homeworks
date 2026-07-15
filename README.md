# Решение: Микросервисы: принципы

## Задача 1: API Gateway, сравнительная таблица

| Критерий | NGINX | Kong | Traefik | Envoy | AWS API Gateway |
|----------|-------|------|---------|-------|-----------------|
| Маршрутизация по конфигурации | ✓ (upstream + location) | ✓ (routes + services) | ✓ (routers + services) | ✓ (routes + clusters) | ✓ (routes) |
| Проверка аутентификации | Базовая (auth_basic) / Lua | ✓ (plugins: JWT, OAuth2, mTLS) | ✓ (middlewares: BasicAuth, ForwardAuth) | ✓ (ext_authz HTTP filter) | ✓ (authorizers, Cognito) |
| Терминация HTTPS | ✓ | ✓ | ✓ | ✓ | ✓ (управляемый) |
| Балансировка нагрузки | ✓ (round-robin, weight, least_conn) | ✓ (round-robin, consistent-hashing) | ✓ (WRR) | ✓ (circular, ring hash, random) | ✓ (управляемый) |
| Плагины/Middleware | Lua-скрипты | 100+ плагинов | Встроенные + ForwardAuth | WASM / Lua / ext_proc | Lambda, VTL-шаблоны |
| Observability | Статус-страница | Prometheus, OpenTelemetry | Prometheus, Tracing | Full observability | CloudWatch, X-Ray |
| Развёртывание | Standalone / Plus (Controller) | БД-зависимый (Postgres/Cassandra) | Автообнаружение (Docker, K8s) | Standalone / Istio | Управляемый сервис |
| Конфигурация | nginx.conf / API | Declarative (YAML) | TOML / File/Docker/K8s | xDS (JSON/YAML) | Console / TF / CloudFormation |
| Сложность эксплуатации | Низкая | Средняя | Низкая–Средняя | Высокая | Нулевая (SaaS) |
| Open Source | ✓ (BSD-2) | ✓ (Apache 2.0) | ✓ (MIT) | ✓ (Apache 2.0) | ✗ (коммерческий) |

### Выбор: NGINX (OpenResty) + Lua

Все три базовых требования (маршрутизация, аутентификация, HTTPS) закрываются «из коробки». NGINX проверен, быстр, потребляет мало памяти. Через Lua (OpenResty) можно написать любую логику аутентификации: проверку JWT, вызов security-сервиса. Конфигурация укладывается в простой nginx.conf с `proxy_pass`, `auth_request` и `ssl`. Порог входа низкий, сообщество огромное, документации много.

---

## Задача 2: Брокер сообщений, сравнительная таблица

| Критерий | RabbitMQ | Apache Kafka | NATS | Redis Streams | ZeroMQ |
|----------|----------|-------------|------|---------------|--------|
| Кластеризация | ✓ (quorum queues) | ✓ (partition replication) | ✓ (clustering + leaf nodes) | ✓ (Redis Cluster) | ✗ (нужны обёртки) |
| Хранение на диске | ✓ (durable queues) | ✓ (commit log, log segments) | ✓ (JetStream file-backed) | ✓ (AOF / RDB) | ✗ (in-memory) |
| Высокая скорость | ~50K msg/s | ~1M+ msg/s | ~10M+ msg/s | ~500K msg/s | ~10M+ msg/s |
| Форматы сообщений | Любой (текст, JSON, bin) | Любой (bin) | Любой (текст, JSON, bin) | Любой (bin) | Любой (bin) |
| Разделение прав | ✓ (vhost, RBAC через плагины) | ✓ (ACL, RBAC) | ✓ (accounts, JWT) | ✓ (ACL) | ✗ |
| Простота эксплуатации | Средняя | Высокая | Очень низкая | Низкая | Низкая |
| Семантика | Queue (point-to-point, pub/sub) | Distributed log (append-only) | Pub/Sub, Queue (JetStream) | Stream, Pub/Sub | Socket (PUSH/PULL, PUB/SUB) |
| Транзакции | ✓ | ✓ (exactly-once) | ✗ | ✓ (MULTI/EXEC) | ✗ |
| TTL сообщений | ✓ | ✓ (log compaction, retention) | ✓ (max age in JetStream) | ✓ (MAXLEN, MINID) | ✗ |

### Выбор: Apache Kafka

Kafka умеет кластеризоваться с репликацией: партиции распределяются по нодам (Leader/Follower), ISR-группа следит за целостью данных. Хранение на диске через append-only commit log с настраиваемой retention. Скорость: миллионы сообщений в секунду. Форматы любые: Avro, Protobuf, JSON, raw bytes. Разделение прав через ACL и RBAC. И есть гарантия exactly-once семантики (идемпотентные продюсеры + транзакции).

Минус: эксплуатация непростая (ZooKeeper/KRaft, партиционирование), но для крупной компании это нормальная цена.

---

## Задача 3: API Gateway, реализация на NGINX

### Архитектура

```
[Client]
    │
    ▼
[NGINX Gateway :8080 → host:80]
    │
    ├── /v1/token ──────────► [security:3000] POST /v1/token
    ├── /v1/token/validation ► [security:3000] GET /v1/token/validation
    ├── /v1/upload ──────────► [uploader:3000] POST /v1/upload
    └── /status ─────────────► [uploader:3000] GET /status
```

### Конфигурация

- [nginx.conf](homework-source/gateway/nginx.conf)
- [docker-compose.yaml](homework-source/docker-compose.yaml)

### Тестирование

```bash
# Получение токена (логин: bob, пароль: qwe123)
TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"login":"bob", "password":"qwe123"}' \
  http://localhost/v1/token)
echo "Token: $TOKEN"

# Валидация токена
curl -s -H "Authorization: Bearer $TOKEN" http://localhost/v1/token/validation

# Загрузка изображения (тестовый файл в репозитории)
RESPONSE=$(curl -s -X POST \
  -H 'Content-Type: image/png' \
  --data-binary @homework-source/test-image.png \
  http://localhost/v1/upload)
echo "Upload: $RESPONSE"

# Скачивание загруженного изображения
FILENAME=$(echo $RESPONSE | grep -o '"filename":"[^"]*"' | cut -d'"' -f4)
curl -s -o downloaded.png http://localhost/images/$FILENAME
echo "Downloaded: downloaded.png ($(wc -c < downloaded.png) bytes)"

# Проверка статуса
curl -s http://localhost/status
```
