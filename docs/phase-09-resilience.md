# Phase 09: 회복탄력성 & 보안

## 목표

장애 상황에서 시스템이 어떻게 반응하는지 검증하고, 보안 취약점을 제거한다.

---

## 현재 상태

| 항목 | 상태 |
|------|------|
| k6 부하 테스트 | 완성 (4 시나리오, 정상 경로) |
| 장애 주입 테스트 | **없음** |
| Circuit Breaker | moalog-server에 구현됨 (검증 안 됨) |
| 보안 스캔 | **없음** |
| 비밀번호 정책 | 기본값 사용 (admin/admin, moalog_local 등) |

---

## 작업 목록

### 9-1. 장애 시나리오 테스트

Docker Compose 환경에서 수동 장애 주입으로 시스템 반응을 검증한다.

**테스트 시나리오**:

| # | 장애 | 방법 | 기대 결과 |
|---|------|------|----------|
| 1 | Redis 다운 | `docker stop moalog-redis` | rate-limiter Fail Open (요청 통과), 에러 로그 |
| 2 | MySQL 다운 | `docker stop moalog-mysql` | moalog-server 503, healthcheck fail |
| 3 | Rate Limiter 다운 | `docker stop moalog-rate-limiter` | moalog-server가 rate-limit 없이 요청 처리 |
| 4 | Kafka 다운 | `docker stop fluxpay-kafka` | fluxpay-engine 결제 처리 불가, outbox 큐잉 |
| 5 | FluxPay 다운 | `docker stop fluxpay-engine` | moalog-server 결제 API 502, 나머지 정상 |
| 6 | 메모리 압박 | `docker update --memory 64m moalog-server` | OOM 처리, 자동 재시작 |
| 7 | 네트워크 지연 | `tc qdisc add dev eth0 delay 500ms` | 타임아웃 처리, Circuit Breaker 동작 |

**테스트 스크립트**: `load-tests/scenarios/chaos/`

```
chaos/
├── redis-failure.sh
├── mysql-failure.sh
├── rate-limiter-failure.sh
├── kafka-failure.sh
├── fluxpay-failure.sh
└── run-all.sh
```

각 스크립트는:
1. 사전 상태 확인 (모든 서비스 healthy)
2. 장애 주입
3. k6로 트래픽 전송 (30초)
4. 응답 코드/지연 수집
5. 서비스 복구
6. 복구 후 정상 동작 확인
7. 결과 리포트 출력

---

### 9-2. Circuit Breaker 검증

moalog-server의 외부 호출(rate-limiter, fluxpay, OpenAI)에 대한 Circuit Breaker 동작 확인.

**검증 항목**:

| 대상 | 상태 | 기대 동작 |
|------|------|----------|
| rate-limiter 연결 실패 | OPEN | 요청 bypass (Fail Open) |
| fluxpay 연결 실패 | OPEN | 결제 API만 503, 나머지 정상 |
| fluxpay 느린 응답 (>3s) | HALF_OPEN | 일부 요청만 전달, 나머지 fallback |
| 복구 후 | CLOSED | 정상 라우팅 재개 |

**k6 검증 시나리오**: `load-tests/scenarios/circuit-breaker.js`
- 정상 트래픽 1분 → 장애 주입 → 1분 관찰 → 복구 → 1분 관찰
- Circuit Breaker 상태 전이 메트릭 수집

---

### 9-3. 보안 강화

**즉시 적용**:

| 항목 | 현재 | 변경 |
|------|------|------|
| MySQL root 비밀번호 | `moalog_local` | 랜덤 생성, .env에서 관리 |
| Grafana admin | `admin/admin` | 초기 비밀번호 변경 강제 |
| Actuator 인증 | `actuator/admin` | 강한 비밀번호 |
| PostgreSQL | `fluxpay/fluxpay` | 별도 비밀번호 |
| Redis | 인증 없음 | `requirepass` 설정 |

**.env.example 정비**:
```env
# === 필수 시크릿 (값 변경 필요) ===
MYSQL_ROOT_PASSWORD=       # 강한 비밀번호 설정
JWT_SECRET=                # 최소 32자 랜덤 문자열
OPENAI_API_KEY=            # OpenAI API 키
TOSS_SECRET_KEY=           # Toss Payments 시크릿 키

# === 선택 (기본값 사용 가능) ===
GRAFANA_ADMIN_PASSWORD=admin
ACTUATOR_PASSWORD=admin
```

**Docker 이미지 보안**:
- 모든 컨테이너 non-root 실행 확인
- readOnlyRootFilesystem 적용 (가능한 서비스)
- Docker Content Trust 활성화

---

### 9-4. 장애 복구 절차서

**파일**: `docs/runbook.md`

| 장애 유형 | 진단 명령 | 복구 절차 |
|----------|----------|----------|
| 서비스 다운 | `make ps` + `make health` | `docker compose restart {service}` |
| DB 연결 실패 | `docker logs moalog-mysql` | 볼륨 확인 → 재시작 → 백업 복원 |
| Redis 메모리 초과 | `redis-cli info memory` | maxmemory 설정 확인 → eviction policy |
| Kafka 파티션 리밸런싱 | `kafka-topics --describe` | Consumer group 재설정 |
| 디스크 부족 | `docker system df` | `docker system prune` + 로그 로테이션 |
| 전체 장애 | `make down && make clean && make up` | 볼륨 삭제 후 재구성 |

---

## 완료 기준

- [ ] 7개 장애 시나리오 테스트 스크립트 작성 + 실행
- [ ] Circuit Breaker OPEN/HALF_OPEN/CLOSED 전이 확인
- [ ] 기본 비밀번호 전면 교체, .env.example 정비
- [ ] 장애 복구 절차서 완성
- [ ] 모든 컨테이너 non-root 실행 확인
