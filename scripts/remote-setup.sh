#!/bin/bash
# Remote SMS Bridge + WireGuard VPN Setup
# Run this from your local admin machine to set up a remote VPS

set -e

echo "================================================"
echo "SMS Bridge + WireGuard VPN Remote Setup"
echo "================================================"
echo
echo "This script will set up SMS Bridge on a remote VPS:"
echo "  1. Connect via SSH to VPS"
echo "  2. Install WireGuard on VPS"
echo "  3. Generate VPN keys"
echo "  4. Configure WireGuard server"
echo "  5. Generate Android client config"
echo "  6. Deploy bridge server"
echo "  7. Configure UFW firewall"
echo
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Get VPS connection details
echo
echo "=== VPS Connection Details ==="
read -p "VPS hostname or IP address: " VPS_HOST
read -p "SSH username (default: root): " VPS_USER
VPS_USER=${VPS_USER:-root}

echo
echo "SSH Authentication Method:"
echo "  1. SSH public key (recommended, uses ~/.ssh/id_rsa)"
echo "  2. Password authentication (uses sshpass)"
read -p "Choose method (1 or 2): " AUTH_METHOD

if [ "$AUTH_METHOD" = "2" ]; then
    # Check if sshpass is installed
    if ! command -v sshpass &> /dev/null; then
        echo "Installing sshpass..."
        sudo apt update
        sudo apt install -y sshpass
    fi
    
    read -sp "SSH password: " VPS_PASS
    echo
    
    # Create SSH command function with sshpass
    ssh_cmd() {
        sshpass -p "$VPS_PASS" ssh -o StrictHostKeyChecking=no "$VPS_USER@$VPS_HOST" "$@"
    }
    
    scp_cmd() {
        sshpass -p "$VPS_PASS" scp -o StrictHostKeyChecking=no "$@"
    }
else
    # Use SSH keys
    if [ ! -f ~/.ssh/id_rsa ]; then
        echo "Error: SSH private key not found at ~/.ssh/id_rsa"
        echo "Generate one with: ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
        exit 1
    fi
    
    echo "Using SSH key: ~/.ssh/id_rsa"
    
    # Create SSH command function with keys
    ssh_cmd() {
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "$VPS_USER@$VPS_HOST" "$@"
    }
    
    scp_cmd() {
        scp -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "$@"
    }
fi

echo
echo "Testing SSH connection to $VPS_USER@$VPS_HOST..."
if ssh_cmd "echo 'SSH connection successful'" > /dev/null 2>&1; then
    echo "✓ SSH connection successful"
else
    echo "✗ Failed to connect via SSH"
    echo "Check your credentials and try again"
    exit 1
fi

# Step 1: Install WireGuard
echo
echo "[1/7] Installing WireGuard on VPS..."
ssh_cmd 'command -v wg &> /dev/null && echo "✓ WireGuard already installed" || (sudo apt update && sudo apt install -y wireguard qrencode && echo "✓ WireGuard installed")'

# Step 2: Generate Keys on VPS
echo
echo "[2/7] Generating WireGuard keys on VPS..."
ssh_cmd 'bash -c "
if [ -f /etc/wireguard/server_private.key ]; then
    echo \"✓ Keys already exist\"
else
    cd /etc/wireguard
    sudo sh -c \"umask 077; wg genkey | tee server_private.key | wg pubkey > server_public.key\"
    sudo sh -c \"umask 077; wg genkey | tee client_private.key | wg pubkey > client_public.key\"
    echo \"✓ Keys generated\"
fi
"'

# Read keys from VPS
echo "Retrieving keys from VPS..."
SERVER_PRIVATE=$(ssh_cmd sudo cat /etc/wireguard/server_private.key)
SERVER_PUBLIC=$(ssh_cmd sudo cat /etc/wireguard/server_public.key)
CLIENT_PRIVATE=$(ssh_cmd sudo cat /etc/wireguard/client_private.key)
CLIENT_PUBLIC=$(ssh_cmd sudo cat /etc/wireguard/client_public.key)
PUBLIC_IP=$(ssh_cmd curl -s ifconfig.me)

echo "Server public key: $SERVER_PUBLIC"
echo "Client public key: $CLIENT_PUBLIC"
echo "VPS public IP: $PUBLIC_IP"

# Step 3: Configure WireGuard Server on VPS
echo
echo "[3/7] Configuring WireGuard server..."
ssh_cmd "bash -c "\"
if [ -f /etc/wireguard/wg0.conf ]; then
    echo \"✓ Server config already exists\"
else
    sudo tee /etc/wireguard/wg0.conf > /dev/null <<'WGEOF'
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
WGEOF
    sudo chmod 600 /etc/wireguard/wg0.conf
    echo \"✓ Server configured\"
fi

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
if ! grep -q \"net.ipv4.ip_forward=1\" /etc/sysctl.conf; then
    echo \"net.ipv4.ip_forward=1\" | sudo tee -a /etc/sysctl.conf > /dev/null
fi

# Start WireGuard
echo \"Starting WireGuard...\"
sudo systemctl enable wg-quick@wg0 > /dev/null 2>&1
sudo systemctl start wg-quick@wg0
echo \"✓ WireGuard started\"
"\""'

# Step 4: Generate Android Config locally
echo
echo "[4/7] Generating Android client configuration..."

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

# Generate QR code locally
echo
echo "Generating QR code for easy Android setup..."
if command -v qrencode &> /dev/null; then
    qrencode -t ansiutf8 <<< "$CLIENT_CONFIG"
    echo
    qrencode -t png -o android-wireguard-qr.png <<< "$CLIENT_CONFIG" 2>/dev/null || true
    echo "✓ QR code image saved: android-wireguard-qr.png"
