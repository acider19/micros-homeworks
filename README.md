# Решение: Микросервисы: масштабирование

## Задача 1: Кластеризация, Kubernetes

### Выбор: Kubernetes (K8s)

Kubernetes это стандарт де-факто для оркестрации контейнеров в микросервисной архитектуре.

### Соответствие требованиям

| Требование | Реализация в Kubernetes |
|-----------|------------------------|
| Поддержка контейнеров | Pod как минимальная единица деплоя, поддержка Docker, containerd, CRI-O |
| Обнаружение сервисов и маршрутизация | Service (ClusterIP, NodePort, LoadBalancer) + Ingress Controller + CoreDNS |
| Горизонтальное масштабирование | `kubectl scale --replicas=N` + Deployment |
| Автоматическое масштабирование | HorizontalPodAutoscaler (HPA), работает на основе CPU/RAM/custom metrics |
| Разделение ресурсов (внешние/внутренние) | Ingress для внешнего трафика + Service ClusterIP для внутреннего; NetworkPolicy |
| Конфигурация через ENV + секреты | ConfigMap (переменные) + Secrets (пароли, ключи); envFrom, volumeMounts |

### Архитектура кластера

```
                    ┌─────────────────────────────────┐
                    │        External Traffic          │
                    └─────────────┬───────────────────┘
                                  │
                    ┌─────────────▼───────────────────┐
                    │    Ingress Controller (NGINX)    │
                    └─────────────┬───────────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
    ┌─────────▼─────────┐ ┌──────▼──────────┐ ┌──────▼──────────┐
    │   Service: API    │ │ Service: Auth   │ │ Service: Order  │
    │   (ClusterIP)     │ │ (ClusterIP)     │ │ (ClusterIP)     │
    └─────────┬─────────┘ └──────┬──────────┘ └──────┬──────────┘
              │                   │                   │
    ┌─────────▼─────────┐ ┌──────▼──────────┐ ┌──────▼──────────┐
    │ Deployment: API   │ │ Deployment: Auth│ │ Deployment: Order│
    │ ┌───┐ ┌───┐ ┌───┐│ │ ┌───┐ ┌───┐    │ │ ┌───┐ ┌───┐     │
    │ │ P │ │ P │ │ P ││ │ │ P │ │ P │    │ │ │ P │ │ P │     │
    │ └───┘ └───┘ └───┘│ │ └───┘ └───┘    │ │ └───┘ └───┘     │
    └───────────────────┘ └────────────────┘ └─────────────────┘
              │                   │                   │
    ┌─────────▼─────────┐ ┌──────▼──────────┐ ┌──────▼──────────┐
    │  ConfigMap +      │ │  ConfigMap +    │ │  ConfigMap +    │
    │  Secrets          │ │  Secrets        │ │  Secrets        │
    └───────────────────┘ └─────────────────┘ └─────────────────┘
```

### Пример Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: security-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: security
  template:
    metadata:
      labels:
        app: security
    spec:
      containers:
        - name: security
          image: security-service:latest
          ports:
            - containerPort: 5000
          envFrom:
            - configMapRef:
                name: security-config
            - secretRef:
                name: security-secrets
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

### HPA (автоматическое масштабирование)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: security-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: security-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### Ingress (внешний доступ)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-gateway
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /v1
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 80
```

### Обоснование выбора

Kubernetes поддерживает все требования «из коробки» и работает в любом облаке: AWS (EKS), GCP (GKE), Azure (AKS) или on-premise. Экосистема большая: Helm, Operators, Service Mesh (Istio), GitOps (ArgoCD). Проект под эгидой CNCF, его поддерживают все крупные вендоры.

---

## Задача 2: Распределённый кеш, Redis Cluster

### Архитектура Redis Cluster (3 шарда × 3 реплики = 9 нод)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Redis Cluster                            │
│                                                                 │
│  Shard 1 (0-5460)          Shard 2 (5461-10922)   Shard 3 (10923-16383) │
│  ┌──────────────┐          ┌──────────────┐        ┌──────────────┐ │
│  │  Master-1    │          │  Master-2    │        │  Master-3    │ │
│  │  (slot 0-5460)│         │ (slot 5461-10922)│    │(slot 10923-16383)│ │
│  └──────┬───────┘          └──────┬───────┘        └──────┬───────┘ │
│         │ replication            │ replication            │ replication │
│  ┌──────▼───────┐          ┌──────▼───────┐        ┌──────▼───────┐ │
│  │  Replica-1a  │          │  Replica-2a  │        │  Replica-3a  │ │
│  └──────────────┘          └──────────────┘        └──────────────┘ │
│  ┌──────────────┐          ┌──────────────┐        ┌──────────────┐ │
│  │  Replica-1b  │          │  Replica-2b  │        │  Replica-3b  │ │
│  └──────────────┘          └──────────────┘        └──────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Конфигурация кластера

```yaml
# docker-compose.yaml
version: '3.8'

