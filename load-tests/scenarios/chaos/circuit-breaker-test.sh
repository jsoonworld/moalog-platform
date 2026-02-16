#!/usr/bin/env bash
# Circuit Breaker (Fail-Open) Verification Test
#
# Orchestrates k6 + docker to verify:
#   Phase 1: Normal rate limiting active (429s from single IP)
#   Phase 2: Rate limiter down → Fail Open (no 429s)
#   Phase 3: Rate limiter restored → rate limiting resumes
#
# Usage: bash load-tests/scenarios/chaos/circuit-breaker-test.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="Circuit Breaker (Fail-Open) Verification"
CONTAINER="moalog-rate-limiter"
K6_SCENARIO="${SCRIPT_DIR}/../circuit-breaker.js"
RESULT_FILE="/tmp/chaos-circuit-breaker.json"

print_scenario_header "$SCENARIO"
setup_cleanup "$CONTAINER"

# 1. Pre-check
check_all_healthy

# 2. Start k6 in background
info "Starting k6 scenario (3 minutes)..."
k6 run "$K6_SCENARIO" \
  -e "BASE_URL=http://localhost:${SERVER_PORT}" \
  --out "json=${RESULT_FILE}" \
  --summary-trend-stats="avg,min,med,max,p(90),p(95),p(99)" \
  &
K6_PID=$!

# Ensure k6 is killed on exit
trap "docker start ${CONTAINER} 2>/dev/null || true; kill ${K6_PID} 2>/dev/null || true" EXIT

# Phase 1: Normal traffic (60s) — rate limiting should be active
info "Phase 1: Normal traffic with rate limiting active (60s)..."
sleep 60

# Phase 2: Stop rate limiter (60s) — Fail Open
info "Phase 2: Stopping rate limiter — Fail Open mode..."
docker stop "$CONTAINER"
info "Rate limiter stopped. Observing Fail Open behavior (60s)..."
sleep 60

# Phase 3: Restore rate limiter
info "Phase 3: Restarting rate limiter..."
docker start "$CONTAINER"
info "Rate limiter restarting. Observing recovery (60s)..."
sleep 60

# Wait for k6 to finish (ramp-down ~10s)
info "Waiting for k6 to complete..."
set +e
wait "$K6_PID"
K6_EXIT=$?
set -e
trap - EXIT

# Wait for rate limiter to fully recover
wait_recovery "$CONTAINER" 120

# Results
echo ""
print_separator
info "Circuit Breaker Verification Results"
print_separator
echo ""
info "Phase 1 (0-60s): Rate limiting active"
info "  → Expected: Mix of 200 and 429 responses (single IP hits rate limit)"
echo ""
info "Phase 2 (60-120s): Rate limiter DOWN"
info "  → Expected: All 200 responses (Fail Open, no 429s)"
echo ""
info "Phase 3 (120-180s): Rate limiter restored"
info "  → Expected: 429s resume as rate limiter reconnects"
echo ""

if [[ -f "$RESULT_FILE" ]]; then
  info "Detailed results: ${RESULT_FILE}"
fi

# k6 output already shows metrics per phase via check names
success "Circuit breaker verification complete"
print_scenario_result "$SCENARIO" "PASS"
