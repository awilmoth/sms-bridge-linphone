#!/bin/bash
# One-command install for SMS Bridge Server

set -e

echo "====================================="
echo "SMS Bridge Server - Quick Installer"
echo "====================================="
echo

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo "Please don't run as root. Run as normal user with sudo privileges."
   exit 1
fi

# Check prerequisites
echo "[1/8] Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Docker installed. Please log out and back in, then run this script again."
    exit 0
fi

if ! command -v docker-compose &> /dev/null; then
    echo "docker-compose not found. Installing..."
    sudo apt update
    sudo apt install -y docker-compose
fi

echo "Prerequisites OK"
echo

# Generate secrets
echo "[2/8] Generating secrets..."
if [ ! -f .env ]; then
    ../scripts/generate-secrets.sh > .env
    echo "Secrets generated in .env"
    echo
    echo "Please edit .env file and fill in:"
    echo "  - FOSSIFY_API_URL (your WireGuard VPN IP: 10.0.0.2)"
    echo "  - FOSSIFY_AUTH_TOKEN (from Fossify app settings)"
    echo
    read -p "Press Enter after editing .env to continue..."
else
    echo ".env already exists, skipping generation"
fi

# Validate configuration
echo
echo "[3/8] Validating configuration..."
source .env

if [ -z "$FOSSIFY_API_URL" ] || [ "$FOSSIFY_API_URL" == "http://10.0.0.2:8080" ]; then
    echo "ERROR: FOSSIFY_API_URL not configured in .env"
    exit 1
fi

if [ -z "$FOSSIFY_AUTH_TOKEN" ] || [ "$FOSSIFY_AUTH_TOKEN" == "generate-with-openssl-rand-hex-32" ]; then
    echo "ERROR: FOSSIFY_AUTH_TOKEN not configured in .env"
    exit 1
fi

echo "Configuration OK"
echo

# Check for mmsgate
echo "[4/8] Checking mmsgate repository..."
if [ ! -d "mmsgate" ]; then
    echo "⚠ mmsgate not found. Cloning from GitHub..."
    git clone --recursive https://github.com/RVgo4it/mmsgate
fi

echo "mmsgate OK"
echo

# Build and push to registry
echo "[5/8] Building Docker images and pushing to local registry..."
../scripts/build-and-push-images.sh

echo
echo "[6/8] Starting services..."
docker-compose up -d

# Wait for startup
echo
echo "[7/8] Waiting for services to start..."
sleep 10

# Check health
echo
echo "[8/8] Checking health..."
if curl -f http://localhost:5000/health &> /dev/null; then
    echo
    echo "====================================="
    echo "Installation successful!"
    echo "====================================="
    echo
    echo "Services running:"
    echo "  - Local registry: localhost:5001"
    echo "  - SMS Bridge: http://localhost:5000"
    echo "  - mmsgate: 38443 (MMS), 5060/5061 (SIP via flexisip), 38000-38999 (RTP)"
    echo "  - Health Monitor: checking bridge and mmsgate"
    echo
    echo "Next steps:"
    echo "1. Configure Fossify webhook:"
    echo "   URL: https://bridge.your-domain.com:5000/webhook/fossify"
    echo "   Token: $BRIDGE_SECRET"
    echo
    echo "2. Configure mmsgate:"
    echo "   api_url = https://bridge.your-domain.com:5000/voipms/api"
    echo
    echo "3. Configure SMTP alerts (optional):"
    echo "   Edit .env and set SMTP_USER, SMTP_PASSWORD, SMTP_TO"
    echo "   Restart monitor: docker-compose restart monitor"
    echo
    echo "4. Setup nginx reverse proxy for HTTPS"
    echo
    echo "Useful commands:"
    echo "  - View logs: docker-compose logs -f"
    echo "  - View registry: docker-compose logs registry"
    echo "  - Restart: docker-compose restart"
    echo "  - Stop: docker-compose down"
    echo "  - Check health: curl http://localhost:5000/health"
    echo
else
    echo
    echo "WARNING: Health check failed"
    echo "Check logs with: docker-compose logs -f"
fi
