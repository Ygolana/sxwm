#!/bin/bash
#
# install-sxwm-suite.sh (fixed for Cozette BDF)
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

echo ">>> Updating package database and upgrading system..."
xbps-install -Syu

# ------------------------------------------------------------
# 1. Install core dependencies
# ------------------------------------------------------------
echo ">>> Installing core dependencies..."
xbps-install -y \
    base-devel \
    xorg-minimal \
    xinit \
    git \
    meson \
    ninja \
    pkg-config \
    elogind \
    dbus \
    curl \
    libX11-devel \
    libXinerama-devel \
    libXcursor-devel \
    libXft-devel \
    libXext-devel \
    libXi-devel \
    fontconfig-devel \
    freetype-devel

ln -sf /etc/sv/elogind /var/service/ 2>/dev/null || true
ln -sf /etc/sv/dbus    /var/service/ 2>/dev/null || true

# ------------------------------------------------------------
# 2. Install Cozette font (OTB/PCF) and sxwm binary package
# ------------------------------------------------------------
echo ">>> Installing font-cozette and sxwm..."
xbps-install -y font-cozette sxwm

# ------------------------------------------------------------
# 2b. Download the BDF version of Cozette (required by cterm)
# ------------------------------------------------------------
COZETTE_BDF_URL="https://github.com/slavfox/Cozette/releases/download/v.1.30.0/cozette.bdf"
COZETTE_BDF_PATH="/usr/share/fonts/misc/cozette.bdf"

if [[ ! -f "$COZETTE_BDF_PATH" ]]; then
    echo ">>> Downloading Cozette BDF from GitHub releases..."
    curl -L -o "$COZETTE_BDF_PATH" "$COZETTE_BDF_URL"
fi

if [[ ! -f "$COZETTE_BDF_PATH" ]]; then
    echo "ERROR: Failed to obtain Cozette BDF. Aborting."
    exit 1
fi

# Refresh font cache so the BDF is recognised by fontconfig
fc-cache -f >/dev/null 2>&1 || true
echo "    Cozette BDF installed at: $COZETTE_BDF_PATH"

# ------------------------------------------------------------
# 3. Build and install sxbar
# ------------------------------------------------------------
echo ">>> Building sxbar from source..."
cd /tmp
rm -rf sxbar
git clone https://github.com/uint23/sxbar.git
cd sxbar
make
make install
cd /tmp
rm -rf sxbar

# ------------------------------------------------------------
# 4. Build and install cterm (with Cozette BDF patch)
# ------------------------------------------------------------
echo ">>> Building cterm from source..."
cd /tmp
rm -rf cterm
git clone https://github.com/uint23/cterm.git
cd cterm

# Patch config.h to use the downloaded BDF
if [[ -f config.h ]]; then
    sed -i "s|\".*\.bdf\"|\"$COZETTE_BDF_PATH\"|" config.h
else
    echo "WARNING: config.h not found – cterm will use its default font."
fi

meson setup build
meson compile -C build
cp build/cterm /usr/local/bin/cterm
cd /tmp
rm -rf cterm

# ------------------------------------------------------------
# 5. Configure .xinitrc and .bash_profile for the first regular user
# ------------------------------------------------------------
TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
if [[ -z "$TARGET_USER" ]]; then
    echo "ERROR: No regular user found. Create a user before running this script."
    exit 1
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
echo ">>> Configuring auto-start for user: $TARGET_USER ($TARGET_HOME)"

cat > "$TARGET_HOME/.xinitrc" <<'EOF'
#!/bin/sh
sxbar &
cterm &
exec sxwm
EOF
chmod +x "$TARGET_HOME/.xinitrc"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"

cat >> "$TARGET_HOME/.bash_profile" <<'EOF'

# Auto-start X on tty1 if not already in a graphical session
if [ -z "$DISPLAY" ] && [ "$(fgconsole)" -eq 1 ]; then
    exec startx
fi
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bash_profile"

# ------------------------------------------------------------
# 6. Final message and reboot
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo " Installation complete!"
echo " The system will reboot in 10 seconds."
echo " After reboot, log in as '$TARGET_USER' on tty1."
echo " The X session (sxwm + sxbar + cterm) will start automatically."
echo "============================================================"
sleep 10
reboot
