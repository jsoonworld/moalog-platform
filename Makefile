# ============================================================
# Moalog Platform — Orchestration Makefile
# ============================================================
# Usage:
#   make up        — Start all services
#   make down      — Stop all services
#   make restart   — Restart all services
#   make ps        — Show service status
#   make logs      — Follow all logs (use SERVICE=name to filter)
#   make build     — Rebuild all images from scratch
#   make health    — Check health of every service
#   make clean     — Stop + remove volumes (full reset)
#   make test-load — Run k6 load tests
# ============================================================

# --- Port defaults (avoid host conflicts) ---
export REDIS_PORT       ?= 6382
export MYSQL_PORT       ?= 3307
export SERVER_PORT      ?= 8090
export RATE_LIMITER_PORT?= 8082
export FLUXPAY_PORT     ?= 8081
export FLUXPAY_POSTGRES_PORT ?= 5435
export KAFKA_PORT       ?= 9092
export ZOOKEEPER_PORT   ?= 2181
export PROMETHEUS_PORT  ?= 9091
export GRAFANA_PORT     ?= 3001
export ALERTMANAGER_PORT?= 9095
export LOKI_PORT        ?= 3100
export JAEGER_UI_PORT   ?= 16686

COMPOSE_FILE := moalog-server/docker-compose.yaml
COMPOSE      := docker compose -f $(COMPOSE_FILE)

.PHONY: up down restart ps logs build health clean test-load

# --- Core commands ---

up:
	$(COMPOSE) up -d
	@echo "\n=== Services starting ==="
	@echo "moalog-server  : http://localhost:$(SERVER_PORT)"
	@echo "rate-limiter   : http://localhost:$(RATE_LIMITER_PORT)"
	@echo "fluxpay-engine : http://localhost:$(FLUXPAY_PORT)"
	@echo "Prometheus     : http://localhost:$(PROMETHEUS_PORT)"
	@echo "Alertmanager   : http://localhost:$(ALERTMANAGER_PORT)"
	@echo "Grafana        : http://localhost:$(GRAFANA_PORT)  (admin/admin)"
	@echo "Loki           : http://localhost:$(LOKI_PORT)"
	@echo "Jaeger UI      : http://localhost:$(JAEGER_UI_PORT)"
	@echo ""

down:
	$(COMPOSE) down

restart: down up

ps:
	$(COMPOSE) ps

logs:
ifdef SERVICE
	$(COMPOSE) logs -f $(SERVICE)
else
	$(COMPOSE) logs -f
endif

build:
	$(COMPOSE) build --no-cache

# --- Health check ---

health:
	@echo "=== Service Health Check ==="
	@printf "%-22s" "moalog-server:" ; \
	  curl -sf http://localhost:$(SERVER_PORT)/health > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "rate-limiter:" ; \
	  curl -sf http://localhost:$(RATE_LIMITER_PORT)/actuator/health > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "fluxpay-engine:" ; \
	  curl -sf http://localhost:$(FLUXPAY_PORT)/api/v1/health > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "redis:" ; \
	  docker exec moalog-redis redis-cli ping 2>/dev/null | grep -q PONG \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "mysql:" ; \
	  docker exec moalog-mysql mysqladmin ping -h localhost -u root -pmoalog_local 2>/dev/null | grep -q alive \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "postgres:" ; \
	  docker exec fluxpay-postgres pg_isready -U fluxpay 2>/dev/null | grep -q accepting \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "kafka:" ; \
	  docker exec fluxpay-kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "prometheus:" ; \
	  curl -sf http://localhost:$(PROMETHEUS_PORT)/-/healthy > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "grafana:" ; \
	  curl -sf http://localhost:$(GRAFANA_PORT)/api/health > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "alertmanager:" ; \
	  curl -sf http://localhost:$(ALERTMANAGER_PORT)/-/healthy > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "loki:" ; \
	  curl -sf http://localhost:$(LOKI_PORT)/ready > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@printf "%-22s" "jaeger:" ; \
	  curl -sf http://localhost:$(JAEGER_UI_PORT)/ > /dev/null 2>&1 \
	  && echo "✅ healthy" || echo "❌ down"
	@echo ""

# --- Cleanup ---

clean:
	$(COMPOSE) down -v
	@echo "Volumes removed."

# --- Load testing ---

test-load:
	@echo "=== Running k6 load tests ==="
	@command -v k6 > /dev/null 2>&1 || { echo "❌ k6 not installed. brew install k6"; exit 1; }
	k6 run load-tests/scenarios/baseline.js \
	  --out json=load-tests/results/baseline.json \
	  --summary-trend-stats="avg,min,med,max,p(90),p(95),p(99)"
