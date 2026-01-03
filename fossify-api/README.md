# Adding API to Fossify Messages

This directory contains the code you need to add to Fossify Messages to enable HTTP API control.

## Quick Start - Download APK

Pre-built APK with API integration is available at:
- **GitHub**: [https://github.com/awilmoth/Messages](https://github.com/awilmoth/Messages)
- **Actions Tab**: [https://github.com/awilmoth/Messages/actions](https://github.com/awilmoth/Messages/actions)

Look for the latest successful build in the Actions tab, download the `fossify-api-debug` artifact.

## Files

- `ApiServer.kt` - Native Java socket server implementation
- `ApiService.kt` - Background service to run the server
- `SmsReceiver.kt` - Webhook client modifications

## Integration Steps

### 1. Fork Fossify Messages

```bash
# On GitHub, fork: https://github.com/FossifyOrg/Messages
git clone https://github.com/YOUR_USERNAME/Messages.git
cd Messages
git checkout -b add-api-server
```

### 2. Add API Server Code

Copy `ApiServer.kt` to:
```
app/src/main/java/org/fossify/messages/api/ApiServer.kt
```

Copy `ApiService.kt` to:
```
app/src/main/java/org/fossify/messages/api/ApiService.kt
```

**Note**: The API server uses native Java sockets and requires no external dependencies beyond the Android SDK.

### 3. Modify SMS Receiver

Add webhook notification code from `SmsReceiver.kt` to your existing SMS/MMS receiver.

Location: `app/src/main/java/org/fossify/messages/receivers/SmsReceiver.kt`

### 4. Add to AndroidManifest.xml

```xml
<service
    android:name=".api.ApiService"
    android:enabled="true"
    android:exported="false" />

<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

Add settings section to allow user to configure:
- Enable API (checkbox)
- API Port (default: 8080)
- API Auth Token (generate random)
- Webhook URL
- Webhook Auth Token

### 5. Start Service

In your MainActivity or Application class:

```kotlin
if (config.isApiEnabled) {
    startService(Intent(this, ApiService::class.java))
}
```

### 6. Build & Deploy

**Manual Build:**
```bash
./gradlew assembleDebug
adb install app/build/outputs/apk/foss/debug/app-debug.apk
```

**Automated Builds:**
The GitHub Actions workflow automatically builds on every push. Get the APK:
1. Go to [GitHub Actions](https://github.com/awilmoth/Messages/actions)
2. Click the latest successful build
3. Download `fossify-api-debug` artifact
4. Install: `adb install app-debug.apk`

## API Endpoints

The API server runs on port 8080 and provides:

**GET /api/status**
```json
{
  "status": "running",
  "port": 8080
}
```

**GET /api/send-sms**
```json
{
  "status": "queued"
}
```

All other endpoints return 404.

## Security

The API server runs on localhost (127.0.0.1) by default. Expose via:

### WireGuard VPN (Recommended)

Use WireGuard tunnel to securely access the API from another device:
- Android device: 10.0.0.2:8080  
- Host machine: 10.0.0.1:8080

See [WIREGUARD-SETUP.md](../WIREGUARD-SETUP.md) for configuration.

### ngrok (Quick Testing)

```bash
# Via Termux on Android
pkg install ngrok
ngrok http 8080
```

## Testing

```bash
# Health check (via WireGuard VPN)
curl http://10.0.0.2:8080/health

# Send SMS (via WireGuard VPN)
curl -X POST http://10.0.0.2:8080/send_sms \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+15551234567","message":"test"}'
```

## Troubleshooting

**Server not starting:**
- Check logs: `adb logcat | grep ApiServer`
- Verify port not in use
- Check permissions granted

**Can't connect:**
- Verify firewall allows port 8080
- Check phone is on same network
- Test with: `curl http://PHONE_IP:8080/health`

**Webhooks not sending:**
- Check webhook URL configured
- Verify webhook token set
- Check bridge server logs

## Notes

- API server runs on main thread - keep handlers fast
- Use WorkManager for long-running operations
- Webhook calls are async (don't block SMS receive)
- Store auth tokens securely (EncryptedSharedPreferences)

## Contributing

If you improve the API implementation:
1. Test thoroughly
2. Update this README
3. Consider submitting upstream to Fossify
