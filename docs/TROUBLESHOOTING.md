# Troubleshooting Guide

Common issues and solutions for the SMS Bridge system.

## Bridge Server Issues

### Bridge won't start

**Check Docker:**
```bash
docker ps
docker-compose logs bridge
```

**Common causes:**
- Port 5000 already in use
- Missing .env file
- Invalid configuration

**Solutions:**
```bash
# Check port
sudo lsof -i :5000

# Verify .env
cat .env

# Rebuild
docker-compose down
docker-compose up --build
```

### Bridge returns 401 Unauthorized

**Cause:** Authentication token mismatch

**Check:**
- Fossify webhook token matches BRIDGE_SECRET
- mmsgate isn't sending auth headers

**Solution:**
```bash
# Verify tokens match
grep BRIDGE_SECRET .env
# Use this token in Fossify webhook config
```

## Fossify API Issues

### Can't connect to Fossify API

**Check:**
```bash
# Ping WireGuard Android
ping 10.0.0.2

# Test API (from VPS via WireGuard VPN)
curl http://10.0.0.2:8080/health
```

**Common causes:**
- WireGuard VPN not running on Android
- API server not started in Fossify
- Firewall blocking port 8080
- FOSSIFY_API_URL in .env pointing to wrong IP

**Solutions:**
```bash
# Verify WireGuard is active on Android
# Check Fossify settings → API Server → Enabled

# Test from VPS (must be on same WireGuard network)
curl http://10.0.0.2:8080/health

# If that fails, check WireGuard status:
wg show
sudo wg-quick status
```

### Fossify returns 401

**Cause:** Auth token mismatch

**Solution:**
```bash
# Get token from Fossify settings
# Update .env:
FOSSIFY_AUTH_TOKEN=<token_from_fossify>

# Restart bridge
docker-compose restart
```

## Message Flow Issues

### Messages not arriving in Linphone

**Diagnostic steps:**

1. **Test Fossify → Bridge:**
```bash
# Check bridge logs
docker-compose logs -f bridge

# Manually trigger
curl -X POST http://localhost:5000/webhook/fossify \
  -H "Authorization: Bearer YOUR_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+15551234567","message":"test"}'
```

2. **Test Bridge → mmsgate:**
```bash
# Check mmsgate logs
docker-compose logs -f mmsgate

# Verify webhook configured
curl https://mms.your-domain.com/health
```

3. **Test mmsgate → Linphone:**
- Check Linphone SIP registration
- Verify Flexisip routing
- Check Flexisip logs

### Messages not sending from Linphone

**Diagnostic steps:**

1. **Test Linphone → mmsgate:**
- Send test message in Linphone
- Check mmsgate logs for incoming SIP MESSAGE

2. **Test mmsgate → Bridge:**
```bash
# Should see in bridge logs:
docker-compose logs bridge | grep voipms

# Manually test proxy:
curl "http://localhost:5000/voipms/api?method=sendSMS&dst=15551234567&message=test"
```

3. **Test Bridge → Fossify:**
```bash
# Should see POST to Fossify
# Check Fossify can send (via WireGuard VPN):
curl -X POST http://10.0.0.2:8080/send_sms \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+15551234567","message":"test"}'
```

## MMS Issues

### MMS photos not appearing

**Common causes:**
- Carrier MMS not enabled
- Cellular data disabled
- Base64 encoding issues

**Check Android phone:**
1. Settings → Mobile Network → Enable MMS
2. Enable cellular data
3. Test MMS locally (send photo to yourself)

**Check logs:**
```bash
# Look for base64 decode errors
docker-compose logs bridge | grep -i error
```

### MMS sending fails

**Check:**
1. Fossify has MMS permissions
2. Photo size < 2MB
3. Valid phone number format

**Test:**
```bash
# Send test MMS (via WireGuard VPN)
curl -X POST http://10.0.0.2:8080/send_mms \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "+15551234567",
    "message": "test",
    "attachments": ["SMALL_BASE64_IMAGE"]
  }'
```

## VoIP.ms Issues

### VoIP.ms API errors

**Check credentials:**
```bash
# Test VoIP.ms directly
curl "https://voip.ms/api/v1/rest.php?api_username=USER&api_password=PASS&method=getSMS"
```

**Common issues:**
- Wrong username/password
- Account suspended
- No SMS credits

### Webhook not receiving

**Check VoIP.ms portal:**
1. DID Numbers → Manage DIDs
2. Select your DID
3. SMS Settings → SMS/MMS URL configured?

**Test webhook:**
```bash
# Send test SMS via VoIP.ms portal
# Check bridge logs
docker-compose logs -f bridge
```

## SIP/Linphone Issues

### Linphone won't register

**Check:**
1. VoIP.ms credentials correct
2. Server: seattle.voip.ms (or your server)
3. Transport: TLS
4. Port: 5061

**Test SIP registration:**
```bash
# From Linux
sip-tester sip:your_account@seattle.voip.ms
```

### No SIP messages

