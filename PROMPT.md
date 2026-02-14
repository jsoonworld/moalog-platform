# Performance Engineering Platform — 통합 개발 프롬프트

## 프로젝트 개요

4개의 독립 마이크로서비스를 연결하여 하나의 프로덕션급 시스템으로 통합하는 프로젝트입니다.
핵심 서비스(moalog-server)를 중심으로, 트래픽 보호 · 결제 · 모니터링을 붙여 실제 운영 가능한 아키텍처를 구성합니다.

```
사용자 요청
    │
    ▼
┌──────────────────────────────────┐
│  distributed-rate-limiter        │  ← 트래픽 보호 (과부하 방지)
│  Kotlin / Spring WebFlux / Redis │
│  Token Bucket, Sliding Window    │
└──────────────┬───────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌─────────────┐  ┌──────────────┐
│ moalog-server│  │ fluxpay-engine│
│ Rust / Axum  │  │ Java / WebFlux│
│ AI 회고 서비스 │  │ 결제 엔진      │
│ (핵심 서비스)  │─→│ (과금 처리)    │
└──────┬──────┘  └──────┬───────┘
       │                │
       ▼                ▼
   ┌────────┐     ┌───────────┐
   │ OpenAI │     │TossPayments│
   └────────┘     └───────────┘

── 모니터링 ──────────────────────────
┌──────────────────────────────────┐
│  rJMX-Exporter (Rust / Axum)     │
│  → FluxPay, Rate Limiter JVM    │
│  → Jolokia → Prometheus format  │
└──────────────┬───────────────────┘
               ▼
       Prometheus → Grafana
```

---

## 레포지토리 구조

```
performance/
├── moalog-server/            → github.com/jsoonworld/moalog-server (Rust/Axum)
├── distributed-rate-limiter/ → github.com/jsoonworld/distributed-rate-limiter (Kotlin/WebFlux)
├── fluxpay-engine/           → github.com/jsoonworld/fluxpay-engine (Java/WebFlux)
└── rJMX-Exporter/            → github.com/jsoonworld/rJMX-Exporter (Rust/Axum)
```

각 프로젝트는 독립 레포지토리를 가지며, 코드 수정은 각 레포에서 진행합니다.
통합은 moalog-server의 docker-compose.yaml에서 전체 서비스를 엮어 실행합니다.

---

## 각 프로젝트 현재 상태

### 1. moalog-server (중심 서비스)
- **언어**: Rust 2021 / Axum 0.7 / SeaORM / MySQL 8
- **상태**: 30+ API 완성, AWS(EC2+RDS) 배포, 실사용자 있음
- **기능**: 소셜 로그인(Google/Kakao), 회고룸 CRUD, 5가지 회고 포맷, AI 분석(GPT), PDF 내보내기, 초대코드, 댓글/좋아요
- **DB 테이블**: member, retro_room, retrospect, response, response_comment, response_like, member_retro_room, member_response, member_retro, assistant_usage, retro_reference
- **빠진 것**: Rate Limiting 없음, 결제 없음, Docker 없음, 모니터링 미흡
- **기본 브랜치**: dev
- **코드 위치**: codes/server/ 하위

### 2. distributed-rate-limiter (트래픽 보호)
- **언어**: Kotlin / Spring WebFlux / Redis
- **상태**: Phase 1~8 완료 (Docker 컨테이너화까지)
- **모듈**: rate-limiter-core, rate-limiter-app, rate-limiter-spring-boot-starter
- **알고리즘**: Token Bucket (burst 허용), Sliding Window Log (정확한 제한)
- **특징**: Redis Lua Script 원자 연산, Fail Open 정책, Micrometer 메트릭, 80%+ 테스트 커버리지
- **기본 브랜치**: develop
- **현재 브랜치**: feature/phase-8-containerization

### 3. fluxpay-engine (결제 엔진)
- **언어**: Java 21 / Spring WebFlux / R2DBC / PostgreSQL
- **상태**: Phase 1~2 진행중
- **기능**: 주문→결제→환불 Saga, 멱등성(Redis), Webhook(inbound/outbound), PG 연동(TossPayments)
- **특징**: 리액티브 전구간, 이벤트 소싱 패턴, 서명 검증
- **기본 브랜치**: main
- **현재 브랜치**: feature/phase2-payment-enhancement

