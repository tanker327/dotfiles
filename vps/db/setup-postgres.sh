#!/bin/bash

SCRIPT_VERSION="1.0.0"

#####################################################
# PostgreSQL Production Setup Script
#####################################################
# Supports: Ubuntu 22.04 / 24.04, Debian 12
# Usage:    sudo bash setup-postgres.sh
# Or:       curl -fsSL <url>/setup-postgres.sh | sudo bash
#
# What it does:
#   - Installs PostgreSQL from the official PGDG apt repo
#   - Applies memory-aware tuning (shared_buffers, work_mem, ...)
#   - Configures network access (listen=*, scram-sha-256 auth)
#   - Hardens logging (slow queries, connections, lock waits)
#   - Opens UFW (if active) on tcp/5432
#   - Creates an application DB + role with a generated password
#   - Installs daily pg_dumpall backup via cron, 7-day retention
#   - Optional offsite upload to S3 (asks at install time, or
#     run vps/db/configure-s3-backup.sh later)
#
# Idempotent: safe to re-run. State tracked in /root/.postgres-setup-state
# Credentials written to /root/postgres-setup-info.txt (chmod 600)
#
# SECURITY WARNING: by default this opens 5432 to 0.0.0.0/0 with SSL off.
# Auth is SCRAM-SHA-256 (passwords are not sent in plaintext), but session
# data is. For prod, restrict via UFW to a CIDR or front via Tailscale/WG,
# and/or enable SSL with a real cert.
#####################################################

set -e
set -o pipefail

# Interactive input source. /dev/tty works under `curl | sudo bash`; stdin
# fallback supports docker -i and CI piping. The brace group is needed because
# bash prints "/dev/tty: No such device" before honoring `2>/dev/null` on a
# bare `exec` redirection.
if ! { exec 3< /dev/tty; } 2>/dev/null; then
    exec 3<&0
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SETUP_INFO_FILE="/root/postgres-setup-info.txt"
STATE_FILE="/root/.postgres-setup-state"
PG_BACKUP_ENV="/root/.pg-backup.env"
PG_BACKUP_SCRIPT="/usr/local/bin/pg-backup.sh"
PG_BACKUP_DIR="/var/backups/postgresql"
PG_BACKUP_CRON="/etc/cron.d/postgres-backup"

#####################################################
# Utility Functions
#####################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    [ -f "$SETUP_INFO_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$SETUP_INFO_FILE" || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    [ -f "$SETUP_INFO_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$SETUP_INFO_FILE" || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    [ -f "$SETUP_INFO_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$SETUP_INFO_FILE" || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    [ -f "$SETUP_INFO_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$SETUP_INFO_FILE" || true
}

section_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

mark_step_complete() {
    echo "$1=done" >> "$STATE_FILE"
    log_info "Step '$1' marked complete"
}

is_step_complete() {
    [ -f "$STATE_FILE" ] && grep -q "^$1=done$" "$STATE_FILE"
}

skip_if_complete() {
    local step="$1"
    if is_step_complete "$step"; then
        log_info "Step '$step' already completed, skipping..."
        return 0
    fi
    return 1
}

save_state() {
    # Persist a key=value pair so we can resume with the same inputs.
    local key="$1"
    local value="$2"
    # Remove any existing value for this key first
    if [ -f "$STATE_FILE" ]; then
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
    echo "${key}=${value}" >> "$STATE_FILE"
}

load_state() {
    local key="$1"
    [ -f "$STATE_FILE" ] || return 1
    local line
    line=$(grep "^${key}=" "$STATE_FILE" | tail -1) || return 1
    [ -n "$line" ] || return 1
    echo "${line#*=}"
}

generate_password() {
    openssl rand -base64 32 | tr -d '=+/' | head -c 32
}

#####################################################
# Pre-flight
#####################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "/etc/os-release not found — cannot detect OS"
        exit 1
    fi
    . /etc/os-release
    case "$ID" in
        ubuntu|debian) : ;;
        *)
            log_error "Unsupported OS: $ID. This script supports Ubuntu and Debian."
            exit 1
            ;;
    esac
    OS_ID="$ID"
    OS_CODENAME="${VERSION_CODENAME:-}"
    if [ -z "$OS_CODENAME" ]; then
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
    fi
    if [ -z "$OS_CODENAME" ]; then
        log_error "Could not determine OS codename"
        exit 1
    fi
    log_info "Detected $OS_ID $OS_CODENAME"
}

