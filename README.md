# Moalog Platform

moalog-server를 중심으로 트래픽 보호 · 결제 · 모니터링 서비스를 통합하는 오케스트레이션 레포입니다.

## Architecture

```
사용자 요청
    │
    ▼
┌──────────────────────────────────┐
│  distributed-rate-limiter        │  ← 트래픽 보호
│  Kotlin / Spring WebFlux / Redis │
└──────────────┬───────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌─────────────┐  ┌──────────────┐
│ moalog-server│  │ fluxpay-engine│
│ Rust / Axum  │  │ Java / WebFlux│
│ AI 회고 서비스 │  │ 결제 엔진      │
└──────┬──────┘  └──────┬───────┘
       │                │
       ▼                ▼
   ┌────────┐     ┌───────────┐
   │ OpenAI │     │TossPayments│
   └────────┘     └───────────┘

── 모니터링 ──────────────────────────
┌──────────────────────────────────┐
│  rJMX-Exporter (Rust / Axum)     │
│  → Jolokia → Prometheus format  │
└──────────────┬───────────────────┘
               ▼
       Prometheus → Grafana
```

## Sub-repositories

| 서비스 | 기술 | 레포 |
|--------|------|------|
| [moalog-server](https://github.com/jsoonworld/moalog-server) | Rust / Axum / SeaORM / MySQL | 핵심 서비스 (AI 회고) |
| [distributed-rate-limiter](https://github.com/jsoonworld/distributed-rate-limiter) | Kotlin / Spring WebFlux / Redis | 트래픽 보호 |
| [fluxpay-engine](https://github.com/jsoonworld/fluxpay-engine) | Java / Spring WebFlux / R2DBC / PostgreSQL | 결제 엔진 |
| [rJMX-Exporter](https://github.com/jsoonworld/rJMX-Exporter) | Rust / Axum / Tokio | JVM 모니터링 |

## 이 레포가 관리하는 것

이 레포는 **오케스트레이션 레포**입니다. 각 서비스의 코드는 해당 레포에서 관리합니다.

- `docker-compose.yaml` — 전체 시스템 통합 실행
- `monitoring/` — Prometheus, Grafana 설정
- `load-tests/` — k6 부하 테스트 스크립트

## Quick Start

```bash
# 전체 시스템 실행 (Phase E 완료 후)
cp .env.example .env
# .env 파일의 값을 수정
docker compose up
```
