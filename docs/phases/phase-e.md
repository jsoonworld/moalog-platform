# Phase E: 통합 인프라 & 부하 테스트

> 전체 시스템을 하나의 docker-compose로 실행하고, k6 부하 테스트로 검증한다.

## 목표

- 4개 서비스 + 인프라 전체를 단일 docker-compose로 기동
- k6 부하 테스트로 시스템 한계 측정 및 병목 식별
- 성과 지표 정량화 (Rate Limiter 효과, rJMX-Exporter 성능 등)

## 선행 조건

- Phase A~D 완료

## 최종 docker-compose 구성

```yaml
services:
  # === 핵심 서비스 ===
  moalog-server:        # Rust / Axum (port 8080)
  fluxpay-engine:       # Java / WebFlux (port 8081)
  rate-limiter:         # Kotlin / WebFlux (port 8082)

  # === 모니터링 ===
  rjmx-exporter:        # Rust / Axum (port 9090)
  prometheus:           # (port 9091)
  grafana:              # (port 3000)
  redis-exporter:       # (port 9121)
  mysqld-exporter:      # (port 9104)

  # === 인프라 ===
  mysql:                # moalog DB (port 3306)
  postgres:             # fluxpay DB (port 5432)
  redis:                # rate-limiter + fluxpay 멱등성 (port 6379)
```

**위치**: `performance/docker-compose.yaml` (이 레포 루트)

## 부하 테스트 시나리오 (k6)

### E-1. Baseline 측정

**시나리오**: 일반 API 호출
```
GET /api/retrospects — 100 VU, 5분
```
**측정**: TPS, P50/P95/P99 레이턴시, 에러율

---

### E-2. Rate Limiter 효과 검증

**시나리오**: AI 분석 요청 폭주
```
POST /api/retrospects/{id}/ai-analysis — 50 VU, 3분
```
**비교**:
- Rate Limiter OFF → 서비스 과부하 / OpenAI 비용 폭발
- Rate Limiter ON → 429 정상 반환, 서비스 안정

---

### E-3. 결제 동시성 테스트

**시나리오**: 동시 결제 요청
```
POST /api/subscriptions — 20 VU, 동시 결제
```
**검증**: FluxPay 멱등성, Saga 정상 동작, 중복 결제 방지

---

### E-4. 전체 통합 부하

**시나리오**: 혼합 트래픽
```
70% 일반 API + 20% AI 분석 + 10% 결제
200 VU, 10분
```
**모니터링**: Grafana 실시간 확인 — 서비스별 자원 사용량, 에러율

## 성과 지표

| 지표 | 측정 방법 |
|------|----------|
| Rate Limiter 적용 전/후 서비스 안정성 | 에러율 비교 (5xx 응답) |
| rJMX-Exporter vs java jmx_exporter | 메모리 사용량 비교 (`docker stats`) |
| 전체 시스템 P99 레이턴시 | k6 summary report |
| Rate Limiter 정확도 | 허용/거부 비율 vs 설정값 일치 여부 |
| 결제 멱등성 | 중복 결제 건수 = 0 |

## 산출물

- [ ] `load-tests/` — k6 테스트 스크립트
- [ ] `load-tests/results/` — 테스트 결과 리포트
- [ ] `docs/results/` — 성과 분석 문서
- [ ] Grafana 대시보드 스크린샷

## 완료 조건

- [ ] `docker compose up` 한 번으로 11개 서비스 전체 기동
- [ ] k6 4개 시나리오 실행 완료
- [ ] Rate Limiter ON/OFF 비교 데이터 확보
- [ ] rJMX-Exporter 메모리 사용량 < 10MB 확인
- [ ] 성과 분석 문서 작성
