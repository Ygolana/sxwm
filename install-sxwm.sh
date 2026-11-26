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

# ----------------------------------------------------------------------
# Helper: Change Void Linux mirror (optional, run manually if needed)
# ----------------------------------------------------------------------
change_mirror() {
    local new_mirror="${1:-https://mirrors.servercentral.com/voidlinux}"
    echo "Changing mirror to: $new_mirror"
    $PRIV mkdir -p /etc/xbps.d
    $PRIV cp /usr/share/xbps.d/*-repository-*.conf /etc/xbps.d/
    $PRIV sed -i "s|https://repo-default.voidlinux.org|$new_mirror|g" /etc/xbps.d/*-repository-*.conf
    $PRIV xbps-install -S
}

# ----------------------------------------------------------------------
# Helper: Robust package installation
# ----------------------------------------------------------------------
install_pkgs() {
    # Clear cache to remove stale metadata
    $PRIV rm -rf /var/cache/xbps/*
    # Verbose upgrade to expose and resolve version conflicts
    if ! $PRIV xbps-install -Suv; then
        echo "Verbose upgrade failed. This often indicates a mirror issue." >&2
        echo "Consider running the 'change_mirror' function in this script." >&2
        # As a last resort, attempt to force the upgrade of the blocking packages
        # This is risky and may break the system, so we only try the specific packages.
        $PRIV xbps-install -Suv libX11 libXext libXfixes libXrender 2>/dev/null || true
        $PRIV xbps-install -Syu
    fi
    # Install the required packages
    $PRIV xbps-install -Sy "$@"
}

cleanup() {
    rm -rf /tmp/sxwm /tmp/sxbar /tmp/cterm /tmp/spleen /tmp/libgrapheme
}
trap cleanup EXIT

# ----------------------------------------------------------------------
# Install system packages (with robust upgrade)
# ----------------------------------------------------------------------
install_pkgs $BUILD_DEPS $SXWM_DEPS $SXBAR_DEPS $CTERM_DEPS $XORG_PKGS $AUDIO_PKGS $UTIL_PKGS

# ... (rest of the script: building components, config files, etc.) ...
