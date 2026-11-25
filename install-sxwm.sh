#!/bin/bash
set -euo pipefail

# --- Privilege helper ---
if command -v doas >/dev/null 2>&1; then PRIV=doas
elif command -v sudo >/dev/null 2>&1; then PRIV=sudo
else echo "ERROR: install doas or sudo first." >&2; exit 1
fi

# --- Packages ---
PKGS="
gcc make meson ninja pkg-config
libX11-devel libXinerama-devel libXcursor-devel
libXft-devel libXext-devel libXi-devel
fontconfig-devel freetype-devel
xorg-server xinit xauth xf86-input-libinput
pipewire wireplumber
brightnessctl terminus-font
dmenu dbus
"
echo "==> Installing packages..."
$PRIV xbps-install -Syu $PKGS

# --- PipeWire / WirePlumber / D-Bus ---
$PRIV mkdir -p /etc/pipewire/pipewire.conf.d
$PRIV ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf \
    /etc/pipewire/pipewire.conf.d/10-wireplumber.conf
$PRIV ln -sf /etc/sv/dbus /var/service/

# --- Build & install ---
BUILD="$HOME/.cache/sx-build"
mkdir -p "$BUILD"
cd "$BUILD"

echo "==> sxwm"
rm -rf sxwm && git clone --depth=1 https://github.com/uint23/sxwm.git
( cd sxwm && make && $PRIV make PREFIX=/usr install )

echo "==> sxbar"
rm -rf sxbar && git clone --depth=1 https://github.com/uint23/sxbar.git
( cd sxbar && make && $PRIV make PREFIX=/usr install )

echo "==> cterm"
rm -rf cterm && git clone --depth=1 https://github.com/uint23/cterm.git
( cd cterm && meson setup build --prefix=/usr && ninja -C build \
    && $PRIV ninja -C build install )

# --- Configs ---
mkdir -p "$HOME/.config/sxbar"

cat > "$HOME/.config/sxwmrc" <<'EOF'
# appearance
mod_key                  : super
border_width             : 2
gaps                     : 0
master_width             : 60
focused_border_colour    : #717394
unfocused_border_colour  : #444444
swap_border_colour       : #eeeeee

# launchers
bind : mod + Return        : "cterm"
bind : mod + p             : "dmenu_run"

# media keys
bind : XF86AudioRaiseVolume : "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+"
bind : XF86AudioLowerVolume : "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"
bind : XF86AudioMute        : "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"

# window control
call : mod + shift + q  : close_window
call : mod + shift + e  : quit
call : mod + r          : reload_config

# focus
call : mod + j : focus_next
call : mod + k : focus_prev

# master / stack
call : mod + h         : master_decrease
call : mod + l         : master_increase
call : mod + shift + h : stack_decrease
call : mod + shift + l : stack_increase

# floating / fullscreen
call : mod + space      : toggle_floating
call : mod + shift + f  : fullscreen

# workspaces 1–9
workspace : mod + 1         : move 1
workspace : mod + 2         : move 2
workspace : mod + 3         : move 3
workspace : mod + 4         : move 4
workspace : mod + 5         : move 5
workspace : mod + 6         : move 6
workspace : mod + 7         : move 7
workspace : mod + 8         : move 8
workspace : mod + 9         : move 9
workspace : mod + shift + 1 : swap 1
workspace : mod + shift + 2 : swap 2
workspace : mod + shift + 3 : swap 3
workspace : mod + shift + 4 : swap 4
workspace : mod + shift + 5 : swap 5
workspace : mod + shift + 6 : swap 6
workspace : mod + shift + 7 : swap 7
workspace : mod + shift + 8 : swap 8
workspace : mod + shift + 9 : swap 9
EOF

cat > "$HOME/.config/sxbar/sxbarc" <<'EOF'
# bar
bar_position        : top
height              : 24
vertical_padding    : 0
horizontal_padding  : 0
text_padding        : 0
border              : false
background_colour   : #171717
foreground_colour   : #fffde0
border_colour       : #717394
font                : Terminus
font_size           : 14

# clock
module.0.name       : clock
module.0.cmd        : date '+%H:%M:%S'
module.0.enabled    : true
module.0.interval   : 1

# volume
module.1.name       : volume
module.1.cmd        : wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "v: %d%%", $2*100}'
module.1.enabled    : true
module.1.interval   : 1

# cpu
module.2.name       : cpu
module.2.cmd        : top -bn1 | grep "Cpu(s)" | awk '{print "cpu: " 100-$8 "%"}'
module.2.enabled    : true
module.2.interval   : 3

# workspaces
workspaces.labels              : @ ? ; % & $ ! ~ *
workspaces.active_background   : #717394
workspaces.active_foreground   : #fffde0
workspaces.inactive_background : #171717
workspaces.inactive_foreground : #fffde0
workspaces.padding_left        : 10
workspaces.padding_right       : 10
workspaces.spacing             : 0
workspaces.position            : left
EOF

cat > "$HOME/.xinitrc" <<'EOF'
#!/bin/sh
exec dbus-run-session -- sh -c 'pipewire & sxbar & exec sxwm'
EOF
chmod +x "$HOME/.xinitrc"

# --- Auto-start on tty1 ---
if ! grep -q 'exec startx' "$HOME/.bash_profile" 2>/dev/null; then
    cat >> "$HOME/.bash_profile" <<'EOF'

[ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ] && exec startx
EOF
fi

echo "==> Reboot to start the session."
$PRIV reboot
