#!/usr/bin/env bash
set -euo pipefail

if command -v sudo >/dev/null 2>&1; then
    PRIV="sudo"
elif command -v doas >/dev/null 2>&1; then
    PRIV="doas"
else
    echo "Neither sudo nor doas was found." >&2
    exit 1
fi

SRC_DIR="$(mktemp -d)"
trap 'rm -rf "$SRC_DIR"' EXIT

BUILD_PKGS="git gcc make pkg-config meson ninja"
DEV_PKGS="libX11-devel libXinerama-devel libXcursor-devel libXext-devel libXi-devel libXft-devel"
RUNTIME_PKGS="xorg-server xinit xf86-input-libinput mesa-dri pipewire wireplumber brightnessctl dbus elogind terminus-font"

# Packages
$PRIV xbps-install -Sy xbps
$PRIV xbps-install -Suy
$PRIV xbps-install -y $BUILD_PKGS $DEV_PKGS $RUNTIME_PKGS

# Services and groups
[ -e /var/service/dbus ] || $PRIV ln -s /etc/sv/dbus /var/service/
[ -e /var/service/elogind ] || $PRIV ln -s /etc/sv/elogind /var/service/
$PRIV usermod -aG video "$USER"

# Bitmap fonts for fontconfig
$PRIV ln -sfn /usr/share/fontconfig/conf.avail/70-yes-bitmaps.conf /etc/fonts/conf.d/
$PRIV xbps-reconfigure -f fontconfig

# Sources
git clone --depth 1 https://github.com/uint23/sxwm "$SRC_DIR/sxwm"
git clone --depth 1 https://github.com/uint23/sxbar "$SRC_DIR/sxbar"
git clone --depth 1 https://github.com/uint23/cterm "$SRC_DIR/cterm"

# Build and install
make -C "$SRC_DIR/sxwm"
$PRIV make -C "$SRC_DIR/sxwm" install

make -C "$SRC_DIR/sxbar"
$PRIV make -C "$SRC_DIR/sxbar" install

meson setup --buildtype=release --prefix=/usr/local "$SRC_DIR/cterm/build" "$SRC_DIR/cterm"
meson compile -C "$SRC_DIR/cterm/build"
$PRIV meson install -C "$SRC_DIR/cterm/build"

# Remove build-only packages
$PRIV xbps-remove -y $BUILD_PKGS $DEV_PKGS

# Configuration
mkdir -p "$HOME/.config/sxwm" "$HOME/.config/sxbar"

cat > "$HOME/.config/sxwm/sxwmrc" <<'EOF'
mod_key : super
gaps : 0
border_width : 1
master_width : 60
focused_border_colour : #ffffff
unfocused_border_colour : #444444
new_win_focus : true
warp_cursor : true

bind : mod + Return : "cterm"

call : mod + shift + q : close_window
call : mod + shift + e : quit
call : mod + r : reload_config
call : mod + Tab : switch_previous_workspace

call : mod + j : focus_next
call : mod + k : focus_prev
call : mod + h : master_decrease
call : mod + l : master_increase
call : mod + shift + j : move_win_down
call : mod + shift + k : move_win_up
call : mod + shift + h : move_win_left
call : mod + shift + l : move_win_right

call : mod + space : toggle_floating
call : mod + shift + f : fullscreen
call : mod + m : toggle_monocle

bind : XF86AudioRaiseVolume : "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
bind : XF86AudioLowerVolume : "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
bind : XF86AudioMute : "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
bind : XF86MonBrightnessUp : "brightnessctl set +5%"
bind : XF86MonBrightnessDown : "brightnessctl set 5%-"
EOF

for workspace in 1 2 3 4 5 6 7 8 9; do
    printf 'workspace : mod + %s\nworkspace : mod + shift + %s\n' "$workspace" "$workspace" >> "$HOME/.config/sxwm/sxwmrc"
done

cat > "$HOME/.config/sxbar/sxbarc" <<'EOF'
bar_position : top
height : 22
vertical_padding : 0
horizontal_padding : 0
text_padding : 0
border : false
background_colour : #000000
foreground_colour : #ffffff
font : Terminus
font_size : 12

module.0.name : volume
module.0.cmd : wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "v: %d%s", $2*100, ($3 ? " m" : "")}'
module.0.enabled : true
module.0.interval : 1

module.1.name : clock
module.1.cmd : date '+%a %Y-%m-%d %H:%M'
module.1.enabled : true
module.1.interval : 10

workspaces.labels : 1 2 3 4 5 6 7 8 9
workspaces.active_background : #ffffff
workspaces.active_foreground : #000000
workspaces.inactive_background : #000000
workspaces.inactive_foreground : #ffffff
workspaces.padding_left : 6
workspaces.padding_right : 6
workspaces.spacing : 0
workspaces.position : left
EOF

cat > "$HOME/.xinitrc" <<'EOF'
pipewire &
wireplumber &
sxbar &
exec sxwm
EOF

grep -qs 'exec startx' "$HOME/.bash_profile" || cat >> "$HOME/.bash_profile" <<'EOF'
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
EOF

$PRIV reboot
