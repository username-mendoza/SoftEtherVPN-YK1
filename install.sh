#!/usr/bin/env bash
# SoftEtherVPN-YK1 installer
# Clones SoftEther v4.44-9807-rtm, applies the YK1 patch, builds, and installs.
set -euo pipefail

SE_REPO="https://github.com/SoftEtherVPN/SoftEtherVPN_Stable.git"
SE_TAG="v4.44-9807-rtm"
PATCH_URL="https://raw.githubusercontent.com/username-mendoza/SoftEtherVPN-YK1/main/yk1.patch"
DEFAULT_INSTALL_DIR="/opt/vpnserver"

# Required per BUILD_UNIX.TXT + confirmed linker flags (-lssl -lcrypto -lreadline -lncurses -lz)
BUILD_DEPS="build-essential libssl-dev libreadline-dev libncurses-dev zlib1g-dev"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
ask()   { local r; read -rp "$1 [y/N] " r < /dev/tty; [[ "$r" =~ ^[Yy]$ ]]; }
prompt(){ local r; read -rp "$1 " r < /dev/tty; echo "${r:-$2}"; }

echo -e "${BOLD}SoftEther VPN Server — YK1 patch installer${NC}"
echo -e "Installs SoftEther $SE_TAG with YubiKey PIV PKCS#11 support"
echo

[ "$EUID" -eq 0 ] || error "Run as root: sudo bash $0"

# Build deps
info "Required build packages: $BUILD_DEPS"
if ask "Install build dependencies now?"; then
    apt-get update -qq
    apt-get install -y $BUILD_DEPS
fi

for dep in gcc make; do
    command -v "$dep" &>/dev/null || error "$dep not found — install build dependencies first"
done

# Locate patch file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-./}")" 2>/dev/null && pwd || echo ".")"
if [ -f "$SCRIPT_DIR/yk1.patch" ]; then
    PATCH="$SCRIPT_DIR/yk1.patch"
    info "Using local patch: $PATCH"
else
    info "Downloading patch from GitHub..."
    PATCH=$(mktemp --suffix=.patch)
    curl -sSL "$PATCH_URL" -o "$PATCH"
    trap "rm -f $PATCH" EXIT
fi

# Install directory
INSTALL_DIR=$(prompt "Install directory [$DEFAULT_INSTALL_DIR]:" "$DEFAULT_INSTALL_DIR")
[ ! -d "$INSTALL_DIR" ] || warn "$INSTALL_DIR already exists — files will be overwritten"

# Build in temp dir
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

info "Cloning SoftEther $SE_TAG (this may take a few minutes)..."
git clone --depth 1 --branch "$SE_TAG" "$SE_REPO" "$BUILD_DIR/src"

info "Applying YK1 patch..."
git -C "$BUILD_DIR/src" apply "$PATCH"

info "Configuring..."
cd "$BUILD_DIR/src"
./configure

info "Building (this takes several minutes)..."
make -j"$(nproc)"

# Install
info "Installing to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp bin/vpnserver/vpnserver   "$INSTALL_DIR/"
cp bin/vpnserver/hamcore.se2 "$INSTALL_DIR/"
cp bin/vpncmd/vpncmd         "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/vpnserver" "$INSTALL_DIR/vpncmd"
info "Binaries installed"

# Service
if ask "Install as systemd service?"; then
    # Use the official service file from source, adjusted for install dir
    sed "s|/opt/vpnserver|$INSTALL_DIR|g" systemd/softether-vpnserver.service \
        > /etc/systemd/system/vpnserver.service

    systemctl daemon-reload
    systemctl enable vpnserver
    info "Service installed and enabled"

    if ask "Start the service now?"; then
        systemctl start vpnserver
        info "SoftEther VPN Server started"
    else
        info "Start when ready: systemctl start vpnserver"
    fi
else
    info "Start manually: $INSTALL_DIR/vpnserver start"
fi

echo
info "Done. Configure with: $INSTALL_DIR/vpncmd"
