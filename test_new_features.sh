#!/bin/bash

# ============================================
# Test Script for New Gateway Features
# ============================================
# Tests the new functionality added to install_gateway_v10.sh

set -e

# Configuration
LOG_FILE="/tmp/gateway_new_features_test_$(date +%Y%m%d_%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_test() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    ((TESTS_TOTAL++))
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC} $test_name"
        ((TESTS_PASSED++))
        echo "[$timestamp] [PASS] $test_name: $details" >> "$LOG_FILE"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}❌ FAIL${NC} $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${RED}└─${NC} $details"
        fi
        ((TESTS_FAILED++))
        echo "[$timestamp] [FAIL] $test_name: $details" >> "$LOG_FILE"
    else
        echo -e "${YELLOW}⚠️  WARN${NC} $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${YELLOW}└─${NC} $details"
        fi
        echo "[$timestamp] [WARN] $test_name: $details" >> "$LOG_FILE"
    fi
}

# Source the functions from the main script for testing
source_script_functions() {
    # Extract functions from the main script for testing
    # This allows us to test individual functions without running the whole script
    
    # Create a temporary file with just the functions
    local temp_functions="/tmp/gateway_functions.sh"
    
    # Extract functions and variables from the main script
    awk '
    /^# Variables de configuración/,/^ETH_INTERFACE="eth0"/ { print }
    /^# Colores para output/,/^NC=/ { print }
    /^log_message\(\)/,/^}$/ { print }
    /^log_info\(\)/,/^}$/ { print }
    /^log_warn\(\)/,/^}$/ { print }
    /^log_error\(\)/,/^}$/ { print }
    /^log_success\(\)/,/^}$/ { print }
    /^cleanup_network_configuration\(\)/,/^}$/ { print }
    /^prompt_building_identification\(\)/,/^}$/ { print }
    /^setup_access_point\(\)/,/^}$/ { print }
    /^install_and_configure_tailscale\(\)/,/^}$/ { print }
    ' install_gateway_v10.sh > "$temp_functions"
    
    # Source the functions
    source "$temp_functions"
    
    return 0
}

# Test function extraction and sourcing
test_function_extraction() {
    echo ""
    echo "=== Testing Function Extraction ==="
    
    if source_script_functions; then
        log_test "Function extraction" "PASS" "Functions extracted successfully"
    else
        log_test "Function extraction" "FAIL" "Could not extract functions"
        return 1
    fi
    
    # Test that key functions exist
    local functions_to_test=(
        "log_info"
        "cleanup_network_configuration"
        "prompt_building_identification"
        "setup_access_point"
        "install_and_configure_tailscale"
    )
    
    for func in "${functions_to_test[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            log_test "Function $func exists" "PASS" "Function is defined"
        else
            log_test "Function $func exists" "FAIL" "Function not found"
        fi
    done
}

# Test new dependencies
test_new_dependencies() {
    echo ""
    echo "=== Testing New Dependencies ==="
    
    # Check if the script includes new dependencies
    local new_deps=("hostapd" "dnsmasq" "iptables")
    
    for dep in "${new_deps[@]}"; do
        if grep -q "\"$dep\"" install_gateway_v10.sh; then
            log_test "Dependency $dep included" "PASS" "Dependency found in script"
        else
            log_test "Dependency $dep included" "FAIL" "Dependency not found"
        fi
    done
}

# Test script version update
test_version_update() {
    echo ""
    echo "=== Testing Version Update ==="
    
    if grep -q "SCRIPT_VERSION=\"10.3\"" install_gateway_v10.sh; then
        log_test "Version updated to 10.3" "PASS" "Script version is current"
    else
        log_test "Version updated to 10.3" "FAIL" "Script version not updated"
    fi
}

# Test main function structure
test_main_function_structure() {
    echo ""
    echo "=== Testing Main Function Structure ==="
    
    # Check that new steps are included in main function
    local new_steps=(
        "Identificación del edificio"
        "Instalando Tailscale"
    )
    
    for step in "${new_steps[@]}"; do
        if grep -q "$step" install_gateway_v10.sh; then
            log_test "Main function includes: $step" "PASS" "Step found in main function"
        else
            log_test "Main function includes: $step" "FAIL" "Step not found"
        fi
    done
    
    # Check that steps are in correct order
    if awk '/^main\(\)/,/^}$/' install_gateway_v10.sh | grep -n "PASO" | head -8 | tail -1 | grep -q "PASO 8"; then
        log_test "Main function has 8 steps" "PASS" "Correct number of steps"
    else
        log_test "Main function has 8 steps" "FAIL" "Incorrect number of steps"
    fi
}

# Test Access Point configuration logic
test_access_point_logic() {
    echo ""
    echo "=== Testing Access Point Logic ==="
    
    # Check that AP setup function exists and has correct parameters
    if grep -A 20 "setup_access_point()" install_gateway_v10.sh | grep -q "ControlsegConfig"; then
        log_test "AP SSID configured correctly" "PASS" "SSID: ControlsegConfig"
    else
        log_test "AP SSID configured correctly" "FAIL" "SSID not found or incorrect"
    fi
    
    if grep -A 20 "setup_access_point()" install_gateway_v10.sh | grep -q "Grupo1598"; then
        log_test "AP password configured correctly" "PASS" "Password: Grupo1598"
    else
        log_test "AP password configured correctly" "FAIL" "Password not found or incorrect"
    fi
    
    if grep -A 30 "setup_access_point()" install_gateway_v10.sh | grep -q "192.168.4.100"; then
        log_test "AP IP configured correctly" "PASS" "IP: 192.168.4.100"
    else
        log_test "AP IP configured correctly" "FAIL" "IP not found or incorrect"
    fi
}

