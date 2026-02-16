# Phase 08: Kubernetes 배포

## 상태: 완료

docker-compose 기반 로컬 환경을 Kubernetes 매니페스트(Kustomize)로 전환하여 클라우드 배포 가능 상태를 만들었다.

---

## 구현 결과

### 매니페스트 통계

| 항목 | 수량 |
|------|------|
| 총 YAML 파일 | 83개 |
| Deployment | 12 |
| StatefulSet | 6 |
| DaemonSet | 1 (Promtail) |
| Service | 18 |
| ConfigMap | 12 |
| Secret | 1 (통합) |
| PVC | 2 |
| Ingress | 1 |
| HPA (prod) | 3 |
| ClusterIssuer (prod) | 1 |
| RBAC (SA/CR/CRB) | 6 |

### 디렉토리 구조

```
k8s/
├── base/
│   ├── namespace.yaml
│   ├── secrets.yaml
│   ├── ingress.yaml
│   ├── cert-manager.yaml
│   ├── kustomization.yaml
│   ├── moalog-server/         # Deployment + Service + ConfigMap
│   ├── rate-limiter/          # Deployment + Service (OTel init)
│   ├── fluxpay-engine/        # Deployment + Service (OTel init)
│   ├── redis/                 # StatefulSet + Service + PVC
│   ├── mysql/                 # StatefulSet + Service + ConfigMap(init SQL)
│   ├── postgres/              # StatefulSet + Service + ConfigMap(init SQL)
│   ├── zookeeper/             # StatefulSet + Service
│   ├── kafka/                 # StatefulSet + Service
│   └── monitoring/
│       ├── prometheus/        # Deployment + Service + SA/RBAC + ConfigMap + PVC
│       ├── grafana/           # Deployment + Service + ConfigMap(datasources) + PVC
│       ├── alertmanager/      # Deployment + Service + ConfigMap
│       ├── loki/              # StatefulSet + Service + ConfigMap
│       ├── promtail/          # DaemonSet + SA/RBAC + ConfigMap
│       ├── jaeger/            # Deployment + Service
│       ├── otel-collector/    # Deployment + Service + ConfigMap
│       └── exporters/         # redis/mysqld/rjmx×2 Deployments + Services
├── overlays/
│   ├── dev/                   # replicas=1, 리소스 축소, TLS 없음, *.moalog.local
│   └── prod/                  # replicas=3, HPA, cert-manager, *.moalog.com
└── (83 files total)
```

---

## 8-1. 서비스별 K8s 매니페스트

rJMX-Exporter의 기존 패턴(Kustomize)을 확장하여 전체 서비스를 전환.

| 서비스 | 종류 | Replicas | Probes | 리소스(req/limit) |
|--------|------|----------|--------|------------------|
| moalog-server | Deployment | 2 | tcpSocket:8080 | 128m-500m / 256Mi-512Mi |
| rate-limiter | Deployment | 2 | /actuator/health | 250m-500m / 512Mi-768Mi |
| fluxpay-engine | Deployment | 2 | /api/v1/health | 250m-500m / 512Mi-768Mi |
| redis | StatefulSet | 1 | redis-cli ping | 100m-250m / 128Mi-256Mi |
| mysql | StatefulSet | 1 | mysqladmin ping | 250m-500m / 512Mi-1Gi |
| postgres | StatefulSet | 1 | pg_isready | 100m-500m / 256Mi-512Mi |
| zookeeper | StatefulSet | 1 | tcpSocket:2181 | 100m-250m / 256Mi-512Mi |
| kafka | StatefulSet | 1 | tcpSocket:9092 | 250m-500m / 512Mi-1Gi |

**JVM 서비스 OTel 자동 계측**: initContainer(busybox)로 opentelemetry-javaagent v2.11.0 다운로드 → emptyDir 공유

---

## 8-2. Ingress & TLS

**NGINX Ingress 라우팅**:
```
api.moalog.com/         → moalog-server:8080
api.moalog.com/pay/     → fluxpay-engine:8080
grafana.moalog.com/     → grafana:3000
```

**Dev**: `moalog.local`, `grafana.moalog.local` (TLS 없음)
**Prod**: cert-manager + Let's Encrypt ClusterIssuer

---

## 8-3. Secret 관리

통합 Secret (`moalog-secrets`)에 모든 시크릿 중앙 관리:
- mysql-root-password, mysql-exporter-password
- postgres-password
- jwt-secret, openai-api-key, toss-secret-key
- grafana-admin-password, actuator-user/password

**현재**: K8s Secret (stringData) — Phase 1 완료
**향후**: Sealed Secrets 또는 External Secrets Operator

---

## 8-4. Overlays

| 환경 | Replicas | 리소스 | HPA | TLS | 호스트 |
|------|----------|--------|-----|-----|--------|
| dev | 1 | 최소 (64m-250m) | 없음 | 없음 | *.moalog.local |
| prod | 3 | 확장 (256m-1) | 있음 (CPU 70%) | cert-manager | *.moalog.com |

**Prod HPA 설정**:
- moalog-server: 2-10 replicas
- rate-limiter: 2-8 replicas
- fluxpay-engine: 2-8 replicas

---

## 8-5. Monitoring Stack (K8s)

| 서비스 | 리소스 타입 | 비고 |
|--------|------------|------|
| Prometheus | Deployment + RBAC | K8s pod SD, 15d retention |
| Grafana | Deployment + PVC | datasources/dashboards provisioning |
| Alertmanager | Deployment | Slack/PagerDuty webhook 지원 |
| Loki | StatefulSet + PVC | filesystem 스토리지 |
| Promtail | DaemonSet + RBAC | K8s pod log 수집 |
| Jaeger | Deployment | all-in-one, OTLP 수신 |
| OTel Collector | Deployment | traces→Jaeger, metrics→Prometheus |
| Exporters | Deployment×4 | redis, mysqld, rjmx×2 |

---

## 사용법

```bash
# Dev 환경 배포
kubectl apply -k k8s/overlays/dev/

# Prod 환경 배포
kubectl apply -k k8s/overlays/prod/

# Kustomize 빌드 확인 (dry-run)
kubectl kustomize k8s/overlays/dev/
```

---

## 완료 기준

- [x] `kubectl kustomize` 빌드 성공 (base, dev, prod)
- [x] 전체 20개 서비스 K8s 매니페스트 작성
- [x] Ingress (NGINX) 라우팅 규칙 설정
- [x] TLS (cert-manager + Let's Encrypt) 구성
- [x] Secret 중앙 관리 (K8s Secret)
- [x] dev/prod overlay 분리 (replicas, resources, HPA)
- [ ] 실제 클러스터 배포 검증 (minikube/EKS)
