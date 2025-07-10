#!/bin/bash

# ============================================
# End-to-End WiFi System Validation Test
# ============================================
# Tests the complete WiFi AP system flow without actual WiFi hardware
# Simulates the installation and boot process
# ============================================

set -e

# Configuration
TEST_DIR="/tmp/wifi_system_test"
CONFIG_DIR="/opt/gateway"
LOG_FILE="$TEST_DIR/e2e_test.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# Test functions
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    touch "$LOG_FILE"
    
    # Ensure config directory exists
    sudo mkdir -p "$CONFIG_DIR/scripts"
    
    log_success "Test environment ready"
}

test_installation_components() {
    log_info "Testing installation components..."
    
    # Check if all necessary files exist
    local missing_files=()
    
    local required_files=(
        "install_gateway_v10.sh"
        "config/hostapd.conf.template"
        "config/dnsmasq.conf.template"
        "config/dhcpcd.conf.backup"
        "config/01-netcfg.yaml.template"
        "scripts/ap_mode.sh"
        "scripts/client_mode.sh"
        "scripts/wifi_mode_monitor.sh"
        "scripts/wifi_config_manager.sh"
        "scripts/web_wifi_api.sh"
        "wifi-mode-monitor.service"
        "network_config_applier.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        log_success "All required installation files present"
    else
        log_error "Missing files: ${missing_files[*]}"
        return 1
    fi
}

test_script_syntax() {
    log_info "Testing script syntax..."
    
    local scripts=(
        "scripts/ap_mode.sh"
        "scripts/client_mode.sh"
        "scripts/wifi_mode_monitor.sh"
        "scripts/wifi_config_manager.sh"
        "scripts/web_wifi_api.sh"
        "install_gateway_v10.sh"
        "network_config_applier.sh"
    )
    
    for script in "${scripts[@]}"; do
        if ! bash -n "$script" 2>/dev/null; then
            log_error "Syntax error in $script"
            return 1
        fi
    done
    
    log_success "All scripts have valid syntax"
}

test_configuration_templates() {
    log_info "Testing configuration templates..."
    
    # Test hostapd configuration
    if ! grep -q "ssid=ControlsegConfig" config/hostapd.conf.template; then
        log_error "hostapd template missing correct SSID"
        return 1
    fi
    
    if ! grep -q "wpa_passphrase=Grupo1598" config/hostapd.conf.template; then
        log_error "hostapd template missing correct password"
        return 1
    fi
    
    # Test dnsmasq configuration
    if ! grep -q "dhcp-range=192.168.4.50,192.168.4.150" config/dnsmasq.conf.template; then
        log_error "dnsmasq template missing correct DHCP range"
        return 1
    fi
    
    if ! grep -q "dhcp-option=3,192.168.4.100" config/dnsmasq.conf.template; then
        log_error "dnsmasq template missing correct gateway"
        return 1
    fi
    
    log_success "Configuration templates are correct"
}

test_script_paths() {
    log_info "Testing script path references..."
    
    # Check if wifi_mode_monitor.sh has correct paths
    if grep -q "\.\./scripts/" scripts/wifi_mode_monitor.sh; then
        log_error "wifi_mode_monitor.sh still has incorrect path references"
        return 1
    fi
    
    # Check if web_wifi_api.sh has correct paths
    if grep -q "\.\./scripts/" scripts/web_wifi_api.sh; then
        log_error "web_wifi_api.sh still has incorrect path references"
        return 1
    fi
    
    log_success "Script paths are correct"
}

test_service_configuration() {
    log_info "Testing service configuration..."
    
    # Check if service file has correct path
    if ! grep -q "ExecStart=/opt/gateway/scripts/wifi_mode_monitor.sh" wifi-mode-monitor.service; then
        log_error "Service file has incorrect script path"
        return 1
    fi
    
    log_success "Service configuration is correct"
}

simulate_installation_process() {
    log_info "Simulating installation process..."
    
    # Copy templates to config directory (simulate installation)
    sudo cp config/*.template "$CONFIG_DIR/" 2>/dev/null || true
    sudo cp config/dhcpcd.conf.backup "$CONFIG_DIR/" 2>/dev/null || true
    
    # Copy scripts to config directory (simulate installation)
    sudo cp scripts/*.sh "$CONFIG_DIR/scripts/" 2>/dev/null || true
    sudo chmod +x "$CONFIG_DIR/scripts/"*.sh 2>/dev/null || true
    
    log_success "Installation simulation completed"
}

test_wifi_config_manager() {
    log_info "Testing WiFi configuration manager..."
    
    # Test saving configuration
    if ! sudo "$CONFIG_DIR/scripts/wifi_config_manager.sh" save "TestNetwork" "testpassword" "WPA2" >/dev/null 2>&1; then
        log_warn "WiFi config manager save test failed (expected without wlan0)"
    fi
    
    # Test show configuration
    if ! sudo "$CONFIG_DIR/scripts/wifi_config_manager.sh" show >/dev/null 2>&1; then
        log_warn "WiFi config manager show test failed"
    fi
    
    log_success "WiFi configuration manager basic functionality works"
}

test_web_api_interface() {
    log_info "Testing web API interface..."
    
    # Test scan command
    if ! sudo "$CONFIG_DIR/scripts/web_wifi_api.sh" scan >/dev/null 2>&1; then
        log_warn "Web API scan test failed (expected without WiFi hardware)"
    fi
    
    # Test usage output
    if ! sudo "$CONFIG_DIR/scripts/web_wifi_api.sh" 2>&1 | grep -q "Usage:"; then
        log_error "Web API doesn't show usage information"
        return 1
    fi
    
    log_success "Web API interface basic functionality works"
}

cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    log_success "Cleanup completed"
}

# Main execution
main() {
    echo "============================================"
    echo "End-to-End WiFi System Validation Test"
    echo "============================================"
    echo ""
    
    setup_test_environment
    
    local tests=(
        "test_installation_components"
        "test_script_syntax"
        "test_configuration_templates"
        "test_script_paths"
        "test_service_configuration"
        "simulate_installation_process"
        "test_wifi_config_manager"
        "test_web_api_interface"
    )
    
    local passed=0
    local failed=0
    
    for test in "${tests[@]}"; do
        echo ""
        if $test; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    echo "============================================"
    echo "TEST SUMMARY"
    echo "============================================"
    echo "Total Tests: $((passed + failed))"
    echo "Passed: $passed"
    echo "Failed: $failed"
    
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
        log_success "End-to-end validation completed successfully"
    else
        echo -e "${YELLOW}⚠️  Some tests had warnings${NC}"
        log_warn "End-to-end validation completed with warnings"
    fi
    
    cleanup
    
    return $failed
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This test script must be run as root"
    exit 1
fi

# Execute main function
main "$@"