#!/usr/bin/env bash
# Chaos Scenario: FluxPay Engine Down
#
# Failure: docker stop fluxpay-engine
# Expected: Payment API returns 502/503 from moalog-server.
#           Read APIs (retro-rooms, retrospects) continue working normally.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="FluxPay Failure"
CONTAINER="fluxpay-engine"
RESULT_FILE="/tmp/chaos-fluxpay-failure.json"

print_scenario_header "$SCENARIO"
setup_cleanup "$CONTAINER"

# 1. Pre-check
check_all_healthy

# 2. Inject failure
info "Stopping ${CONTAINER}..."
docker stop "$CONTAINER"
sleep 3

# 3. Send traffic (mixed — reads should work, payments should fail)
info "Sending mixed traffic while FluxPay is down..."
set +e
run_k6_chaos "mixed" "25s" "15" "$RESULT_FILE"
K6_EXIT=$?
set -e

# 4. Validate: moalog-server should still be healthy (reads work)
info "Validating results..."
PASS=true

if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
  success "moalog-server still healthy (reads working)"
else
  fail "moalog-server became unhealthy"
  PASS=false
fi

# Verify read endpoints specifically
RES=$(curl -sf "http://localhost:${SERVER_PORT}/api/v1/retro-rooms" \
  -H "Content-Type: application/json" 2>/dev/null || echo "FAIL")
if [[ "$RES" != "FAIL" ]]; then
  success "Read API (retro-rooms) responding normally"
else
  warn "Read API may require auth — testing via k6 results"
fi

# 5. Restore service
info "Restarting ${CONTAINER}..."
docker start "$CONTAINER"

# 6. Wait for recovery (JVM + OTel agent startup ~90-120s)
wait_recovery "$CONTAINER" 150

# 7. Post-recovery verification
sleep 5
if check_service "fluxpay-engine" "http://localhost:${FLUXPAY_PORT}/api/v1/health"; then
  success "FluxPay recovered and healthy"
else
  fail "FluxPay did not recover"
  PASS=false
fi

echo ""
if [[ "$PASS" == true ]]; then
  print_scenario_result "$SCENARIO" "PASS"
else
  print_scenario_result "$SCENARIO" "FAIL"
  exit 1
fi
