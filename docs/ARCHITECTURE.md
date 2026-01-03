# System Architecture

Complete technical architecture of the SMS/MMS bridge system.

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    YOUR COMPLETE SYSTEM                     │
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
```

## Component Architecture

### 1. Fossify Messages (Android Phone)

**Modified open-source messaging app with HTTP API**

**Location:** Home with SIM card, plugged in, internet connected

**Capabilities:**
- Receives SMS/MMS via cellular network (native Android APIs)
- HTTP API server (port 8080) for remote control
- Webhook client to notify bridge of incoming messages
- Full MMS support (send & receive photos, videos)

**Key Endpoints:**
- `POST /send_sms` - Send SMS to phone number
- `POST /send_mms` - Send MMS with attachments
- `GET /health` - Health check
- Webhook notification on message receive

**Security:**
- Bearer token authentication
- Only accessible via WireGuard VPN (10.0.0.2:8080)
- HTTPS not needed (private VPN tunnel)

**Code:** `fossify-api/` directory contains the modifications

---

### 2. WireGuard VPN

**Encrypted tunnel between VPS and Android phone**

**Configuration:**
- Server (VPS): 10.0.0.1
- Client (Android): 10.0.0.2
- Network: 10.0.0.0/24
- Protocol: UDP port 51820

**Purpose:**
- Android phone has no public IP (behind home NAT/firewall)
- WireGuard creates encrypted tunnel
- Bridge server can reach Fossify at 10.0.0.2:8080 over VPN
- Persistent connection with keepalive

**Security:**
- Elliptic Curve Cryptography (modern, fast)
- Perfect Forward Secrecy
- UDP only (NAT-friendly)

---

### 3. Bridge Server (VPS)

**Python Flask application - message router and API proxy**

**Location:** Public VPS with static IP

**Responsibilities:**
- Receives webhooks from Fossify (incoming SMS/MMS)
- Receives mmsgate API calls (outgoing SMS/MMS)
- Routes messages between cellular and SIP networks
- Proxies VoIP.ms API for mmsgate

**Key Endpoints:**
- `POST /webhook/fossify` - Receive from Fossify
- `GET/POST /voipms/api` - API proxy for mmsgate
- `GET /health` - Health check

**Deployment:**
- Docker container with docker-compose
- Ports: 5000 (HTTPS with self-signed cert)
- Environment: Python 3.9+, Flask, Requests

**Security:**
- Bearer token authentication for all endpoints
- HTTPS with valid certificates
- Firewall: only ports 443 (SIP) and 5000 (bridge) open
- Stateless design (no persistent data)

**Code:** `bridge-server/sms-bridge-server.py`

---

### 4. mmsgate (VPS)

**VoIP.ms API ↔ SIP MESSAGE converter**

**Location:** VPS alongside bridge

**Responsibilities:**
- Converts between VoIP.ms SMS API and SIP MESSAGE protocol
- Handles MMS media uploads/downloads
- Routes messages between Linphone and bridge
- Provides unified messaging interface

**Configuration:**
- Points to bridge as "VoIP.ms API": `https://bridge.your-domain.com:5000/voipms/api`
- Receives mmsgate-specific webhooks from bridge
- Communicates with Flexisip for SIP MESSAGE routing

**Security:**
- Credentials: VoIP.ms username/password (for authentication only)
- Encrypted communication with bridge (HTTPS)
- Behind firewall (internal communication)

**Repository:** https://github.com/RVgo4it/mmsgate

---

### 5. Flexisip (VPS)

**SIP proxy server for message routing**

**Location:** VPS

**Responsibilities:**
- Routes SIP MESSAGE between clients
- Handles SIP registration (Linphone auth)
- Manages presence/availability
- Delivers push notifications (optional)

**Configuration:**
- TLS transport on port 5061
- Routes to mmsgate for SMS/MMS
- Registered users: you (Linphone client)

**Security:**
- TLS encryption for all SIP traffic
- Certificate-based authentication
- Firewall: only port 5061 open to internet