else
    echo "⚠️  qrencode not installed. Install with: sudo apt install qrencode"
fi

echo "✓ Scan this QR code with WireGuard Android app"
echo

# Step 5: Configure UFW Firewall on VPS
echo
echo "[5/7] Configuring UFW firewall..."
ssh_cmd 'bash -c "
# Install UFW if needed
if ! command -v ufw &> /dev/null; then
    sudo apt update
    sudo apt install -y ufw
fi

# Configure firewall
sudo ufw --force reset > /dev/null 2>&1
sudo ufw default deny incoming > /dev/null 2>&1
sudo ufw default allow outgoing > /dev/null 2>&1

# SSH
sudo ufw allow 22/tcp > /dev/null 2>&1

# WireGuard
sudo ufw allow 51820/udp > /dev/null 2>&1

# SIP/VoIP
sudo ufw allow 443/tcp > /dev/null 2>&1
sudo ufw allow 5060/tcp > /dev/null 2>&1
sudo ufw allow 5060/udp > /dev/null 2>&1
sudo ufw allow 5061/tcp > /dev/null 2>&1
sudo ufw allow 10000:20000/udp > /dev/null 2>&1

# Enable firewall
sudo ufw --force enable > /dev/null 2>&1

echo \"✓ UFW firewall configured\"
"'

# Step 6: Setup Bridge Server on VPS
echo
echo "[6/7] Setting up bridge server..."

# Install Docker if needed
echo "Installing Docker and docker-compose on VPS..."
ssh_cmd 'bash -c "
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker \$USER
    echo \"✓ Docker installed\"
else
    echo \"✓ Docker already installed\"
fi

if ! command -v docker-compose &> /dev/null; then
    sudo apt install -y docker-compose
    echo \"✓ docker-compose installed\"
else
    echo \"✓ docker-compose already installed\"
fi
"'

# Generate and send .env to VPS
echo "Generating bridge configuration..."

BRIDGE_SECRET=$(openssl rand -hex 32)
FOSSIFY_TOKEN=$(openssl rand -hex 32)

ENV_CONTENT="# Fossify Messages API Configuration (via WireGuard VPN)
FOSSIFY_API_URL=http://10.0.0.2:8080
FOSSIFY_AUTH_TOKEN=$FOSSIFY_TOKEN

# Bridge Security
BRIDGE_SECRET=$BRIDGE_SECRET

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
"

# Send .env to VPS
echo "Sending configuration to VPS..."
echo "$ENV_CONTENT" | ssh_cmd 'cat > /tmp/.env.tmp && (cd bridge-server && [ ! -f .env ] && mv /tmp/.env.tmp .env || rm /tmp/.env.tmp)'

# Start bridge server
echo "Starting bridge server..."
ssh_cmd 'bash -c "
cd bridge-server
docker-compose up -d --build 2>&1 | head -20
"'

# Step 7: Test
echo
echo "[7/7] Testing remote setup..."
sleep 5

# Test bridge health via SSH
echo "Testing bridge health..."
if ssh_cmd 'curl -f http://localhost:5000/health > /dev/null 2>&1'; then
    echo "✓ Bridge server running"
else
    echo "⚠️  Bridge server health check failed (may still be starting)"
fi

# Summary
echo
echo "================================================"
echo "Remote Setup Complete!"
echo "================================================"
echo
echo "Connection Details:"
echo "  - VPS: $VPS_USER@$VPS_HOST"
echo "  - VPS IP: $PUBLIC_IP"
echo "  - VPS Internal IP: 10.0.0.1"
echo "  - Android VPN IP: 10.0.0.2"
echo
echo "Next steps on YOUR LOCAL MACHINE:"
echo
echo "1. Install WireGuard on Android:"
echo "   - Download from Google Play Store"
echo "   - Tap '+' → 'Scan from QR code'"
echo "   - Scan the QR code from this setup"
echo "   - Or import: android-wireguard.conf"
echo
echo "2. Test WireGuard connection:"
echo "   - Enable VPN on Android"
echo "   - From VPS: ping 10.0.0.2"
echo "   - From local: ping -c 4 10.0.0.2 (via VPN)"
echo
echo "3. Configure Fossify Messages on Android:"
echo "   - Settings → API Server → Enable ✓"
echo "   - Port: 8080"
echo "   - Auth Token: (save from below)"
echo "   - Webhook URL: https://bridge.your-domain.com:5000/webhook/fossify"
echo "   - Webhook Token: (save from below)"
echo
echo "4. Build and install Fossify APK:"
echo "   - See ../fossify-api/README.md for details"
echo
echo "Generated Credentials (save securely):"
echo "  - FOSSIFY_AUTH_TOKEN=$FOSSIFY_TOKEN"
echo "  - BRIDGE_SECRET=$BRIDGE_SECRET"
echo
echo "WireGuard Files:"
echo "  - android-wireguard.conf (config file)"
echo "  - android-wireguard-qr.png (QR code image)"
echo
echo "Useful remote commands:"
echo "  - SSH: ssh -i ~/.ssh/id_rsa $VPS_USER@$VPS_HOST"
echo "  - Bridge logs: ssh $VPS_USER@$VPS_HOST 'cd bridge-server && docker-compose logs -f'"
echo "  - Bridge down: ssh $VPS_USER@$VPS_HOST 'cd bridge-server && docker-compose down'"
echo "  - Check VPN: ssh $VPS_USER@$VPS_HOST 'sudo wg show'"
echo
