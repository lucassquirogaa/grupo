#!/bin/bash

# ============================================
# WiFi Mode Monitor Script
# ============================================
# Monitors WiFi connectivity and automatically switches between
# Access Point and Client modes based on configuration and connection status
# ============================================

set -e

# Configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/var/log/wifi_mode_monitor.log"
CONFIG_DIR="/opt/gateway"
WIFI_CONFIG_FILE="$CONFIG_DIR/wifi_client.conf"

# Scripts
AP_MODE_SCRIPT="$CONFIG_DIR/scripts/ap_mode.sh"
CLIENT_MODE_SCRIPT="$CONFIG_DIR/scripts/client_mode.sh"

# WiFi interface
WIFI_INTERFACE="wlan0"

# Monitor settings
CHECK_INTERVAL=30  # seconds
CONNECTION_TIMEOUT=5  # ping timeout
MAX_FAILURES=3  # failures before switching modes

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
    echo "[$timestamp] [MONITOR] [$level] $message" | tee -a "$LOG_FILE"
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
# UTILITY FUNCTIONS
# ============================================

get_current_mode() {
    if [ -f "$CONFIG_DIR/current_wifi_mode" ]; then
        cat "$CONFIG_DIR/current_wifi_mode"
    else
        echo "unknown"
    fi
}

set_current_mode() {
    echo "$1" > "$CONFIG_DIR/current_wifi_mode"
    echo "$(date)" > "$CONFIG_DIR/${1}_mode_started"
}

has_wifi_config() {
    [ -f "$WIFI_CONFIG_FILE" ] && [ -s "$WIFI_CONFIG_FILE" ]
}

is_interface_up() {
    ip link show "$WIFI_INTERFACE" 2>/dev/null | grep -q "state UP"
}

is_ap_mode_running() {
    systemctl is-active --quiet hostapd && systemctl is-active --quiet dnsmasq
}

is_client_connected() {
    if command -v wpa_cli >/dev/null 2>&1; then
        wpa_cli -i "$WIFI_INTERFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED"
    else
        return 1
    fi
}

has_ip_address() {
    ip addr show "$WIFI_INTERFACE" 2>/dev/null | grep -q "inet "
}

test_internet_connectivity() {
    # Test multiple DNS servers
    ping -c 1 -W "$CONNECTION_TIMEOUT" 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W "$CONNECTION_TIMEOUT" 1.1.1.1 >/dev/null 2>&1 || \
    ping -c 1 -W "$CONNECTION_TIMEOUT" 8.8.4.4 >/dev/null 2>&1
}

