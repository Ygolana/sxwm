#!/bin/bash
# install-sxwm-suite.sh (minimal)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

# --- Packages ---
xbps-install -Syu
xbps-install -y \
    gcc make pkg-config meson ninja git curl \
    dbus elogind xorg-minimal xinit \
    libX11-devel libXext-devel libXi-devel libXinerama-devel libXft-devel \
    sxwm

# --- Services ---
ln -sf /etc/sv/dbus    /var/service/
ln -sf /etc/sv/elogind /var/service/

# --- Cozette BDF (cterm requires BDF) ---
BDF=/usr/share/fonts/misc/cozette.bdf
mkdir -p "$(dirname "$BDF")"
[[ -s $BDF ]] || curl -fL --create-dirs -o "$BDF" \
    https://github.com/slavfox/Cozette/releases/download/v.1.30.0/cozette.bdf
fc-cache -f >/dev/null

# --- Build sxbar + cterm ---
cd /tmp && rm -rf sxbar cterm
git clone --depth 1 https://github.com/uint23/sxbar
git clone --depth 1 https://github.com/uint23/cterm

make -C sxbar all install
sed -i "s|\".*\.bdf\"|\"$BDF\"|" cterm/config.h
meson setup cterm/build cterm >/dev/null
meson compile -C cterm/build >/dev/null
install -m755 cterm/build/cterm /usr/local/bin/
cd /tmp && rm -rf sxbar cterm

# --- Auto-start for the first regular user on tty1 ---
U=$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)
H=$(getent passwd "$U" | cut -d: -f6)

printf '#!/bin/sh\nsxbar &\ncterm &\nexec sxwm\n' > "$H/.xinitrc"
chmod +x "$H/.xinitrc"

printf '\n[ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ] && exec startx\n' \
    >> "$H/.bash_profile"

chown -R "$U:$U" "$H/.xinitrc" "$H/.bash_profile"

# --- Reboot ---
echo "Done. Rebooting in 5s..."
sleep 5
reboot
