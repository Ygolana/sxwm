#!/bin/bash
set -euo pipefail

# ----------------------------------------------------------------------
# Privilege escalation
# ----------------------------------------------------------------------
if command -v sudo >/dev/null 2>&1; then
    PRIV="sudo"
elif command -v doas >/dev/null 2>&1; then
    PRIV="doas"
else
    echo "Error: neither sudo nor doas found." >&2
    exit 1
fi

# ----------------------------------------------------------------------
# Package groups
# ----------------------------------------------------------------------
BUILD_DEPS="gcc make meson ninja pkg-config git"
SXWM_DEPS="libX11-devel libXinerama-devel libXcursor-devel"
SXBAR_DEPS="libX11-devel libXinerama-devel libXft-devel fontconfig-devel freetype-devel"
CTERM_DEPS="libX11-devel libXext-devel libXi-devel"
XORG_PKGS="xorg-minimal xinit xf86-video-intel xf86-input-libinput font-misc-misc"
AUDIO_PKGS="pipewire wireplumber dbus"
UTIL_PKGS="brightnessctl dmenu"

FALLBACK_MIRROR="https://mirrors.servercentral.com/voidlinux"

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
change_mirror() {
    local mirror="${1:-$FALLBACK_MIRROR}"
    echo "==> Switching Void Linux mirror to: $mirror" >&2
    $PRIV mkdir -p /etc/xbps.d
    for f in /usr/share/xbps.d/*-repository-*.conf; do
        [ -e "$f" ] || continue
        local base
        base=$(basename "$f")
        [ -f "/etc/xbps.d/$base" ] || $PRIV cp "$f" "/etc/xbps.d/$base"
    done
    $PRIV sed -i -E "s|repository=https://[^/]+(/current.*)|repository=$mirror\1|" /etc/xbps.d/*-repository-*.conf
    $PRIV xbps-install -S
}

install_pkgs() {
    $PRIV rm -rf /var/cache/xbps/*

    if $PRIV xbps-install -Suv && $PRIV xbps-install -Sy "$@"; then
        return 0
    fi

    echo "==> Package operation failed. Attempting mirror switch..." >&2
    change_mirror

    $PRIV rm -rf /var/cache/xbps/*
    $PRIV xbps-install -Suv
    $PRIV xbps-install -Sy "$@"
}

cleanup() {
    rm -rf /tmp/sxwm /tmp/sxbar /tmp/cterm /tmp/spleen /tmp/libgrapheme
}
trap cleanup EXIT

# ----------------------------------------------------------------------
# Install system packages
# ----------------------------------------------------------------------
install_pkgs $BUILD_DEPS $SXWM_DEPS $SXBAR_DEPS $CTERM_DEPS $XORG_PKGS $AUDIO_PKGS $UTIL_PKGS

# ----------------------------------------------------------------------
# Build and install libgrapheme (required by cterm)
# ----------------------------------------------------------------------
if ! pkg-config --exists libgrapheme; then
    git clone --depth=1 https://github.com/FRIGN/libgrapheme.git /tmp/libgrapheme
    cd /tmp/libgrapheme
    make
    $PRIV make PREFIX=/usr install
    cd /
fi

# ----------------------------------------------------------------------
# Build and install sxwm
# ----------------------------------------------------------------------
if ! command -v sxwm >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/uint23/sxwm.git /tmp/sxwm
    cd /tmp/sxwm
    make
    $PRIV make install
    cd /
fi

# ----------------------------------------------------------------------
# Build and install sxbar
# ----------------------------------------------------------------------
if ! command -v sxbar >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/uint23/sxbar.git /tmp/sxbar
    cd /tmp/sxbar
    make
    $PRIV make install
    cd /
fi

# ----------------------------------------------------------------------
# Build and install cterm
# ----------------------------------------------------------------------
if ! command -v cterm >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/uint23/cterm.git /tmp/cterm
    cd /tmp/cterm
    meson setup build --prefix=/usr
    meson compile -C build
    $PRIV meson install -C build
    cd /
fi

# ----------------------------------------------------------------------
# Install Spleen 5x8 BDF font (for cterm)
# ----------------------------------------------------------------------
if [ ! -f "$HOME/.local/share/fonts/spleen-5x8.bdf" ]; then
    git clone --depth=1 https://github.com/fcambus/spleen.git /tmp/spleen
    mkdir -p "$HOME/.local/share/fonts"
    cp /tmp/spleen/spleen-5x8.bdf "$HOME/.local/share/fonts/"
    fc-cache -f "$HOME/.local/share/fonts"
fi

# ----------------------------------------------------------------------
# Enable D-Bus system service (PipeWire/WirePlumber start in session)
# ----------------------------------------------------------------------
$PRIV ln -sf /etc/sv/dbus /var/service/

# ----------------------------------------------------------------------
# Configuration files (written only if missing)
# ----------------------------------------------------------------------
CONFIG_DIR="$HOME/.config"
mkdir -p "$CONFIG_DIR/sxwm" "$CONFIG_DIR/sxbar" "$CONFIG_DIR/cterm"

# sxwm
if [ ! -f "$CONFIG_DIR/sxwm/sxwmrc" ]; then
    cat > "$CONFIG_DIR/sxwm/sxwmrc" <<'EOF'
mod_key: super

bind: mod + Return : "cterm"
bind: mod + d : "dmenu_run"

call: mod + shift + q : close_window
call: mod + shift + e : quit
call: mod + r : reload_config

# workspace navigation
workspace: mod + 1 : move 1
workspace: mod + 2 : move 2
workspace: mod + 3 : move 3
workspace: mod + 4 : move 4
workspace: mod + 5 : move 5
workspace: mod + 6 : move 6
workspace: mod + 7 : move 7
workspace: mod + 8 : move 8
workspace: mod + 9 : move 9

# move focused window to workspace
workspace: mod + shift + 1 : swap 1
workspace: mod + shift + 2 : swap 2
workspace: mod + shift + 3 : swap 3
workspace: mod + shift + 4 : swap 4
workspace: mod + shift + 5 : swap 5
workspace: mod + shift + 6 : swap 6
workspace: mod + shift + 7 : swap 7
workspace: mod + shift + 8 : swap 8
workspace: mod + shift + 9 : swap 9

call: mod + j : focus_next
call: mod + k : focus_prev

call: mod + l : master_increase
call: mod + h : master_decrease
call: mod + space : toggle_floating
call: mod + shift + f : fullscreen

bind: XF86AudioRaiseVolume : "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
bind: XF86AudioLowerVolume : "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
bind: XF86AudioMute : "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"

bind: XF86MonBrightnessUp : "brightnessctl set 5%+"
bind: XF86MonBrightnessDown : "brightnessctl set 5%-"
EOF
fi

# sxbar
if [ ! -f "$CONFIG_DIR/sxbar/sxbarc" ]; then
    cat > "$CONFIG_DIR/sxbar/sxbarc" <<'EOF'
bar_position: top
height: 24
background_colour: #171717
foreground_colour: #fffde0
font: fixed

# left: workspaces (only active, roman numerals)
workspaces.labels: I II III IV V VI VII VIII IX
workspaces.only_active: true
workspaces.position: left
workspaces.active_background: #717394
workspaces.active_foreground: #fffde0
workspaces.inactive_background: #171717
workspaces.inactive_foreground: #fffde0
workspaces.padding_left: 10
workspaces.padding_right: 10
workspaces.spacing: 0

# middle: time and date
module.0.name: clock
module.0.cmd: date '+%H:%M:%S'
module.0.interval: 1
module.0.position: middle

module.1.name: date
module.1.cmd: date '+%Y-%m-%d'
module.1.interval: 60
module.1.position: middle

# right: network, audio, battery
module.2.name: net
module.2.cmd: ping -c1 -W1 1.1.1.1 >/dev/null && echo "Online" || echo "Offline"
module.2.interval: 30
module.2.position: right

module.3.name: vol
module.3.cmd: wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2*100)"%"}'
module.3.interval: 1
module.3.position: right

module.4.name: bat
module.4.cmd: cat /sys/class/power_supply/BAT0/capacity 2>/dev/null | sed 's/$/%/' || echo 'N/A'
module.4.interval: 30
module.4.position: right
EOF
fi

# cterm
if [ ! -f "$CONFIG_DIR/cterm/cterm.conf" ]; then
    cat > "$CONFIG_DIR/cterm/cterm.conf" <<EOF
font_path = $HOME/.local/share/fonts/spleen-5x8.bdf
EOF
fi

# ----------------------------------------------------------------------
# X session autostart (PipeWire, WirePlumber, wallpaper, bar, WM)
# ----------------------------------------------------------------------
if [ ! -f "$HOME/.xinitrc" ]; then
    cat > "$HOME/.xinitrc" <<'EOF'
#!/bin/sh
exec dbus-run-session -- sh -c '
  pipewire &
  wireplumber &
  xsetroot -solid "#171717" &
  sxbar &
  exec sxwm
'
EOF
    chmod +x "$HOME/.xinitrc"
fi

# ----------------------------------------------------------------------
# Remove build-time packages
# ----------------------------------------------------------------------
$PRIV xbps-remove -Ry $BUILD_DEPS $SXWM_DEPS $SXBAR_DEPS $CTERM_DEPS

# ----------------------------------------------------------------------
# Reboot
# ----------------------------------------------------------------------
reboot