resume_or_fresh() {
    if [ -f "$STATE_FILE" ]; then
        section_header "Previous Setup Detected"
        log_warning "State file exists at $STATE_FILE"
        echo "Completed steps:"
        grep '=done$' "$STATE_FILE" | sed 's/^/  - /' || echo "  (none)"
        echo ""
        read -p "Resume previous setup? [Y/n]: " RESUME <&3
        RESUME="${RESUME:-Y}"
        if [[ ! "$RESUME" =~ ^[Yy]$ ]]; then
            log_info "Starting fresh — clearing state file"
            rm -f "$STATE_FILE"
        fi
    fi
}

#####################################################
# Input Collection
#####################################################

collect_inputs() {
    if skip_if_complete "inputs_collected"; then
        APP_DB_NAME=$(load_state "APP_DB_NAME")
        APP_DB_USER=$(load_state "APP_DB_USER")
        APP_DB_PASSWORD=$(load_state "APP_DB_PASSWORD")
        POSTGRES_SUPERUSER_PASSWORD=$(load_state "POSTGRES_SUPERUSER_PASSWORD")
        ENABLE_S3=$(load_state "ENABLE_S3")
        if [ "$ENABLE_S3" = "yes" ]; then
            S3_BUCKET=$(load_state "S3_BUCKET")
            AWS_REGION=$(load_state "AWS_REGION")
            AWS_ACCESS_KEY_ID=$(load_state "AWS_ACCESS_KEY_ID")
            AWS_SECRET_ACCESS_KEY=$(load_state "AWS_SECRET_ACCESS_KEY")
            S3_RETENTION_DAYS=$(load_state "S3_RETENTION_DAYS")
        fi
        return
    fi

    section_header "Configuration"

    read -p "App database name [appdb]: " APP_DB_NAME <&3
    APP_DB_NAME="${APP_DB_NAME:-appdb}"

    read -p "App database user [appuser]: " APP_DB_USER <&3
    APP_DB_USER="${APP_DB_USER:-appuser}"

    APP_DB_PASSWORD=$(generate_password)
    POSTGRES_SUPERUSER_PASSWORD=$(generate_password)
    log_info "Generated strong random passwords for postgres superuser and app user"

    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  SECURITY WARNING${NC}"
    echo -e "${RED}========================================${NC}"
    echo "PostgreSQL will be configured to listen on 0.0.0.0 with SSL DISABLED."
    echo "  - Auth uses SCRAM-SHA-256 (password never sent in plaintext)"
    echo "  - But session traffic is unencrypted"
    echo ""
    echo "Recommended for prod:"
    echo "  - Restrict UFW to a specific CIDR (your app servers)"
    echo "  - Or front-end via Tailscale / WireGuard"
    echo "  - Or enable SSL with a real cert"
    echo -e "${RED}========================================${NC}"
    read -p "Proceed with these settings? [y/N]: " ACK <&3
    if [[ ! "$ACK" =~ ^[Yy]$ ]]; then
        log_error "Aborted by user"
        exit 1
    fi

    echo ""
    read -p "Enable S3 upload for daily backups? [y/N]: " S3_YN <&3
    if [[ "$S3_YN" =~ ^[Yy]$ ]]; then
        ENABLE_S3="yes"
        read -p "  S3 bucket prefix (e.g. s3://my-pg-backups/host1/): " S3_BUCKET <&3
        read -p "  AWS region [us-east-1]: " AWS_REGION <&3
        AWS_REGION="${AWS_REGION:-us-east-1}"
        read -p "  AWS access key ID: " AWS_ACCESS_KEY_ID <&3
        read -rsp "  AWS secret access key: " AWS_SECRET_ACCESS_KEY <&3
        echo ""
        read -p "  S3 retention days [30]: " S3_RETENTION_DAYS <&3
        S3_RETENTION_DAYS="${S3_RETENTION_DAYS:-30}"
    else
        ENABLE_S3="no"
    fi

    # Persist for resume
    save_state "APP_DB_NAME" "$APP_DB_NAME"
    save_state "APP_DB_USER" "$APP_DB_USER"
    save_state "APP_DB_PASSWORD" "$APP_DB_PASSWORD"
    save_state "POSTGRES_SUPERUSER_PASSWORD" "$POSTGRES_SUPERUSER_PASSWORD"
    save_state "ENABLE_S3" "$ENABLE_S3"
    if [ "$ENABLE_S3" = "yes" ]; then
        save_state "S3_BUCKET" "$S3_BUCKET"
        save_state "AWS_REGION" "$AWS_REGION"
        save_state "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
        save_state "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
        save_state "S3_RETENTION_DAYS" "$S3_RETENTION_DAYS"
    fi

    # Lock down state file (contains passwords)
    chmod 600 "$STATE_FILE"

    mark_step_complete "inputs_collected"
}

