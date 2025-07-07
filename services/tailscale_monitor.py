#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tailscale Monitor Service
Sistema Gateway 24/7 - Raspberry Pi 3B+

Monitors Tailscale connection, handles auto-reconnection,
and logs user access events.
"""

import os
import sys
import time
import json
import logging
import subprocess
import threading
import signal
import requests
from datetime import datetime, timezone
from typing import Dict, List, Optional, Set

# Configuration
CONFIG_PATH = "/opt/gateway/config/tailscale.conf"
LOG_PATH = "/var/log/tailscale_monitor.log"
STATE_FILE = "/tmp/tailscale_monitor_state.json"
TELEGRAM_NOTIFIER_PATH = "/opt/gateway/services/telegram_notifier.py"

class TailscaleMonitor:
    def __init__(self):
        self.config = self.load_config()
        self.running = True
        self.connected_users = set()
        self.connection_status = False
        self.setup_logging()
        self.telegram_notifier = None
        
    def load_config(self) -> Dict:
        """Load configuration from file"""
        config = {}
        try:
            with open(CONFIG_PATH, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        # Convert boolean strings
                        if value.lower() in ('true', 'false'):
                            value = value.lower() == 'true'
                        # Convert numeric strings
                        elif value.isdigit():
                            value = int(value)
                        config[key.strip()] = value
        except Exception as e:
            logging.error(f"Error loading config: {e}")
            # Default configuration
            config = {
                'TSKEY': 'tskey-auth-kv46teABjB11CNTRL-yejSHDZq8SL7J1HAqZWsRLW8Lfe9UmT8A',
                'CHECK_INTERVAL': 30,
                'RECONNECT_ATTEMPTS': 3,
                'RECONNECT_DELAY': 60,
                'LOG_CONNECTIONS': True
            }
        return config
        
    def setup_logging(self):
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(LOG_PATH),
                logging.StreamHandler()
            ]
        )
        
    def notify_telegram(self, message_type: str, **kwargs):
        """Send notification to Telegram service"""
        try:
            if message_type == 'tailscale_access':
                # Import here to avoid circular imports
                sys.path.insert(0, '/opt/gateway/services')
                from telegram_notifier import TelegramNotifier
                notifier = TelegramNotifier()
                notifier.notify_tailscale_access(kwargs.get('user', 'Unknown'), kwargs.get('action', 'connected'))
        except Exception as e:
            logging.error(f"Failed to send Telegram notification: {e}")
            
    def is_tailscale_installed(self) -> bool:
        """Check if Tailscale is installed"""
        try:
            result = subprocess.run(['which', 'tailscale'], 
                                  capture_output=True, text=True, timeout=5)
            return result.returncode == 0
        except:
            return False
            
    def install_tailscale(self) -> bool:
        """Install Tailscale if not present"""
        logging.info("Installing Tailscale...")
        
        try:
            # Download and run Tailscale installer
            install_script = """
            curl -fsSL https://tailscale.com/install.sh | sh
            """
            
            result = subprocess.run(['bash', '-c', install_script], 
                                  capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                logging.info("Tailscale installed successfully")
                return True
            else:
                logging.error(f"Tailscale installation failed: {result.stderr}")
                return False
                
        except Exception as e:
            logging.error(f"Error installing Tailscale: {e}")
            return False
            
    def authenticate_tailscale(self) -> bool:
        """Authenticate Tailscale with the provided key"""
        try:
            tskey = self.config.get('TSKEY')
            if not tskey:
                logging.error("No Tailscale auth key configured")
                return False
                
            # Check if already authenticated
            result = subprocess.run(['tailscale', 'status'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and 'Logged out' not in result.stdout:
                logging.info("Tailscale already authenticated")
                return True
                
            # Authenticate
            cmd = ['tailscale', 'up', '--authkey', tskey]
            
            # Add optional flags based on configuration
            if self.config.get('ACCEPT_ROUTES', True):
                cmd.append('--accept-routes')
            if self.config.get('ACCEPT_DNS', False):
                cmd.append('--accept-dns')
            if self.config.get('ADVERTISE_EXIT_NODE', False):
                cmd.append('--advertise-exit-node')
                
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                logging.info("Tailscale authenticated successfully")
                return True
            else:
                logging.error(f"Tailscale authentication failed: {result.stderr}")
                return False
                
        except Exception as e:
            logging.error(f"Error authenticating Tailscale: {e}")
            return False
            
    def get_tailscale_status(self) -> Dict:
        """Get Tailscale connection status and peer information"""
        try:
            result = subprocess.run(['tailscale', 'status', '--json'], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                status_data = json.loads(result.stdout)
                return {
                    'connected': True,
                    'self_ip': status_data.get('TailscaleIPs', ['Unknown'])[0],
                    'peers': status_data.get('Peer', {}),
                    'backend_state': status_data.get('BackendState', 'Unknown')
                }
            else:
                return {'connected': False, 'error': result.stderr}
                
        except Exception as e:
            logging.error(f"Error getting Tailscale status: {e}")
            return {'connected': False, 'error': str(e)}
            
    def monitor_user_connections(self, status: Dict):
        """Monitor and log user connections/disconnections"""
        if not status.get('connected') or not self.config.get('LOG_CONNECTIONS', True):
            return
            
        current_users = set()
        peers = status.get('peers', {})
        
        for peer_id, peer_info in peers.items():
            if peer_info.get('Online', False):
                user_name = peer_info.get('HostName', peer_id)
                current_users.add(user_name)
                
        # Check for new connections
        new_users = current_users - self.connected_users
        for user in new_users:
            logging.info(f"User connected: {user}")
            self.notify_telegram('tailscale_access', user=user, action='connected')
            
        # Check for disconnections
        disconnected_users = self.connected_users - current_users
        for user in disconnected_users:
            logging.info(f"User disconnected: {user}")
            self.notify_telegram('tailscale_access', user=user, action='disconnected')
            
        self.connected_users = current_users
        
    def check_connection_health(self) -> bool:
        """Check if Tailscale connection is healthy"""
        try:
            status = self.get_tailscale_status()
            
            if not status.get('connected'):
                return False
                
            # Check if we can reach the coordination server
            result = subprocess.run(['tailscale', 'ping', 'login.tailscale.com'], 
                                  capture_output=True, text=True, timeout=15)
            
            return result.returncode == 0
            
        except Exception as e:
            logging.error(f"Error checking connection health: {e}")
            return False
            
    def reconnect_tailscale(self) -> bool:
        """Attempt to reconnect Tailscale"""
        logging.info("Attempting to reconnect Tailscale...")
        
        max_attempts = self.config.get('RECONNECT_ATTEMPTS', 3)
        delay = self.config.get('RECONNECT_DELAY', 60)
        
        for attempt in range(max_attempts):
            try:
                # First try to bring connection back up
                result = subprocess.run(['tailscale', 'up'], 
                                      capture_output=True, text=True, timeout=60)
                
                if result.returncode == 0:
                    logging.info(f"Reconnection successful on attempt {attempt + 1}")
                    return True
                    
                # If that fails, try full re-authentication
                if self.authenticate_tailscale():
                    logging.info(f"Re-authentication successful on attempt {attempt + 1}")
                    return True
                    
                if attempt < max_attempts - 1:
                    logging.warning(f"Reconnection attempt {attempt + 1} failed, retrying in {delay}s")
                    time.sleep(delay)
                    
            except Exception as e:
                logging.error(f"Reconnection attempt {attempt + 1} error: {e}")
                if attempt < max_attempts - 1:
                    time.sleep(delay)
                    
        logging.error("All reconnection attempts failed")
        return False
        
    def save_state(self):
        """Save current state to file"""
        try:
            state = {
                'connection_status': self.connection_status,
                'connected_users': list(self.connected_users),
                'last_update': datetime.now(timezone.utc).isoformat()
            }
            
            with open(STATE_FILE, 'w') as f:
                json.dump(state, f, indent=2)
                
        except Exception as e:
            logging.error(f"Error saving state: {e}")
            
    def load_state(self):
        """Load previous state from file"""
        try:
            if os.path.exists(STATE_FILE):
                with open(STATE_FILE, 'r') as f:
                    state = json.load(f)
                    
                self.connection_status = state.get('connection_status', False)
                self.connected_users = set(state.get('connected_users', []))
                
                logging.info("Previous state loaded successfully")
                
        except Exception as e:
            logging.error(f"Error loading state: {e}")
            
    def get_statistics(self) -> Dict:
        """Get connection statistics and metrics"""
        try:
            status = self.get_tailscale_status()
            
            stats = {
                'connection_status': status.get('connected', False),
                'self_ip': status.get('self_ip', 'Unknown'),
                'backend_state': status.get('backend_state', 'Unknown'),
                'connected_users_count': len(self.connected_users),
                'connected_users': list(self.connected_users),
                'last_check': datetime.now(timezone.utc).isoformat()
            }
            
            # Add peer details
            peers = status.get('peers', {})
            peer_details = []
            
            for peer_id, peer_info in peers.items():
                peer_details.append({
                    'hostname': peer_info.get('HostName', peer_id),
                    'online': peer_info.get('Online', False),
                    'last_seen': peer_info.get('LastSeen', 'Unknown'),
                    'ip': peer_info.get('TailscaleIPs', ['Unknown'])[0] if peer_info.get('TailscaleIPs') else 'Unknown'
                })
                
            stats['peer_details'] = peer_details
            
            return stats
            
        except Exception as e:
            logging.error(f"Error getting statistics: {e}")
            return {
                'connection_status': False,
                'error': str(e),
                'last_check': datetime.now(timezone.utc).isoformat()
            }
            
    def setup_tailscale(self) -> bool:
        """Complete Tailscale setup process"""
        logging.info("Starting Tailscale setup...")
        
        # Check if Tailscale is installed
        if not self.is_tailscale_installed():
            if not self.install_tailscale():
                return False
                
        # Authenticate if needed
        if not self.authenticate_tailscale():
            return False
            
        # Enable and start Tailscale service
        try:
            subprocess.run(['systemctl', 'enable', 'tailscaled'], timeout=30, check=True)
            subprocess.run(['systemctl', 'start', 'tailscaled'], timeout=30, check=True)
            logging.info("Tailscale service enabled and started")
        except Exception as e:
            logging.error(f"Error managing Tailscale service: {e}")
            
        return True
        
    def monitor_loop(self):
        """Main monitoring loop"""
        check_interval = self.config.get('CHECK_INTERVAL', 30)
        consecutive_failures = 0
        max_failures = 3
        
        while self.running:
            try:
                # Get current status
                status = self.get_tailscale_status()
                current_connected = status.get('connected', False)
                
                # Check for connection state changes
                if current_connected != self.connection_status:
                    if current_connected:
                        logging.info("Tailscale connection established")
                        self.notify_telegram('connection_established', 
                                           ip=status.get('self_ip', 'Unknown'),
                                           mode='Tailscale')
                    else:
                        logging.warning("Tailscale connection lost")
                        self.notify_telegram('disconnection', connection_type='Tailscale')
                        
                    self.connection_status = current_connected
                    
                # Monitor user connections
                if current_connected:
                    self.monitor_user_connections(status)
                    consecutive_failures = 0
                else:
                    consecutive_failures += 1
                    
                    # Attempt reconnection after multiple failures
                    if consecutive_failures >= max_failures:
                        logging.warning(f"Connection lost for {consecutive_failures} checks, attempting reconnection")
                        if self.reconnect_tailscale():
                            consecutive_failures = 0
                        else:
                            # Reset counter to avoid constant reconnection attempts
                            consecutive_failures = 0
                            
                # Save current state
                self.save_state()
                
                # Wait for next check
                time.sleep(check_interval)
                
            except Exception as e:
                logging.error(f"Error in monitoring loop: {e}")
                time.sleep(check_interval)
                
    def run(self):
        """Main run method"""
        logging.info("Starting Tailscale Monitor Service")
        
        # Load previous state
        self.load_state()
        
        # Setup Tailscale if needed
        if not self.setup_tailscale():
            logging.error("Failed to setup Tailscale, monitoring will continue anyway")
            
        # Start monitoring
        try:
            self.monitor_loop()
        except KeyboardInterrupt:
            logging.info("Shutting down Tailscale Monitor Service")
            self.running = False
            
def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logging.info(f"Received signal {signum}, shutting down...")
    sys.exit(0)
    
def main():
    """Main function"""
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    monitor = TailscaleMonitor()
    monitor.run()
    
if __name__ == "__main__":
    main()