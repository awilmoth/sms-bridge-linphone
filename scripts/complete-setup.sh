#!/bin/bash
# Complete setup script for SMS Bridge with WireGuard VPN

set -e

echo "================================================"
echo "SMS Bridge + WireGuard VPN Setup"
echo "================================================"
echo
echo "This script will:"
echo "  1. Install WireGuard on VPS"
echo "  2. Generate VPN keys"
echo "  3. Configure WireGuard server"
echo "  4. Generate Android client config"
echo "  5. Deploy bridge server"
echo
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo "Please don't run as root. Run as normal user with sudo privileges."
   exit 1
fi

# Step 1: Install WireGuard
echo
echo "[1/6] Installing WireGuard..."
if ! command -v wg &> /dev/null; then
    sudo apt update
    sudo apt install -y wireguard qrencode
    echo "✓ WireGuard installed"
else
    echo "✓ WireGuard already installed"
fi

# Step 2: Generate Keys
echo
echo "[2/6] Generating WireGuard keys..."
if [ ! -f /etc/wireguard/server_private.key ]; then
    cd /etc/wireguard
    sudo sh -c 'umask 077; wg genkey | tee server_private.key | wg pubkey > server_public.key'
    sudo sh -c 'umask 077; wg genkey | tee client_private.key | wg pubkey > client_public.key'
    echo "✓ Keys generated"
else
    echo "✓ Keys already exist"
fi

# Read keys
SERVER_PRIVATE=$(sudo cat /etc/wireguard/server_private.key)
SERVER_PUBLIC=$(sudo cat /etc/wireguard/server_public.key)
CLIENT_PRIVATE=$(sudo cat /etc/wireguard/client_private.key)
CLIENT_PUBLIC=$(sudo cat /etc/wireguard/client_public.key)
PUBLIC_IP=$(curl -s ifconfig.me)

echo "Server public key: $SERVER_PUBLIC"
echo "Client public key: $CLIENT_PUBLIC"

# Step 3: Configure WireGuard Server
echo
echo "[3/6] Configuring WireGuard server..."
if [ ! -f /etc/wireguard/wg0.conf ]; then
    sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = 10.0.0.2/32
PersistentKeepalive = 25
EOF
    sudo chmod 600 /etc/wireguard/wg0.conf
    echo "✓ Server configured"
else
    echo "✓ Server config already exists"
fi

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
fi

# Start WireGuard
echo "Starting WireGuard..."
sudo systemctl enable wg-quick@wg0 > /dev/null 2>&1
sudo systemctl start wg-quick@wg0

# Configure firewall (UFW)
echo
echo "Configuring UFW firewall..."
if command -v ufw &> /dev/null; then
    # Enable UFW with default deny policy
    sudo ufw --force enable > /dev/null 2>&1
    
    # Default deny all incoming
    sudo ufw default deny incoming > /dev/null 2>&1
    sudo ufw default allow outgoing > /dev/null 2>&1
    
    # Allow SSH (port 22)
    sudo ufw allow 22/tcp > /dev/null 2>&1
    
    # Allow WireGuard (port 51820 UDP)
    sudo ufw allow 51820/udp > /dev/null 2>&1
    
    # Allow SIP/VoIP traffic
    # - Port 5061: SIP TLS (Linphone ↔ Flexisip)
    # - Port 5060: SIP TCP/UDP (VoIP provider)
    # - Port 443: HTTPS (bridge API, also used by SIP over TLS)
    # - Port 5000: Bridge API (only reachable via WireGuard, but open for safety)
    sudo ufw allow 443/tcp > /dev/null 2>&1
    sudo ufw allow 5060/tcp > /dev/null 2>&1
    sudo ufw allow 5060/udp > /dev/null 2>&1
    sudo ufw allow 5061/tcp > /dev/null 2>&1
    
    # RTP for voice (typically 16384-32767, open range for simplicity)
    # In production, restrict this range more tightly
    sudo ufw allow 10000:20000/udp > /dev/null 2>&1
    
    echo "✓ UFW firewall configured:"
    echo "  - Default: DENY all incoming"
    echo "  - SSH: port 22/tcp"
    echo "  - WireGuard: port 51820/udp"
    echo "  - SIP/VoIP: ports 443, 5060, 5061, 10000:20000/udp"
else
    echo "⚠️  UFW not available, skipping firewall configuration"
    echo "   Install with: sudo apt install ufw"
fi

# Step 4: Generate Android Config
echo
echo "[4/6] Generating Android client configuration..."

# Create client config
CLIENT_CONFIG=$(cat <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF
)

