#!/usr/bin/env bash
set -Eeuo pipefail

# Safe maintenance entrypoint. Default operation is read-only.
# OS updates require explicit --apply-os-updates and never modify Docker data.

MODE="${1:---check}"
log() { printf '[vps-maintenance] %s\n' "$*"; }
die() { printf '[vps-maintenance] ERROR: %s\n' "$*" >&2; exit 1; }

case "$MODE" in
  --check)
    log 'Read-only status check; no changes will be made.'
    printf '\nOS: '
    if [[ -r /etc/os-release ]]; then . /etc/os-release; printf '%s\n' "${PRETTY_NAME:-unknown}"; else echo unknown; fi
    printf '\nDisk usage:\n'
    df -h /
    printf '\nDocker containers:\n'
    if command -v docker >/dev/null 2>&1; then
      docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
      docker system df 2>/dev/null || true
    else
      echo 'Docker is not installed.'
    fi
    printf '\nService state:\n'
    for service in ssh docker nginx fail2ban; do
      printf '%-12s %s\n' "$service" "$(systemctl is-active "$service" 2>/dev/null || true)"
    done
    printf '\nFirewall:\n'
    ufw status 2>/dev/null || true
    printf '\nJournal usage:\n'
    journalctl --disk-usage 2>/dev/null || true
    printf '\nBackup directory (names and metadata only):\n'
    ls -ld --time-style=long-iso /var/backups/cortexbuild-* 2>/dev/null || echo 'No matching CortexBuild backups found.'
    printf '\nNginx configuration test:\n'
    if command -v nginx >/dev/null 2>&1; then nginx -t 2>&1 || true; else echo 'Nginx is not installed.'; fi
    log 'CHECK_COMPLETE; no files, services, containers, volumes, logs, or backups were changed.'
    ;;

  --apply-os-updates)
    [[ ${EUID} -eq 0 ]] || die 'Run OS updates as root.'
    command -v flock >/dev/null 2>&1 || die 'flock is required.'
    exec 9>/run/lock/vps-os-updates.lock
    flock -n 9 || die 'Another OS update is already running.'
    export DEBIAN_FRONTEND=noninteractive
    log 'Applying apt package updates only. Docker images, containers, volumes, project dependencies, logs, and backups will not be pruned or deleted.'
    apt-get update
    apt-get upgrade -y
    printf '\nReboot status:\n'
    if [[ -f /var/run/reboot-required ]]; then
      echo 'REBOOT_REQUIRED=yes'
      cat /var/run/reboot-required.pkgs 2>/dev/null || true
    else
      echo 'REBOOT_REQUIRED=no'
    fi
    log 'OS package update command completed. Review service health and reboot requirements before scheduling a restart.'
    ;;

  --help|-h)
    cat <<'HELP'
Usage:
  bash update-vps.sh                 Read-only status check (default)
  sudo bash update-vps.sh --check    Read-only status check
  sudo bash update-vps.sh --apply-os-updates
                                     Apply Ubuntu apt upgrades only

This script never prunes Docker resources, removes backups, truncates logs,
changes Node dependencies, pulls/recreates application containers, or restarts
production application services.
HELP
    ;;

  *)
    die "Unknown option: $MODE (use --check, --apply-os-updates, or --help)."
    ;;
esac
