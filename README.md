# SMS/MMS Bridge: Linphone Complete Solution

**Everything in one app: Calls, SMS, and MMS via Linphone using your real cellular number**

## Project Overview

This project enables you to use Linphone as your complete communications app while traveling, with full SMS/MMS capabilities using your actual cellular number. Your Android phone stays at home with your SIM card, and all messages route through a bridge server to Linphone wherever you are.

### What You Get

- ✅ **Voice calls** via VoIP.ms in Linphone
- ✅ **SMS** (bidirectional) via your cellular number in Linphone
- ✅ **MMS with photos** (bidirectional) via your cellular number in Linphone
- ✅ **Real cellular number** - recipients see your actual number, not VoIP
- ✅ **Single app** - everything in Linphone
- ✅ **Works globally** - travel anywhere with internet access

### Perfect For

- 🌍 Digital nomads and frequent travelers
- 🏦 Banking 2FA codes while abroad
- 📱 Maintaining your US/home number internationally
- 💼 Professional communications on the go

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
                    │ Android (Home)  │
                    │  10.0.0.2 (VPN) │
                    │ Behind NAT/FW   │
                    └─────────────────┘

OUTGOING (You → Someone):
  You (Linphone)
    ↓ SIP MESSAGE
  mmsgate (calls "VoIP.ms API" at bridge)
    ↓ HTTP to bridge:5000/voipms/api
  Bridge (intercepts, routes via WireGuard VPN)
    ↓ HTTP to 10.0.0.2:8080
  Fossify Messages (Android at home)
    ↓ Cellular
  Recipient (sees YOUR cellular number)

INCOMING (Someone → You):
  Sender → Your cellular number
    ↓ Cellular
  Fossify Messages (Android at home)
    ↓ Webhook via WireGuard to bridge:5000/webhook/fossify
  Bridge
    ↓ Webhook to mmsgate
  mmsgate
    ↓ SIP MESSAGE
  Linphone (You)

CALLS:
  Inbound: Cellular → *72 Forward → VoIP.ms → Linphone
  Outbound: Linphone → VoIP.ms (with cellular caller ID) → PSTN
```

## Key Innovation

**The bridge acts as a VoIP.ms API proxy:**
- mmsgate thinks it's calling VoIP.ms to send SMS
- Bridge intercepts and routes to Fossify instead
- Fossify sends via your cellular network
- Recipient sees your real cellular number

No VoIP numbers for SMS/MMS - everything uses your cellular number.

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

- **Android phone** with SIM card (stays at home, plugged in)
- **VPS** with 2GB RAM, public IP (Ubuntu 22.04 recommended)
- **Domain name** with DNS configured
- **VoIP.ms account** (for SIP/voice)
- **Docker & docker-compose** (installed automatically by script)
- **WireGuard VPN** setup (included in scripts)

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

**Phase 3: Configure mmsgate** (5 min manual)
```bash
cd bridge-server/
nano mmsgate.conf  # Add VoIP.ms credentials
docker-compose restart mmsgate
# - Point VoIP.ms webhook to bridge
```

**Phase 4: Setup Linphone** (5 min manual)
```bash
# Install Linphone app
# Add SIP account (VoIP.ms credentials)
# Enable call forwarding via Fossify
# Test messaging
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
- ✅ No VoIP.ms number for messages
- ✅ Carrier-grade reliability
- ✅ Works with shortcodes (2FA)

### Single App Experience

Everything in Linphone:
- ✅ Voice calls (VoIP.ms)
- ✅ SMS messaging
- ✅ MMS messaging
- ✅ Standard SIP interface

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
- VoIP.ms API proxy (intercepts mmsgate)
- Webhook receiver (from Fossify)
- Message router (cellular ↔ SIP)
- Stateless, simple, reliable

**Code:** `bridge-server/sms-bridge-server.py`

### 3. mmsgate (VPS)

**VoIP.ms ↔ SIP MESSAGE converter**
- Converts between VoIP.ms API and SIP
- Handles MMS media
- Works with standard SIP clients

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
- **mmsgate:** Username/password
- **VoIP.ms:** Account credentials

### Encryption

- **SIP transport:** TLS (port 5061)
- **HTTP webhooks:** HTTPS with valid certificates
- **WireGuard VPN:** Encrypted tunnel for Fossify API access (10.0.0.0/24)

### Network Exposure

- **Fossify:** Not exposed (WireGuard VPN only, 10.0.0.2)
- **WireGuard:** UDP port 51820 (encrypted VPN tunnel)
- **Bridge:** HTTPS with authentication
- **mmsgate:** HTTPS with authentication
- **Flexisip:** TLS SIP only

## Costs

### One-Time
- **Android phone:** $0 (use existing old phone)

### Monthly
- **VPS:** $1.50/month
- **Cellular SIM + plan:** $8.00/month
- **VoIP.ms DID:** $0.85/month
- **Domain:** Free (already own)
- **SSL:** $0 (Let's Encrypt)
- **WireGuard VPN:** $0 (open source)

**Total: ~$10.35/month**

Compare to:
- International roaming: $50-100/month
- Separate VoIP number: Doesn't work for banking
- Google Fi: $70-80/month for international

## Advantages Over Alternatives

### vs Android SMS Gateway + Telegram

| Feature          | Android SMS Gateway | This Solution      |
| ---------------- | ------------------- | ------------------ |
| MMS sending      | ❌ No                | ✅ Yes              |
| Interface        | Telegram (separate) | Linphone (unified) |
| Calls + messages | 2 apps              | 1 app              |
| Code control     | Limited             | Full               |

### vs VoIP.ms SMS Only

| Feature              | VoIP.ms SMS | This Solution             |
| -------------------- | ----------- | ------------------------- |
| Real cellular number | ❌ No        | ✅ Yes (via WireGuard VPN) |
| Banking compatible   | ⚠️ Sometimes | ✅ Always                  |
| Shortcodes (2FA)     | ❌ No        | ✅ Yes                     |
| Carrier-grade        | ❌ No        | ✅ Yes                     |
| Phone at home        | ❌ N/A       | ✅ Connected via VPN       |

### vs Dual SIM + International Plan

| Feature          | International Plan | This Solution        |
| ---------------- | ------------------ | -------------------- |
| Monthly cost     | $50-100            | $27-37               |
| Works everywhere | ⚠️ Some countries   | ✅ With internet      |
| Battery drain    | High               | None (phone at home) |

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
- **VoIP.ms:** https://voip.ms

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
