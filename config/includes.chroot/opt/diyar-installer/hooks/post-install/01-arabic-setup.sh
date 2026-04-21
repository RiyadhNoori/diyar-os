#!/usr/bin/env bash
# =============================================================================
# Diyar OS — Post-Install Hook: Arabic Environment
# hooks/post-install/01-arabic-setup.sh
#
# Runs inside chroot after rsync, before grub-install.
# Configures Arabic keyboard, IBus, fontconfig, GTK RTL.
# =============================================================================

set -euo pipefail

TARGET="${TARGET:-/target}"

log_info() { echo "[POST] $*"; }

# ---------------------------------------------------------------------------
# Keyboard layout — Arabic + English toggle
# ---------------------------------------------------------------------------
setup_keyboard() {
    log_info "Configuring keyboard layout..."
    cat > "${TARGET}/etc/default/keyboard" <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="ara,us"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle,grp_led:scroll"
BACKSPACE="guess"
EOF
}

# ---------------------------------------------------------------------------
# IBus input method
# ---------------------------------------------------------------------------
setup_ibus() {
    log_info "Configuring IBus for Arabic input..."

    local ibus_conf="${TARGET}/etc/profile.d/diyar-ibus.sh"
    cat > "$ibus_conf" <<'EOF'
# Diyar OS — IBus Arabic input method
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
EOF
    chmod 644 "$ibus_conf"
}

# ---------------------------------------------------------------------------
# Fontconfig — Vazirmatn primary, full Arabic stack
# (Uses the config from configs/fontconfig/local.conf)
# ---------------------------------------------------------------------------
setup_fontconfig() {
    log_info "Configuring fontconfig for Arabic rendering..."
    mkdir -p "${TARGET}/etc/fonts/conf.d"
    # The local.conf was already deployed by build_arface.sh / rsync
    # Just ensure the priority symlink exists
    local conf_src="${TARGET}/etc/fonts/conf.avail/99-diyar-arabic.conf"
    local conf_dst="${TARGET}/etc/fonts/conf.d/99-diyar-arabic.conf"

    if [[ -f "$conf_src" ]] && [[ ! -f "$conf_dst" ]]; then
        ln -sf "$conf_src" "$conf_dst"
    fi
}

# ---------------------------------------------------------------------------
# GRUB — Arabic-friendly theme config
# ---------------------------------------------------------------------------
setup_grub_defaults() {
    log_info "Configuring GRUB defaults..."
    cat > "${TARGET}/etc/default/grub" <<'EOF'
# Diyar OS GRUB configuration
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Diyar OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""

# Graphics
GRUB_GFXMODE=1920x1080,1280x720,auto
GRUB_GFXPAYLOAD_LINUX=keep

# Disable OS prober (speeds up boot, re-enable for dual-boot)
# GRUB_DISABLE_OS_PROBER=false
EOF
}

# ---------------------------------------------------------------------------
# LightDM autologin (optional, disabled by default)
# ---------------------------------------------------------------------------
setup_lightdm() {
    log_info "Configuring LightDM..."
    local ldm_conf="${TARGET}/etc/lightdm/lightdm.conf.d/50-diyar.conf"
    mkdir -p "$(dirname "$ldm_conf")"
    cat > "$ldm_conf" <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
# user-session=xfce
# autologin-user=${DIYAR_USERNAME:-user}
# autologin-user-timeout=0
EOF
}

# ---------------------------------------------------------------------------
# LightDM greeter — Arabic-themed
# ---------------------------------------------------------------------------
setup_lightdm_greeter() {
    log_info "Configuring LightDM GTK greeter..."
    local greeter_conf="${TARGET}/etc/lightdm/lightdm-gtk-greeter.conf"
    cat > "$greeter_conf" <<'EOF'
[greeter]
background=/usr/share/diyar-os/wallpapers/diyar-login.jpg
theme-name=Adwaita-dark
icon-theme-name=Papirus-Dark
font-name=Vazirmatn 11
xft-antialias=true
xft-hintstyle=slight
xft-rgba=rgb
indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power
clock-format=%H:%M  —  %A %d %B %Y
EOF
}

# ---------------------------------------------------------------------------
# Run all hooks
# ---------------------------------------------------------------------------
main() {
    log_info "=== Diyar post-install Arabic setup starting ==="
    setup_keyboard
    setup_ibus
    setup_fontconfig
    setup_grub_defaults
    setup_lightdm
    setup_lightdm_greeter
    log_info "=== Arabic setup complete ==="
}

main "$@"
