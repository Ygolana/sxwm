#!/usr/bin/env bash
set -euo pipefail

# ── privilege escalation ────────────────────────────────────────────────
if command -v sudo >/dev/null 2>&1; then
    ROOT=sudo
elif command -v doas >/dev/null 2>&1; then
    ROOT=doas
else
    echo "error: neither sudo nor doas found" >&2
    exit 1
fi

# ── package installation ────────────────────────────────────────────────
$ROOT xbps-install -S
$ROOT xbps-install -y \
    gcc make pkg-config git meson ninja \
    libX11-devel libXinerama-devel libXcursor-devel libXext-devel libXi-devel \
    fontconfig-devel \
    xorg-minimal xinit xauth xf86-input-libinput xf86-video-vesa \
    terminus-font \
    pipewire wireplumber \
    brightnessctl

# ── enable audio services (runit) ──────────────────────────────────────
$ROOT ln -sf /etc/sv/pipewire      /var/service/
$ROOT ln -sf /etc/sv/wireplumber   /var/service/

# ── brightness permission ──────────────────────────────────────────────
$ROOT usermod -aG video "$USER"

# ── build & install sxwm ───────────────────────────────────────────────
git clone --depth 1 https://github.com/uint23/sxwm /tmp/sxwm
cd /tmp/sxwm
make
$ROOT make install

# ── build & install sxbar ──────────────────────────────────────────────
git clone --depth 1 https://github.com/uint23/sxbar /tmp/sxbar
cd /tmp/sxbar
make
$ROOT make install

# ── build & install cterm ──────────────────────────────────────────────
git clone --depth 1 https://github.com/uint23/cterm /tmp/cterm
cd /tmp/cterm
meson setup build
meson compile -C build
$ROOT meson install -C build

# ── configuration files ────────────────────────────────────────────────
mkdir -p "$HOME/.config/sxwm" "$HOME/.config/sxbar" "$HOME/.config/cterm"

cat > "$HOME/.config/sxwm/sxwmrc" <<'EOF'
# minimal sxwmrc
focused_border_colour   : #717394
unfocused_border_colour : #444444
border_width            : 1
gaps                    : 0
master_width            : 60
mod_key                 : super

bind : mod + Return : "cterm"
bind : mod + b      : "firefox"
bind : mod + q      : "sxwm-msg close_window"
bind : mod + shift+q: "sxwm-msg quit"
bind : mod + j      : "sxwm-msg focus_next"
bind : mod + k      : "sxwm-msg focus_prev"
bind : mod + h      : "sxwm-msg master_decrease"
bind : mod + l      : "sxwm-msg master_increase"
bind : mod + space  : "sxwm-msg toggle_floating"
bind : mod + f      : "sxwm-msg fullscreen"

workspace : mod + 1 : move 1
workspace : mod + 2 : move 2
workspace : mod + 3 : move 3
workspace : mod + 4 : move 4
workspace : mod + 5 : move 5
workspace : mod + 6 : move 6
workspace : mod + 7 : move 7
workspace : mod + 8 : move 8
workspace : mod + 9 : move 9
EOF

cat > "$HOME/.config/sxbar/sxbarc" <<'EOF'
bar_position        : top
height              : 20
background_colour   : #171717
foreground_colour   : #fffde0
font                : Terminus
font_size           : 12

module.0.name       : clock
module.0.cmd        : date '+%H:%M'
module.0.interval   : 1

module.1.name       : volume
module.1.cmd        : wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "vol: %s", $2}'
module.1.interval   : 1

module.2.name       : cpu
module.2.cmd        : top -bn1 | awk '/Cpu\(s\)/ {printf "cpu: %.0f%%", $2+$4}'
module.2.interval   : 3
EOF

cat > "$HOME/.config/cterm/config" <<'EOF'
font: /usr/share/fonts/misc/ter-u12n.bdf
foreground: #fffde0
background: #171717
polling_rate: 100
EOF

# ── X session autostart ────────────────────────────────────────────────
cat > "$HOME/.xinitrc" <<'EOF'
#!/bin/sh
sxbar &
exec sxwm
EOF
chmod +x "$HOME/.xinitrc"

# ── reboot ─────────────────────────────────────────────────────────────
$ROOT reboot
