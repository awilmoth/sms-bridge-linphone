#!/usr/bin/env python3
"""
SMS/MMS Bridge Server
Connects Fossify Messages (cellular) ↔ VoIP.ms (SIP)

Architecture:
- Fossify Messages webhook → Bridge → VoIP.ms API (incoming from cellular)
- VoIP.ms webhook → Bridge → Fossify API (outgoing to cellular)
- mmsgate handles VoIP.ms ↔ Linphone
"""

import os
import sys
import logging
import base64
import time
import requests
from typing import Dict, List, Optional
from dataclasses import dataclass

from flask import Flask, request, jsonify

# Configuration
FOSSIFY_API_URL = os.getenv('FOSSIFY_API_URL', 'http://192.168.1.100:8080')
FOSSIFY_AUTH_TOKEN = os.getenv('FOSSIFY_AUTH_TOKEN', '')

BRIDGE_SECRET = os.getenv('BRIDGE_SECRET', 'change-me')
FLASK_HOST = os.getenv('FLASK_HOST', '0.0.0.0')
FLASK_PORT = int(os.getenv('FLASK_PORT', '5000'))

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('bridge.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)


@dataclass
class Message:
    """Message data structure"""
    from_number: str
    to_number: str
    text: str
    attachments: List[Dict] = None
    is_mms: bool = False


class FossifyAPI:
    """Client for Fossify Messages API"""
    
    def __init__(self, base_url: str, auth_token: str):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers['Authorization'] = f'Bearer {auth_token}'
    
    def send_sms(self, phone_number: str, message: str) -> Dict:
        """Send SMS via Fossify Messages"""
        try:
            response = self.session.post(
                f"{self.base_url}/send_sms",
                json={
                    "phoneNumber": phone_number,
                    "message": message
                },
                timeout=30
            )
            response.raise_for_status()
            result = response.json()
            logger.info(f"SMS sent via Fossify to {phone_number}")
            return result
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to send SMS via Fossify: {e}")
            raise
    
    def send_mms(self, phone_number: str, message: str, 
                 attachments: List[str]) -> Dict:
        """Send MMS via Fossify Messages"""
        try:
            response = self.session.post(
                f"{self.base_url}/send_mms",
                json={
                    "phoneNumber": phone_number,
                    "message": message,
                    "attachments": attachments  # base64 encoded images
                },
                timeout=60
            )
            response.raise_for_status()
            result = response.json()
            logger.info(f"MMS sent via Fossify to {phone_number}")
            return result
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to send MMS via Fossify: {e}")
            raise


# Initialize API clients
fossify_api = FossifyAPI(FOSSIFY_API_URL, FOSSIFY_AUTH_TOKEN)


@app.route('/webhook/fossify', methods=['POST'])
def webhook_from_fossify():
    """
    Receive SMS/MMS from Fossify Messages (incoming from cellular)
    Forward to mmsgate webhook to deliver to Linphone via SIP MESSAGE
    """
    try:
        # Verify authentication
        auth_header = request.headers.get('Authorization', '')
        if auth_header != f"Bearer {BRIDGE_SECRET}":
            logger.warning(f"Unauthorized Fossify webhook from {request.remote_addr}")
            return jsonify({'error': 'Unauthorized'}), 401
        
        data = request.json
        logger.debug(f"Received from Fossify: {data}")
        
        # Parse message data
        from_number = data.get('phoneNumber', data.get('from'))
        message_text = data.get('message', data.get('text', ''))
        attachments = data.get('attachments', [])
        
        if not from_number:
            logger.error(f"No phone number in Fossify webhook: {data}")
            return jsonify({'error': 'No phone number'}), 400
        
        # Determine message type
        message_type = 'mms' if attachments else 'sms'
        
        # Forward to mmsgate webhook for delivery to Linphone
        mmsgate_webhook_url = 'http://mmsgate:38443/mms/receive'
        mmsgate_payload = {
            'from': from_number,
            'message': message_text,
            'type': message_type
        }
        
        # Include attachments if present
        if attachments:
            mmsgate_payload['attachments'] = attachments
        
        try:
            logger.info(f"Forwarding {message_type.upper()} from {from_number} to mmsgate")
            response = requests.post(
                mmsgate_webhook_url,
                json=mmsgate_payload,
                timeout=10
            )
            response.raise_for_status()
            logger.info(f"Successfully delivered to mmsgate: {response.status_code}")
            return jsonify({'status': 'delivered'}), 200
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to deliver to mmsgate: {e}")
            return jsonify({'error': 'Failed to deliver to mmsgate'}), 500
        
    except Exception as e:
        logger.error(f"Error in Fossify webhook: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/webhook/linphone', methods=['POST'])
def webhook_from_linphone():
    """
    Receive SMS/MMS from Linphone/mmsgate (outgoing to cellular)
    This is called when you send a message FROM Linphone
    Forward to Fossify Messages API to send via cellular
    """
    try:
        # Verify authentication
        auth_header = request.headers.get('Authorization', '')
        if auth_header != f"Bearer {BRIDGE_SECRET}":
            logger.warning(f"Unauthorized Linphone webhook from {request.remote_addr}")
            return jsonify({'error': 'Unauthorized'}), 401
        
        data = request.json
        logger.debug(f"Received from Linphone: {data}")
        
        # Parse message data
        # Expected format: {to: '+1234567890', message: 'text', media: ['base64...']}
        to_number = data.get('to', data.get('dst', data.get('destination')))
        message_text = data.get('message', data.get('text', ''))
        media_data = data.get('media', data.get('attachments', []))
        
        if not to_number:
            logger.error(f"No destination number in Linphone webhook: {data}")
            return jsonify({'error': 'No destination'}), 400
        
        # Forward to Fossify Messages to send via cellular
        if media_data:
            # MMS - media already in base64 or needs downloading
            attachments = []
            for media in media_data:
                if isinstance(media, str):
                    # Could be base64 or URL
                    if media.startswith('http'):
                        # Download from URL
                        try:
                            media_response = requests.get(media, timeout=30)
                            media_response.raise_for_status()
                            base64_data = base64.b64encode(media_response.content).decode('utf-8')
                            attachments.append(base64_data)
                        except Exception as e:
                            logger.error(f"Failed to download media from {media}: {e}")
                    else:
                        # Assume already base64
                        attachments.append(media)
            
            if attachments:
                fossify_api.send_mms(to_number, message_text, attachments)
            else:
                # Fallback to SMS if no attachments
                fossify_api.send_sms(to_number, message_text)
        else:
            # SMS
            fossify_api.send_sms(to_number, message_text)
        
        return jsonify({'status': 'sent_via_cellular'}), 200
        
    except Exception as e:
        logger.error(f"Error in Linphone webhook: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/sip/message', methods=['POST'])
def receive_sip_message():
    """
    Receive SIP MESSAGE directly from Linphone
    Alternative to webhook - accepts SIP MESSAGE format
    """
    try:
        # Parse SIP MESSAGE headers
        from_uri = request.headers.get('From', '')
        to_uri = request.headers.get('To', '')
        content_type = request.headers.get('Content-Type', 'text/plain')
        
        # Extract phone number from SIP URI
        # Format: sip:+15551234567@domain or tel:+15551234567
        import re
        to_match = re.search(r'(?:sip:|tel:)\+?(\d+)', to_uri)
        if not to_match:
            return jsonify({'error': 'Invalid To address'}), 400
        
        to_number = '+' + to_match.group(1)
        
        # Get message body
        if content_type == 'text/plain':
            message_text = request.data.decode('utf-8')
            # Send SMS
            fossify_api.send_sms(to_number, message_text)
        elif content_type.startswith('multipart/'):
            # MMS with attachments
            # Parse multipart message
            # This would need full MIME parsing
            message_text = "MMS message"  # Simplified
            fossify_api.send_sms(to_number, message_text)
        
        # Return SIP 200 OK
        return '', 200
        
    except Exception as e:
        logger.error(f"Error in SIP MESSAGE: {e}")
        return '', 500


@app.route('/voipms/api', methods=['GET', 'POST'])
def proxy_voipms_api():
    """
    Proxy VoIP.ms API calls from mmsgate
    Intercept sendSMS/sendMMS and route to Fossify instead
    
    This allows mmsgate to think it's talking to VoIP.ms
    while we actually send via cellular through Fossify
    """
    try:
        # Get method parameter (VoIP.ms API uses 'method' param)
        method = request.args.get('method', request.form.get('method'))
        
        if not method:
            return jsonify({'status': 'error', 'error': 'Missing method parameter'}), 400
        
        logger.info(f"VoIP.ms API proxy called: {method}")
        
        if method == 'sendSMS':
            # Extract parameters
            dst = request.args.get('dst', request.form.get('dst'))
            message = request.args.get('message', request.form.get('message'))
            
            if not dst or not message:
                return jsonify({'status': 'error', 'error': 'Missing dst or message'}), 400
            
            # Format phone number
            if not dst.startswith('+'):
                dst = '+' + dst
            
            # Send via Fossify instead of VoIP.ms
            logger.info(f"Routing SMS to Fossify: {dst}")
            result = fossify_api.send_sms(dst, message)
            
            # Return VoIP.ms-style response
            return jsonify({
                'status': 'success',
                'sms': result.get('id', int(time.time()))
            }), 200
        
        elif method == 'sendMMS':
            # Extract parameters
            dst = request.args.get('dst', request.form.get('dst'))
            message = request.args.get('message', request.form.get('message', ''))
            
            # VoIP.ms supports media1, media2, media3
            media_urls = []
            for i in range(1, 4):
                media = request.args.get(f'media{i}', request.form.get(f'media{i}'))
                if media:
                    media_urls.append(media)
            
            if not dst:
                return jsonify({'status': 'error', 'error': 'Missing dst'}), 400
            
            # Format phone number
            if not dst.startswith('+'):
                dst = '+' + dst
            
            # Download media and convert to base64
            attachments = []
            for url in media_urls:
                try:
                    logger.info(f"Downloading media: {url}")
                    media_response = requests.get(url, timeout=30)
                    media_response.raise_for_status()
                    base64_data = base64.b64encode(media_response.content).decode('utf-8')
                    attachments.append(base64_data)
                except Exception as e:
                    logger.error(f"Failed to download media from {url}: {e}")
            
            # Send via Fossify
            if attachments:
                logger.info(f"Routing MMS to Fossify: {dst} ({len(attachments)} attachments)")
                result = fossify_api.send_mms(dst, message, attachments)
            else:
                logger.info(f"No attachments, routing as SMS to Fossify: {dst}")
                result = fossify_api.send_sms(dst, message)
            
            # Return VoIP.ms-style response
            return jsonify({
                'status': 'success',
                'mms': result.get('id', int(time.time()))
            }), 200
        
        else:
            # Other methods - return error
            return jsonify({
                'status': 'error',
                'error': f'Method {method} not supported by bridge'
            }), 400
        
    except Exception as e:
        logger.error(f"Error in VoIP.ms API proxy: {e}")
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'bridge': 'sms-mms-bridge',
        'fossify_api': FOSSIFY_API_URL,
        'mmsgate': 'http://mmsgate:38443'
    }), 200


@app.route('/test/fossify', methods=['POST'])
def test_fossify():
    """Test Fossify Messages API connection"""
    try:
        data = request.json
        phone = data.get('phone', '+15551234567')
        message = data.get('message', 'Test from bridge')
        
        result = fossify_api.send_sms(phone, message)
        return jsonify({'status': 'ok', 'result': result}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


def main():
    """Main entry point"""
    # Validate configuration
    required = {
        'FOSSIFY_API_URL': FOSSIFY_API_URL,
        'FOSSIFY_AUTH_TOKEN': FOSSIFY_AUTH_TOKEN,
        'BRIDGE_SECRET': BRIDGE_SECRET
    }
    
    missing = [k for k, v in required.items() if not v or v == 'change-me']
    if missing:
        logger.error(f"Missing required configuration: {', '.join(missing)}")
        sys.exit(1)
    
    logger.info("SMS/MMS Bridge Server starting...")
    logger.info(f"Fossify API: {FOSSIFY_API_URL}")
    logger.info(f"mmsgate webhook: http://mmsgate:38443")
    logger.info(f"Listening on {FLASK_HOST}:{FLASK_PORT}")
    
    app.run(host=FLASK_HOST, port=FLASK_PORT, debug=False)


if __name__ == '__main__':
    main()
