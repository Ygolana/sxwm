#!/usr/bin/env bash
#
# install-uint23.sh
# Installs sxwm, sxbar, cterm, and uint23 dotfiles from source on Void Linux.
#
set -euo pipefail

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
REPO_SXWM="https://github.com/uint23/sxwm.git"
REPO_SXBAR="https://github.com/uint23/sxbar.git"
REPO_CTERM="https://github.com/uint23/cterm.git"
REPO_DOTS="https://github.com/uint23/uint23.git"

TMP_DIR="$(mktemp -d /tmp/uint23-install.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Privilege escalation helper
if [[ $EUID -eq 0 ]]; then
    SUDO=""
elif command -v sudo &>/dev/null; then
    SUDO="sudo"
elif command -v doas &>/dev/null; then
    SUDO="doas"
else
    echo "ERROR: Neither sudo nor doas found. Please install one or run as root."
    exit 1
fi

# Determine target user home (if running via sudo, use SUDO_USER)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# ------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------
log()  { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

check_void() {
    if ! grep -qi 'void' /etc/os-release 2>/dev/null; then
        die "This script is intended for Void Linux only."
    fi
    log "Void Linux detected."
}

install_packages() {
    log "Installing build dependencies..."
    $SUDO xbps-install -Sy \
        git gcc make meson ninja pkg-config \
        libX11-devel libXinerama-devel libXcursor-devel \
        libXft-devel freetype-devel fontconfig-devel \
        libXext-devel libXi-devel xorgproto
}

build_sxwm() {
    log "Building and installing sxwm..."
    git clone --depth=1 "$REPO_SXWM" "$TMP_DIR/sxwm"
    (
        cd "$TMP_DIR/sxwm"
        make
        $SUDO make install
    )
    log "sxwm installed successfully."
}

build_sxbar() {
    log "Building and installing sxbar..."
    git clone --depth=1 "$REPO_SXBAR" "$TMP_DIR/sxbar"
    (
        cd "$TMP_DIR/sxbar"
        make
        $SUDO make install
    )
    log "sxbar installed successfully."
}

build_cterm() {
    log "Building and installing cterm..."
    git clone --depth=1 "$REPO_CTERM" "$TMP_DIR/cterm"
    (
        cd "$TMP_DIR/cterm"
        meson setup build --prefix=/usr/local
        meson compile -C build
        $SUDO meson install -C build
    )
    log "cterm installed successfully."
}

install_dotfiles() {
    log "Installing uint23 dotfiles to $TARGET_HOME ..."
    git clone --depth=1 "$REPO_DOTS" "$TMP_DIR/dots"

    # Backup existing dotfiles if they exist
    for item in .config .mkshrc .vimrc .Xmodmap autostart userChrome.css wallpapers; do
        if [[ -e "$TARGET_HOME/$item" ]]; then
            warn "Backing up existing $TARGET_HOME/$item -> $TARGET_HOME/$item.bak"
            mv "$TARGET_HOME/$item" "$TARGET_HOME/$item.bak"
        fi
    done

    # Copy everything from the dotfiles repo into the home directory
    cp -a "$TMP_DIR/dots/." "$TARGET_HOME/"
    chown -R "$TARGET_USER:" "$TARGET_HOME/.config" "$TARGET_HOME/.mkshrc" \
        "$TARGET_HOME/.vimrc" "$TARGET_HOME/.Xmodmap" \
        "$TARGET_HOME/autostart" "$TARGET_HOME/userChrome.css" \
        "$TARGET_HOME/wallpapers" 2>/dev/null || true

    log "Dotfiles installed."
}

setup_configs() {
    log "Setting up default configuration files..."

    # sxwm: copy default config to ~/.config/sxwmrc
    if [[ ! -f "$TARGET_HOME/.config/sxwmrc" ]]; then
        cp /usr/local/share/sxwmrc "$TARGET_HOME/.config/sxwmrc"
        chown "$TARGET_USER:" "$TARGET_HOME/.config/sxwmrc"
        log "Created ~/.config/sxwmrc"
    fi

    # sxbar: copy default config to ~/.config/sxbar/sxbarc
    mkdir -p "$TARGET_HOME/.config/sxbar"
    if [[ ! -f "$TARGET_HOME/.config/sxbar/sxbarc" ]]; then
        cp /usr/local/share/sxbarc "$TARGET_HOME/.config/sxbar/sxbarc"
        chown -R "$TARGET_USER:" "$TARGET_HOME/.config/sxbar"
        log "Created ~/.config/sxbar/sxbarc"
    fi
}

print_post_install() {
    cat <<'EOF'

✅  All components installed successfully!

Next steps:
  1. To start sxwm with startx, add the following to ~/.xinitrc:
         exec sxwm
  2. If you use a display manager, select "sxwm" from the session menu.
  3. sxbar can be launched manually or added to your sxwm autostart file:
         sxbar &
  4. cterm is available as `cterm`.
  5. Review and customise the configuration files:
         ~/.config/sxwmrc
         ~/.config/sxbar/sxbarc
  6. Log out and back in (or restart your display manager) to apply changes.

EOF
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
main() {
    check_void
    install_packages
    build_sxwm
    build_sxbar
    build_cterm
    install_dotfiles
    setup_configs
    print_post_install
}

main "$@"