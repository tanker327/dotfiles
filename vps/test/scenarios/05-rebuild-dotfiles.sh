#!/bin/bash
# Scenario 05: Validate vps/rebuild-dotfiles.sh.
# The script is meant to be run by a non-root user with cloned dotfiles
# to (re)create symlinks and (re)install Oh My Zsh + plugins.
#
# Critical assertion: after Oh My Zsh installs, the .zshrc symlink must
# still point at dotfiles/zsh/zshrc — i.e. the OMZ installer's default-
# template behavior was suppressed by KEEP_ZSHRC=yes.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

IMAGE="vps-test-minimal"
CONTAINER="vps-test-rebuild-$$"
LOG_FILE="/tmp/${CONTAINER}.log"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

echo "── Scenario 05: rebuild-dotfiles.sh ──"

# Start a long-lived container so we can prep + exec + assert
docker run -d --name "$CONTAINER" \
    -v "$REPO_ROOT:/dotfiles-src:ro" \
    "$IMAGE" \
    sleep infinity >/dev/null

echo "Preparing container (create user, install zsh, clone dotfiles, plant pre-existing configs)..."
docker exec "$CONTAINER" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq zsh >/dev/null

    useradd -m -s /bin/bash testuser
    su - testuser -c "git clone /dotfiles-src /home/testuser/dotfiles" >/dev/null 2>&1

    # Plant pre-existing non-symlinked configs to exercise the backup path
    su - testuser -c "echo \"# old gitconfig\" > /home/testuser/.gitconfig"
    su - testuser -c "echo \"# old zshrc\"    > /home/testuser/.zshrc"
    echo "Prep complete."
'

echo "Running rebuild-dotfiles.sh as testuser..."
docker exec -i "$CONTAINER" su - testuser -c "bash /home/testuser/dotfiles/vps/rebuild-dotfiles.sh" >"$LOG_FILE" 2>&1
RC=$?

assert_exit_zero "$RC" "rebuild-dotfiles.sh exits cleanly"

echo "Verifying symlinks survived OMZ install..."
# THE bug-fix assertion: .zshrc must still be a symlink to dotfiles/zsh/zshrc.
# Without KEEP_ZSHRC=yes, OMZ install would have moved this aside.
assert_exec_in "$CONTAINER" ".zshrc still a symlink after OMZ install" test -L /home/testuser/.zshrc
assert_exec_in "$CONTAINER" ".zshrc points at dotfiles" \
    bash -c "[ \"\$(readlink /home/testuser/.zshrc)\" = \"/home/testuser/dotfiles/zsh/zshrc\" ]"

assert_exec_in "$CONTAINER" ".gitconfig is a symlink" test -L /home/testuser/.gitconfig
assert_exec_in "$CONTAINER" ".gitignore_global is a symlink" test -L /home/testuser/.gitignore_global

echo "Verifying OMZ + plugins installed..."
assert_exec_in "$CONTAINER" "Oh My Zsh installed" test -d /home/testuser/.oh-my-zsh
assert_exec_in "$CONTAINER" "Powerlevel10k theme installed" test -d /home/testuser/.oh-my-zsh/custom/themes/powerlevel10k
assert_exec_in "$CONTAINER" "zsh-autosuggestions installed" test -d /home/testuser/.oh-my-zsh/custom/plugins/zsh-autosuggestions
assert_exec_in "$CONTAINER" "zsh-syntax-highlighting installed" test -d /home/testuser/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

echo "Verifying backups of pre-existing configs..."
assert_exec_in "$CONTAINER" "old .zshrc backed up" \
    bash -c "ls /home/testuser/.backup/.zshrc.backup-* >/dev/null 2>&1"
assert_exec_in "$CONTAINER" "old .gitconfig backed up" \
    bash -c "ls /home/testuser/.backup/.gitconfig.backup-* >/dev/null 2>&1"

echo "Re-running to confirm idempotency..."
docker exec -i "$CONTAINER" su - testuser -c "bash /home/testuser/dotfiles/vps/rebuild-dotfiles.sh" >/tmp/${CONTAINER}-2.log 2>&1
RC2=$?
assert_exit_zero "$RC2" "second run exits cleanly"
assert_log_contains "/tmp/${CONTAINER}-2.log" "Oh My Zsh already installed" "OMZ skipped on re-run"
assert_log_contains "/tmp/${CONTAINER}-2.log" "Powerlevel10k already installed" "P10k skipped on re-run"
assert_log_contains "/tmp/${CONTAINER}-2.log" "zsh-autosuggestions already installed" "autosuggestions skipped on re-run"

# zshrc must still be a symlink after second run too
assert_exec_in "$CONTAINER" ".zshrc still symlinked after re-run" test -L /home/testuser/.zshrc

rm -f "/tmp/${CONTAINER}-2.log"
print_summary
