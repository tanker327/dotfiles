#!/bin/bash
# Scenario 02: Run setup-vps.sh twice in the same container.
# Second run starts fresh (state file removed on success) and must exit 0
# while skipping every already-installed component.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

IMAGE="vps-test-minimal"
CONTAINER="vps-test-rerun-$$"
INTERMEDIATE="${IMAGE}-rerun-$$"
LOG1="/tmp/${CONTAINER}-1.log"
LOG2="/tmp/${CONTAINER}-2.log"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker rmi -f "$INTERMEDIATE" >/dev/null 2>&1 || true
    rm -f "$LOG1" "$LOG2"
}
trap cleanup EXIT

echo "── Scenario 02: Re-run after success ──"

# First run: create user fresh
INPUT_FIRST=$(cat <<'EOF'
n
testuser
Eric
eric@example.com
y
n
n
y
y
y
n
n
y
y
n
n
y
y
EOF
)

# Second run: user testuser already exists, so "Use existing user?" → n still
# leads to "Enter username" + "Continue with existing user? (y/n):" extra prompt.
# Feed that extra 'y' between the username and git config lines.
INPUT_SECOND=$(cat <<'EOF'
n
testuser
y
Eric
eric@example.com
y
n
n
y
y
y
n
n
y
y
n
n
y
y
EOF
)

echo "[1/2] First run..."
docker run -i --name "$CONTAINER" \
    -v "$REPO_ROOT:/dotfiles-src:ro" \
    -e DOTFILES_REPO_URL=file:///dotfiles-src \
    "$IMAGE" \
    bash /dotfiles-src/vps/setup-vps.sh <<<"$INPUT_FIRST" >"$LOG1" 2>&1
RC1=$?
assert_exit_zero "$RC1" "first run exits cleanly"

# Snapshot container state into a new image, then re-run from it
docker commit "$CONTAINER" "$INTERMEDIATE" >/dev/null
docker rm -f "$CONTAINER" >/dev/null

echo "[2/2] Second run on same state..."
docker run -i --name "$CONTAINER" \
    -v "$REPO_ROOT:/dotfiles-src:ro" \
    -e DOTFILES_REPO_URL=file:///dotfiles-src \
    "$INTERMEDIATE" \
    bash /dotfiles-src/vps/setup-vps.sh <<<"$INPUT_SECOND" >"$LOG2" 2>&1
RC2=$?
assert_exit_zero "$RC2" "second run exits cleanly"

echo "Verifying second run skipped existing installs..."
assert_log_contains "$LOG2" "User testuser already exists" "create_user reused existing user"
assert_log_contains "$LOG2" "NVM already installed" "NVM install skipped"
assert_log_contains "$LOG2" "UV already installed" "UV install skipped"
assert_log_contains "$LOG2" "Bun already installed" "Bun install skipped"
assert_log_contains "$LOG2" "Claude Code already installed" "Claude install skipped"
assert_log_contains "$LOG2" "Dotfiles repo already present" "dotfiles pull-not-clone"

# Verify no destructive log lines on second run
assert_log_not_contains "$LOG2" "rm -rf.*dotfiles" "dotfiles NOT wiped on re-run"

docker start "$CONTAINER" >/dev/null
assert_exec_in "$CONTAINER" "dotfiles still present after re-run" test -d /home/testuser/dotfiles/.git

print_summary
