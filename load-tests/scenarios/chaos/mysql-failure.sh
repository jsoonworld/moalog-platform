#!/usr/bin/env bash
# Chaos Scenario: MySQL Down
#
# Failure: docker stop moalog-mysql
# Expected: moalog-server returns 500 on DB-dependent endpoints, /health fails.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="MySQL Failure"
CONTAINER="moalog-mysql"
RESULT_FILE="/tmp/chaos-mysql-failure.json"

print_scenario_header "$SCENARIO"
setup_cleanup "$CONTAINER"

# 1. Pre-check
check_all_healthy

# 2. Inject failure
info "Stopping ${CONTAINER}..."
docker stop "$CONTAINER"
sleep 3

# 3. Send traffic (read — DB-dependent endpoints will fail)
info "Sending read traffic while MySQL is down..."
set +e
run_k6_chaos "read" "25s" "15" "$RESULT_FILE"
K6_EXIT=$?
set -e

# 4. Validate: expect errors on DB-dependent endpoints
info "Validating results..."
PASS=true

# moalog-server /health should fail
if ! check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
  success "moalog-server /health correctly reports unhealthy"
else
  warn "moalog-server /health unexpectedly reports healthy"
fi

# 5. Restore service
info "Restarting ${CONTAINER}..."
docker start "$CONTAINER"

# 6. Wait for recovery (MySQL takes longer)
wait_recovery "$CONTAINER" 90

# 7. Post-recovery verification
sleep 5
if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
  success "moalog-server healthy after MySQL recovery"
else
  fail "moalog-server did not recover after MySQL restart"
  PASS=false
fi

echo ""
if [[ "$PASS" == true ]]; then
  print_scenario_result "$SCENARIO" "PASS"
else
  print_scenario_result "$SCENARIO" "FAIL"
  exit 1
fi
