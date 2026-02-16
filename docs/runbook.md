# Moalog Platform — Operational Runbook

## Quick Reference

| Command | Purpose |
|---------|---------|
| `make up` | Start all services |
| `make down` | Stop all services |
| `make restart` | Restart all services |
| `make ps` | Show container status |
| `make health` | Check health of every service |
| `make logs SERVICE=<name>` | View service logs |
| `make clean` | Stop + remove volumes (full reset) |
| `make test-load` | Run baseline load test |
| `make test-chaos` | Run all chaos/failure tests |
| `make test-circuit-breaker` | Run circuit breaker verification |

---

## Service Health Endpoints

| Service | URL | Expected |
|---------|-----|----------|
| moalog-server | `http://localhost:8090/health` | `healthy` |
| rate-limiter | `http://localhost:8082/actuator/health` | `{"status":"UP"}` |
| fluxpay-engine | `http://localhost:8081/api/v1/health` | `200 OK` |
| redis | `docker exec moalog-redis redis-cli --no-auth-warning -a $REDIS_PASSWORD ping` | `PONG` |
| mysql | `docker exec moalog-mysql mysqladmin ping -h localhost -u root -p$MYSQL_ROOT_PASSWORD` | `alive` |
| postgres | `docker exec fluxpay-postgres pg_isready -U fluxpay` | `accepting` |
| kafka | `docker exec fluxpay-kafka kafka-broker-api-versions --bootstrap-server localhost:9092` | version list |
| prometheus | `http://localhost:9091/-/healthy` | `200` |
| grafana | `http://localhost:3001/api/health` | `200` |
| alertmanager | `http://localhost:9095/-/healthy` | `200` |
| loki | `http://localhost:3100/ready` | `200` |
| jaeger | `http://localhost:16686/` | `200` |

---

## Failure Scenarios

### 1. Service Down (Generic)

**Symptoms**: `make health` shows "down" for a service.

**Diagnosis**:
```bash
make ps                              # Check container status
docker logs <container-name> --tail 50  # View recent logs
docker inspect <container-name> --format='{{.State.Status}}'
```

**Recovery**:
```bash
docker compose -f moalog-server/docker-compose.yaml restart <service-name>
```

**Escalation**: If restart fails, check volumes and disk space.

---

### 2. Redis Down

**Impact**:
- Rate limiting fails open (all requests pass through without rate limiting)
- FluxPay idempotency checks unavailable
- No data loss (rate limiter state is ephemeral)

**Diagnosis**:
```bash
docker logs moalog-redis --tail 20
docker exec moalog-redis redis-cli --no-auth-warning -a $REDIS_PASSWORD ping
docker exec moalog-redis redis-cli --no-auth-warning -a $REDIS_PASSWORD info memory
```

**Recovery**:
```bash
docker compose -f moalog-server/docker-compose.yaml restart redis
```

**Post-recovery**:
- Verify rate-limiter reconnects: check rate-limiter logs for "Connected to Redis"
- Verify FluxPay reconnects: `curl http://localhost:8081/api/v1/health`

---

### 3. MySQL Down

**Impact**:
- moalog-server returns 500 on all DB-dependent endpoints
- `/health` reports unhealthy
- No data loss if MySQL volume is intact

**Diagnosis**:
```bash
docker logs moalog-mysql --tail 30
docker exec moalog-mysql mysqladmin ping -h localhost -u root -pmoalog_local
docker system df  # Check disk space
```

**Recovery**:
```bash
docker compose -f moalog-server/docker-compose.yaml restart mysql
# Wait 30-60s for MySQL to initialize
make health
```

**Data safety**: MySQL data persists in `mysql_data` volume. Only `make clean` removes it.

---

### 4. Kafka Down

**Impact**:
- FluxPay outbox events queue in the database but cannot be published
- Payment event processing halts
- Read APIs and direct payment operations may still work
- Events will be retried when Kafka recovers

**Diagnosis**:
```bash
docker logs fluxpay-kafka --tail 30
docker exec fluxpay-kafka kafka-topics --list --bootstrap-server localhost:9092
docker exec fluxpay-kafka kafka-consumer-groups --bootstrap-server localhost:9092 --list
```

**Recovery**:
```bash
# Zookeeper must be running first
docker compose -f moalog-server/docker-compose.yaml restart fluxpay-zookeeper
sleep 10
docker compose -f moalog-server/docker-compose.yaml restart fluxpay-kafka
```

**Post-recovery**: Check consumer lag to verify backlog processing.

---

### 5. FluxPay Engine Down

**Impact**:
- Payment API returns 502 from moalog-server (`FluxPayServiceError`)
- Read APIs (retro-rooms, retrospects, AI) continue working normally
- moalog-server remains healthy

**Diagnosis**:
```bash
docker logs fluxpay-engine --tail 50
docker inspect fluxpay-engine --format='{{.State.OOMKilled}}'  # Check for OOM
```

