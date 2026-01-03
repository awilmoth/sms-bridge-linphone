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

echo "# Monitoring & Alerts"
echo "MONITOR_CHECK_INTERVAL=60"
echo "MONITOR_ALERT_COOLDOWN=300"
echo ""

echo "# SMTP Configuration (optional - for health monitoring alerts)"
echo "# Gmail example: smtp.gmail.com:587"
echo "# For Gmail, use an App Password: https://myaccount.google.com/apppasswords"
echo "SMTP_HOST=smtp.gmail.com"
echo "SMTP_PORT=587"
echo "SMTP_USER="
echo "SMTP_PASSWORD="
echo "SMTP_FROM="
echo "SMTP_TO="
echo ""

echo "# Note: VoIP.ms credentials are configured in mmsgate.conf, not here"
echo "# The bridge acts as a proxy - it intercepts calls to VoIP.ms API"
echo "# and routes them to Fossify instead"
