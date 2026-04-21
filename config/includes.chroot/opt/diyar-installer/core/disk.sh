#!/usr/bin/env bash
# =============================================================================
# Diyar OS Installer — Disk Utilities
# core/disk.sh  —  sourced by engine.sh
# =============================================================================

# ---------------------------------------------------------------------------
# Resolve partition name for a given disk and partition number.
# Handles: /dev/sda → sda1, /dev/nvme0n1 → nvme0n1p1, /dev/mmcblk0 → mmcblk0p1
# ---------------------------------------------------------------------------
disk_part() {
    local disk="$1"
    local num="$2"
    case "$disk" in
        *nvme*|*mmcblk*)
            echo "${disk}p${num}"
            ;;
        *)
            echo "${disk}${num}"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Get UUID of a partition (waits up to 5s for udev to settle)
# ---------------------------------------------------------------------------
get_uuid() {
    local part="$1"
    local uuid=""
    local retries=10

    # Give udev time to register new partitions after mkfs
    udevadm settle --timeout=5 2>/dev/null || true

    for (( i=0; i<retries; i++ )); do
        uuid="$(blkid -s UUID -o value "${part}" 2>/dev/null || true)"
        [[ -n "$uuid" ]] && echo "$uuid" && return 0
        sleep 0.5
    done

    # Fallback: try lsblk
    uuid="$(lsblk -no UUID "${part}" 2>/dev/null | head -1 || true)"
    [[ -n "$uuid" ]] && echo "$uuid" && return 0

    die "Could not get UUID for ${part}"
}

# ---------------------------------------------------------------------------
# Get filesystem type of a partition
# ---------------------------------------------------------------------------
get_fstype() {
    local part="$1"
    blkid -s TYPE -o value "${part}" 2>/dev/null || echo "ext4"
}

# ---------------------------------------------------------------------------
# List available block devices (disks only, not partitions/loops)
# Returns: list of /dev/sdX, /dev/nvmeXnY, /dev/mmcblkX paths
# ---------------------------------------------------------------------------
list_disks() {
    lsblk -dpno NAME,SIZE,MODEL \
        --include 8,259,179 \
        2>/dev/null \
    | grep -v "^loop" \
    | awk '{print $1, $2, substr($0, index($0,$3))}'
}

# ---------------------------------------------------------------------------
# Human-readable disk size
# ---------------------------------------------------------------------------
disk_size_human() {
    local disk="$1"
    lsblk -dno SIZE "${disk}" 2>/dev/null || echo "?"
}

# ---------------------------------------------------------------------------
# Check if disk has enough space (in GiB)
# ---------------------------------------------------------------------------
disk_has_space() {
    local disk="$1"
    local required_gib="${2:-8}"

    local bytes
    bytes="$(lsblk -dno SIZE --bytes "${disk}" 2>/dev/null || echo 0)"
    local required_bytes=$(( required_gib * 1024 * 1024 * 1024 ))

    (( bytes >= required_bytes ))
}

# ---------------------------------------------------------------------------
# Estimate required space from live system
# ---------------------------------------------------------------------------
live_system_size_gib() {
    local live_root="${1:-/}"
    local used_kb
    used_kb="$(du -sx --exclude=/proc --exclude=/sys --exclude=/dev \
               --exclude=/run --exclude=/tmp \
               "${live_root}" 2>/dev/null | cut -f1 || echo 5242880)"
    # Add 20% headroom
    echo $(( (used_kb * 12) / (10 * 1024 * 1024) + 1 ))
}
