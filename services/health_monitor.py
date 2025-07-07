#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Health Monitor Service
Sistema Gateway 24/7 - Raspberry Pi 3B+

Performs comprehensive health checks and generates reports.
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
import requests
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional

# Configuration
CONFIG_PATH = "/opt/gateway/config/monitoring.conf"
LOG_PATH = "/var/log/health_monitor.log"
REPORT_PATH = "/tmp/health_reports"

class HealthMonitor:
    def __init__(self):
        self.config = self.load_config()
        self.running = True
        self.health_history = []
        self.setup_logging()
        os.makedirs(REPORT_PATH, exist_ok=True)
        
    def load_config(self) -> Dict:
        """Load configuration from file"""
        config = {}
        try:
            with open(CONFIG_PATH, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        if value.lower() in ('true', 'false'):
                            value = value.lower() == 'true'
                        elif value.isdigit():
                            value = int(value)
                        config[key.strip()] = value
        except Exception as e:
            logging.error(f"Error loading config: {e}")
            config = {
                'HEALTH_CHECK_INTERVAL': 300,
                'CONNECTIVITY_CHECK_INTERVAL': 30,
                'SERVICE_CHECK_INTERVAL': 60,
                'DISK_CHECK_INTERVAL': 3600
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
            
            if message_type == 'disconnection':
                notifier.notify_disconnection(kwargs.get('connection_type', 'Unknown'))
            elif message_type == 'connection_established':
                notifier.notify_connection_established(kwargs.get('ip', 'Unknown'), 
                                                     kwargs.get('mode', 'Unknown'))
                                                     
        except Exception as e:
            logging.error(f"Failed to send Telegram notification: {e}")
            
    def check_network_connectivity(self) -> Dict:
        """Check various network connectivity options"""
        connectivity = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'ethernet': False,
            'wifi': False,
            'tailscale': False,
            'internet': False,
            'details': {}
        }
        
        try:
            # Check Ethernet
            result = subprocess.run(['ip', 'addr', 'show', 'eth0'], 
                                  capture_output=True, text=True, timeout=5)
            if 'UP' in result.stdout:
                for line in result.stdout.split('\n'):
                    if 'inet ' in line and not '127.0.0.1' in line:
                        connectivity['ethernet'] = True
                        connectivity['details']['ethernet_ip'] = line.strip().split()[1]
                        break
            
            # Check WiFi
            try:
                result = subprocess.run(['iwgetid', '-r'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0 and result.stdout.strip():
                    connectivity['wifi'] = True
                    connectivity['details']['wifi_ssid'] = result.stdout.strip()
            except:
                pass
            
            # Check Tailscale
            try:
                result = subprocess.run(['tailscale', 'ip'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0 and result.stdout.strip():
                    connectivity['tailscale'] = True
                    connectivity['details']['tailscale_ip'] = result.stdout.strip()
            except:
                pass
            
            # Check Internet connectivity
            test_hosts = ['8.8.8.8', '1.1.1.1', 'google.com']
            for host in test_hosts:
                try:
                    result = subprocess.run(['ping', '-c', '1', '-W', '3', host], 
                                          capture_output=True, text=True, timeout=10)
                    if result.returncode == 0:
                        connectivity['internet'] = True
                        connectivity['details']['internet_test_host'] = host
                        break
                except:
                    continue
                    
        except Exception as e:
            connectivity['error'] = str(e)
            
        return connectivity
        
    def check_service_status(self) -> Dict:
        """Check status of all critical services"""
        services = {
            'access_control.service': False,
            'network-monitor.service': False,
            'tailscaled.service': False,
            'systemd-resolved.service': False,
            'NetworkManager.service': False
        }
        
        service_details = {}
        
        for service in services.keys():
            try:
                result = subprocess.run(['systemctl', 'is-active', service], 
                                      capture_output=True, text=True, timeout=5)
                services[service] = result.stdout.strip() == 'active'
                
                # Get more details
                result = subprocess.run(['systemctl', 'status', service], 
                                      capture_output=True, text=True, timeout=5)
                
                # Extract memory usage if available
                for line in result.stdout.split('\n'):
                    if 'Memory:' in line:
                        try:
                            memory = line.split('Memory:')[1].strip()
                            service_details[service] = {'memory': memory}
                        except:
                            pass
                        break
                        
            except Exception as e:
                logging.error(f"Error checking service {service}: {e}")
                
        return {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'services': services,
            'details': service_details,
            'healthy_count': sum(services.values()),
            'total_count': len(services)
        }
        
    def check_hardware_health(self) -> Dict:
        """Check hardware health metrics"""
        health = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'cpu_temperature': None,
            'throttling': {},
            'voltage': None,
            'clock_speeds': {},
            'hardware_errors': []
        }
        
        try:
            # CPU Temperature
            result = subprocess.run(['vcgencmd', 'measure_temp'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                temp_str = result.stdout.strip().replace('temp=', '').replace("'C", '')
                health['cpu_temperature'] = float(temp_str)
                
            # Throttling status
            result = subprocess.run(['vcgencmd', 'get_throttled'], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                throttle_hex = result.stdout.strip().replace('throttled=', '')
                throttle_int = int(throttle_hex, 16)
                health['throttling'] = {
                    'raw_value': throttle_hex,
                    'is_throttled': throttle_int != 0,
                    'under_voltage': bool(throttle_int & 0x1),
                    'frequency_capped': bool(throttle_int & 0x2),
                    'currently_throttled': bool(throttle_int & 0x4),
                    'soft_temp_limit': bool(throttle_int & 0x8)
                }
                
            # Voltage measurements
            for component in ['core', 'sdram_c', 'sdram_i', 'sdram_p']:
                try:
                    result = subprocess.run(['vcgencmd', 'measure_volts', component], 
                                          capture_output=True, text=True, timeout=5)
                    if result.returncode == 0:
                        voltage_str = result.stdout.strip().replace('volt=', '').replace('V', '')
                        if health['voltage'] is None:
                            health['voltage'] = {}
                        health['voltage'][component] = float(voltage_str)
                except:
                    pass
                    
            # Clock speeds
            for clock in ['arm', 'core', 'h264', 'isp', 'v3d', 'uart', 'pwm', 'emmc', 'pixel', 'vec', 'hdmi', 'dpi']:
                try:
                    result = subprocess.run(['vcgencmd', 'measure_clock', clock], 
                                          capture_output=True, text=True, timeout=5)
                    if result.returncode == 0:
                        clock_str = result.stdout.strip().replace(f'frequency({clock})=', '')
                        health['clock_speeds'][clock] = int(clock_str)
                except:
                    pass
                    
        except Exception as e:
            health['error'] = str(e)
            
        return health
        
    def check_storage_health(self) -> Dict:
        """Check storage health and performance"""
        storage = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'disk_usage': {},
            'io_stats': {},
            'mount_points': [],
            'health_status': 'unknown'
        }
        
        try:
            # Disk usage for all mount points
            for partition in psutil.disk_partitions():
                try:
                    usage = psutil.disk_usage(partition.mountpoint)
                    storage['disk_usage'][partition.mountpoint] = {
                        'total_gb': usage.total / (1024**3),
                        'used_gb': usage.used / (1024**3),
                        'free_gb': usage.free / (1024**3),
                        'percent': (usage.used / usage.total) * 100,
                        'filesystem': partition.fstype
                    }
                    storage['mount_points'].append(partition.mountpoint)
                except:
                    pass
                    
            # I/O statistics
            io_counters = psutil.disk_io_counters()
            if io_counters:
                storage['io_stats'] = {
                    'read_count': io_counters.read_count,
                    'write_count': io_counters.write_count,
                    'read_bytes': io_counters.read_bytes,
                    'write_bytes': io_counters.write_bytes,
                    'read_time': io_counters.read_time,
                    'write_time': io_counters.write_time
                }
                
            # Try to get SD card health (Raspberry Pi specific)
            try:
                # Check for read-only filesystem (common SD card failure)
                result = subprocess.run(['mount'], capture_output=True, text=True, timeout=5)
                if 'ro,' in result.stdout or '(ro)' in result.stdout:
                    storage['health_status'] = 'readonly_detected'
                else:
                    storage['health_status'] = 'healthy'
            except:
                pass
                
        except Exception as e:
            storage['error'] = str(e)
            
        return storage
        
    def perform_connectivity_test(self) -> Dict:
        """Perform comprehensive connectivity tests"""
        test_results = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'local_network': False,
            'dns_resolution': False,
            'external_connectivity': False,
            'tailscale_mesh': False,
            'latency_tests': {},
            'speed_test': {}
        }
        
        try:
            # Local network test (ping gateway)
            try:
                gateway = subprocess.run(['ip', 'route', 'show', 'default'], 
                                       capture_output=True, text=True, timeout=5)
                if gateway.returncode == 0:
                    gateway_ip = gateway.stdout.split()[2]
                    result = subprocess.run(['ping', '-c', '3', '-W', '2', gateway_ip], 
                                          capture_output=True, text=True, timeout=15)
                    if result.returncode == 0:
                        test_results['local_network'] = True
                        # Extract latency
                        for line in result.stdout.split('\n'):
                            if 'round-trip' in line or 'rtt' in line:
                                test_results['latency_tests']['gateway'] = line.strip()
                                break
            except:
                pass
                
            # DNS resolution test
            try:
                result = subprocess.run(['nslookup', 'google.com'], 
                                      capture_output=True, text=True, timeout=10)
                test_results['dns_resolution'] = result.returncode == 0
            except:
                pass
                
            # External connectivity test
            external_hosts = ['8.8.8.8', '1.1.1.1', 'google.com']
            for host in external_hosts:
                try:
                    result = subprocess.run(['ping', '-c', '3', '-W', '2', host], 
                                          capture_output=True, text=True, timeout=15)
                    if result.returncode == 0:
                        test_results['external_connectivity'] = True
                        # Extract latency
                        for line in result.stdout.split('\n'):
                            if 'round-trip' in line or 'rtt' in line:
                                test_results['latency_tests'][host] = line.strip()
                                break
                        break
                except:
                    continue
                    
            # Tailscale mesh connectivity
            try:
                result = subprocess.run(['tailscale', 'ping', '--verbose', '--c', '3', 'login.tailscale.com'], 
                                      capture_output=True, text=True, timeout=20)
                test_results['tailscale_mesh'] = result.returncode == 0
                if result.returncode == 0:
                    test_results['latency_tests']['tailscale'] = result.stdout.strip()
            except:
                pass
                
        except Exception as e:
            test_results['error'] = str(e)
            
        return test_results
        
    def generate_health_report(self) -> Dict:
        """Generate comprehensive health report"""
        report = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'system_info': self.get_system_info(),
            'connectivity': self.check_network_connectivity(),
            'services': self.check_service_status(),
            'hardware': self.check_hardware_health(),
            'storage': self.check_storage_health(),
            'performance': self.get_performance_metrics(),
            'overall_health': 'unknown'
        }
        
        # Calculate overall health score
        health_score = 0
        max_score = 0
        
        # Connectivity score (25 points)
        max_score += 25
        if report['connectivity'].get('internet'):
            health_score += 15
        if report['connectivity'].get('ethernet') or report['connectivity'].get('wifi'):
            health_score += 10
            
        # Services score (25 points)
        max_score += 25
        services = report['services'].get('services', {})
        critical_services = ['access_control.service', 'network-monitor.service']
        for service in critical_services:
            if services.get(service, False):
                health_score += 12.5
                
        # Hardware score (25 points)
        max_score += 25
        hardware = report['hardware']
        temp = hardware.get('cpu_temperature')
        if temp and temp < 75:
            health_score += 15
        elif temp and temp < 85:
            health_score += 10
        elif temp and temp < 90:
            health_score += 5
            
        throttling = hardware.get('throttling', {})
        if not throttling.get('is_throttled', True):
            health_score += 10
            
        # Storage score (25 points)
        max_score += 25
        storage = report['storage']
        disk_usage = storage.get('disk_usage', {})
        root_usage = disk_usage.get('/', {})
        if root_usage:
            usage_percent = root_usage.get('percent', 100)
            if usage_percent < 70:
                health_score += 15
            elif usage_percent < 85:
                health_score += 10
            elif usage_percent < 95:
                health_score += 5
                
        if storage.get('health_status') == 'healthy':
            health_score += 10
            
        # Calculate final health status
        health_percentage = (health_score / max_score) * 100 if max_score > 0 else 0
        
        if health_percentage >= 90:
            report['overall_health'] = 'excellent'
        elif health_percentage >= 75:
            report['overall_health'] = 'good'
        elif health_percentage >= 50:
            report['overall_health'] = 'fair'
        elif health_percentage >= 25:
            report['overall_health'] = 'poor'
        else:
            report['overall_health'] = 'critical'
            
        report['health_score'] = health_percentage
        
        return report
        
    def get_system_info(self) -> Dict:
        """Get basic system information"""
        info = {
            'hostname': subprocess.run(['hostname'], capture_output=True, text=True).stdout.strip(),
            'uptime': time.time() - psutil.boot_time(),
            'load_avg': psutil.getloadavg(),
            'cpu_count': psutil.cpu_count(),
            'memory_total': psutil.virtual_memory().total,
            'kernel_version': subprocess.run(['uname', '-r'], capture_output=True, text=True).stdout.strip()
        }
        
        try:
            # Get Raspberry Pi model
            with open('/proc/device-tree/model', 'r') as f:
                info['pi_model'] = f.read().strip()
        except:
            info['pi_model'] = 'Unknown'
            
        return info
        
    def get_performance_metrics(self) -> Dict:
        """Get performance metrics"""
        return {
            'cpu_percent': psutil.cpu_percent(interval=1),
            'memory_percent': psutil.virtual_memory().percent,
            'cpu_freq': psutil.cpu_freq()._asdict() if psutil.cpu_freq() else {},
            'cpu_times': psutil.cpu_times()._asdict(),
            'memory_info': psutil.virtual_memory()._asdict(),
            'swap_info': psutil.swap_memory()._asdict(),
            'process_count': len(psutil.pids()),
            'network_io': psutil.net_io_counters()._asdict(),
            'disk_io': psutil.disk_io_counters()._asdict() if psutil.disk_io_counters() else {}
        }
        
    def save_health_report(self, report: Dict):
        """Save health report to file"""
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f"health_report_{timestamp}.json"
            filepath = os.path.join(REPORT_PATH, filename)
            
            with open(filepath, 'w') as f:
                json.dump(report, f, indent=2, default=str)
                
            logging.info(f"Health report saved: {filepath}")
            
            # Clean up old reports (keep last 24 hours)
            self.cleanup_old_reports()
            
        except Exception as e:
            logging.error(f"Error saving health report: {e}")
            
    def cleanup_old_reports(self):
        """Clean up old health reports"""
        try:
            cutoff_time = time.time() - (24 * 60 * 60)  # 24 hours ago
            
            for filename in os.listdir(REPORT_PATH):
                filepath = os.path.join(REPORT_PATH, filename)
                if os.path.isfile(filepath) and os.path.getmtime(filepath) < cutoff_time:
                    os.remove(filepath)
                    
        except Exception as e:
            logging.error(f"Error cleaning up old reports: {e}")
            
    def monitor_loop(self):
        """Main monitoring loop"""
        health_check_interval = self.config.get('HEALTH_CHECK_INTERVAL', 300)
        connectivity_check_interval = self.config.get('CONNECTIVITY_CHECK_INTERVAL', 30)
        last_health_check = 0
        last_connectivity_check = 0
        
        while self.running:
            try:
                current_time = time.time()
                
                # Connectivity check (more frequent)
                if current_time - last_connectivity_check >= connectivity_check_interval:
                    connectivity = self.check_network_connectivity()
                    
                    # Store in history for trend analysis
                    self.health_history.append({
                        'timestamp': connectivity['timestamp'],
                        'type': 'connectivity',
                        'data': connectivity
                    })
                    
                    # Keep only last 100 entries
                    if len(self.health_history) > 100:
                        self.health_history.pop(0)
                        
                    last_connectivity_check = current_time
                    
                # Full health check (less frequent)
                if current_time - last_health_check >= health_check_interval:
                    report = self.generate_health_report()
                    self.save_health_report(report)
                    
                    # Log health status
                    health_status = report.get('overall_health', 'unknown')
                    health_score = report.get('health_score', 0)
                    logging.info(f"Health check: {health_status} ({health_score:.1f}%)")
                    
                    last_health_check = current_time
                    
                # Sleep for a short interval
                time.sleep(10)
                
            except Exception as e:
                logging.error(f"Error in monitor loop: {e}")
                time.sleep(health_check_interval)
                
    def generate_weekly_report(self) -> str:
        """Generate weekly summary report"""
        try:
            # Get reports from the last week
            week_ago = time.time() - (7 * 24 * 60 * 60)
            weekly_reports = []
            
            for filename in os.listdir(REPORT_PATH):
                filepath = os.path.join(REPORT_PATH, filename)
                if os.path.isfile(filepath) and os.path.getmtime(filepath) > week_ago:
                    try:
                        with open(filepath, 'r') as f:
                            report = json.load(f)
                            weekly_reports.append(report)
                    except:
                        continue
                        
            if not weekly_reports:
                return "📊 *Reporte Semanal*\n\nNo hay datos suficientes para generar reporte"
                
            # Calculate averages and trends
            avg_health = sum(r.get('health_score', 0) for r in weekly_reports) / len(weekly_reports)
            avg_cpu = sum(r.get('performance', {}).get('cpu_percent', 0) for r in weekly_reports) / len(weekly_reports)
            avg_memory = sum(r.get('performance', {}).get('memory_percent', 0) for r in weekly_reports) / len(weekly_reports)
            
            # Count connectivity issues
            connectivity_issues = sum(1 for r in weekly_reports if not r.get('connectivity', {}).get('internet', True))
            
            # Service uptime
            service_checks = len(weekly_reports)
            access_control_up = sum(1 for r in weekly_reports if r.get('services', {}).get('services', {}).get('access_control.service', False))
            uptime_percentage = (access_control_up / service_checks * 100) if service_checks > 0 else 0
            
            # Temperature analysis
            temps = [r.get('hardware', {}).get('cpu_temperature') for r in weekly_reports if r.get('hardware', {}).get('cpu_temperature')]
            avg_temp = sum(temps) / len(temps) if temps else 0
            max_temp = max(temps) if temps else 0
            
            message = f"📊 *Reporte Semanal Sistema Gateway*\n\n"
            message += f"📈 **Salud General**: {avg_health:.1f}%\n"
            message += f"⚡ **Uptime Servicios**: {uptime_percentage:.1f}%\n"
            message += f"🖥️ **CPU Promedio**: {avg_cpu:.1f}%\n"
            message += f"💾 **Memoria Promedio**: {avg_memory:.1f}%\n"
            message += f"🌡️ **Temperatura**: {avg_temp:.1f}°C (máx: {max_temp:.1f}°C)\n"
            message += f"🌐 **Problemas Conectividad**: {connectivity_issues}\n"
            message += f"📊 **Reportes Analizados**: {len(weekly_reports)}\n\n"
            
            if avg_health >= 90:
                message += "✅ Sistema funcionando excelentemente"
            elif avg_health >= 75:
                message += "✅ Sistema funcionando bien"
            elif avg_health >= 50:
                message += "⚠️ Sistema necesita atención"
            else:
                message += "🚨 Sistema requiere mantenimiento inmediato"
                
            return message
            
        except Exception as e:
            return f"❌ Error generando reporte semanal: {str(e)}"
            
    def run(self):
        """Main run method"""
        logging.info("Starting Health Monitor Service")
        
        # Start monitoring loop
        try:
            self.monitor_loop()
        except KeyboardInterrupt:
            logging.info("Shutting down Health Monitor Service")
            self.running = False
            
def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logging.info(f"Received signal {signum}, shutting down...")
    sys.exit(0)
    
def main():
    """Main function"""
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    monitor = HealthMonitor()
    monitor.run()
    
if __name__ == "__main__":
    main()