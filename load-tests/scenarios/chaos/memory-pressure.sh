#!/usr/bin/env bash
# Chaos Scenario: Memory Pressure
#
# Failure: docker update --memory 64m moalog-server
# Expected: OOM handling, container restart behavior
#
# NOTE: docker update --memory is NOT supported on Docker Desktop for Mac.
#       This script detects the platform and skips on macOS.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIO="Memory Pressure"
CONTAINER="moalog-server"
RESULT_FILE="/tmp/chaos-memory-pressure.json"

print_scenario_header "$SCENARIO"

# Platform detection
IS_MACOS=false
if [[ "$(uname -s)" == "Darwin" ]]; then
  IS_MACOS=true
fi

# Check if Docker Desktop (no cgroup memory limit support)
DOCKER_INFO=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || echo "unknown")
IS_DOCKER_DESKTOP=false
if echo "$DOCKER_INFO" | grep -qi "docker desktop\|linuxkit"; then
  IS_DOCKER_DESKTOP=true
fi

if [[ "$IS_DOCKER_DESKTOP" == true ]]; then
  warn "Docker Desktop detected: 'docker update --memory' is not supported."
  warn "This test requires native Docker Engine on Linux."
  echo ""
  print_scenario_result "$SCENARIO" "SKIP"
  exit 0
fi

# Linux path: proceed with memory constraint
setup_cleanup "$CONTAINER"

# 1. Pre-check
check_all_healthy

# Save original memory limit
ORIG_MEMORY=$(docker inspect --format='{{.HostConfig.Memory}}' "$CONTAINER" 2>/dev/null || echo "0")
info "Original memory limit: ${ORIG_MEMORY} bytes (0 = unlimited)"

# 2. Inject failure: constrain memory to 64MB
info "Constraining ${CONTAINER} to 64MB memory..."
docker update --memory 64m --memory-swap 64m "$CONTAINER" 2>/dev/null || {
  warn "docker update --memory failed on this platform"
  print_scenario_result "$SCENARIO" "SKIP"
  exit 0
}

# 3. Send traffic under memory pressure
info "Sending read traffic under memory pressure..."
set +e
run_k6_chaos "read" "20s" "10" "$RESULT_FILE"
K6_EXIT=$?
set -e

# 4. Check if container was OOM-killed
PASS=true
OOM_KILLED=$(docker inspect --format='{{.State.OOMKilled}}' "$CONTAINER" 2>/dev/null || echo "false")
RUNNING=$(docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "false")

if [[ "$OOM_KILLED" == "true" ]]; then
  info "Container was OOM-killed (expected under 64MB constraint)"
  info "Restart policy: unless-stopped — should auto-restart"
fi

if [[ "$RUNNING" == "false" ]]; then
  warn "Container stopped — restarting"
  docker start "$CONTAINER"
fi

# 5. Restore original memory limit
info "Restoring original memory limit..."
if [[ "$ORIG_MEMORY" == "0" ]]; then
  docker update --memory 0 --memory-swap 0 "$CONTAINER" 2>/dev/null || true
else
  docker update --memory "$ORIG_MEMORY" "$CONTAINER" 2>/dev/null || true
fi

# 6. Wait for recovery
wait_recovery "$CONTAINER" 60

# 7. Post-recovery
sleep 3
if check_service "moalog-server" "http://localhost:${SERVER_PORT}/health"; then
  success "moalog-server recovered after memory pressure"
else
  fail "moalog-server did not recover"
  PASS=false
fi

echo ""
if [[ "$PASS" == true ]]; then
  print_scenario_result "$SCENARIO" "PASS"
else
  print_scenario_result "$SCENARIO" "FAIL"
  exit 1
fi