**Check Flexisip:**
```bash
docker-compose logs flexisip

# Verify routing
flexisip-cli show routes
```

**Verify mmsgate:**
```bash
# Check mmsgate is forwarding SIP MESSAGE
docker-compose logs mmsgate | grep MESSAGE
```

## SSL/Certificate Issues

### Let's Encrypt renewal failed

```bash
# Renew manually
sudo certbot renew

# Check cron
sudo systemctl status certbot.timer
```

### Certificate not trusted

**Check:**
```bash
# Verify certificate
openssl s_client -connect bridge.your-domain.com:443

# Check chain
curl -vI https://bridge.your-domain.com
```

## Network Issues

### Can't reach bridge from internet

**Check firewall:**
```bash
sudo ufw status

# Allow ports
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 5060/udp
sudo ufw allow 5061/tcp
```

**Check nginx:**
```bash
sudo nginx -t
sudo systemctl status nginx
```

### WireGuard issues

**Restart:**
```bash
# On Android (using WireGuard app)
# 1. Open WireGuard app
# 2. Toggle off then on
# 3. Watch status indicator for "Connected"

# On VPS (if needed)
sudo wg-quick down wg0
sudo wg-quick up wg0
```

**Check connectivity:**
```bash
# From VPS
wg show
ping 10.0.0.2

# From Android
# WireGuard app status should show "Connected"
# Try pinging VPS at 10.0.0.1 via terminal app
```

## Performance Issues

### High latency

**Check:**
1. Network speed (ping times)
2. Server load (top, htop)
3. Docker resources

**Optimize:**
```bash
# Increase Docker resources
# Edit docker-compose.yml:
services:
  bridge:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
```

### Messages delayed

**Check queue:**
```bash
# Are messages being queued?
docker-compose logs bridge | grep -i queue
```

**Common causes:**
- Fossify offline
- Network issues
- VoIP.ms rate limiting

## Debugging Tips

### Enable verbose logging

**Bridge server:**
```python
# Edit sms-bridge-server.py
logging.basicConfig(level=logging.DEBUG)
```

**Rebuild:**
```bash
docker-compose down
docker-compose up --build
```

### Capture traffic

```bash
# On VPS
sudo tcpdump -i any -w capture.pcap port 5000 or port 8080

# Analyze with Wireshark
```

### Test components individually

**1. Fossify only (via WireGuard VPN):**
```bash
curl -X POST http://10.0.0.2:8080/send_sms \
  -H "Authorization: Bearer TOKEN" \
  -d '{"phoneNumber":"+1...","message":"test"}'
```

**2. Bridge only:**
```bash
curl http://localhost:5000/health
```

**3. Full chain:**
Send message in Linphone, trace through logs

## Getting Help

### Collect diagnostic info

```bash
# System info
uname -a
docker --version
docker-compose --version

# Service status
docker-compose ps

# Recent logs
docker-compose logs --tail=100 > debug.log

# Configuration (redact secrets!)
cat .env | sed 's/=.*$/=REDACTED/' > config.txt
```

### Where to ask

1. Check existing issues
2. Search documentation
3. Open new issue with:
   - Error message
   - Logs
   - What you tried
   - Configuration (redacted)

## Common Error Messages

### "Connection refused"

**Meaning:** Service not running or port blocked

**Solution:** Check service status, firewall, port

### "401 Unauthorized"

**Meaning:** Wrong auth token

**Solution:** Verify tokens match in both sides

### "404 Not Found"

**Meaning:** Wrong URL or endpoint

**Solution:** Check URL path, verify endpoint exists

### "500 Internal Server Error"

**Meaning:** Server error

**Solution:** Check server logs for details

### "Timeout"

**Meaning:** No response within time limit

**Solution:** Check network, service running, not overloaded

## Prevention

### Regular maintenance

```bash
# Weekly
docker-compose logs --tail=1000 > logs-$(date +%Y%m%d).txt
docker system prune -f

# Monthly
docker-compose pull
docker-compose up -d --build

# Check certificates
sudo certbot renew --dry-run
```

### Monitoring

The system includes an automated health monitoring service:

```bash
# Check monitor status
docker-compose ps monitor

# View monitor logs
docker-compose logs -f monitor

# Restart monitor
docker-compose restart monitor
```

**Configure SMTP Alerts:**

Edit `.env` and add your SMTP credentials:
```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=your-email@gmail.com
SMTP_TO=alert-recipient@example.com
```

Then restart the monitor:
```bash
docker-compose restart monitor
```

The monitor will:
- Check bridge health endpoint every 60 seconds
- Check mmsgate TCP port availability every 60 seconds
- Send email alerts when services go down
- Send recovery notifications when services come back up
- Wait 5 minutes before repeating alerts for the same service

### Backup

```bash
# Backup configuration
tar czf backup-$(date +%Y%m%d).tar.gz .env docker-compose.yml configs/

# Store offsite
rsync -av backup-*.tar.gz remote:~/backups/
```
