# Phase A: moalog-server 기반 정리

> moalog-server를 독립 실행 가능한 Docker 컨테이너로 만든다.

## 목표

- CORS 하드코딩 제거 → 환경변수 기반 설정
- 멀티스테이지 Dockerfile 작성
- docker-compose로 moalog-server + MySQL one-command 실행
- .env.example 정비

## 작업 목록

### A-1. CORS 환경변수 추출

**현재 문제**: `src/main.rs:258-265`에 6개 origin 하드코딩

```rust
// AS-IS (하드코딩)
let allowed_origins = [
    "http://localhost:3000",
    "http://localhost:5173",
    "https://www.moalog.me",
    // ...
];
```

**해야 할 것**:
- `ALLOWED_ORIGINS` 환경변수 추가 (쉼표 구분)
- 기본값: `http://localhost:3000,http://localhost:5173`
- 프로덕션: `ALLOWED_ORIGINS=https://www.moalog.me,https://moalog.me,https://moaofficial.kr`

**수정 대상**: `moalog-server` 레포 (`codes/server/src/main.rs`)

---

### A-2. Dockerfile 작성 (멀티스테이지)

**위치**: `moalog-server/codes/server/Dockerfile`

**구조**:
```
Stage 1: cargo-chef (의존성 캐싱)
Stage 2: cargo build --release
Stage 3: debian-slim runtime (fonts 포함)
```

**핵심 포인트**:
- Rust 멀티스테이지 빌드로 최종 이미지 크기 최소화
- `fonts/` 디렉토리 복사 (PDF 생성에 NanumGothic 필요)
- Health check: `GET /health`

---

### A-3. docker-compose.yaml 작성

**위치**: `moalog-server/docker-compose.yaml` (moalog-server 레포 루트)

**서비스 구성**:
```yaml
services:
  moalog-server:    # Rust (port 8080)
  mysql:            # MySQL 8 (port 3306)
```

**핵심 포인트**:
- MySQL 초기화: SeaORM auto-schema가 있으므로 별도 init script 불필요 (단, DB 생성은 필요)
- Health check 설정
- Volume: MySQL 데이터 영속화
- Network: moalog-net

---

### A-4. .env.example 정비

**현재 상태**: `.env.example` 존재하나 Docker 환경 미반영

**추가할 항목**:
- `ALLOWED_ORIGINS` (CORS)
- `DATABASE_URL` Docker 내부 호스트 반영 (`mysql://mysql:3306/retrospect`)
- `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE` (docker-compose용)

---

### A-5. 로컬 실행 확인

**성공 기준**:
```bash
cd moalog-server
docker compose up
# → MySQL 기동 → moalog-server 기동 → GET /health 200 OK
```

## 완료 조건

- [ ] CORS가 환경변수로 설정 가능
- [ ] `docker compose up`으로 moalog-server + MySQL 기동
- [ ] `curl localhost:8080/health` → 200 응답
- [ ] `.env.example`에 모든 필수 환경변수 문서화
