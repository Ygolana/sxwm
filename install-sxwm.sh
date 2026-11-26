#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="$HOME/.cache/sxwm-build"
FONT_BDF_URL="https://sourceforge.net/projects/terminus-font/files/terminus-font-4.49.1/terminus-font-4.49.1.tar.gz/download"
FONT_DIR="/usr/local/share/fonts/terminus-bdf"

if command -v sudo >/dev/null 2>&1; then
    PRIV="sudo"
elif command -v doas >/dev/null 2>&1; then
    PRIV="doas"
else
    echo "Neither sudo nor doas found" >&2
    exit 1
fi

# Base packages: Xorg core, Intel (modesetting + Mesa DRI), input, audio, brightness, font
$PRIV xbps-install -Sy \
    xorg-server xinit xf86-input-libinput mesa-dri \
    dbus elogind \
    pipewire wireplumber \
    brightnessctl \
    terminus-font fontconfig

# Build-only packages (removed at the end)
$PRIV xbps-install -Sy \
    git gcc make pkg-config meson ninja \
    libX11-devel libXinerama-devel libXcursor-devel \
    libXft-devel freetype-devel fontconfig-devel \
    tar curl

# Fonts: enable bitmap fonts for Xft (sxbar) and rebuild font cache
$PRIV ln -sfn /usr/share/fontconfig/conf.avail/70-yes-bitmaps.conf /etc/fonts/conf.d/70-yes-bitmaps.conf
$PRIV xbps-reconfigure -f fontconfig

# Services: system bus, seat/session management (XDG_RUNTIME_DIR for PipeWire)
for svc in dbus elogind; do
    [ -e "/var/service/$svc" ] || $PRIV ln -s "/etc/sv/$svc" /var/service/
done

# Brightness without root: video group + udev rule for backlight nodes
$PRIV usermod -aG video "$(id -un)"
$PRIV tee /etc/udev/rules.d/90-backlight.rules >/dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"
EOF

# Terminus BDF source for cterm (cterm needs BDF, not OTB/PCF)
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
curl -fL "$FONT_BDF_URL" -o terminus.tar.gz
tar -xzf terminus.tar.gz
TERM_BDF="$(find "$BUILD_DIR" -name 'ter-u16n.bdf' -print -quit)"
$PRIV install -Dm644 "$TERM_BDF" "$FONT_DIR/ter-u16n.bdf"

# sxwm
git clone --depth 1 https://github.com/uint23/sxwm.git "$BUILD_DIR/sxwm"
make -C "$BUILD_DIR/sxwm"
$PRIV make -C "$BUILD_DIR/sxwm" PREFIX=/usr/local install

# sxbar
git clone --depth 1 https://github.com/uint23/sxbar.git "$BUILD_DIR/sxbar"
make -C "$BUILD_DIR/sxbar"
$PRIV make -C "$BUILD_DIR/sxbar" PREFIX=/usr/local install

# cterm (compile-time config: point font_path at the installed BDF)
git clone --depth 1 https://github.com/uint23/cterm.git "$BUILD_DIR/cterm"
sed -i "s|\"monospace.bdf\"|\"$FONT_DIR/ter-u16n.bdf\"|" "$BUILD_DIR/cterm/config.def.h"
meson setup "$BUILD_DIR/cterm/build" "$BUILD_DIR/cterm" --prefix=/usr/local --buildtype=release
ninja -C "$BUILD_DIR/cterm/build"
$PRIV ninja -C "$BUILD_DIR/cterm/build" install

# sxwm keybinds (format: bind|workspace <combo> : <action>)
mkdir -p "$HOME/.config"
cat > "$HOME/.config/sxwmrc" <<'EOF'
bind mod+Return : "cterm"
bind mod+shift+c : close_window
bind mod+f : fullscreen
bind mod+space : toggle_floating
bind mod+j : focus_next
bind mod+k : focus_prev
bind mod+shift+j : move_win_down
bind mod+shift+k : move_win_up
bind mod+h : master_decrease
bind mod+l : master_increase
bind mod+shift+r : reload_config
bind mod+shift+e : quit
bind mod+Tab : switch_previous_workspace
EOF
for ws in 1 2 3 4 5 6 7 8 9; do
    printf 'workspace mod+%s : move %s\nworkspace mod+shift+%s : swap %s\n' "$ws" "$ws" "$ws" "$ws" >> "$HOME/.config/sxwmrc"
done
cat >> "$HOME/.config/sxwmrc" <<'EOF'
bind XF86AudioRaiseVolume : "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
bind XF86AudioLowerVolume : "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
bind XF86AudioMute : "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
bind XF86MonBrightnessUp : "brightnessctl set 5%+"
bind XF86MonBrightnessDown : "brightnessctl set 5%-"
EOF

# sxbar config: bottom bar, Terminus, clock + workspace labels
mkdir -p "$HOME/.config/sxbar"
cat > "$HOME/.config/sxbar/sxbarc" <<'EOF'
bar_position: top
height: 20
font: Terminus
font_size: 16
background_colour: #000000
foreground_colour: #cccccc
module.0.name: clock
module.0.cmd: date '+%a %d %b %H:%M'
module.0.enabled: true
module.0.interval: 30
EOF

# Auto-start: PipeWire/WirePlumber, bar, then sxwm via startx on tty1 login
cat > "$HOME/.xinitrc" <<'EOF'
pipewire &
wireplumber &
sxbar &
exec sxwm
EOF
chmod +x "$HOME/.xinitrc"

PROFILE="$HOME/.bash_profile"
touch "$PROFILE"
if ! grep -q 'exec startx' "$PROFILE"; then
    cat >> "$PROFILE" <<'EOF'

[ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ] && exec startx
EOF
fi

# Remove build-only packages and their orphaned dependencies
$PRIV xbps-remove -Ry git gcc make pkg-config meson ninja \
    libX11-devel libXinerama-devel libXcursor-devel \
    libXft-devel freetype-devel fontconfig-devel tar curl || true
$PRIV xbps-remove -Oy
rm -rf "$BUILD_DIR"

$PRIV reboot
