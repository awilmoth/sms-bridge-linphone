# SMS Bridge Deployment - Template & Reference

> **⚠️ IMPORTANT:** This is a template file. Do NOT commit your actual `DEPLOYMENT.md` with real secrets to git!
> 
> Keep your actual `DEPLOYMENT.md` locally with your real credentials. Add it to `.gitignore` (already done).

## ✅ Completed Phases

### Phase 0: WireGuard VPN Setup
- ✅ VPS provisioned: `[your-vps-hostname]` (IP: `[your-vps-ip]`)
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

### Phase 2: Docker Image Build

The remote setup script is building three Docker image layers sequentially:

1. **Flexisip layer** (5-10 min) - SIP proxy infrastructure
2. **PJSIP layer** (5-10 min) - Telephony library
3. **mmsgate layer** (5-10 min) - SMS/MMS ↔ SIP converter

All three are built from source and cached in the local Docker registry.

**To monitor progress:**

```bash
cd scripts/
./monitor-build.sh [your-vps-hostname] root
```

## 📋 Next Steps (After Build Completes)

### Step 1: Start Docker Containers

Once all three mmsgate layers are built, the script auto-starts containers.

Verify containers are running:

```bash
ssh -i ~/.ssh/id_ed25519 root@[your-vps-hostname] 'cd sms-bridge-linphone/bridge-server && docker-compose ps'
```

### Step 2: Test Bridge Server Health

```bash
ssh -i ~/.ssh/id_ed25519 root@[your-vps-hostname] 'curl http://localhost:5000/health'
```

### Step 3: Test WireGuard Connection

**From VPS:**
```bash
ssh -i ~/.ssh/id_ed25519 root@[your-vps-hostname] 'ping 10.0.0.2'
```

### Step 4: Configure Fossify Messages on Android

- **API Server URL:** `http://10.0.0.1:5000` (via WireGuard VPN)
- **Port:** `8080`
- **Auth Token:** `[your-fossify-token-from-setup]`
- **Webhook URL:** `https://bridge.[your-domain]:5000/webhook/fossify`
- **Webhook Token:** `[same-as-auth-token]`

### Step 5: Install Linphone

1. Download Linphone from [linphone.org](https://linphone.org)
2. Create SIP account:
   - **Username:** Choose any username
   - **Password:** Choose any strong password
   - **Domain:** `sip.[your-domain]`
   - **Transport:** TLS (port 5061)

### Step 6: Test End-to-End

Send a test message from Linphone to verify the flow works.

## 📊 Service Architecture Running on VPS

```
Docker Containers (on private network):
├─ sms-bridge:5000 (message router)
├─ mmsgate (with Flexisip built-in)
│  ├─ Port 5060 (SIP)
│  ├─ Port 5061 (SIP TLS)
│  └─ Ports 10000-20000 (RTP/media)
├─ monitor (health checks + SMTP alerts)
├─ registry:5001 (Docker image cache)
└─ WireGuard VPN:51820 (Android tunnel)

Public Firewall (UFW):
├─ 22/tcp (SSH)
├─ 51820/udp (WireGuard)
├─ 5060/tcp (SIP)
├─ 5061/tcp (SIP TLS)
└─ 10000-20000/udp (RTP)
```

## 🔧 Useful Commands

**Check service logs:**
```bash
ssh -i ~/.ssh/id_ed25519 root@[your-vps] 'cd sms-bridge-linphone/bridge-server && docker-compose logs -f sms-bridge'
```

**Restart services:**
```bash
ssh -i ~/.ssh/id_ed25519 root@[your-vps] 'cd sms-bridge-linphone/bridge-server && docker-compose restart'
```

**View WireGuard status:**
```bash
ssh -i ~/.ssh/id_ed25519 root@[your-vps] 'sudo wg show'
```

**Check UFW firewall:**
```bash
ssh -i ~/.ssh/id_ed25519 root@[your-vps] 'sudo ufw status'
```

## 🐛 Troubleshooting

**Bridge health check fails:**
- Check if containers are running: `docker-compose ps`
- Check logs: `docker-compose logs sms-bridge`

**WireGuard not connecting:**
- Check VPS WireGuard status: `sudo wg show`
- Verify firewall allows 51820/udp: `sudo ufw status`

**Fossify not reaching bridge:**
- Verify WireGuard VPN is connected on Android
- Check Fossify API URL matches bridge IP
- Verify auth tokens match

## 📝 Your Saved Credentials (Keep Locally Only!)

⚠️ **NEVER commit this to git!** Keep in `DEPLOYMENT.md` locally only:

```
VPS Hostname: [your-vps-hostname]
VPS IP: [your-vps-ip]
VPS Internal IP (WireGuard): 10.0.0.1
Android IP (WireGuard): 10.0.0.2

WireGuard Server Key: [your-key]
WireGuard Client Key: [your-key]

FOSSIFY_AUTH_TOKEN: [your-token]
BRIDGE_SECRET: [your-secret]
```

## 📚 Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Technical details
- [QUICKSTART.md](docs/QUICKSTART.md) - Step-by-step guide
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues

---

**Reference:** Use this template to create your local `DEPLOYMENT.md`
