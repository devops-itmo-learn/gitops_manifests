# Argo CD
## Требования
- Argo CD 2.3.0+, 2.2.6+, 2.1.11+ (ArgoCD 2.1.9, 2.1.10, 2.2.4, 2.2.5 не совместимы с helm-secrets).
- helm-secrets 3.9.x или выше.
## Установка
Для кастомизации ресурсов описанных ниже, Argo CD будет установлен с помощью создания хельм чарта, где [основной](https://argoproj.github.io/argo-helm/), будет установлен в качестве саб чарта и его параметры будут модифицироваться в values.yaml

<details>
<summary>Chart.yaml</summary>
<p>

```yaml
apiVersion: v2
name: argo-cd
version: 0.1.0
dependencies:
  - name: argo-cd
    version: 5.46.8
    repository: https://argoproj.github.io/argo-helm
```
</details>

# Argo CD repo-server
[argocd-repo-server](https://argo-cd.readthedocs.io/en/stable/operator-manual/server-commands/argocd-repo-server/) - это внутренний сервис, ответственный за генерацию k8s манифестов. Поэтому, нужно его кастомизировать для корректной работы плагина helm-secrets.

## Кастомизация значений
### Mount volumes
Сначала, нужно указать тома, куда будут устанавливаться зависимости и куда в последствии будет монтироваться секрет для передачи приватного ключа.


<details>
<summary>values.yaml</summary>
<p>

```yaml
repoServer:
  volumes:
    - name: gitops-tools
      emptyDir: {}
    - name: helm-secrets-private-keys
      secret:
        secretName: helm-secrets-private-keys
  volumeMounts:
    - mountPath: /gitops-tools
      name: gitops-tools
    - mountPath: /usr/local/sbin/helm
      subPath: helm
      name: gitops-tools
    - mountPath: /helm-secrets-private-keys/
      name: helm-secrets-private-keys

```
</details>

### Переменные окружения
Далее создаем нужные для корректной работы helm-secrets переменные окружения, а так же переменные согласно [правилам безопасности](https://github.com/jkroepke/helm-secrets/wiki/Security-in-shared-environments)

<details>
<summary>values.yaml</summary>
<p>

```yaml
repoServer:
  env:
    - name: HELM_PLUGINS
      value: /gitops-tools/helm-plugins/
    - name: HELM_SECRETS_CURL_PATH
      value: /gitops-tools/curl
    - name: HELM_SECRETS_SOPS_PATH
      value: /gitops-tools/sops
    - name: HELM_SECRETS_VALS_PATH
      value: /gitops-tools/vals
    - name: HELM_SECRETS_AGE_PATH
      value: /gitops-tools/age
    - name: HELM_SECRETS_KUBECTL_PATH
      value: /gitops-tools/kubectl
    - name: HELM_SECRETS_BACKEND
      value: sops
    - name: HELM_SECRETS_VALUES_ALLOW_SYMLINKS
      value: "false"
    - name: HELM_SECRETS_VALUES_ALLOW_ABSOLUTE_PATH
      value: "true"
    - name: HELM_SECRETS_VALUES_ALLOW_PATH_TRAVERSAL
      value: "false"
    - name: HELM_SECRETS_WRAPPER_ENABLED
      value: "true"
    - name: HELM_SECRETS_DECRYPT_SECRETS_IN_TMP_DIR
      value: "true"
    - name: HELM_SECRETS_HELM_PATH
      value: /usr/local/bin/helm

    - name: SOPS_AGE_KEY_FILE
      value: /helm-secrets-private-keys/key.txt

```
</details>

### Init Container
Установка всех нужных зависимостей будет осуществлятся путем модификации поля ```initContainer```, в [deployment.yaml](https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/templates/argocd-repo-server/deployment.yaml).

<details>
<summary>values.yaml</summary>
<p>

```yaml
repoServer:
  initContainers:
    - name: download-tools
      image: alpine:latest
      imagePullPolicy: IfNotPresent
      command: [sh, -euc]
      env:
        - name: HELM_SECRETS_VERSION
          value: "4.7.4"
        - name: KUBECTL_VERSION
          value: "1.34.2"
        - name: VALS_VERSION
          value: "0.42.6"
        - name: SOPS_VERSION
          value: "3.11.0"
        - name: AGE_VERSION
          value: "1.2.1"
        - name: HELM_PLUGINS
          value: /gitops-tools/helm-plugins/
        - name: HELM_SECRETS_CURL_PATH
          value: /gitops-tools/curl
        - name: HELM_SECRETS_SOPS_PATH
          value: /gitops-tools/sops
        - name: HELM_SECRETS_VALS_PATH
          value: /gitops-tools/vals
        - name: HELM_SECRETS_AGE_PATH
          value: /gitops-tools/age
        - name: HELM_SECRETS_KUBECTL_PATH
          value: /gitops-tools/kubectl
      args:
        - |
          mkdir -p "${HELM_PLUGINS}"

          export CURL_ARCH=$(uname -m | sed -e 's/x86_64/amd64/')
          wget -qO "${HELM_SECRETS_CURL_PATH}" https://github.com/moparisthebest/static-curl/releases/latest/download/curl-${CURL_ARCH}

          export GO_ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')
          wget -qO "${HELM_SECRETS_KUBECTL_PATH}" https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${GO_ARCH}/kubectl
          wget -qO "${HELM_SECRETS_SOPS_PATH}" https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${GO_ARCH}
          wget -qO- https://github.com/helmfile/vals/releases/download/v${VALS_VERSION}/vals_${VALS_VERSION}_linux_${GO_ARCH}.tar.gz | tar zxv -C "${HELM_SECRETS_VALS_PATH%/*}" vals
          wget -qO- https://github.com/jkroepke/helm-secrets/releases/download/v${HELM_SECRETS_VERSION}/helm-secrets.tar.gz | tar -C "${HELM_PLUGINS}" -xzf-
          wget -qO- "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz" | tar -xzf- --strip-components=1 -C "${HELM_SECRETS_AGE_PATH%/*}" age/age
          
          chmod +x \
            "${HELM_SECRETS_CURL_PATH}" \
            "${HELM_SECRETS_SOPS_PATH}" \
            "${HELM_SECRETS_KUBECTL_PATH}" \
            "${HELM_SECRETS_VALS_PATH}" \
            "${HELM_SECRETS_AGE_PATH}"

          cp "${HELM_PLUGINS}/helm-secrets/scripts/wrapper/helm.sh" /gitops-tools/helm
      volumeMounts:
        - mountPath: /gitops-tools
          name: gitops-tools
```
</details>

# Argo CD config map
Изначально [argocd-cm](https://github.com/argoproj/argo-cd/blob/af5f234bdbc8fd9d6dcc90d12e462316d9af32cf/docs/operator-manual/argocd-cm.yaml) поддерживает только value schemes вида http и https
```yaml
helm.valuesFileSchemes: http, https
```
Нужно добавить схемы для helm-secrets, для поддержки синтаксиса вида:

```yaml
secrets://values.secret.yaml

secrets+gpg-import:///helm-secrets-private-keys/key.asc?secrets.yaml
```

<details>
<summary>values.yaml</summary>
<p>

```yaml
configs:
  cm:
    helm.valuesFileSchemes: >-
      secrets+gpg-import, secrets+gpg-import-kubernetes,
      secrets+age-import, secrets+age-import-kubernetes,
      secrets, secrets+literal,
      https
```
</details>

# Argo CD Application
Приложение будет устанвливаться в Argo CD при помощи создания app-helm.yaml
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app
  namespace: argocd
spec:
  project: default
  source:
    chart: demo-chart
    repoURL: docker.io/gitopsitmo
    targetRevision: 0.1.0
    helm:
      valueFiles:
      - values.yaml
      - secrets://values.secret.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: helm-dev

  syncPolicy:
    automated: {}
    syncOptions:
      - CreateNamespace=true

```

# Инструкция по установке
После шагов выше, должны получится два файла

<details>
<summary>Chart.yaml</summary>
<p>

```yaml
apiVersion: v2
name: argo-cd
version: 0.1.0
dependencies:
  - name: argo-cd
    version: 5.46.8
    repository: https://argoproj.github.io/argo-helm
```
</details>

<details>
<summary>values.yaml</summary>
<p>

```yaml
argo-cd:
  configs:
    cm:
      helm.valuesFileSchemes: >-
        secrets+gpg-import, secrets+gpg-import-kubernetes,
        secrets+age-import, secrets+age-import-kubernetes,
        secrets, secrets+literal,
        https
  repoServer:
    # image:
    #   repository: gitopsitmo/argocd-helm-secrets
    #   tag: latest
    #   imagePullPolicy: IfNotPresent
    env:
      - name: HELM_PLUGINS
        value: /gitops-tools/helm-plugins/
      - name: HELM_SECRETS_CURL_PATH
        value: /gitops-tools/curl
      - name: HELM_SECRETS_SOPS_PATH
        value: /gitops-tools/sops
      - name: HELM_SECRETS_VALS_PATH
        value: /gitops-tools/vals
      - name: HELM_SECRETS_AGE_PATH
        value: /gitops-tools/age
      - name: HELM_SECRETS_KUBECTL_PATH
        value: /gitops-tools/kubectl
      - name: HELM_SECRETS_BACKEND
        value: sops
      # https://github.com/jkroepke/helm-secrets/wiki/Security-in-shared-environments
      - name: HELM_SECRETS_VALUES_ALLOW_SYMLINKS
        value: "false"
      - name: HELM_SECRETS_VALUES_ALLOW_ABSOLUTE_PATH
        value: "true"
      - name: HELM_SECRETS_VALUES_ALLOW_PATH_TRAVERSAL
        value: "false"
      - name: HELM_SECRETS_WRAPPER_ENABLED
        value: "true"
      - name: HELM_SECRETS_DECRYPT_SECRETS_IN_TMP_DIR
        value: "true"
      - name: HELM_SECRETS_HELM_PATH
        value: /usr/local/bin/helm

      - name: SOPS_AGE_KEY_FILE # For age
        value: /helm-secrets-private-keys/key.txt
    volumes:
      - name: gitops-tools
        emptyDir: {}
      # kubectl create secret generic helm-secrets-private-keys --from-file=key.asc=assets/gpg/private2.gpg
      - name: helm-secrets-private-keys
        secret:
          secretName: helm-secrets-private-keys
    volumeMounts:
      - mountPath: /gitops-tools
        name: gitops-tools
      - mountPath: /usr/local/sbin/helm
        subPath: helm
        name: gitops-tools
      - mountPath: /helm-secrets-private-keys/
        name: helm-secrets-private-keys
    initContainers:
      - name: download-tools
        image: alpine:latest
        imagePullPolicy: IfNotPresent
        command: [sh, -euc]
        env:
          - name: HELM_SECRETS_VERSION
            value: "4.7.4"
          - name: KUBECTL_VERSION
            value: "1.34.2"
          - name: VALS_VERSION
            value: "0.42.6"
          - name: SOPS_VERSION
            value: "3.11.0"
          - name: AGE_VERSION
            value: "1.2.1"
          - name: HELM_PLUGINS
            value: /gitops-tools/helm-plugins/
          - name: HELM_SECRETS_CURL_PATH
            value: /gitops-tools/curl
          - name: HELM_SECRETS_SOPS_PATH
            value: /gitops-tools/sops
          - name: HELM_SECRETS_VALS_PATH
            value: /gitops-tools/vals
          - name: HELM_SECRETS_AGE_PATH
            value: /gitops-tools/age
          - name: HELM_SECRETS_KUBECTL_PATH
            value: /gitops-tools/kubectl
        args:
          - |
            mkdir -p "${HELM_PLUGINS}"

            export CURL_ARCH=$(uname -m | sed -e 's/x86_64/amd64/')
            wget -qO "${HELM_SECRETS_CURL_PATH}" https://github.com/moparisthebest/static-curl/releases/latest/download/curl-${CURL_ARCH}

            export GO_ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')
            wget -qO "${HELM_SECRETS_KUBECTL_PATH}" https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${GO_ARCH}/kubectl
            wget -qO "${HELM_SECRETS_SOPS_PATH}" https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${GO_ARCH}
            wget -qO- https://github.com/helmfile/vals/releases/download/v${VALS_VERSION}/vals_${VALS_VERSION}_linux_${GO_ARCH}.tar.gz | tar zxv -C "${HELM_SECRETS_VALS_PATH%/*}" vals
            wget -qO- https://github.com/jkroepke/helm-secrets/releases/download/v${HELM_SECRETS_VERSION}/helm-secrets.tar.gz | tar -C "${HELM_PLUGINS}" -xzf-
            wget -qO- "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz" | tar -xzf- --strip-components=1 -C "${HELM_SECRETS_AGE_PATH%/*}" age/age
            
            chmod +x \
              "${HELM_SECRETS_CURL_PATH}" \
              "${HELM_SECRETS_SOPS_PATH}" \
              "${HELM_SECRETS_KUBECTL_PATH}" \
              "${HELM_SECRETS_VALS_PATH}" \
              "${HELM_SECRETS_AGE_PATH}"

            cp "${HELM_PLUGINS}/helm-secrets/scripts/wrapper/helm.sh" /gitops-tools/helm
        volumeMounts:
          - mountPath: /gitops-tools
            name: gitops-tools

```
</details>

После создания кластера, например

```bash
kind create cluster --config manifests/kind-config.yaml --name test
```

Нужно создать namespace argocd, в котором будут лежать все ресурсы описанные выше

```bash
kubectl create namespace argocd
```

А так же создать секрет, по лежащим локально ключам age, в примере они находятся в `$HOME/.config/sops/age/keys.txt`

```bash
kubectl -n argocd create secret generic helm-secrets-private-keys --from-file=key.txt=$HOME/.config/sops/age/keys.txt
```

Далее установка созданного чарта argocd и приминение appproject и application

```bash
helm install argo-cd manifests/argocd/argocd-chart/ -n argocd --values manifests/argocd/argocd-chart/values.yaml
```

```bash
kubectl apply -n argocd -f manifests/argocd/appproject.yaml
```

```bash
kubectl apply -n argocd -f manifests/argocd/app-helm-repo.yaml
```