### 4. rJMX-Exporter (JVM 모니터링)
- **언어**: Rust / Axum / Tokio
- **상태**: Phase 3 완료
- **기능**: Jolokia HTTP → JMX MBean 수집 → Prometheus /metrics 노출
- **특징**: Java jmx_exporter 대비 10x 적은 메모리 (<10MB), YAML 설정 기반 다중 타겟
- **기본 브랜치**: develop

---

## 통합 개발 로드맵

### Phase A: moalog-server 기반 정리
> moalog-server를 독립 실행 가능한 상태로 만듭니다.

**작업 목록:**
1. CORS 하드코딩 제거 → `ALLOWED_ORIGINS` 환경변수로 추출 (src/main.rs:262-269)
2. Dockerfile 작성 (멀티스테이지 빌드: cargo build → slim runtime)
3. docker-compose.yaml 작성 (moalog-server + MySQL)
4. .env.example 정비 (시크릿 패턴만 남기기)
5. 로컬 개발 환경 one-command 실행 확인 (`docker compose up`)

**기술 포인트:**
- Rust 멀티스테이지 Docker 빌드 (빌드 이미지 → runtime 이미지)
- MySQL 초기화 스크립트 (SeaORM auto-schema가 있지만 Docker init에도 대비)
- Health check 엔드포인트 활용

---

### Phase B: Rate Limiter 통합
> moalog-server의 AI 엔드포인트에 Rate Limiting을 적용합니다.

**적용 대상 엔드포인트:**
- `POST /api/retrospects/{id}/ai-analysis` — AI 분석 (OpenAI 비용 발생)
- `POST /api/retrospects/{id}/ai-guide` — AI 가이드 생성
- 전체 API — 비인증 요청 제한

**Rate Limit 정책:**
| 대상 | 알고리즘 | 제한 |
|------|---------|------|
| AI 분석 (사용자별) | Token Bucket | 분당 5회, burst 3 |
| AI 가이드 (사용자별) | Token Bucket | 분당 10회 |
| 전체 API (IP별) | Sliding Window | 분당 100회 |
| OpenAI 호출 (서비스 전체) | Sliding Window | 초당 20회 (비용 보호) |

**통합 방식:**
- distributed-rate-limiter를 독립 서비스로 docker-compose에 추가
- moalog-server → rate-limiter HTTP 호출 (or Redis 직접 공유)
- Rate Limit 초과 시 429 응답 + `Retry-After` 헤더

**작업 목록:**
1. rate-limiter Docker 이미지 빌드/배포 설정
2. docker-compose.yaml에 rate-limiter + Redis 추가
3. moalog-server에 rate limit 미들웨어 또는 프록시 구성
4. 429 응답 포맷 통일 (moalog 에러 포맷에 맞춤)
5. Rate Limit 현황 메트릭 노출

---

### Phase C: 모니터링 통합
> rJMX-Exporter + Prometheus + Grafana로 전체 시스템 관측성을 확보합니다.

**모니터링 대상:**
| 서비스 | 수집 방법 | 주요 메트릭 |
|--------|----------|------------|
| moalog-server (Rust) | 자체 /metrics 엔드포인트 | 요청 TPS, 레이턴시, DB 커넥션 풀 |
| rate-limiter (Kotlin/JVM) | Jolokia → rJMX-Exporter | JVM Heap, GC, Thread pool, Redis 커넥션 |
| fluxpay-engine (Java/JVM) | Jolokia → rJMX-Exporter | JVM Heap, GC, 결제 TPS, DB 커넥션 |
| Redis | redis_exporter | 메모리, 커넥션 수, 명령 처리량 |
| MySQL | mysqld_exporter | 쿼리 처리량, slow query, 커넥션 |