#####################################################
# Install PostgreSQL from PGDG
#####################################################

install_postgresql() {
    if skip_if_complete "postgresql_installed"; then
        return
    fi
    section_header "Installing PostgreSQL from PGDG"

    apt-get update -qq
    apt-get install -y -qq curl ca-certificates gnupg lsb-release apt-transport-https

    install -d -m 0755 /etc/apt/keyrings
    if [ ! -s /etc/apt/keyrings/postgresql.gpg ]; then
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
            | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
    fi

    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt ${OS_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list

    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql postgresql-contrib

    mark_step_complete "postgresql_installed"
}

detect_pg_version() {
    PG_VERSION=$(ls /etc/postgresql 2>/dev/null | sort -V | tail -1)
    if [ -z "$PG_VERSION" ]; then
        log_error "Could not detect installed PostgreSQL version under /etc/postgresql"
        exit 1
    fi
    PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
    PG_CONF_FILE="${PG_CONF_DIR}/postgresql.conf"
    PG_HBA_FILE="${PG_CONF_DIR}/pg_hba.conf"
    PG_CONFD_DIR="${PG_CONF_DIR}/conf.d"
    log_info "Detected PostgreSQL version: ${PG_VERSION}"
}

#####################################################
# Memory-aware tuning
#####################################################

apply_tuning() {
    if skip_if_complete "tuning_applied"; then
        return
    fi
    section_header "Applying Memory-Aware Tuning"

    local mem_kb mem_mb
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    mem_mb=$(( mem_kb / 1024 ))
    log_info "Detected system memory: ${mem_mb} MB"

    # shared_buffers = 25% of RAM, cap at 8GB
    local shared_buffers_mb=$(( mem_mb / 4 ))
    if [ "$shared_buffers_mb" -gt 8192 ]; then
        shared_buffers_mb=8192
    fi
    if [ "$shared_buffers_mb" -lt 128 ]; then
        shared_buffers_mb=128
    fi

    # effective_cache_size = 75% of RAM
    local effective_cache_mb=$(( mem_mb * 3 / 4 ))
    if [ "$effective_cache_mb" -lt 512 ]; then
        effective_cache_mb=512
    fi

    # maintenance_work_mem = min(2GB, 6% RAM)
    local maint_mb=$(( mem_mb * 6 / 100 ))
    if [ "$maint_mb" -gt 2048 ]; then
        maint_mb=2048
    fi
    if [ "$maint_mb" -lt 64 ]; then
        maint_mb=64
    fi

    # work_mem (~ for 100 active connections, very rough heuristic)
    local work_mem_mb=$(( mem_mb / 200 ))
    if [ "$work_mem_mb" -lt 4 ]; then
        work_mem_mb=4
    fi

    install -d -m 0755 -o postgres -g postgres "$PG_CONFD_DIR"

    # Make sure postgresql.conf includes the conf.d directory (Debian/Ubuntu
    # defaults already do, but check to be safe).
    if ! grep -qE "^[[:space:]]*include_dir[[:space:]]*=[[:space:]]*'conf\.d'" "$PG_CONF_FILE"; then
        echo "include_dir = 'conf.d'" >> "$PG_CONF_FILE"
        log_info "Added 'include_dir = conf.d' to postgresql.conf"
    fi

    cat > "${PG_CONFD_DIR}/10-tuning.conf" <<EOF
# Memory-aware tuning generated by setup-postgres.sh ${SCRIPT_VERSION}
# System RAM detected: ${mem_mb} MB
shared_buffers = ${shared_buffers_mb}MB
effective_cache_size = ${effective_cache_mb}MB
maintenance_work_mem = ${maint_mb}MB
work_mem = ${work_mem_mb}MB
max_connections = 200
wal_buffers = -1
checkpoint_completion_target = 0.9
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100
EOF
    chown postgres:postgres "${PG_CONFD_DIR}/10-tuning.conf"
    chmod 640 "${PG_CONFD_DIR}/10-tuning.conf"
    log_success "Tuning written to ${PG_CONFD_DIR}/10-tuning.conf"

    mark_step_complete "tuning_applied"
}

#####################################################
# Network config
#####################################################

apply_network_config() {
    if skip_if_complete "network_configured"; then
        return
    fi
    section_header "Configuring Network Access"

    cat > "${PG_CONFD_DIR}/20-network.conf" <<EOF
# Network configuration generated by setup-postgres.sh ${SCRIPT_VERSION}
listen_addresses = '*'
port = 5432
password_encryption = scram-sha-256
ssl = off
EOF
    chown postgres:postgres "${PG_CONFD_DIR}/20-network.conf"
    chmod 640 "${PG_CONFD_DIR}/20-network.conf"

    # Append host rules if not already present
    if ! grep -qE "^host[[:space:]]+all[[:space:]]+all[[:space:]]+0\.0\.0\.0/0" "$PG_HBA_FILE"; then
        cat >> "$PG_HBA_FILE" <<EOF

# Added by setup-postgres.sh ${SCRIPT_VERSION}
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF
        log_success "Appended remote-access rules to pg_hba.conf"
    else
        log_info "pg_hba.conf already has 0.0.0.0/0 host rule, skipping"
    fi

    mark_step_complete "network_configured"
}

#####################################################
# Logging
#####################################################

apply_logging_config() {
    if skip_if_complete "logging_configured"; then
        return
    fi
    section_header "Configuring Logging"

    cat > "${PG_CONFD_DIR}/30-logging.conf" <<EOF
# Logging configuration generated by setup-postgres.sh ${SCRIPT_VERSION}
logging_collector = on
log_destination = 'stderr'
log_filename = 'postgresql-%a.log'
log_truncate_on_rotation = on
log_rotation_age = 1d
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_line_prefix = '%m [%p] %q%u@%d '
EOF
    chown postgres:postgres "${PG_CONFD_DIR}/30-logging.conf"
    chmod 640 "${PG_CONFD_DIR}/30-logging.conf"

    mark_step_complete "logging_configured"
}

#####################################################
# Restart service & wait for ready
#####################################################

restart_postgres() {
    if skip_if_complete "postgres_restarted"; then
        return
    fi
    section_header "Restarting PostgreSQL"

    systemctl enable postgresql >/dev/null 2>&1 || true
    systemctl restart postgresql

    local i
    for i in $(seq 1 30); do
        if sudo -u postgres pg_isready -q; then
            log_success "PostgreSQL is ready"
            mark_step_complete "postgres_restarted"
            return
        fi
        sleep 1
    done
    log_error "PostgreSQL did not become ready within 30s"
    exit 1
}

#####################################################
# Create roles / DB
#####################################################

create_roles_and_db() {
    if skip_if_complete "roles_and_db_created"; then
        return
    fi
    section_header "Creating Application Database and Role"

    # psql -v variables are not substituted inside dollar-quoted ($$..$$)
    # strings, so we do existence checks at the bash level and run plain
    # CREATE/ALTER statements outside any DO block. Passwords go through
    # :'name' so psql handles the literal-quoting safely.

    # Set the postgres superuser password (ALTER USER is idempotent)
    sudo -u postgres psql -v ON_ERROR_STOP=1 \
        -v pgpass="${POSTGRES_SUPERUSER_PASSWORD}" <<'SQL'
ALTER USER postgres WITH PASSWORD :'pgpass';
SQL

    # App role: create if missing, otherwise update the password
    local role_exists
    role_exists=$(sudo -u postgres psql -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname='${APP_DB_USER}'")
    if [ "$role_exists" != "1" ]; then
        sudo -u postgres psql -v ON_ERROR_STOP=1 \
            -v rolpass="${APP_DB_PASSWORD}" <<SQL
CREATE ROLE "${APP_DB_USER}" LOGIN PASSWORD :'rolpass';
SQL
        log_success "Created role ${APP_DB_USER}"
    else
        sudo -u postgres psql -v ON_ERROR_STOP=1 \
            -v rolpass="${APP_DB_PASSWORD}" <<SQL
ALTER ROLE "${APP_DB_USER}" WITH LOGIN PASSWORD :'rolpass';
SQL
        log_info "Role ${APP_DB_USER} already exists; password updated"
    fi

    # App database: CREATE DATABASE can't run inside a transaction block, so
    # we check first and conditionally run it.
    local db_exists
    db_exists=$(sudo -u postgres psql -tAc \
        "SELECT 1 FROM pg_database WHERE datname='${APP_DB_NAME}'")
    if [ "$db_exists" != "1" ]; then
        sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
            "CREATE DATABASE \"${APP_DB_NAME}\" OWNER \"${APP_DB_USER}\""
        log_success "Created database ${APP_DB_NAME}"
    else
        log_info "Database ${APP_DB_NAME} already exists, skipping create"
    fi

    sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
        "GRANT ALL PRIVILEGES ON DATABASE \"${APP_DB_NAME}\" TO \"${APP_DB_USER}\""

    log_success "Application role and database ready"
    mark_step_complete "roles_and_db_created"
}

#####################################################
# UFW
#####################################################

configure_ufw() {
    if skip_if_complete "ufw_configured"; then
        return
    fi
    section_header "Configuring UFW"

    if ! command -v ufw >/dev/null 2>&1; then
        log_warning "ufw not installed — skipping firewall step"
        log_warning "If you enable UFW later, run: ufw allow 5432/tcp"
        mark_step_complete "ufw_configured"
        return
    fi
    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        log_warning "ufw is installed but inactive — skipping rule add"
        log_warning "If you enable UFW later, run: ufw allow 5432/tcp"
        mark_step_complete "ufw_configured"
        return
    fi

    ufw allow 5432/tcp comment 'PostgreSQL' >/dev/null
    log_success "Opened tcp/5432 in UFW"

    mark_step_complete "ufw_configured"
}

#####################################################
# AWS CLI v2 (only if S3 enabled)
#####################################################

install_aws_cli() {
    if skip_if_complete "aws_cli_installed"; then
        return
    fi
    if [ "${ENABLE_S3:-no}" != "yes" ]; then
        log_info "S3 disabled — skipping AWS CLI install"
        mark_step_complete "aws_cli_installed"
        return
    fi
    section_header "Installing AWS CLI v2"

    if command -v aws >/dev/null 2>&1; then
        local ver
        ver=$(aws --version 2>&1 | head -1)
        if echo "$ver" | grep -q "aws-cli/2"; then
            log_info "AWS CLI v2 already installed: $ver"
            mark_step_complete "aws_cli_installed"
            return
        fi
        log_warning "Found older AWS CLI ($ver), installing v2 alongside"
    fi

    apt-get install -y -qq unzip
    local arch
    arch=$(uname -m)
    local url
    case "$arch" in
        x86_64)  url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
        aarch64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
        *)
            log_error "Unsupported architecture for AWS CLI v2: $arch"
            exit 1
            ;;
    esac

    local tmpdir
    tmpdir=$(mktemp -d)
    curl -fsSL "$url" -o "$tmpdir/awscliv2.zip"
    unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir"
    if command -v aws >/dev/null 2>&1; then
        "$tmpdir/aws/install" --update
    else
        "$tmpdir/aws/install"
    fi
    rm -rf "$tmpdir"

    log_success "AWS CLI v2 installed: $(aws --version 2>&1)"
    mark_step_complete "aws_cli_installed"
}

