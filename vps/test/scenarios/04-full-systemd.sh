#!/bin/bash
# Scenario 04: Full install (all components = y) in a systemd-enabled
# container. Requires --privileged and --cgroupns=host so systemd can boot
# as PID 1, allowing Docker, UFW, fail2ban, and swap to actually start.
# Skipped automatically if those flags aren't supported on the host.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

IMAGE="vps-test-systemd"
CONTAINER="vps-test-full-$$"
LOG_FILE="/tmp/${CONTAINER}.log"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

echo "── Scenario 04: Full install (systemd image) ──"

# Probe: this scenario requires a systemd container, which in turn needs:
#   1. The base image to build for our architecture
#   2. --privileged + --cgroupns=host support
# Skip on macOS / Apple Silicon where neither holds.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo -e "  ${Y}SKIP${NC} systemd base image unavailable for this platform (arm64 not supported by jrei/systemd-ubuntu)"
    print_summary
    exit 0
fi
if ! docker run --rm --privileged --cgroupns=host alpine:3 true >/dev/null 2>&1; then
    echo -e "  ${Y}SKIP${NC} --cgroupns=host not supported on this host (Linux + privileged required)"
    print_summary
    exit 0
fi

echo "Booting systemd container..."
docker run -d --privileged --cgroupns=host \
    --name "$CONTAINER" \
    -v "$REPO_ROOT:/dotfiles-src:ro" \
    -e DOTFILES_REPO_URL=file:///dotfiles-src \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    "$IMAGE" >/dev/null

# Give systemd a few seconds to settle (units up, dbus alive)
sleep 5

# All-yes input, including swap size:
INPUT=$(cat <<'EOF'
n
testuser
Eric
eric@example.com
y
y
y
y
y
y
y
y
y
y

y
y
EOF
)

echo "Running setup-vps.sh inside systemd container..."
docker exec -i "$CONTAINER" bash /dotfiles-src/vps/setup-vps.sh <<<"$INPUT" >"$LOG_FILE" 2>&1
RC=$?
assert_exit_zero "$RC" "full-install run exits cleanly"

echo "Verifying systemd-managed services..."
assert_exec_in "$CONTAINER" "Docker service active" systemctl is-active docker
assert_exec_in "$CONTAINER" "fail2ban service active" systemctl is-active fail2ban
assert_exec_in "$CONTAINER" "UFW reports active" bash -c "ufw status | grep -q 'Status: active'"
assert_exec_in "$CONTAINER" "swap configured" bash -c "swapon --show | grep -q /swapfile"

# Core user-env asserts
assert_exec_in "$CONTAINER" "testuser exists" id testuser
assert_exec_in "$CONTAINER" "testuser in docker group" bash -c "groups testuser | grep -qw docker"
assert_exec_in "$CONTAINER" ".zshrc symlinked" test -L /home/testuser/.zshrc
assert_exec_in "$CONTAINER" "NVM installed" test -d /home/testuser/.nvm

print_summary
