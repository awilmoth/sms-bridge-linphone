#!/usr/bin/env python3
"""
Service Health Monitor
Checks bridge, mmsgate, and flexisip health and sends email alerts on failures
"""

import os
import sys
import time
import logging
import socket
import requests
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
from typing import Dict, Optional

# Configuration
CHECK_INTERVAL = int(os.getenv('MONITOR_CHECK_INTERVAL', '60'))  # seconds
ALERT_COOLDOWN = int(os.getenv('MONITOR_ALERT_COOLDOWN', '300'))  # seconds between repeat alerts

SMTP_HOST = os.getenv('SMTP_HOST', 'smtp.gmail.com')
SMTP_PORT = int(os.getenv('SMTP_PORT', '587'))
SMTP_USER = os.getenv('SMTP_USER', '')
SMTP_PASSWORD = os.getenv('SMTP_PASSWORD', '')
SMTP_FROM = os.getenv('SMTP_FROM', SMTP_USER)
SMTP_TO = os.getenv('SMTP_TO', '')

# Services to monitor
SERVICES = {
    'bridge': {
        'url': 'http://sms-bridge:5000/health',
        'name': 'SMS Bridge Server',
        'timeout': 10,
        'type': 'http'
    },
    'mmsgate': {
        'host': 'mmsgate',
        'port': 38443,
        'name': 'mmsgate (MMS Gateway)',
        'timeout': 5,
        'type': 'tcp'
    }
    # Note: Flexisip doesn't have a standard HTTP health endpoint
    # It's monitored indirectly via mmsgate which depends on it
}

# State tracking
service_states: Dict[str, bool] = {}
last_alert_times: Dict[str, float] = {}

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('monitor.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


def send_email(subject: str, body: str) -> bool:
    """Send email alert via SMTP"""
    if not SMTP_USER or not SMTP_TO:
        logger.warning("SMTP not configured, skipping email alert")
        return False
    
    try:
        msg = MIMEMultipart()
        msg['From'] = SMTP_FROM
        msg['To'] = SMTP_TO
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'plain'))
        
        # Connect to SMTP server
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            if SMTP_PASSWORD:
                server.login(SMTP_USER, SMTP_PASSWORD)
            server.send_message(msg)
        
        logger.info(f"Alert email sent: {subject}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to send email: {e}")
        return False


def check_service(service_id: str, config: Dict) -> bool:
    """Check if a service is healthy"""
    try:
        if config.get('type') == 'http':
            # HTTP health check
            response = requests.get(
                config['url'],
                timeout=config['timeout']
            )
            return response.status_code == 200
        elif config.get('type') == 'tcp':
            # TCP port check (for services without HTTP health endpoints)
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(config['timeout'])
            result = sock.connect_ex((config['host'], config['port']))
            sock.close()
            return result == 0
        else:
            logger.error(f"Unknown service type for {service_id}")
            return False
    except Exception as e:
        logger.debug(f"{config['name']} health check failed: {e}")
        return False


def should_send_alert(service_id: str) -> bool:
    """Check if enough time has passed since last alert"""
    last_alert = last_alert_times.get(service_id, 0)
    return (time.time() - last_alert) > ALERT_COOLDOWN


def handle_service_down(service_id: str, config: Dict):
    """Handle service down event"""
    service_name = config['name']
    
    # Send alert if cooldown period has passed
    if should_send_alert(service_id):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        subject = f"🚨 SMS Bridge Alert: {service_name} is DOWN"
        
        # Build check info based on type
        if config.get('type') == 'http':
            check_info = f"Health URL: {config['url']}"
        elif config.get('type') == 'tcp':
            check_info = f"TCP Port: {config['host']}:{config['port']}"
        else:
            check_info = "Check type: unknown"
        
        body = f"""
SERVICE DOWN ALERT

Service: {service_name}
Status: UNREACHABLE
Time: {timestamp}
{check_info}

Action Required:
1. Check service logs: docker-compose logs {service_id}
2. Restart service: docker-compose restart {service_id}
3. Check docker status: docker ps

This is an automated alert from the SMS Bridge monitoring system.
"""
        
        if send_email(subject, body):
            last_alert_times[service_id] = time.time()


def handle_service_recovered(service_id: str, config: Dict):
    """Handle service recovery event"""
    service_name = config['name']
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # Build check info based on type
    if config.get('type') == 'http':
        check_info = f"Health URL: {config['url']}"
    elif config.get('type') == 'tcp':
        check_info = f"TCP Port: {config['host']}:{config['port']}"
    else:
        check_info = "Check type: unknown"
    
    subject = f"✅ SMS Bridge: {service_name} RECOVERED"
    body = f"""
SERVICE RECOVERY

Service: {service_name}
Status: HEALTHY
Time: {timestamp}
{check_info}

The service is now responding normally.

This is an automated alert from the SMS Bridge monitoring system.
"""
    
    send_email(subject, body)
    # Clear cooldown after recovery
    last_alert_times.pop(service_id, None)


def monitor_loop():
    """Main monitoring loop"""
    logger.info("SMS Bridge Monitor starting...")
    logger.info(f"Monitoring {len(SERVICES)} services")
    logger.info(f"Check interval: {CHECK_INTERVAL}s")
    logger.info(f"Alert cooldown: {ALERT_COOLDOWN}s")
    
    if not SMTP_USER or not SMTP_TO:
        logger.warning("⚠️  SMTP not configured - email alerts disabled")
        logger.warning("Set SMTP_USER and SMTP_TO environment variables to enable alerts")
    
    # Initialize states
    for service_id in SERVICES:
        service_states[service_id] = True  # Assume healthy initially
    
    # Wait for services to start
    logger.info("Waiting 30 seconds for services to start...")
    time.sleep(30)
    
    while True:
        try:
            for service_id, config in SERVICES.items():
                is_healthy = check_service(service_id, config)
                was_healthy = service_states.get(service_id, True)
                
                if is_healthy and not was_healthy:
                    # Service recovered
                    logger.info(f"✅ {config['name']} recovered")
                    handle_service_recovered(service_id, config)
                    service_states[service_id] = True
                    
                elif not is_healthy and was_healthy:
                    # Service went down
                    logger.error(f"🚨 {config['name']} is DOWN")
                    handle_service_down(service_id, config)
                    service_states[service_id] = False
                    
                elif not is_healthy:
                    # Service still down - check if we should repeat alert
                    if should_send_alert(service_id):
                        logger.warning(f"⚠️  {config['name']} still DOWN")
                        handle_service_down(service_id, config)
                else:
                    # Service healthy
                    logger.debug(f"✓ {config['name']} healthy")
            
            # Wait before next check
            time.sleep(CHECK_INTERVAL)
            
        except KeyboardInterrupt:
            logger.info("Monitor stopped by user")
            break
        except Exception as e:
            logger.error(f"Error in monitor loop: {e}")
            time.sleep(CHECK_INTERVAL)


def main():
    """Main entry point"""
    # Validate configuration
    if not SMTP_USER or not SMTP_TO:
        logger.warning("⚠️  SMTP credentials not configured")
        logger.warning("Email alerts will be disabled")
        logger.warning("Set SMTP_USER and SMTP_TO to enable email notifications")
    
    logger.info("Starting service health monitoring...")
    monitor_loop()


if __name__ == '__main__':
    main()
