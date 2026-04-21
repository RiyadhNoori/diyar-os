#!/usr/bin/env bash
# =============================================================================
# Diyar OS Installer — Core Engine
# engine.sh
#
# The rsync-based installation engine.
# Pattern: proven by refractainstaller, AntiX, Devuan live installers.
#
# Flow:
#   1. Detect live source root
#   2. Partition target disk (optional — can use pre-partitioned)
#   3. Format partitions
#   4. rsync live → /target
#   5. chroot: locale, hostname, user, fstab (UUID-based), grub
#   6. Clean up live artefacts
#   7. Unmount and signal completion
#
# Called by: ui/diyar-installer (main UI wrapper)
# Exports:   DIYAR_PROGRESS (0-100), DIYAR_STATUS (string)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Source shared config and i18n
# ---------------------------------------------------------------------------
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${INSTALLER_DIR}/conf/installer.conf"
source "${INSTALLER_DIR}/core/log.sh"
source "${INSTALLER_DIR}/core/disk.sh"
source "${INSTALLER_DIR}/core/chroot_setup.sh"

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
TARGET="/target"
LIVE_ROOT=""
DIYAR_PROGRESS=0
DIYAR_STATUS=""
LOG_FILE="/var/log/diyar-installer.log"

# ---------------------------------------------------------------------------
# Progress reporting (writes to named pipe read by UI)
# ---------------------------------------------------------------------------
PROGRESS_PIPE="${INSTALLER_RUNTIME_DIR}/progress.pipe"

progress() {
    local pct="$1"; shift
    local msg="$*"
    DIYAR_PROGRESS="$pct"
    DIYAR_STATUS="$msg"
    log_info "[${pct}%] ${msg}"
    if [[ -p "$PROGRESS_PIPE" ]]; then
        echo "${pct}|${msg}" > "$PROGRESS_PIPE" || true
    fi
}

