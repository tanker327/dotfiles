#!/bin/bash
#
# systemctl-shim.sh — translates systemctl(8) calls into pg_ctlcluster /
# service equivalents for use inside a non-systemd Docker test container.
#
# This is for the postgres install test only. Do NOT install on a real host.
#
# Supports:
#   systemctl start|stop|restart|reload postgresql      -> pg_ctlcluster
#   systemctl enable|disable|is-enabled postgresql      -> no-op (returns 0)
#   systemctl status postgresql                          -> pg_lsclusters
#   systemctl is-active postgresql                       -> pg_isready
# Anything else: prints what it would do and returns 0 to keep installers happy.

set -e

verb="${1:-}"
unit="${2:-}"
unit="${unit%.service}"

pg_main_version() {
    ls /etc/postgresql 2>/dev/null | sort -V | tail -1
}

case "$verb" in
    start|stop|restart|reload)
        if [ "$unit" = "postgresql" ]; then
            ver=$(pg_main_version)
            if [ -z "$ver" ]; then
                echo "systemctl-shim: postgresql not yet installed; treating $verb as no-op" >&2
                exit 0
            fi
            exec pg_ctlcluster "$ver" main "$verb"
        fi
        ;;
    enable|disable|is-enabled|mask|unmask|daemon-reload)
        # No-ops in this container
        exit 0
        ;;
    status)
        if [ "$unit" = "postgresql" ]; then
            exec pg_lsclusters
        fi
        ;;
    is-active)
        if [ "$unit" = "postgresql" ]; then
            sudo -u postgres pg_isready -q && echo "active" && exit 0
            echo "inactive"
            exit 3
        fi
        ;;
esac

# Default: log + succeed so installers don't crash on unknown verbs
echo "systemctl-shim: ignoring 'systemctl $*'" >&2
exit 0
