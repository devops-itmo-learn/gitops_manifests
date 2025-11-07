#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

MANIFESTS_DIR="manifests"
NAMESPACE="dev"
KIND_CLUSTER_NAME="kind"
KIND_CONFIG="$MANIFESTS_DIR/kind-config.yaml"

echo -e "${GREEN}=== GitOps Deployment Script ===${NC}\n"

# Шаг 0: Удаление и создание Kind кластера
echo -e "${YELLOW}[0/5] Управление Kind кластером...${NC}"

# Проверяем, установлен ли kind
if ! command -v kind &> /dev/null; then
    echo -e "${RED}  ✗ Kind не установлен${NC}"
    echo "  Установите Kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Всегда удаляем кластер, если он существует
if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    echo "  Удаление существующего кластера ${KIND_CLUSTER_NAME}..."
    kind delete cluster --name "$KIND_CLUSTER_NAME" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Кластер удален${NC}"
    sleep 2
fi

# Создаем новый кластер
echo "  Создание нового Kind кластера..."
if [ -f "$KIND_CONFIG" ]; then
    kind create cluster --name "$KIND_CLUSTER_NAME" --config "$KIND_CONFIG"
else
    echo -e "${YELLOW}  ⚠ Файл конфигурации $KIND_CONFIG не найден, создание кластера с настройками по умолчанию${NC}"
    kind create cluster --name "$KIND_CLUSTER_NAME"
fi

# Ждем, пока кластер станет доступен
echo "  Ожидание готовности кластера..."
sleep 5

# Проверяем подключение
for i in {1..10}; do
    if kubectl cluster-info &>/dev/null; then
        break
    fi
    echo "  Попытка подключения $i/10..."
    sleep 2
done

# Финальная проверка
if kubectl cluster-info &>/dev/null; then
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "$KIND_CLUSTER_NAME")
    echo -e "${GREEN}  ✓ Кластер создан и доступен: $CLUSTER_NAME${NC}"
    echo -e "${GREEN}  ✓ Кластер должен быть виден в Lens${NC}\n"
else
    echo -e "${RED}  ✗ Не удалось подключиться к кластеру${NC}"
    echo "  Проверьте: kubectl cluster-info"
    exit 1
fi

# Шаг 1: Применение манифестов в правильном порядке
echo -e "${YELLOW}[1/5] Применение манифестов...${NC}"

echo "  Применение Namespace..."
kubectl apply -f "$MANIFESTS_DIR/namespace-dev.yaml"
sleep 1

echo "  Применение Secret..."
kubectl apply -f "$MANIFESTS_DIR/secret.yaml"
sleep 1

echo "  Применение ConfigMap..."
kubectl apply -f "$MANIFESTS_DIR/configmap.yaml"
sleep 1

echo "  Применение Deployment..."
kubectl apply -f "$MANIFESTS_DIR/deployment.yaml"
sleep 2

echo "  Применение Service..."
kubectl apply -f "$MANIFESTS_DIR/service.yaml"
sleep 1

echo -e "${GREEN}  ✓ Все манифесты применены${NC}\n"

# Шаг 2: Ожидание готовности подов
echo -e "${YELLOW}[2/5] Ожидание запуска подов...${NC}"

# Ждем максимум 60 секунд
TIMEOUT=60
ELAPSED=0
INTERVAL=3

while [ $ELAPSED -lt $TIMEOUT ]; do
    READY=$(kubectl get deployment demo-app -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment demo-app -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
        echo -e "${GREEN}  ✓ Все поды готовы ($READY/$DESIRED)${NC}\n"
        break
    fi
    
    echo "  Ожидание... ($READY/$DESIRED готовы, прошло ${ELAPSED}с)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}  ⚠ Таймаут ожидания готовности подов${NC}\n"
fi

# Шаг 3: Проверка статуса
echo -e "${YELLOW}[3/5] Проверка статуса ресурсов...${NC}\n"

kubectl get all -n "$NAMESPACE"

echo ""

# Проверка статуса подов
POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app=demo-app -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
if echo "$POD_STATUS" | grep -q "Running"; then
    echo -e "${GREEN}  ✓ Поды запущены${NC}"
else
    echo -e "${YELLOW}  ⚠ Поды еще не в статусе Running${NC}"
    echo "  Проверьте логи: kubectl logs -n $NAMESPACE -l app=demo-app"
fi

# Шаг 4: Информация о доступе
echo -e "\n${YELLOW}[4/5] Информация о доступе:${NC}\n"

NODEPORT=$(kubectl get svc demo-app -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "не найден")

if [ "$NODEPORT" != "не найден" ]; then
    echo -e "${GREEN}  ✓ Service доступен на NodePort: $NODEPORT${NC}"
    echo -e "  Приложение будет доступно по адресу: ${GREEN}http://localhost:$NODEPORT${NC}"
else
    echo -e "${RED}  ✗ NodePort не найден${NC}"
fi

echo ""
echo -e "${GREEN}=== Развертывание завершено ===${NC}\n"

# Шаг 5: Информация о Lens
echo -e "${YELLOW}[5/5] Информация о Lens:${NC}\n"
echo -e "${GREEN}  ✓ Кластер должен быть автоматически обнаружен в Lens${NC}"
echo -e "  Если кластер не виден в Lens:"
echo -e "    1. Убедитесь, что Lens запущен"
echo -e "    2. Проверьте контекст: kubectl config current-context"
echo -e "    3. Вставьте конфиг в Lens: kubectl config view --minify --raw"
echo ""

# Полезные команды
echo -e "${YELLOW}Полезные команды:${NC}"
echo "  Просмотр логов:     kubectl logs -n $NAMESPACE -l app=demo-app -f"
echo "  Статус подов:       kubectl get pods -n $NAMESPACE"
echo "  Описание пода:      kubectl describe pod -n $NAMESPACE -l app=demo-app"
echo "  Удаление всего:     kubectl delete namespace $NAMESPACE"
echo "  Удаление кластера:  kind delete cluster --name $KIND_CLUSTER_NAME"
echo ""

