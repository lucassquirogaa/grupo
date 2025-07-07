#!/bin/bash

# ============================================
# Access Point Mode Script
# ============================================
# Switches Raspberry Pi to Access Point mode using hostapd + dnsmasq
# Replaces NetworkManager-based AP functionality
# ============================================

set -e

# Configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/var/log/wifi_mode.log"
CONFIG_DIR="/opt/gateway"
WIFI_CONFIG_FILE="$CONFIG_DIR/wifi_client.conf"

# Service configurations
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
DHCPCD_CONF="/etc/dhcpcd.conf"

# AP Configuration
AP_SSID="ControlsegConfig"
AP_PASSWORD="Grupo1598"
AP_IP="192.168.4.100"
AP_INTERFACE="wlan0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# LOGGING FUNCTIONS
# ============================================

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AP_MODE] [$level] $message" | tee -a "$LOG_FILE"
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

# ============================================
# MAIN FUNCTIONS
# ============================================

check_interface() {
    log_info "Checking wlan0 interface availability..."
    if ! ip link show $AP_INTERFACE >/dev/null 2>&1; then
        log_error "Interface $AP_INTERFACE not found"
        return 1
    fi
    log_success "Interface $AP_INTERFACE is available"
    return 0
}

stop_network_services() {
    log_info "Stopping network services..."
    
    # Stop NetworkManager from managing wlan0
    if systemctl is-active --quiet NetworkManager; then
        log_info "Stopping NetworkManager temporarily..."
        systemctl stop NetworkManager || log_warn "Failed to stop NetworkManager"
    fi
    
    # Stop any existing hostapd/dnsmasq
    systemctl stop hostapd 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    
    # Disconnect any existing WiFi connections
    if command -v wpa_cli >/dev/null 2>&1; then
        wpa_cli disconnect 2>/dev/null || true
    fi
    
    # Kill any remaining wpa_supplicant processes
    pkill -f "wpa_supplicant.*$AP_INTERFACE" || true
    
    log_success "Network services stopped"
}

setup_hostapd() {
    log_info "Setting up hostapd configuration..."
    
    # Create hostapd configuration
    cp "$CONFIG_DIR/hostapd.conf.template" "$HOSTAPD_CONF" || {
        log_error "Failed to copy hostapd template"
        return 1
    }
    
    # Ensure correct permissions
    chmod 644 "$HOSTAPD_CONF"
    chown root:root "$HOSTAPD_CONF"
    
    # Update hostapd daemon configuration
    echo "DAEMON_CONF=\"$HOSTAPD_CONF\"" > /etc/default/hostapd
    
    log_success "hostapd configuration ready"
}

setup_dnsmasq() {
    log_info "Setting up dnsmasq configuration..."
    
    # Backup existing dnsmasq config
    if [ -f "$DNSMASQ_CONF" ] && [ ! -f "$DNSMASQ_CONF.backup" ]; then
        cp "$DNSMASQ_CONF" "$DNSMASQ_CONF.backup"
    fi
    
    # Create dnsmasq configuration
    cp "$CONFIG_DIR/dnsmasq.conf.template" "$DNSMASQ_CONF" || {
        log_error "Failed to copy dnsmasq template"
        return 1
    }
    
    # Ensure correct permissions
    chmod 644 "$DNSMASQ_CONF"
    chown root:root "$DNSMASQ_CONF"
    
    log_success "dnsmasq configuration ready"
}

configure_interface() {
    log_info "Configuring interface $AP_INTERFACE..."
    
    # Bring interface down
    ip link set $AP_INTERFACE down 2>/dev/null || true
    
    # Configure static IP for AP mode
    ip addr flush dev $AP_INTERFACE
    ip addr add ${AP_IP}/24 dev $AP_INTERFACE
    ip link set $AP_INTERFACE up
    
    # Add routing
    ip route add 192.168.4.0/24 dev $AP_INTERFACE 2>/dev/null || true
    
    log_success "Interface $AP_INTERFACE configured with IP $AP_IP"
}

setup_iptables() {
    log_info "Setting up iptables for AP mode..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Configure iptables for NAT (if eth0 available)
    if ip link show eth0 >/dev/null 2>&1; then
        # Clear existing rules
        iptables -t nat -F
        iptables -F
        iptables -X
        
        # Set up NAT
        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
        iptables -A FORWARD -i eth0 -o $AP_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -i $AP_INTERFACE -o eth0 -j ACCEPT
        
        log_success "iptables configured for NAT forwarding"
    else
        log_warn "eth0 not available - NAT forwarding not configured"
    fi
}

start_services() {
    log_info "Starting AP services..."
    
    # Start hostapd
    systemctl enable hostapd
    systemctl start hostapd || {
        log_error "Failed to start hostapd"
        journalctl -u hostapd --no-pager -n 10
        return 1
    }
    
    # Start dnsmasq
    systemctl enable dnsmasq
    systemctl start dnsmasq || {
        log_error "Failed to start dnsmasq"
        journalctl -u dnsmasq --no-pager -n 10
        return 1
    }
    
    log_success "AP services started successfully"
}

verify_ap() {
    log_info "Verifying Access Point functionality..."
    
    # Check if hostapd is running
    if ! systemctl is-active --quiet hostapd; then
        log_error "hostapd is not running"
        return 1
    fi
    
    # Check if dnsmasq is running
    if ! systemctl is-active --quiet dnsmasq; then
        log_error "dnsmasq is not running"
        return 1
    fi
    
    # Check if interface has correct IP
    if ! ip addr show $AP_INTERFACE | grep -q "$AP_IP"; then
        log_error "Interface does not have correct IP address"
        return 1
    fi
    
    log_success "Access Point is functioning correctly"
    log_info "====================================="
    log_info "ACCESS POINT MODE ACTIVE"
    log_info "====================================="
    log_info "SSID: $AP_SSID"
    log_info "Password: $AP_PASSWORD"
    log_info "Gateway IP: $AP_IP"
    log_info "DHCP Range: 192.168.4.50-150"
    log_info "Portal URL: http://$AP_IP:8080"
    log_info "====================================="
    
    return 0
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    log_info "Starting Access Point mode setup..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Execute setup steps
    check_interface || exit 1
    stop_network_services || exit 1
    setup_hostapd || exit 1
    setup_dnsmasq || exit 1
    configure_interface || exit 1
    setup_iptables || exit 1
    start_services || exit 1
    verify_ap || exit 1
    
    # Create mode marker
    echo "ap" > "$CONFIG_DIR/current_wifi_mode"
    echo "$(date)" > "$CONFIG_DIR/ap_mode_started"
    
    log_success "Access Point mode setup completed successfully"
}

# Execute main function
main "$@"