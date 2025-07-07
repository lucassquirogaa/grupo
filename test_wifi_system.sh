#!/bin/bash

# ============================================
# WiFi System Test Script
# ============================================
# Tests the hostapd + dnsmasq WiFi system functionality
# Validates configuration files, scripts, and services
# ============================================

set -e

# Configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/var/log/wifi_system_test.log"
CONFIG_DIR="/opt/gateway"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# ============================================
# LOGGING AND TEST FUNCTIONS
# ============================================

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [WIFI_TEST] [$level] $message" | tee -a "$LOG_FILE"
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

test_start() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo ""
    echo -e "${BLUE}[TEST $TESTS_TOTAL]${NC} $test_name"
    echo "----------------------------------------"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✅ PASSED${NC}"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}❌ FAILED${NC}"
}

# ============================================
# TEST FUNCTIONS
# ============================================

test_configuration_files() {
    test_start "Configuration Files Existence"
    
    local config_files=(
        "$CONFIG_DIR/hostapd.conf.template"
        "$CONFIG_DIR/dnsmasq.conf.template"
        "$CONFIG_DIR/dhcpcd.conf.backup"
        "$CONFIG_DIR/01-netcfg.yaml.template"
    )
    
    local all_exist=true
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            echo "✓ Found: $file"
        else
            echo "✗ Missing: $file"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        test_pass
    else
        test_fail
    fi
}

test_scripts_existence() {
    test_start "Scripts Existence and Permissions"
    
    local scripts=(
        "scripts/ap_mode.sh"
        "scripts/client_mode.sh"
        "scripts/wifi_mode_monitor.sh"
        "scripts/wifi_config_manager.sh"
        "scripts/web_wifi_api.sh"
        "scripts/patch_web_portal.sh"
    )
    
    local all_exist=true
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                echo "✓ Found and executable: $script"
            else
                echo "✗ Found but not executable: $script"
                all_exist=false
            fi
        else
            echo "✗ Missing: $script"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        test_pass
    else
        test_fail
    fi
}

test_service_files() {
    test_start "Service Files"
    
    local services=(
        "wifi-mode-monitor.service"
        "network-config-applier.service"
    )
    
    local all_exist=true
    for service in "${services[@]}"; do
        if [ -f "$service" ]; then
            echo "✓ Found: $service"
        else
            echo "✗ Missing: $service"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        test_pass
    else
        test_fail
    fi
}

test_configuration_syntax() {
    test_start "Configuration File Syntax"
    
    local all_valid=true
    
    # Test hostapd configuration syntax
    if [ -f "$CONFIG_DIR/hostapd.conf.template" ]; then
        if grep -q "interface=wlan0" "$CONFIG_DIR/hostapd.conf.template" && \
           grep -q "ssid=ControlsegConfig" "$CONFIG_DIR/hostapd.conf.template" && \
           grep -q "wpa_passphrase=Grupo1598" "$CONFIG_DIR/hostapd.conf.template"; then
            echo "✓ hostapd.conf.template syntax OK"
        else
            echo "✗ hostapd.conf.template missing required fields"
            all_valid=false
        fi
    fi
    
    # Test dnsmasq configuration syntax
    if [ -f "$CONFIG_DIR/dnsmasq.conf.template" ]; then
        if grep -q "interface=wlan0" "$CONFIG_DIR/dnsmasq.conf.template" && \
           grep -q "dhcp-range=192.168.4.50,192.168.4.150" "$CONFIG_DIR/dnsmasq.conf.template"; then
            echo "✓ dnsmasq.conf.template syntax OK"
        else
            echo "✗ dnsmasq.conf.template missing required fields"
            all_valid=false
        fi
    fi
    
    if [ "$all_valid" = true ]; then
        test_pass
    else
        test_fail
    fi
}

test_scripts_syntax() {
    test_start "Scripts Syntax Check"
    
    local all_valid=true
    local scripts=(
        "scripts/ap_mode.sh"
        "scripts/client_mode.sh"
        "scripts/wifi_mode_monitor.sh"
        "scripts/wifi_config_manager.sh"
        "scripts/web_wifi_api.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>/dev/null; then
                echo "✓ $script syntax OK"
            else
                echo "✗ $script syntax error"
                all_valid=false
            fi
        fi
    done
    
    if [ "$all_valid" = true ]; then
        test_pass
    else
        test_fail
    fi
}

test_dependencies() {
    test_start "System Dependencies"
    
    local deps=(
        "hostapd"
        "dnsmasq"
        "wpa_supplicant"
        "dhcpcd"
        "iptables"
        "ip"
        "iwlist"
    )
    
    local all_available=true
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            echo "✓ $dep available"
        else
            echo "✗ $dep not found"
            all_available=false
        fi
    done
    
    if [ "$all_available" = true ]; then
        test_pass
    else
        test_fail
        echo "Note: Some dependencies may be installed during main installation"
    fi
}

test_network_interface() {
    test_start "Network Interface Check"
    
    if ip link show wlan0 >/dev/null 2>&1; then
        echo "✓ wlan0 interface found"
        
        # Show interface details
        local wlan0_status=$(ip link show wlan0 | grep "state" | awk '{print $9}')
        echo "  Interface state: $wlan0_status"
        
        test_pass
    else
        echo "✗ wlan0 interface not found"
        echo "Note: This is expected in environments without WiFi hardware"
        test_fail
    fi
}

test_wifi_config_manager() {
    test_start "WiFi Config Manager Functionality"
    
    if [ -x "scripts/wifi_config_manager.sh" ]; then
        # Test help output
        if scripts/wifi_config_manager.sh 2>&1 | grep -q "Usage:"; then
            echo "✓ WiFi config manager shows usage"
            test_pass
        else
            echo "✗ WiFi config manager doesn't show proper usage"
            test_fail
        fi
    else
        echo "✗ WiFi config manager not executable"
        test_fail
    fi
}

test_main_installer_integration() {
    test_start "Main Installer Integration"
    
    local all_integrated=true
    
    # Check if main installer references new functions
    if grep -q "ensure_hostapd_dnsmasq_templates" install_gateway_v10.sh; then
        echo "✓ Main installer has template function"
    else
        echo "✗ Main installer missing template function"
        all_integrated=false
    fi
    
    if grep -q "install_wifi_mode_monitor_service" install_gateway_v10.sh; then
        echo "✓ Main installer has WiFi monitor service"
    else
        echo "✗ Main installer missing WiFi monitor service"
        all_integrated=false
    fi
    
    if grep -q "setup_networkmanager_ignore_wlan0" install_gateway_v10.sh; then
        echo "✓ Main installer configures NetworkManager"
    else
        echo "✗ Main installer missing NetworkManager config"
        all_integrated=false
    fi
    
    if [ "$all_integrated" = true ]; then
        test_pass
    else
        test_fail
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

show_test_summary() {
    echo ""
    echo "============================================"
    echo "TEST SUMMARY"
    echo "============================================"
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    local success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    echo "Success Rate: $success_rate%"
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}⚠️  Some tests failed${NC}"
        return 1
    fi
}

main() {
    echo "============================================"
    echo "WiFi System Test Suite"
    echo "Testing hostapd + dnsmasq implementation"
    echo "============================================"
    
    # Run all tests
    test_configuration_files
    test_scripts_existence
    test_service_files
    test_configuration_syntax
    test_scripts_syntax
    test_dependencies
    test_network_interface
    test_wifi_config_manager
    test_main_installer_integration
    
    # Show summary
    show_test_summary
}

# Execute main function
main "$@"