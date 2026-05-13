#!/bin/bash
# Scenario 01: Fresh install on a clean ubuntu:24.04 container.
# All infra components (UFW/fail2ban/Tailscale/swap/Docker) disabled so we
# can run unprivileged without systemd. Validates user creation, dotfiles
# symlinks, and language toolchain installs (NVM/UV/Bun/Claude).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

IMAGE="vps-test-minimal"
CONTAINER="vps-test-fresh-$$"
LOG_FILE="/tmp/${CONTAINER}.log"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

echo "── Scenario 01: Fresh install (minimal) ──"

# Feed answers to the 16 interactive prompts (in order):
INPUT=$(cat <<'EOF'
n
testuser
Eric
eric@example.com
y
n
y
y
y
n
n
y
y
n
y
y
EOF
)

echo "Running setup-vps.sh in $CONTAINER..."
docker run -i --name "$CONTAINER" \
    -v "$REPO_ROOT:/dotfiles-src:ro" \
    -e DOTFILES_REPO_URL=file:///dotfiles-src \
    "$IMAGE" \
    bash /dotfiles-src/vps/setup-vps.sh <<<"$INPUT" >"$LOG_FILE" 2>&1
RC=$?

assert_exit_zero "$RC" "setup-vps.sh exits cleanly"

echo "Verifying container state..."
# Restart the stopped container so we can exec into it
docker start "$CONTAINER" >/dev/null

assert_exec_in "$CONTAINER" "testuser exists" id testuser
assert_exec_in "$CONTAINER" ".zshrc is a symlink" test -L /home/testuser/.zshrc
assert_exec_in "$CONTAINER" ".gitconfig is a symlink" test -L /home/testuser/.gitconfig
assert_exec_in "$CONTAINER" "dotfiles repo cloned" test -d /home/testuser/dotfiles/.git
assert_exec_in "$CONTAINER" "NVM installed" test -d /home/testuser/.nvm
assert_exec_in "$CONTAINER" "UV installed" test -f /home/testuser/.local/bin/uv
assert_exec_in "$CONTAINER" "Bun installed" test -f /home/testuser/.bun/bin/bun
assert_exec_in "$CONTAINER" "Oh My Zsh installed" test -d /home/testuser/.oh-my-zsh
assert_exec_in "$CONTAINER" "zsh-autosuggestions plugin" test -d /home/testuser/.oh-my-zsh/custom/plugins/zsh-autosuggestions
assert_exec_in "$CONTAINER" "state file cleaned up" bash -c "! test -f /root/.vps-setup-state"
assert_exec_in "$CONTAINER" "after_setup_todo.txt created" test -f /home/testuser/after_setup_todo.txt

# UFW/fail2ban/Tailscale should NOT be installed in this scenario
assert_log_not_contains "$LOG_FILE" "Installing UFW firewall" "UFW skipped"
assert_log_not_contains "$LOG_FILE" "Installing Tailscale" "Tailscale skipped"

print_summary