**Repository:** https://github.com/BelledonneCommunications/flexisip

---

### 6. Linphone (Your Device)

**SIP client application - your messaging interface**

**Location:** Anywhere (traveling)

**Capabilities:**
- Voice calls (via VoIP.ms)
- SMS messaging (via bridge → Fossify)
- MMS messaging (via bridge → Fossify)
- Presence and typing indicators
- Desktop/mobile/web versions

**Configuration:**
- SIP account: bridge credentials you choose (username/password)
- Domain: flexisip server (your domain, sip.your-domain.com)
- Transport: TLS
- Register interval: ~1800 seconds
- Voice calls: optional (requires VoIP provider integration)

**Security:**
- TLS encryption to Flexisip
- Password-protected SIP registration
- SRTP optional for voice

**Website:** https://linphone.org

---

## Message Flow

### OUTGOING: Sending SMS from Linphone to Cellular

```
1. You compose message in Linphone
   From: your_voipms_account
   To: +15551234567
   Message: "Hello from Linphone"
   
2. Linphone → Flexisip (SIP MESSAGE over TLS)
   SEND MESSAGE sip:+15551234567@domain
   Content: Hello from Linphone
   
3. Flexisip routes to mmsgate
   Detects this is an SMS request
   
4. mmsgate → Bridge (HTTP GET)
   GET /voipms/api?method=sendSMS&dst=15551234567&message=Hello+from+Linphone
   Authentication: implicit (Linphone already authenticated)
   
5. Bridge intercepts the "VoIP.ms" call
   Recognizes as SMS
   Calls Fossify instead of VoIP.ms
   
6. Bridge → Fossify (HTTP POST over WireGuard VPN)
   POST http://10.0.0.2:8080/send_sms
   Authorization: Bearer TOKEN
   Body: {phoneNumber: "+15551234567", message: "Hello from Linphone"}
   
7. Fossify receives over VPN (secure tunnel)
   Calls Android SmsManager API
   
8. Android Cellular Network
   SMS sent from your SIM card
   Recipient sees your real cellular number
   
9. Recipient receives SMS
   Sender: +1-555-YOUR-NUMBER
   Message: "Hello from Linphone"
```

**Time:** ~2-5 seconds
**User experience:** Type in Linphone, message sent from cellular

---

### OUTGOING: Sending MMS from Linphone to Cellular

```
Same as SMS, but:

4. mmsgate → Bridge
   GET /voipms/api?method=sendMMS&dst=15551234567&message=Hello&media1=https://...
   
6. Bridge → Fossify
   POST /send_mms
   Body: {
     phoneNumber: "+15551234567",
     message: "Hello",
     attachments: ["base64_encoded_image_data"]
   }
   
7. Fossify
   Calls Android MmsManager API
   (not available for SMS, only MMS)
   
8. Android sends MMS with attachment
   Uses cellular data
   
9. Recipient receives MMS
   With photo/video attachment
```

---

### INCOMING: Receiving SMS in Linphone from Cellular

```
1. Someone texts your cellular number
   Sender: +1-555-FRIEND
   Message: "Reply from friend"
   
2. Android phone receives SMS
   Via cellular network
   Fossify captures it (SMS receiver)
   
3. Fossify → Bridge (HTTP POST via WireGuard VPN)
   POST https://bridge.your-domain.com:5000/webhook/fossify
   Authorization: Bearer BRIDGE_SECRET
   Body: {
     phoneNumber: "+15555551111",
     message: "Reply from friend",
     attachments: []
   }
   
4. Bridge receives webhook
   Processes incoming message
   Calls mmsgate webhook
   
5. Bridge → mmsgate (HTTP POST)
   POST http://localhost:38443/mms/receive
   Body: {
     from: "+15555551111",
     message: "Reply from friend",
     type: "sms"
   }
   
6. mmsgate converts to SIP MESSAGE
   Calls Flexisip API
   
7. Flexisip → Linphone (SIP MESSAGE)
   Delivers to registered Linphone client
   
8. Linphone receives notification
   Message appears in conversation
   Shows sender's real number
   
9. User sees message
   "Reply from friend"
   From: +1-555-FRIEND
```

