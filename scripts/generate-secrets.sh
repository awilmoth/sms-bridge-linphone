#!/bin/bash
# Generate secure secrets for bridge-server/.env file

echo "# Bridge Server Configuration"
echo "# Generated $(date)"
echo ""

echo "# Fossify Messages API (via WireGuard VPN)"
echo "FOSSIFY_API_URL=http://10.0.0.2:8080"
echo "FOSSIFY_AUTH_TOKEN=$(openssl rand -hex 32)"
echo ""

echo "# Bridge Security"
echo "BRIDGE_SECRET=$(openssl rand -hex 32)"
echo ""

echo "# Server Configuration"
echo "FLASK_HOST=0.0.0.0"
echo "FLASK_PORT=5000"
echo ""

echo "# Note: VoIP.ms credentials are configured in mmsgate.conf, not here"
echo "# The bridge acts as a proxy - it intercepts calls to VoIP.ms API"
echo "# and routes them to Fossify instead"