x-redis-common: &redis-common
  image: redis:7-alpine
  command: >
    redis-server
    --cluster-enabled yes
    --cluster-config-file nodes.conf
    --cluster-node-timeout 5000
    --appendonly yes
    --appendfsync everysec
    --maxmemory 256mb
    --maxmemory-policy allkeys-lru

services:
  # Shard 1
  redis-master-1:
    <<: *redis-common
    ports:
      - "7001:6379"
    volumes:
      - redis-master-1-data:/data

  redis-replica-1a:
    <<: *redis-common
    ports:
      - "7011:6379"
    volumes:
      - redis-replica-1a-data:/data
    depends_on:
      - redis-master-1

  redis-replica-1b:
    <<: *redis-common
    ports:
      - "7012:6379"
    volumes:
      - redis-replica-1b-data:/data
    depends_on:
      - redis-master-1

  # Shard 2
  redis-master-2:
    <<: *redis-common
    ports:
      - "7002:6379"
    volumes:
      - redis-master-2-data:/data

  redis-replica-2a:
    <<: *redis-common
    ports:
      - "7021:6379"
    volumes:
      - redis-replica-2a-data:/data
    depends_on:
      - redis-master-2

  redis-replica-2b:
    <<: *redis-common
    ports:
      - "7022:6379"
    volumes:
      - redis-replica-2b-data:/data
    depends_on:
      - redis-master-2

  # Shard 3
  redis-master-3:
    <<: *redis-common
    ports:
      - "7003:6379"
    volumes:
      - redis-master-3-data:/data

  redis-replica-3a:
    <<: *redis-common
    ports:
      - "7031:6379"
    volumes:
      - redis-replica-3a-data:/data
    depends_on:
      - redis-master-3

  redis-replica-3b:
    <<: *redis-common
    ports:
      - "7032:6379"
    volumes:
      - redis-replica-3b-data:/data
    depends_on:
      - redis-master-3

volumes:
  redis-master-1-data:
  redis-replica-1a-data:
  redis-replica-1b-data:
  redis-master-2-data:
  redis-replica-2a-data:
  redis-replica-2b-data:
  redis-master-3-data:
  redis-replica-3a-data:
  redis-replica-3b-data:
```

### Создание кластера

```bash
# Запустить все ноды
docker compose up -d

# Создать кластер (6 master-нод: 3 шарда × 1 мастер)
redis-cli --cluster create \
  redis-master-1:6379 redis-master-2:6379 redis-master-3:6379 \
  redis-replica-1a:6379 redis-replica-2a:6379 redis-replica-3a:6379 \
  --cluster-replicas 1

# Проверить статус кластера
redis-cli -p 7001 cluster info
redis-cli -p 7001 cluster nodes
```

### Проверка работы

```bash
# Подключение к кластеру (с -c для кластерного режима)
redis-cli -c -p 7001

# Записать данные (автоматическое распределение по слотам)
> SET session:user123 "active"
> SET session:user456 "active"
> SET session:user789 "active"

# Проверить, на каком шарде данные
> CLUSTER KEYSLOT session:user123
> CLUSTER KEYSLOT session:user456
> CLUSTER KEYSLOT session:user789

# Проверить распределение слотов
> CLUSTER SLOTS
```

### Ключевые особенности

Всего 16384 слота, распределённых между 3 шардами: [0-5460], [5461-10922], [10923-16383]. При падении мастера replica автоматически продвигается в master. Маршрутизация ключей идёт через CRC16 хеш-функцию. Клиент запоминает распределение слотов и обращается напрямую к нужному шарду.