# Test Tailscale configuration
test_tailscale_configuration() {
    echo ""
    echo "=== Testing Tailscale Configuration ==="
    
    # Check that correct auth key is used
    if grep -q "tskey-auth-kpNN1bCPr321CNTRL-QnTaeC2BWaCJE5TY9RJEaCDns9BEzpDZb" install_gateway_v10.sh; then
        log_test "Tailscale auth key correct" "PASS" "Auth key matches requirements"
    else
        log_test "Tailscale auth key correct" "FAIL" "Auth key not found or incorrect"
    fi
    
    # Check that hostname is derived from building address
    if grep -A 10 "install_and_configure_tailscale" install_gateway_v10.sh | grep -q "building_address.txt"; then
        log_test "Hostname uses building address" "PASS" "Building address is used for hostname"
    else
        log_test "Hostname uses building address" "FAIL" "Building address not used"
    fi
}

# Test building identification prompt
test_building_identification() {
    echo ""
    echo "=== Testing Building Identification ==="
    
    # Check that function saves to correct file
    if grep -A 20 "prompt_building_identification" install_gateway_v10.sh | grep -q "building_address.txt"; then
        log_test "Building address saved correctly" "PASS" "Saves to building_address.txt"
    else
        log_test "Building address saved correctly" "FAIL" "File path not found"
    fi
    
    # Check that function has proper validation
    if grep -A 30 "prompt_building_identification" install_gateway_v10.sh | grep -q "al menos 3 caracteres"; then
        log_test "Building address validation" "PASS" "Has minimum length validation"
    else
        log_test "Building address validation" "FAIL" "Validation not found"
    fi
}

# Test network cleanup logic
test_network_cleanup() {
    echo ""
    echo "=== Testing Network Cleanup ==="
    
    # Check that cleanup function addresses multiple gateways
    if grep -A 20 "cleanup_network_configuration" install_gateway_v10.sh | grep -q "default gateways"; then
        log_test "Multiple gateway cleanup" "PASS" "Handles multiple default gateways"
    else
        log_test "Multiple gateway cleanup" "FAIL" "Multiple gateway handling not found"
    fi
    
    # Check that cleanup handles multiple IPs
    if grep -A 30 "cleanup_network_configuration" install_gateway_v10.sh | grep -q "Múltiples IPs"; then
        log_test "Multiple IP cleanup" "PASS" "Handles multiple IPs on interface"
    else
        log_test "Multiple IP cleanup" "FAIL" "Multiple IP handling not found"
    fi
}

# Test enhanced WiFi detection
test_enhanced_wifi_detection() {
    echo ""
    echo "=== Testing Enhanced WiFi Detection ==="
    
    # Check that WiFi detection checks for active connections
    if grep -A 15 "check_wifi_configured" install_gateway_v10.sh | grep -q "active_wifi"; then
        log_test "WiFi detection checks active connections" "PASS" "Checks for active WiFi connections"
    else
        log_test "WiFi detection checks active connections" "FAIL" "Active connection check not found"
    fi
    
    # Check that it verifies IP assignment
    if grep -A 20 "check_wifi_configured" install_gateway_v10.sh | grep -q "wlan_ip"; then
        log_test "WiFi detection checks IP assignment" "PASS" "Verifies IP is assigned to wlan0"
    else
        log_test "WiFi detection checks IP assignment" "FAIL" "IP assignment check not found"
    fi
}

# Test script integration
test_script_integration() {
    echo ""
    echo "=== Testing Script Integration ==="
    
    # Test that script runs without syntax errors
    if bash -n install_gateway_v10.sh; then
        log_test "Script syntax validation" "PASS" "No syntax errors found"
    else
        log_test "Script syntax validation" "FAIL" "Syntax errors detected"
    fi
    
    # Test that all new functions are called in main
    local main_content=$(awk '/^main\(\)/,/^}$/' install_gateway_v10.sh)
    
    if echo "$main_content" | grep -q "prompt_building_identification"; then
        log_test "Building identification called in main" "PASS" "Function is called"
    else
        log_test "Building identification called in main" "FAIL" "Function not called"
    fi
    
    if echo "$main_content" | grep -q "install_and_configure_tailscale"; then
        log_test "Tailscale installation called in main" "PASS" "Function is called"
    else
        log_test "Tailscale installation called in main" "FAIL" "Function not called"
    fi
}

# Main function
main() {
    echo "============================================"
    echo "Gateway New Features Test Suite"
    echo "============================================"
    echo "Test started: $(date)"
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Initialize log file
    echo "Gateway New Features Test Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "======================================" >> "$LOG_FILE"
    
    # Run all test suites
    test_function_extraction
    test_new_dependencies
    test_version_update
    test_main_function_structure
    test_access_point_logic
    test_tailscale_configuration
    test_building_identification
    test_network_cleanup
    test_enhanced_wifi_detection
    test_script_integration
    
    # Summary
    echo ""
    echo "============================================"
    echo "TEST SUMMARY"
    echo "============================================"
    echo "Total tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Warnings: ${YELLOW}$((TESTS_TOTAL - TESTS_PASSED - TESTS_FAILED))${NC}"
    echo ""
    
    local success_rate=0
    if [ "$TESTS_TOTAL" -gt 0 ]; then
        success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
    fi
    
    echo "Success rate: $success_rate%"
    echo "Log file: $LOG_FILE"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
        echo "New gateway features are ready for deployment"
        exit 0
    else
        echo -e "${RED}❌ SOME TESTS FAILED${NC}"
        echo "Please review the failures before deployment"
        exit 1
    fi
}

# Check if running from correct directory
if [ ! -f "install_gateway_v10.sh" ]; then
    echo "Error: Please run this test from the gateway repository root directory"
    exit 1
fi

# Run main function
main "$@"