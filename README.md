# SMS/MMS Bridge with Linphone

**Route SMS/MMS from an Android phone with cellular service through a bridge server to Linphone**

## Project Overview

This system creates a secure bridge between an Android phone with a SIM card (the messaging device) and a Linphone client (the messaging app). SMS/MMS messages route through a bridge server on a VPS, allowing you to send and receive SMS/MMS from Linphone using your actual cellular number.

### What You Get

- ✅ **SMS** (bidirectional) via cellular in Linphone
- ✅ **MMS with photos** (bidirectional) via cellular in Linphone
- ✅ **Voice calls** (optional) using your real cellular number via SIP forwarding
- ✅ **Real cellular number** - for SMS/MMS and voice (with bring-your-own-DID provider)
- ✅ **Single unified app** - everything in Linphone
- ✅ **Provider-agnostic** - use any SIP provider that supports number forwarding (or none)
- ✅ **Health monitoring** - automatic SMTP alerts when services go down

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    COMPLETE MESSAGE FLOW                    │
└─────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │ Internet/Public │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  VPS (Bridge)   │
                    │  Public IP      │
                    │  10.0.0.1 (VPN) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ WireGuard VPN   │
                    │  10.0.0.0/24    │
                    │   Encrypted     │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Android Phone   │
                    │  (with SIM)     │
                    │  10.0.0.2 (VPN) │
                    │                 │
                    │ Messaging Device│
                    └─────────────────┘

OUTGOING (Linphone user → Recipient):
  Linphone app
    ↓ SIP MESSAGE
  mmsgate (SIP messaging handler)
    ↓ HTTP to bridge:5000/voipms/api
  Bridge (message router, via WireGuard VPN)
    ↓ HTTPS to 10.0.0.2:8080
  Fossify Messages (Android phone)
    ↓ Cellular network
  Recipient (sees your real cellular number)

INCOMING (Someone → Your cellular number):
  Sender → Your cellular number
    ↓ Cellular network
  Fossify Messages (Android phone)
    ↓ Webhook via WireGuard to bridge:5000/webhook/fossify
  Bridge (receives and routes)
    ↓ Webhook to mmsgate
  mmsgate (SIP messaging)
    ↓ SIP MESSAGE
  Linphone app (receives notification)

CALLS (Optional, any SIP provider with bring-your-own-DID):
  Inbound: Your cellular number → VoIP provider → Linphone (via SIP)
  Outbound: Linphone → VoIP provider → PSTN (with your cellular caller ID)
```

## Key Innovation

**SMS/MMS flow (completely independent of VoIP provider):**
- Your Android SIM card → Fossify (cellular) → Bridge → mmsgate → Linphone
- Bridge proxies messaging requests and routes to Fossify instead of making actual API calls
- Recipient sees your real cellular number (not a VoIP number)
- Works with **any SIP provider** or even **without voice calling at all**

**Voice calls (optional, provider-agnostic):**
- Use any VoIP provider that supports bring-your-own-DID (VoIP.ms, Twilio, Vonage, etc.)
- Forward your cellular number to your Linphone SIP address via the provider
- Outbound calls can use your cellular caller ID through the provider
- Completely separate from SMS/MMS flow (which always uses cellular)
- Can be omitted entirely - this system works for messaging alone

## Project Structure

```
sms-bridge-linphone/
├── README.md                    ← You are here
├── docs/
│   ├── ARCHITECTURE.md          ← Detailed architecture diagrams
│   └── TROUBLESHOOTING.md       ← Common issues and solutions
├── bridge-server/
│   ├── sms-bridge-server.py     ← Main bridge server
│   ├── requirements.txt         ← Python dependencies
│   ├── Dockerfile               ← Container image
│   ├── docker-compose.yml       ← Full stack deployment
│   └── .env.example             ← Configuration template
├── fossify-api/
│   ├── ApiServer.kt             ← HTTP server for Fossify
│   ├── ApiService.kt            ← Background service
│   ├── SmsReceiver.kt           ← Webhook client
│   └── README.md                ← Integration instructions
├── configs/
│   ├── mmsgate.conf.example     ← mmsgate configuration
│   ├── flexisip.conf.example    ← SIP proxy configuration
│   └── nginx.conf.example       ← Reverse proxy setup
└── scripts/
    ├── install-bridge.sh        ← One-command install
    ├── test-endpoints.sh        ← Endpoint testing
    └── generate-secrets.sh      ← Generate secure tokens
