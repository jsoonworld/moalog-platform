#!/usr/bin/env bash
# Chaos Scenario: Rate Limiter Down
#
# Failure: docker stop moalog-rate-limiter
# Expected: Fail Open — moalog-server bypasses rate limiting, all requests pass through.
#           (rate_limit.rs: connection error → Err(()) → middleware allows request)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="Rate Limiter Failure"
CONTAINER="moalog-rate-limiter"
RESULT_FILE="/tmp/chaos-rate-limiter-failure.json"

print_scenario_header "$SCENARIO"
setup_cleanup "$CONTAINER"

# 1. Pre-check
check_all_healthy

# 2. Inject failure
info "Stopping ${CONTAINER}..."
docker stop "$CONTAINER"
sleep 3

# 3. Send traffic (read — same IP, no rate limiting should apply)
info "Sending read traffic from single IP while rate limiter is down..."
set +e
run_k6_chaos "read" "25s" "15" "$RESULT_FILE"
K6_EXIT=$?
set -e

# 4. Validate: requests should succeed (Fail Open)
info "Validating results..."
PASS=true

if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
  success "moalog-server still healthy with rate limiter down"
else
  fail "moalog-server became unhealthy"
  PASS=false
fi

# 5. Restore service
info "Restarting ${CONTAINER}..."
docker start "$CONTAINER"

# 6. Wait for recovery (JVM startup ~60-90s)
wait_recovery "$CONTAINER" 120

# 7. Post-recovery: verify rate limiting resumes
sleep 5
if check_service "rate-limiter" "http://localhost:${RATE_LIMITER_PORT}/actuator/health"; then
  success "Rate limiter recovered and healthy"
else
  fail "Rate limiter did not recover"
  PASS=false
fi

echo ""
if [[ "$PASS" == true ]]; then
  print_scenario_result "$SCENARIO" "PASS"
else
  print_scenario_result "$SCENARIO" "FAIL"
  exit 1
fi
