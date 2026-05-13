#!/bin/bash
# Scenario 03: Resume after a simulated mid-run failure.
# We pre-seed /root/.vps-setup-state with the early steps marked done and
# a pre-created testuser, then run setup-vps.sh and answer "y" at the
# resume prompt. The script must skip the marked steps and only install
# the remaining components (NVM/UV/Bun/Claude).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

IMAGE="vps-test-minimal"
CONTAINER="vps-test-resume-$$"
LOG_FILE="/tmp/${CONTAINER}.log"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

echo "── Scenario 03: Resume after mid-run failure ──"

# Start a container we can prep before running the script
docker run -d --name "$CONTAINER" \
    -v "$REPO_ROOT:/dotfiles-src:ro" \
    -e DOTFILES_REPO_URL=file:///dotfiles-src \
    "$IMAGE" \
    sleep infinity >/dev/null

echo "Pre-seeding partial state (testuser + apt deps + early steps marked done)..."
docker exec "$CONTAINER" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    # Pre-install the system packages that the marked-done steps would have installed,
    # so downstream sub-steps (chsh, OMZ install, etc.) can actually run.
    apt-get update -qq >/dev/null
    apt-get install -y -qq zsh curl wget vim htop unzip tree build-essential >/dev/null
    useradd -m -s /bin/bash testuser
    echo "testuser:testuser" | chpasswd
    usermod -aG sudo testuser

    cat > /root/.vps-setup-state <<EOF
# Pre-seeded state for resume test
NEW_USERNAME="testuser"
CREATE_NEW_USER="y"
GIT_USER_NAME="Eric"
GIT_USER_EMAIL="eric@example.com"
INSTALL_TOOLS="y"
INSTALL_SECURITY="n"
INSTALL_MOSH="n"
INSTALL_ZSH="y"
INSTALL_UV="y"
INSTALL_NVM="y"
INSTALL_DOCKER="n"
INSTALL_TAILSCALE="n"
INSTALL_BUN="y"
INSTALL_CLAUDE="y"
INSTALL_CODEX="n"
SETUP_SWAP="n"
SWAP_SIZE=""
INSTALL_DOTFILES="y"
update_system=done
check_ssh_keys=done
create_user=done
install_common_tools=done
install_zsh=done
EOF
    echo "State pre-seeded."
'

echo "Running setup-vps.sh in resume mode..."
# Resume prompt expects "y"; rest of config comes from state file.
docker exec -i "$CONTAINER" bash /dotfiles-src/vps/setup-vps.sh <<<"y" >"$LOG_FILE" 2>&1
RC=$?
assert_exit_zero "$RC" "resume run exits cleanly"

echo "Verifying skipped vs newly-installed steps..."
assert_log_contains "$LOG_FILE" "Resuming previous installation" "resume path taken"
assert_log_contains "$LOG_FILE" "Step 'update_system' already completed" "update_system skipped"
assert_log_contains "$LOG_FILE" "Step 'create_user' already completed" "create_user skipped"
assert_log_contains "$LOG_FILE" "Step 'install_common_tools' already completed" "install_common_tools skipped"

# NVM/UV/Bun/Claude must actually install (no pre-marked state for them)
assert_exec_in "$CONTAINER" "NVM installed after resume" test -d /home/testuser/.nvm
assert_exec_in "$CONTAINER" "UV installed after resume" test -f /home/testuser/.local/bin/uv
assert_exec_in "$CONTAINER" "Bun installed after resume" test -f /home/testuser/.bun/bin/bun
assert_exec_in "$CONTAINER" "state file cleaned up after success" bash -c "! test -f /root/.vps-setup-state"

print_summary
