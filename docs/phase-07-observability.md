# Phase 07: 관측성 강화

## 목표

현재 메트릭 수집(Prometheus/Grafana)에 알림 · 로그 집계 · 분산 트레이싱을 추가하여 관측성 3대 축을 완성한다.

---

## 현재 상태

| 축 | 상태 | 도구 |
|----|------|------|
| Metrics | 완성 | Prometheus + Grafana (5 대시보드, 9 타겟) |
| Logs | **완성** | Loki + Promtail → Grafana Explore |
| Traces | **완성** | OTel Collector + Jaeger (JVM 자동 계측) |
| Alerting | **완성** | Prometheus Alert Rules + Alertmanager |

---

## 완료된 작업

### 7-1. Prometheus 알림 룰 ✅

**파일**: `moalog-server/monitoring/alert-rules.yml`

| 알림 | 조건 | 심각도 |
|------|------|--------|
| ServiceDown | up == 0 (1분 지속) | critical |
| RedisConnectionFailed | redis_up == 0 (30초) | critical |
| HighLatency | p95 > 500ms (5분 지속) | warning |
| HighErrorRate | 5xx 비율 > 1% (5분 지속) | critical |
| RateLimiterOverload | 429 응답 > 1000/min | info |
| JVMHeapHigh | heap used > 80% of max | warning |
| MySQLSlowQueries | slow queries > 10/min | warning |
| RedisHighMemory | memory used > 80% of max | warning |

**Alertmanager**: `moalog-server/monitoring/alertmanager/alertmanager.yml`
- 기본: Alertmanager UI에서 확인 (http://localhost:9095)
- Slack/Discord webhook 설정 예제 포함 (주석 처리)
- severity별 라우팅 (critical → 별도 채널)

---

### 7-2. Loki 로그 집계 ✅

**추가 서비스**:
```
loki (3100)       — 로그 저장소
promtail          — Docker 컨테이너 로그 수집기
```

**Promtail 설정** (`moalog-server/monitoring/promtail/promtail.yml`):
- Docker socket SD (서비스 자동 발견)
- 서비스별 라벨 자동 부여 (container, service, logstream)
- JSON 파싱 (rate-limiter, fluxpay-engine — Spring Boot JSON 로그)
- Regex 파싱 (moalog-server — Rust tracing 포맷)

**Grafana 연동**:
- Loki 데이터소스 자동 프로비저닝
- Trace ID → Jaeger 연결 (derivedFields)
- Explore 탭에서 전 서비스 로그 검색 가능

---

### 7-3. OpenTelemetry 분산 트레이싱 ✅

**추가 서비스**:
```
jaeger (16686)         — 트레이스 UI + 저장소
otel-collector         — OTLP 수집 → Jaeger 전달
otel-agent-init        — OTel Java Agent 다운로드 (초기화)
```

**서비스별 계측**:

| 서비스 | 방법 | 코드 변경 |
|--------|------|----------|
| rate-limiter (Kotlin) | OTel Java Agent 자동 계측 | 없음 |
| fluxpay-engine (Java) | OTel Java Agent 자동 계측 | 없음 |
| moalog-server (Rust) | 미적용 (tracing-opentelemetry 추가 필요) | 별도 PR |

**OTel Java Agent 자동 계측 방식**:
- `otel-agent-init` 서비스가 Java Agent JAR 다운로드 (v2.11.0)
- `otel_agent` 볼륨을 JVM 서비스에 read-only 마운트
- `JAVA_TOOL_OPTIONS=-javaagent:/otel/opentelemetry-javaagent.jar` 환경변수로 자동 로드
- 서비스 코드 변경 없이 HTTP/gRPC/JDBC/Kafka 트레이스 수집

**트레이스 경로**:
```
사용자 → rate-limiter → moalog-server (미계측)
사용자 → fluxpay-engine → Kafka / PostgreSQL
```

---

### 7-4. SLO/SLI 대시보드 ✅

**파일**: `moalog-server/monitoring/grafana/dashboards/slo-dashboard.json`

| SLI | 목표(SLO) | 측정 |
|-----|----------|------|
| 가용성 | 99.9% | avg(up) over 24h |
| 응답 지연 | p95 < 500ms | axum_http_requests_duration_seconds |
| 에러율 | < 0.1% | 5xx / total requests |
| 에러 버짓 | 잔여 % | (1 - error_rate / 0.001) × 100 |

**대시보드 패널**: 4 게이지 (SLO Overview) + 서비스별 가용성/지연/에러율 시계열 + 활성 알림 목록

---

## 추가된 서비스 & 포트

| 서비스 | 호스트 포트 | 용도 |
|--------|------------|------|
| alertmanager | 9095 | 알림 관리 UI |
| loki | 3100 | 로그 저장소 API |
| promtail | — | 로그 수집기 (내부) |
| jaeger | 16686 | 트레이스 UI |
| otel-collector | 4317 (gRPC), 4318 (HTTP) | 트레이스 수집 |
| otel-agent-init | — | Java Agent 다운로드 (일회성) |

---

## 파일 변경 요약

| 파일 | 변경 |
|------|------|
| `monitoring/alert-rules.yml` | **신규** — 8개 알림 룰 |
| `monitoring/alertmanager/alertmanager.yml` | **신규** — Alertmanager 설정 |
| `monitoring/promtail/promtail.yml` | **신규** — Docker 로그 수집 |
| `monitoring/otel-collector/otel-collector.yml` | **신규** — OTLP → Jaeger 파이프라인 |
| `monitoring/prometheus.yml` | **수정** — rule_files + alerting + otel-collector 타겟 |
| `monitoring/grafana/provisioning/datasources/datasources.yml` | **수정** — Loki + Jaeger 데이터소스 |
| `monitoring/grafana/dashboards/slo-dashboard.json` | **신규** — SLO/SLI 대시보드 |
| `docker-compose.yaml` | **수정** — 6개 서비스 추가 + JVM OTel 계측 |
| `Makefile` | **수정** — 신규 서비스 포트/헬스체크 |
| `.env.example` | **수정** — 신규 포트 변수 |

---

## 미완료 (향후 작업)

- [ ] moalog-server (Rust) OpenTelemetry 계측: `tracing-opentelemetry` + `opentelemetry-otlp` crate 추가
- [ ] Slack/Discord 웹훅 연동 (alertmanager.yml 주석 해제 + URL 설정)
- [ ] Grafana 알림 채널 설정 (Grafana Alerting → Contact Points)
