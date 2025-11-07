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

# Функция для проверки существования ресурса
check_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if [ -n "$namespace" ]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null
    else
        kubectl get "$resource_type" "$resource_name" &>/dev/null
    fi
}

# Шаг 0: Проверка и создание Kind кластера
echo -e "${YELLOW}[0/6] Проверка Kind кластера...${NC}"

# Проверяем, доступен ли kubectl и есть ли подключение к кластеру
if ! kubectl cluster-info &>/dev/null; then
    echo "  Кластер не найден или недоступен"
    
    # Проверяем, установлен ли kind
    if ! command -v kind &> /dev/null; then
        echo -e "${RED}  ✗ Kind не установлен${NC}"
        echo "  Установите Kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi
    
    # Проверяем, существует ли кластер
    if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        echo "  Кластер ${KIND_CLUSTER_NAME} существует, но недоступен"
        echo "  Попытка подключения..."
        # Kind автоматически настраивает kubeconfig, просто проверяем еще раз
        sleep 2
    else
        echo "  Создание Kind кластера..."
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
            echo "  Попытка $i/10..."
            sleep 2
        done
    fi
    
    # Финальная проверка
    if kubectl cluster-info &>/dev/null; then
        echo -e "${GREEN}  ✓ Кластер создан и доступен${NC}"
        echo -e "${GREEN}  ✓ Кластер должен быть виден в Lens${NC}\n"
    else
        echo -e "${RED}  ✗ Не удалось подключиться к кластеру${NC}"
        echo "  Проверьте: kubectl cluster-info"
        exit 1
    fi
else
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
    echo -e "${GREEN}  ✓ Кластер доступен: $CLUSTER_NAME${NC}\n"
fi

# Шаг 1: Удаление существующих ресурсов (если есть)
echo -e "${YELLOW}[1/6] Очистка предыдущего запуска...${NC}"

if check_resource deployment demo-app "$NAMESPACE"; then
    echo "  Удаление Deployment..."
    kubectl delete -f "$MANIFESTS_DIR/deployment.yaml" --ignore-not-found=true
    sleep 2
fi

if check_resource service demo-app "$NAMESPACE"; then
    echo "  Удаление Service..."
    kubectl delete -f "$MANIFESTS_DIR/service.yaml" --ignore-not-found=true
    sleep 1
fi

if check_resource configmap app-config "$NAMESPACE"; then
    echo "  Удаление ConfigMap..."
    kubectl delete -f "$MANIFESTS_DIR/configmap.yaml" --ignore-not-found=true
    sleep 1
fi

if check_resource secret docker-registry-secret "$NAMESPACE"; then
    echo "  Удаление Secret..."
    kubectl delete -f "$MANIFESTS_DIR/secret.yaml" --ignore-not-found=true
    sleep 1
fi

if check_resource namespace "$NAMESPACE"; then
    echo "  Удаление Namespace..."
    kubectl delete -f "$MANIFESTS_DIR/namespace-dev.yaml" --ignore-not-found=true
    sleep 2
fi

echo -e "${GREEN}  ✓ Очистка завершена${NC}\n"

# Шаг 2: Применение манифестов в правильном порядке
echo -e "${YELLOW}[2/6] Применение манифестов...${NC}"

echo "  Создание Namespace..."
kubectl apply -f "$MANIFESTS_DIR/namespace-dev.yaml"
sleep 1

echo "  Создание Secret..."
kubectl apply -f "$MANIFESTS_DIR/secret.yaml"
sleep 1

echo "  Создание ConfigMap..."
kubectl apply -f "$MANIFESTS_DIR/configmap.yaml"
sleep 1

echo "  Создание Deployment..."
kubectl apply -f "$MANIFESTS_DIR/deployment.yaml"
sleep 2

echo "  Создание Service..."
kubectl apply -f "$MANIFESTS_DIR/service.yaml"
sleep 1

echo -e "${GREEN}  ✓ Все манифесты применены${NC}\n"

# Шаг 3: Ожидание готовности подов
echo -e "${YELLOW}[3/6] Ожидание запуска подов...${NC}"

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

# Шаг 4: Проверка статуса
echo -e "${YELLOW}[4/6] Проверка статуса ресурсов...${NC}\n"

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

# Шаг 5: Информация о доступе
echo -e "\n${YELLOW}[5/6] Информация о доступе:${NC}\n"

NODEPORT=$(kubectl get svc demo-app -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "не найден")

if [ "$NODEPORT" != "не найден" ]; then
    echo -e "${GREEN}  ✓ Service доступен на NodePort: $NODEPORT${NC}"
    echo -e "  Приложение будет доступно по адресу: ${GREEN}http://localhost:$NODEPORT${NC}"
else
    echo -e "${RED}  ✗ NodePort не найден${NC}"
fi

echo ""
echo -e "${GREEN}=== Развертывание завершено ===${NC}\n"

# Шаг 6: Информация о Lens
echo -e "${YELLOW}[6/6] Информация о Lens:${NC}\n"
echo -e "${GREEN}  ✓ Кластер должен быть автоматически обнаружен в Lens${NC}"
echo -e "  Если кластер не виден в Lens:"
echo -e "    1. Убедитесь, что Lens запущен"
echo -e "    2. Проверьте контекст: kubectl config current-context"
echo -e "    3. В Lens: File > Add Cluster > или выберите из списка доступных контекстов"
echo ""

# Полезные команды
echo -e "${YELLOW}Полезные команды:${NC}"
echo "  Просмотр логов:     kubectl logs -n $NAMESPACE -l app=demo-app -f"
echo "  Статус подов:       kubectl get pods -n $NAMESPACE"
echo "  Описание пода:      kubectl describe pod -n $NAMESPACE -l app=demo-app"
echo "  Удаление всего:     kubectl delete namespace $NAMESPACE"
echo "  Удаление кластера:  kind delete cluster --name $KIND_CLUSTER_NAME"
echo ""

