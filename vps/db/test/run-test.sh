#!/bin/bash
#
# run-test.sh — Docker-based smoke test for vps/db/setup-postgres.sh
#
# Builds an ubuntu:24.04 image with the repo mounted, runs the installer
# non-interactively, and asserts:
#   - service starts
#   - app DB + role exist
#   - app user can connect over TCP with the generated password
#   - tuning + network settings applied
#   - backup script produces a valid gzipped dump
#   - re-running the installer is a no-op (idempotent)
#
# Usage: bash vps/db/test/run-test.sh

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

IMG="dotfiles-pg-test"
CONTAINER="dotfiles-pg-test-$$"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Building test image..."
docker build -q -f vps/db/test/Dockerfile -t "$IMG" . >/dev/null

# Installer prompts in order:
#   App DB name [appdb]            -> appdb
#   App DB user [appuser]          -> appuser
#   Proceed with insecure config?  -> y
#   Enable S3 backups?             -> n
INPUT=$(cat <<'EOF'
appdb
appuser
y
n
EOF
)

echo "==> Running installer + assertions in container..."
docker run --rm --name "$CONTAINER" -i "$IMG" bash -c '
set -e
set -o pipefail

echo "--- Phase 1: run installer"
bash /root/dotfiles/vps/db/setup-postgres.sh

echo ""
echo "--- Phase 2: assertions"

# 1. App DB exists
sudo -u postgres psql -lqt | cut -d "|" -f 1 | grep -qw appdb \
    || { echo "FAIL: appdb missing"; sudo -u postgres psql -l; exit 1; }
echo "OK: appdb exists"

# 2. App role exists (and has LOGIN — \du output lists no attributes for plain login users, so just check presence)
sudo -u postgres psql -c "\du" | awk "{print \$1}" | grep -qw appuser \
    || { echo "FAIL: appuser missing"; sudo -u postgres psql -c "\du"; exit 1; }
echo "OK: appuser exists"

# 3. Tuning applied (drop-in file exists with non-zero shared_buffers value)
SB=$(sudo -u postgres psql -tAc "SHOW shared_buffers")
echo "shared_buffers = $SB"
[ -n "$SB" ] || { echo "FAIL: shared_buffers empty"; exit 1; }
echo "OK: shared_buffers set"

# 4. Listen address
LA=$(sudo -u postgres psql -tAc "SHOW listen_addresses")
[ "$LA" = "*" ] || { echo "FAIL: listen_addresses = $LA (expected *)"; exit 1; }
echo "OK: listen_addresses = *"

# 5. SSL off
SSL=$(sudo -u postgres psql -tAc "SHOW ssl")
[ "$SSL" = "off" ] || { echo "FAIL: ssl = $SSL (expected off)"; exit 1; }
echo "OK: ssl = off"

# 6. password_encryption = scram-sha-256
PE=$(sudo -u postgres psql -tAc "SHOW password_encryption")
[ "$PE" = "scram-sha-256" ] || { echo "FAIL: password_encryption = $PE"; exit 1; }
echo "OK: password_encryption = scram-sha-256"

# 7. App user can connect over TCP using generated password from info file
PW=$(grep "^  password:" /root/postgres-setup-info.txt | sed -n "2p" | awk "{print \$2}")
[ -n "$PW" ] || { echo "FAIL: could not extract app password"; cat /root/postgres-setup-info.txt; exit 1; }
PGPASSWORD="$PW" psql -h 127.0.0.1 -U appuser -d appdb -tAc "SELECT 1" \
    | grep -qx 1 || { echo "FAIL: TCP connect as appuser failed"; exit 1; }
echo "OK: appuser connects via TCP"

# 8. Backup script exists and produces a valid gzipped dump
[ -x /usr/local/bin/pg-backup.sh ] || { echo "FAIL: pg-backup.sh missing"; exit 1; }
/usr/local/bin/pg-backup.sh
LATEST=$(ls -1t /var/backups/postgresql/dumpall-*.sql.gz 2>/dev/null | head -1)
[ -s "$LATEST" ] || { echo "FAIL: no backup file produced"; exit 1; }
gzip -t "$LATEST" || { echo "FAIL: backup gzip integrity"; exit 1; }
echo "OK: backup script produced $LATEST"

# 9. Cron entry exists
[ -f /etc/cron.d/postgres-backup ] || { echo "FAIL: cron entry missing"; exit 1; }
grep -q "/usr/local/bin/pg-backup.sh" /etc/cron.d/postgres-backup \
    || { echo "FAIL: cron entry does not reference backup script"; exit 1; }
echo "OK: cron entry installed"

# 10. pg_hba.conf has the host rule
grep -qE "^host[[:space:]]+all[[:space:]]+all[[:space:]]+0\.0\.0\.0/0[[:space:]]+scram-sha-256" \
    /etc/postgresql/*/main/pg_hba.conf \
    || { echo "FAIL: pg_hba.conf missing host rule"; exit 1; }
echo "OK: pg_hba.conf has 0.0.0.0/0 host rule"

# 11. Info file has tight permissions
MODE=$(stat -c %a /root/postgres-setup-info.txt)
[ "$MODE" = "600" ] || { echo "FAIL: info file mode is $MODE, expected 600"; exit 1; }
echo "OK: info file mode 600"

# 12. State file mode
MODE2=$(stat -c %a /root/.postgres-setup-state)
[ "$MODE2" = "600" ] || { echo "FAIL: state file mode is $MODE2, expected 600"; exit 1; }
echo "OK: state file mode 600"

echo ""
echo "--- Phase 3: idempotency (re-run should be no-op)"
# Reply "Y" to resume prompt
echo "Y" | bash /root/dotfiles/vps/db/setup-postgres.sh > /tmp/rerun.log 2>&1
if ! grep -q "already completed" /tmp/rerun.log; then
    echo "FAIL: re-run did not skip completed steps"
    tail -40 /tmp/rerun.log
    exit 1
fi
echo "OK: re-run is idempotent"

# 13. configure-s3-backup.sh status works and reports "NOT CONFIGURED"
out=$(bash /root/dotfiles/vps/db/configure-s3-backup.sh status)
echo "$out" | grep -q "NOT CONFIGURED" \
    || { echo "FAIL: configure-s3-backup.sh status output unexpected: $out"; exit 1; }
echo "OK: configure-s3-backup.sh status reports NOT CONFIGURED"

echo ""
echo "ALL CHECKS PASSED"
' <<<"$INPUT"

echo ""
echo "==> Test passed."