```

## Quick Start

### Prerequisites

- **Android phone** with active cellular SIM card
- **VPS/Server** with public IP and domain (2GB RAM minimum)
- **Docker & docker-compose**
- **WireGuard** (automated setup included)
- *Optional:* **SIP/VoIP provider** that supports bring-your-own-DID (for seamless number forwarding and voice calls)

### 4-Phase Deployment

**Phase 0: WireGuard VPN**
```bash
cd scripts/
./complete-setup.sh
# - Installs WireGuard on VPS
# - Generates keys and QR code
# - Provides Android installation instructions
```

**Phase 1: Build Fossify**
```bash
# See fossify-api/README.md
# - Fork Fossify Messages
# - Add HTTP API code (provided)
# - Build and install APK on Android
# - Configure API settings in app
```

**Phase 2: Deploy Bridge + mmsgate**
```bash
cd bridge-server/
../scripts/install-bridge.sh
# - Clones mmsgate repo
# - Builds all Docker images (multi-layer)
# - Pushes to local registry
# - Starts all services
```

**Phase 3: Configure mmsgate** *(SMS/MMS works without this step)*
```bash
cd bridge-server/

# SMS/MMS works immediately with placeholder credentials
# For voice calls, add your VoIP provider credentials:
nano mmsgate.conf  # Update username/password with your provider account
nano flexisip.conf # Update domain settings if needed

docker-compose restart mmsgate
```

**Phase 4: Setup Linphone** *(optional for voice calls)*
```bash
# Install Linphone app on your device
# Add SIP account with your provider's credentials
# Configure cellular number forwarding (if using voice calls)
# Test SMS/MMS (works without SIP account)
```

### Technology Stack

| Component   | Purpose                     | Technology         |
| ----------- | --------------------------- | ------------------ |
| **Bridge**  | Message routing & API proxy | Python Flask       |
| **VPN**     | Secure tunnel to Android    | WireGuard          |
| **Phone**   | Native cellular messaging   | Fossify + HTTP API |
| **SIP**     | Voice calls & SIP messages  | Linphone + mmsgate |
| **Hosting** | All services in containers  | Docker Compose     |

### Docker Deployment Architecture

```
VPS Docker Compose:
├─ sms-bridge:5000 (Flask, message router)
├─ mmsgate:38443 + 5060/5061 (SIP messaging + Flexisip proxy)
├─ monitor (health checks + SMTP alerts)
├─ nginx:80/443 (HTTPS reverse proxy)
├─ registry:5001 (Local Docker image storage)
└─ WireGuard VPN:51820 (encrypted tunnel to Android)

