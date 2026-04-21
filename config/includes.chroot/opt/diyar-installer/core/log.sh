#!/usr/bin/env bash
# =============================================================================
# Diyar OS Installer — Logging
# core/log.sh
# =============================================================================

LOG_FILE="${LOG_FILE:-/var/log/diyar-installer.log}"

log_info() {
    local ts; ts="$(date '+%H:%M:%S')"
    echo "[${ts}] INFO  $*" | tee -a "$LOG_FILE"
}

log_warn() {
    local ts; ts="$(date '+%H:%M:%S')"
    echo "[${ts}] WARN  $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    local ts; ts="$(date '+%H:%M:%S')"
    echo "[${ts}] ERROR $*" | tee -a "$LOG_FILE" >&2
}

die() {
    log_error "$*"
    progress 0 "ERROR: $*"
    exit 1
}