# Save to file
echo "$CLIENT_CONFIG" > android-wireguard.conf
echo "✓ Configuration saved to: android-wireguard.conf"

# Generate QR code
echo
echo "Generating QR code for easy Android setup..."
qrencode -t ansiutf8 <<< "$CLIENT_CONFIG"
echo
echo "✓ Scan this QR code with WireGuard Android app"
echo

# Also save QR as PNG
qrencode -t png -o android-wireguard-qr.png <<< "$CLIENT_CONFIG" 2>/dev/null || true

# Step 5: Setup Bridge Server
echo
echo "[5/6] Setting up bridge server..."

# Install Docker if needed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Installing docker-compose..."
    sudo apt install -y docker-compose
fi

# Generate .env
cd "$(dirname "$0")/../bridge-server"

if [ ! -f .env ]; then
    echo "Generating .env configuration..."
    cat > .env <<ENV_EOF
# Fossify Messages API Configuration (via WireGuard VPN)
FOSSIFY_API_URL=http://10.0.0.2:8080
FOSSIFY_AUTH_TOKEN=$(openssl rand -hex 32)

# Bridge Security
BRIDGE_SECRET=$(openssl rand -hex 32)

# Server Configuration
FLASK_HOST=0.0.0.0
FLASK_PORT=5000

# Monitoring & Alerts
MONITOR_CHECK_INTERVAL=60
MONITOR_ALERT_COOLDOWN=300

# SMTP Configuration (optional - for health monitoring alerts)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=
SMTP_TO=
ENV_EOF
    
    echo "✓ Configuration generated: bridge-server/.env"
    echo
    echo "⚠️  IMPORTANT: Edit bridge-server/.env and update:"
    echo "    - FOSSIFY_API_URL: Use your WireGuard Android IP (10.0.0.2)"
    echo "    - FOSSIFY_AUTH_TOKEN: Use token from Fossify app settings"
    echo "    - SMTP_USER/SMTP_PASSWORD: Optional, for email alerts when services fail"
    echo
    echo "Note: VoIP.ms credentials go in mmsgate.conf, NOT here"
    echo
    read -p "Press Enter after editing .env to continue..."
fi

# Start bridge
echo "Starting bridge server..."
docker-compose up -d --build

# Step 6: Test
echo
echo "[6/6] Testing setup..."
sleep 5

# Test bridge health
if curl -f http://localhost:5000/health > /dev/null 2>&1; then
    echo "✓ Bridge server running"
else
    echo "✗ Bridge server health check failed"
fi

# Summary
echo
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo
echo "Next steps:"
echo
echo "1. Install WireGuard on Android:"
echo "   - Download from Google Play Store"
echo "   - Tap '+' → 'Scan from QR code'"
echo "   - Scan the QR code above"
echo "   - Or import: android-wireguard.conf"
echo
echo "2. Configure Fossify Messages:"
echo "   - Settings → API Server → Enable ✓"
echo "   - Port: 8080"
echo "   - Auth Token: (copy from below)"
echo "   - Webhook URL: https://bridge.your-domain.com:5000/webhook/fossify"
echo "   - Webhook Token: (copy from below)"
echo
echo "3. Test WireGuard connection:"
echo "   - Enable VPN on Android"
echo "   - From VPS: ping 10.0.0.2"
echo "   - Should get replies"
echo
echo "4. Test Fossify API:"
echo "   curl http://10.0.0.2:8080/health"
echo
echo "Configuration details:"
echo "  - VPN Server: $PUBLIC_IP:51820"
echo "  - VPN Network: 10.0.0.0/24"
echo "  - VPS IP: 10.0.0.1"
echo "  - Android IP: 10.0.0.2"
echo "  - Fossify URL: http://10.0.0.2:8080"
echo
echo "Tokens (save these securely):"
grep "FOSSIFY_AUTH_TOKEN" .env
grep "BRIDGE_SECRET" .env
echo
echo "Android WireGuard config: android-wireguard.conf"
echo "QR Code image: android-wireguard-qr.png"
echo
echo "Useful commands:"
echo "  - Check VPN: sudo wg show"
echo "  - Bridge logs: docker-compose logs -f"
echo "  - Monitor logs: docker-compose logs -f monitor"
echo "  - Test endpoints: ../scripts/test-endpoints.sh"
echo
echo "Optional: Configure SMTP alerts"
echo "  - Edit .env: SMTP_USER, SMTP_PASSWORD, SMTP_TO"
echo "  - Restart: docker-compose restart monitor"
echo
