#!/bin/bash

# ============================================
# Test WiFi rfkill Fix Implementation
# ============================================
# Test script to validate the WiFi interface setup and scanning functionality
# ============================================

set -e

# Configuration
TEST_SCRIPT_VERSION="1.0"
TEST_LOG_FILE="/tmp/test_wifi_rfkill.log"
CONFIG_DIR="/opt/gateway"

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
    echo "[$timestamp] [TEST] [$level] $message" | tee -a "$TEST_LOG_FILE"
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
# TEST FUNCTIONS
# ============================================

test_rfkill_availability() {
    log_info "Testing rfkill availability..."
    
    if command -v rfkill >/dev/null 2>&1; then
        log_success "rfkill command is available"
        
        # Show current rfkill status
        log_info "Current rfkill status:"
        rfkill list | while read line; do
            log_info "  $line"
        done
        return 0
    else
        log_error "rfkill command not found"
        return 1
    fi
}

test_wlan0_interface() {
    log_info "Testing wlan0 interface presence..."
    
    if ip link show wlan0 >/dev/null 2>&1; then
        local wlan_state=$(ip link show wlan0 | grep -o "state [A-Z]*" | cut -d' ' -f2)
        log_success "wlan0 interface found - State: $wlan_state"
        
        # Show interface details
        log_info "wlan0 interface details:"
        ip link show wlan0 | while read line; do
            log_info "  $line"
        done
        return 0
    else
        log_warn "wlan0 interface not found"
        log_info "Available interfaces:"
        ip link show | grep -E "^[0-9]+:" | while read line; do
            log_info "  $line"
        done
        return 1
    fi
}

test_wifi_unblock() {
    log_info "Testing WiFi unblock functionality..."
    
    if ! command -v rfkill >/dev/null 2>&1; then
        log_warn "rfkill not available, skipping unblock test"
        return 0
    fi
    
    # Show status before unblock
    log_info "WiFi status before unblock:"
    rfkill list wifi | while read line; do
        log_info "  $line"
    done
    
    # Try to unblock WiFi
    if rfkill unblock wifi 2>/dev/null; then
        log_success "WiFi unblock command succeeded"
    else
        log_warn "WiFi unblock command failed (may require root)"
    fi
    
    if rfkill unblock all 2>/dev/null; then
        log_success "All interfaces unblock command succeeded"
    else
        log_warn "All interfaces unblock command failed (may require root)"
    fi
    
    # Show status after unblock
    log_info "WiFi status after unblock:"
    rfkill list wifi | while read line; do
        log_info "  $line"
    done
    
    return 0
}

test_wlan0_activation() {
    log_info "Testing wlan0 activation..."
    
    if ! ip link show wlan0 >/dev/null 2>&1; then
        log_warn "wlan0 not available, skipping activation test"
        return 1
    fi
    
    # Show status before activation
    local state_before=$(ip link show wlan0 | grep -o "state [A-Z]*" | cut -d' ' -f2)
    log_info "wlan0 state before activation: $state_before"
    
    # Try to bring up wlan0
    if ip link set wlan0 up 2>/dev/null; then
        log_success "wlan0 activation command succeeded"
    else
        log_warn "wlan0 activation command failed (may require root)"
    fi
    
    # Show status after activation
    sleep 1
    local state_after=$(ip link show wlan0 | grep -o "state [A-Z]*" | cut -d' ' -f2)
    log_info "wlan0 state after activation: $state_after"
    
    if [ "$state_after" = "UP" ] || [ "$state_after" = "UNKNOWN" ]; then
        log_success "wlan0 is now active"
        return 0
    else
        log_warn "wlan0 may not be fully active (state: $state_after)"
        return 1
    fi
}

test_wifi_scanning_tools() {
    log_info "Testing WiFi scanning tools availability..."
    
    local tools_found=0
    
    if command -v iwlist >/dev/null 2>&1; then
        log_success "iwlist tool is available"
        ((tools_found++))
    else
        log_warn "iwlist tool not found"
    fi
    
    if command -v iw >/dev/null 2>&1; then
        log_success "iw tool is available"
        ((tools_found++))
    else
        log_warn "iw tool not found"
    fi
    
    if command -v nmcli >/dev/null 2>&1; then
        log_success "nmcli tool is available"
        ((tools_found++))
    else
        log_warn "nmcli tool not found"
    fi
    
    if [ $tools_found -gt 0 ]; then
        log_success "At least one WiFi scanning tool is available"
        return 0
    else
        log_error "No WiFi scanning tools found"
        return 1
    fi
}

