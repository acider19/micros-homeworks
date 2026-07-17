#!/usr/bin/env bash
set -euo pipefail

CERTS_DIR="$(cd "$(dirname "$0")/../../src/certs" && pwd)"
CA_DAYS=3650
CERT_DAYS=365
REDIS_NODES=("192.168.139.86" "192.168.139.59" "192.168.139.161")

echo "=== Генерация CA ==="
mkdir -p "$CERTS_DIR"

openssl genrsa -out "$CERTS_DIR/ca.key" 4096
openssl req -x509 -new -nodes -key "$CERTS_DIR/ca.key" \
  -sha256 -days "$CA_DAYS" \
  -out "$CERTS_DIR/ca.crt" \
  -subj "/CN=Redis Cluster CA/O=Netology"

echo "=== Генерация серверных сертификатов ==="
for IP in "${REDIS_NODES[@]}"; do
  NODE_DIR="$CERTS_DIR/$IP"
  mkdir -p "$NODE_DIR"

  openssl genrsa -out "$NODE_DIR/redis.key" 2048

  cat > "$NODE_DIR/redis.cnf" <<EOF
[req]
distinguished_name = req_dn
req_extensions = v3_req
prompt = no

[req_dn]
CN = $IP
O = Netology

[v3_req]
subjectAltName = @alt_names

[alt_names]
IP.1 = $IP
DNS.1 = redis-$IP
DNS.2 = localhost
EOF

  openssl req -new \
    -key "$NODE_DIR/redis.key" \
    -out "$NODE_DIR/redis.csr" \
    -config "$NODE_DIR/redis.cnf"

  openssl x509 -req \
    -in "$NODE_DIR/redis.csr" \
    -CA "$CERTS_DIR/ca.crt" \
    -CAkey "$CERTS_DIR/ca.key" \
    -CAcreateserial \
    -out "$NODE_DIR/redis.crt" \
    -days "$CERT_DAYS" \
    -sha256 \
    -extensions v3_req \
    -extfile "$NODE_DIR/redis.cnf"

  echo "  Сертификат для $IP готов"
done

echo "=== Копирование на VM ==="
for IP in "${REDIS_NODES[@]}"; do
  VM_NAME="redis-vm$(echo "$IP" | grep -o '[0-9]*$')"
  echo "  → $VM_NAME ($IP)"

  orb -m "$VM_NAME" sudo mkdir -p /etc/redis/tls
  orb -m "$VM_NAME" sudo cp "$CERTS_DIR/ca.crt" /etc/redis/tls/
  orb -m "$VM_NAME" sudo cp "$CERTS_DIR/$IP/redis.crt" /etc/redis/tls/
  orb -m "$VM_NAME" sudo cp "$CERTS_DIR/$IP/redis.key" /etc/redis/tls/
  orb -m "$VM_NAME" sudo chmod 600 /etc/redis/tls/redis.key

  for PORT in 6379 6380; do
    orb -m "$VM_NAME" redis-cli -p "$PORT" CONFIG SET tls-cert-file /etc/redis/tls/redis.crt
    orb -m "$VM_NAME" redis-cli -p "$PORT" CONFIG SET tls-key-file /etc/redis/tls/redis.key
    orb -m "$VM_NAME" redis-cli -p "$PORT" CONFIG SET tls-ca-cert-file /etc/redis/tls/ca.crt
    orb -m "$VM_NAME" redis-cli -p "$PORT" CONFIG SET tls-auth-clients optional
    orb -m "$VM_NAME" redis-cli -p "$PORT" CONFIG REWRITE
  done

  echo "    TLS настроен на $IP:6379,6380"
done

echo ""
echo "=== Готово ==="
echo "Сертификаты в $CERTS_DIR/"
echo "TLS активирован на всех нодах"
echo ""
echo "Envoy с TLS: docker compose -f docker-compose-tls.yaml up -d"
