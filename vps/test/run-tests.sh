#!/bin/bash
# Orchestrator: builds both images, runs all scenarios (or a filtered subset),
# and reports overall pass/fail.
#
# Usage:
#   ./run-tests.sh           # run all scenarios
#   ./run-tests.sh 01        # run only scenarios matching "01"
#   ./run-tests.sh fresh     # run only scenarios matching "fresh"

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

FILTER="${1:-}"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed or not on PATH" >&2
    exit 1
fi

if [ -t 1 ]; then
    G='\033[0;32m'; R='\033[0;31m'; B='\033[1;34m'; NC='\033[0m'
else
    G=''; R=''; B=''; NC=''
fi

echo -e "${B}Building Docker images...${NC}"
docker build -q -t vps-test-minimal -f Dockerfile.minimal . >/dev/null
echo "  ✓ vps-test-minimal"
if docker build -q -t vps-test-systemd -f Dockerfile.systemd . >/dev/null 2>&1; then
    echo "  ✓ vps-test-systemd"
else
    echo "  ⚠ vps-test-systemd skipped (image unavailable for this platform — scenario 04 will SKIP)"
fi
echo ""

FAILED_SCENARIOS=()
PASSED_SCENARIOS=()

for scenario in scenarios/*.sh; do
    name=$(basename "$scenario" .sh)
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
        continue
    fi
    echo -e "${B}▶ $name${NC}"
    if bash "$scenario"; then
        PASSED_SCENARIOS+=("$name")
    else
        FAILED_SCENARIOS+=("$name")
    fi
    echo ""
done

echo "════════════════════════════════════════"
echo "Results:"
for s in "${PASSED_SCENARIOS[@]+"${PASSED_SCENARIOS[@]}"}"; do
    echo -e "  ${G}PASS${NC} $s"
done
for s in "${FAILED_SCENARIOS[@]+"${FAILED_SCENARIOS[@]}"}"; do
    echo -e "  ${R}FAIL${NC} $s"
done
echo "════════════════════════════════════════"

if [ ${#FAILED_SCENARIOS[@]} -eq 0 ]; then
    echo -e "${G}✓ All scenarios passed${NC}"
    exit 0
else
    echo -e "${R}✗ ${#FAILED_SCENARIOS[@]} scenario(s) failed${NC}"
    exit 1
fi