**Recovery**:
```bash
docker compose -f moalog-server/docker-compose.yaml restart fluxpay-engine
# Wait 90-120s for JVM + OTel agent startup
curl http://localhost:8081/api/v1/health
```

---

### 6. Rate Limiter Down

**Impact**:
- moalog-server activates Fail Open mode (all requests bypass rate limiting)
- No 5xx errors — requests proceed normally but without rate protection
- In-process rate limiters (AI analysis, OpenAI global) still function

**Diagnosis**:
```bash
docker logs moalog-rate-limiter --tail 30
```

**Recovery**:
```bash
docker compose -f moalog-server/docker-compose.yaml restart rate-limiter
# Wait 60-90s for JVM startup
curl http://localhost:8082/actuator/health
```

---

### 7. Redis Memory Pressure

**Diagnosis**:
```bash
docker exec moalog-redis redis-cli --no-auth-warning -a $REDIS_PASSWORD info memory
docker exec moalog-redis redis-cli --no-auth-warning -a $REDIS_PASSWORD config get maxmemory
```

**Recovery**:
- Check `maxmemory-policy` (should be `allkeys-lru` for cache workloads)
- If safe to flush: `docker exec moalog-redis redis-cli --no-auth-warning -a $REDIS_PASSWORD FLUSHDB`

**Prevention**: Set `maxmemory` in Redis config based on available container memory.

---

### 8. Disk Space Issues

**Diagnosis**:
```bash
docker system df              # Docker disk usage
docker system df -v           # Detailed breakdown
df -h                         # Host disk usage
```

**Recovery**:
```bash
docker system prune           # Remove unused containers, networks, images
docker volume prune           # Remove unused volumes (CAREFUL: may delete data)
```

**Log rotation**: Loki/Promtail handle log retention automatically. Docker log size can be limited via daemon.json `log-opts`.

---

### 9. Full Stack Recovery

When multiple services are in a bad state or after a system reboot:

```bash
# 1. Stop everything cleanly
make down

# 2. Verify no orphan containers
docker ps -a | grep moalog

# 3. Clean start (preserves data volumes)
make up

# 4. Wait for all services to initialize (2-3 minutes)
sleep 180

# 5. Verify health
make health

# 6. If data was lost (used make clean), re-seed test data
./load-tests/setup-test-data.sh
```

### 10. Full Data Reset

When you need to start from scratch:

```bash
make clean          # Stops all containers and removes volumes
make up             # Fresh start
sleep 180           # Wait for initialization
make health         # Verify
./load-tests/setup-test-data.sh  # Re-seed test data
```

---

## Monitoring Links

| Tool | URL | Credentials |
|------|-----|-------------|
| Grafana | http://localhost:3001 | admin / (see .env `GRAFANA_ADMIN_PASSWORD`) |
| Prometheus | http://localhost:9091 | — |
| Alertmanager | http://localhost:9095 | — |
| Jaeger | http://localhost:16686 | — |
| Loki | http://localhost:3100 | — (via Grafana Explore) |

### Grafana Dashboards

- **Platform Overview**: System-wide metrics, request rates, error rates
- **JVM Dashboard**: Heap, GC, threads for rate-limiter and fluxpay-engine
- **Redis Dashboard**: Memory, connections, commands/sec
- **MySQL Dashboard**: Queries, connections, InnoDB metrics

---

## Alert Response

Alert rules are defined in `moalog-server/monitoring/alert-rules.yml`. Key alerts:

| Alert | Severity | Action |
|-------|----------|--------|
| `HighErrorRate` | critical | Check service logs, investigate root cause |
| `HighLatency` | warning | Check for resource contention, DB slow queries |
| `ServiceDown` | critical | Follow service recovery procedure above |
| `DiskSpaceRunningLow` | warning | Run `docker system prune` |
| `HighMemoryUsage` | warning | Check for memory leaks, restart service |

---

## Security Notes

- All passwords are managed via `.env` file (see `.env.example` for defaults)
- Redis requires authentication (`--requirepass`)
- Actuator endpoints are authenticated (basic auth)
- All custom application containers run as non-root user (`appuser:1001`)
- Docker volumes store persistent data — protect volume mount paths
- Change all default passwords before any non-local deployment

---

## Resilience Patterns

| Service Call | Timeout | Failure Behavior |
|-------------|---------|------------------|
| moalog-server → rate-limiter | 500ms | **Fail Open** — request passes without rate limiting |
| moalog-server → fluxpay-engine | 5s | Returns `FluxPayServiceError` to caller |
| moalog-server → OpenAI | 30s | Returns `AiServiceUnavailable` to caller |
| moalog-server → OAuth | 10s | Returns `SocialAuthFailed` to caller |
| rate-limiter → Redis | Spring default | Depends on Spring Data Redis config |
| fluxpay-engine → PostgreSQL | R2DBC default | Connection pool timeout |
| fluxpay-engine → Kafka | Spring default | Outbox queues events for retry |
