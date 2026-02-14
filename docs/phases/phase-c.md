# Phase C: 모니터링 통합

> rJMX-Exporter + Prometheus + Grafana로 전체 시스템 관측성을 확보한다.

## 목표

- 모든 서비스의 메트릭을 Prometheus로 수집
- Grafana 대시보드로 시스템 상태 실시간 확인
- JVM 서비스(rate-limiter, fluxpay-engine)는 rJMX-Exporter로 모니터링

## 선행 조건

- Phase A 완료 (moalog-server Docker화)
- Phase B 완료 (rate-limiter 통합) — 선택적이나 권장

## 모니터링 대상

| 서비스 | 수집 방법 | 주요 메트릭 |
|--------|----------|------------|
| moalog-server (Rust) | 자체 `/metrics` 엔드포인트 | 요청 TPS, 레이턴시, DB 커넥션 풀 |
| rate-limiter (Kotlin/JVM) | Jolokia → rJMX-Exporter | JVM Heap, GC, Thread pool, Redis 커넥션 |
| fluxpay-engine (Java/JVM) | Jolokia → rJMX-Exporter | JVM Heap, GC, 결제 TPS, DB 커넥션 |
| Redis | redis_exporter | 메모리, 커넥션 수, 명령 처리량 |
| MySQL | mysqld_exporter | 쿼리 처리량, slow query, 커넥션 |

## 작업 목록

### C-1. JVM 앱에 Jolokia 에이전트 추가

**대상**: distributed-rate-limiter, fluxpay-engine

**해야 할 것**:
- Dockerfile에 Jolokia JVM agent 추가
- Jolokia HTTP 포트 노출 (기본 8778)
- 각 레포에서 수정 후 이미지 재빌드

---

### C-2. rJMX-Exporter 설정

**현재 상태**: Phase 3 완료, YAML 설정 기반 다중 타겟 지원

**해야 할 것**:
- `targets.yaml`에 rate-limiter, fluxpay-engine 등록
- 수집할 MBean 패턴 정의 (JVM 기본 + 앱 커스텀)

---

### C-3. moalog-server에 /metrics 엔드포인트 추가

**수정 대상**: `moalog-server` 레포

**해야 할 것**:
- `metrics` crate (prometheus-client 또는 metrics-rs) 의존성 추가
- Axum 라우트에 `GET /metrics` 추가
- 수집할 메트릭:
  - HTTP 요청 수/레이턴시 (method, path, status별)
  - DB 커넥션 풀 (active, idle)
  - AI 호출 수/레이턴시/비용

---

### C-4. docker-compose에 모니터링 스택 추가

```yaml
services:
  # 기존 서비스들...
  rjmx-exporter:    # Rust (port 9090)
  prometheus:       # (port 9091)
  grafana:          # (port 3000)
  redis-exporter:   # (port 9121)
  mysqld-exporter:  # (port 9104)
```

**Prometheus 설정** (`prometheus.yml`):
- scrape 타겟: moalog-server, rjmx-exporter, redis-exporter, mysqld-exporter

---

### C-5. Grafana 대시보드 구성

**대시보드 목록**:
1. **System Overview** — 전체 서비스 상태 한눈에
2. **moalog-server** — HTTP 메트릭, AI 호출, DB
3. **JVM Services** — rate-limiter & fluxpay-engine JVM 상태
4. **Infrastructure** — Redis, MySQL 상태

**프로비저닝**: JSON 파일로 대시보드 정의 → Docker volume mount로 자동 로드

## 완료 조건

- [ ] `http://localhost:3000` (Grafana) 접속 가능
- [ ] 4개 서비스 메트릭이 Prometheus에 수집됨
- [ ] System Overview 대시보드에서 전체 상태 확인 가능
- [ ] rJMX-Exporter가 JVM 앱 메트릭을 정상 수집
