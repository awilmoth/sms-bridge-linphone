# SMS Bridge Deployment - Current Status & Next Steps

## ✅ Completed Phases

### Phase 0: WireGuard VPN Setup
- ✅ VPS provisioned: `sip-us.aaronwilmoth.org` (IP: 192.227.231.7)
- ✅ WireGuard installed and configured
- ✅ Server VPN IP: 10.0.0.1
- ✅ Android client VPN IP: 10.0.0.2
- ✅ UFW firewall configured (SSH, WireGuard, SIP ports open)
- ✅ Android WireGuard config generated

**Your WireGuard files:**
- `android-wireguard.conf` — Import into WireGuard Android app
- `android-wireguard-qr.png` — QR code for easy setup

### Phase 1: Repository & Environment
- ✅ Repository cloned to VPS at `/root/sms-bridge-linphone`
- ✅ Bridge `.env` configuration generated
- ✅ Docker and docker-compose installed

## 🔨 Currently In Progress

### Phase 2: Docker Image Build (15-25 minutes)

The remote setup script is building three Docker image layers sequentially:

1. **Flexisip layer** (5-10 min) - SIP proxy infrastructure
2. **PJSIP layer** (5-10 min) - Telephony library
3. **mmsgate layer** (5-10 min) - SMS/MMS ↔ SIP converter

All three are built from source and cached in the local Docker registry at `localhost:5001/mmsgate:latest`.

**To monitor progress:**

```bash
cd scripts/
./monitor-build.sh sip-us.aaronwilmoth.org root
```

This will show you which layers have completed and estimate remaining time.

**Alternative (manual check):**

```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'docker image ls | grep -E "flexisip|pjsip|mmsgate"'
```

## 📋 Next Steps (After Build Completes)

### Step 1: Start Docker Containers

Once all three mmsgate layers are built, start the full stack:

```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org '
cd sms-bridge-linphone/bridge-server
docker-compose up -d
'
```

This will start:
- `sms-bridge` (Flask API server on port 5000)
- `mmsgate` (SIP MESSAGE handler on ports 5060/5061)
- `monitor` (Health check service)
- `registry` (Local Docker image cache)

**Verify containers are running:**

```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'cd sms-bridge-linphone/bridge-server && docker-compose ps'
```

### Step 2: Test Bridge Server Health

```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'curl http://localhost:5000/health'
```

Expected response:
```json
{"status": "healthy", "bridge": "up"}
```

### Step 3: Test WireGuard Connection

**On Android:**
1. Install WireGuard from Google Play
2. Import `android-wireguard.conf` or scan the QR code
3. Enable VPN and verify connection

**From VPS:**
```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'ping 10.0.0.2'
```

Should see ping responses from Android at 10.0.0.2.

### Step 4: Configure Fossify Messages on Android

Install your modified Fossify APK and configure:

- **API Server URL:** `http://10.0.0.1:5000` (VPS via WireGuard)
- **Port:** `8080`
- **Auth Token:** `63966f0eb7db749088229099722521d64544103e970cef922c31d62385cca332`
- **Webhook URL:** `https://bridge.sip-us.aaronwilmoth.org:5000/webhook/fossify`
- **Webhook Token:** `63966f0eb7db749088229099722521d64544103e970cef922c31d62385cca332`

### Step 5: Install Linphone

**On your computer/phone:**
1. Download Linphone from [linphone.org](https://linphone.org)
2. Create SIP account:
   - **Username:** Choose any username (e.g., `your-name`)
   - **Password:** Choose any strong password
   - **Domain:** `sip.sip-us.aaronwilmoth.org`
   - **Transport:** TLS (port 5061)

3. Enable push notifications and accept the account

### Step 6: Test End-to-End

**Send a message from Linphone:**
1. Open Linphone
2. Go to Chat
3. Start new chat with any contact
4. Type and send a message
5. Message should appear on Android phone as an SMS

**Receive a message on Linphone:**
1. Have someone text your Android phone
2. Fossify on Android receives SMS
3. Message is forwarded to bridge
4. Bridge sends to mmsgate
5. mmsgate delivers to Linphone via SIP MESSAGE
6. Notification appears in Linphone

## 📊 Service Architecture Running on VPS

```
Docker Containers (all on private network):
├─ sms-bridge:5000 (message router)
│  └─ Receives from Fossify, routes to mmsgate
├─ mmsgate (with Flexisip built-in)
│  ├─ Port 5060 (SIP)
│  ├─ Port 5061 (SIP TLS)
│  └─ Ports 10000-20000 (RTP/media)
├─ monitor (health checks + SMTP alerts)
├─ registry:5001 (Docker image cache)
└─ WireGuard VPN:51820 (connects to Android)

Public Firewall (UFW):
├─ 22/tcp (SSH)
├─ 51820/udp (WireGuard)
├─ 443/tcp (HTTPS reverse proxy - future)
├─ 5060/tcp (SIP)
├─ 5061/tcp (SIP TLS)
└─ 10000-20000/udp (RTP)
```

## 🔧 Useful Commands

**Check service logs:**
```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'cd sms-bridge-linphone/bridge-server && docker-compose logs -f sms-bridge'
```

**Restart services:**
```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'cd sms-bridge-linphone/bridge-server && docker-compose restart'
```

**View WireGuard status:**
```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'sudo wg show'
```

**Check UFW firewall:**
```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'sudo ufw status'
```

**View container resource usage:**
```bash
ssh -i ~/.ssh/id_ed25519 root@sip-us.aaronwilmoth.org 'docker stats'
```

## 🐛 Troubleshooting

**Bridge health check fails:**
- Check if containers are running: `docker-compose ps`
- Check logs: `docker-compose logs sms-bridge`
- May need to wait 30-60 seconds for startup

**WireGuard not connecting:**
- Check VPS WireGuard status: `sudo wg show`
- Verify firewall allows 51820/udp: `sudo ufw status`
- Restart WireGuard: `sudo systemctl restart wg-quick@wg0`

**mmsgate not receiving SIP messages:**
- Check mmsgate logs: `docker-compose logs mmsgate`
- Verify Linphone can connect to SIP server
- Check firewall allows 5060/5061

**Fossify not reaching bridge:**
- Verify WireGuard VPN is connected on Android
- Check Fossify API URL is `http://10.0.0.1:5000`
- Verify auth token matches in both Fossify and bridge

## 📝 Your Saved Credentials

Keep these safe! You'll need them for configuration:

```
VPS Hostname: sip-us.aaronwilmoth.org
VPS IP: 192.227.231.7
VPS Internal IP (WireGuard): 10.0.0.1
Android IP (WireGuard): 10.0.0.2

WireGuard Server Key: qz/gbwWuUwunxg69lHQmBAUCbF3ijsdypUxSBtJoe0g=
WireGuard Client Key: aZ4Px7SRNni+W9dgKD5mmNa1gUjvmUJpqn87pgGeT1s=

FOSSIFY_AUTH_TOKEN: 63966f0eb7db749088229099722521d64544103e970cef922c31d62385cca332
BRIDGE_SECRET: 424f007cece1bb32128448802b5f55304f1ac0175fe48dcbf9ad4f76f7540c7e
```

## 📚 Documentation

For detailed information, see:
- [ARCHITECTURE.md](../docs/ARCHITECTURE.md) - Technical details
- [QUICKSTART.md](../docs/QUICKSTART.md) - Step-by-step guide
- [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - Common issues
- [fossify-api/README.md](../fossify-api/README.md) - Building Fossify

---

**Last updated:** January 3, 2026
**Deployment status:** Phase 2 (Docker build in progress)
