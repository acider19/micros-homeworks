#!/bin/bash
# Проверка развёрнутого Kubernetes-кластера (задача 1)

set -e

echo "=== Применение манифестов ==="
kubectl apply -f src_1/

echo ""
echo "=== Поды ==="
kubectl get pods -o wide

echo ""
echo "=== Сервисы ==="
kubectl get svc

echo ""
echo "=== Ingress ==="
kubectl get ingress

echo ""
echo "=== Потребление ресурсов ==="
kubectl top pods

echo ""
echo "=== HPA ==="
kubectl get hpa

echo ""
echo "=== Логи security-service ==="
kubectl logs -l app=security --tail=20