test_local_gateway() {
    local gateway=$(ip route | grep "^default" | grep "$WIFI_INTERFACE" | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        ping -c 1 -W "$CONNECTION_TIMEOUT" "$gateway" >/dev/null 2>&1
    else
        return 1
    fi
}

# ============================================
# MODE SWITCHING FUNCTIONS
# ============================================

switch_to_ap_mode() {
    log_info "Switching to Access Point mode..."
    
    if [ -x "$AP_MODE_SCRIPT" ]; then
        if "$AP_MODE_SCRIPT"; then
            set_current_mode "ap"
            log_success "Successfully switched to AP mode"
            return 0
        else
            log_error "Failed to switch to AP mode"
            return 1
        fi
    else
        log_error "AP mode script not found or not executable: $AP_MODE_SCRIPT"
        return 1
    fi
}

switch_to_client_mode() {
    log_info "Switching to WiFi client mode..."
    
    if [ -x "$CLIENT_MODE_SCRIPT" ]; then
        if "$CLIENT_MODE_SCRIPT"; then
            set_current_mode "client"
            log_success "Successfully switched to client mode"
            return 0
        else
            log_error "Failed to switch to client mode"
            return 1
        fi
    else
        log_error "Client mode script not found or not executable: $CLIENT_MODE_SCRIPT"
        return 1
    fi
}

# ============================================
# MONITORING FUNCTIONS
# ============================================

check_ap_mode_health() {
    log_info "Checking AP mode health..."
    
    # Check if hostapd and dnsmasq are running
    if ! is_ap_mode_running; then
        log_warn "AP services not running"
        return 1
    fi
    
    # Check if interface has correct IP
    if ! ip addr show "$WIFI_INTERFACE" | grep -q "192.168.4.100"; then
        log_warn "AP interface does not have correct IP"
        return 1
    fi
    
    # Check if interface is up
    if ! is_interface_up; then
        log_warn "WiFi interface is down"
        return 1
    fi
    
    log_info "AP mode is healthy"
    return 0
}

check_client_mode_health() {
    log_info "Checking client mode health..."
    
    # Check if wpa_supplicant is connected
    if ! is_client_connected; then
        log_warn "WiFi client not connected"
        return 1
    fi
    
    # Check if interface has IP address
    if ! has_ip_address; then
        log_warn "WiFi interface has no IP address"
        return 1
    fi
    
    # Test local connectivity first
    if ! test_local_gateway; then
        log_warn "Cannot reach local gateway"
        return 1
    fi
    
    # Test internet connectivity
    if ! test_internet_connectivity; then
        log_warn "No internet connectivity"
        # Don't fail on internet connectivity issues - local network might be sufficient
        # return 1
    fi
    
    log_info "Client mode is healthy"
    return 0
}

monitor_and_decide() {
    local current_mode=$(get_current_mode)
    local failure_count_file="$CONFIG_DIR/mode_failure_count"
    local failure_count=0
    
    # Load failure count
    if [ -f "$failure_count_file" ]; then
        failure_count=$(cat "$failure_count_file")
    fi
    
    log_info "Current mode: $current_mode, Failure count: $failure_count"
    
    case "$current_mode" in
        "ap")
            # In AP mode - check if client config is available and switch if so
            if has_wifi_config; then
                log_info "WiFi client configuration detected - attempting switch to client mode"
                if switch_to_client_mode; then
                    echo "0" > "$failure_count_file"  # Reset failure count
                    return 0
                else
                    failure_count=$((failure_count + 1))
                    echo "$failure_count" > "$failure_count_file"
                    log_error "Failed to switch to client mode (attempt $failure_count/$MAX_FAILURES)"
                fi
            else
                # No client config - verify AP mode health
                if ! check_ap_mode_health; then
                    log_warn "AP mode unhealthy - attempting restart"
                    if switch_to_ap_mode; then
                        echo "0" > "$failure_count_file"
                    else
                        failure_count=$((failure_count + 1))
                        echo "$failure_count" > "$failure_count_file"
                    fi
                else
                    echo "0" > "$failure_count_file"  # Reset failure count on health check success
                fi
            fi
            ;;
        
        "client")
            # In client mode - check health and fall back to AP if needed
            if ! check_client_mode_health; then
                failure_count=$((failure_count + 1))
                echo "$failure_count" > "$failure_count_file"
                log_warn "Client mode unhealthy (attempt $failure_count/$MAX_FAILURES)"
                
                if [ $failure_count -ge $MAX_FAILURES ]; then
                    log_warn "Max failures reached - switching to AP mode"
                    if switch_to_ap_mode; then
                        echo "0" > "$failure_count_file"
                    fi
                fi
            else
                echo "0" > "$failure_count_file"  # Reset failure count on health check success
            fi
            ;;
        
        "unknown"|*)
            # Unknown mode - determine what should be active
            log_warn "Unknown WiFi mode - determining appropriate mode"
            
            if has_wifi_config; then
                log_info "WiFi config available - attempting client mode"
                if ! switch_to_client_mode; then
                    log_warn "Client mode failed - falling back to AP mode"
                    switch_to_ap_mode
                fi
            else
                log_info "No WiFi config - starting AP mode"
                switch_to_ap_mode
            fi
            echo "0" > "$failure_count_file"
            ;;
    esac
}

# ============================================
# MAIN EXECUTION
# ============================================

run_once() {
    log_info "WiFi Mode Monitor - Single Check"
    monitor_and_decide
}

run_daemon() {
    log_info "WiFi Mode Monitor - Starting daemon mode"
    log_info "Check interval: ${CHECK_INTERVAL}s, Connection timeout: ${CONNECTION_TIMEOUT}s"
    
    while true; do
        monitor_and_decide
        sleep "$CHECK_INTERVAL"
    done
}

main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Parse command line arguments
    case "${1:-daemon}" in
        "once")
            run_once
            ;;
        "daemon")
            run_daemon
            ;;
        *)
            echo "Usage: $0 [once|daemon]"
            echo "  once   - Run a single check and exit"
            echo "  daemon - Run continuously (default)"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"