Note: Flexisip is built into mmsgate container, not a separate service
```

**Key feature:** mmsgate uses multi-layer build (flexisip → pjsip → mmsgate), cached in local registry for fast redeployment.

## Complete Setup

Follow the detailed steps in [docs/QUICKSTART.md](docs/QUICKSTART.md).

## Key Features

### Full MMS Support

Uses **native Android MMS APIs** for complete functionality:
- ✅ Send photos via MMS
- ✅ Receive photos via MMS
- ✅ Multiple attachments
- ✅ Video messages

### Real Cellular Number

All SMS/MMS use the actual cellular number:
- ✅ Banking and services see legitimate cellular number
- ✅ No VoIP numbers for messaging (separate from voice)
- ✅ Carrier-grade reliability
- ✅ Works with shortcodes (2FA, OTP, banking)

### Flexible Architecture

SMS/MMS independent of voice calling:
- ✅ Works with **any SIP provider** (Twilio, Vonage, Asterisk, VoIP.ms, etc.)
- ✅ Works **without voice calling** (SMS/MMS only mode)
- ✅ Switch providers without code changes
- ✅ Unified Linphone interface for any SIP provider

### Unified Interface

Single app for all communications:
- ✅ SMS messaging
- ✅ MMS messaging with photos
- ✅ Voice calls (optional)

## Components

### 1. Fossify Messages (Android Phone)

**Modified open-source messaging app**
- Receives SMS/MMS via cellular network
- HTTP API server for remote control
- Webhook client for notifications
- Native Android MMS APIs (full support)

**Repository:** https://github.com/FossifyOrg/Messages (your fork)

### 2. Bridge Server (VPS)

**Python Flask server**
- Message API proxy (intercepts and routes requests)
- Webhook receiver (from Fossify)
- Message router (cellular ↔ SIP)
- Provider-agnostic (works with any SIP backend)
- Stateless, simple, reliable

**Code:** `bridge-server/sms-bridge-server.py`

### 3. mmsgate (VPS)

**SIP MESSAGE ↔ SMS/MMS converter**
- Converts between SIP and SMS/MMS protocols
- Handles MMS media uploads/downloads
- Routes messages to Flexisip for SIP delivery
- Works with standard SIP clients (Linphone, etc.)

**Repository:** https://github.com/RVgo4it/mmsgate

### 4. Flexisip (VPS)

**SIP proxy server**
- Routes SIP messages
- Handles push notifications
- Production-grade SIP infrastructure

**Repository:** https://github.com/BelledonneCommunications/flexisip

### 5. Linphone (Your Device)

**SIP client app**
- Available on iOS, Android, Desktop
- Standard SIP/RTP protocols
- Excellent messaging support

**Website:** https://linphone.org

## Security

### Authentication

- **Fossify API:** Bearer token authentication
- **Bridge webhooks:** Bearer token authentication  
- **SIP (Linphone):** Username/password (your VoIP provider's credentials, if using voice)
- **mmsgate:** Internal to Docker network

### Encryption

- **SIP transport:** TLS (port 5061)
- **Bridge webhooks:** HTTPS with valid certificates
- **WireGuard VPN:** Encrypted tunnel for Fossify API access (10.0.0.0/24)
- **All internal Docker communication:** Private Docker network (sms-net)

### Network Exposure

- **Fossify:** Not exposed (WireGuard VPN only, 10.0.0.2)
- **WireGuard:** UDP port 51820 (encrypted VPN tunnel)
- **Bridge:** HTTPS with authentication
- **mmsgate:** HTTPS with authentication
- **Flexisip:** TLS SIP only

## Features

### Full MMS Support

Unlike many SMS gateways, this system uses **native Android MMS APIs**:
- ✅ Send photos via MMS
- ✅ Receive photos via MMS
- ✅ Multiple attachments
- ✅ Video messages

### Real Cellular Number

All SMS/MMS use the actual cellular number:
- ✅ Legitimate cellular number for banking
- ✅ Works with shortcodes (2FA, OTP)
- ✅ Carrier-grade reliability
- ✅ No VoIP numbers for messaging

### Flexible Architecture

SMS/MMS flow is independent of voice/VoIP:
- ✅ Works with **any SIP provider** (Twilio, Vonage, Asterisk, VoIP.ms, etc.)
- ✅ Works **without any voice calling** (SMS/MMS only)
- ✅ Easy to switch providers - no code changes needed
- ✅ Use Linphone as unified SIP client for any provider

## Contributing

This is a personal project, but improvements welcome:

1. **Fossify API improvements** - better error handling, security
2. **Bridge features** - message queueing, delivery reports
3. **Documentation** - setup guides, video tutorials
4. **Testing** - automated tests, CI/CD

## License

- **This project:** MIT License (bridge server, documentation)
- **Fossify Messages:** GPL-3.0 (your fork must stay GPL-3.0)
- **mmsgate:** Check repository license
- **Flexisip:** GPLv3

## Credits

- **Fossify Messages:** https://github.com/FossifyOrg/Messages
- **mmsgate:** https://github.com/RVgo4it/mmsgate
- **Flexisip:** https://github.com/BelledonneCommunications/flexisip
- **Linphone:** https://linphone.org

## Support

### Documentation

- [Quick Start Guide](docs/QUICKSTART.md) - Follow this to get started
- [Architecture](docs/ARCHITECTURE.md) - Technical details
- [Fossify Build](fossify-api/README.md) - Building Fossify with API
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues

### Community

- Open an issue for bugs or questions
- Share improvements via pull request

## Roadmap

- [x] Basic SMS/MMS bridge
- [x] Message API proxy
- [x] Full MMS support
- [x] Docker registry caching
- [x] WireGuard VPN automation
- [ ] Message delivery reports
- [ ] Message queueing/retry
- [ ] Multi-device support
- [ ] Web admin interface
- [ ] Automated testing

## FAQ

**Q: Why not use other SMS gateway solutions?**  
A: Most SMS gateways don't support MMS sending. This system uses native Android MMS APIs for full multimedia support.

**Q: Does the Android phone need a public IP?**  
A: No. The WireGuard VPN creates a secure tunnel from the phone to the VPS, allowing the bridge to reach the phone via the private VPN network (10.0.0.2).

**Q: What if the Android phone's internet goes down?**  
A: Messages will fail until connectivity is restored. The phone needs internet access to maintain the WireGuard VPN tunnel.

**Q: Can I use this with WhatsApp/Signal/Telegram?**  
A: No, only SMS/MMS. Those apps require the phone itself to be actively running their app.

**Q: How reliable is this system?**  
A: Very reliable for SMS. MMS reliability depends on carrier settings and network quality. Voice calls depend on your chosen SIP provider.

**Q: Can I switch SIP/VoIP providers?**  
A: Yes. The SMS/MMS bridge is provider-agnostic. You can use any SIP provider that supports bring-your-own-DID, or none at all (SMS/MMS only mode).

**Q: How do I use my cellular number for voice calls?**  
A: Use a VoIP provider that supports bring-your-own-DID (like VoIP.ms). Configure call forwarding from your cellular number to your provider's DID, then set up that DID in Linphone. Outbound calls will show your cellular caller ID.

**Q: How does health monitoring work?**  
A: The monitor service checks bridge health endpoint (HTTP) and mmsgate availability (TCP port check) every 60 seconds. If a service goes down, it sends an email alert via SMTP (configurable). You'll get alerts when services fail and when they recover. Configure SMTP settings in `.env` to enable alerts.
