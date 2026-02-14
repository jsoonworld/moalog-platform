# Phase D: FluxPay 결제 연동

> moalog-server에 프리미엄 플랜을 추가하고, FluxPay로 결제를 처리한다.

## 목표

- Free / Pro / Team 플랜 체계 도입
- FluxPay-engine을 통한 TossPayments 결제 연동
- AI 분석 사용량을 플랜에 따라 제한
- Webhook 기반 결제 완료 → 플랜 활성화

## 선행 조건

- Phase A 완료 (moalog-server Docker화)
- fluxpay-engine Phase 2 완료 (결제 Saga, 멱등성, Webhook)

## 플랜 설계

| 플랜 | AI 분석 | PDF 내보내기 | 룸 인원 | 가격 |
|------|--------|-------------|---------|------|
| Free | 월 3회 | X | 5명 | 무료 |
| Pro | 무제한 | O | 10명 | 월 9,900원 |
| Team | 무제한 | O | 무제한 | 월 29,900원 |

## 결제 흐름

```
1. 사용자: 플랜 선택 → moalog-server POST /api/subscriptions
2. moalog-server → fluxpay-engine: POST /api/v1/payments (주문 생성)
3. fluxpay-engine → TossPayments: 결제 승인 요청
4. TossPayments → fluxpay-engine: 결제 승인 Webhook
5. fluxpay-engine → moalog-server: 결제 완료 Webhook
6. moalog-server: subscription 테이블 업데이트 → 플랜 활성화
```

## 작업 목록

### D-1. moalog-server DB 스키마 추가

**새 테이블**:
- `subscription` — 사용자별 구독 정보
- `plan` — 플랜 정의 (Free/Pro/Team)
- `payment_history` — 결제 이력

**수정 대상**: `moalog-server` 레포 (SeaORM migration)

---

### D-2. 플랜/구독 관리 API

**엔드포인트**:
- `GET /api/plans` — 플랜 목록 조회
- `GET /api/subscriptions/me` — 내 구독 조회
- `POST /api/subscriptions` — 구독 시작 (결제 요청)
- `DELETE /api/subscriptions` — 구독 해지

---

### D-3. FluxPay-engine HTTP 클라이언트

**수정 대상**: `moalog-server` 레포

**해야 할 것**:
- `reqwest` 기반 FluxPay API 클라이언트
- 결제 생성, 결제 조회, 환불 요청
- 타임아웃, 재시도, 에러 핸들링

---

### D-4. AI 사용량 제한에 플랜 반영

**현재**: `assistant_usage` 테이블로 AI 사용량 추적 중

**변경**:
- Free 플랜: 월 3회 AI 분석 제한
- Pro/Team: 무제한
- 제한 초과 시 403 + 업그레이드 안내 메시지

---

### D-5. docker-compose에 fluxpay-engine 추가

```yaml
services:
  # 기존 서비스들...
  fluxpay-engine:   # Java (port 8081)
  postgres:         # FluxPay DB (port 5432)
```

## 완료 조건

- [ ] Free 사용자 → AI 분석 4번째 시도에서 403 + 업그레이드 안내
- [ ] 결제 완료 → Pro 플랜 활성화 → AI 무제한 사용 가능
- [ ] 구독 해지 → 다음 결제 주기부터 Free로 전환
- [ ] FluxPay 장애 시에도 기존 구독 유지 (Graceful degradation)
