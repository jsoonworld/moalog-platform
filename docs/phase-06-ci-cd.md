# Phase 06: CI/CD & 자동화

## 목표

오케스트레이션 레포에 CI/CD 파이프라인을 구축하고, 반복 작업을 자동화한다.

---

## 현재 상태

| 레포 | CI/CD | 비고 |
|------|-------|------|
| moalog-server | deploy.yml, pr-check.yml, terraform.yml | EC2 배포 포함 |
| distributed-rate-limiter | ci.yml, coverage.yml, docker-build.yml, pr.yml, release.yml | 가장 완성도 높음 |
| rJMX-Exporter | ci.yaml, release.yaml | develop → main 전략 |
| fluxpay-engine | **없음** | CI/CD 미구성 |
| moalog-platform (오케스트레이션) | **없음** | .github/workflows 없음, Makefile 없음 |

---

## 작업 목록

### 6-1. Makefile 작성

오케스트레이션 레포 루트에 공통 명령어 자동화.

```makefile
# 예시 타겟
up          # docker compose up -d (포트 env 포함)
down        # docker compose down
ps          # docker compose ps
logs        # docker compose logs -f [service]
build       # docker compose build --no-cache
restart     # down + up
health      # 전 서비스 healthcheck curl
clean       # docker compose down -v (볼륨 포함 삭제)
test-load   # k6 부하 테스트 전체 실행
```

**파일**: `moalog-platform/Makefile`

**핵심 포인트**:
- 포트 환경변수(REDIS_PORT, MYSQL_PORT 등) 기본값 내장
- docker-compose.yaml 경로 → `moalog-server/docker-compose.yaml`
- `make health`로 모든 서비스 상태 한 번에 확인

---

### 6-2. 오케스트레이션 GitHub Actions

**파일**: `moalog-platform/.github/workflows/integration.yml`

**트리거**: push to main, PR to main

**Job 1 — Validate**:
- docker-compose.yaml 문법 검증 (`docker compose config`)
- .env.example 존재 여부 확인
- Prometheus config 검증

**Job 2 — Smoke Test**:
- Docker Compose로 전체 스택 기동
- 각 서비스 healthcheck 통과 대기
- 기본 API 호출 검증 (health, actuator)
- Prometheus targets UP 확인
- 결과 리포트 → PR comment

**Job 3 — Load Test (선택적)**:
- k6 설치 + 실행 (baseline 시나리오만)
- p95 임계값 초과 시 warning
- 결과 artifact 저장

---

### 6-3. fluxpay-engine CI/CD 워크플로우

**파일**: `fluxpay-engine/.github/workflows/ci.yml`

| 단계 | 내용 |
|------|------|
| Build | Gradle build (jammy JDK 21) |
| Test | 단위 테스트 + 통합 테스트 |
| Lint | Checkstyle / SpotBugs |
| Docker | 이미지 빌드 검증 |

**파일**: `fluxpay-engine/.github/workflows/pr.yml`

| 단계 | 내용 |
|------|------|
| PR 제목 | Semantic versioning 검증 |
| 리뷰 | 자동 라벨링 (size, path) |

---

### 6-4. Docker 이미지 보안 스캔

모든 서비스 Dockerfile에 Trivy 스캔 추가.

```yaml
# 각 서비스 CI에 추가
- name: Trivy scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ service-image }}
    severity: 'CRITICAL,HIGH'
    exit-code: '1'
```

---

## 완료 기준

- [x] `make up` / `make down` / `make health` 동작 확인
- [x] 오케스트레이션 PR 시 Smoke Test 자동 실행
- [x] fluxpay-engine PR 시 build + test 자동 실행
- [x] Docker 이미지 CRITICAL 취약점 0건 (Trivy 스캔 구성)
