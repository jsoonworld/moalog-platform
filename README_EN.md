<div align="center">

# Moalog Platform

**Production-Ready Microservice Platform for an AI Retrospective Service**

Rust · Kotlin · Java | 20 Services | Kubernetes | Full Observability

[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](#cicd-pipeline)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](#quick-start)
[![Kubernetes](https://img.shields.io/badge/K8s-Kustomize-326CE5?logo=kubernetes&logoColor=white)](#kubernetes-deployment)
[![Monitoring](https://img.shields.io/badge/Monitoring-Prometheus_+_Grafana-E6522C?logo=prometheus&logoColor=white)](#observability-stack)

[한국어](./README.md) · [Runbook](./docs/runbook.md) · [Load Test Results](#load-test-results)

</div>

---

## Table of Contents

- [Why This Project](#why-this-project)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Service Details](#service-details)
- [Quick Start](#quick-start)
- [Observability Stack](#observability-stack)
- [Load Test Results](#load-test-results)
- [Chaos Engineering](#chaos-engineering)
- [Kubernetes Deployment](#kubernetes-deployment)
- [CI/CD Pipeline](#cicd-pipeline)
- [Project Structure](#project-structure)
- [Design Decisions & Trade-offs](#design-decisions--trade-offs)

---

## Why This Project

"Building a service" and "**operating a service**" are fundamentally different problems.

This project goes beyond simple CRUD — it tackles **real production challenges** head-on:

- What if traffic spikes? → **Distributed Rate Limiter** (Sliding Window + Token Bucket)
- What about duplicate payments? → **Saga + Outbox + Idempotency Keys**
- What if Redis goes down? → **Fail Open** (the service must stay alive)
- JVM monitoring costs 100MB+? → **Custom Rust Exporter** (5MB)
- How to verify resilience? → **7 Chaos Test Scenarios**

---

## Architecture

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
           │  Token Bucket /    │   │  AI Retrospect    │   │  Payment · Sub ·   │
           │  Sliding Window    │   │  Auth · JWT · PDF │   │  Saga · Outbox     │
           └────────┬───────────┘   └───┬─────────┬─────┘   └──┬────────┬───────┘
                    │                   │         │             │        │
              ┌─────▼─────┐      ┌─────▼───┐  ┌──▼───┐  ┌─────▼──┐  ┌──▼──────┐
              │   Redis   │      │  MySQL  │  │OpenAI│  │Postgres│  │  Kafka  │
              │  7-alpine │      │   8.0   │  │ API  │  │   16   │  │  7.5.0  │
              └───────────┘      └─────────┘  └──────┘  └────────┘  └─────────┘

─── Observability ───────────────────────────────────────────────────────────────

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

## Tech Stack

### Application Services

| Service | Language | Framework | DB | Key Features |
|---------|----------|-----------|-----|-------------|
| **moalog-server** | Rust 1.85 | Axum 0.7 · SeaORM | MySQL 8.0 | AI retrospect, JWT auth, PDF export, global rate limit |
| **distributed-rate-limiter** | Kotlin 1.9 | Spring Boot 3.2 · WebFlux | Redis 7 | Token Bucket, Sliding Window (Lua scripts) |
| **fluxpay-engine** | Java 21 | Spring Boot 3.2 · WebFlux · R2DBC | PostgreSQL 16 | Payment, subscription, Saga, Outbox, idempotency |
| **rJMX-Exporter** | Rust 1.83 | Axum 0.7 · Tokio | — | Jolokia → Prometheus metric conversion |

### Infrastructure & Observability

| Category | Technology | Version | Purpose |
|---------|------------|---------|---------|
| **Metrics** | Prometheus | v2.48.0 | Time-series DB, 15-day retention, 9 scrape targets |
| **Dashboards** | Grafana | 10.2.0 | 5 dashboards (Overview, JVM, Redis, MySQL, SLO) |
| **Alerting** | Alertmanager | v0.27.0 | 8 alert rules, severity-based routing |
| **Logging** | Loki + Promtail | 2.9.0 | Centralized logs, Docker Socket auto-discovery |
| **Tracing** | Jaeger + OTel | 1.54 / 0.93.0 | Distributed tracing, Java Agent auto-instrumentation |
| **JVM Metrics** | rJMX-Exporter | Custom | Jolokia-based JMX collector (Rust, ~5MB) |
| **DB Metrics** | Redis Exporter · MySQL Exporter | v1.66.0 / v0.16.0 | Data store monitoring |
| **Orchestration** | Docker Compose / Kubernetes | — / 1.25+ | Local dev / Cloud deploy (Kustomize) |
| **CI/CD** | GitHub Actions | — | Validation, smoke test, load test, security scan |
| **Security Scan** | Trivy | latest | Container vulnerability scanning (4 services) |
| **Load Testing** | k6 | latest | 4 scenarios + 7 chaos tests |

---

## Service Details

### moalog-server (Rust)

The core backend for the AI-powered retrospective service.

- **Authentication**: JWT (Cookie `access_token` + Bearer header dual support)
- **AI Integration**: Async OpenAI API calls (async-openai crate)
- **Rate Limiting**: Global IP-based 100req/60s (governor crate)
- **PDF Export**: Retrospect export via genpdf
- **API Docs**: Utoipa + Swagger UI auto-generation
- **Metrics**: Prometheus format via axum-prometheus
- **Dockerfile**: 3-stage build (planner → builder → runtime), non-root execution

### distributed-rate-limiter (Kotlin)

Redis-backed distributed rate limiter with two selectable algorithms.

| Algorithm | Characteristics | Memory | Best For |
|-----------|----------------|--------|----------|
| **Token Bucket** | Burst-friendly, constant refill rate | O(1) | General API rate limiting |
| **Sliding Window Log** | Precise counting, no boundary issues | O(N) | Strict enforcement |

- **Fail Open**: Requests pass through on Redis failure (availability > accuracy)
- **Atomic Operations**: Redis Lua scripts prevent race conditions
- **Kotlin Coroutines**: Non-blocking async processing
- **Jolokia**: JMX metrics exposed via HTTP/JSON (collected by rJMX-Exporter)

### fluxpay-engine (Java)

Hexagonal architecture payment engine integrated with Toss Payments.

```
┌─ Presentation ─────────┐    ┌─ Domain ──────────────┐    ┌─ Infrastructure ─┐
│ Controller · DTO       │───▶│ Entity · Service      │───▶│ R2DBC Repository │
│ Exception Handler      │    │ Domain Event · Port   │    │ Kafka · External │
└────────────────────────┘    └───────────────────────┘    └──────────────────┘
```

| Pattern | Implementation | Purpose |
|---------|---------------|---------|
| **Saga** | saga_instances + saga_steps tables | Distributed transaction compensation |
| **Transactional Outbox** | outbox_events + processed_events | Reliable event publishing |
| **Idempotency Keys** | Redis Lua + idempotency_keys (24h TTL) | Duplicate payment prevention |
| **RLS** | PostgreSQL Row-Level Security | Multi-tenant isolation |

**Domains**: Order · Payment · Credit · Subscription

### rJMX-Exporter (Rust)

A lightweight JMX metrics exporter that replaces the Java-based `jmx_exporter`.

| Metric | rJMX-Exporter (Rust) | jmx_exporter (Java) |
|--------|---------------------|---------------------|
| **Memory** | **~5MB** | ~50-100MB |
| **Startup** | **< 100ms** | 2-5s |
| **JVM Required** | **No** | Yes |
| **App Impact** | **Zero** (sidecar) | Shared GC/Heap |

- Jolokia 2.x HTTP/JSON → Prometheus exposition format conversion
- YAML-based rule engine: pattern matching to transform MBeans → metric names
- Binary optimized with LTO + single codegen unit + strip

---

## Quick Start

### Prerequisites

- Docker & Docker Compose v2
- ~8GB RAM (for the full stack)
- (Optional) k6 — for load testing
- (Optional) kubectl + kustomize — for K8s deployment

### Run

```bash
# 1. Clone the repository
git clone --recurse-submodules https://github.com/jsoonworld/moalog-platform.git
cd moalog-platform

# 2. Configure environment variables
cp .env.example .env
# Edit .env — set OPENAI_API_KEY and other required values

# 3. Start the full stack
make up

# 4. Health check (after 2-3 minutes)
make health
```

### Service URLs

| Service | URL | Notes |
|---------|-----|-------|
| moalog-server | http://localhost:8090 | Swagger: /swagger-ui |
| rate-limiter | http://localhost:8082 | Health: /actuator/health |
| fluxpay-engine | http://localhost:8081 | Health: /api/v1/health |
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9091 | 9 targets |
| Alertmanager | http://localhost:9095 | Alert status |
| Jaeger | http://localhost:16686 | Distributed tracing |

### Key Make Commands

```bash
make up                  # Start all services
make down                # Stop all services
make health              # Health check all services
make logs SERVICE=name   # Tail logs for a specific service
make build               # Rebuild all images
make test-load           # Run load test (baseline)
make test-chaos          # Run all chaos tests
make clean               # Stop + remove volumes (full reset)
```

---

## Observability Stack

A complete monitoring stack covering the 3 Pillars of Observability:

### Metrics (Prometheus)

**9 scrape targets**, 15-day retention:

| Target | Path | Interval |
|--------|------|----------|
| moalog-server | `/metrics` | 10s |
| rate-limiter | `/actuator/prometheus` | 15s |
| fluxpay-engine | `/actuator/prometheus` | 10s |
| rjmx-rate-limiter | `/metrics` | 15s |
| rjmx-fluxpay | `/metrics` | 15s |
| redis-exporter | `/metrics` | 15s |
| mysqld-exporter | `/metrics` | 15s |
| otel-collector | `/metrics` | 15s |
| prometheus (self) | `/metrics` | 15s |

### Dashboards (Grafana)

5 auto-provisioned dashboards:

| Dashboard | Key Panels |
|-----------|-----------|
| **Platform Overview** | Service health, request rate, 5xx rate, p50/p95/p99 latency |
| **JVM Detail** | Heap/non-heap memory, GC count/duration, thread states |
| **Redis Detail** | Memory usage, commands/sec, connections, fragmentation ratio |
| **MySQL Detail** | Query performance, slow queries, InnoDB buffer pool hit ratio |
| **SLO Dashboard** | Availability 99.9%, p95 < 500ms, error rate < 0.1%, error budget |

### Logs (Loki + Promtail)

- **Promtail**: Docker Socket SD for automatic container discovery (5s refresh)
- **Parsing**: Spring Boot → JSON parser / Rust → Regex parser
- **Labels**: service, container, level, logger
- **Grafana Integration**: `trace_id` Derived Field → click to jump to Jaeger

### Tracing (Jaeger + OpenTelemetry)

- **Java Agent Auto-instrumentation**: busybox init container downloads JAR → mounted to JVM services
- **Collection Path**: Java Service → OTel Agent → OTel Collector (4317) → Jaeger
- **OTEL_METRICS_EXPORTER=none**: Prevents conflicts with existing Micrometer
- **Loki Integration**: Click trace_id in logs to navigate to the corresponding trace

### Alerting (Alertmanager)

8 alert rules with severity-based routing:

| Alert | Condition | Severity |
|-------|-----------|----------|
| ServiceDown | `up == 0` (1min) | critical |
| RedisConnectionFailed | `redis_up == 0` (30s) | critical |
| HighErrorRate | 5xx > 1% (5min) | critical |
| HighLatency | p95 > 500ms (5min) | warning |
| JVMHeapHigh | Heap > 80% (5min) | warning |
| MySQLSlowQueries | Slow queries > 10/min (5min) | warning |
| RedisHighMemory | Memory > 80% (5min) | warning |
| RateLimiterOverload | 429 > 1000/min (5min) | info |

---

## Load Test Results

4 scenarios using k6, executed on 2026-02-15.

### Baseline Performance

```
VU: 100  |  Duration: 5min  |  Result: PASS ✓
─────────────────────────────────────────────
Throughput:  59 req/s
p95 Latency: 125ms
p99 Latency: —
Error Rate:  0.00%
```

### Rate Limiter Verification

```
Result: PASS ✓
───────────────────────────────────────────
Total Requests: 27,646+
Blocked (429):  99.99%
5xx Errors:     0
```

IP-based Sliding Window (100req/60s) blocks excess traffic precisely with zero server errors.

### Payment Concurrency

```
VU: 50  |  Duration: 2min  |  Result: PASS ✓
─────────────────────────────────────────────
Duplicate Payments: 0
5xx (excl. 502):    0
```

Idempotency keys (`X-Idempotency-Key`) completely prevent duplicate payment processing.

### Mixed Load

```
VU: 200  |  Duration: 10min  |  Result: PASS ✓
─────────────────────────────────────────────
Throughput:  108 req/s
p95 Latency: 672ms
p99 Latency: 2.35s
Error Rate:  0.07%
```

Under 200 VU mixed traffic (read/write/payment/AI), error rate stays below 0.1%.

### rJMX-Exporter Resource Usage

| Instance | Memory | Target |
|----------|--------|--------|
| rjmx-rate-limiter | **5.1 MB** | < 10 MB ✓ |
| rjmx-fluxpay | **6.0 MB** | < 10 MB ✓ |

**10-20x memory savings** compared to Java jmx_exporter.

---

## Chaos Engineering

System resilience verified through 7 failure scenarios:

### Service Failures (5 scenarios)

| Scenario | Injected Failure | Expected Behavior | Result |
|----------|-----------------|-------------------|--------|
| **Redis Failure** | Stop Redis container | Rate Limiter → Fail Open (requests pass) | ✓ |
| **MySQL Failure** | Stop MySQL container | moalog-server → 503, recovers within 60s | ✓ |
| **Rate Limiter Failure** | Stop Rate Limiter | moalog-server → Bypasses rate limiting | ✓ |
| **Kafka Failure** | Stop Kafka container | Outbox queues events, replays on recovery | ✓ |
| **FluxPay Failure** | Stop FluxPay container | Payment API → 502, non-payment APIs unaffected | ✓ |

### Resource Constraints (2 scenarios)

| Scenario | Injected Failure | Expected Behavior | Notes |
|----------|-----------------|-------------------|-------|
| **Memory Pressure** | 64MB memory limit | OOM Kill → auto-restart | SKIP on macOS Docker |
| **Network Delay** | 500ms+ delay (tc qdisc) | Timeout → Circuit Breaker triggers | Falls back to disconnect test if tc unavailable |

```bash
# Run all chaos tests
make test-chaos

# Run Circuit Breaker verification only
make test-circuit-breaker
```

---

## Kubernetes Deployment

83 Kustomize manifests with dev/prod overlays.

### Structure

```
k8s/
├── base/                    # Common resources (20 services)
│   ├── moalog-server/       # Deployment + Service + ConfigMap
│   ├── rate-limiter/        # + OTel init container
│   ├── fluxpay-engine/      # + OTel init container
│   ├── redis/               # StatefulSet + PVC
│   ├── mysql/               # StatefulSet + PVC + init SQL
│   ├── postgres/            # StatefulSet + PVC + init SQL
│   ├── kafka/ + zookeeper/  # StatefulSet
│   ├── monitoring/          # Full observability stack
│   │   ├── prometheus/      # RBAC, ServiceAccount, PVC
│   │   ├── grafana/         # 5 dashboards provisioned
│   │   ├── alertmanager/    # Alert routing
│   │   ├── loki/            # 7-day retention
│   │   ├── promtail/        # DaemonSet
│   │   ├── jaeger/          # all-in-one
│   │   ├── otel-collector/  # OTLP → Jaeger
│   │   └── exporters/       # Redis, MySQL, rJMX ×2
│   ├── ingress.yaml         # NGINX, TLS
│   └── secrets.yaml         # Unified secret
└── overlays/
    ├── dev/                 # replica=1, minimal resources, *.moalog.local
    └── prod/                # replica=3, HPA (CPU 70%), cert-manager
```

### Dev vs Prod Comparison

| Aspect | Dev | Prod |
|--------|-----|------|
| App Replicas | 1 | 3 (min 2, max 10) |
| HPA | None | CPU 70%, Memory 80% |
| TLS | None | cert-manager + Let's Encrypt |
| Hosts | `*.moalog.local` | `*.moalog.com` |
| Resources | Minimal | Scaled (CPU 256m~1, Mem 512Mi~1Gi) |

### Deploy

```bash
# Dev environment
kubectl apply -k k8s/overlays/dev/

# Prod environment
kubectl apply -k k8s/overlays/prod/
```

---

## CI/CD Pipeline

GitHub Actions 4-stage pipeline:

```
┌──────────┐    ┌─────────────┐    ┌─────────────┐    ┌────────────────┐
│ Validate │───▶│ Smoke Test  │───▶│ Load Test   │    │ Security Scan  │
│          │    │             │    │ (main only) │    │ (Trivy ×4)     │
│ • YAML   │    │ • Full stack│    │ • k6 base-  │    │ • CRITICAL/HIGH│
│ • .env   │    │   startup   │    │   line perf │    │   vuln detect  │
│ • Prom   │    │ • Health    │    │ • p95 warn  │    │ • SARIF report │
│   config │    │   checks    │    │ • Artifacts │    │                │
└──────────┘    └─────────────┘    └─────────────┘    └────────────────┘
                                                       (runs in parallel)
```

| Stage | Trigger | Timeout | Notes |
|-------|---------|---------|-------|
| Validate | PR / Push | — | Config file syntax validation |
| Smoke Test | After Validate | 20min | Full Docker Compose stack + health checks |
| Load Test | main push only | 30min | k6 baseline, warns if p95 > 1000ms |
| Security Scan | Always (parallel) | 20min/service | Trivy scans 4 service images |

---

## Project Structure

```
moalog-platform/
├── moalog-server/              # [Sub-repo] Rust core backend
│   ├── codes/server/           #   Server source code
│   ├── docker-compose.yaml     #   Full stack definition (20 services)
│   └── monitoring/             #   Prometheus, Grafana, Loki, OTel configs
│       ├── prometheus.yml
│       ├── alert-rules.yml
│       ├── alertmanager/
│       ├── grafana/
│       │   ├── dashboards/     #   5 JSON dashboards
│       │   └── provisioning/   #   Datasource + dashboard auto-provisioning
│       ├── otel-collector/
│       ├── promtail/
│       └── rjmx-exporter/      #   rate-limiter.yaml, fluxpay-engine.yaml
│
├── distributed-rate-limiter/   # [Sub-repo] Kotlin Rate Limiter
├── fluxpay-engine/             # [Sub-repo] Java Payment Engine
├── rJMX-Exporter/              # [Sub-repo] Rust JVM Metrics Collector
│
├── k8s/                        # Kubernetes manifests (83 files)
│   ├── base/                   #   Common resources
│   └── overlays/               #   dev / prod overlays
│
├── load-tests/                 # k6 load tests + chaos tests
│   ├── scenarios/              #   4 load scenarios
│   ├── scenarios/chaos/        #   7 chaos scenarios
│   ├── results/                #   Test results (JSON + CSV)
│   └── lib/                    #   Shared utilities (auth, config, checks)
│
├── docs/                       # Documentation
│   ├── runbook.md              #   Operational runbook
│   └── phase-*.md              #   Phase implementation docs
│
├── .github/workflows/          # CI/CD
│   └── integration.yml         #   4-stage pipeline
│
├── Makefile                    # Orchestration commands
└── .env.example                # Environment variable template
```

---

## Design Decisions & Trade-offs

### 1. Language Choice: Rust + Kotlin + Java

| | Rust | Kotlin | Java |
|---|---|---|---|
| **Used For** | moalog-server, rJMX | Rate Limiter | FluxPay |
| **Why** | Memory efficiency, zero GC, low latency | Spring ecosystem + coroutines | Spring ecosystem + mature WebFlux |
| **Trade-off** | Slower development, steep learning curve | JVM memory overhead | JVM memory overhead |

> **Rationale**: The core server (moalog-server) runs on every request — Rust's low latency and memory efficiency are decisive here. For the Rate Limiter and payment engine, Spring ecosystem productivity (Redis/Kafka/R2DBC integration) matters more than raw performance.

### 2. Rate Limiter: Fail Open vs Fail Closed

```
Fail Open  (chosen) → Redis down = all requests pass  → Availability first
Fail Closed          → Redis down = all requests denied → Safety first
```

> **Rationale**: "A slow but alive service" is better than "a safe but dead service." DDoS protection is handled separately at the infrastructure level (WAF, CDN).

### 3. rJMX-Exporter: Build vs Buy

| | rJMX (Custom) | jmx_exporter (Existing) |
|---|---|---|
| **Memory** | 5MB | 50-100MB |
| **Startup** | < 100ms | 2-5s |
| **Maintenance** | Self-maintained | Community-maintained |
| **Scope** | Selected MBeans only | All MBeans |

> **Rationale**: In a sidecar pattern, 50MB+ per instance adds up quickly. A lightweight exporter collecting only needed metrics is more economical in K8s. The trade-off is writing custom rules for new MBeans.

### 4. FluxPay Architecture: Outbox + Saga

```
Simple:  Service → Kafka directly  → Fast but DB commit & message publish can be inconsistent
Outbox:  Service → DB (outbox table) → Relay → Kafka  → Atomicity guaranteed, higher complexity
```

> **Rationale**: For payments, correctness is paramount. The Outbox pattern guarantees atomicity between DB transactions and event publishing. Even when Kafka is down, events are stored in the outbox table and retransmitted after recovery.

### 5. OTel: Metrics Exporter = none

```
OTel Agent default → Collects metrics/logs/traces → Conflicts with existing Micrometer
Current choice     → Traces only, metrics via Micrometer, logs via Logback
```

> **Rationale**: Micrometer + Prometheus already handle metrics well. OTel Agent focuses solely on tracing to avoid duplicate collection and metric conflicts. This enables gradual full-OTel migration in the future.

### 6. Kubernetes: Kustomize vs Helm

```
Helm      → Template engine, variable substitution, chart registry → Versatile but complex
Kustomize → Patch-based, direct YAML modification, built into kubectl → Simple but limited conditionals
```

> **Rationale**: For 20 services, environment differences are mainly replicas/resources/hosts. Kustomize patches handle this well. The project hasn't reached the scale where Helm's conditional logic or chart dependencies are needed.

### 7. Container Build: Alpine vs Debian

| | Alpine | Debian (bookworm/jammy) |
|---|---|---|
| **Image Size** | Small (~5MB base) | Large (~80MB base) |
| **C Library** | musl libc | glibc |
| **Compatibility** | Some binary incompatibility | Broadly compatible |

> **Rationale**: Rust services (final images) can use Alpine (static builds). JDK builders **must use jammy/bookworm** — Alpine's musl libc causes SIGSEGV in Gradle native-platform on ARM Docker. JRE runtimes can use Alpine.

### 8. Security: Non-Root + Authentication

All application containers run as **non-root user** (appuser:1001):

- Redis: `--requirepass` required (`REDIS_PASSWORD` env var)
- PostgreSQL: Password via environment variable (`FLUXPAY_DB_PASSWORD`)
- Actuator: Basic Auth (actuator/admin)
- All secrets: `.env` → K8s Secret management

---

## Sub-repositories

Source code for each service is managed in individual repositories:

| Service | Repository | Description |
|---------|-----------|-------------|
| moalog-server | [jsoonworld/moalog-server](https://github.com/jsoonworld/moalog-server) | Rust · Axum · SeaORM · MySQL |
| distributed-rate-limiter | [jsoonworld/distributed-rate-limiter](https://github.com/jsoonworld/distributed-rate-limiter) | Kotlin · Spring WebFlux · Redis |
| fluxpay-engine | [jsoonworld/fluxpay-engine](https://github.com/jsoonworld/fluxpay-engine) | Java · Spring WebFlux · R2DBC · PostgreSQL |
| rJMX-Exporter | [jsoonworld/rJMX-Exporter](https://github.com/jsoonworld/rJMX-Exporter) | Rust · Axum · Tokio |

---

## License

This project is for educational and portfolio purposes.
