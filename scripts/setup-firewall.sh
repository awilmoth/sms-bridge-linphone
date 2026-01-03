#!/bin/bash
# UFW Firewall Setup for SMS Bridge VPS
# Blocks all incoming traffic except SSH, WireGuard, and VoIP

set -e

echo "================================================"
echo "SMS Bridge UFW Firewall Setup"
echo "================================================"
echo
echo "This script will configure UFW to:"
echo "  - Block ALL incoming traffic by default"
echo "  - Allow SSH (port 22) for administration"
echo "  - Allow WireGuard VPN (port 51820 UDP)"
echo "  - Allow SIP/VoIP traffic (ports 443, 5060, 5061)"
echo "  - Allow RTP voice streams (ports 10000-20000 UDP)"
echo
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
   echo "This script requires sudo privileges"
   exit 1
fi

# Install UFW if needed
if ! command -v ufw &> /dev/null; then
    echo "Installing UFW..."
    sudo apt update
    sudo apt install -y ufw
fi

# Configure firewall
echo
echo "Configuring UFW..."

# Show current status
echo
echo "Current UFW status:"
sudo ufw status

echo
echo "Resetting UFW to defaults..."
sudo ufw --force reset > /dev/null 2>&1

echo "Setting default policies..."
# Default deny all incoming traffic
sudo ufw default deny incoming > /dev/null 2>&1
# Allow all outgoing traffic
sudo ufw default allow outgoing > /dev/null 2>&1

echo "Allowing essential ports..."

# SSH administration
echo "  - SSH (22/tcp) for remote administration"
sudo ufw allow 22/tcp > /dev/null 2>&1

# WireGuard VPN
echo "  - WireGuard (51820/udp) for VPN tunnel to Android"
sudo ufw allow 51820/udp > /dev/null 2>&1

# SIP/VoIP Traffic
echo "  - HTTPS (443/tcp) for SIP over TLS and bridge API"
sudo ufw allow 443/tcp > /dev/null 2>&1

echo "  - SIP (5060/tcp,udp) for SIP signaling"
sudo ufw allow 5060/tcp > /dev/null 2>&1
sudo ufw allow 5060/udp > /dev/null 2>&1

echo "  - SIP TLS (5061/tcp) for encrypted SIP"
sudo ufw allow 5061/tcp > /dev/null 2>&1

echo "  - RTP (10000:20000/udp) for voice streaming"
sudo ufw allow 10000:20000/udp > /dev/null 2>&1

echo
echo "Enabling UFW..."
sudo ufw --force enable > /dev/null 2>&1

# Show final status
echo
echo "================================================"
echo "Firewall Configuration Complete!"
echo "================================================"
echo
echo "UFW Status:"
sudo ufw status verbose
echo
echo "Port Details:"
echo
echo "┌─────────────────────────────────────────────────────────┐"
echo "│ Port    │ Protocol │ Purpose                            │"
echo "├─────────────────────────────────────────────────────────┤"
echo "│ 22      │ TCP      │ SSH (administration)               │"
echo "│ 443     │ TCP      │ HTTPS (SIP TLS, Bridge API)        │"
echo "│ 5060    │ TCP/UDP  │ SIP signaling (VoIP provider)      │"
echo "│ 5061    │ TCP      │ SIP TLS (Linphone ↔ Flexisip)      │"
echo "│ 10000-  │ UDP      │ RTP (voice streams)                │"
echo "│ 20000   │          │                                    │"
echo "│ 51820   │ UDP      │ WireGuard VPN (Android)            │"
echo "└─────────────────────────────────────────────────────────┘"
echo
echo "All other incoming traffic is BLOCKED."
echo
echo "Useful commands:"
echo "  - View status:  sudo ufw status verbose"
echo "  - View logs:    sudo ufw status numbered"
echo "  - Show rules:   sudo ufw show added"
echo "  - Reload:       sudo ufw reload"
echo "  - Disable:      sudo ufw disable"
echo
echo "If you accidentally lock yourself out:"
echo "  1. SSH back using SSH key (if key-based auth is working)"
echo "  2. Run: sudo ufw disable"
echo "  3. Re-run this script to restore rules"
echo
echo "Note: Make sure SSH key-based authentication is configured"
echo "      before enabling UFW to avoid being locked out!"
echo