#####################################################
# Backup script + cron
#####################################################

install_backup_script() {
    if skip_if_complete "backup_script_installed"; then
        return
    fi
    section_header "Installing Backup Script"

    install -d -m 0750 -o postgres -g postgres "$PG_BACKUP_DIR"

    cat > "$PG_BACKUP_SCRIPT" <<'BACKUP_EOF'
#!/bin/bash
#
# pg-backup.sh — daily PostgreSQL backup (installed by setup-postgres.sh)
#
# - Runs pg_dumpall as the postgres user, gzips, writes to /var/backups/postgresql
# - Prunes local dumps older than 7 days
# - If /root/.pg-backup.env exists, sources it and uploads to S3, then prunes
#   S3 objects older than $S3_RETENTION_DAYS
# - Logs to syslog under tag pg-backup
#
# Exit non-zero on any failure (cron will mail root).

set -e
set -o pipefail

BACKUP_DIR="/var/backups/postgresql"
ENV_FILE="/root/.pg-backup.env"
STAMP=$(date +%Y%m%d_%H%M%S)
OUT="${BACKUP_DIR}/dumpall-${STAMP}.sql.gz"
LOCAL_RETENTION_DAYS=7

log() { logger -t pg-backup -- "$*"; echo "$*"; }
fail() { logger -t pg-backup -p user.err -- "$*"; echo "ERROR: $*" >&2; exit 1; }

[ -d "$BACKUP_DIR" ] || fail "Backup dir $BACKUP_DIR does not exist"

log "Starting pg_dumpall to $OUT"
if ! sudo -u postgres pg_dumpall | gzip -9 > "$OUT"; then
    fail "pg_dumpall failed"
fi
if [ ! -s "$OUT" ]; then
    fail "Backup file $OUT is empty"
fi
if ! gzip -t "$OUT"; then
    fail "Backup gzip integrity check failed for $OUT"
fi
chown postgres:postgres "$OUT"
chmod 640 "$OUT"
SIZE=$(stat -c %s "$OUT" 2>/dev/null || stat -f %z "$OUT")
log "Local backup OK (${SIZE} bytes)"

# Prune local
find "$BACKUP_DIR" -name 'dumpall-*.sql.gz' -mtime "+${LOCAL_RETENTION_DAYS}" -delete
log "Pruned local backups older than ${LOCAL_RETENTION_DAYS} days"

# Optional S3 upload
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
    : "${S3_BUCKET:?S3_BUCKET not set in $ENV_FILE}"
    : "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set in $ENV_FILE}"
    : "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set in $ENV_FILE}"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    DEST="${S3_BUCKET%/}/dumpall-${STAMP}.sql.gz"
    log "Uploading to $DEST"
    if ! aws s3 cp "$OUT" "$DEST" --only-show-errors; then
        fail "S3 upload to $DEST failed"
    fi
    log "S3 upload OK"

    # Prune S3 objects older than $S3_RETENTION_DAYS
    S3_RETENTION_DAYS="${S3_RETENTION_DAYS:-30}"
    CUTOFF=$(date -u -d "${S3_RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null \
        || date -u -v-"${S3_RETENTION_DAYS}"d +%Y-%m-%d)
    aws s3 ls "${S3_BUCKET%/}/" 2>/dev/null \
        | awk '{print $1, $4}' \
        | while read -r DATE NAME; do
            [ -z "$NAME" ] && continue
            case "$NAME" in
                dumpall-*.sql.gz) : ;;
                *) continue ;;
            esac
            if [[ "$DATE" < "$CUTOFF" ]]; then
                log "Pruning old S3 object: $NAME (uploaded $DATE)"
                aws s3 rm "${S3_BUCKET%/}/$NAME" --only-show-errors || \
                    log "WARN: failed to delete $NAME"
            fi
        done
    log "S3 prune complete (cutoff ${CUTOFF})"
