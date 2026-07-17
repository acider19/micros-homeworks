# TLS: шифрование трафика

## Зачем TLS

Redis по умолчанию ходит в открытом виде. Любой в сети может перехватить пароли, данные, команды. TLS решает это — шифрует всё между клиентом и Envoy, а также между Envoy и Redis.

---

## Архитектура с TLS

```
Клиент → :6391 (TLS) → Envoy → :6379 (TLS) → Redis
```

Envoy выступает терминатором TLS:
- Клиент подключается по TLS на порт 6391
- Envoy завершает TLS, читает команду Redis
- Envoy подключается по TLS к Redis-ноде
- Ответ возвращается клиенту

---

## Шаг 1: Генерация сертификатов

### Через скрипт

```bash
bash scripts/setup-tls.sh
```

Скрипт делает:
1. Генерирует CA (Certificate Authority) — корневой сертификат доверия
2. Для каждой VM генерирует серверный сертификат (с IP-адресом в SAN)
3. Копирует сертификаты на VM в `/etc/redis/tls/`
4. Настраивает Redis на использование TLS

### Руками

#### Создаём CA

```bash
mkdir -p src/certs
cd src/certs

# Генерируем ключ CA
openssl genrsa -out ca.key 4096

# Создаём самоподписанный сертификат CA
openssl req -x509 -new -nodes -key ca.key \
  -sha256 -days 3650 \
  -out ca.crt \
  -subj "/CN=Redis Cluster CA/O=Netology"
```

#### Для каждой VM (пример для VM1)

```bash
VM1_IP="192.168.139.86"  # замени на реальный IP

mkdir -p "$VM1_IP"

# Генерируем ключ сервера
openssl genrsa -out "$VM1_IP/redis.key" 2048

# Создаём конфиг с SAN (Subject Alternative Name)
cat > "$VM1_IP/redis.cnf" <<EOF
[req]
distinguished_name = req_dn
req_extensions = v3_req
prompt = no

[req_dn]
CN = $VM1_IP
O = Netology

[v3_req]
subjectAltName = @alt_names

[alt_names]
IP.1 = $VM1_IP
DNS.1 = localhost
EOF

# Создаём CSR (Certificate Signing Request)
openssl req -new \
  -key "$VM1_IP/redis.key" \
  -out "$VM1_IP/redis.csr" \
  -config "$VM1_IP/redis.cnf"

# Подписываем сертификат CA
openssl x509 -req \
  -in "$VM1_IP/redis.csr" \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out "$VM1_IP/redis.crt" \
  -days 365 \
  -sha256 \
  -extensions v3_req \
  -extfile "$VM1_IP/redis.cnf"
```

Повторить для VM2 и VM3, заменив `VM1_IP` на соответствующий IP.

---

## Шаг 2: Копирование сертификатов на VM

```bash
for VM_NAME in redis-vm1 redis-vm2 redis-vm3; do
  VM_IP=$(orb info "$VM_NAME" | grep -i ip | awk '{print $2}')

  orb -m "$VM_NAME" sudo mkdir -p /etc/redis/tls
  orb -m "$VM_NAME" sudo cp src/certs/ca.crt /etc/redis/tls/
  orb -m "$VM_NAME" sudo cp "src/certs/$VM_IP/redis.crt" /etc/redis/tls/
  orb -m "$VM_NAME" sudo cp "src/certs/$VM_IP/redis.key" /etc/redis/tls/
  orb -m "$VM_NAME" sudo chmod 600 /etc/redis/tls/redis.key
done
```

---

## Шаг 3: Настройка Redis на TLS

На каждой VM, для каждого порта (6379 и 6380):

```bash
for PORT in 6379 6380; do
  orb -m redis-vm1 redis-cli -p "$PORT" CONFIG SET tls-cert-file /etc/redis/tls/redis.crt
  orb -m redis-vm1 redis-cli -p "$PORT" CONFIG SET tls-key-file /etc/redis/tls/redis.key
  orb -m redis-vm1 redis-cli -p "$PORT" CONFIG SET tls-ca-cert-file /etc/redis/tls/ca.crt
  orb -m redis-vm1 redis-cli -p "$PORT" CONFIG SET tls-auth-clients optional
  orb -m redis-vm1 redis-cli -p "$PORT" CONFIG REWRITE
done
```

`tls-auth-clients optional` — разрешаем подключения без клиентского сертификата (для простоты).

---

## Шаг 4: Настройка Envoy с TLS

Envoy подключается к Redis по TLS. Конфиг: `src/envoy-tls.yaml`.

Ключевое отличие от обычного конфига — `transport_socket`:

```yaml
clusters:
- name: redis_cluster_tls
  transport_socket:
    name: envoy.transport_sockets.tls
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
      sni: redis-cluster
  cluster_type:
    name: envoy.clusters.redis
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.clusters.redis.v3.RedisClusterConfig
      cluster_refresh_rate: 1s
      cluster_refresh_timeout: 3s
  ...
```

`UpstreamTlsContext` говорит Envoy: «подключайся к Redis по TLS».

---

## Шаг 5: Запуск Envoy с TLS

```bash
cd src
docker compose -f docker-compose-tls.yaml up -d
```

---

## Шаг 6: Проверка

```bash
# Через Envoy (без TLS на клиенте)
redis-cli -p 6390 SET tls:test "works"
# → OK

redis-cli -p 6390 GET tls:test
# → "works"
```

Проверить, что Redis действительно использует TLS:

```bash
orb -m redis-vm1 redis-cli -p 6379 CONFIG GET tls-port
# tls-port 6379
```
