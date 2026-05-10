# SoftEtherVPN YK1 Patch

Patch for **SoftEther VPN v4.44-9807-rtm** adding YubiKey PIV PKCS#11 certificate authentication over OpenVPN protocol.

## What it does

- **`src/Mayaqua/Secure.h`** — adds YubiKey 5 to the PKCS#11 device list (IDs 28/29: `libykcs11.dll` / `libykcs11.so`)
- **`src/Cedar/Protocol.c`** — strips `@domain` suffix from certificate CN in `PackLoginWithOpenVPNCertificate()` so `alice@example.com` matches username `alice`
- **`src/Cedar/Cedar.c`** — version string suffix → `Build 9807-YK1`
- **`src/Cedar/Console.c`** — fix extended key sequence handling on Linux (`OS_WIN32` guard)
- **`src/Cedar/VLanUnix.h`** — declare `FreeTap()`

## Quick install

```bash
sudo bash <(curl -sSL https://raw.githubusercontent.com/username-mendoza/SoftEtherVPN-YK1/main/install.sh)
```

The script installs build dependencies (optional), clones SoftEther v4.44-9807-rtm, applies the patch, compiles, and installs the binaries. Optionally installs and starts a systemd service. It asks before doing anything non-trivial.

Requires: Debian/Ubuntu-based system, `git`, `curl`, internet access.

## Manual build

### 1. Install build dependencies

Debian / Ubuntu:
```bash
sudo apt-get install build-essential libssl-dev libreadline-dev libncurses-dev zlib1g-dev
```

Fedora / CentOS:
```bash
sudo yum groupinstall "Development Tools"
sudo yum install openssl-devel readline-devel ncurses-devel zlib-devel
```

### 2. Clone, patch, build

```bash
git clone --depth 1 --branch v4.44-9807-rtm \
    https://github.com/SoftEtherVPN/SoftEtherVPN_Stable.git
cd SoftEtherVPN_Stable
git apply /path/to/yk1.patch
./configure
make -j$(nproc)
```

Binaries end up in `bin/vpnserver/` (vpnserver + hamcore.se2) and `bin/vpncmd/`.

### 3. Install

```bash
sudo mkdir -p /opt/vpnserver
sudo cp bin/vpnserver/vpnserver bin/vpnserver/hamcore.se2 bin/vpncmd/vpncmd /opt/vpnserver/
sudo chmod +x /opt/vpnserver/vpnserver /opt/vpnserver/vpncmd
```

### 4. Systemd service (optional)

A service file is included in the source at `systemd/softether-vpnserver.service`. Adjust the path if you installed somewhere other than `/opt/vpnserver/`:

```bash
sudo sed 's|/opt/vpnserver|/your/path|g' \
    systemd/softether-vpnserver.service \
    > /etc/systemd/system/vpnserver.service
sudo systemctl daemon-reload
sudo systemctl enable --now vpnserver
```

Or start directly:
```bash
/opt/vpnserver/vpnserver start
```

## Client setup

Uses standard OpenVPN with `pkcs11-providers libykcs11` — no client patching needed. Compatible with **OpenVPN community CLI/GUI** and **OpenVPN Connect v3.3+**.

```
pkcs11-providers /usr/lib/x86_64-linux-gnu/libykcs11.so
pkcs11-id "pkcs11:model=YubiKey%20YK5;token=YubiKey%20PIV%20%23XXXXXXXX;..."
```

Get the correct `pkcs11-id` with:
```
openvpn --show-pkcs11-ids /usr/lib/libykcs11.so
```

## Auth model

- Auth type: `AUTHTYPE_USERCERT` — each user has their certificate registered directly in SoftEther
- No CA required — byte-for-byte certificate match
- Username derived from certificate CN (or from `auth-user-pass` for multi-hub routing)
