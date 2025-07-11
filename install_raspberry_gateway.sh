#!/bin/bash

# ============================================
# RASPBERRY PI 3B+ GATEWAY INSTALLATION SCRIPT
# ============================================
# Version: 1.0
# Description: Single comprehensive installation script for Raspberry Pi 3B+ gateway
# Requirements: Raspberry Pi OS Lite, TP-Link as external AP
# Features: Flask web portal, Tailscale VPN, WiFi configuration portal
# 
# IMPORTANT: This script does NOT configure internal AP (hostapd/dnsmasq)
# It uses an external TP-Link device as AP and configures ethernet only
# ============================================

set -e  # Exit on any error

# ============================================
# CONSTANTS AND CONFIGURATION
# ============================================
SCRIPT_VERSION="1.0"
SCRIPT_NAME="Raspberry Pi Gateway Installer"
LOG_FILE="/var/log/raspberry_gateway_install.log"
CONFIG_DIR="/opt/raspberry_gateway"
SERVICE_NAME="raspberry_gateway.service"
REVERT_SERVICE_NAME="ethernet_dhcp_revert.service"

# Network Configuration
STATIC_IP="192.168.4.100"
STATIC_NETMASK="24"
STATIC_GATEWAY="192.168.4.1"
STATIC_DNS="8.8.8.8,8.8.4.4"
ETH_INTERFACE="eth0"
WEB_PORT="8080"

# Tailscale Configuration
TAILSCALE_AUTH_KEY="tskey-auth-kpNN1bCPr321CNTRL-QnTaeC2BWaCJE5TY9RJEaCDns9BEzpDZb"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# LOGGING AND UTILITY FUNCTIONS
# ============================================

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    log_message "WARN" "$1"
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    log_message "ERROR" "$1"
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    log_message "SUCCESS" "$1"
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Check log file: $LOG_FILE"
    exit 1
}

trap 'error_handler $LINENO' ERR

# ============================================
# SYSTEM VALIDATION FUNCTIONS
# ============================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Usage: sudo $0"
        exit 1
    fi
}

check_raspberry_pi() {
    log_info "Checking if running on Raspberry Pi..."
    
    if [ ! -f /proc/device-tree/model ]; then
        log_warn "Cannot detect Raspberry Pi model"
        return 0
    fi
    
    local model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
    log_info "Detected device: $model"
    
    if [[ "$model" =~ "Raspberry Pi" ]]; then
        log_success "Raspberry Pi detected"
        return 0
    else
        log_warn "Not running on Raspberry Pi, proceeding anyway"
        return 0
    fi
}

check_internet_connectivity() {
    log_info "Checking internet connectivity..."
    
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_success "Internet connectivity confirmed"
        return 0
    else
        log_error "No internet connectivity - installation cannot proceed"
        log_error "Please ensure the device is connected to internet before running this script"
        exit 1
    fi
}

backup_existing_configs() {
    log_info "Creando backup completo de configuraciones existentes..."
    
    local backup_dir="/root/gateway_config_backup_$(date +%s)"
    mkdir -p "$backup_dir"
    
    log_info "Directorio de backup: $backup_dir"
    
    # Backup network configurations with detailed logging
    if [ -f /etc/network/interfaces ]; then
        cp /etc/network/interfaces "$backup_dir/" && \
        log_info "✓ Backup creado: /etc/network/interfaces"
    fi
    
    if [ -f /etc/dhcpcd.conf ]; then
        cp /etc/dhcpcd.conf "$backup_dir/" && \
        log_info "✓ Backup creado: /etc/dhcpcd.conf"
    fi
    
    if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
        cp /etc/wpa_supplicant/wpa_supplicant.conf "$backup_dir/" && \
        log_info "✓ Backup creado: /etc/wpa_supplicant/wpa_supplicant.conf"
    fi
    
    # Backup systemd network configs if they exist
    if [ -d /etc/systemd/network ]; then
        cp -r /etc/systemd/network "$backup_dir/" && \
        log_info "✓ Backup creado: /etc/systemd/network/"
    fi
    
    # Backup NetworkManager configurations
    if [ -d /etc/NetworkManager ]; then
        cp -r /etc/NetworkManager "$backup_dir/" && \
        log_info "✓ Backup creado: /etc/NetworkManager/"
    fi
    
    # Save current network state
    log_info "Guardando estado actual de red..."
    ip addr show > "$backup_dir/current_ip_addresses.txt"
    ip route show > "$backup_dir/current_routes.txt"
    cat /etc/resolv.conf > "$backup_dir/current_dns.txt" 2>/dev/null || true
    
    # Save NetworkManager connections if available
    if command -v nmcli >/dev/null 2>&1; then
        nmcli connection show > "$backup_dir/nmcli_connections.txt" 2>/dev/null || true
        nmcli device status > "$backup_dir/nmcli_devices.txt" 2>/dev/null || true
    fi
    
    # Create restore script
    cat > "$backup_dir/restore_network.sh" << EOF
#!/bin/bash
# Network Configuration Restore Script
# Created: $(date)
# Backup directory: $backup_dir

echo "Restaurando configuración de red desde backup..."

# Stop services
systemctl stop NetworkManager 2>/dev/null || true

# Restore files
[ -f "$backup_dir/interfaces" ] && cp "$backup_dir/interfaces" /etc/network/
[ -f "$backup_dir/dhcpcd.conf" ] && cp "$backup_dir/dhcpcd.conf" /etc/
[ -f "$backup_dir/wpa_supplicant.conf" ] && cp "$backup_dir/wpa_supplicant.conf" /etc/wpa_supplicant/
[ -d "$backup_dir/systemd" ] && cp -r "$backup_dir/systemd" /etc/
[ -d "$backup_dir/NetworkManager" ] && cp -r "$backup_dir/NetworkManager" /etc/

# Restart services
systemctl restart NetworkManager 2>/dev/null || true

echo "Configuración de red restaurada desde backup"
echo "Puede ser necesario reiniciar el sistema para aplicar todos los cambios"
EOF
    
    chmod +x "$backup_dir/restore_network.sh"
    
    # Save backup location for later reference
    echo "$backup_dir" > "$CONFIG_DIR/backup_location.txt"
    
    # Create backup summary
    cat > "$backup_dir/backup_summary.txt" << EOF
Raspberry Pi Gateway Network Configuration Backup
Creado: $(date)
Script versión: $SCRIPT_VERSION

Archivos respaldados:
$(ls -la "$backup_dir")

Estado de red al momento del backup:
Dirección IP ethernet: $(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | head -1 || echo "No asignada")
Gateway por defecto: $(ip route | grep default | awk '{print $3}' | head -1 || echo "No configurado")
DNS actual: $(cat /etc/resolv.conf | grep nameserver | head -3 || echo "No configurado")

Para restaurar:
bash $backup_dir/restore_network.sh
EOF
    
    log_success "Backup completo creado exitosamente en: $backup_dir"
    log_info "✓ Script de restauración disponible: $backup_dir/restore_network.sh"
    log_info "✓ Resumen del backup: $backup_dir/backup_summary.txt"
    
    return 0
}

# ============================================
# BUILDING IDENTIFICATION FUNCTION
# ============================================

