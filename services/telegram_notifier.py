#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telegram Notifier Service
Sistema Gateway 24/7 - Raspberry Pi 3B+

Handles all Telegram notifications and bot interactions.
Optimized for 24/7 operation with minimal resource usage.
"""

import os
import sys
import time
import json
import logging
import requests
import threading
import signal
import subprocess
import psutil
from datetime import datetime, timezone
from configparser import ConfigParser
from typing import Dict, Optional, List

# Configuration
CONFIG_PATH = "/opt/gateway/config/telegram.conf"
LOG_PATH = "/var/log/telegram_notifier.log"
STATE_FILE = "/tmp/telegram_notifier_state.json"

class TelegramNotifier:
    def __init__(self):
        self.config = self.load_config()
        self.bot_token = self.config.get('BOT_TOKEN')
        self.chat_id = self.config.get('CHAT_ID')
        self.running = True
        self.last_notifications = {}
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
                'BOT_TOKEN': '7954949854:AAHjEYMdvJ9z2jD8pV7fGsI0a6ipTjJHR2M',
                'CHAT_ID': '-4812920580',
                'CPU_THRESHOLD': 70,
                'MIN_NOTIFICATION_INTERVAL': 60
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
        
    def send_message(self, message: str, parse_mode: str = 'Markdown') -> bool:
        """Send message to Telegram chat"""
        try:
            url = f"https://api.telegram.org/bot{self.bot_token}/sendMessage"
            payload = {
                'chat_id': self.chat_id,
                'text': message,
                'parse_mode': parse_mode
            }
            
            response = requests.post(url, json=payload, timeout=10)
            response.raise_for_status()
            
            logging.info(f"Message sent successfully: {message[:50]}...")
            return True
            
        except Exception as e:
            logging.error(f"Failed to send message: {e}")
            return False
            
    def should_notify(self, event_type: str) -> bool:
        """Check if enough time has passed since last notification of this type"""
        now = time.time()
        last_time = self.last_notifications.get(event_type, 0)
        interval = self.config.get('MIN_NOTIFICATION_INTERVAL', 60)
        
        if now - last_time >= interval:
            self.last_notifications[event_type] = now
            return True
        return False
        
    def notify_connection_established(self, ip: str, mode: str):
        """Notify when connection is established"""
        if not self.config.get('NOTIFY_CONNECTION', True):
            return
            
        if self.should_notify('connection'):
            message = f"🟢 *Gateway Conectado*\n\n"
            message += f"📍 IP asignada: `{ip}`\n"
            message += f"🔧 Modo: *{mode}*\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            self.send_message(message)
            
    def notify_disconnection(self, connection_type: str):
        """Notify when disconnection is detected"""
        if not self.config.get('NOTIFY_DISCONNECTION', True):
            return
            
        if self.should_notify('disconnection'):
            message = f"🔴 *Desconexión Detectada*\n\n"
            message += f"🌐 Tipo: *{connection_type}*\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            self.send_message(message)
            
    def notify_tailscale_access(self, user: str, action: str):
        """Notify Tailscale user access"""
        if not self.config.get('NOTIFY_TAILSCALE_ACCESS', True):
            return
            
        if self.should_notify(f'tailscale_{user}'):
            message = f"👤 *Acceso Tailscale*\n\n"
            message += f"👥 Usuario: *{user}*\n"
            message += f"🔄 Acción: *{action}*\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            self.send_message(message)
            
    def notify_high_cpu(self, cpu_percent: float, stats: Dict):
        """Notify high CPU usage"""
        if not self.config.get('NOTIFY_CPU_HIGH', True):
            return
            
        threshold = self.config.get('CPU_THRESHOLD', 70)
        if cpu_percent > threshold and self.should_notify('high_cpu'):
            message = f"⚠️ *CPU Alto ({cpu_percent:.1f}%)*\n\n"
            message += f"🔥 Temperatura: {stats.get('temp', 'N/A')}°C\n"
            message += f"💾 Memoria: {stats.get('memory', 'N/A')}%\n"
            message += f"💿 Disco: {stats.get('disk', 'N/A')}%\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            self.send_message(message)
            
    def notify_critical_event(self, event_type: str, details: str):
        """Notify critical system events"""
        if not self.config.get('NOTIFY_CRITICAL_EVENTS', True):
            return
            
        if self.should_notify(f'critical_{event_type}'):
            message = f"🚨 *Evento Crítico*\n\n"
            message += f"📋 Tipo: *{event_type}*\n"
            message += f"📝 Detalles: {details}\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            self.send_message(message)
            
    def notify_mode_change(self, old_mode: str, new_mode: str):
        """Notify network mode changes"""
        if not self.config.get('NOTIFY_MODE_CHANGES', True):
            return
            
        if self.should_notify('mode_change'):
            message = f"🔄 *Cambio de Modo*\n\n"
            message += f"📤 Anterior: *{old_mode}*\n"
            message += f"📥 Nuevo: *{new_mode}*\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            self.send_message(message)
            
    def get_system_status(self) -> str:
        """Get comprehensive system status"""
        try:
            # System metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            # Temperature
            temp = "N/A"
            try:
                result = subprocess.run(['vcgencmd', 'measure_temp'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    temp = result.stdout.strip().replace('temp=', '').replace("'C", '')
            except:
                pass
            
            # Network info
            try:
                ip_result = subprocess.run(['hostname', '-I'], 
                                         capture_output=True, text=True, timeout=5)
                ip_addr = ip_result.stdout.strip().split()[0] if ip_result.returncode == 0 else "N/A"
            except:
                ip_addr = "N/A"
            
            # Uptime
            try:
                uptime = subprocess.run(['uptime', '-p'], 
                                      capture_output=True, text=True, timeout=5)
                uptime_str = uptime.stdout.strip() if uptime.returncode == 0 else "N/A"
            except:
                uptime_str = "N/A"
            
            message = f"📊 *Estado del Sistema*\n\n"
            message += f"🖥️ CPU: {cpu_percent:.1f}%\n"
            message += f"💾 Memoria: {memory.percent:.1f}%\n"
            message += f"💿 Disco: {disk.percent:.1f}%\n"
            message += f"🌡️ Temperatura: {temp}°C\n"
            message += f"🌐 IP: `{ip_addr}`\n"
            message += f"⏱️ Uptime: {uptime_str}\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            
            return message
            
        except Exception as e:
            return f"❌ Error obteniendo estado: {str(e)}"
            
    def handle_bot_command(self, command: str) -> str:
        """Handle incoming bot commands"""
        command = command.lower().strip()
        
        if command == '/status':
            return self.get_system_status()
            
        elif command == '/users':
            return self.get_tailscale_users()
            
        elif command == '/logs':
            return self.get_recent_logs()
            
        elif command == '/health':
            return self.get_health_diagnostics()
            
        elif command == '/temp':
            return self.get_temperature_info()
            
        elif command == '/network':
            return self.get_network_info()
            
        elif command.startswith('/restart'):
            service = command.split()[-1] if len(command.split()) > 1 else 'all'
            return self.restart_service(service)
            
        else:
            return self.get_help_message()
            
    def get_tailscale_users(self) -> str:
        """Get currently connected Tailscale users"""
        try:
            result = subprocess.run(['tailscale', 'status'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                active_users = []
                for line in lines[1:]:  # Skip header
                    if line.strip():
                        parts = line.split()
                        if len(parts) >= 2:
                            active_users.append(f"• {parts[1]}")
                
                if active_users:
                    message = f"👥 *Usuarios Tailscale Activos*\n\n"
                    message += '\n'.join(active_users)
                else:
                    message = "👥 *No hay usuarios Tailscale conectados*"
            else:
                message = "❌ Error obteniendo usuarios Tailscale"
                
        except Exception as e:
            message = f"❌ Error: {str(e)}"
            
        return message
        
    def get_recent_logs(self) -> str:
        """Get recent important system events"""
        try:
            logs = []
            
            # Get systemd logs for key services
            services = ['access_control.service', 'network-monitor.service', 'tailscale.service']
            
            for service in services:
                try:
                    result = subprocess.run([
                        'journalctl', '-u', service, '--since', '1 hour ago', 
                        '--no-pager', '-n', '3', '--output', 'short'
                    ], capture_output=True, text=True, timeout=10)
                    
                    if result.returncode == 0 and result.stdout.strip():
                        logs.extend(result.stdout.strip().split('\n')[-2:])
                except:
                    continue
            
            if logs:
                message = f"📝 *Eventos Recientes*\n\n"
                for log in logs[-10:]:  # Last 10 events
                    if log.strip():
                        # Truncate long log lines
                        log_short = log[:80] + "..." if len(log) > 80 else log
                        message += f"• {log_short}\n"
            else:
                message = "📝 *No hay eventos recientes*"
                
        except Exception as e:
            message = f"❌ Error obteniendo logs: {str(e)}"
            
        return message
        
    def get_health_diagnostics(self) -> str:
        """Get comprehensive health diagnostics"""
        try:
            # System load
            load1, load5, load15 = psutil.getloadavg()
            
            # Memory details
            memory = psutil.virtual_memory()
            
            # Disk I/O
            disk_io = psutil.disk_io_counters()
            
            # Network stats
            net_io = psutil.net_io_counters()
            
            # Service status
            services_ok = 0
            services_total = 3
            
            for service in ['access_control.service', 'network-monitor.service']:
                try:
                    result = subprocess.run(['systemctl', 'is-active', service], 
                                          capture_output=True, text=True, timeout=5)
                    if result.stdout.strip() == 'active':
                        services_ok += 1
                except:
                    pass
            
            message = f"🏥 *Diagnóstico Completo*\n\n"
            message += f"📈 Load: {load1:.2f}, {load5:.2f}, {load15:.2f}\n"
            message += f"💾 RAM libre: {memory.available // 1024 // 1024} MB\n"
            message += f"📊 Servicios: {services_ok}/{services_total} OK\n"
            message += f"💿 Disco I/O: {disk_io.read_count}/{disk_io.write_count}\n"
            message += f"🌐 Red: ↓{net_io.bytes_recv // 1024 // 1024}MB ↑{net_io.bytes_sent // 1024 // 1024}MB\n"
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            
        except Exception as e:
            message = f"❌ Error en diagnóstico: {str(e)}"
            
        return message
        
    def get_temperature_info(self) -> str:
        """Get temperature information and history"""
        try:
            # Current temperature
            temp = "N/A"
            try:
                result = subprocess.run(['vcgencmd', 'measure_temp'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    temp = result.stdout.strip().replace('temp=', '').replace("'C", '')
            except:
                pass
            
            # Throttling status
            throttle_status = "N/A"
            try:
                result = subprocess.run(['vcgencmd', 'get_throttled'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    throttle_hex = result.stdout.strip().replace('throttled=', '')
                    throttle_int = int(throttle_hex, 16)
                    throttle_status = "Normal" if throttle_int == 0 else f"Throttled ({throttle_hex})"
            except:
                pass
            
            message = f"🌡️ *Información de Temperatura*\n\n"
            message += f"🔥 Temperatura actual: {temp}°C\n"
            message += f"⚡ Estado throttling: {throttle_status}\n"
            
            # Temperature thresholds
            try:
                temp_float = float(temp)
                if temp_float > 75:
                    message += f"⚠️ Temperatura alta\n"
                elif temp_float > 85:
                    message += f"🚨 Temperatura crítica\n"
                else:
                    message += f"✅ Temperatura normal\n"
            except:
                pass
            
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            
        except Exception as e:
            message = f"❌ Error obteniendo temperatura: {str(e)}"
            
        return message
        
    def get_network_info(self) -> str:
        """Get network connection information"""
        try:
            message = f"🌐 *Estado de Red*\n\n"
            
            # Ethernet status
            try:
                result = subprocess.run(['ip', 'addr', 'show', 'eth0'], 
                                      capture_output=True, text=True, timeout=5)
                if 'UP' in result.stdout:
                    eth_ip = "Disconnected"
                    for line in result.stdout.split('\n'):
                        if 'inet ' in line and not '127.0.0.1' in line:
                            eth_ip = line.strip().split()[1]
                            break
                    message += f"🔌 Ethernet: {eth_ip}\n"
                else:
                    message += f"🔌 Ethernet: Down\n"
            except:
                message += f"🔌 Ethernet: Error\n"
            
            # WiFi status
            try:
                result = subprocess.run(['iwgetid', '-r'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0 and result.stdout.strip():
                    ssid = result.stdout.strip()
                    message += f"📶 WiFi: {ssid}\n"
                else:
                    message += f"📶 WiFi: Disconnected\n"
            except:
                message += f"📶 WiFi: Error\n"
            
            # Tailscale status
            try:
                result = subprocess.run(['tailscale', 'ip'], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0 and result.stdout.strip():
                    ts_ip = result.stdout.strip()
                    message += f"🔒 Tailscale: {ts_ip}\n"
                else:
                    message += f"🔒 Tailscale: Disconnected\n"
            except:
                message += f"🔒 Tailscale: Not installed\n"
            
            # Ping test
            try:
                result = subprocess.run(['ping', '-c', '1', '-W', '3', '8.8.8.8'], 
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    message += f"🌍 Internet: ✅ Connected\n"
                else:
                    message += f"🌍 Internet: ❌ No connection\n"
            except:
                message += f"🌍 Internet: ❌ Error testing\n"
            
            message += f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            
        except Exception as e:
            message = f"❌ Error obteniendo info de red: {str(e)}"
            
        return message
        
    def restart_service(self, service: str) -> str:
        """Restart specified service remotely"""
        try:
            if service == 'all':
                services = ['access_control.service', 'network-monitor.service']
                results = []
                for svc in services:
                    try:
                        subprocess.run(['systemctl', 'restart', svc], 
                                     timeout=30, check=True)
                        results.append(f"✅ {svc}")
                    except:
                        results.append(f"❌ {svc}")
                
                message = f"🔄 *Reinicio de Servicios*\n\n"
                message += '\n'.join(results)
                
            else:
                # Single service restart
                valid_services = ['access_control.service', 'network-monitor.service', 'tailscale.service']
                if f"{service}.service" in valid_services or service in valid_services:
                    service_name = service if service.endswith('.service') else f"{service}.service"
                    subprocess.run(['systemctl', 'restart', service_name], 
                                 timeout=30, check=True)
                    message = f"✅ Servicio {service_name} reiniciado"
                else:
                    message = f"❌ Servicio no válido: {service}"
                    
        except subprocess.TimeoutExpired:
            message = f"⏱️ Timeout reiniciando {service}"
        except Exception as e:
            message = f"❌ Error reiniciando {service}: {str(e)}"
            
        return message
        
    def get_help_message(self) -> str:
        """Get help message with available commands"""
        message = f"🤖 *Bot Gateway 24/7*\n\n"
        message += f"*Comandos disponibles:*\n\n"
        message += f"📊 `/status` - Estado completo del sistema\n"
        message += f"👥 `/users` - Usuarios Tailscale conectados\n"
        message += f"📝 `/logs` - Últimos 10 eventos importantes\n"
        message += f"🔄 `/restart [servicio]` - Reinicio remoto\n"
        message += f"🏥 `/health` - Diagnóstico completo\n"
        message += f"🌡️ `/temp` - Temperatura actual\n"
        message += f"🌐 `/network` - Estado de conexiones\n\n"
        message += f"*Ejemplos:*\n"
        message += f"• `/restart all` - Reinicia todos los servicios\n"
        message += f"• `/restart access_control` - Reinicia servicio específico"
        
        return message
        
    def start_bot_listener(self):
        """Start listening for bot commands (basic polling)"""
        offset = 0
        
        while self.running:
            try:
                url = f"https://api.telegram.org/bot{self.bot_token}/getUpdates"
                params = {'offset': offset, 'timeout': 30}
                
                response = requests.get(url, params=params, timeout=35)
                response.raise_for_status()
                
                data = response.json()
                
                if data['ok']:
                    for update in data['result']:
                        offset = update['update_id'] + 1
                        
                        if 'message' in update and 'text' in update['message']:
                            text = update['message']['text']
                            chat_id = str(update['message']['chat']['id'])
                            
                            # Only respond to messages from configured chat
                            if chat_id == str(self.chat_id):
                                response_text = self.handle_bot_command(text)
                                self.send_message(response_text)
                                
            except requests.exceptions.Timeout:
                # Expected for long polling
                continue
            except Exception as e:
                logging.error(f"Bot listener error: {e}")
                time.sleep(5)
                
    def run(self):
        """Main run loop"""
        logging.info("Starting Telegram Notifier Service")
        
        # Send startup notification
        self.send_message("🟢 *Gateway Sistema 24/7*\n\nServicio de notificaciones iniciado correctamente")
        
        # Start bot listener in separate thread
        bot_thread = threading.Thread(target=self.start_bot_listener, daemon=True)
        bot_thread.start()
        
        # Main monitoring loop
        try:
            while self.running:
                time.sleep(10)  # Keep service alive
                
        except KeyboardInterrupt:
            logging.info("Shutting down Telegram Notifier Service")
            self.running = False
            
def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logging.info(f"Received signal {signum}, shutting down...")
    sys.exit(0)
    
def main():
    """Main function"""
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    notifier = TelegramNotifier()
    notifier.run()
    
if __name__ == "__main__":
    main()