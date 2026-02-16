#!/usr/bin/env bash
# Chaos Scenario: Network Delay
#
# Failure: tc qdisc add dev eth0 root netem delay 500ms
# Expected: Increased latency, potential timeouts on rate-limiter calls (500ms timeout).
#
# NOTE: Requires NET_ADMIN capability and iproute2 (tc) in the container.
#       moalog-server uses debian:bookworm-slim which may not have tc installed.
#       This script gracefully skips if tc is unavailable.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="Network Delay"
CONTAINER="moalog-server"
RESULT_FILE="/tmp/chaos-network-delay.json"

print_scenario_header "$SCENARIO"

# 1. Pre-check
check_all_healthy

# 2. Check if tc is available in the container
info "Checking if tc (traffic control) is available in ${CONTAINER}..."
if ! docker exec "$CONTAINER" which tc > /dev/null 2>&1; then
  warn "'tc' not found in ${CONTAINER}."
  warn "Network delay test requires iproute2 package and NET_ADMIN capability."
  warn "To enable: add 'cap_add: [NET_ADMIN]' and install iproute2 in Dockerfile."
  echo ""

  # Fallback: simple network disconnect/reconnect test
  info "Running fallback: brief network partition test..."

  NETWORK=$(docker inspect --format='{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$CONTAINER" 2>/dev/null | head -1)
  if [[ -z "$NETWORK" ]]; then
    warn "Could not determine container network"
    print_scenario_result "$SCENARIO" "SKIP"
    exit 0
  fi

  info "Disconnecting ${CONTAINER} from network '${NETWORK}' for 10s..."
  trap "docker network connect ${NETWORK} ${CONTAINER} 2>/dev/null || true" EXIT

  docker network disconnect "$NETWORK" "$CONTAINER" 2>/dev/null || {
    warn "Network disconnect failed"
    print_scenario_result "$SCENARIO" "SKIP"
    exit 0
  }

  sleep 10

  info "Reconnecting ${CONTAINER} to network..."
  docker network connect "$NETWORK" "$CONTAINER"
  trap - EXIT

  sleep 5
  if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
    success "moalog-server recovered after network partition"
    print_scenario_result "$SCENARIO" "PASS"
  else
    # May need more time to reconnect
    sleep 10
    if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
      success "moalog-server recovered after network partition (delayed)"
      print_scenario_result "$SCENARIO" "PASS"
    else
      fail "moalog-server did not recover after network partition"
      print_scenario_result "$SCENARIO" "FAIL"
      exit 1
    fi
  fi
  exit 0
fi

# tc is available — use netem for delay injection
setup_cleanup "$CONTAINER"
trap "docker exec ${CONTAINER} tc qdisc del dev eth0 root 2>/dev/null || true; info 'Network delay removed'" EXIT

# Baseline latency measurement
info "Measuring baseline latency..."
BASELINE_START=$(date +%s%3N)
curl -sf "http://localhost:${SERVER_PORT}/health" > /dev/null 2>&1
BASELINE_END=$(date +%s%3N)
BASELINE_MS=$((BASELINE_END - BASELINE_START))
info "Baseline latency: ${BASELINE_MS}ms"

# 3. Inject 500ms network delay
info "Adding 500ms network delay to ${CONTAINER}..."
docker exec "$CONTAINER" tc qdisc add dev eth0 root netem delay 500ms || {
  warn "tc qdisc add failed (need NET_ADMIN capability)"
  print_scenario_result "$SCENARIO" "SKIP"
  exit 0
}

# 4. Send traffic under delay
info "Sending read traffic with 500ms network delay..."
set +e
run_k6_chaos "read" "20s" "10" "$RESULT_FILE"
K6_EXIT=$?
set -e

# 5. Measure delayed latency
DELAYED_START=$(date +%s%3N)
curl -sf "http://localhost:${SERVER_PORT}/health" > /dev/null 2>&1
DELAYED_END=$(date +%s%3N)
DELAYED_MS=$((DELAYED_END - DELAYED_START))
info "Delayed latency: ${DELAYED_MS}ms"

# 6. Remove delay
info "Removing network delay..."
docker exec "$CONTAINER" tc qdisc del dev eth0 root 2>/dev/null || true
trap - EXIT

# 7. Verify recovery
sleep 3
RECOVERY_START=$(date +%s%3N)
curl -sf "http://localhost:${SERVER_PORT}/health" > /dev/null 2>&1
RECOVERY_END=$(date +%s%3N)
RECOVERY_MS=$((RECOVERY_END - RECOVERY_START))
info "Recovery latency: ${RECOVERY_MS}ms"

PASS=true
echo ""
info "Latency comparison:"
info "  Baseline: ${BASELINE_MS}ms"
info "  Delayed:  ${DELAYED_MS}ms"
info "  Recovery: ${RECOVERY_MS}ms"

if [[ "$DELAYED_MS" -gt "$((BASELINE_MS + 300))" ]]; then
  success "Network delay was correctly injected (${DELAYED_MS}ms > ${BASELINE_MS}ms + 300ms)"
else
  warn "Network delay may not have been effective"
fi

if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
  success "moalog-server healthy after delay removal"
else
  fail "moalog-server unhealthy after delay removal"
  PASS=false
fi

echo ""
if [[ "$PASS" == true ]]; then
  print_scenario_result "$SCENARIO" "PASS"
else
  print_scenario_result "$SCENARIO" "FAIL"
  exit 1
fi
