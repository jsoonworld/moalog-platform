#!/usr/bin/env bash
# Run all chaos test scenarios sequentially
# Usage: bash load-tests/scenarios/chaos/run-all.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SCENARIOS=(
  "redis-failure"
  "mysql-failure"
  "rate-limiter-failure"
  "kafka-failure"
  "fluxpay-failure"
  "memory-pressure"
  "network-delay"
)

declare -A RESULTS

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         Moalog Platform — Chaos Test Suite          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Pre-flight check
info "Pre-flight: checking all services..."
check_all_healthy
echo ""

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

for scenario in "${SCENARIOS[@]}"; do
  TOTAL=$((TOTAL + 1))
  SCRIPT="${SCRIPT_DIR}/${scenario}.sh"

  if [[ ! -f "$SCRIPT" ]]; then
    error "Script not found: ${SCRIPT}"
    RESULTS[$scenario]="MISSING"
    FAILED=$((FAILED + 1))
    continue
  fi

  set +e
  bash "$SCRIPT"
  EXIT_CODE=$?
  set -e

  if [[ "$EXIT_CODE" -eq 0 ]]; then
    # Check if it was a SKIP (script outputs SKIP and exits 0)
    # We detect SKIP by checking the last few lines of output
    RESULTS[$scenario]="PASS"
    PASSED=$((PASSED + 1))
  else
    RESULTS[$scenario]="FAIL"
    FAILED=$((FAILED + 1))
  fi

  # Brief pause between scenarios to let services stabilize
  info "Waiting 10s before next scenario..."
  sleep 10
  echo ""
done

# ─── Summary ────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║               Chaos Test Summary                    ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  %-30s  %-10s      ║\n" "Scenario" "Result"
echo "╠══════════════════════════════════════════════════════╣"

for scenario in "${SCENARIOS[@]}"; do
  result="${RESULTS[$scenario]:-UNKNOWN}"
  case "$result" in
    PASS)    color="${GREEN}" ;;
    FAIL)    color="${RED}" ;;
    SKIP)    color="${YELLOW}" ;;
    *)       color="${RED}" ;;
  esac
  printf "║  %-30s  ${color}%-10s${NC}      ║\n" "$scenario" "$result"
done

echo "╠══════════════════════════════════════════════════════╣"
printf "║  Total: %-3d  Pass: %-3d  Fail: %-3d  Skip: %-3d       ║\n" \
  "$TOTAL" "$PASSED" "$FAILED" "$SKIPPED"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
