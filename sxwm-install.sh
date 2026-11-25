#!/usr/bin/env bash
# install-sxwm-sxbar-cterm.sh
# Fresh Void Linux base install -> X11 + sxwm + sxbar + cterm + Terminus bitmap font.
set -euo pipefail
IFS=$'\n\t'

info() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- sanity checks ----------
[ -f /etc/void-release ] || die "This script is intended for Void Linux."
command -v xbps-install >/dev/null 2>&1 || die "xbps-install not found."

# ---------- root helper ----------
if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
elif command -v doas >/dev/null 2>&1; then
  SUDO=(doas)
else
  die "Run as root, or install sudo/doas first."
fi
run_root() { "${SUDO[@]}" "$@"; }

# ---------- configuration ----------
TERMINUS_PKG="terminus-font"
TERMINUS_BDF="ter-u14n.bdf"
TERMINUS_BDF_BOLD="ter-u14b.bdf"

FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/terminus"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# ---------- 1. system packages ----------
info "Syncing XBPS and installing build/runtime dependencies ..."
run_root xbps-install -Sy \
  git curl tar gcc make pkgconf \
  meson ninja \
  xorg-server xinit xf86-input-libinput \
  libX11-devel libXinerama-devel libXcursor-devel \
  libXft-devel libXext-devel libXi-devel \
  fontconfig fontconfig-devel freetype-devel \
  "$TERMINUS_PKG"

# ---------- 2. Terminus BDF for cterm ----------
info "Installing Terminus BDF for cterm ..."
mkdir -p "$FONT_DIR"

TERMINUS_VERSION="4.49.1"
TERMINUS_URL="https://downloads.sourceforge.net/project/terminus-font/terminus-font-4.49/terminus-font-${TERMINUS_VERSION}.tar.gz"
TERMINUS_TAR="$BUILD_DIR/terminus-font-${TERMINUS_VERSION}.tar.gz"

if curl -fL --retry 3 --connect-timeout 15 -o "$TERMINUS_TAR" "$TERMINUS_URL"; then
  tar -xzf "$TERMINUS_TAR" -C "$BUILD_DIR"
  for bdf in "$TERMINUS_BDF" "$TERMINUS_BDF_BOLD"; do
    src="$(find "$BUILD_DIR" -maxdepth 4 -type f -name "$bdf" -print -quit)"
    [ -n "$src" ] || die "Could not find $bdf in the Terminus tarball."
    install -Dm644 "$src" "$FONT_DIR/$bdf"
  done
else
  warn "SourceForge download failed; trying FreeBSD's Terminus 4.49.1 mirror."
  curl -fL --retry 3 \
    "https://raw.githubusercontent.com/freebsd/freebsd-src/main/contrib/terminus/$TERMINUS_BDF" \
    -o "$FONT_DIR/$TERMINUS_BDF"
  curl -fL --retry 3 \
    "https://raw.githubusercontent.com/freebsd/freebsd-src/main/contrib/terminus/$TERMINUS_BDF_BOLD" \
    -o "$FONT_DIR/$TERMINUS_BDF_BOLD" || true
fi

# ---------- 3. font cache ----------
info "Refreshing font cache ..."
fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
fc-cache -f >/dev/null 2>&1 || true

# ---------- 4. sxwm ----------
info "Building and installing sxwm ..."
git clone --depth=1 https://github.com/uint23/sxwm.git "$BUILD_DIR/sxwm"
(
  cd "$BUILD_DIR/sxwm"
  make CC=gcc
  run_root make CC=gcc install
)

# ---------- 5. sxbar ----------
info "Building and installing sxbar ..."
git clone --depth=1 https://github.com/uint23/sxbar.git "$BUILD_DIR/sxbar"
(
  cd "$BUILD_DIR/sxbar"
  make CC=gcc
  run_root make CC=gcc install
)

# ---------- 6. cterm ----------
info "Building and installing cterm with X11 backend ..."
git clone --depth=1 https://github.com/uint23/cterm.git "$BUILD_DIR/cterm"
(
  cd "$BUILD_DIR/cterm"

  # cterm only supports BDF. Point it at the Terminus BDF we just installed.
  cp config.def.h config.h
  sed -i "s|\"monospace.bdf\"|\"$FONT_DIR/$TERMINUS_BDF\"|" config.h

  export CC=gcc
  meson setup build --buildtype=release -Dwindow_backend=x11
  meson compile -C build
  run_root meson install -C build
)

# ---------- 7. user configuration ----------
info "Writing sxwm, sxbar, and xinitrc configuration ..."
mkdir -p "$CONFIG_DIR/sxbar"

# sxwm: use cterm as the default terminal instead of "st"
cp /usr/local/share/sxwmrc "$CONFIG_DIR/sxwmrc"
sed -i 's|bind : mod + Return : "st"|bind : mod + Return : "cterm"|' "$CONFIG_DIR/sxwmrc"

# sxbar: use the packaged Terminus bitmap font
cp /usr/local/share/sxbarc "$CONFIG_DIR/sxbar/sxbarc"
sed -i 's|^font : monospace|font : Terminus|' "$CONFIG_DIR/sxbar/sxbarc"

# xinitrc: start sxbar, then sxwm
if [ -f "$HOME/.xinitrc" ]; then
  cp "$HOME/.xinitrc" "$HOME/.xinitrc.bak.$(date +%s)"
fi
cat > "$HOME/.xinitrc" <<'EOF'
#!/bin/sh
sxbar &
exec sxwm
EOF
chmod +x "$HOME/.xinitrc"

info "Installation complete."
cat <<EOF

Installed:
  sxwm          -> /usr/local/bin/sxwm
  sxbar         -> /usr/local/bin/sxbar
  cterm         -> /usr/local/bin/cterm
  Terminus BDF  -> $FONT_DIR/$TERMINUS_BDF
  sxwm config   -> $CONFIG_DIR/sxwmrc
  sxbar config  -> $CONFIG_DIR/sxbar/sxbarc
  xinitrc       -> $HOME/.xinitrc

Start X with:
  startx

Check the font:
  fc-list | grep -i terminus
  ls -l "$FONT_DIR/$TERMINUS_BDF"

If you want a different Terminus size, change TERMINUS_BDF in this script
(for example ter-u16n.bdf) and adjust font_size in the sxbar config.
EOF
