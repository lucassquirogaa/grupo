#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
System Watchdog Service
Sistema Gateway 24/7 - Raspberry Pi 3B+

Monitors system health, manages auto-recovery,
and ensures 24/7 operation.
"""

import os
import sys
import time
import json
import logging
import subprocess
import threading
import signal
import psutil
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional

# Configuration
CONFIG_PATH = "/opt/gateway/config/monitoring.conf"
LOG_PATH = "/var/log/system_watchdog.log"
STATE_FILE = "/tmp/system_watchdog_state.json"

class SystemWatchdog:
    def __init__(self):
        self.config = self.load_config()
        self.running = True
        self.recovery_attempts = {}
        self.last_alerts = {}
        self.setup_logging()
        
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
                'WATCHDOG_TIMEOUT': 120,
                'RESTART_ATTEMPTS': 3,
                'RESTART_DELAY': 30,
                'CPU_THRESHOLD': 70,
                'MEMORY_THRESHOLD': 80,
                'TEMPERATURE_THRESHOLD': 75,
                'AUTO_RECOVERY': True
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
            sys.path.insert(0, '/opt/gateway/services')
            from telegram_notifier import TelegramNotifier
            notifier = TelegramNotifier()
            
            if message_type == 'critical_event':
                notifier.notify_critical_event(kwargs.get('event_type', 'Unknown'), 
                                              kwargs.get('details', ''))
            elif message_type == 'high_cpu':
                notifier.notify_high_cpu(kwargs.get('cpu_percent', 0), 
                                       kwargs.get('stats', {}))
                                       
        except Exception as e:
            logging.error(f"Failed to send Telegram notification: {e}")
            
    def get_system_metrics(self) -> Dict:
        """Get comprehensive system metrics"""
        try:
            metrics = {
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'cpu_percent': psutil.cpu_percent(interval=1),
                'memory_percent': psutil.virtual_memory().percent,
                'memory_available': psutil.virtual_memory().available,
                'disk_percent': psutil.disk_usage('/').percent,
                'disk_free': psutil.disk_usage('/').free,
                'load_avg': psutil.getloadavg(),
                'uptime': time.time() - psutil.boot_time(),
                'temperature': self.get_cpu_temperature(),
                'throttled': self.check_throttling(),
                'process_count': len(psutil.pids())
            }
            
            # Network stats
            net_io = psutil.net_io_counters()
            metrics['network'] = {
                'bytes_sent': net_io.bytes_sent,
                'bytes_recv': net_io.bytes_recv,
                'packets_sent': net_io.packets_sent,
                'packets_recv': net_io.packets_recv
            }
            
            # Disk I/O stats
            disk_io = psutil.disk_io_counters()
            if disk_io:
                metrics['disk_io'] = {
                    'read_bytes': disk_io.read_bytes,
                    'write_bytes': disk_io.write_bytes,
                    'read_count': disk_io.read_count,
                    'write_count': disk_io.write_count
                }
            
            return metrics
            
        except Exception as e:
            logging.error(f"Error getting system metrics: {e}")
            return {
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'error': str(e)
            }
            
    def get_cpu_temperature(self) -> Optional[float]:
        """Get CPU temperature for Raspberry Pi"""
        try:
            result = subprocess.run(['vcgencmd', 'measure_temp'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                temp_str = result.stdout.strip().replace('temp=', '').replace("'C", '')
                return float(temp_str)
        except:
            pass
            
        # Alternative method using thermal zone
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp_millidegrees = int(f.read().strip())
                return temp_millidegrees / 1000.0
        except:
            pass
            
        return None
        
    def check_throttling(self) -> Dict:
        """Check if system is being throttled"""
        try:
            result = subprocess.run(['vcgencmd', 'get_throttled'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                throttle_hex = result.stdout.strip().replace('throttled=', '')
                throttle_int = int(throttle_hex, 16)
                
                return {
                    'raw_value': throttle_hex,
                    'is_throttled': throttle_int != 0,
                    'under_voltage': bool(throttle_int & 0x1),
                    'frequency_capped': bool(throttle_int & 0x2),
                    'currently_throttled': bool(throttle_int & 0x4),
                    'soft_temp_limit': bool(throttle_int & 0x8)
                }
        except:
            pass
            
        return {'is_throttled': False, 'error': 'Unable to check throttling status'}
        
    def check_service_health(self, service_name: str) -> Dict:
        """Check health of a specific service"""
        try:
            # Check if service is active
            result = subprocess.run(['systemctl', 'is-active', service_name], 
                                  capture_output=True, text=True, timeout=10)
            is_active = result.stdout.strip() == 'active'
            
            # Check if service is enabled
            result = subprocess.run(['systemctl', 'is-enabled', service_name], 
                                  capture_output=True, text=True, timeout=10)
            is_enabled = result.stdout.strip() == 'enabled'
            
            # Get service status details
            result = subprocess.run(['systemctl', 'status', service_name], 
                                  capture_output=True, text=True, timeout=10)
            status_output = result.stdout
            
            # Extract key information
            memory_usage = None
            cpu_usage = None
            
            for line in status_output.split('\n'):
                if 'Memory:' in line:
                    try:
                        memory_usage = line.split('Memory:')[1].strip()
                    except:
                        pass
                elif 'CPU:' in line:
                    try:
                        cpu_usage = line.split('CPU:')[1].strip()
                    except:
                        pass
            
            return {
                'name': service_name,
                'is_active': is_active,
                'is_enabled': is_enabled,
                'memory_usage': memory_usage,
                'cpu_usage': cpu_usage,
                'healthy': is_active and is_enabled
            }
            
        except Exception as e:
            return {
                'name': service_name,
                'is_active': False,
                'is_enabled': False,
                'healthy': False,
                'error': str(e)
            }
            
    def restart_service(self, service_name: str) -> bool:
        """Restart a failed service"""
        try:
            logging.info(f"Attempting to restart service: {service_name}")
            
            # Get current attempt count
            attempts = self.recovery_attempts.get(service_name, 0)
            max_attempts = self.config.get('RESTART_ATTEMPTS', 3)
            
            if attempts >= max_attempts:
                logging.error(f"Max restart attempts ({max_attempts}) reached for {service_name}")
                return False
                
            # Increment attempt counter
            self.recovery_attempts[service_name] = attempts + 1
            
            # Restart the service
            result = subprocess.run(['systemctl', 'restart', service_name], 
                                  capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                logging.info(f"Service {service_name} restarted successfully")
                
                # Reset attempt counter on success
                self.recovery_attempts[service_name] = 0
                
                # Notify success
                self.notify_telegram('critical_event', 
                                   event_type='Service Recovery',
                                   details=f"Service {service_name} restarted successfully")
                return True
            else:
                logging.error(f"Failed to restart {service_name}: {result.stderr}")
                return False
                
        except Exception as e:
            logging.error(f"Error restarting service {service_name}: {e}")
            return False
            
    def check_disk_space(self) -> Dict:
        """Check disk space and clean up if necessary"""
        try:
            disk_usage = psutil.disk_usage('/')
            disk_percent = (disk_usage.used / disk_usage.total) * 100
            
            result = {
                'disk_percent': disk_percent,
                'disk_free_gb': disk_usage.free / (1024**3),
                'disk_total_gb': disk_usage.total / (1024**3),
                'cleanup_performed': False
            }
            
            # Check if cleanup is needed
            threshold = self.config.get('DISK_THRESHOLD', 85)
            if disk_percent > threshold:
                logging.warning(f"Disk usage high: {disk_percent:.1f}%")
                
                # Perform cleanup
                cleanup_success = self.cleanup_disk_space()
                result['cleanup_performed'] = cleanup_success
                
                if cleanup_success:
                    # Recalculate after cleanup
                    disk_usage = psutil.disk_usage('/')
                    result['disk_percent'] = (disk_usage.used / disk_usage.total) * 100
                    result['disk_free_gb'] = disk_usage.free / (1024**3)
                    
            return result
            
        except Exception as e:
            logging.error(f"Error checking disk space: {e}")
            return {'error': str(e)}
            
    def cleanup_disk_space(self) -> bool:
        """Clean up disk space"""
        try:
            cleanup_commands = [
                # Clean package cache
                ['apt-get', 'clean'],
                # Remove old log files
                ['journalctl', '--vacuum-time=7d'],
                # Clean temporary files
                ['find', '/tmp', '-type', 'f', '-mtime', '+7', '-delete'],
                # Clean old pip cache
                ['rm', '-rf', '/root/.cache/pip/*']
            ]
            
            for cmd in cleanup_commands:
                try:
                    subprocess.run(cmd, capture_output=True, timeout=60)
                except:
                    continue
                    
            logging.info("Disk cleanup completed")
            return True
            
        except Exception as e:
            logging.error(f"Error during disk cleanup: {e}")
            return False
            
    def check_memory_pressure(self) -> Dict:
        """Check memory pressure and take action if needed"""
        try:
            memory = psutil.virtual_memory()
            swap = psutil.swap_memory()
            
            result = {
                'memory_percent': memory.percent,
                'memory_available_gb': memory.available / (1024**3),
                'swap_percent': swap.percent,
                'swap_free_gb': swap.free / (1024**3),
                'action_taken': False
            }
            
            threshold = self.config.get('MEMORY_THRESHOLD', 80)
            
            if memory.percent > threshold:
                logging.warning(f"High memory usage: {memory.percent:.1f}%")
                
                # Try to free memory
                if self.free_memory():
                    result['action_taken'] = True
                    
                    # Recalculate after cleanup
                    memory = psutil.virtual_memory()
                    result['memory_percent'] = memory.percent
                    result['memory_available_gb'] = memory.available / (1024**3)
                    
            return result
            
        except Exception as e:
            logging.error(f"Error checking memory pressure: {e}")
            return {'error': str(e)}
            
    def free_memory(self) -> bool:
        """Try to free system memory"""
        try:
            # Drop caches
            with open('/proc/sys/vm/drop_caches', 'w') as f:
                f.write('3')
                
            # Compact memory
            try:
                with open('/proc/sys/vm/compact_memory', 'w') as f:
                    f.write('1')
            except:
                pass
                
            logging.info("Memory cleanup completed")
            return True
            
        except Exception as e:
            logging.error(f"Error freeing memory: {e}")
            return False
            
    def check_system_alerts(self, metrics: Dict):
        """Check system metrics against thresholds and send alerts"""
        now = time.time()
        alert_interval = 300  # 5 minutes between same type of alerts
        
        # CPU alert
        cpu_threshold = self.config.get('CPU_THRESHOLD', 70)
        if metrics.get('cpu_percent', 0) > cpu_threshold:
            if now - self.last_alerts.get('cpu', 0) > alert_interval:
                self.notify_telegram('high_cpu', 
                                   cpu_percent=metrics['cpu_percent'],
                                   stats={
                                       'temp': metrics.get('temperature'),
                                       'memory': metrics.get('memory_percent'),
                                       'disk': metrics.get('disk_percent')
                                   })
                self.last_alerts['cpu'] = now
                
        # Temperature alert
        temp_threshold = self.config.get('TEMPERATURE_THRESHOLD', 75)
        temp = metrics.get('temperature')
        if temp and temp > temp_threshold:
            if now - self.last_alerts.get('temperature', 0) > alert_interval:
                self.notify_telegram('critical_event',
                                   event_type='High Temperature',
                                   details=f"CPU temperature: {temp}°C (threshold: {temp_threshold}°C)")
                self.last_alerts['temperature'] = now
                
        # Throttling alert
        throttled = metrics.get('throttled', {})
        if throttled.get('is_throttled', False):
            if now - self.last_alerts.get('throttling', 0) > alert_interval:
                self.notify_telegram('critical_event',
                                   event_type='System Throttling',
                                   details=f"System is being throttled: {throttled}")
                self.last_alerts['throttling'] = now
                
    def save_state(self):
        """Save current state to file"""
        try:
            state = {
                'recovery_attempts': self.recovery_attempts,
                'last_alerts': self.last_alerts,
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
                    
                self.recovery_attempts = state.get('recovery_attempts', {})
                self.last_alerts = state.get('last_alerts', {})
                
                logging.info("Previous state loaded successfully")
                
        except Exception as e:
            logging.error(f"Error loading state: {e}")
            
    def watchdog_loop(self):
        """Main watchdog monitoring loop"""
        check_interval = 60  # Check every minute
        
        while self.running:
            try:
                # Get system metrics
                metrics = self.get_system_metrics()
                
                # Check system alerts
                self.check_system_alerts(metrics)
                
                # Check critical services
                critical_services = ['access_control.service', 'network-monitor.service']
                
                for service in critical_services:
                    service_health = self.check_service_health(service)
                    
                    if not service_health['healthy'] and self.config.get('AUTO_RECOVERY', True):
                        logging.warning(f"Service {service} is unhealthy, attempting recovery")
                        self.restart_service(service)
                        
                # Check disk space
                disk_status = self.check_disk_space()
                if disk_status.get('cleanup_performed'):
                    self.notify_telegram('critical_event',
                                       event_type='Disk Cleanup',
                                       details=f"Disk cleanup performed. Usage: {disk_status.get('disk_percent', 'N/A')}%")
                    
                # Check memory pressure
                memory_status = self.check_memory_pressure()
                if memory_status.get('action_taken'):
                    self.notify_telegram('critical_event',
                                       event_type='Memory Cleanup',
                                       details=f"Memory cleanup performed. Usage: {memory_status.get('memory_percent', 'N/A')}%")
                
                # Save state
                self.save_state()
                
                # Wait for next check
                time.sleep(check_interval)
                
            except Exception as e:
                logging.error(f"Error in watchdog loop: {e}")
                time.sleep(check_interval)
                
    def run(self):
        """Main run method"""
        logging.info("Starting System Watchdog Service")
        
        # Load previous state
        self.load_state()
        
        # Start watchdog loop
        try:
            self.watchdog_loop()
        except KeyboardInterrupt:
            logging.info("Shutting down System Watchdog Service")
            self.running = False
            
def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logging.info(f"Received signal {signum}, shutting down...")
    sys.exit(0)
    
def main():
    """Main function"""
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    watchdog = SystemWatchdog()
    watchdog.run()
    
if __name__ == "__main__":
    main()