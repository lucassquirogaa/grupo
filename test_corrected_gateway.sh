#!/bin/bash

# ============================================
# TEST SCRIPT FOR CORRECTED GATEWAY INSTALLATION
# ============================================
# Tests the corrected installation script for safe network configuration
# Validates that network changes are deferred and user prompts are present
# ============================================

# set -e  # Disabled to continue testing on failures

# Test configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/tmp/corrected_gateway_test.log"
INSTALL_SCRIPT="./install_raspberry_gateway.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# ============================================
# TEST HELPER FUNCTIONS
# ============================================

log_test() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [TEST] $message" | tee -a "$LOG_FILE"
}

test_passed() {
    local test_name="$1"
    local details="$2"
    echo -e "${GREEN}✓${NC} $test_name"
    [ -n "$details" ] && echo "  $details"
    ((TESTS_PASSED++))
    ((TOTAL_TESTS++))
    log_test "PASSED: $test_name - $details"
}

test_failed() {
    local test_name="$1"
    local details="$2"
    echo -e "${RED}✗${NC} $test_name"
    [ -n "$details" ] && echo "  $details"
    ((TESTS_FAILED++))
    ((TOTAL_TESTS++))
    log_test "FAILED: $test_name - $details"
}

# ============================================
# SPECIFIC TESTS FOR CORRECTED SCRIPT
# ============================================

test_script_exists() {
    if [ -f "$INSTALL_SCRIPT" ]; then
        test_passed "Install script exists" "Found $INSTALL_SCRIPT"
    else
        test_failed "Install script exists" "Not found: $INSTALL_SCRIPT"
    fi
}

