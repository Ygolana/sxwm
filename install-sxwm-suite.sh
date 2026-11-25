#!/bin/bash
#
# install-sxwm-suite.sh
# Installs sxwm, sxbar, cterm, and the Cozette font on Void Linux,
# configures auto-start on tty1, and reboots.
#
set -euo pipefail

# ------------------------------------------------------------
# 0. Prerequisites
# ------------------------------------------------------------
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
    libX11-devel \
    libXinerama-devel \
    libXcursor-devel \
    libXft-devel \
    libXext-devel \
    libXi-devel \
    fontconfig-devel \
    freetype-devel

# Enable elogind for proper session/XDG_RUNTIME_DIR management
ln -sf /etc/sv/elogind /var/service/ 2>/dev/null || true
ln -sf /etc/sv/dbus    /var/service/ 2>/dev/null || true

# ------------------------------------------------------------
# 2. Install Cozette font (BDF) and sxwm binary package
# ------------------------------------------------------------
echo ">>> Installing Cozette font and sxwm..."
xbps-install -y font-cozette sxwm

# Locate the Cozette BDF file (installed by the package)
COZETTE_BDF=$(find /usr/share/fonts -iname '*cozette*.bdf' 2>/dev/null | head -n1)
if [[ -z "$COZETTE_BDF" ]]; then
    echo "ERROR: Cozette BDF font not found. Aborting."
    exit 1
fi
echo "    Cozette BDF path: $COZETTE_BDF"

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
# 4. Build and install cterm (with Cozette font patch)
# ------------------------------------------------------------
echo ">>> Building cterm from source..."
cd /tmp
rm -rf cterm
git clone https://github.com/uint23/cterm.git
cd cterm

# Patch the font path in config.h to use the installed Cozette BDF
if [[ -f config.h ]]; then
    sed -i "s|\".*\.bdf\"|\"$COZETTE_BDF\"|" config.h
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
# Find the first user with UID ≥ 1000 (typical first login user)
TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
if [[ -z "$TARGET_USER" ]]; then
    echo "ERROR: No regular user found. Create a user before running this script."
    exit 1
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
echo ">>> Configuring auto-start for user: $TARGET_USER ($TARGET_HOME)"

# Create .xinitrc
cat > "$TARGET_HOME/.xinitrc" <<'EOF'
#!/bin/sh
# Start the status bar in the background
sxbar &
# Start the terminal emulator in the background
cterm &
# Replace the shell with the window manager
exec sxwm
EOF
chmod +x "$TARGET_HOME/.xinitrc"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"

# Append auto-start logic to .bash_profile (only on tty1 and outside X)
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
