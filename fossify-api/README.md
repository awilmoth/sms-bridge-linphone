# Adding API to Fossify Messages

This directory contains the code you need to add to Fossify Messages to enable HTTP API control.

## Files

- `ApiServer.kt` - NanoHTTPD server implementation
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

### 2. Add Dependencies

Edit `app/build.gradle.kts`, add to dependencies section:

```kotlin
dependencies {
    // Existing dependencies...
    
    // HTTP server
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    implementation("com.google.code.gson:gson:2.10.1")
}
```

### 3. Add API Server Code

Copy `ApiServer.kt` to:
```
app/src/main/java/org/fossify/messages/api/ApiServer.kt
```

Copy `ApiService.kt` to:
```
app/src/main/java/org/fossify/messages/api/ApiService.kt
```

### 4. Modify SMS Receiver

Add webhook notification code from `SmsReceiver.kt` to your existing SMS/MMS receiver.

Location: `app/src/main/java/org/fossify/messages/receivers/SmsReceiver.kt`

### 5. Add to AndroidManifest.xml

```xml
<service
    android:name=".api.ApiService"
    android:enabled="true"
    android:exported="false" />

<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### 6. Add Settings UI

Add settings section to allow user to configure:
- Enable API (checkbox)
- API Port (default: 8080)
- API Auth Token (generate random)
- Webhook URL
- Webhook Auth Token

### 7. Start Service

In your MainActivity or Application class:

```kotlin
if (config.isApiEnabled) {
    startService(Intent(this, ApiService::class.java))
}
```

### 8. Build APK

```bash
# Debug build
./gradlew assembleDebug

# Release build
./gradlew assembleRelease
```

### 9. Sign APK (Release Only)

```bash
keytool -genkey -v -keystore my-release-key.jks \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias my-key-alias

jarsigner -verbose -sigalg SHA256withRSA -digestalg SHA-256 \
    -keystore my-release-key.jks \
    app/build/outputs/apk/release/app-release-unsigned.apk \
    my-key-alias

zipalign -v 4 \
    app/build/outputs/apk/release/app-release-unsigned.apk \
    fossify-messages-api.apk
```

### 10. Install

```bash
adb install fossify-messages-api.apk
```

## API Endpoints

Once installed and configured, the app exposes:

**POST /send_sms**
```json
{
  "phoneNumber": "+15551234567",
  "message": "Hello from API"
}
```

**POST /send_mms**
```json
{
  "phoneNumber": "+15551234567",
  "message": "Hello from API",
  "attachments": ["base64_encoded_image_data"]
}
```

**GET /health**
```json
{
  "status": "ok",
  "server": "fossify-api"
}
```

## Security

**API Auth Token:**
- Generate with: `openssl rand -hex 32`
- Include in requests: `Authorization: Bearer YOUR_TOKEN`

**Webhook Auth Token:**
- Generate with: `openssl rand -hex 32`
- App includes in webhook calls: `Authorization: Bearer YOUR_TOKEN`

## Exposing API

### Option A: WireGuard VPN (Recommended)

**Setup WireGuard tunnel (10.0.0.2 ↔ 10.0.0.1) via complete-setup.sh**

```bash
# Access via: http://10.0.0.2:8080
```

This is the most secure option - the API is accessible only when connected to the WireGuard VPN.

### Option B: ngrok

```bash
# On Android via Termux
pkg install ngrok
ngrok http 8080
# Get URL: https://abc123.ngrok.io
```

### Option C: Port Forward

Forward port 8080 on your router to Android phone's IP.

**Not recommended** - use WireGuard instead for security.

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