**Time:** ~2-5 seconds (depending on network)
**User experience:** Message appears in Linphone from real cellular number

---

### INCOMING: Receiving MMS in Linphone from Cellular

```
Same as SMS, but:

2. Fossify captures MMS
   Extracts message and attachments
   
3. Fossify webhook includes media
   Base64-encoded image/video data
   
4. Bridge passes attachments to mmsgate
   Media URLs or base64 data
   
7. mmsgate includes media in SIP MESSAGE
   (or stores separately and references)
   
9. Linphone receives and displays
   Message with photo/video thumbnail
```

---

### VOICE CALLS: Receiving Call to Cellular

```
1. Caller calls your cellular number
   +1-555-YOUR-CELL
   
2. Cellular network tries to route
   Uses call forwarding rule (*72 setup)
   Forwards to VoIP.ms DID number
   
3. VoIP.ms receives call
   Looks up DID configuration
   Routes to Flexisip
   
4. Flexisip has your Linphone registered
   Sends INVITE to your Linphone
   
5. Linphone rings
   Caller ID shows your cellular number
   (via VoIP.ms caller ID setup)
   
6. You answer in Linphone
   Voice RTP stream established
   (secure, encrypted)
   
7. You talk to caller
   Using Linphone
   They see your cellular number
   From their perspective: normal call
```

---

## Security Model

### Authentication Layers

**1. Cellular Network**
- Your SIM card (biometric unlock)
- PIN code (carrier backup)

**2. WireGuard VPN (Android ↔ Bridge)**
- Elliptic Curve Cryptography (ChaCha20)
- Perfect Forward Secrecy
- Pre-shared keys (updated on setup)

**3. Bridge API (Fossify ↔ Bridge)**
- Bearer token authentication (shared secret)
- HTTPS not needed (already on VPN)
- Token rotation recommended monthly

**4. Bridge API (mmsgate ↔ Bridge)**
- Bearer token authentication
- HTTPS required (internet-facing)
- Different token than Fossify

**5. SIP Registration (Linphone ↔ Flexisip)**
- Username/password (bridge SIP account you create)
- TLS encryption
- Certificate validation