prompt_building_identification() {
    log_info "Requesting building identification..."
    
    local building_address=""
    
    # Check if existing identification exists
    if [ -f "$CONFIG_DIR/building_address.txt" ]; then
        local existing_address=$(cat "$CONFIG_DIR/building_address.txt" 2>/dev/null || echo "")
        if [ -n "$existing_address" ]; then
            log_info "Existing address found: $existing_address"
            echo -e "${BLUE}Current building address:${NC} $existing_address"
            echo -n "Do you want to change it? (y/N): "
            read -r change_address
            if [[ ! "$change_address" =~ ^[Yy]$ ]]; then
                log_info "Keeping existing address: $existing_address"
                return 0
            fi
        fi
    fi
    
    # Request new address
    echo ""
    echo "============================================"
    echo "BUILDING IDENTIFICATION"
    echo "============================================"
    echo "Please enter the address or identifying name"
    echo "for this building/location."
    echo ""
    echo "Examples:"
    echo "  - Central Building 123"
    echo "  - North Branch"
    echo "  - Av. Libertador 456"
    echo ""
    
    while [ -z "$building_address" ]; do
        echo -n "Building Address/Name: "
        read -r building_address
        
        if [ -z "$building_address" ]; then
            echo -e "${RED}Error: Address cannot be empty${NC}"
            echo ""
        elif [ ${#building_address} -lt 3 ]; then
            echo -e "${RED}Error: Address must be at least 3 characters${NC}"
            echo ""
            building_address=""
        fi
    done
    
    # Save the address
    mkdir -p "$CONFIG_DIR"
    echo "$building_address" > "$CONFIG_DIR/building_address.txt"
    
    log_success "Building address saved: $building_address"
    echo -e "${GREEN}✓${NC} Address saved to: $CONFIG_DIR/building_address.txt"
    echo ""
    
    return 0
}

# ============================================
# DEPENDENCY INSTALLATION FUNCTIONS
# ============================================

install_system_dependencies() {
    log_info "Installing system dependencies..."
    
    # Update package repositories
    log_info "Updating package repositories..."
    apt-get update || {
        log_error "Failed to update package repositories"
        exit 1
    }
    
    # Install essential packages
    local packages=(
        "python3"
        "python3-pip"
        "python3-venv"
        "python3-dev"
        "git"
        "curl"
        "wget"
        "systemd"
        "network-manager"
        "dnsutils"
        "iputils-ping"
        "net-tools"
        "wireless-tools"
        "wpasupplicant"
        "rfkill"
        "iptables"
        "sqlite3"
        "build-essential"
        "pkg-config"
        "libssl-dev"
        "libffi-dev"
    )
    
    for package in "${packages[@]}"; do
        log_info "Installing $package..."
        apt-get install -y "$package" || {
            log_error "Failed to install $package"
            exit 1
        }
    done
    
    log_success "System dependencies installed successfully"
}

setup_wifi_interface() {
    log_info "Setting up WiFi interface and verifying status..."
    
    # Step 1: Unblock WiFi with rfkill
    log_info "Unblocking WiFi interface with rfkill..."
    if command -v rfkill >/dev/null 2>&1; then
        # Unblock WiFi specifically
        rfkill unblock wifi || {
            log_warn "Could not unblock WiFi specifically"
        }
        
        # Unblock all wireless interfaces
        rfkill unblock all || {
            log_warn "Could not unblock all interfaces"
        }
        
        log_info "rfkill commands executed"
        
        # Show current rfkill status for logs
        rfkill list | while read line; do
            log_info "rfkill status: $line"
        done
    else
        log_warn "rfkill not available, skipping unblock"
    fi
    
    # Step 2: Check if wlan0 exists
    if ip link show wlan0 >/dev/null 2>&1; then
        log_success "wlan0 interface detected"
        
        # Step 3: Bring up wlan0 interface
        log_info "Bringing up wlan0 interface..."
        ip link set wlan0 up || {
            log_warn "Could not bring up wlan0, but continuing..."
        }
        
        # Verify final status
        local wlan_state=$(ip link show wlan0 | grep -o "state [A-Z]*" | cut -d' ' -f2)
        log_info "wlan0 state: $wlan_state"
        
        if [ "$wlan_state" = "UP" ] || [ "$wlan_state" = "UNKNOWN" ]; then
            log_success "wlan0 interface is active and ready"
            return 0
        else
            log_warn "wlan0 not in UP state, but hardware is present"
            log_warn "State: $wlan_state - WiFi scanning may still work"
            return 0
        fi
    else
        log_warn "⚠️  wlan0 interface NOT found"
        log_warn "Possible causes:"
        log_warn "  - No WiFi hardware present"
        log_warn "  - WiFi driver not loaded"
        log_warn "  - WiFi hardware disabled in BIOS/firmware"
        log_warn ""
        log_warn "Installation will continue, but WiFi scanning"
        log_warn "will not be available until hardware is resolved."
        log_warn ""
        log_warn "For diagnosis, run after installation:"
        log_warn "  lsusb | grep -i wireless"
        log_warn "  lspci | grep -i wireless"
        log_warn "  dmesg | grep -i wlan"
        log_warn "  rfkill list"
        
        return 0  # Don't fail installation for this
    fi
}

setup_python_environment() {
    log_info "Setting up Python environment..."
    
    # Create configuration directory
    mkdir -p "$CONFIG_DIR"
    cd "$CONFIG_DIR"
    
    # Create virtual environment
    log_info "Creating Python virtual environment..."
    python3 -m venv venv || {
        log_error "Failed to create virtual environment"
        exit 1
    }
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Upgrade pip
    log_info "Upgrading pip..."
    pip install --upgrade pip
    
    # Install Python dependencies
    log_info "Installing Python packages..."
    pip install \
        flask==2.3.3 \
        flask-sqlalchemy==3.0.5 \
        flask-migrate==4.0.5 \
        flask-login==0.6.3 \
        flask-mail==0.9.1 \
        psutil==5.9.5 \
        APScheduler==3.10.4 \
        werkzeug==2.3.7 \
        wtforms==3.0.1 \
        flask-wtf==1.1.1 || {
        log_error "Failed to install Python dependencies"
        exit 1
    }
    
    log_success "Python environment configured successfully"
}

install_tailscale() {
    log_info "Installing Tailscale..."
    
    # Check if Tailscale is already installed
    if command -v tailscale >/dev/null 2>&1; then
        log_info "Tailscale already installed"
    else
        log_info "Downloading and installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh || {
            log_error "Failed to install Tailscale"
            exit 1
        }
        
        # Enable and start the service
        systemctl enable tailscaled
        systemctl start tailscaled
        log_success "Tailscale installed and service started"
    fi
}

# ============================================
# FLASK APPLICATION CREATION
# ============================================

create_flask_application() {
    log_info "Creating Flask web application..."
    
    cat > "$CONFIG_DIR/app.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Raspberry Pi Gateway Flask Application
WiFi Configuration Portal for TP-Link Gateway Setup
"""

import os
import sys
import json
import subprocess
import logging
import time
from datetime import datetime
from flask import Flask, render_template, request, jsonify, redirect, url_for, flash
from werkzeug.security import generate_password_hash, check_password_hash
import sqlite3

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'raspberry-gateway-secret-key-change-in-production')

# Configuration
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE_PATH = os.path.join(BASE_DIR, 'gateway.db')
WPA_SUPPLICANT_PATH = '/etc/wpa_supplicant/wpa_supplicant.conf'
DHCP_REVERT_SCRIPT = '/opt/raspberry_gateway/revert_to_dhcp.sh'

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/raspberry_gateway_app.log'),
        logging.StreamHandler()
    ]
)

def init_database():
    """Initialize SQLite database"""
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    
    # Create WiFi configurations table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS wifi_configs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ssid TEXT NOT NULL,
            password TEXT,
            security TEXT DEFAULT 'WPA2',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            is_active BOOLEAN DEFAULT 0
        )
    ''')
    
    # Create system logs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS system_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            level TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()

def log_to_database(level, message):
    """Log message to database"""
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO system_logs (level, message) VALUES (?, ?)",
            (level, message)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        app.logger.error(f"Failed to log to database: {e}")

def scan_wifi_networks():
    """Scan for available WiFi networks"""
    try:
        # Step 1: Check if wlan0 interface exists
        result = subprocess.run(['ip', 'link', 'show', 'wlan0'], 
                              capture_output=True, text=True)
        if result.returncode != 0:
            app.logger.error("wlan0 interface not found")
            return []
        
        # Step 2: Check and unblock rfkill if needed
        try:
            result = subprocess.run(['rfkill', 'list', 'wifi'], 
                                  capture_output=True, text=True)
            if result.returncode == 0 and 'blocked: yes' in result.stdout:
                app.logger.warning("WiFi blocked by rfkill, attempting to unblock...")
                subprocess.run(['rfkill', 'unblock', 'wifi'], capture_output=True)
                subprocess.run(['rfkill', 'unblock', 'all'], capture_output=True)
                app.logger.info("WiFi unblocked successfully")
        except Exception as e:
            app.logger.warning(f"Could not check/unblock rfkill: {e}")
        
        # Step 3: Ensure wlan0 is up
        try:
            subprocess.run(['ip', 'link', 'set', 'wlan0', 'up'], 
                          capture_output=True, check=False)
            time.sleep(1)  # Give interface time to come up
        except Exception as e:
            app.logger.warning(f"Could not bring up wlan0: {e}")
        
        # Step 4: Try nmcli first
        result = subprocess.run(['nmcli', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi'], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            networks = []
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    parts = line.split(':')
                    if len(parts) >= 3 and parts[0].strip():
                        networks.append({
                            'ssid': parts[0].strip(),
                            'signal': parts[1].strip(),
                            'security': parts[2].strip()
                        })
            if networks:
                return networks
        
        # Fallback to iwlist
        result = subprocess.run(['iwlist', 'wlan0', 'scan'], capture_output=True, text=True)
        if result.returncode != 0:
            app.logger.error(f"WiFi scan failed: {result.stderr}")
            return []
            
        networks = []
        current_network = {}
        
        for line in result.stdout.split('\n'):
            line = line.strip()
            if 'ESSID:' in line:
                ssid = line.split('"')[1] if '"' in line else ''
                if ssid:
                    current_network['ssid'] = ssid
                    if current_network:
                        networks.append(current_network.copy())
                    current_network = {'ssid': ssid, 'signal': '50', 'security': 'WPA2'}
        
        return networks
    except Exception as e:
        app.logger.error(f"Failed to scan WiFi networks: {e}")
        return []

def configure_wifi(ssid, password):
    """Configure WiFi connection"""
    try:
        log_to_database('INFO', f'Configuring WiFi for SSID: {ssid}')
        
        # Create wpa_supplicant configuration
        wpa_config = f'''country=AR
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={{
    ssid="{ssid}"
    psk="{password}"
    key_mgmt=WPA-PSK
}}
'''
        
        # Backup existing configuration
        subprocess.run(['cp', WPA_SUPPLICANT_PATH, f'{WPA_SUPPLICANT_PATH}.backup'], 
                      capture_output=True)
        
        # Write new configuration
        with open(WPA_SUPPLICANT_PATH, 'w') as f:
            f.write(wpa_config)
        
        # Save to database
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        
        # Deactivate all existing configs
        cursor.execute("UPDATE wifi_configs SET is_active = 0")
        
        # Add new config
        cursor.execute(
            "INSERT INTO wifi_configs (ssid, password, is_active) VALUES (?, ?, 1)",
            (ssid, password)
        )
        conn.commit()
        conn.close()
        
        # Restart WiFi interface
        subprocess.run(['wpa_cli', '-i', 'wlan0', 'reconfigure'], capture_output=True)
        
        log_to_database('SUCCESS', f'WiFi configured successfully for SSID: {ssid}')
        return True
        
    except Exception as e:
        app.logger.error(f"Failed to configure WiFi: {e}")
        log_to_database('ERROR', f'Failed to configure WiFi: {e}')
        return False

def check_wifi_connection():
    """Check if WiFi is connected"""
    try:
        # Check wpa_supplicant status
        result = subprocess.run(['wpa_cli', '-i', 'wlan0', 'status'], 
                              capture_output=True, text=True)
        
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'wpa_state=COMPLETED' in line:
                    return True
        
        # Alternative check using ip command
        result = subprocess.run(['ip', 'addr', 'show', 'wlan0'], 
                              capture_output=True, text=True)
        
        if 'inet ' in result.stdout:
            return True
            
        return False
    except:
        return False

def trigger_dhcp_revert():
    """Trigger ethernet DHCP revert script"""
    try:
        if os.path.exists(DHCP_REVERT_SCRIPT):
            subprocess.run(['bash', DHCP_REVERT_SCRIPT], capture_output=True)
            log_to_database('INFO', 'DHCP revert script triggered')
            return True
    except Exception as e:
        app.logger.error(f"Failed to trigger DHCP revert: {e}")
    return False

@app.route('/')
def index():
    """Main page"""
    wifi_connected = check_wifi_connection()
    
    # Get current WiFi config from database
    current_wifi = None
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT ssid FROM wifi_configs WHERE is_active = 1 ORDER BY created_at DESC LIMIT 1")
        result = cursor.fetchone()
        if result:
            current_wifi = result[0]
        conn.close()
    except:
        pass
    
    return render_template_string(INDEX_TEMPLATE, 
                                wifi_connected=wifi_connected,
                                current_wifi=current_wifi)

@app.route('/wifi')
def wifi_config():
    """WiFi configuration page"""
    networks = scan_wifi_networks()
    return render_template_string(WIFI_TEMPLATE, networks=networks)

@app.route('/connect_wifi', methods=['POST'])
def connect_wifi():
    """Connect to WiFi network"""
    try:
        ssid = request.form.get('ssid')
        password = request.form.get('password')
        
        if not ssid:
            flash('SSID is required', 'error')
            return redirect(url_for('wifi_config'))
        
        if configure_wifi(ssid, password):
            flash(f'Successfully connected to {ssid}', 'success')
            
            # Trigger DHCP revert after successful WiFi connection
            trigger_dhcp_revert()
            
            return redirect(url_for('index'))
        else:
            flash('Failed to connect to WiFi', 'error')
            return redirect(url_for('wifi_config'))
            
    except Exception as e:
        app.logger.error(f"Error connecting to WiFi: {e}")
        flash('Error connecting to WiFi', 'error')
        return redirect(url_for('wifi_config'))

@app.route('/api/status')
def api_status():
    """API endpoint for system status"""
    try:
        wifi_connected = check_wifi_connection()
        
        # Get system information
        status = {
            'timestamp': datetime.now().isoformat(),
            'wifi_connected': wifi_connected,
            'ethernet_ip': get_ethernet_ip(),
            'wifi_ip': get_wifi_ip(),
            'tailscale_status': get_tailscale_status()
        }
        
        return jsonify(status)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

def get_ethernet_ip():
    """Get ethernet IP address"""
    try:
        result = subprocess.run(['ip', 'addr', 'show', 'eth0'], 
                              capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if 'inet ' in line and not '127.0.0.1' in line:
                return line.split()[1].split('/')[0]
    except:
        pass
    return None

def get_wifi_ip():
    """Get WiFi IP address"""
    try:
        result = subprocess.run(['ip', 'addr', 'show', 'wlan0'], 
                              capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if 'inet ' in line:
                return line.split()[1].split('/')[0]
    except:
        pass
    return None

def get_tailscale_status():
    """Get Tailscale status"""
    try:
        result = subprocess.run(['tailscale', 'status', '--json'], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            status = json.loads(result.stdout)
            return {
                'connected': status.get('BackendState') == 'Running',
                'ip': status.get('TailscaleIPs', [None])[0]
            }
    except:
        pass
    return {'connected': False, 'ip': None}

# HTML Templates
INDEX_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Raspberry Pi Gateway</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; margin-bottom: 30px; }
        .status { padding: 15px; margin: 20px 0; border-radius: 5px; }
        .status.connected { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .status.disconnected { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .btn { display: inline-block; padding: 12px 24px; background-color: #007bff; color: white; text-decoration: none; border-radius: 5px; margin: 10px 5px; border: none; cursor: pointer; }
        .btn:hover { background-color: #0056b3; }
        .info-section { margin: 20px 0; padding: 15px; background-color: #f8f9fa; border-left: 4px solid #007bff; }
        .flash-messages { margin: 20px 0; }
        .flash { padding: 10px; margin: 5px 0; border-radius: 5px; }
        .flash.success { background-color: #d4edda; color: #155724; }
        .flash.error { background-color: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔗 Raspberry Pi Gateway</h1>
        
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                <div class="flash-messages">
                    {% for category, message in messages %}
                        <div class="flash {{ category }}">{{ message }}</div>
                    {% endfor %}
                </div>
            {% endif %}
        {% endwith %}
        
        <div class="status {{ 'connected' if wifi_connected else 'disconnected' }}">
            <strong>WiFi Status:</strong> 
            {% if wifi_connected %}
                ✅ Connected
                {% if current_wifi %}
                    to "{{ current_wifi }}"
                {% endif %}
            {% else %}
                ❌ Not Connected
            {% endif %}
        </div>
        
        <div class="info-section">
            <h3>📡 Network Configuration</h3>
            <p>This Raspberry Pi gateway uses an external TP-Link device as Access Point.</p>
            <p><strong>Ethernet IP:</strong> 192.168.4.100 (Static - for initial setup)</p>
            <p><strong>Web Portal:</strong> http://192.168.4.100:8080</p>
            <p><strong>Purpose:</strong> Configure WiFi connection to building network</p>
        </div>
        
        <div style="text-align: center; margin: 30px 0;">
            <a href="/wifi" class="btn">🔧 Configure WiFi</a>
            <a href="/api/status" class="btn" style="background-color: #28a745;">📊 System Status</a>
        </div>
        
        <div class="info-section">
            <h3>📋 Setup Instructions</h3>
            <ol>
                <li>Connect to TP-Link WiFi: "ControlsegConfig" (Password: Grupo1598)</li>
                <li>Open this portal at: http://192.168.4.100:8080</li>
                <li>Configure WiFi connection to your building network</li>
                <li>System will automatically switch ethernet to DHCP after WiFi connection</li>
                <li>Access via Tailscale VPN for remote management</li>
            </ol>
        </div>
    </div>
</body>
</html>
'''

WIFI_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WiFi Configuration</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; margin-bottom: 30px; }
        .network { padding: 15px; margin: 10px 0; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; }
        .network:hover { background-color: #f0f0f0; cursor: pointer; }
        .signal { float: right; font-weight: bold; }
        .signal.high { color: #28a745; }
        .signal.medium { color: #ffc107; }
        .signal.low { color: #dc3545; }
        .form-group { margin: 15px 0; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input[type="text"], input[type="password"] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 5px; box-sizing: border-box; }
        .btn { display: inline-block; padding: 12px 24px; background-color: #007bff; color: white; text-decoration: none; border-radius: 5px; margin: 10px 5px; border: none; cursor: pointer; }
        .btn:hover { background-color: #0056b3; }
        .btn.secondary { background-color: #6c757d; }
        .btn.secondary:hover { background-color: #545b62; }
        .hidden { display: none; }
    </style>
    <script>
        function selectNetwork(ssid) {
            document.getElementById('ssid').value = ssid;
            document.getElementById('wifi-form').style.display = 'block';
            document.getElementById('password').focus();
        }
        
        function refreshNetworks() {
            location.reload();
        }
    </script>
</head>
<body>
    <div class="container">
        <h1>📡 WiFi Configuration</h1>
        
        <div style="text-align: center; margin: 20px 0;">
            <button onclick="refreshNetworks()" class="btn secondary">🔄 Refresh Networks</button>
            <a href="/" class="btn secondary">← Back to Home</a>
        </div>
        
        <h3>Available Networks:</h3>
        {% if networks %}
            {% for network in networks %}
                <div class="network" onclick="selectNetwork('{{ network.ssid }}')">
                    <strong>{{ network.ssid }}</strong>
                    <span class="signal {{ 'high' if network.signal|int > 70 else 'medium' if network.signal|int > 40 else 'low' }}">
                        {{ network.signal }}%
                    </span>
                    <br>
                    <small>Security: {{ network.security or 'Open' }}</small>
                </div>
            {% endfor %}
        {% else %}
            <p>No networks found. Make sure WiFi is enabled and click "Refresh Networks".</p>
        {% endif %}
        
        <div id="wifi-form" class="hidden" style="margin-top: 30px; padding: 20px; border: 2px solid #007bff; border-radius: 10px; background-color: #f8f9fa;">
            <h3>Connect to Network</h3>
            <form method="POST" action="/connect_wifi">
                <div class="form-group">
                    <label for="ssid">Network Name (SSID):</label>
                    <input type="text" id="ssid" name="ssid" required>
                </div>
                <div class="form-group">
                    <label for="password">Password:</label>
                    <input type="password" id="password" name="password" placeholder="Leave blank for open networks">
                </div>
                <div style="text-align: center;">
                    <button type="submit" class="btn">🔗 Connect</button>
                    <button type="button" onclick="document.getElementById('wifi-form').style.display='none'" class="btn secondary">Cancel</button>
                </div>
            </form>
        </div>
    </div>
</body>
</html>
'''

if __name__ == '__main__':
    # Initialize database
    init_database()
    
    # Start Flask application
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

    chmod +x "$CONFIG_DIR/app.py"
    log_success "Flask application created successfully"
}

# ============================================
# DHCP REVERT SCRIPT CREATION
# ============================================

create_dhcp_revert_script() {
    log_info "Creating ethernet DHCP revert script..."
    
    cat > "$CONFIG_DIR/revert_to_dhcp.sh" << 'EOF'
#!/bin/bash

# ============================================
# ETHERNET DHCP REVERT SCRIPT
# ============================================
# This script reverts ethernet (eth0) from static IP to DHCP
# after WiFi has been successfully configured
# ============================================

LOG_FILE="/var/log/ethernet_dhcp_revert.log"
ETH_INTERFACE="eth0"

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

log_message "Starting ethernet DHCP revert process"

# Check if WiFi is connected before reverting
check_wifi_connection() {
    # Check wpa_supplicant status
    if wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
        return 0
    fi
    
    # Check if wlan0 has an IP address
    if ip addr show wlan0 2>/dev/null | grep -q "inet "; then
        return 0
    fi
    
    return 1
}

if ! check_wifi_connection; then
    log_message "WiFi not connected - skipping DHCP revert"
    exit 0
fi

log_message "WiFi connection confirmed - proceeding with DHCP revert"

# Backup current network configuration
backup_dir="/root/network_backup_$(date +%s)"
mkdir -p "$backup_dir"

# Backup NetworkManager configurations
if command -v nmcli >/dev/null 2>&1; then
    nmcli connection show > "$backup_dir/nm_connections.txt" 2>/dev/null || true
fi

# Use NetworkManager if available
if command -v nmcli >/dev/null 2>&1; then
    log_message "Using NetworkManager to configure DHCP"
    
    # Find ethernet connection name
    connection_name=$(nmcli -t -f NAME,TYPE connection show | grep ":ethernet$" | cut -d: -f1 | head -1)
    
    if [ -z "$connection_name" ]; then
        connection_name="Wired connection 1"
    fi
    
    log_message "Configuring DHCP on connection: $connection_name"
    
    # Configure DHCP
    nmcli connection modify "$connection_name" \
        ipv4.method auto \
        ipv4.addresses "" \
        ipv4.gateway "" \
        ipv4.dns "" 2>/dev/null || {
        log_message "Failed to configure DHCP with NetworkManager"
        exit 1
    }
    
    # Restart connection
    nmcli connection down "$connection_name" 2>/dev/null || true
    sleep 2
    nmcli connection up "$connection_name" 2>/dev/null || {
        log_message "Failed to bring up DHCP connection"
        exit 1
    }
    
else
    log_message "Using legacy network configuration for DHCP"
    
    # Remove static configuration files
    rm -f /etc/network/interfaces.d/eth0-static
    
    # Create DHCP configuration
    cat > /etc/network/interfaces.d/eth0-dhcp << 'DHCP_EOF'
auto eth0
iface eth0 inet dhcp
DHCP_EOF
    
    # Restart networking
    ifdown "$ETH_INTERFACE" 2>/dev/null || true
    sleep 2
    ifup "$ETH_INTERFACE" || {
        log_message "Failed to bring up DHCP interface"
        exit 1
    }
fi

# Wait for DHCP to assign IP
sleep 10

# Verify DHCP assignment
new_ip=$(ip addr show "$ETH_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -n "$new_ip" ] && [ "$new_ip" != "192.168.4.100" ]; then
    log_message "Successfully switched to DHCP - New IP: $new_ip"
    
    # Create a flag file to indicate DHCP revert completed
    echo "dhcp_reverted=$(date)" > /opt/raspberry_gateway/dhcp_revert_status.txt
    echo "new_ip=$new_ip" >> /opt/raspberry_gateway/dhcp_revert_status.txt
    
    # Disable this service to prevent it from running again
    systemctl disable ethernet_dhcp_revert.service 2>/dev/null || true
    
    log_message "DHCP revert completed successfully"
else
    log_message "DHCP assignment failed or same IP retained"
    exit 1
fi
EOF

    chmod +x "$CONFIG_DIR/revert_to_dhcp.sh"
    log_success "DHCP revert script created successfully"
}

# ============================================
# DEFERRED NETWORK CONFIGURATION FUNCTIONS
# ============================================

create_network_config_applier() {
    log_info "Creating network configuration applier script..."
    
    cat > "$CONFIG_DIR/apply_network_config.sh" << 'EOF'
#!/bin/bash

# ============================================
# Network Configuration Applier
# ============================================
# Applies deferred network configuration safely
# This script runs after reboot to apply network changes
# ============================================

set -e

LOG_FILE="/var/log/network_config_applier.log"
CONFIG_DIR="/opt/raspberry_gateway"
PENDING_CONFIG_DIR="$CONFIG_DIR/pending_network_config"
APPLIED_FLAG="$CONFIG_DIR/.network_config_applied"

# Network Configuration
STATIC_IP="192.168.4.100"
STATIC_NETMASK="24"
STATIC_GATEWAY="192.168.4.1"
STATIC_DNS="8.8.8.8,8.8.4.4"
ETH_INTERFACE="eth0"

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
}

log_success() {
    log_message "SUCCESS" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

apply_static_ip_config() {
    log_info "Applying static IP configuration..."
    
    # Create backup of current configuration
    local backup_dir="/root/network_backup_$(date +%s)"
    mkdir -p "$backup_dir"
    
    if command -v nmcli >/dev/null 2>&1; then
        # Use NetworkManager
        local connection_name="Wired connection 1"
        
        # Find existing ethernet connection
        local existing_conn=$(nmcli -t -f NAME,TYPE connection show | grep ":ethernet$" | cut -d: -f1 | head -1)
        if [ -n "$existing_conn" ]; then
            connection_name="$existing_conn"
        fi
        
        log_info "Configuring static IP on connection: $connection_name"
        
        # Backup current settings
        nmcli connection show "$connection_name" > "$backup_dir/connection_backup.txt" 2>/dev/null || true
        
        # Configure static IP
        nmcli connection modify "$connection_name" \
            ipv4.method manual \
            ipv4.addresses "$STATIC_IP/$STATIC_NETMASK" \
            ipv4.gateway "$STATIC_GATEWAY" \
            ipv4.dns "$STATIC_DNS" || {
            log_error "Failed to configure static IP with NetworkManager"
            return 1
        }
        
        # Restart connection
        nmcli connection down "$connection_name" 2>/dev/null || true
        sleep 2
        nmcli connection up "$connection_name" || {
            log_error "Failed to activate static IP connection"
            return 1
        }
        
    else
        # Fallback for systems without NetworkManager
        log_info "Using legacy network configuration"
        
        # Backup current configuration
        cp /etc/network/interfaces "$backup_dir/" 2>/dev/null || true
        
        # Create static interface configuration
        cat > /etc/network/interfaces.d/eth0-static << IFACE_EOF
auto $ETH_INTERFACE
iface $ETH_INTERFACE inet static
    address $STATIC_IP
    netmask 255.255.255.0
    gateway $STATIC_GATEWAY
    dns-nameservers $STATIC_DNS
IFACE_EOF
        
        # Restart interface
        ifdown $ETH_INTERFACE 2>/dev/null || true
        sleep 2
        ifup $ETH_INTERFACE || {
            log_error "Failed to activate static IP on $ETH_INTERFACE"
            return 1
        }
    fi
    
    # Verify IP assignment
    sleep 5
    local assigned_ip=$(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    
    if [ "$assigned_ip" = "$STATIC_IP" ]; then
        log_success "Static IP configured successfully: $assigned_ip"
        echo "backup_location=$backup_dir" > "$CONFIG_DIR/network_backup_info.txt"
        return 0
    else
        log_error "Static IP configuration failed. Expected: $STATIC_IP, Got: $assigned_ip"
        return 1
    fi
}

main() {
    log_info "Starting deferred network configuration application"
    
    # Check if already applied
    if [ -f "$APPLIED_FLAG" ]; then
        log_info "Network configuration already applied"
        exit 0
    fi
    
    # Check if there's pending configuration
    if [ ! -d "$PENDING_CONFIG_DIR" ] || [ ! -f "$PENDING_CONFIG_DIR/config_type" ]; then
        log_info "No pending network configuration found"
        exit 0
    fi
    
    local config_type=$(cat "$PENDING_CONFIG_DIR/config_type")
    log_info "Applying pending configuration type: $config_type"
    
    case "$config_type" in
        "static_ip")
            if apply_static_ip_config; then
                log_success "Static IP configuration applied successfully"
                
                # Enable DHCP revert service now that static IP is configured
                systemctl enable ethernet_dhcp_revert.service
                
                # Mark as applied
                touch "$APPLIED_FLAG"
                echo "applied_at=$(date)" >> "$APPLIED_FLAG"
                echo "config_type=$config_type" >> "$APPLIED_FLAG"
                
                # Clean up pending configuration
                rm -rf "$PENDING_CONFIG_DIR"
                
                # Disable this service so it doesn't run again
                systemctl disable network-config-applier.service
                
                log_success "Network configuration application completed successfully"
            else
                log_error "Failed to apply static IP configuration"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown configuration type: $config_type"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
EOF

    chmod +x "$CONFIG_DIR/apply_network_config.sh"
    log_success "Network configuration applier script created"
}

prepare_deferred_network_config() {
    log_info "Preparing deferred network configuration..."
    
    # Create pending configuration directory
    local pending_dir="$CONFIG_DIR/pending_network_config"
    mkdir -p "$pending_dir"
    
    # Set configuration type
    echo "static_ip" > "$pending_dir/config_type"
    echo "prepared_at=$(date)" > "$pending_dir/metadata.txt"
    echo "static_ip=$STATIC_IP" >> "$pending_dir/metadata.txt"
    echo "static_gateway=$STATIC_GATEWAY" >> "$pending_dir/metadata.txt"
    echo "static_dns=$STATIC_DNS" >> "$pending_dir/metadata.txt"
    
    log_success "Deferred network configuration prepared"
    log_info "Network changes will be applied after reboot"
}

prompt_network_configuration() {
    log_info "Prompting user for network configuration..."
    
    echo ""
    echo "============================================"
    echo "⚠️  CONFIGURACIÓN DE RED"
    echo "============================================"
    echo ""
    echo "TODAS las dependencias, Tailscale y servicios han sido"
    echo "instalados exitosamente manteniendo la conectividad actual."
    echo ""
    echo "AHORA es necesario configurar la IP estática para el"
    echo "setup inicial con TP-Link:"
    echo ""
    echo "🔗 IP estática: $STATIC_IP"
    echo "🌐 Gateway: $STATIC_GATEWAY"
    echo "📡 Interface: $ETH_INTERFACE"
    echo ""
    echo "⚠️  ADVERTENCIA:"
    echo "Este cambio puede cortar la conexión SSH/network actual."
    echo "El sistema será accesible después en la nueva IP."
    echo ""
    echo "Opciones:"
    echo "1. Aplicar AHORA (recomendado si instalación local)"
    echo "2. Diferir hasta después del REINICIO (recomendado para SSH remoto)"
    echo "3. Configurar MANUALMENTE más tarde"
    echo ""
    
    local choice=""
    while [ -z "$choice" ]; do
        echo -n "Elija una opción (1/2/3): "
        read -r choice
        
        case "$choice" in
            1|"ahora"|"now")
                log_info "Usuario eligió aplicar configuración inmediatamente"
                return 0  # Apply now
                ;;
            2|"reinicio"|"reboot"|"diferir")
                log_info "Usuario eligió diferir configuración hasta reinicio"
                return 1  # Defer to reboot
                ;;
            3|"manual"|"despues"|"later")
                log_info "Usuario eligió configuración manual posterior"
                return 2  # Manual later
                ;;
            *)
                echo -e "${RED}Opción inválida. Por favor elija 1, 2 o 3.${NC}"
                choice=""
                ;;
        esac
    done
}

show_manual_configuration_instructions() {
    echo ""
    echo "============================================"
    echo "📋 INSTRUCCIONES PARA CONFIGURACIÓN MANUAL"
    echo "============================================"
    echo ""
    echo "Para aplicar la configuración de red manualmente más tarde:"
    echo ""
    echo "1. Ejecutar el script aplicador:"
    echo "   sudo $CONFIG_DIR/apply_network_config.sh"
    echo ""
    echo "2. O reiniciar el sistema para aplicación automática:"
    echo "   sudo reboot"
    echo ""
    echo "3. O configurar manualmente la IP estática:"
    echo "   # Con NetworkManager:"
    echo "   sudo nmcli connection modify \"Wired connection 1\" \\"
    echo "     ipv4.method manual \\"
    echo "     ipv4.addresses \"$STATIC_IP/$STATIC_NETMASK\" \\"
    echo "     ipv4.gateway \"$STATIC_GATEWAY\" \\"
    echo "     ipv4.dns \"$STATIC_DNS\""
    echo "   sudo nmcli connection up \"Wired connection 1\""
    echo ""
    echo "Después de la configuración:"
    echo "🌐 Portal web: http://$STATIC_IP:$WEB_PORT"
    echo "🔧 Configurar WiFi desde el portal web"
    echo ""
    echo "Archivos de configuración en: $CONFIG_DIR"
    echo "============================================"
    echo ""
}

# ============================================
# NETWORK CONFIGURATION FUNCTIONS (MODIFIED)
# ============================================

configure_static_ip() {
    log_info "Configuring static IP on $ETH_INTERFACE: $STATIC_IP/$STATIC_NETMASK"
    
    # Backup current configuration
    backup_existing_configs
    
    if command -v nmcli >/dev/null 2>&1; then
        # Use NetworkManager
        local connection_name="Wired connection 1"
        
        # Find existing ethernet connection
        local existing_conn=$(nmcli -t -f NAME,TYPE connection show | grep ":ethernet$" | cut -d: -f1 | head -1)
        if [ -n "$existing_conn" ]; then
            connection_name="$existing_conn"
        fi
        
        log_info "Configuring static IP on connection: $connection_name"
        
        # Configure static IP
        nmcli connection modify "$connection_name" \
            ipv4.method manual \
            ipv4.addresses "$STATIC_IP/$STATIC_NETMASK" \
            ipv4.gateway "$STATIC_GATEWAY" \
            ipv4.dns "$STATIC_DNS" || {
            log_error "Failed to configure static IP with NetworkManager"
            exit 1
        }
        
        # Restart connection
        nmcli connection down "$connection_name" 2>/dev/null || true
        sleep 2
        nmcli connection up "$connection_name" || {
            log_warn "Could not immediately activate connection"
        }
        
    else
        # Fallback for systems without NetworkManager
        log_info "NetworkManager not available, using legacy configuration"
        
        # Create static interface configuration
        cat > /etc/network/interfaces.d/eth0-static << EOF
auto $ETH_INTERFACE
iface $ETH_INTERFACE inet static
    address $STATIC_IP
    netmask 255.255.255.0
    gateway $STATIC_GATEWAY
    dns-nameservers $STATIC_DNS
EOF
        
        # Restart interface
        ifdown $ETH_INTERFACE 2>/dev/null || true
        sleep 2
        ifup $ETH_INTERFACE || {
            log_error "Failed to activate static IP on $ETH_INTERFACE"
            exit 1
        }
    fi
    
    # Verify IP assignment
    sleep 5
    local assigned_ip=$(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    
    if [ "$assigned_ip" = "$STATIC_IP" ]; then
        log_success "Static IP configured successfully: $assigned_ip"
    else
        log_error "Static IP configuration failed. Expected: $STATIC_IP, Got: $assigned_ip"
        exit 1
    fi
}

configure_tailscale() {
    log_info "Configuring Tailscale VPN..."
    
    # Read building address for hostname
    local building_address=""
    if [ -f "$CONFIG_DIR/building_address.txt" ]; then
        building_address=$(cat "$CONFIG_DIR/building_address.txt" 2>/dev/null || echo "")
    fi
    
    if [ -z "$building_address" ]; then
        log_error "Building address not found. Cannot configure Tailscale hostname"
        exit 1
    fi
    
    # Convert address to valid hostname
    local tailscale_hostname=$(echo "$building_address" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-\|-$//g')
    
    # Ensure hostname is not empty and has prefix
    if [ -z "$tailscale_hostname" ]; then
        tailscale_hostname="gateway-$(hostname | tr '[:upper:]' '[:lower:]')"
    else
        tailscale_hostname="gateway-$tailscale_hostname"
    fi
    
    log_info "Tailscale hostname: $tailscale_hostname"
    
    # Check if already authenticated
    if tailscale status >/dev/null 2>&1; then
        local status_output=$(tailscale status 2>&1 || echo "")
        if [[ ! "$status_output" =~ "Logged out" ]] && [[ ! "$status_output" =~ "not logged in" ]]; then
            log_info "Tailscale already authenticated"
            local current_ip=$(tailscale ip 2>/dev/null || echo "")
            if [ -n "$current_ip" ]; then
                log_success "Tailscale connected - IP: $current_ip"
                return 0
            fi
        fi
    fi
    
    # Authenticate Tailscale
    log_info "Authenticating Tailscale with hostname: $tailscale_hostname"
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname="$tailscale_hostname" --accept-routes || {
        log_error "Failed to authenticate Tailscale"
        exit 1
    }
    
    # Verify connection
    sleep 10
    local tailscale_ip=$(tailscale ip 2>/dev/null || echo "")
    if [ -n "$tailscale_ip" ]; then
        log_success "Tailscale configured successfully"
        log_info "IP Tailscale assigned: $tailscale_ip"
        log_info "Hostname: $tailscale_hostname"
        
        # Save Tailscale information
        echo "tailscale_ip=$tailscale_ip" > "$CONFIG_DIR/tailscale_info.txt"
        echo "tailscale_hostname=$tailscale_hostname" >> "$CONFIG_DIR/tailscale_info.txt"
        
        return 0
    else
        log_error "Tailscale authenticated but could not get IP"
        exit 1
    fi
}

# ============================================
# SYSTEMD SERVICE CREATION
# ============================================

create_systemd_services() {
    log_info "Creating systemd services..."
    
    # Main Flask application service
    cat > "/etc/systemd/system/$SERVICE_NAME" << EOF
[Unit]
Description=Raspberry Pi Gateway Flask Application
Documentation=https://github.com/lucassquirogaa/grupo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
Environment=PATH=$CONFIG_DIR/venv/bin
ExecStart=$CONFIG_DIR/venv/bin/python $CONFIG_DIR/app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # DHCP revert service (one-shot) - DO NOT ENABLE YET
    cat > "/etc/systemd/system/$REVERT_SERVICE_NAME" << EOF
[Unit]
Description=Ethernet DHCP Revert Service
Documentation=Reverts ethernet to DHCP after WiFi configuration
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CONFIG_DIR/revert_to_dhcp.sh
RemainAfterExit=no
User=root
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Network config applier service (for deferred configuration)
    cat > "/etc/systemd/system/network-config-applier.service" << EOF
[Unit]
Description=Network Configuration Applier
Documentation=Applies deferred network configuration after installation
After=network.target NetworkManager.service
Wants=network-online.target
ConditionPathExists=$CONFIG_DIR/pending_network_config

[Service]
Type=oneshot
ExecStart=$CONFIG_DIR/apply_network_config.sh
RemainAfterExit=no
User=root
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable only the main service initially
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    # Note: DHCP revert and network config applier services will be enabled only when needed
    
    log_success "Systemd services created (main service enabled, network services pending)"
}

# ============================================
# VALIDATION AND TESTING FUNCTIONS
# ============================================

validate_installation() {
    log_info "Validating installation..."
    
    local errors=0
    
    # Check if directories exist
    if [ ! -d "$CONFIG_DIR" ]; then
        log_error "Configuration directory not found: $CONFIG_DIR"
        ((errors++))
    fi
    
    # Check if Python environment exists
    if [ ! -f "$CONFIG_DIR/venv/bin/python" ]; then
        log_error "Python virtual environment not found"
        ((errors++))
    fi
    
    # Check if Flask app exists
    if [ ! -f "$CONFIG_DIR/app.py" ]; then
        log_error "Flask application not found"
        ((errors++))
    fi
    
    # Check if revert script exists
    if [ ! -f "$CONFIG_DIR/revert_to_dhcp.sh" ]; then
        log_error "DHCP revert script not found"
        ((errors++))
    fi
    
    # Check if systemd services exist
    if [ ! -f "/etc/systemd/system/$SERVICE_NAME" ]; then
        log_error "Main systemd service not found"
        ((errors++))
    fi
    
    if [ ! -f "/etc/systemd/system/$REVERT_SERVICE_NAME" ]; then
        log_error "DHCP revert service not found"
        ((errors++))
    fi
    
    # Check if building address is configured
    if [ ! -f "$CONFIG_DIR/building_address.txt" ]; then
        log_error "Building address not configured"
        ((errors++))
    fi
    
    # Check Tailscale installation
    if ! command -v tailscale >/dev/null 2>&1; then
        log_error "Tailscale not installed"
        ((errors++))
    fi
    
    # Check network configuration
    local current_ip=$(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    if [ "$current_ip" != "$STATIC_IP" ]; then
        log_warn "Static IP not configured yet. Current IP: $current_ip"
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Installation validation passed"
        return 0
    else
        log_error "Installation validation failed with $errors errors"
        return 1
    fi
}

test_flask_application() {
    log_info "Testing Flask application..."
    
    # Start Flask app in background for testing
    cd "$CONFIG_DIR"
    source venv/bin/activate
    
    # Test if app can start
    timeout 10 python app.py &
    local flask_pid=$!
    sleep 5
    
    if kill -0 $flask_pid 2>/dev/null; then
        log_success "Flask application starts successfully"
        kill $flask_pid 2>/dev/null || true
        return 0
    else
        log_error "Flask application failed to start"
        return 1
    fi
}

# ============================================
# MAIN INSTALLATION FUNCTION
# ============================================

main() {
    echo "============================================"
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Instalación Segura con Configuración de Red Diferida"
    echo "============================================"
    
    # Pre-installation checks
    check_root
    check_raspberry_pi
    check_internet_connectivity
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$CONFIG_DIR"
    
    log_info "Iniciando instalación segura de Raspberry Pi Gateway v$SCRIPT_VERSION"
    log_info "TODAS las dependencias se instalarán ANTES de modificar la red"
    
    # =================================================================
    # PHASE 1: INSTALL ALL DEPENDENCIES (MANTENER INTERNET CONNECTIVITY)
    # =================================================================
    
    log_info "=== FASE 1: Instalando TODAS las dependencias (sin tocar la red) ==="
    
    # Step 1: Install system dependencies FIRST
    log_info "PASO 1: Instalando dependencias del sistema..."
    install_system_dependencies || {
        log_error "Error en instalación de dependencias del sistema"
        exit 1
    }
    
    # Step 1.5: Setup WiFi interface and unblock rfkill
    log_info "PASO 1.5: Configurando interfaz WiFi..."
    setup_wifi_interface || {
        log_warn "Advertencias en configuración WiFi, pero continuando instalación..."
    }
    
    # Step 2: Setup Python environment FIRST  
    log_info "PASO 2: Configurando entorno Python..."
    setup_python_environment || {
        log_error "Error configurando entorno Python"
        exit 1
    }
    
    # Step 3: Install Tailscale FIRST (while internet is available)
    log_info "PASO 3: Instalando Tailscale..."
    install_tailscale || {
        log_error "Error instalando Tailscale"
        exit 1
    }
    
    # Step 4: Request building identification FIRST
    log_info "PASO 4: Identificación del edificio..."
    prompt_building_identification || {
        log_error "Error en identificación del edificio"
        exit 1
    }
    
    # Step 5: Configure Tailscale FIRST (while internet is available)
    log_info "PASO 5: Configurando Tailscale..."
    configure_tailscale || {
        log_error "Error configurando Tailscale"
        exit 1
    }
    
    # Step 6: Create application components FIRST
    log_info "PASO 6: Creando componentes de aplicación..."
    create_flask_application || {
        log_error "Error creando aplicación Flask"
        exit 1
    }
    
    create_dhcp_revert_script || {
        log_error "Error creando script de revert DHCP"
        exit 1
    }
    
    # Step 7: Create network configuration applier FIRST
    log_info "PASO 7: Preparando configurador de red diferido..."
    create_network_config_applier || {
        log_error "Error creando aplicador de configuración de red"
        exit 1
    }
    
    # Step 8: Create systemd services FIRST (but don't enable network-modifying ones)
    log_info "PASO 8: Creando servicios systemd..."
    create_systemd_services || {
        log_error "Error creando servicios systemd"
        exit 1
    }
    
    log_success "FASE 1 COMPLETADA: Todas las dependencias instaladas manteniendo conectividad"
    
    # =================================================================
    # PHASE 2: NETWORK CONFIGURATION (POTENTIALLY BREAKING CONNECTIVITY)
    # =================================================================
    
    log_info "=== FASE 2: Configuración de red (puede cortar conectividad) ==="
    
    # Create comprehensive backup BEFORE any network changes
    log_info "Creando backup completo de configuración de red..."
    backup_existing_configs || {
        log_error "Error creando backup de configuración"
        exit 1
    }
    
    # Prompt user for network configuration approach
    prompt_network_configuration
    local config_choice=$?
    
    case $config_choice in
        0)  # Apply now
            log_info "Aplicando configuración de red INMEDIATAMENTE..."
            log_warn "⚠️  La conectividad actual puede perderse después de este punto"
            
            # Apply static IP configuration immediately
            configure_static_ip || {
                log_error "Error configurando IP estática"
                log_error "Verifique la conectividad y ejecute manualmente si es necesario"
                exit 1
            }
            
            # Enable DHCP revert service now
            systemctl enable "$REVERT_SERVICE_NAME"
            
            # Start services
            log_info "Iniciando servicios..."
            systemctl start "$SERVICE_NAME" || {
                log_warn "No se pudo iniciar el servicio principal inmediatamente"
            }
            
            log_success "Configuración de red aplicada inmediatamente"
            ;;
            
        1)  # Defer to reboot
            log_info "CONFIGURACIÓN DE RED DIFERIDA hasta reinicio..."
            
            # Prepare deferred configuration
            prepare_deferred_network_config || {
                log_error "Error preparando configuración diferida"
                exit 1
            }
            
            # Enable network config applier service
            systemctl enable network-config-applier.service
            
            # Start main service without network changes
            systemctl start "$SERVICE_NAME" || {
                log_warn "No se pudo iniciar el servicio principal inmediatamente"
            }
            
            log_success "Configuración diferida preparada para aplicación después del reinicio"
            ;;
            
        2)  # Manual later
            log_info "Configuración manual posterior seleccionada"
            
            # Prepare configuration but don't enable automatic application
            prepare_deferred_network_config || {
                log_error "Error preparando configuración manual"
                exit 1
            }
            
            # Start main service without network changes
            systemctl start "$SERVICE_NAME" || {
                log_warn "No se pudo iniciar el servicio principal inmediatamente"
            }
            
            # Show manual instructions
            show_manual_configuration_instructions
            
            log_success "Instalación completada - configuración manual pendiente"
            ;;
    esac
    
    # =================================================================
    # PHASE 3: VALIDATION AND COMPLETION
    # =================================================================
    
    log_info "=== FASE 3: Validación y finalización ==="
    
    # Validate installation
    validate_installation || {
        log_warn "Algunas validaciones fallaron, pero la instalación puede ser funcional"
    }
    
    # Test Flask application if we can
    test_flask_application || {
        log_warn "No se pudo validar la aplicación Flask, pero puede funcionar después del reinicio"
    }
    
    # Final success message
    log_success "¡Instalación de Raspberry Pi Gateway completada exitosamente!"
    
    # Display final information based on configuration choice
    display_final_information $config_choice
}

display_final_information() {
    local config_choice=$1
    
    local current_ip=$(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    local tailscale_ip=$(tailscale ip 2>/dev/null || echo "Configurando...")
    local building_address=$(cat "$CONFIG_DIR/building_address.txt" 2>/dev/null || echo "No configurado")
    
    echo ""
    echo "=========================================="
    echo "INSTALACIÓN COMPLETADA EXITOSAMENTE"
    echo "=========================================="
    echo "🏢 Edificio: $building_address"
    echo "🔒 Tailscale IP: $tailscale_ip"
    echo "📁 Configuración: $CONFIG_DIR"
    echo "📋 Logs: $LOG_FILE"
    echo "=========================================="
    
    case $config_choice in
        0)  # Applied now
            echo "✅ CONFIGURACIÓN DE RED APLICADA"
            echo "=========================================="
            echo "🌐 IP Ethernet: $current_ip"
            echo "🌐 Portal Web: http://$current_ip:$WEB_PORT"
            echo "📱 Configuración WiFi: Disponible en portal web"
            echo ""
            echo "PRÓXIMOS PASOS:"
            echo "1. Conéctese a TP-Link WiFi: 'ControlsegConfig'"
            echo "2. Use contraseña: 'Grupo1598'"
            echo "3. Abra portal web: http://$current_ip:$WEB_PORT"
            echo "4. Configure conexión WiFi del edificio"
            echo "5. Sistema cambiará automáticamente ethernet a DHCP"
            ;;
            
        1)  # Deferred to reboot
            echo "⏳ CONFIGURACIÓN DE RED DIFERIDA"
            echo "=========================================="
            echo "🌐 IP Ethernet actual: $current_ip"
            echo "🔄 IP estática después del reinicio: $STATIC_IP"
            echo "🌐 Portal web después del reinicio: http://$STATIC_IP:$WEB_PORT"
            echo ""
            echo "⚠️  REINICIAR PARA APLICAR CONFIGURACIÓN:"
            echo "   sudo reboot"
            echo ""
            echo "DESPUÉS DEL REINICIO:"
            echo "1. Conéctese a TP-Link WiFi: 'ControlsegConfig'"
            echo "2. Use contraseña: 'Grupo1598'"
            echo "3. Abra portal web: http://$STATIC_IP:$WEB_PORT"
            echo "4. Configure conexión WiFi del edificio"
            ;;
            
        2)  # Manual later
            echo "📋 CONFIGURACIÓN MANUAL PENDIENTE"
            echo "=========================================="
            echo "🌐 IP Ethernet actual: $current_ip"
            echo "⚙️  Configuración manual requerida"
            echo ""
            echo "REVISAR INSTRUCCIONES MOSTRADAS ANTERIORMENTE"
            echo "O ejecutar:"
            echo "   sudo $CONFIG_DIR/apply_network_config.sh"
            ;;
    esac
    
    echo "=========================================="
    echo ""
    echo "🔧 COMANDOS DE GESTIÓN:"
    echo "  systemctl status $SERVICE_NAME"
    echo "  systemctl status $REVERT_SERVICE_NAME"
    echo "  tail -f $LOG_FILE"
    echo "  tail -f /var/log/raspberry_gateway_app.log"
    echo ""
    echo "🔄 BACKUP DE CONFIGURACIÓN:"
    local backup_location=$(cat "$CONFIG_DIR/backup_location.txt" 2>/dev/null || echo "No disponible")
    echo "  $backup_location"
    echo "=========================================="
    
    log_info "Información de instalación mostrada al usuario"
}

# ============================================
# SCRIPT EXECUTION
# ============================================

# Execute main function
main "$@"