**작업 목록:**
1. rate-limiter, fluxpay-engine에 Jolokia JVM 에이전트 추가
2. rJMX-Exporter 설정 (targets.yaml에 두 JVM 앱 등록)
3. moalog-server에 Prometheus /metrics 엔드포인트 추가 (metrics-rs 등)
4. docker-compose.yaml에 Prometheus + Grafana + rJMX-Exporter 추가
5. Grafana 대시보드 구성 (시스템 개요, 서비스별 상세)

---

### Phase D: FluxPay 결제 연동
> moalog-server에 프리미엄 플랜을 추가하고, FluxPay로 결제를 처리합니다.

**플랜 설계 (예시):**
| 플랜 | AI 분석 | 가격 |
|------|--------|------|
| Free | 월 3회 | 무료 |
| Pro | 무제한 + PDF | 월 9,900원 |
| Team | Pro + 10명 이상 룸 | 월 29,900원 |

**연동 흐름:**
```
사용자 결제 요청
    → moalog-server: 플랜 선택/결제 요청 API
    → fluxpay-engine: POST /api/v1/payments (주문 생성)
    → TossPayments: 결제 승인
    → fluxpay-engine: Webhook → 결제 완료 이벤트
    → moalog-server: 플랜 활성화 (assistant_usage 제한 해제)
```

**작업 목록:**
1. moalog-server DB에 subscription/plan 테이블 추가
2. 플랜 관리 API (조회, 구독, 해지)
3. fluxpay-engine 연동 HTTP 클라이언트
4. assistant_usage 제한 로직에 플랜 반영
5. docker-compose.yaml에 fluxpay-engine + PostgreSQL 추가

---

### Phase E: 통합 인프라 & 부하 테스트
> 전체 시스템을 하나의 docker-compose로 실행하고, 부하 테스트로 검증합니다.

**최종 docker-compose 서비스 목록:**
```yaml
services:
  # 핵심 서비스
  moalog-server:        # Rust (port 8080)
  fluxpay-engine:       # Java (port 8081)
  rate-limiter:         # Kotlin (port 8082)

  # 모니터링
  rjmx-exporter:        # Rust (port 9090)
  prometheus:           # (port 9091)
  grafana:              # (port 3000)

  # 인프라
  mysql:                # moalog DB (port 3306)
  postgres:             # fluxpay DB (port 5432)
  redis:                # rate-limiter + fluxpay 멱등성 (port 6379)
```

**부하 테스트 시나리오 (k6):**
1. 일반 API 호출 (GET /api/retrospects) — baseline TPS 측정
2. AI 분석 요청 폭주 — Rate Limiter 동작 확인
3. 동시 결제 요청 — FluxPay 멱등성 + Saga 검증
4. Rate Limit + 모니터링 — Grafana에서 실시간 확인

**성과 지표:**
- Rate Limiter 적용 전/후 서비스 안정성 비교
- rJMX-Exporter vs java jmx_exporter 메모리 사용량 비교
- 전체 시스템 P99 레이턴시, 에러율

---

## 기술 스택 요약

| 레이어 | 기술 |
|--------|------|
| 핵심 서비스 | Rust, Axum 0.7, SeaORM, MySQL 8 |
| 결제 엔진 | Java 21, Spring WebFlux, R2DBC, PostgreSQL |
| Rate Limiter | Kotlin, Spring WebFlux, Redis 7, Lua Script |
| JVM 모니터링 | Rust, Axum, Jolokia, Prometheus format |
| 관측성 | Prometheus, Grafana, Micrometer |
| 컨테이너 | Docker, Docker Compose |
| 부하 테스트 | k6 |

---

## 작업 원칙

1. **각 프로젝트는 각자의 레포에서 수정** — 통합은 docker-compose로만 엮음
2. **서비스 간 통신은 REST API** — 코드 의존성 없음
3. **각 프로젝트의 기존 컨벤션 유지** — moalog는 Rust 컨벤션, rate-limiter는 Kotlin 컨벤션
4. **TDD 원칙** — 모든 프로젝트에서 테스트 선행
5. **Docker 우선** — 로컬 개발도 docker compose up 한 번으로 전체 실행
