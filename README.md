# SMS/MMS Bridge with Linphone

**Route SMS/MMS from an Android phone with cellular service through a bridge server to Linphone**

## Project Overview

This system creates a secure bridge between an Android phone with a SIM card (the messaging device) and a Linphone client (the messaging app). SMS/MMS messages route through a bridge server on a VPS, allowing you to send and receive SMS/MMS from Linphone using your actual cellular number.

### What You Get

- ✅ **SMS** (bidirectional) via cellular in Linphone
- ✅ **MMS with photos** (bidirectional) via cellular in Linphone
- ✅ **Voice calls** (optional) via any SIP/VoIP provider
- ✅ **Real cellular number** - recipients see your actual number
- ✅ **Single unified app** - everything in Linphone
- ✅ **Provider-agnostic** - use any SIP provider (or none)

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

CALLS (Optional, any SIP provider):
  Inbound: Cellular → Provider → Linphone (via SIP)
  Outbound: Linphone → Provider → PSTN
```

## Key Innovation

**SMS/MMS flow (completely independent of VoIP provider):**
- Your Android SIM card → Fossify (cellular) → Bridge → mmsgate → Linphone
- Bridge proxies messaging requests and routes to Fossify instead of making actual API calls
- Recipient sees your real cellular number (not a VoIP number)
- Works with **any SIP provider** or even **without voice calling at all**

**Voice calls (optional, provider-agnostic):**
- Use any VoIP provider (VoIP.ms, Twilio, Vonage, Asterisk, etc.)
- Provider handles call forwarding to your Linphone SIP address
- Completely separate from SMS/MMS flow
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
- *Optional:* **SIP/VoIP account** (for voice calls; any provider with SIP support)

### 4-Phase Deployment

**Phase 0: WireGuard VPN** (5 min automated)
```bash
cd scripts/
./complete-setup.sh
# - Installs WireGuard on VPS
# - Generates keys and QR code
# - Shows you how to install on Android
```

**Phase 1: Build Fossify** (30 min manual)
```bash
# See fossify-api/README.md
# - Fork Fossify Messages
# - Add HTTP API code (provided)
# - Build and install on Android
# - Configure in-app settings
```

**Phase 2: Deploy Bridge + mmsgate** (30-40 min first run, < 5 min after)
```bash
cd bridge-server/
../scripts/install-bridge.sh
# - Clones mmsgate repo
# - Builds mmsgate (flexisip + pjsip layers)
# - Pushes to local registry
# - Starts all services
```

**Phase 3: Configure mmsgate** (5 min manual, optional if no voice calls needed)
```bash
cd bridge-server/
nano mmsgate.conf  # Only needed if using a VoIP provider
# - Add your VoIP provider credentials
# - Configure call forwarding to bridge
# - Restart service if needed
```

**Phase 4: Setup Linphone** (5 min manual, optional)
```bash
# Install Linphone app
# If using VoIP: Add SIP account (your provider's credentials)
# If voice calls only: Configure call forwarding via your provider
# Test SMS/MMS immediately (works without voice setup)
```

**Total automated setup: ~45 minutes (initial builds)**  
**Subsequent deployments: < 5 minutes**

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
├─ mmsgate:38443 + mmsgate:5060/5061 (MMS gateway + Flexisip SIP proxy)
├─ nginx:80/443 (HTTPS reverse proxy)
├─ registry:5001 (Local Docker image storage)
└─ WireGuard VPN:51820 (connects Android at 10.0.0.2)

Note: Flexisip is built into mmsgate container, not a separate service
```

**Key feature:** mmsgate is built once via multi-layer process (flexisip → pjsip → mmsgate), cached in registry, fast subsequent deployments.

**Step 3: Configure mmsgate**
- Point to bridge as "VoIP.ms API"
- Setup webhook to receive messages

**Step 4: Setup Linphone**
- Add VoIP.ms SIP account
- Test messaging and calls

## Complete Setup

Follow the detailed steps in [docs/QUICKSTART.md](docs/QUICKSTART.md).

## Key Features

### Full MMS Support

Unlike Android SMS Gateway, Fossify uses **native Android MMS APIs**:
- ✅ Send photos via MMS
- ✅ Receive photos via MMS
- ✅ Multiple attachments
- ✅ Video messages

### Real Cellular Number

All SMS/MMS use your actual cellular number:
- ✅ Banking sees legitimate cellular number
- ✅ No VoIP numbers for messages (completely separate flow)
- ✅ Carrier-grade reliability via cellular
- ✅ Works with shortcodes (2FA, banking)

### Flexible Architecture

SMS/MMS flow is independent of voice/VoIP:
- ✅ Works with **any SIP provider** (VoIP.ms, Twilio, Asterisk, etc.)
- ✅ Works **without any voice calling** (SMS/MMS only)
- ✅ Easy to switch providers - no code changes needed
- ✅ Use Linphone as unified SIP client for any provider

### Single App Experience

Everything in Linphone:
- ✅ SMS messaging (always available)
- ✅ MMS messaging with photos (always available)
- ✅ Voice calls (optional, your choice of provider)

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
- [x] VoIP.ms API proxy
- [x] Full MMS support
- [ ] Message delivery reports
- [ ] Message queueing/retry
- [ ] Multi-device support
- [ ] Web admin interface
- [ ] Automated testing

## FAQ

**Q: Why not just use Android SMS Gateway?**  
A: Android SMS Gateway doesn't support sending MMS. Fossify uses native Android APIs with full MMS support.

**Q: Is this legal?**  
A: Yes. You're using your own cellular plan, your own SIM card, and routing messages through your own infrastructure.

**Q: What if my home internet goes down?**  
A: Messages will fail until connectivity restored. Android phone needs internet for WireGuard VPN connection to VPS. Consider backup internet (LTE hotspot) or hosting phone somewhere with redundant internet.

**Q: Does the Android phone need a public IP?**  
A: No! That's why we use WireGuard VPN. The phone connects out to the VPS, creating a private tunnel. The bridge can then reach the phone at 10.0.0.2 via the VPN.

**Q: Can I use this commercially?**  
A: Technically yes, but verify carrier terms. Built for personal use.

**Q: Does this work with WhatsApp/Signal/etc?**  
A: No, only SMS/MMS. Those apps require the phone itself to be active.

**Q: How reliable is this?**  
A: Very reliable for SMS. MMS reliability depends on carrier settings and network quality. Voice calls via VoIP.ms are production-grade.

## Next Steps

1. **Start with:** [docs/QUICKSTART.md](docs/QUICKSTART.md) - Run `./scripts/complete-setup.sh`
2. **Build Fossify:** [fossify-api/README.md](fossify-api/README.md)
3. **Deploy bridge:** `cd bridge-server && docker-compose up`
4. **Test thoroughly:** Before relying on it for travel
5. **Monitor:** Setup alerts and logging

---

**Status:** Production-ready for personal use

**Last Updated:** January 2026

**Maintained by:** Your infrastructure, your control
