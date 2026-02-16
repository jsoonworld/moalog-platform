# Phase 08: Kubernetes 배포

## 목표

docker-compose 기반 로컬 환경을 Kubernetes 매니페스트로 전환하여 클라우드 배포 가능 상태를 만든다.

---

## 현재 상태

| 항목 | 상태 |
|------|------|
| docker-compose (14 서비스) | 완성, 로컬 검증 완료 |
| rJMX-Exporter K8s | 완성 (Kustomize, Deployment, Service, ConfigMap, Secret) |
| 나머지 서비스 K8s | **없음** |
| Helm Chart | **없음** |
| Ingress / TLS | **없음** |
| Secret 관리 | 환경변수 하드코딩 |

**참고**: rJMX-Exporter에 이미 K8s 매니페스트가 있으므로, 이 패턴을 다른 서비스에 확장한다.

---

## 작업 목록

### 8-1. 서비스별 K8s 매니페스트

rJMX-Exporter의 기존 패턴(Kustomize)을 따른다.

**디렉토리 구조**:
```
moalog-platform/k8s/
├── base/
│   ├── moalog-server/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   ├── rate-limiter/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── fluxpay-engine/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── redis/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── mysql/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml    # init SQL
│   │   └── kustomization.yaml
│   ├── postgres/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── kafka/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── monitoring/
│   │   ├── prometheus/
│   │   ├── grafana/
│   │   └── exporters/
│   └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   └── prod/
│       ├── kustomization.yaml
│       └── patches/
└── kustomization.yaml
```

**서비스별 핵심 설정**:

| 서비스 | 리소스 | Replicas | Probes |
|--------|--------|----------|--------|
| moalog-server | 256Mi / 500m | 2 | /health |
| rate-limiter | 512Mi / 500m | 2 | /actuator/health |
| fluxpay-engine | 512Mi / 500m | 2 | /api/v1/health |
| redis | 128Mi / 250m | 1 (StatefulSet) | redis-cli ping |
| mysql | 512Mi / 500m | 1 (StatefulSet) | mysqladmin ping |
| postgres | 256Mi / 500m | 1 (StatefulSet) | pg_isready |

---

### 8-2. Ingress & TLS

**Ingress Controller**: NGINX Ingress

```yaml
# 라우팅 규칙
api.moalog.com/         → moalog-server:8080
api.moalog.com/pay/     → fluxpay-engine:8080
grafana.moalog.com/     → grafana:3000
```

**TLS**: cert-manager + Let's Encrypt

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@moalog.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

---

### 8-3. Secret 관리

| 시크릿 | 현재 | 목표 |
|--------|------|------|
| DB 비밀번호 | 환경변수 하드코딩 | K8s Secret (base64) |
| JWT_SECRET | .env 파일 | Sealed Secrets |
| OPENAI_API_KEY | .env 파일 | External Secrets (AWS SSM) |
| TOSS_SECRET_KEY | .env 파일 | External Secrets (AWS SSM) |
| Grafana admin | 기본값 admin/admin | K8s Secret |

**Phase 1**: K8s Secret (base64) — 기본 구현
**Phase 2**: Sealed Secrets 또는 External Secrets Operator — 프로덕션

---

### 8-4. Helm Chart (선택)

Kustomize로 충분하지 않을 경우 Helm Chart 전환.

```
moalog-platform/charts/
└── moalog/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-prod.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml
        └── _helpers.tpl
```

---

## 완료 기준

- [ ] `kubectl apply -k k8s/overlays/dev/` 로 전체 스택 기동
- [ ] 모든 Pod Running + healthcheck 통과
- [ ] Ingress를 통한 외부 접근 확인
- [ ] TLS 인증서 자동 발급 확인
- [ ] Secret이 평문으로 노출되지 않음
