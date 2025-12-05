
## Назначение

Репозиторий содержит полный набор Kubernetes-манифестов и вспомогательных файлов для демонстрационного приложения `demo-app`, развёртываемого по GitOps-подходу в окружении `dev`. Все ресурсы применяются в фиксированном порядке скриптом `deploy.sh`, чтобы гарантировать успешную и воспроизводимую доставку.

## Структура репозитория

```
gitops_manifests/
├── deploy.sh              # Автоматизация создания кластера kind и применения манифестов
├── manifests/
│   ├── namespace-dev.yaml # Пространство имён dev
│   ├── secret.yaml        # docker-registry-secret с учётными данными registry
│   ├── configmap.yaml     # Конфигурация приложения (порт, логирование)
│   ├── deployment.yaml    # Deployment demo-app с probes и ресурсами
│   ├── service.yaml       # NodePort сервис demo-app (30080)
│   └── kind-config.yaml   # Топология локального kind-кластера
└── README.md
```

## Что разворачивается

| Ресурс | Файл | Ключевые детали |
| --- | --- | --- |
| Namespace | `manifests/namespace-dev.yaml` | Создаёт окружение `dev` |
| Secret | `manifests/secret.yaml` | Docker registry (`kubernetes.io/dockerconfigjson`) и `imagePullSecrets` для подов |
| ConfigMap | `manifests/configmap.yaml` | Конфигурация Spring Boot: порт, имя приложения, уровни логирования |
| Deployment | `manifests/deployment.yaml` | 3 реплики контейнера `gitopsitmo/gitops-app:0.1.0`, probes `/healthz`, requests/limits, `zone=dev` nodeSelector |
| Service | `manifests/service.yaml` | `NodePort` 30080 → контейнер 8080 |
| kind cluster | `manifests/kind-config.yaml` | 1 control-plane + 2 worker ноды, проброшенный порт 30080, метки `zone=prod/dev` |

## Локальный старт

1. Клонируйте репозиторий и перейдите в каталог `gitops_manifests`.
2. Убедитесь, что переменные в `deploy.sh` соответствуют вашим ожиданиям (например, имя кластера kind).
3. Запустите скрипт:

```bash
./deploy.sh
```

Скрипт:

1. Создаёт (или повторно использует) кластер kind с конфигурацией `manifests/kind-config.yaml`.
2. Применяет манифесты в правильном порядке: namespace → secret → configmap → deployment → service.
3. Ждёт готовности всех подов.
4. Показывает статус ресурсов и даёт URL `http://localhost:30080`.
5. Выводит подсказки по работе с Lens и полезные команды `kubectl`.


