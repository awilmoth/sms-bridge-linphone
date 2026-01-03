# SMS/MMS Bridge - Fossify Build Status & Next Steps

## Current Status (January 3, 2026)

### ✅ Completed
- **Bridge Server**: Running on VPS (sip-us.aaronwilmoth.org)
  - sms-bridge (Flask): ✅ Healthy
  - mmsgate: ✅ Running 
  - local-registry: ✅ Running
  - Bridge health check: ✅ Responds correctly

- **Network**: WireGuard VPN ready
  - Server: 10.0.0.1 (VPS)
  - Client: 10.0.0.2 (Android) - waiting for connection

- **Configuration**: All set
  - flexisip.conf: ✅ Deployed
  - mmsgate.conf: ✅ Deployed (fixed)
  - .env: ✅ Loaded
  - test-endpoints.sh: ✅ Fixed and working

### 🔄 In Progress
- **Fossify APK Build**: Currently building (Docker-based)
  - Start time: Jan 3, 01:20 UTC
  - Method: Docker container with Android SDK
  - Status: Downloading thyrlian/android-sdk image (~4GB)
  - ETA: 10-30 minutes

### ⏳ Pending
- APK installation on Android device
- Fossify API server configuration
- Bridge ↔ Fossify integration test
- SMS/MMS sending test

---

## Build Progress

**Monitor build status:**

```bash
# Check if APK exists
ls -lh ~/Code/sms-bridge-linphone/build/*.apk 2>/dev/null || echo "Still building..."

# View full build log
tail -f ~/Code/sms-bridge-linphone/build.log

# When complete:
#   File: ~/Code/sms-bridge-linphone/build/app-debug.apk
```

**What's happening:**

1. Docker image `thyrlian/android-sdk:latest` is being pulled (1st time only)
2. Fossify Messages repo is cloned to `/home/aaron/Code/fossify-messages`
3. API files (ApiServer.kt, ApiService.kt) are copied into Fossify
4. Gradle builds the APK with Android SDK tools
5. Result copied to `~/Code/sms-bridge-linphone/build/`

---

## Installation Checklist

Once APK is built, follow these steps in order:

### Phase 1: Prepare Android Device (Day 1)
- [ ] Android phone powered on, connected to internet/WiFi
- [ ] Plug in phone (will stay plugged in)
- [ ] Enable Developer Options: Settings → About → Tap Build Number 7x
- [ ] Enable USB Debugging: Developer Options → USB Debugging → ON
- [ ] Connect to computer via USB

### Phase 2: Install Fossify (Day 1)
```bash
# When APK is ready:
adb devices  # Verify phone appears
adb install ~/Code/sms-bridge-linphone/build/app-debug.apk
```

- [ ] APK installs successfully
- [ ] Fossify Messages app opens
- [ ] Grant requested permissions (SMS, MMS, etc.)

### Phase 3: Configure WireGuard (Day 1)

On Android phone:
1. Download WireGuard app from Play Store
2. Create new tunnel from QR code or config file
   - Config: `/root/wg_configs/android.conf` on VPS
3. Enable VPN connection: VPN appears in status bar
4. Verify connection: Disconnect/reconnect a few times

Commands to get WireGuard config:
```bash
ssh root@sip-us.aaronwilmoth.org
cat /root/wg_configs/android.conf | qrencode -t UTF8
# Or display as QR code to scan
```

### Phase 4: Configure Fossify API (Day 1)

In Fossify Messages on Android:

1. Open **Settings** (menu icon → Settings)
2. Scroll to **API Server** section
3. Toggle **Enable API**: **ON**
4. Set **Port**: `8080`
5. Set **Auth Token**: Copy from below OR generate new
6. Set **Webhook URL**: `http://10.0.0.1:5000/webhook/fossify`
7. Set **Webhook Auth Token**: (See below)
8. **Save** changes

**Getting tokens:**

```bash
# SSH to VPS
ssh root@sip-us.aaronwilmoth.org

# Get Bridge secret
grep BRIDGE_SECRET /root/sms-bridge-linphone/bridge-server/.env

# Use as both auth tokens
# Example: abcd1234ef5678...
```

### Phase 5: Verify Connection (Day 1)