else
    log "No $ENV_FILE — local backup only"
fi

log "Backup run complete"
BACKUP_EOF

    chmod 750 "$PG_BACKUP_SCRIPT"
    chown root:root "$PG_BACKUP_SCRIPT"

    # Cron entry — runs as root so it can read /root/.pg-backup.env
    cat > "$PG_BACKUP_CRON" <<EOF
# Daily PostgreSQL backup — installed by setup-postgres.sh ${SCRIPT_VERSION}
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 3 * * * root ${PG_BACKUP_SCRIPT}
EOF
    chmod 644 "$PG_BACKUP_CRON"
    log_success "Installed ${PG_BACKUP_SCRIPT} and daily cron at 03:15"

    mark_step_complete "backup_script_installed"
}

write_s3_env_file() {
    if skip_if_complete "s3_env_written"; then
        return
    fi
    if [ "${ENABLE_S3:-no}" != "yes" ]; then
        log_info "S3 disabled — skipping env file"
        mark_step_complete "s3_env_written"
        return
    fi
    section_header "Writing S3 Backup Env File"

    umask 077
    cat > "$PG_BACKUP_ENV" <<EOF
# Generated by setup-postgres.sh ${SCRIPT_VERSION}
# Used by ${PG_BACKUP_SCRIPT}. Owner: root, mode 600.
S3_BUCKET="${S3_BUCKET}"
AWS_DEFAULT_REGION="${AWS_REGION}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
S3_RETENTION_DAYS="${S3_RETENTION_DAYS}"
EOF
    chmod 600 "$PG_BACKUP_ENV"
    chown root:root "$PG_BACKUP_ENV"
    umask 022
    log_success "Wrote ${PG_BACKUP_ENV} (mode 600)"

    mark_step_complete "s3_env_written"
}

