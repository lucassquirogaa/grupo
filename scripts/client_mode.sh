#!/bin/bash

# ============================================
# WiFi Client Mode Script
# ============================================
# Switches Raspberry Pi to WiFi client mode using wpa_supplicant
# Replaces NetworkManager-based client functionality
# ============================================

set -e

# Configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/var/log/wifi_mode.log"
CONFIG_DIR="/opt/gateway"
WIFI_CONFIG_FILE="$CONFIG_DIR/wifi_client.conf"

# Service configurations
WPA_SUPPLICANT_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
DHCPCD_CONF="/etc/dhcpcd.conf"

# WiFi interface
WIFI_INTERFACE="wlan0"

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
    echo "[$timestamp] [CLIENT_MODE] [$level] $message" | tee -a "$LOG_FILE"
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

check_wifi_config() {
    log_info "Checking WiFi client configuration..."
    
    if [ ! -f "$WIFI_CONFIG_FILE" ]; then
        log_error "WiFi configuration file not found: $WIFI_CONFIG_FILE"
        return 1
    fi
    
    # Validate config file format
    if ! grep -q "ssid=" "$WIFI_CONFIG_FILE" || ! grep -q "psk=" "$WIFI_CONFIG_FILE"; then
        log_error "Invalid WiFi configuration format"
        return 1
    fi
    
    local ssid=$(grep "^ssid=" "$WIFI_CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')
    log_info "WiFi configuration found for SSID: $ssid"
    return 0
}

stop_ap_services() {
    log_info "Stopping Access Point services..."
    
    # Stop hostapd and dnsmasq
    systemctl stop hostapd 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    
    # Disable services to prevent auto-start
    systemctl disable hostapd 2>/dev/null || true
    systemctl disable dnsmasq 2>/dev/null || true
    
    # Clear iptables rules
    iptables -t nat -F 2>/dev/null || true
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    
    log_success "Access Point services stopped"
}

configure_wpa_supplicant() {
    log_info "Configuring wpa_supplicant..."
    
    # Backup existing wpa_supplicant config
    if [ -f "$WPA_SUPPLICANT_CONF" ] && [ ! -f "$WPA_SUPPLICANT_CONF.backup" ]; then
        cp "$WPA_SUPPLICANT_CONF" "$WPA_SUPPLICANT_CONF.backup"
    fi
    
    # Create wpa_supplicant configuration header
    cat > "$WPA_SUPPLICANT_CONF" << EOF
# wpa_supplicant configuration for client mode
country=AR
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

EOF
    
    # Append WiFi network configuration
    cat "$WIFI_CONFIG_FILE" >> "$WPA_SUPPLICANT_CONF"
    
    # Ensure correct permissions
    chmod 600 "$WPA_SUPPLICANT_CONF"
    chown root:root "$WPA_SUPPLICANT_CONF"
    
    log_success "wpa_supplicant configuration created"
}

configure_dhcpcd() {
    log_info "Configuring dhcpcd for client mode..."
    
    # Backup existing dhcpcd config
    if [ -f "$DHCPCD_CONF" ] && [ ! -f "$DHCPCD_CONF.backup.client" ]; then
        cp "$DHCPCD_CONF" "$DHCPCD_CONF.backup.client"
    fi
    
    # Restore original dhcpcd configuration
    if [ -f "$CONFIG_DIR/dhcpcd.conf.backup" ]; then
        cp "$CONFIG_DIR/dhcpcd.conf.backup" "$DHCPCD_CONF"
    fi
    
    # Remove any static IP configuration for wlan0
    sed -i "/^interface $WIFI_INTERFACE/,/^$/d" "$DHCPCD_CONF"
    
    log_success "dhcpcd configured for DHCP on $WIFI_INTERFACE"
}

configure_interface() {
    log_info "Preparing interface $WIFI_INTERFACE..."
    
    # Bring interface down
    ip link set $WIFI_INTERFACE down 2>/dev/null || true
    
    # Clear any existing IP addresses
    ip addr flush dev $WIFI_INTERFACE 2>/dev/null || true
    
    # Remove any AP-specific routes
    ip route del 192.168.4.0/24 dev $WIFI_INTERFACE 2>/dev/null || true
    
    # Bring interface back up
    ip link set $WIFI_INTERFACE up
    
    log_success "Interface $WIFI_INTERFACE reset"
}

start_client_services() {
    log_info "Starting WiFi client services..."
    
    # Kill any existing wpa_supplicant processes
    pkill -f "wpa_supplicant.*$WIFI_INTERFACE" || true
    sleep 2
    
    # Start wpa_supplicant
    wpa_supplicant -B -i "$WIFI_INTERFACE" -c "$WPA_SUPPLICANT_CONF" || {
        log_error "Failed to start wpa_supplicant"
        return 1
    }
    
    # Start dhcpcd
    systemctl restart dhcpcd || {
        log_error "Failed to restart dhcpcd"
        return 1
    }
    
    log_success "WiFi client services started"
}

wait_for_connection() {
    log_info "Waiting for WiFi connection..."
    
    local timeout=60
    local count=0
    
    while [ $count -lt $timeout ]; do
        if wpa_cli -i "$WIFI_INTERFACE" status | grep -q "wpa_state=COMPLETED"; then
            # Get IP address
            local ip_addr=$(ip addr show "$WIFI_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            if [ -n "$ip_addr" ]; then
                log_success "WiFi connection established"
                log_info "IP Address: $ip_addr"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 2
        count=$((count + 2))
    done
    
    log_error "WiFi connection timeout after $timeout seconds"
    return 1
}

verify_connection() {
    log_info "Verifying WiFi connection..."
    
    # Check wpa_supplicant status
    if ! wpa_cli -i "$WIFI_INTERFACE" status | grep -q "wpa_state=COMPLETED"; then
        log_error "wpa_supplicant not connected"
        return 1
    fi
    
    # Check if we have an IP address
    local ip_addr=$(ip addr show "$WIFI_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -z "$ip_addr" ]; then
        log_error "No IP address assigned"
        return 1
    fi
    
    # Test internet connectivity
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_success "Internet connectivity verified"
    else
        log_warn "No internet connectivity (local network only)"
    fi
    
    # Get current SSID
    local ssid=$(wpa_cli -i "$WIFI_INTERFACE" status | grep "ssid=" | cut -d'=' -f2)
    
    log_success "WiFi client mode active"
    log_info "====================================="
    log_info "WIFI CLIENT MODE ACTIVE"
    log_info "====================================="
    log_info "Connected to: $ssid"
    log_info "IP Address: $ip_addr"
    log_info "Interface: $WIFI_INTERFACE"
    log_info "====================================="
    
    return 0
}

cleanup_on_failure() {
    log_warn "Cleaning up after failure..."
    
    # Stop wpa_supplicant
    pkill -f "wpa_supplicant.*$WIFI_INTERFACE" || true
    
    # Clear interface
    ip addr flush dev $WIFI_INTERFACE 2>/dev/null || true
    
    log_info "Cleanup completed"
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    log_info "Starting WiFi client mode setup..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Execute setup steps
    if ! check_wifi_config; then
        log_error "WiFi client mode setup failed - no configuration"
        exit 1
    fi
    
    if ! stop_ap_services; then
        log_error "Failed to stop AP services"
        exit 1
    fi
    
    if ! configure_wpa_supplicant; then
        log_error "Failed to configure wpa_supplicant"
        exit 1
    fi
    
    if ! configure_dhcpcd; then
        log_error "Failed to configure dhcpcd"
        exit 1
    fi
    
    if ! configure_interface; then
        log_error "Failed to configure interface"
        exit 1
    fi
    
    if ! start_client_services; then
        log_error "Failed to start client services"
        cleanup_on_failure
        exit 1
    fi
    
    if ! wait_for_connection; then
        log_error "Failed to establish WiFi connection"
        cleanup_on_failure
        exit 1
    fi
    
    if ! verify_connection; then
        log_error "WiFi connection verification failed"
        cleanup_on_failure
        exit 1
    fi
    
    # Create mode marker
    echo "client" > "$CONFIG_DIR/current_wifi_mode"
    echo "$(date)" > "$CONFIG_DIR/client_mode_started"
    
    log_success "WiFi client mode setup completed successfully"
}

# Execute main function
main "$@"