**6. Bridge HTTPS**
- Valid certificate (Let's Encrypt)
- Modern TLS 1.2+
- HSTS headers

### Data Flow Security

```
Public Internet                      Private VPN
├─ Linphone ↔ Flexisip (TLS)       ├─ Android ↔ Bridge (WireGuard)
├─ Bridge (HTTPS)                   └─ Fossify API only on VPN
├─ mmsgate (internal)
└─ VoIP.ms (external service)
```

### Firewall Configuration (UFW)

**Automated Setup:** `./scripts/setup-firewall.sh`

**Default Policy:** BLOCK all incoming traffic

**Allowed Inbound Ports:**

| Port        | Protocol | Purpose                               | Direction |
| ----------- | -------- | ------------------------------------- | --------- |
| 22          | TCP      | SSH administration                    | Incoming  |
| 443         | TCP      | HTTPS (SIP TLS, Bridge API)           | Incoming  |
| 5060        | TCP/UDP  | SIP signaling (VoIP provider)         | Incoming  |
| 5061        | TCP      | SIP TLS (Linphone ↔ Flexisip)         | Incoming  |
| 10000-20000 | UDP      | RTP (voice streams)                   | Incoming  |
| 51820       | UDP      | WireGuard VPN                         | Incoming  |
| All         | TCP/UDP  | Outgoing traffic (allowed by default) | Outgoing  |

**Important:** Make sure SSH key-based authentication is working BEFORE enabling UFW, or you may lock yourself out. If locked out, use SSH keys to reconnect and run `sudo ufw disable`.

### What's NOT Exposed

- Fossify API (WireGuard VPN only, 10.0.0.2)
- Android phone (behind home NAT + WireGuard)
- WireGuard keys (only on VPS and Android)
- Bridge secrets (stored in .env, not in code)
- Message content (encrypted in transit)
- Docker internal ports (blocked by firewall)

### What IS Public

- VPS IP address (your domain)
- SIP ports (443, 5061) for Linphone connectivity
- SIP ports (5060) for VoIP provider
- RTP ports (10000-20000) for voice streaming
- WireGuard (51820) for VPN tunnel
- VoIP provider DID (part of your phone setup)
- **All other ports:** Blocked by UFW firewall

### Credential Architecture (Critical)

**Three Different Credential Sets:**

**1. Bridge SIP Account (REQUIRED)**
- **What:** Username & password you create
- **Where:** flexisip.conf `[authorization]` section
- **Used by:** Linphone to register with Flexisip
- **Example:** `user: "yourname"` / `password: "strongpassword"`
- **Purpose:** Authenticates Linphone as authorized SIP client
- **Notes:** You choose these credentials; NOT from VoIP provider

**2. VoIP Provider Credentials (OPTIONAL - Voice Calls Only)**
- **What:** Your VoIP provider account (e.g., VoIP.ms username/API token)
- **Where:** mmsgate.conf `[voip_provider]` section
- **Used by:** mmsgate to forward calls/SMS to provider
- **Example:** `provider_username: "your_voipms_user"` / `api_key: "your_api_token"`
- **Purpose:** Authenticates with VoIP provider for external routing
- **Notes:** Only needed if setting up voice calls; SMS/MMS works without this

**3. Bridge Bearer Tokens (REQUIRED)**
- **What:** API authentication tokens (random secrets)
- **Where:** `.env` files `BRIDGE_TOKEN`, `MMSGATE_TOKEN`
- **Used by:** Fossify & mmsgate to authenticate with Bridge API
- **Example:** `BRIDGE_TOKEN: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."`
- **Purpose:** Secures Bridge API from unauthorized access
- **Notes:** Generated by `generate-secrets.sh`; rotate monthly

**Credential Flow Diagram:**

```
SMS/MMS Scenario (No VoIP Provider Needed):
┌─────────┐      BRIDGE TOKEN      ┌────────┐
│Fossify  │ ─────────────────────→  │ Bridge │
└─────────┘                         └───┬────┘
                              Bearer token verified
                                       │
                              ┌────────▼─────────┐
                              │    mmsgate       │
                              │ (Flexisip built  │
                              │     in)          │
                              └────────┬─────────┘
                                       │
                              Routing via Flexisip
                                       │
                         ┌─────────────▼──────────────┐
                         │  Linphone (Bridge SIP Cred) │
                         │  Registered with Flexisip  │
                         └────────────────────────────┘

Voice Calls Scenario (With VoIP Provider):
┌──────────────┐      BEARER TOKEN      ┌────────┐
│ Linphone     │ ◄─────────────────────  │ Bridge │
│ (INVITE)     │                         └───┬────┘
└──────┬───────┘                             │
       │ (Bridge SIP Credentials)       BEARER TOKEN
       │ Register with Flexisip             │
       │                           ┌────────▼─────────┐
       │                           │    mmsgate       │
       │                           │ (VoIP Provider   │
       │                           │  Credentials)    │
       │                           └────────┬─────────┘
       │                                    │
       │                    Routing to Provider
       │                                    │
       └────────────┬──────────────────────▼───┐
                    │                          │
              ┌─────▼──────┐          ┌───────▼───┐
              │ Cellular   │          │ VoIP      │
              │ Provider   │          │ Provider  │
              │ (Inbound)  │          │ (External)│
              └────────────┘          └───────────┘
```

**Configuration Summary:**

| Component  | Credential Type          | Source         | Config File     | Purpose                      |
| ---------- | ------------------------ | -------------- | --------------- | ---------------------------- |
| Linphone   | Bridge SIP account       | You create     | flexisip.conf   | Register as SIP client       |
| mmsgate    | VoIP provider (optional) | Your provider  | mmsgate.conf    | Route to provider network    |
| Bridge API | Bearer token             | Generated      | .env            | Authenticate Fossify/mmsgate |
| Flexisip   | Bridge user database     | Auto-generated | bridge-users.db | User authentication          |

---

## Data Model

### Message Object (Internal)

```python
@dataclass
class Message:
    from_number: str          # "+15551234567"
    to_number: str            # "+15559876543"
    text: str                 # "Hello"
    attachments: List[Dict]   # [{url, type, size}]
    is_mms: bool              # True if has attachments
    timestamp: datetime       # When message created
    message_id: str           # Unique ID for tracking
```

### API Request/Response Formats

**Bridge receives from mmsgate (VoIP.ms API proxy):**
```
GET /voipms/api?method=sendSMS&dst=15551234567&message=test

Response:
{
  "status": "success",
  "sms": 12345  # Message ID
}
```

**Bridge receives from Fossify (webhook):**
```
POST /webhook/fossify
Authorization: Bearer TOKEN

{
  "phoneNumber": "+15551234567",
  "message": "Hello",
  "attachments": [],
  "timestamp": "2026-01-02T10:30:00Z"
}
```

**Bridge sends to mmsgate (webhook):**
```
POST http://mmsgate:38443/mms/receive

{
  "from": "+15551234567",
  "message": "Hello",
  "attachments": [],
  "type": "sms"
}
```

---

## Deployment Architecture

### Single VPS (Docker Compose with Local Registry)

All services run in docker-compose on a single VPS with images stored in a local Docker registry for easy rebuilds.

```
┌─────────────────────────────────────┐
│         VPS (Ubuntu 22.04)          │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐    │
│  │  Local Docker Registry      │    │
│  │  (port 5001)                │    │
│  │  - sms-bridge image         │    │
│  │  - mmsgate image            │    │
│  │    (includes flexisip+pjsip)│    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Docker Compose Network     │    │
│  │  (internal bridge: sms-net) │    │
│  │  ┌────────────────────────┐ │    │
│  │  │ sms-bridge container   │ │    │
│  │  │ Port: 5000             │ │    │
│  │  │ Flask app              │ │    │
│  │  └────────────────────────┘ │    │
│  │  ┌────────────────────────┐ │    │
│  │  │ mmsgate container      │ │    │
│  │  │ Ports: 38443, 5060/61  │ │    │
│  │  │ Includes flexisip      │ │    │
│  │  │ (SIP proxy inside)     │ │    │
│  │  └────────────────────────┘ │    │
│  │  ┌────────────────────────┐ │    │
│  │  │ nginx container        │ │    │
│  │  │ HTTPS reverse proxy    │ │    │
│  │  └────────────────────────┘ │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  WireGuard VPN              │    │
│  │  Port: 51820 (UDP)          │    │
│  │  Tunnel to Android (10.0.0.0/24) │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

### Container Communication

Services communicate over the internal `sms-net` Docker bridge network:

```
Android Phone (10.0.0.2)
    ↕ WireGuard VPN (10.0.0.1:51820)
    ↕
Fossify API (10.0.0.2:8080)
    ↕ HTTP
    ↕
sms-bridge:5000 ←→ mmsgate:38443 (includes flexisip:5060/5061)
    ↕
    └─ Direct internal network (sms-net Docker bridge)
```

**Key:** Services use container names for DNS (sms-bridge, mmsgate) - no localhost/127.0.0.1 issues.

### Network Topology

```
┌─ Internet
│
└─ VPS (Public IP)
   ├─ nginx (reverse proxy) → bridge:5000, mmsgate:38443
   ├─ flexisip SIP (5060/5061) - runs inside mmsgate container
   ├─ Local Docker registry (5001, internal only)
   └─ WireGuard Tunnel (10.0.0.0/24)
      └─ Android Phone (10.0.0.2:8080 Fossify API)
```

### Port Mapping

| Port        | Protocol | Purpose             | Exposed | Container  |
| ----------- | -------- | ------------------- | ------- | ---------- |
| 51820       | UDP      | WireGuard VPN       | Yes     | Host       |
| 443         | TCP      | HTTPS (nginx proxy) | Yes     | nginx:443  |
| 80          | TCP      | HTTP redirect       | Yes     | nginx:80   |
| 5061        | TCP      | SIP/TLS (clients)   | Yes     | mmsgate    |
| 5060        | UDP      | SIP (clients)       | Yes     | mmsgate    |
| 5000        | TCP      | Bridge API          | No      | sms-bridge |
| 38443       | TCP      | mmsgate             | No      | mmsgate    |
| 5001        | TCP      | Docker registry     | No      | registry   |
| 38000-38999 | UDP      | RTP media           | Yes     | mmsgate    |

### Image Build Process

**First deployment (30-40 minutes):**
1. build-and-push-images.sh clones mmsgate repo
2. Builds mmsgate with multi-layer process:
   - Layer 1: Dockerfile_flexisip_install (5-10 min)
   - Layer 2: Dockerfile_pjsip_install (5-10 min)
   - Layer 3: Dockerfile_mmsgate_install (10-15 min)
3. Final image includes flexisip SIP proxy + mmsgate
4. Pushes mmsgate image to registry (5001)
5. Pushes sms-bridge image to registry
6. docker-compose pulls and starts services

**Subsequent deployments (< 1 minute):**
- docker-compose pulls images from registry
- Starts containers immediately (cached images)
- Can update configs and restart individual services

---

## Scalability Considerations

### Current Design
- Single VPS (sufficient for personal use)
- Docker containers on one machine
- Local registry for image management
- Stateless bridge (easy to restart)


### If Scaling Needed

**High Availability:**
- Multiple VPS instances
- Load balancer (nginx/HAProxy)
- Shared secrets management (Vault)
- Message queue (Redis)

**Performance:**
- Bridge: CPU/memory based on message rate
- Typical personal use: <100MB RAM, <5% CPU
- Fossify: Limited by Fossil app, local processing

**Redundancy:**
- Backup VPS for failover
- Separate domain with DNS failover
- Message retry logic in bridge

---

## Monitoring & Observability

### Automated Health Monitoring

The system includes an automated monitoring service that:
- Checks bridge HTTP health endpoint (`/health`) every 60 seconds
- Checks mmsgate TCP port (38443) availability every 60 seconds
- Sends SMTP email alerts when services go down
- Sends recovery notifications when services come back up
- Implements 5-minute cooldown to prevent alert spam

**Configuration:** See `.env.example` for SMTP settings.

**Logs:** `docker-compose logs -f monitor`

### What to Monitor

**Bridge Health:**
- CPU usage
- Memory usage
- Disk space (/var/log, docker volumes)
- Network connectivity

**Service Health:**
- Bridge responds to `/health` endpoint (automated ✓)
- Fossify API responds to `/health`
- Flexisip SIP registration working
- mmsgate process running (automated via TCP check ✓)

**Message Flow:**
- Incoming/outgoing message count
- Delivery latency
- Error rates by type
- Failed message queue

**Security:**
- Failed authentication attempts
- Certificate expiration dates
- WireGuard connection status
- VPN bandwidth usage

### Log Locations

```
/home/aaron/Code/sms-bridge-linphone/bridge-server/bridge.log
/var/log/docker/containers/*/std*.log
Docker compose logs: docker-compose logs -f
```

---

## Future Improvements

- [ ] Message delivery reports
- [ ] Message queueing/retry logic
- [ ] Multi-device support (same account, multiple clients)
- [ ] Web admin interface
- [ ] Message search/archive
- [ ] Automated backups
- [ ] Metrics (Prometheus endpoint)
- [ ] Distributed tracing (Jaeger)
