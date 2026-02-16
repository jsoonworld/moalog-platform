<div align="center">

# Moalog Platform

**AI 회고 서비스를 위한 프로덕션 레디 마이크로서비스 플랫폼**

Rust · Kotlin · Java | 20개 서비스 | Kubernetes | Full Observability

[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](#cicd-파이프라인)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](#quick-start)
[![Kubernetes](https://img.shields.io/badge/K8s-Kustomize-326CE5?logo=kubernetes&logoColor=white)](#kubernetes-배포)
[![Monitoring](https://img.shields.io/badge/Monitoring-Prometheus_+_Grafana-E6522C?logo=prometheus&logoColor=white)](#관측성-스택)

[English](./README_EN.md) · [Runbook](./docs/runbook.md) · [부하 테스트 결과](#부하-테스트-결과)

</div>

---

## 목차

- [왜 이 프로젝트인가](#왜-이-프로젝트인가)
- [아키텍처](#아키텍처)
- [기술 스택](#기술-스택)
- [서비스 상세](#서비스-상세)
- [Quick Start](#quick-start)
- [관측성 스택](#관측성-스택)
- [부하 테스트 결과](#부하-테스트-결과)
- [카오스 엔지니어링](#카오스-엔지니어링)
- [Kubernetes 배포](#kubernetes-배포)
- [CI/CD 파이프라인](#cicd-파이프라인)
- [프로젝트 구조](#프로젝트-구조)
- [설계 의사결정과 트레이드오프](#설계-의사결정과-트레이드오프)

---

## 왜 이 프로젝트인가

"서비스를 만든다"와 "서비스를 **운영한다**"는 완전히 다른 문제입니다.

이 프로젝트는 단순한 CRUD 서버를 넘어, **실제 프로덕션 환경에서 마주치는 문제들**을 직접 해결합니다:

- 트래픽이 몰리면? → **분산 Rate Limiter** (Sliding Window + Token Bucket)
- 결제 중복이 발생하면? → **Saga + Outbox + 멱등성 키**
- Redis가 죽으면? → **Fail Open** (서비스는 살아있어야 한다)
- JVM 모니터링에 메모리가 100MB+? → **Rust로 직접 만든 Exporter** (5MB)
- 장애를 어떻게 검증하지? → **카오스 테스트 7개 시나리오**

---

## 아키텍처

```
                            ┌─────────────────────────────────────────────┐
                            │            Kubernetes (Kustomize)           │
                            │         dev / prod overlays · HPA          │
                            └─────────────────────────────────────────────┘

                                         ┌──────────┐
                                         │  Client  │
                                         └────┬─────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │   NGINX Ingress    │
                                    │  TLS (cert-manager) │
                                    └─────────┬──────────┘
                                              │
                     ┌────────────────────────┼────────────────────────┐
                     │                        │                        │
           ┌─────────▼──────────┐   ┌────────▼─────────┐   ┌─────────▼──────────┐
           │  Rate Limiter      │   │  moalog-server    │   │  FluxPay Engine    │
           │  Kotlin · WebFlux  │   │  Rust · Axum      │   │  Java · WebFlux    │
           │  Token Bucket /    │   │  AI 회고 · Auth    │   │  결제 · 구독 · Saga │
           │  Sliding Window    │   │  JWT · PDF Export  │   │  Outbox · 멱등성   │
           └────────┬───────────┘   └───┬─────────┬─────┘   └──┬────────┬───────┘
                    │                   │         │             │        │
              ┌─────▼─────┐      ┌─────▼───┐  ┌──▼───┐  ┌─────▼──┐  ┌──▼──────┐
              │   Redis   │      │  MySQL  │  │OpenAI│  │Postgres│  │  Kafka  │
              │  7-alpine │      │   8.0   │  │ API  │  │   16   │  │  7.5.0  │
              └───────────┘      └─────────┘  └──────┘  └────────┘  └─────────┘

─── 관측성 (Observability) ──────────────────────────────────────────────────────

  ┌────────────┐   ┌───────────┐   ┌──────────────────┐   ┌──────────┐
  │ Prometheus │◄──│  rJMX     │   │  OTel Collector  │──▶│  Jaeger  │
  │  v2.48.0   │   │ Exporter  │   │  OTLP gRPC/HTTP  │   │  v1.54   │
  └──────┬─────┘   │  (Rust)   │   └────────▲─────────┘   └──────────┘
         │         │  ~5MB RAM │            │
         ▼         └───────────┘    Java Agent (auto)
  ┌────────────┐                            │
  │  Grafana   │   ┌───────────┐   ┌───────┴──────────┐
  │  10.2.0    │◄──│   Loki    │◄──│    Promtail      │
  │ 5 Dashboard│   │  2.9.0    │   │  Docker Socket SD│
  └────────────┘   └───────────┘   └──────────────────┘
         │
  ┌──────▼───────┐
  │ Alertmanager │
  │   v0.27.0    │
  └──────────────┘
```

---

## 기술 스택

### 애플리케이션

| 서비스 | 언어 | 프레임워크 | DB | 핵심 기능 |
|--------|------|-----------|-----|----------|
| **moalog-server** | Rust 1.85 | Axum 0.7 · SeaORM | MySQL 8.0 | AI 회고, JWT 인증, PDF 생성, 글로벌 Rate Limit |
| **distributed-rate-limiter** | Kotlin 1.9 | Spring Boot 3.2 · WebFlux | Redis 7 | Token Bucket, Sliding Window (Lua 스크립트) |
| **fluxpay-engine** | Java 21 | Spring Boot 3.2 · WebFlux · R2DBC | PostgreSQL 16 | 결제, 구독, Saga, Outbox, 멱등성 |
| **rJMX-Exporter** | Rust 1.83 | Axum 0.7 · Tokio | — | Jolokia → Prometheus 메트릭 변환 |

### 인프라 & 관측성

| 카테고리 | 기술 | 버전 | 용도 |
|---------|------|------|------|
| **메트릭** | Prometheus | v2.48.0 | 시계열 DB, 15일 보존, 9개 scrape 타겟 |
| **대시보드** | Grafana | 10.2.0 | 5개 대시보드 (Overview, JVM, Redis, MySQL, SLO) |
| **알림** | Alertmanager | v0.27.0 | 8개 알림 룰, severity 기반 라우팅 |
| **로그** | Loki + Promtail | 2.9.0 | 중앙 집중 로그, Docker Socket 자동 수집 |
| **트레이싱** | Jaeger + OTel | 1.54 / 0.93.0 | 분산 트레이싱, Java Agent 자동 계측 |
| **JVM 메트릭** | rJMX-Exporter | 자체 개발 | Jolokia 기반 JMX 수집 (Rust, ~5MB) |
| **DB 메트릭** | Redis Exporter · MySQL Exporter | v1.66.0 / v0.16.0 | 데이터 스토어 모니터링 |
| **오케스트레이션** | Docker Compose / Kubernetes | — / 1.25+ | 로컬 개발 / 클라우드 배포 (Kustomize) |
| **CI/CD** | GitHub Actions | — | 검증, 스모크 테스트, 부하 테스트, 보안 스캔 |
| **보안 스캔** | Trivy | latest | 4개 서비스 컨테이너 취약점 스캔 |
| **부하 테스트** | k6 | latest | 4개 시나리오 + 7개 카오스 테스트 |

---

## 서비스 상세

### moalog-server (Rust)

AI 기반 회고(Retrospect) 서비스의 핵심 백엔드.

- **인증**: JWT (Cookie `access_token` + Bearer 헤더 이중 지원)
- **AI**: OpenAI API 비동기 호출 (async-openai)
- **Rate Limit**: 글로벌 IP 기반 100req/60s (governor 크레이트)
- **PDF**: genpdf를 활용한 회고 내보내기
- **API 문서**: Utoipa + Swagger UI
- **메트릭**: axum-prometheus로 Prometheus 형식 노출
- **Dockerfile**: 3-stage 빌드 (planner → builder → runtime), 논루트 실행

### distributed-rate-limiter (Kotlin)

Redis 기반 분산 Rate Limiter. 두 가지 알고리즘을 선택 가능.

| 알고리즘 | 특성 | 메모리 | 적합한 케이스 |
|---------|------|--------|-------------|
| **Token Bucket** | 버스트 허용, 일정 속도 리필 | O(1) | API 일반 Rate Limit |
| **Sliding Window Log** | 정확한 카운팅, 경계 이슈 없음 | O(N) | 엄격한 제한 필요 시 |

- **Fail Open**: Redis 장애 시 요청을 차단하지 않음 (가용성 > 정확성)
- **원자적 연산**: Redis Lua 스크립트로 race condition 방지
- **Kotlin Coroutines**: 논블로킹 비동기 처리
- **Jolokia**: JMX 메트릭을 HTTP/JSON으로 노출 (rJMX-Exporter가 수집)

### fluxpay-engine (Java)

헥사고날 아키텍처 기반 결제 엔진. Toss Payments 연동.

```
┌─ Presentation ─────────┐    ┌─ Domain ──────────────┐    ┌─ Infrastructure ─┐
│ Controller · DTO       │───▶│ Entity · Service      │───▶│ R2DBC Repository │
│ Exception Handler      │    │ Domain Event · Port   │    │ Kafka · External │
└────────────────────────┘    └───────────────────────┘    └──────────────────┘
```

| 패턴 | 구현 | 목적 |
|------|------|------|
| **Saga** | saga_instances + saga_steps 테이블 | 분산 트랜잭션 보상 |
| **Transactional Outbox** | outbox_events + processed_events | 신뢰성 있는 이벤트 발행 |
| **멱등성 키** | Redis Lua + idempotency_keys (24h TTL) | 중복 결제 방지 |
| **RLS** | PostgreSQL Row-Level Security | 멀티 테넌트 격리 |

**도메인**: Order (주문) · Payment (결제) · Credit (크레딧) · Subscription (구독)

### rJMX-Exporter (Rust)

Java 기반 `jmx_exporter`를 대체하는 경량 JMX 메트릭 수집기.

| 지표 | rJMX-Exporter (Rust) | jmx_exporter (Java) |
|------|---------------------|---------------------|
| **메모리** | **~5MB** | ~50-100MB |
| **시작 시간** | **< 100ms** | 2-5초 |
| **JVM 필요** | **No** | Yes |
| **앱 영향** | **Zero** (사이드카) | GC/힙 공유 |

- Jolokia 2.x HTTP/JSON → Prometheus exposition format 변환
- YAML 기반 룰 엔진: 패턴 매칭으로 MBean → 메트릭 이름 변환
- LTO + 단일 codegen unit + strip으로 바이너리 최적화

---

## Quick Start

### 사전 요구사항

- Docker & Docker Compose v2
- 약 8GB RAM (전체 스택 실행 시)
- (선택) k6 — 부하 테스트
- (선택) kubectl + kustomize — K8s 배포

### 실행

```bash
# 1. 레포 클론
git clone --recurse-submodules https://github.com/jsoonworld/moalog-platform.git
cd moalog-platform

# 2. 환경 변수 설정
cp .env.example .env
# .env 파일에서 OPENAI_API_KEY 등 필요한 값 수정

# 3. 전체 스택 실행
make up

# 4. 헬스 체크 (2-3분 후)
make health
```

### 서비스 URL

| 서비스 | URL | 비고 |
|--------|-----|------|
| moalog-server | http://localhost:8090 | Swagger: /swagger-ui |
| rate-limiter | http://localhost:8082 | Health: /actuator/health |
| fluxpay-engine | http://localhost:8081 | Health: /api/v1/health |
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9091 | 9개 타겟 |
| Alertmanager | http://localhost:9095 | 알림 현황 |
| Jaeger | http://localhost:16686 | 분산 트레이싱 |

### 주요 Make 명령어

```bash
make up                  # 전체 서비스 시작
make down                # 전체 서비스 중지
make health              # 헬스 체크
make logs SERVICE=name   # 특정 서비스 로그 확인
make build               # 전체 이미지 리빌드
make test-load           # 부하 테스트 (baseline)
make test-chaos          # 카오스 테스트 전체 실행
make clean               # 전체 중지 + 볼륨 삭제 (초기화)
```

---

## 관측성 스택

3 Pillars of Observability를 완비한 모니터링 스택:

### 메트릭 (Metrics)

**Prometheus** — 9개 scrape 타겟, 15일 보존

| 타겟 | 수집 경로 | 주기 |
|------|----------|------|
| moalog-server | `/metrics` | 10s |
| rate-limiter | `/actuator/prometheus` | 15s |
| fluxpay-engine | `/actuator/prometheus` | 10s |
| rjmx-rate-limiter | `/metrics` | 15s |
| rjmx-fluxpay | `/metrics` | 15s |
| redis-exporter | `/metrics` | 15s |
| mysqld-exporter | `/metrics` | 15s |
| otel-collector | `/metrics` | 15s |
| prometheus (self) | `/metrics` | 15s |

### 대시보드 (Grafana)

5개 프로비저닝 대시보드:

| 대시보드 | 주요 패널 |
|---------|----------|
| **Platform Overview** | 서비스 상태, 요청률, 5xx 비율, p50/p95/p99 레이턴시 |
| **JVM Detail** | 힙/논힙 메모리, GC 횟수/시간, 스레드 현황 |
| **Redis Detail** | 메모리 사용량, 커맨드/초, 커넥션 수, 단편화율 |
| **MySQL Detail** | 쿼리 성능, 슬로우 쿼리, InnoDB 버퍼풀 히트율 |
| **SLO Dashboard** | 가용성 99.9%, p95 < 500ms, 에러율 < 0.1%, 에러 버짓 |

### 로그 (Loki + Promtail)

- **Promtail**: Docker Socket SD로 컨테이너 자동 감지 (5초 리프레시)
- **파싱**: Spring Boot → JSON 파서 / Rust → Regex 파서
- **라벨**: service, container, level, logger
- **Grafana 연동**: `trace_id` Derived Field → 클릭 시 Jaeger로 이동

### 트레이싱 (Jaeger + OTel)

- **Java Agent 자동 계측**: busybox init 컨테이너가 JAR 다운로드 → JVM 서비스에 마운트
- **수집 경로**: Java Service → OTel Agent → OTel Collector (4317) → Jaeger
- **OTEL_METRICS_EXPORTER=none**: 기존 Micrometer와 충돌 방지
- **Loki 연동**: 로그에서 trace_id 클릭 시 해당 트레이스로 점프

### 알림 (Alertmanager)

8개 알림 룰, severity 기반 라우팅:

| 알림 | 조건 | 심각도 |
|------|------|--------|
| ServiceDown | `up == 0` (1분) | critical |
| RedisConnectionFailed | `redis_up == 0` (30초) | critical |
| HighErrorRate | 5xx > 1% (5분) | critical |
| HighLatency | p95 > 500ms (5분) | warning |
| JVMHeapHigh | 힙 > 80% (5분) | warning |
| MySQLSlowQueries | 슬로우 쿼리 > 10/분 (5분) | warning |
| RedisHighMemory | 메모리 > 80% (5분) | warning |
| RateLimiterOverload | 429 > 1000/분 (5분) | info |

---

## 부하 테스트 결과

k6를 활용한 4개 시나리오, 2026-02-15 실행.

### Baseline (기준 성능)

```
VU: 100  |  Duration: 5min  |  Result: PASS ✓
─────────────────────────────────────────────
Throughput:  59 req/s
p95 Latency: 125ms
p99 Latency: —
Error Rate:  0.00%
```

### Rate Limiter 검증

```
Result: PASS ✓
───────────────────────────────────────────
Total Requests: 27,646+
Blocked (429):  99.99%
5xx Errors:     0
```

→ IP 기반 Sliding Window(100req/60s)가 정확하게 동작. 초과 요청은 429로 차단하면서 서버 에러는 0건.

### Payment Concurrency (결제 동시성)

```
VU: 50  |  Duration: 2min  |  Result: PASS ✓
─────────────────────────────────────────────
Duplicate Payments: 0건
5xx (502 제외):     0건
```

→ 멱등성 키(`X-Idempotency-Key`)로 동일 결제 요청 중복 처리 완전 방지.

### Mixed Load (복합 부하)

```
VU: 200  |  Duration: 10min  |  Result: PASS ✓
─────────────────────────────────────────────
Throughput:  108 req/s
p95 Latency: 672ms
p99 Latency: 2.35s
Error Rate:  0.07%
```

→ 200 VU 혼합 트래픽(읽기/쓰기/결제/AI) 에서도 에러율 0.1% 미만 유지.

### rJMX-Exporter 리소스 사용량

| 인스턴스 | 메모리 | 목표 |
|---------|--------|------|
| rjmx-rate-limiter | **5.1 MB** | < 10 MB ✓ |
| rjmx-fluxpay | **6.0 MB** | < 10 MB ✓ |

→ Java jmx_exporter 대비 **10~20배 메모리 절약**.

---

## 카오스 엔지니어링

7개 장애 시나리오로 시스템 복원력 검증:

### 서비스 장애 (5개)

| 시나리오 | 주입 장애 | 기대 동작 | 결과 |
|---------|----------|----------|------|
| **Redis 장애** | Redis 컨테이너 중지 | Rate Limiter → Fail Open (요청 통과) | ✓ |
| **MySQL 장애** | MySQL 컨테이너 중지 | moalog-server → 503, 60초 내 복구 | ✓ |
| **Rate Limiter 장애** | Rate Limiter 중지 | moalog-server → Rate Limit 우회 | ✓ |
| **Kafka 장애** | Kafka 컨테이너 중지 | Outbox에 이벤트 큐잉, 복구 후 재전송 | ✓ |
| **FluxPay 장애** | FluxPay 컨테이너 중지 | 결제 API → 502, 비결제 API 정상 | ✓ |

### 리소스 제약 (2개)

| 시나리오 | 주입 장애 | 기대 동작 | 비고 |
|---------|----------|----------|------|
| **메모리 압박** | 64MB 메모리 제한 | OOM Kill → 자동 재시작 | macOS Docker에서 SKIP |
| **네트워크 지연** | 500ms+ 지연 주입 (tc qdisc) | 타임아웃 → Circuit Breaker 작동 | tc 미지원 시 disconnect 폴백 |

```bash
# 전체 카오스 테스트 실행
make test-chaos

# Circuit Breaker 단독 검증
make test-circuit-breaker
```

---

## Kubernetes 배포

Kustomize 기반 83개 매니페스트. dev/prod 오버레이 분리.

### 구조

```
k8s/
├── base/                    # 공통 리소스 (20개 서비스)
│   ├── moalog-server/       # Deployment + Service + ConfigMap
│   ├── rate-limiter/        # + OTel init container
│   ├── fluxpay-engine/      # + OTel init container
│   ├── redis/               # StatefulSet + PVC
│   ├── mysql/               # StatefulSet + PVC + init SQL
│   ├── postgres/            # StatefulSet + PVC + init SQL
│   ├── kafka/ + zookeeper/  # StatefulSet
│   ├── monitoring/          # 전체 관측성 스택
│   │   ├── prometheus/      # RBAC, ServiceAccount, PVC
│   │   ├── grafana/         # 5 Dashboard 프로비저닝
│   │   ├── alertmanager/    # 알림 라우팅
│   │   ├── loki/            # 7일 보존
│   │   ├── promtail/        # DaemonSet
│   │   ├── jaeger/          # all-in-one
│   │   ├── otel-collector/  # OTLP → Jaeger
│   │   └── exporters/       # Redis, MySQL, rJMX ×2
│   ├── ingress.yaml         # NGINX, TLS
│   └── secrets.yaml         # 통합 시크릿
└── overlays/
    ├── dev/                 # replica=1, 최소 리소스, *.moalog.local
    └── prod/                # replica=3, HPA(CPU 70%), cert-manager
```

### Dev vs Prod 비교

| 항목 | Dev | Prod |
|------|-----|------|
| 앱 레플리카 | 1 | 3 (min 2, max 10) |
| HPA | 없음 | CPU 70%, Memory 80% |
| TLS | 없음 | cert-manager + Let's Encrypt |
| 호스트 | `*.moalog.local` | `*.moalog.com` |
| 리소스 | 최소 | 증가 (CPU 256m~1, Mem 512Mi~1Gi) |

### 배포

```bash
# Dev 환경
kubectl apply -k k8s/overlays/dev/

# Prod 환경
kubectl apply -k k8s/overlays/prod/
```

---

## CI/CD 파이프라인

GitHub Actions 기반 4-stage 파이프라인:

```
┌──────────┐    ┌─────────────┐    ┌─────────────┐    ┌────────────────┐
│ Validate │───▶│ Smoke Test  │───▶│ Load Test   │    │ Security Scan  │
│          │    │             │    │ (main only) │    │ (Trivy ×4)     │
│ • YAML   │    │ • 전체 스택  │    │ • k6 기준   │    │ • CRITICAL/HIGH│
│ • .env   │    │   기동      │    │   성능 측정  │    │   취약점 검출   │
│ • Prom   │    │ • 헬스체크   │    │ • p95 경고  │    │ • SARIF 리포트 │
│   config │    │ • 타겟 UP   │    │ • 아티팩트   │    │                │
└──────────┘    └─────────────┘    └─────────────┘    └────────────────┘
                                                       (병렬 실행)
```

| 단계 | 트리거 | 타임아웃 | 비고 |
|------|--------|---------|------|
| Validate | PR / Push | — | 설정 파일 문법 검증 |
| Smoke Test | Validate 통과 후 | 20분 | Docker Compose 전체 스택 기동 + 헬스 체크 |
| Load Test | main push만 | 30분 | k6 baseline, p95 > 1000ms 시 경고 |
| Security Scan | 항상 (병렬) | 20분/서비스 | Trivy로 4개 서비스 이미지 스캔 |

---

## 프로젝트 구조

```
moalog-platform/
├── moalog-server/              # [Sub-repo] Rust 핵심 백엔드
│   ├── codes/server/           #   서버 소스 코드
│   ├── docker-compose.yaml     #   전체 스택 정의 (20개 서비스)
│   └── monitoring/             #   Prometheus, Grafana, Loki, OTel 설정
│       ├── prometheus.yml
│       ├── alert-rules.yml
│       ├── alertmanager/
│       ├── grafana/
│       │   ├── dashboards/     #   5개 JSON 대시보드
│       │   └── provisioning/   #   데이터소스 + 대시보드 자동 프로비저닝
│       ├── otel-collector/
│       ├── promtail/
│       └── rjmx-exporter/      #   rate-limiter.yaml, fluxpay-engine.yaml
│
├── distributed-rate-limiter/   # [Sub-repo] Kotlin Rate Limiter
├── fluxpay-engine/             # [Sub-repo] Java 결제 엔진
├── rJMX-Exporter/              # [Sub-repo] Rust JVM 메트릭 수집기
│
├── k8s/                        # Kubernetes 매니페스트 (83개)
│   ├── base/                   #   공통 리소스
│   └── overlays/               #   dev / prod 오버레이
│
├── load-tests/                 # k6 부하 테스트 + 카오스 테스트
│   ├── scenarios/              #   4개 부하 시나리오
│   ├── scenarios/chaos/        #   7개 카오스 시나리오
│   ├── results/                #   테스트 결과 (JSON + CSV)
│   └── lib/                    #   공통 유틸 (auth, config, checks)
│
├── docs/                       # 문서
│   ├── runbook.md              #   운영 런북
│   └── phase-*.md              #   단계별 구현 문서
│
├── .github/workflows/          # CI/CD
│   └── integration.yml         #   4-stage 파이프라인
│
├── Makefile                    # 오케스트레이션 명령어
└── .env.example                # 환경 변수 템플릿
```

---

## 설계 의사결정과 트레이드오프

### 1. 언어 선택: Rust + Kotlin + Java

| | Rust | Kotlin | Java |
|---|---|---|---|
| **사용처** | moalog-server, rJMX | Rate Limiter | FluxPay |
| **선택 이유** | 메모리 효율, 제로 GC, 빠른 응답 | Spring 생태계 + 코루틴 | Spring 생태계 + WebFlux 성숙도 |
| **트레이드오프** | 개발 속도 느림, 러닝커브 높음 | JVM 메모리 오버헤드 | JVM 메모리 오버헤드 |

> **판단**: 핵심 서버(moalog-server)는 매 요청마다 실행되므로 Rust의 낮은 레이턴시와 메모리 효율이 결정적. Rate Limiter와 결제는 Spring 생태계(Redis/Kafka/R2DBC 통합)의 생산성이 더 중요.

### 2. Rate Limiter: Fail Open vs Fail Closed

```
Fail Open  (현재 선택) → Redis 죽으면 모든 요청 통과  → 가용성 우선
Fail Closed             → Redis 죽으면 모든 요청 거부  → 안전성 우선
```

> **판단**: "서비스가 느리더라도 살아있는 것"이 "안전하지만 죽은 서비스"보다 낫다. DDoS 위험은 인프라 레벨(WAF, CDN)에서 별도 대응.

### 3. rJMX-Exporter: 직접 개발 vs 기존 jmx_exporter

| | rJMX (자체 개발) | jmx_exporter (기존) |
|---|---|---|
| **메모리** | 5MB | 50-100MB |
| **시작 시간** | < 100ms | 2-5초 |
| **유지보수** | 직접 관리 필요 | 커뮤니티 유지보수 |
| **기능 범위** | 필요한 MBean만 | 전체 MBean |

> **판단**: 사이드카 패턴에서 인스턴스마다 50MB+는 부담. 필요한 메트릭만 수집하는 경량 Exporter가 K8s 환경에서 더 경제적. 다만 커스텀 MBean 추가 시 직접 룰을 작성해야 하는 비용 존재.

### 4. FluxPay 아키텍처: Outbox + Saga

```
단순 방식:   Service → Kafka 직접 발행  → 빠르지만 DB 커밋 & 메시지 발행 불일치 가능
Outbox 방식: Service → DB(outbox 테이블) → Relay → Kafka  → 원자성 보장, 복잡도 증가
```

> **판단**: 결제는 정확성이 최우선. DB 트랜잭션과 이벤트 발행의 원자성을 Outbox로 보장. Kafka 장애 시에도 outbox 테이블에 이벤트가 저장되어 복구 후 재전송.

### 5. OTel: Metrics Exporter = none

```
OTel Agent 기본  → 메트릭/로그/트레이스 모두 수집  → 기존 Micrometer와 충돌
현재 선택        → 트레이스만 수집, 메트릭은 Micrometer, 로그는 Logback 유지
```

> **판단**: 이미 Micrometer + Prometheus가 메트릭을 잘 수집하고 있으므로, OTel Agent는 트레이싱만 담당하게 하여 중복 수집과 충돌 방지. 향후 전면 OTel 전환 시 점진적 마이그레이션 가능.

### 6. Kubernetes: Kustomize vs Helm

```
Helm      → 템플릿 엔진, 변수 치환, 차트 레지스트리  → 범용적이지만 복잡
Kustomize → 패치 기반, YAML 직접 수정, kubectl 내장   → 단순하지만 조건부 로직 한계
```

> **판단**: 20개 서비스의 리소스가 환경별로 다른 것은 주로 replica/resource/host뿐. 이 수준의 차이는 Kustomize 패치로 충분. Helm의 조건부 로직이나 차트 의존성이 필요한 규모가 아님.

### 7. 컨테이너 빌드: Alpine vs Debian

| | Alpine | Debian (bookworm/jammy) |
|---|---|---|
| **이미지 크기** | 작음 (~5MB 베이스) | 큼 (~80MB 베이스) |
| **라이브러리** | musl libc | glibc |
| **호환성** | 일부 바이너리 비호환 | 대부분 호환 |

> **판단**: Rust 서비스(final 이미지)는 Alpine 사용 가능 (정적 빌드). JDK builder는 **반드시 jammy/bookworm** — Alpine의 musl libc에서 Gradle native-platform이 SIGSEGV 발생 (ARM Docker 환경). JRE runtime은 Alpine 사용.

### 8. 보안: Non-Root + requirepass

모든 애플리케이션 컨테이너가 **비루트 사용자**(appuser:1001)로 실행:

- Redis: `--requirepass` 필수 (`REDIS_PASSWORD` 환경변수)
- PostgreSQL: 패스워드 환경변수화 (`FLUXPAY_DB_PASSWORD`)
- Actuator: Basic Auth (actuator/admin)
- 모든 시크릿: `.env` → K8s Secret으로 관리

---

## Sub-repositories

각 서비스의 소스 코드는 개별 레포에서 관리합니다:

| 서비스 | 레포 | 설명 |
|--------|------|------|
| moalog-server | [jsoonworld/moalog-server](https://github.com/jsoonworld/moalog-server) | Rust · Axum · SeaORM · MySQL |
| distributed-rate-limiter | [jsoonworld/distributed-rate-limiter](https://github.com/jsoonworld/distributed-rate-limiter) | Kotlin · Spring WebFlux · Redis |
| fluxpay-engine | [jsoonworld/fluxpay-engine](https://github.com/jsoonworld/fluxpay-engine) | Java · Spring WebFlux · R2DBC · PostgreSQL |
| rJMX-Exporter | [jsoonworld/rJMX-Exporter](https://github.com/jsoonworld/rJMX-Exporter) | Rust · Axum · Tokio |

---

## License

This project is for educational and portfolio purposes.