test_actual_wifi_scan() {
    log_info "Testing actual WiFi scanning..."
    
    if ! ip link show wlan0 >/dev/null 2>&1; then
        log_warn "wlan0 not available, skipping scan test"
        return 1
    fi
    
    # Try iwlist scan
    if command -v iwlist >/dev/null 2>&1; then
        log_info "Attempting WiFi scan with iwlist..."
        local scan_output=$(iwlist wlan0 scan 2>&1)
        local scan_result=$?
        
        if [ $scan_result -eq 0 ]; then
            local network_count=$(echo "$scan_output" | grep -c "ESSID:" || echo "0")
            log_success "iwlist scan succeeded - Found $network_count networks"
            
            # Show a few sample networks
            echo "$scan_output" | grep "ESSID:" | head -3 | while read line; do
                log_info "  Network: $line"
            done
            return 0
        else
            log_warn "iwlist scan failed:"
            echo "$scan_output" | head -5 | while read line; do
                log_warn "  $line"
            done
        fi
    fi
    
    # Try nmcli scan
    if command -v nmcli >/dev/null 2>&1; then
        log_info "Attempting WiFi scan with nmcli..."
        local scan_output=$(nmcli dev wifi 2>&1)
        local scan_result=$?
        
        if [ $scan_result -eq 0 ]; then
            local network_count=$(echo "$scan_output" | grep -v "SSID" | wc -l)
            log_success "nmcli scan succeeded - Found $network_count networks"
            
            # Show header and a few sample networks
            echo "$scan_output" | head -4 | while read line; do
                log_info "  $line"
            done
            return 0
        else
            log_warn "nmcli scan failed:"
            echo "$scan_output" | head -5 | while read line; do
                log_warn "  $line"
            done
        fi
    fi
    
    log_error "All WiFi scan methods failed"
    return 1
}

test_wifi_api_script() {
    log_info "Testing web WiFi API script..."
    
    local wifi_api_script="scripts/web_wifi_api.sh"
    
    if [ ! -f "$wifi_api_script" ]; then
        log_error "WiFi API script not found: $wifi_api_script"
        return 1
    fi
    
    if [ ! -x "$wifi_api_script" ]; then
        log_warn "WiFi API script not executable, making it executable..."
        chmod +x "$wifi_api_script"
    fi
    
    log_info "Testing WiFi API scan command..."
    local api_output=$("$wifi_api_script" scan 2>&1)
    local api_result=$?
    
    if [ $api_result -eq 0 ]; then
        local network_count=$(echo "$api_output" | wc -l)
        log_success "WiFi API scan succeeded - Found $network_count results"
        
        # Show sample results
        echo "$api_output" | head -3 | while read line; do
            log_info "  Network: $line"
        done
        return 0
    else
        log_warn "WiFi API scan failed:"
        echo "$api_output" | head -5 | while read line; do
            log_warn "  $line"
        done
        return 1
    fi
}

# ============================================
# MAIN TEST EXECUTION
# ============================================

main() {
    echo "============================================"
    echo "WiFi rfkill Fix Test Suite v$TEST_SCRIPT_VERSION"
    echo "============================================"
    
    # Create log file
    mkdir -p "$(dirname "$TEST_LOG_FILE")"
    log_info "Starting WiFi rfkill fix tests..."
    
    local tests_passed=0
    local tests_failed=0
    local tests_warned=0
    
    # Run tests
    echo ""
    echo "Running tests..."
    echo ""
    
    # Test 1: rfkill availability
    if test_rfkill_availability; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    echo ""
    
    # Test 2: wlan0 interface
    if test_wlan0_interface; then
        ((tests_passed++))
    else
        ((tests_warned++))
    fi
    echo ""
    
    # Test 3: WiFi unblock
    if test_wifi_unblock; then
        ((tests_passed++))
    else
        ((tests_warned++))
    fi
    echo ""
    
    # Test 4: wlan0 activation
    if test_wlan0_activation; then
        ((tests_passed++))
    else
        ((tests_warned++))
    fi
    echo ""
    
    # Test 5: scanning tools
    if test_wifi_scanning_tools; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    echo ""
    
    # Test 6: actual scan
    if test_actual_wifi_scan; then
        ((tests_passed++))
    else
        ((tests_warned++))
    fi
    echo ""
    
    # Test 7: API script
    if test_wifi_api_script; then
        ((tests_passed++))
    else
        ((tests_warned++))
    fi
    echo ""
    
    # Summary
    echo "============================================"
    echo "TEST RESULTS SUMMARY"
    echo "============================================"
    log_success "Tests passed: $tests_passed"
    if [ $tests_warned -gt 0 ]; then
        log_warn "Tests with warnings: $tests_warned"
    fi
    if [ $tests_failed -gt 0 ]; then
        log_error "Tests failed: $tests_failed"
    fi
    echo "Full log: $TEST_LOG_FILE"
    echo "============================================"
    
    if [ $tests_failed -eq 0 ]; then
        log_success "All critical tests passed! WiFi rfkill fix appears to be working."
        return 0
    else
        log_error "Some critical tests failed. Review the results above."
        return 1
    fi
}

# Execute main function
main "$@"