#####################################################
# Summary
#####################################################

write_summary() {
    section_header "Setup Complete"

    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$server_ip" ] && server_ip="<server-ip>"

    local s3_status="disabled"
    if [ "${ENABLE_S3:-no}" = "yes" ]; then
        s3_status="enabled -> ${S3_BUCKET} (retention ${S3_RETENTION_DAYS}d)"
    fi

    umask 077
    cat > "$SETUP_INFO_FILE" <<EOF
PostgreSQL Setup Summary
========================
Setup script:        setup-postgres.sh v${SCRIPT_VERSION}
Detected OS:         ${OS_ID} ${OS_CODENAME}
Date:                $(date '+%Y-%m-%d %H:%M:%S %Z')
PostgreSQL version:  ${PG_VERSION}
Listen address:      *
Port:                5432
SSL:                 OFF

Postgres superuser:
  user:     postgres
  password: ${POSTGRES_SUPERUSER_PASSWORD}

Application:
  database: ${APP_DB_NAME}
  user:     ${APP_DB_USER}
  password: ${APP_DB_PASSWORD}

Connection examples:
  psql "host=${server_ip} dbname=${APP_DB_NAME} user=${APP_DB_USER}"
  postgresql://${APP_DB_USER}:${APP_DB_PASSWORD}@${server_ip}:5432/${APP_DB_NAME}

Config:
  postgresql.conf: ${PG_CONF_FILE}
  drop-in dir:     ${PG_CONFD_DIR}
  pg_hba.conf:     ${PG_HBA_FILE}
  log dir:         /var/log/postgresql

Backups:
  script:    ${PG_BACKUP_SCRIPT}
  cron:      ${PG_BACKUP_CRON} (daily 03:15)
  local dir: ${PG_BACKUP_DIR} (7-day retention)
  S3:        ${s3_status}
  env file:  ${PG_BACKUP_ENV} (only if S3 enabled)

To enable / change / disable S3 backups later:
  sudo bash vps/db/configure-s3-backup.sh {enable|disable|status}

Bucket lifecycle:
  The backup script prunes old objects in S3, but configuring a bucket
  lifecycle policy in AWS is the more robust option for long-term retention.

============================================================
SECURITY WARNING
============================================================
PostgreSQL is exposed on 0.0.0.0:5432 with SSL DISABLED.

Authentication uses SCRAM-SHA-256 (passwords are not sent in plaintext),
but session traffic is unencrypted. To harden:

  1. Restrict UFW to your app server CIDR:
       ufw delete allow 5432/tcp
       ufw allow from 10.0.0.0/8 to any port 5432

  2. OR front-end via Tailscale / WireGuard (much safer).

  3. OR enable SSL with a real cert in ${PG_CONFD_DIR}/20-network.conf
     (set ssl = on and provide ssl_cert_file / ssl_key_file).
============================================================
EOF
    chmod 600 "$SETUP_INFO_FILE"
    umask 022

    cat "$SETUP_INFO_FILE"
    echo ""
    log_success "Full details saved to $SETUP_INFO_FILE (mode 600)"
}

#####################################################
# Main
#####################################################

main() {
    check_root
    check_os
    resume_or_fresh

    collect_inputs
    install_postgresql
    detect_pg_version
    apply_tuning
    apply_network_config
    apply_logging_config
    restart_postgres
    create_roles_and_db
    configure_ufw
    install_aws_cli
    install_backup_script
    write_s3_env_file
    write_summary
}

main "$@"
