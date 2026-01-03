# Fossify Messages APK Build Guide

## Quick Start

The APK build process has been automated and is running. Check build status with:

```bash
ls -lh ~/Code/sms-bridge-linphone/build/*.apk
```

## Build Methods

### Method 1: Docker Build (Recommended - Currently Running)

```bash
cd ~/Code/sms-bridge-linphone
bash scripts/build-fossify-docker.sh
```

**Status**: Docker image `thyrlian/android-sdk` is downloading (~4GB)
- Estimated time: 10-30 minutes depending on internet
- Will auto-complete and copy APK to `build/`

### Method 2: Local Build (Requires JDK 17+)

If you want to build locally after Docker completes:

```bash
cd ~/Code/fossify-messages
./gradlew assembleDebug
```

Output APK will be at:
```
app/build/outputs/apk/debug/app-debug.apk
```

## Manual Integration (If Needed)

If Docker build doesn't work, here's how to integrate manually:

### Step 1: Clone Fossify (Already Done)

```bash
cd ~/Code
git clone https://github.com/FossifyOrg/Messages.git fossify-messages
cd fossify-messages
```

### Step 2: Copy API Files

```bash
mkdir -p app/src/main/java/org/fossify/messages/api
cp ~/Code/sms-bridge-linphone/fossify-api/*.kt \
   app/src/main/java/org/fossify/messages/api/
```

### Step 3: Add Dependencies to build.gradle.kts

```kotlin
dependencies {
    // Add to existing dependencies block:
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    implementation("com.google.code.gson:gson:2.10.1")
}
```

### Step 4: Update AndroidManifest.xml

Add after the closing `</application>` tag:

```xml
<service
    android:name=".api.ApiService"
    android:enabled="true"
    android:exported="false" />

<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

Exactly where: Find `</manifest>` at the end and add permissions BEFORE it.

### Step 5: Modify SmsReceiver.kt

In `app/src/main/java/org/fossify/messages/receivers/SmsReceiver.kt`, add webhook notification:

From `~/Code/sms-bridge-linphone/fossify-api/SmsReceiver.kt`, copy the webhook client code and integrate it into the onReceive() method.

### Step 6: Build

```bash
cd ~/Code/fossify-messages
./gradlew assembleDebug
```

## Installation on Android

### Prerequisites
- Android phone connected via USB
- USB debugging enabled in Developer Options
- `adb` command-line tool installed

### Install Debug APK

```bash
# Find the APK
APK_FILE=$(find ~/Code/sms-bridge-linphone/build -name "*.apk" | head -1)

# Install
adb install "$APK_FILE"

# Or from fossify-messages directory:
adb install app/build/outputs/apk/debug/app-debug.apk
```

### Enable API Server in Fossify

After installation:

1. **Open Fossify Messages** on Android
2. **Settings** (or menu icon)
3. **API Server** section
4. Enable: **ON**
5. Set **Port**: 8080
6. Set **Auth Token**: Generate a random token (e.g., `openssl rand -hex 32`)
7. **Webhook URL**: 
   ```
   http://10.0.0.1:5000/webhook/fossify
   ```
8. **Webhook Auth Token**: Use same as BRIDGE_SECRET from `/root/sms-bridge-linphone/bridge-server/.env`
9. **Save**

### Verify Connection

From VPS:
```bash
ssh root@your-vps -c 'curl http://10.0.0.2:8080/health 2>/dev/null | jq .'
```

Expected response:
```json
{
  "status": "ok",
  "version": "1.0"
}
```

## Troubleshooting

### APK won't install
```bash
# Check device
adb devices

# Uninstall old version
adb uninstall org.fossify.messages

# Try debug APK (requires developer mode)
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### API server won't start
- Check WireGuard is connected (Android status → VPN active)
- Check port 8080 is not in use: `adb shell netstat | grep 8080`
- Check Fossify logs: Settings → About → Log viewer

### Bridge can't reach Fossify
```bash
# From VPS bridge container
docker exec sms-bridge bash -c 'curl http://10.0.0.2:8080/health'

# Check WireGuard on Android
ifconfig wg0  # should show 10.0.0.2
```

## Testing

Once installed and running:

```bash
cd ~/Code/sms-bridge-linphone/bridge-server

# Test bridge can reach Fossify API
bash ../scripts/test-endpoints.sh
# Answer 'n' to Fossify API test (Fossify not deployed yet)
```

## API Files Reference

The following files were integrated:

- **ApiServer.kt** - NanoHTTPD server handling API requests
- **ApiService.kt** - Android service managing the server lifecycle
- **SmsReceiver.kt** - SMS/MMS webhook notifications back to bridge

These implement:

| Endpoint    | Method | Purpose              |
| ----------- | ------ | -------------------- |
| `/health`   | GET    | Server health check  |
| `/send`     | POST   | Send SMS via Fossify |
| `/send_mms` | POST   | Send MMS via Fossify |

## Next Steps

1. **Wait for build to complete**
   ```bash
   # Monitor build
   watch -n 5 'ls -lh ~/Code/sms-bridge-linphone/build/'
   ```

2. **Install on Android device** (once APK is built)
   ```bash
   adb install ~/Code/sms-bridge-linphone/build/app-debug.apk
   ```

3. **Configure API in Fossify settings** on Android

4. **Run full integration test**
   ```bash
   cd ~/Code/sms-bridge-linphone/bridge-server
   bash ../scripts/test-endpoints.sh
   ```

5. **Test SMS sending** once everything is connected
