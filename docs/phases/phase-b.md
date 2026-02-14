# Phase B: Rate Limiter 통합

> moalog-server의 AI 엔드포인트에 distributed-rate-limiter를 적용한다.

## 목표

- AI 분석/가이드 요청에 사용자별 Rate Limiting 적용
- 전체 API에 IP 기반 Rate Limiting 적용
- OpenAI 호출에 서비스 전체 Rate Limiting 적용 (비용 보호)
- Rate Limit 초과 시 429 + Retry-After 응답

## 선행 조건

- Phase A 완료 (moalog-server Docker화)

## Rate Limit 정책

| 대상 | 알고리즘 | 제한 | 키 |
|------|---------|------|-----|
| AI 분석 (사용자별) | Token Bucket | 분당 5회, burst 3 | `user:{id}:ai-analysis` |
| AI 가이드 (사용자별) | Token Bucket | 분당 10회 | `user:{id}:ai-guide` |
| 전체 API (IP별) | Sliding Window | 분당 100회 | `ip:{addr}` |
| OpenAI 호출 (서비스 전체) | Sliding Window | 초당 20회 | `global:openai` |

## 작업 목록

### B-1. rate-limiter Docker 이미지 빌드

**현재 상태**: `distributed-rate-limiter/Dockerfile` 존재 (Phase 8 완료)

**해야 할 것**:
- Dockerfile 검증 및 이미지 빌드 테스트
- rate-limiter의 설정 파일에 moalog 전용 정책 추가

---

### B-2. docker-compose에 rate-limiter + Redis 추가

**위치**: `moalog-server/docker-compose.yaml` 확장

```yaml
services:
  # Phase A 서비스들...
  rate-limiter:     # Kotlin/WebFlux (port 8082)
  redis:            # Redis 7 (port 6379)
```

---

### B-3. moalog-server Rate Limit 미들웨어

**통합 방식 선택**:
- **Option A**: moalog-server → rate-limiter HTTP 호출 (서비스 간 통신)
- **Option B**: moalog-server가 Redis 직접 접근 (rate-limiter의 Lua script 재사용)

**권장**: Option A (서비스 간 의존성 최소화, rate-limiter의 로직을 그대로 활용)

**수정 대상**: `moalog-server` 레포
- 새 미들웨어 또는 Axum layer 추가
- AI 핸들러 라우트에 rate limit layer 적용

---

### B-4. 429 응답 포맷 통일

moalog-server의 에러 포맷에 맞춤:
```json
{
  "isSuccess": false,
  "code": "RATE_LIMIT_EXCEEDED",
  "message": "요청 한도를 초과했습니다. 잠시 후 다시 시도해주세요.",
  "result": null
}
```
+ `Retry-After` 헤더 포함

---

### B-5. Rate Limit 메트릭 노출

- rate-limiter의 Micrometer 메트릭 활용
- 거부된 요청 수, 현재 토큰 잔량 등

## 완료 조건

- [ ] AI 분석 요청 6회 연속 → 6번째에서 429 응답
- [ ] 다른 사용자는 영향 없음 (사용자별 격리)
- [ ] IP 기반 전체 API 제한 동작
- [ ] Retry-After 헤더 정확한 값 반환
- [ ] rate-limiter 장애 시 Fail Open (서비스 정상 동작)
