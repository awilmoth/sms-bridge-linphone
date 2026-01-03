#!/bin/bash
# Test all SMS Bridge endpoints

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Load configuration
if [ -f "$PROJECT_ROOT/bridge-server/.env" ]; then
    source "$PROJECT_ROOT/bridge-server/.env"
else
    echo "ERROR: .env file not found at $PROJECT_ROOT/bridge-server/.env"
    exit 1
fi

BRIDGE_URL="${BRIDGE_URL:-http://localhost:5000}"
FOSSIFY_API_URL="${FOSSIFY_API_URL:-http://10.0.0.2:8080}"
TEST_PHONE="+15551234567"

echo "====================================="
echo "SMS Bridge Endpoint Tests"
echo "====================================="
echo

# Test 1: Bridge health
echo "[1/5] Testing bridge health..."
response=$(curl -s -o /dev/null -w "%{http_code}" $BRIDGE_URL/health)
if [ "$response" == "200" ]; then
    echo "✓ Bridge health OK"
    curl -s $BRIDGE_URL/health | jq .
else
    echo "✗ Bridge health FAILED (HTTP $response)"
fi
echo

# Test 2: Fossify API health
echo "[2/5] Testing Fossify API..."
if [ -z "$FOSSIFY_API_URL" ]; then
    echo "⊘ Fossify API URL not configured, skipping"
else
    response=$(curl -s -o /dev/null -w "%{http_code}" "$FOSSIFY_API_URL/health" 2>/dev/null)
    if [ "$response" == "200" ]; then
        echo "✓ Fossify API OK"
    else
        echo "✗ Fossify API FAILED (HTTP $response)"
        echo "  Make sure Fossify is running and accessible at $FOSSIFY_API_URL"
    fi
fi
echo

# Test 3: VoIP.ms API proxy (SMS)
echo "[3/5] Testing VoIP.ms API proxy (sendSMS)..."
echo "This will send a test SMS to $TEST_PHONE via Fossify"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    response=$(curl -s "$BRIDGE_URL/voipms/api?method=sendSMS&dst=${TEST_PHONE//+/}&message=Test+from+bridge")
    echo "$response" | jq .
    if echo "$response" | jq -e '.status == "success"' > /dev/null; then
        echo "✓ VoIP.ms sendSMS proxy OK"
    else
        echo "✗ VoIP.ms sendSMS proxy FAILED"
    fi
else
    echo "Skipped"
fi
echo

# Test 4: Fossify webhook receiver
echo "[4/5] Testing Fossify webhook endpoint..."
response=$(curl -s -X POST $BRIDGE_URL/webhook/fossify \
    -H "Authorization: Bearer $BRIDGE_SECRET" \
    -H "Content-Type: application/json" \
    -d "{
        \"phoneNumber\": \"$TEST_PHONE\",
        \"message\": \"Test incoming message\",
        \"type\": \"sms\",
        \"receivedAt\": $(date +%s)000
    }")

if echo "$response" | jq -e '.status == "delivered"' > /dev/null 2>&1; then
    echo "✓ Fossify webhook OK"
else
    echo "✗ Fossify webhook FAILED"
    echo "Response: $response"
fi
echo

# Test 5: End-to-end Fossify test
echo "[5/5] Testing Fossify send_sms endpoint..."
read -p "Send test SMS to $TEST_PHONE? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    response=$(curl -s -X POST $FOSSIFY_API_URL/send_sms \
        -H "Authorization: Bearer $FOSSIFY_AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"phoneNumber\": \"$TEST_PHONE\",
            \"message\": \"Direct test from Fossify API\"
        }")
    
    if echo "$response" | jq -e '.status == "sent"' > /dev/null 2>&1; then
        echo "✓ Fossify send_sms OK"
        echo "Check if SMS arrived at $TEST_PHONE"
    else
        echo "✗ Fossify send_sms FAILED"
        echo "Response: $response"
    fi
else
    echo "Skipped"
fi
echo

echo "====================================="
echo "Test Summary"
echo "====================================="
echo "Check the results above"
echo
echo "If all tests passed:"
echo "  1. Configure mmsgate to use bridge"
echo "  2. Configure Fossify webhook"
echo "  3. Test with Linphone"
echo
echo "If tests failed:"
echo "  - Check docker-compose logs -f"
echo "  - Verify .env configuration"
echo "  - Check network connectivity"echo "====================================="