# ---------------------------------------------------------------------------
# Detect live source root
# ---------------------------------------------------------------------------
detect_live_root() {
    progress 2 "Detecting live filesystem..."

    # Standard live-boot mount points (Debian live-build)
    local candidates=(
        "/run/live/rootfs/filesystem.squashfs"
        "/run/live/medium/live/filesystem.squashfs"
        "/lib/live/mount/rootfs/filesystem.squashfs"
        "/"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate" ]] || [[ "$candidate" == "/" ]]; then
            LIVE_ROOT="$candidate"
            log_info "Live root detected: ${LIVE_ROOT}"
            return 0
        fi
    done

    # Fallback: use running root
    LIVE_ROOT="/"
    log_warn "Could not detect squashfs mount, using / as source."
}

# ---------------------------------------------------------------------------
# Validate inputs from UI
# ---------------------------------------------------------------------------
validate_inputs() {
    progress 4 "Validating configuration..."

    [[ -z "${TARGET_DISK:-}"    ]] && die "TARGET_DISK not set"
    [[ -z "${TARGET_PART_ROOT:-}" ]] && die "TARGET_PART_ROOT not set"
    [[ -z "${DIYAR_HOSTNAME:-}"  ]] && die "DIYAR_HOSTNAME not set"
    [[ -z "${DIYAR_USERNAME:-}"  ]] && die "DIYAR_USERNAME not set"
    [[ -z "${DIYAR_PASSWORD:-}"  ]] && die "DIYAR_PASSWORD not set"
    [[ -z "${DIYAR_LOCALE:-}"    ]] && DIYAR_LOCALE="ar_IQ.UTF-8"
    [[ -z "${DIYAR_TIMEZONE:-}"  ]] && DIYAR_TIMEZONE="Asia/Baghdad"

    # Verify disk exists
    [[ -b "${TARGET_DISK}" ]] || die "Disk not found: ${TARGET_DISK}"

    log_info "Config validated. Target: ${TARGET_DISK}, Root: ${TARGET_PART_ROOT}"
}

# ---------------------------------------------------------------------------
# Partition the disk
# Mode: auto (wipe+partition) or manual (pre-partitioned by user)
# ---------------------------------------------------------------------------
partition_disk() {
    if [[ "${PARTITION_MODE:-auto}" == "manual" ]]; then
        progress 8 "Using existing partitions (manual mode)..."
        log_info "Skipping partitioning — manual mode."
        return 0
    fi

    progress 6 "Partitioning ${TARGET_DISK}..."
    log_info "Partition mode: ${PARTITION_MODE}"

    # Detect firmware type
    if [[ -d /sys/firmware/efi ]]; then
        FIRMWARE_TYPE="uefi"
        log_info "UEFI firmware detected."
    else
        FIRMWARE_TYPE="bios"
        log_info "BIOS/Legacy firmware detected."
    fi

    # Wipe existing partition table
    wipefs -a "${TARGET_DISK}" >> "$LOG_FILE" 2>&1

    if [[ "$FIRMWARE_TYPE" == "uefi" ]]; then
        # GPT + EFI partition
        parted -s "${TARGET_DISK}" \
            mklabel gpt \
            mkpart ESP fat32 1MiB 513MiB \
            set 1 esp on \
            mkpart primary ext4 513MiB 100% \
            >> "$LOG_FILE" 2>&1

        # Resolve partition names (handles nvme0n1p1 vs sda1)
        TARGET_PART_EFI="$(disk_part "${TARGET_DISK}" 1)"
        TARGET_PART_ROOT="$(disk_part "${TARGET_DISK}" 2)"
        FIRMWARE_TYPE="uefi"
    else
        # MBR + single root
        parted -s "${TARGET_DISK}" \
            mklabel msdos \
            mkpart primary ext4 1MiB 100% \
            set 1 boot on \
            >> "$LOG_FILE" 2>&1

        TARGET_PART_ROOT="$(disk_part "${TARGET_DISK}" 1)"
        FIRMWARE_TYPE="bios"
    fi

    log_info "Partitioned: root=${TARGET_PART_ROOT} firmware=${FIRMWARE_TYPE}"
    progress 10 "Partitioning complete."
}

# ---------------------------------------------------------------------------
# Format partitions
# ---------------------------------------------------------------------------
format_partitions() {
    progress 12 "Formatting partitions..."

    # Format root as ext4
    log_info "Formatting root: ${TARGET_PART_ROOT}"
    mkfs.ext4 -F -L "diyar-root" "${TARGET_PART_ROOT}" >> "$LOG_FILE" 2>&1

    # Format EFI if UEFI
    if [[ "${FIRMWARE_TYPE:-bios}" == "uefi" ]]; then
        log_info "Formatting EFI: ${TARGET_PART_EFI}"
        mkfs.fat -F32 -n "DIYAR-EFI" "${TARGET_PART_EFI}" >> "$LOG_FILE" 2>&1
    fi

    # Format swap if requested
    if [[ -n "${TARGET_PART_SWAP:-}" ]]; then
        log_info "Formatting swap: ${TARGET_PART_SWAP}"
        mkswap -L "diyar-swap" "${TARGET_PART_SWAP}" >> "$LOG_FILE" 2>&1
    fi

    progress 14 "Formatting complete."
}

# ---------------------------------------------------------------------------
# Mount target
# ---------------------------------------------------------------------------
mount_target() {
    progress 16 "Mounting target filesystem..."

    mkdir -p "${TARGET}"
    mount "${TARGET_PART_ROOT}" "${TARGET}" || die "Cannot mount ${TARGET_PART_ROOT}"

    if [[ "${FIRMWARE_TYPE:-bios}" == "uefi" ]]; then
        mkdir -p "${TARGET}/boot/efi"
        mount "${TARGET_PART_EFI}" "${TARGET}/boot/efi" \
            || die "Cannot mount EFI partition"
    fi

    log_info "Target mounted at ${TARGET}"
    progress 18 "Target mounted."
}

# ---------------------------------------------------------------------------
# THE CORE: rsync live system → target
# This is why it works where Calamares/GTK3 fail:
#   - copies the exact running system
#   - preserves all attributes, symlinks, permissions
#   - excludes live-specific artefacts
# ---------------------------------------------------------------------------
rsync_system() {
    progress 20 "Copying system to disk (this takes a few minutes)..."
    log_info "Starting rsync: ${LIVE_ROOT} → ${TARGET}"

    local RSYNC_EXCLUDES=(
        --exclude="/proc/*"
        --exclude="/sys/*"
        --exclude="/dev/*"
        --exclude="/run/*"
        --exclude="/tmp/*"
        --exclude="/mnt/*"
        --exclude="/media/*"
        --exclude="/lost+found"
        # Live-specific exclusions
        --exclude="/etc/live/*"
        --exclude="/lib/live/*"
        --exclude="/run/live/*"
        --exclude="/etc/hostname.live"
        --exclude="/etc/hosts.live"
        # Diyar installer itself (not needed on installed system)
        --exclude="/opt/diyar-installer/*"
        --exclude="/usr/local/sbin/diyar-installer"
        # Machine-specific live state
        --exclude="/etc/machine-id"
        --exclude="/var/lib/dbus/machine-id"
        --exclude="/etc/udev/rules.d/70-persistent-net.rules"
    )

    rsync \
        -aAXHv \
        --delete \
        --progress \
        "${RSYNC_EXCLUDES[@]}" \
        "${LIVE_ROOT}/" \
        "${TARGET}/" \
        2>&1 | while IFS= read -r line; do
            # Parse rsync output to drive progress bar (20% → 75%)
            if [[ "$line" =~ ^[[:space:]]*([0-9,]+)[[:space:]]+([0-9]+)% ]]; then
                local pct="${BASH_REMATCH[2]}"
                local mapped=$(( 20 + (pct * 55 / 100) ))
                progress "$mapped" "Copying system... ${pct}%"
            fi
            echo "$line" >> "$LOG_FILE"
        done

    progress 76 "File copy complete."
    log_info "rsync finished successfully."
}

# ---------------------------------------------------------------------------
# Bind-mount /proc /sys /dev for chroot operations
# ---------------------------------------------------------------------------
bind_mount_pseudo() {
    log_info "Binding pseudo-filesystems..."
    mount --bind /proc  "${TARGET}/proc"
    mount --bind /sys   "${TARGET}/sys"
    mount --bind /dev   "${TARGET}/dev"
    mount --bind /dev/pts "${TARGET}/dev/pts"
    # Network access inside chroot (for grub-install)
    cp /etc/resolv.conf "${TARGET}/etc/resolv.conf" 2>/dev/null || true
}

unbind_pseudo() {
    log_info "Unbinding pseudo-filesystems..."
    for dir in dev/pts dev proc sys; do
        umount -lf "${TARGET}/${dir}" 2>/dev/null || true
    done
}

# ---------------------------------------------------------------------------
# Full chroot setup (delegates to chroot_setup.sh)
# ---------------------------------------------------------------------------
run_chroot_setup() {
    progress 78 "Configuring installed system..."
    bind_mount_pseudo
    trap 'unbind_pseudo' EXIT

    # Generate fresh machine-id
    progress 79 "Generating machine ID..."
    rm -f "${TARGET}/etc/machine-id"
    chroot "${TARGET}" systemd-machine-id-setup 2>/dev/null \
        || dbus-uuidgen > "${TARGET}/etc/machine-id"
    cp "${TARGET}/etc/machine-id" "${TARGET}/var/lib/dbus/machine-id" 2>/dev/null || true

    # Hostname
    progress 80 "Setting hostname..."
    chroot_set_hostname "${DIYAR_HOSTNAME}"

    # Locale
    progress 82 "Configuring locale..."
    chroot_set_locale "${DIYAR_LOCALE}"

    # Timezone
    progress 83 "Setting timezone..."
    chroot_set_timezone "${DIYAR_TIMEZONE}"

    # fstab with UUIDs
    progress 84 "Writing fstab..."
    chroot_write_fstab

    # User account
    progress 86 "Creating user account..."
    chroot_create_user "${DIYAR_USERNAME}" "${DIYAR_PASSWORD}" "${DIYAR_FULLNAME:-}"

    # Remove live-boot packages
    progress 88 "Removing live-boot packages..."
    chroot_remove_live_packages

    # Install GRUB bootloader
    progress 90 "Installing GRUB bootloader..."
    chroot_install_grub

    progress 96 "Chroot configuration complete."
}

# ---------------------------------------------------------------------------
# Final cleanup
# ---------------------------------------------------------------------------
final_cleanup() {
    progress 97 "Cleaning up..."

    # Remove installer desktop shortcut from installed system
    rm -f "${TARGET}/home/${DIYAR_USERNAME}/Desktop/diyar-install.desktop" 2>/dev/null || true
    rm -f "${TARGET}/root/Desktop/diyar-install.desktop" 2>/dev/null || true

    # Truncate logs (don't ship live-session logs)
    : > "${TARGET}/var/log/diyar-installer.log" 2>/dev/null || true

    unbind_pseudo
    trap - EXIT

    # Unmount EFI first (child mount)
    if [[ "${FIRMWARE_TYPE:-bios}" == "uefi" ]]; then
        umount "${TARGET}/boot/efi" 2>/dev/null || true
    fi

    sync
    umount "${TARGET}" 2>/dev/null || true

    progress 100 "Installation complete. You can now reboot."
    log_info "=== Diyar OS installation finished successfully ==="
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    log_info "=== Diyar OS Installer Engine starting ==="
    log_info "Version: ${DIYAR_INSTALLER_VERSION:-1.0.0}"
    log_info "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

    detect_live_root
    validate_inputs
    partition_disk
    format_partitions
    mount_target
    rsync_system
    run_chroot_setup
    final_cleanup
}

main "$@"