test_script_syntax() {
    local syntax_check=$(bash -n "$INSTALL_SCRIPT" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        test_passed "Script syntax validation" "No syntax errors found"
    else
        test_failed "Script syntax validation" "Syntax errors: $syntax_check"
    fi
}

test_deferred_network_functions() {
    local required_functions=(
        "create_network_config_applier"
        "prepare_deferred_network_config"
        "prompt_network_configuration"
        "show_manual_configuration_instructions"
        "display_final_information"
    )
    
    local found_functions=0
    for func in "${required_functions[@]}"; do
        if grep -q "^$func()" "$INSTALL_SCRIPT"; then
            ((found_functions++))
        fi
    done
    
    if [ $found_functions -eq ${#required_functions[@]} ]; then
        test_passed "Deferred network functions" "All $found_functions functions found"
    else
        test_failed "Deferred network functions" "Only $found_functions/${#required_functions[@]} functions found"
    fi
}

test_user_prompt_logic() {
    # Test that user prompts are present
    if grep -q "prompt_network_configuration" "$INSTALL_SCRIPT" && \
       grep -q "Elija una opción" "$INSTALL_SCRIPT" && \
       grep -q "puede cortar la conexión" "$INSTALL_SCRIPT"; then
        test_passed "User prompt for network changes" "Warning and options present"
    else
        test_failed "User prompt for network changes" "Missing user prompts or warnings"
    fi
}

test_deferred_config_preparation() {
    # Test that deferred configuration is prepared
    if grep -q "prepare_deferred_network_config" "$INSTALL_SCRIPT" && \
       grep -q "pending_network_config" "$INSTALL_SCRIPT" && \
       grep -q "network-config-applier.service" "$INSTALL_SCRIPT"; then
        test_passed "Deferred configuration preparation" "Deferred config logic present"
    else
        test_failed "Deferred configuration preparation" "Missing deferred config logic"
    fi
}

test_installation_phase_ordering() {
    # Extract main() function and test the ordering
    local main_function=$(sed -n '/^main() {/,/^}/p' "$INSTALL_SCRIPT")
    
    # Test that dependencies come before network configuration
    local deps_line=$(echo "$main_function" | grep -n "install_system_dependencies" | cut -d: -f1)
    local network_line=$(echo "$main_function" | grep -n "prompt_network_configuration" | cut -d: -f1)
    
    if [ -n "$deps_line" ] && [ -n "$network_line" ] && [ "$deps_line" -lt "$network_line" ]; then
        test_passed "Installation phase ordering" "Dependencies before network config"
    else
        test_failed "Installation phase ordering" "Incorrect ordering of installation phases"
    fi
}

test_no_immediate_network_services() {
    # Test that network-modifying services are not enabled immediately
    if grep -q "systemctl enable.*revert.*# Note:" "$INSTALL_SCRIPT" || \
       grep -q "DO NOT ENABLE YET" "$INSTALL_SCRIPT"; then
        test_passed "No immediate network service enabling" "Network services properly deferred"
    else
        test_failed "No immediate network service enabling" "Network services may be enabled too early"
    fi
}

test_comprehensive_backup() {
    # Test that backup is comprehensive with logging
    if grep -q "backup_existing_configs" "$INSTALL_SCRIPT" && \
       grep -q "restore_network.sh" "$INSTALL_SCRIPT" && \
       grep -q "backup_summary.txt" "$INSTALL_SCRIPT"; then
        test_passed "Comprehensive backup system" "Backup with restore script and summary"
    else
        test_failed "Comprehensive backup system" "Missing comprehensive backup features"
    fi
}

test_tailscale_before_network_changes() {
    # Test that Tailscale is configured before network changes
    local main_function=$(sed -n '/^main() {/,/^}/p' "$INSTALL_SCRIPT")
    
    local tailscale_line=$(echo "$main_function" | grep -n "configure_tailscale" | cut -d: -f1)
    local network_line=$(echo "$main_function" | grep -n "FASE 2" | cut -d: -f1)
    
    if [ -n "$tailscale_line" ] && [ -n "$network_line" ] && [ "$tailscale_line" -lt "$network_line" ]; then
        test_passed "Tailscale before network changes" "Tailscale configured while internet available"
    else
        test_failed "Tailscale before network changes" "Tailscale may be configured after network changes"
    fi
}

test_manual_configuration_instructions() {
    # Test that manual configuration instructions are present
    if grep -q "show_manual_configuration_instructions" "$INSTALL_SCRIPT" && \
       grep -q "INSTRUCCIONES PARA CONFIGURACIÓN MANUAL" "$INSTALL_SCRIPT" && \
       grep -q "apply_network_config.sh" "$INSTALL_SCRIPT"; then
        test_passed "Manual configuration instructions" "Complete instructions provided"
    else
        test_failed "Manual configuration instructions" "Missing or incomplete instructions"
    fi
}

test_network_applier_script_creation() {
    # Test that the network applier script is properly created
    if grep -q "create_network_config_applier" "$INSTALL_SCRIPT" && \
       grep -q "apply_network_config.sh" "$INSTALL_SCRIPT" && \
       grep -q "chmod.*apply_network_config" "$INSTALL_SCRIPT"; then
        test_passed "Network applier script creation" "Script creation and permissions set"
    else
        test_failed "Network applier script creation" "Missing or incomplete applier script creation"
    fi
}

test_three_configuration_options() {
    # Test that all three configuration options are handled
    if grep -q "case.*config_choice" "$INSTALL_SCRIPT" && \
       grep -q "Apply now" "$INSTALL_SCRIPT" && \
       grep -q "Defer to reboot" "$INSTALL_SCRIPT" && \
       grep -q "Manual later" "$INSTALL_SCRIPT"; then
        test_passed "Three configuration options" "All three options (now/reboot/manual) handled"
    else
        test_failed "Three configuration options" "Missing configuration option handling"
    fi
}

test_phase_separation() {
    # Test that phases are clearly separated
    if grep -q "FASE 1.*dependencias" "$INSTALL_SCRIPT" && \
       grep -q "FASE 2.*red" "$INSTALL_SCRIPT" && \
       grep -q "FASE 3.*finalización" "$INSTALL_SCRIPT"; then
        test_passed "Clear phase separation" "Three distinct phases identified"
    else
        test_failed "Clear phase separation" "Missing clear phase separation"
    fi
}

# ============================================
# MAIN TEST EXECUTION
# ============================================

main() {
    echo "============================================"
    echo "Corrected Gateway Installation Test v$SCRIPT_VERSION"
    echo "Testing Safe Deferred Network Configuration"
    echo "============================================"
    echo ""
    
    # Initialize log file
    echo "Test started at $(date)" > "$LOG_FILE"
    
    echo "Testing script existence and syntax..."
    test_script_exists
    test_script_syntax
    
    echo ""
    echo "Testing deferred network configuration features..."
    test_deferred_network_functions
    test_user_prompt_logic
    test_deferred_config_preparation
    test_no_immediate_network_services
    
    echo ""
    echo "Testing installation flow safety..."
    test_installation_phase_ordering
    test_tailscale_before_network_changes
    test_phase_separation
    
    echo ""
    echo "Testing backup and recovery features..."
    test_comprehensive_backup
    
    echo ""
    echo "Testing user experience features..."
    test_manual_configuration_instructions
    test_three_configuration_options
    
    echo ""
    echo "Testing technical implementation..."
    test_network_applier_script_creation
    
    echo ""
    echo "============================================"
    echo "TEST SUMMARY"
    echo "============================================"
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! Corrected installation script is ready.${NC}"
        echo ""
        echo "Key improvements validated:"
        echo "• Dependencies installed before network changes"
        echo "• User confirmation required before network changes"
        echo "• Three configuration options (immediate/deferred/manual)"
        echo "• Comprehensive backup and restore system"
        echo "• Clear phase separation for maximum safety"
        echo "• Tailscale configured while internet is available"
        echo ""
        return 0
    else
        echo -e "${RED}✗ $TESTS_FAILED tests failed. Please review and fix issues.${NC}"
        echo ""
        return 1
    fi
}

# Execute main function
main "$@"