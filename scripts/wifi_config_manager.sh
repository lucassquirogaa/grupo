#!/bin/bash

# ============================================
# WiFi Configuration Manager
# ============================================
# Utility script for managing WiFi client configurations
# Used by the web portal to save and validate WiFi settings
# ============================================

set -e

# Configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/var/log/wifi_config.log"
CONFIG_DIR="/opt/gateway"
WIFI_CONFIG_FILE="$CONFIG_DIR/wifi_client.conf"

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
    # Only log to file if we have permission, otherwise just echo
    if touch "$LOG_FILE" 2>/dev/null; then
        echo "[$timestamp] [WIFI_CONFIG] [$level] $message" | tee -a "$LOG_FILE"
    else
        echo "[$timestamp] [WIFI_CONFIG] [$level] $message"
    fi
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

escape_ssid() {
    local ssid="$1"
    # Escape special characters for wpa_supplicant
    echo "\"$ssid\""
}

escape_password() {
    local password="$1"
    # Escape special characters for wpa_supplicant
    echo "\"$password\""
}

validate_ssid() {
    local ssid="$1"
    
    if [ -z "$ssid" ]; then
        log_error "SSID cannot be empty"
        return 1
    fi
    
    if [ ${#ssid} -gt 32 ]; then
        log_error "SSID too long (max 32 characters)"
        return 1
    fi
    
    return 0
}

validate_password() {
    local password="$1"
    
    if [ ${#password} -lt 8 ] && [ ${#password} -gt 0 ]; then
        log_error "Password too short (minimum 8 characters)"
        return 1
    fi
    
    if [ ${#password} -gt 63 ]; then
        log_error "Password too long (max 63 characters)"
        return 1
    fi
    
    return 0
}

# ============================================
# MAIN FUNCTIONS
# ============================================

save_wifi_config() {
    local ssid="$1"
    local password="$2"
    local security="$3"
    
    log_info "Saving WiFi configuration for SSID: $ssid"
    
    # Validate inputs
    if ! validate_ssid "$ssid"; then
        return 1
    fi
    
    if ! validate_password "$password"; then
        return 1
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Backup existing config
    if [ -f "$WIFI_CONFIG_FILE" ]; then
        cp "$WIFI_CONFIG_FILE" "$WIFI_CONFIG_FILE.backup.$(date +%s)"
    fi
    
    # Create wpa_supplicant network block
    local escaped_ssid=$(escape_ssid "$ssid")
    local config_content=""
    
    if [ -z "$password" ]; then
        # Open network
        config_content="network={
    ssid=$escaped_ssid
    key_mgmt=NONE
    priority=1
}"
    else
        # Secured network
        local escaped_password=$(escape_password "$password")
        config_content="network={
    ssid=$escaped_ssid
    psk=$escaped_password
    key_mgmt=WPA-PSK
    priority=1
}"
    fi
    
    # Write configuration
    echo "$config_content" > "$WIFI_CONFIG_FILE"
    
    # Set proper permissions
    chmod 600 "$WIFI_CONFIG_FILE"
    chown root:root "$WIFI_CONFIG_FILE"
    
    # Log configuration (without password)
    log_success "WiFi configuration saved successfully"
    log_info "SSID: $ssid"
    log_info "Security: ${security:-Open}"
    log_info "Config file: $WIFI_CONFIG_FILE"
    
    return 0
}

remove_wifi_config() {
    log_info "Removing WiFi configuration..."
    
    if [ -f "$WIFI_CONFIG_FILE" ]; then
        # Backup before removal
        cp "$WIFI_CONFIG_FILE" "$WIFI_CONFIG_FILE.removed.$(date +%s)"
        rm -f "$WIFI_CONFIG_FILE"
        log_success "WiFi configuration removed"
    else
        log_info "No WiFi configuration to remove"
    fi
    
    return 0
}

show_wifi_config() {
    if [ -f "$WIFI_CONFIG_FILE" ]; then
        log_info "Current WiFi configuration:"
        cat "$WIFI_CONFIG_FILE"
        
        # Extract SSID for display
        local ssid=$(grep "ssid=" "$WIFI_CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')
        log_info "Configured SSID: $ssid"
    else
        log_info "No WiFi configuration found"
        return 1
    fi
    
    return 0
}

test_wifi_config() {
    log_info "Testing WiFi configuration..."
    
    if [ ! -f "$WIFI_CONFIG_FILE" ]; then
        log_error "No WiFi configuration to test"
        return 1
    fi
    
    # Validate configuration file format
    if ! grep -q "network={" "$WIFI_CONFIG_FILE"; then
        log_error "Invalid configuration format"
        return 1
    fi
    
    if ! grep -q "ssid=" "$WIFI_CONFIG_FILE"; then
        log_error "No SSID found in configuration"
        return 1
    fi
    
    # Test with wpa_supplicant syntax check
    if command -v wpa_supplicant >/dev/null 2>&1; then
        local temp_conf="/tmp/wpa_test_$$.conf"
        cat > "$temp_conf" << EOF
country=AR
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

EOF
        cat "$WIFI_CONFIG_FILE" >> "$temp_conf"
        
        if wpa_supplicant -c "$temp_conf" -D nl80211 -i wlan0 -t >/dev/null 2>&1; then
            log_success "WiFi configuration syntax is valid"
            rm -f "$temp_conf"
            return 0
        else
            log_error "WiFi configuration syntax is invalid"
            rm -f "$temp_conf"
            return 1
        fi
    else
        log_warn "wpa_supplicant not available for testing"
        return 0
    fi
}

scan_networks() {
    log_info "Scanning for available networks..."
    
    if command -v iwlist >/dev/null 2>&1; then
        # Use iwlist for scanning
        iwlist wlan0 scan 2>/dev/null | grep "ESSID:" | cut -d'"' -f2 | sort -u
    elif command -v iw >/dev/null 2>&1; then
        # Use iw for scanning
        iw dev wlan0 scan 2>/dev/null | grep "SSID:" | cut -d' ' -f2- | sort -u
    else
        log_error "No wireless scanning tool available"
        return 1
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

show_usage() {
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  save <ssid> [password] [security]  - Save WiFi configuration"
    echo "  remove                             - Remove WiFi configuration"
    echo "  show                               - Show current configuration"
    echo "  test                               - Test configuration validity"
    echo "  scan                               - Scan for available networks"
    echo ""
    echo "Examples:"
    echo "  $0 save \"MyNetwork\" \"mypassword\" \"WPA2\""
    echo "  $0 save \"OpenNetwork\"  # For open networks"
    echo "  $0 remove"
    echo "  $0 show"
    echo "  $0 test"
    echo "  $0 scan"
}

main() {
    local command="$1"
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    
    # Show usage if no command provided
    if [ -z "$command" ]; then
        show_usage
        exit 0
    fi
    
    case "$command" in
        "save")
            local ssid="$2"
            local password="$3"
            local security="$4"
            
            if [ -z "$ssid" ]; then
                log_error "SSID is required"
                show_usage
                exit 1
            fi
            
            save_wifi_config "$ssid" "$password" "$security"
            ;;
        
        "remove")
            remove_wifi_config
            ;;
        
        "show")
            show_wifi_config
            ;;
        
        "test")
            test_wifi_config
            ;;
        
        "scan")
            scan_networks
            ;;
        
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"