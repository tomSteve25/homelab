#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Pre-flight checks ---
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

ARCH=$(uname -m)
info "Detected architecture: $ARCH"
case "$ARCH" in
    aarch64|armv7l|x86_64) ;;
    *) warn "Untested architecture: $ARCH — proceed with caution" ;;
esac

# --- Install Docker if missing ---
if ! command -v docker &>/dev/null; then
    info "Docker not found — installing via official script..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    info "Docker installed successfully"
else
    info "Docker already installed: $(docker --version)"
fi

# Verify Compose v2
if ! docker compose version &>/dev/null; then
    error "Docker Compose v2 plugin not found. Install it: https://docs.docker.com/compose/install/"
fi
info "Docker Compose: $(docker compose version --short)"

# --- System prep ---

# Disable systemd-resolved stub listener if it's holding port 53
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    if ss -tulnp | grep -q ':53.*systemd-resolve'; then
        info "Disabling systemd-resolved stub listener (frees port 53 for Pi-hole)..."
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/no-stub.conf <<EOF
[Resolve]
DNSStubListener=no
EOF
        systemctl restart systemd-resolved
        # Point /etc/resolv.conf to a real upstream while we transition
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        info "systemd-resolved stub listener disabled"
    else
        info "systemd-resolved is running but not binding port 53 — no changes needed"
    fi
fi

# Enable IP forwarding (needed for Tailscale)
info "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

# Persist IP forwarding
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi

# Ensure TUN device exists
if [[ ! -e /dev/net/tun ]]; then
    info "Creating /dev/net/tun..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 666 /dev/net/tun
fi

# --- Environment setup ---
if [[ ! -f .env ]]; then
    info "Creating .env from .env.example..."
    cp .env.example .env

    echo ""
    echo "============================================"
    echo "  Configure your environment variables"
    echo "============================================"
    echo ""

    read -rp "Tailscale auth key (tskey-auth-...): " ts_key
    [[ -z "$ts_key" ]] && error "Tailscale auth key is required"
    sed -i "s|TS_AUTHKEY=tskey-auth-XXXX|TS_AUTHKEY=$ts_key|" .env

    read -rp "Pi-hole admin password: " pihole_pw
    [[ -n "$pihole_pw" ]] && sed -i "s|PIHOLE_PASSWORD=changeme|PIHOLE_PASSWORD=$pihole_pw|" .env

    read -rp "Your domain (e.g. example.com) [optional]: " domain
    [[ -n "$domain" ]] && sed -i "s|DOMAIN=example.com|DOMAIN=$domain|" .env

    read -rp "Timezone (e.g. America/New_York) [America/New_York]: " tz
    [[ -n "$tz" ]] && sed -i "s|TZ=America/New_York|TZ=$tz|" .env

    read -rp "Cloudflare Tunnel token [optional]: " cf_tunnel
    [[ -n "$cf_tunnel" ]] && sed -i "s|CF_TUNNEL_TOKEN=|CF_TUNNEL_TOKEN=$cf_tunnel|" .env

    echo ""
    info ".env configured — you can edit it later at: $SCRIPT_DIR/.env"
else
    info ".env already exists — skipping configuration"
fi

# --- Create data directories ---
info "Creating data directories..."
mkdir -p services/tailscale-pihole/ts-state
mkdir -p services/tailscale-pihole/config/pihole
mkdir -p services/tailscale-pihole/config/dnsmasq

# --- Install Caddyfile ---
if command -v caddy &>/dev/null; then
    info "Installing Caddyfile..."
    cp "$SCRIPT_DIR/Caddyfile" /etc/caddy/Caddyfile
    systemctl reload caddy || systemctl restart caddy
    info "Caddy reloaded"
else
    warn "Caddy not found — skipping Caddyfile install"
fi

# --- Launch ---
info "Pulling images..."
docker compose pull

info "Starting services..."
docker compose up -d

echo ""
echo "============================================"
echo "  Homelab is running!"
echo "============================================"
echo ""

# Wait a moment for Tailscale to connect
sleep 5

TS_IP=$(docker exec tailscale-pihole tailscale ip -4 2>/dev/null || echo "pending...")
echo "  Pi-hole Tailscale IP: $TS_IP"
echo "  Pi-hole Admin UI:     http://$TS_IP/admin"
echo ""
echo "  Next steps:"
echo "  1. Go to https://login.tailscale.com/admin/dns"
echo "  2. Add a Global Nameserver: $TS_IP"
echo "  3. Enable 'Override local DNS'"
echo "  4. All Tailnet devices will now use Pi-hole for DNS"
echo ""
info "Done!"