```bash
# On your local machine:
# Test 1: Can bridge reach Fossify?
ssh root@sip-us.aaronwilmoth.org << 'EOF'
docker exec sms-bridge curl -s http://10.0.0.2:8080/health | jq '.'
EOF

# Expected: {"status":"ok","version":"1.0"}

# Test 2: Full integration test
cd ~/Code/sms-bridge-linphone/bridge-server
bash ../scripts/test-endpoints.sh
# Answer 'n' to all Fossify prompts (API not ready yet)
```

Expected results:
- ✅ Bridge health: OK
- ✅ mmsgate: Running
- ⚠ Fossify API: Not yet deployed (but reachable once phone connected)

### Phase 6: Configure Linphone (Day 2)

On your Linphone client (laptop/desktop):

1. **Settings** → **Accounts**
2. **Add SIP Account** (if not exists)
3. Set up account with your VoIP provider
4. Account type: `sip`
5. Registrar: Your VoIP.ms or other provider settings
6. **Save**

Now Linphone will route SMS/MMS through the bridge to your cellular number!

---

## Architecture Summary

Once everything is set up:

```
OUTGOING MESSAGE (Linphone → Phone number):
  Linphone app
    ↓ SIP MESSAGE
  mmsgate (processes via Bridge)
    ↓ HTTP API
  Fossify (on Android)
    ↓ Cellular network
  Recipient

INCOMING MESSAGE (Phone number → Linphone):
  Sender
    ↓ Cellular network
  Fossify (receives SMS/MMS)
    ↓ Webhook (via WireGuard VPN)
  Bridge (routes to Linphone)
    ↓ SIP MESSAGE
  Linphone (notifications)
```

---

## Troubleshooting Quick Ref

### "adb: command not found"
```bash
# Install Android tools
sudo apt-get install -y android-tools-adb android-tools-fastboot
```

### "error: device not found" in adb
```bash
# Check USB connection
lsusb | grep -i android

# Restart adb
adb kill-server
adb start-server
adb devices
```

### Fossify API won't start
- Verify WireGuard is connected on Android (check VPN status)
- Check port 8080 is free on Android
- Restart Fossify app: Force close + reopen

### Bridge can't reach Fossify
```bash
# From VPS:
ping -c 1 10.0.0.2  # Should succeed if Android VPN is active

# Check firewall
ufw status
# Should show: 10.0.0.2 allowed
```

### SMS won't send
1. Verify Linphone account is registered
2. Check Bridge logs: `docker logs sms-bridge`
3. Check mmsgate logs: `docker logs mmsgate`

---

## Key Files & Locations

| Purpose          | Location                                                     |
| ---------------- | ------------------------------------------------------------ |
| Build script     | `~/Code/sms-bridge-linphone/scripts/build-fossify-docker.sh` |
| Build output     | `~/Code/sms-bridge-linphone/build/`                          |
| Build logs       | `~/Code/sms-bridge-linphone/build.log`                       |
| Fossify source   | `~/Code/fossify-messages/`                                   |
| API patches      | `~/Code/sms-bridge-linphone/fossify-api/`                    |
| Bridge server    | `/root/sms-bridge-linphone/` (on VPS)                        |
| WireGuard config | `/root/wg_configs/` (on VPS)                                 |

---

## Timeline Estimate

- **Build**: 10-30 min (currently running)
- **Installation & Setup**: 15-30 min
- **Configuration**: 15-30 min
- **Testing**: 10-15 min
- **Total**: ~2 hours from now

Once complete, you'll have:
- ✅ Full SMS/MMS bridge working
- ✅ Messages in Linphone from your real number
- ✅ Two-way communication
- ✅ Secure WireGuard tunnel
- ✅ Self-hosted (privacy + control)

---

## Commands Summary

```bash
# Monitor build
tail -f ~/Code/sms-bridge-linphone/build.log

# Check APK ready
ls -lh ~/Code/sms-bridge-linphone/build/*.apk

# Install when ready
adb install ~/Code/sms-bridge-linphone/build/app-debug.apk

# Run tests
cd ~/Code/sms-bridge-linphone/bridge-server
bash ../scripts/test-endpoints.sh

# View bridge status
ssh root@sip-us.aaronwilmoth.org "cd /root/sms-bridge-linphone/bridge-server && docker ps"
```

---

**Status**: Build in progress ✨ Check back in 15-30 minutes for APK!
