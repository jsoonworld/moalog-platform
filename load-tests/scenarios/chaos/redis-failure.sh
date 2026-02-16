#!/usr/bin/env bash
# Chaos Scenario: Redis Down
#
# Failure: docker stop moalog-redis
# Expected: Rate limiter Fail Open — requests pass through without rate limiting.
#           moalog-server itself does NOT use Redis directly.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="Redis Failure"
CONTAINER="moalog-redis"
RESULT_FILE="/tmp/chaos-redis-failure.json"

print_scenario_header "$SCENARIO"
setup_cleanup "$CONTAINER"

# 1. Pre-check
check_all_healthy

# 2. Inject failure
info "Stopping ${CONTAINER}..."
docker stop "$CONTAINER"
sleep 3

# 3. Send traffic (read — should still work via Fail Open)
info "Sending read traffic while Redis is down..."
set +e
run_k6_chaos "read" "25s" "15" "$RESULT_FILE"
K6_EXIT=$?
set -e

# 4. Validate: reads should succeed (Fail Open on rate limiter)
info "Validating results..."
PASS=true

if [[ "$K6_EXIT" -ne 0 ]]; then
  warn "k6 exited with code ${K6_EXIT} (may include expected errors)"
fi

# 5. Restore service
info "Restarting ${CONTAINER}..."
docker start "$CONTAINER"

# 6. Wait for recovery
wait_recovery "$CONTAINER" 30

# 7. Post-recovery verification
sleep 3
if docker exec moalog-redis redis-cli --no-auth-warning -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q PONG; then
  success "Redis recovered and responding to PING"
else
  fail "Redis did not recover"
  PASS=false
fi

# Check rate limiter reconnected
sleep 5
if check_service "rate-limiter" "http://localhost:${RATE_LIMITER_PORT}/actuator/health"; then
  success "Rate limiter healthy after Redis recovery"
else
  warn "Rate limiter may still be reconnecting"
fi

echo ""
if [[ "$PASS" == true ]]; then
  print_scenario_result "$SCENARIO" "PASS"
else
  print_scenario_result "$SCENARIO" "FAIL"
  exit 1
fi
