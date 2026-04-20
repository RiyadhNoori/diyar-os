#!/usr/bin/env bash
# =============================================================================
# Diyar OS — Master Build Script
# scripts/build.sh
#
# Usage:
#   sudo bash scripts/build.sh [--clean] [--no-net]
#
# Requires Debian 12 host with live-build installed.
# =============================================================================

set -euo pipefail

RED='\033[0;31m' GRN='\033[0;32m' CYN='\033[0;36m'
YLW='\033[1;33m' BLD='\033[1m'    RST='\033[0m'

info()  { echo -e "${CYN}${BLD}[DIYAR]${RST} $*"; }
ok()    { echo -e "${GRN}${BLD}[  OK ]${RST} $*"; }
warn()  { echo -e "${YLW}${BLD}[ WRN ]${RST} $*"; }
die()   { echo -e "${RED}${BLD}[ ERR ]${RST} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

DO_CLEAN=false
OFFLINE=false

for arg in "$@"; do
    case "$arg" in
        --clean)  DO_CLEAN=true ;;
        --no-net) OFFLINE=true ;;
    esac
done

# --- Guards ---
[[ $EUID -eq 0 ]] || die "Must run as root: sudo bash scripts/build.sh"
command -v lb &>/dev/null || \
    die "live-build not installed. Run: apt-get install live-build"

# --- Dependencies ---
info "Checking build dependencies..."
DEPS=(live-build debootstrap squashfs-tools xorriso grub-pc-bin
      grub-efi-amd64-bin mtools isolinux syslinux-common rsync)
MISSING=()
for d in "${DEPS[@]}"; do
    dpkg -l "$d" &>/dev/null | grep -q "^ii" || MISSING+=("$d")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Installing missing deps: ${MISSING[*]}"
    apt-get install -y "${MISSING[@]}"
fi
ok "Dependencies satisfied."

cd "${PROJECT_ROOT}"

# --- Clean ---
if $DO_CLEAN; then
    info "Cleaning previous build..."
    bash auto/clean
    ok "Clean complete."
fi

# --- Configure ---
info "Running lb config..."
bash auto/config
ok "Configuration complete."

# --- Build ---
info "Starting live-build... (this takes 20-60 minutes)"
info "Log: ${PROJECT_ROOT}/build.log"
echo ""

START_TIME=$SECONDS

bash auto/build 2>&1 | tee build.log | \
    grep -E "^(P:|N:|I:|W:|E:|Get:|Ign:|Err|Setting up|Unpacking|\[DIYAR\])" \
    || true

BUILD_TIME=$(( SECONDS - START_TIME ))

# --- Check output ---
ISO_FILE="$(find . -maxdepth 1 -name "*.iso" 2>/dev/null | head -1 || true)"

if [[ -z "$ISO_FILE" ]]; then
    die "Build FAILED — no ISO produced. Check build.log"
fi

ISO_SIZE="$(du -sh "$ISO_FILE" | cut -f1)"

echo ""
echo -e "${BLD}${GRN}╔══════════════════════════════════════════════════════╗${RST}"
echo -e "${BLD}${GRN}║   Diyar OS ISO build complete!                       ║${RST}"
echo -e "${BLD}${GRN}╠══════════════════════════════════════════════════════╣${RST}"
echo -e "${BLD}${GRN}║${RST}  ISO    : ${ISO_FILE}  (${ISO_SIZE})           ${BLD}${GRN}║${RST}"
echo -e "${BLD}${GRN}║${RST}  Time   : ${BUILD_TIME}s                                   ${BLD}${GRN}║${RST}"
echo -e "${BLD}${GRN}║${RST}                                                      ${BLD}${GRN}║${RST}"
echo -e "${BLD}${GRN}║${RST}  Test:  qemu-system-x86_64 -cdrom ${ISO_FILE} -m 2G  ${BLD}${GRN}║${RST}"
echo -e "${BLD}${GRN}║${RST}  Write: dd if=${ISO_FILE} of=/dev/sdX bs=4M status=progress ${BLD}${GRN}║${RST}"
echo -e "${BLD}${GRN}╚══════════════════════════════════════════════════════╝${RST}"
