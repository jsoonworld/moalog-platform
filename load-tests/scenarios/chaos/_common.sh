#!/usr/bin/env bash
# load-tests/scenarios/chaos/_common.sh
# Shared functions for chaos test scripts

set -euo pipefail

# ─── Colors ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*"; }

# ─── Port defaults (match Makefile) ─────────────────
export SERVER_PORT="${SERVER_PORT:-8090}"
export RATE_LIMITER_PORT="${RATE_LIMITER_PORT:-8082}"
export FLUXPAY_PORT="${FLUXPAY_PORT:-8081}"
export REDIS_PORT="${REDIS_PORT:-6382}"
export MYSQL_PORT="${MYSQL_PORT:-3307}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-moalog_redis_local}"

# ─── Paths ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_CHAOS_TRAFFIC="${SCRIPT_DIR}/k6-chaos-traffic.js"

# ─── Health check functions ─────────────────────────

check_service() {
  local name="$1"
  local url="$2"
  if curl -sf "$url" > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

check_all_healthy() {
  info "Checking all services are healthy..."
  local failed=0

  check_service "moalog-server"  "http://localhost:${SERVER_PORT}/health" || { error "moalog-server is down"; failed=1; }
  check_service "rate-limiter"   "http://localhost:${RATE_LIMITER_PORT}/actuator/health" || { error "rate-limiter is down"; failed=1; }
  check_service "fluxpay-engine" "http://localhost:${FLUXPAY_PORT}/api/v1/health" || { error "fluxpay-engine is down"; failed=1; }

  docker exec moalog-redis redis-cli --no-auth-warning -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q PONG || { error "redis is down"; failed=1; }
  docker exec moalog-mysql mysqladmin ping -h localhost -u root -pmoalog_local 2>/dev/null | grep -q alive || { error "mysql is down"; failed=1; }

  if [[ "$failed" -ne 0 ]]; then
    error "Pre-check failed. All services must be healthy before running chaos tests."
    error "Run: make up && sleep 120 && make health"
    exit 1
  fi

  success "All services healthy"
}

# ─── Recovery wait ──────────────────────────────────

wait_recovery() {
  local container="$1"
  local max_seconds="${2:-60}"
  local interval=5
  local elapsed=0

  info "Waiting for ${container} to recover (max ${max_seconds}s)..."

  while [[ "$elapsed" -lt "$max_seconds" ]]; do
    if docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null | grep -q healthy; then
      success "${container} recovered in ${elapsed}s"
      return 0
    fi

    # Fallback: check if container is at least running
    if [[ "$elapsed" -gt 10 ]] && docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null | grep -q true; then
      # For containers without healthcheck, just verify running
      local has_health
      has_health=$(docker inspect --format='{{if .State.Health}}yes{{end}}' "$container" 2>/dev/null || echo "")
      if [[ -z "$has_health" ]]; then
        success "${container} is running (no healthcheck) after ${elapsed}s"
        return 0
      fi
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  warn "${container} did not recover within ${max_seconds}s"
  return 1
}

# ─── k6 runner ──────────────────────────────────────

run_k6_chaos() {
  local traffic_type="${1:-read}"
  local duration="${2:-30s}"
  local vus="${3:-20}"
  local output_file="${4:-/tmp/chaos-k6-result.json}"

  info "Running k6: type=${traffic_type}, duration=${duration}, VUs=${vus}"

  k6 run "$K6_CHAOS_TRAFFIC" \
    -e "CHAOS_DURATION=${duration}" \
    -e "CHAOS_VUS=${vus}" \
    -e "TRAFFIC_TYPE=${traffic_type}" \
    -e "BASE_URL=http://localhost:${SERVER_PORT}" \
    --out "json=${output_file}" \
    --summary-trend-stats="avg,min,med,max,p(90),p(95),p(99)" \
    --quiet 2>&1

  return $?
}

# ─── Result summary ─────────────────────────────────

print_separator() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_scenario_header() {
  local name="$1"
  echo ""
  print_separator
  echo -e "${BLUE}  CHAOS SCENARIO: ${name}${NC}"
  print_separator
}

print_scenario_result() {
  local name="$1"
  local result="$2"  # PASS, FAIL, SKIP

  case "$result" in
    PASS) success "Scenario '${name}': PASS" ;;
    FAIL) fail    "Scenario '${name}': FAIL" ;;
    SKIP) warn    "Scenario '${name}': SKIP" ;;
  esac
}

# ─── Cleanup trap helper ───────────────────────────

# Usage: setup_cleanup "container_name"
# Call in each script to ensure container is restarted on exit
setup_cleanup() {
  local container="$1"
  trap "info 'Cleanup: restarting ${container}...'; docker start ${container} 2>/dev/null || true" EXIT
}

setup_cleanup_multi() {
  local containers=("$@")
  trap "info 'Cleanup: restarting containers...'; for c in ${containers[*]}; do docker start \$c 2>/dev/null || true; done" EXIT
}
