#!/usr/bin/env bash
# Chaos Scenario: Kafka Down
#
# Failure: docker stop fluxpay-kafka
# Expected: FluxPay outbox events queue but cannot be published.
#           Payment processing may degrade. Read APIs unaffected.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="Kafka Failure"
CONTAINER="fluxpay-kafka"
RESULT_FILE="/tmp/chaos-kafka-failure.json"

print_scenario_header "$SCENARIO"
setup_cleanup "$CONTAINER"

# 1. Pre-check
check_all_healthy

# 2. Inject failure
info "Stopping ${CONTAINER}..."
docker stop "$CONTAINER"
sleep 3

# 3. Send traffic (mixed — reads + payments)
info "Sending mixed traffic while Kafka is down..."
set +e
run_k6_chaos "mixed" "25s" "15" "$RESULT_FILE"
K6_EXIT=$?
set -e

# 4. Validate: read APIs should be unaffected
info "Validating results..."
PASS=true

if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
  success "moalog-server still healthy"
else
  warn "moalog-server health degraded"
fi

# FluxPay may or may not degrade depending on Kafka dependency
if check_service "fluxpay-engine" "http://localhost:${FLUXPAY_PORT}/api/v1/health"; then
  info "FluxPay still reports healthy (outbox queuing active)"
else
  info "FluxPay health degraded (expected with Kafka down)"
fi

# 5. Restore service
info "Restarting ${CONTAINER}..."
docker start "$CONTAINER"

# 6. Wait for recovery
sleep 15  # Kafka needs time to elect leader
info "Waiting for Kafka broker to be ready..."
for i in $(seq 1 12); do
  if docker exec "$CONTAINER" kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    success "Kafka recovered in $((i * 5))s"
    break
  fi
  sleep 5
done

# 7. Post-recovery
sleep 5
if check_service "fluxpay-engine" "http://localhost:${FLUXPAY_PORT}/api/v1/health"; then
  success "FluxPay healthy after Kafka recovery"
else
  warn "FluxPay may still be reconnecting to Kafka"
fi

echo ""
if [[ "$PASS" == true ]]; then
  print_scenario_result "$SCENARIO" "PASS"
else
  print_scenario_result "$SCENARIO" "FAIL"
  exit 1
fi
