#!/bin/bash

# ============================================
# RASPBERRY PI GATEWAY INSTALLATION TEST SCRIPT
# ============================================
# Version: 1.0
# Description: Comprehensive test script for the Raspberry Pi Gateway installation
# Tests: Script syntax, dependencies, configuration, and functionality
# ============================================

# set -e  # Disabled to continue testing on failures

# Test configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/tmp/raspberry_gateway_test.log"
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

test_warning() {
    local test_name="$1"
    local details="$2"
    echo -e "${YELLOW}⚠${NC} $test_name"
    [ -n "$details" ] && echo "  $details"
    log_test "WARNING: $test_name - $details"
}

# ============================================
# TEST FUNCTIONS
# ============================================

test_script_exists() {
    echo "Testing script existence and permissions..."
    
    if [ -f "$INSTALL_SCRIPT" ]; then
        test_passed "Install script exists" "Found $INSTALL_SCRIPT"
    else
        test_failed "Install script exists" "Not found: $INSTALL_SCRIPT"
        return 1
    fi
    
    if [ -x "$INSTALL_SCRIPT" ]; then
        test_passed "Install script is executable" "Permissions OK"
    else
        test_failed "Install script is executable" "Missing execute permission"
        return 1
    fi
}

test_script_syntax() {
    echo "Testing script syntax..."
    
    if bash -n "$INSTALL_SCRIPT" 2>/dev/null; then
        test_passed "Script syntax validation" "No syntax errors found"
    else
        test_failed "Script syntax validation" "Syntax errors detected"
        bash -n "$INSTALL_SCRIPT" 2>&1 | head -5
    fi
}

test_required_functions() {
    echo "Testing required functions in script..."
    
    local required_functions=(
        "log_info"
        "log_error"
        "check_root"
        "install_system_dependencies"
        "setup_python_environment"
        "create_flask_application"
        "create_dhcp_revert_script"
        "configure_static_ip"
        "configure_tailscale"
        "main"
    )
    
    local found_functions=0
    for func in "${required_functions[@]}"; do
        if grep -q "^$func()" "$INSTALL_SCRIPT"; then
            ((found_functions++))
        else
            test_warning "Missing function" "$func not found"
        fi
    done
    
    if [ $found_functions -eq ${#required_functions[@]} ]; then
        test_passed "Required functions check" "All $found_functions functions found"
    else
        test_failed "Required functions check" "Only $found_functions/${#required_functions[@]} functions found"
    fi
}

test_configuration_values() {
    echo "Testing configuration values..."
    
    # Test static IP configuration
    if grep -q "STATIC_IP=\"192\.168\.4\.100\"" "$INSTALL_SCRIPT"; then
        test_passed "Static IP configuration" "Correct IP (192.168.4.100)"
    else
        test_failed "Static IP configuration" "Incorrect or missing static IP"
    fi
    
    # Test gateway configuration
    if grep -q "STATIC_GATEWAY=\"192\.168\.4\.1\"" "$INSTALL_SCRIPT"; then
        test_passed "Gateway configuration" "Correct gateway (192.168.4.1)"
    else
        test_failed "Gateway configuration" "Incorrect or missing gateway"
    fi
    
    # Test web port configuration
    if grep -q "WEB_PORT=\"8080\"" "$INSTALL_SCRIPT"; then
        test_passed "Web port configuration" "Correct port (8080)"
    else
        test_failed "Web port configuration" "Incorrect or missing web port"
    fi
    
    # Test Tailscale auth key
    if grep -q "TAILSCALE_AUTH_KEY=" "$INSTALL_SCRIPT"; then
        test_passed "Tailscale auth key" "Auth key configured"
    else
        test_failed "Tailscale auth key" "Auth key not configured"
    fi
}

test_flask_application_content() {
    echo "Testing Flask application content..."
    
    # Check if Flask app creation function contains required routes
    local flask_content=$(grep -A 1000 "create_flask_application()" "$INSTALL_SCRIPT")
    
    if echo "$flask_content" | grep -q "@app.route('/')"; then
        test_passed "Flask main route" "Root route defined"
    else
        test_failed "Flask main route" "Root route not found"
    fi
    
    if echo "$flask_content" | grep -q "@app.route('/wifi')"; then
        test_passed "Flask WiFi route" "WiFi configuration route defined"
    else
        test_failed "Flask WiFi route" "WiFi route not found"
    fi
    
    if echo "$flask_content" | grep -q "@app.route('/api/status')"; then
        test_passed "Flask API route" "Status API route defined"
    else
        test_failed "Flask API route" "Status API route not found"
    fi
    
    if echo "$flask_content" | grep -q "app.run(host='0.0.0.0', port=8080"; then
        test_passed "Flask host configuration" "Listens on 0.0.0.0:8080"
    else
        test_failed "Flask host configuration" "Incorrect host/port configuration"
    fi
}

test_dhcp_revert_script_content() {
    echo "Testing DHCP revert script content..."
    
    local revert_content=$(grep -A 500 "create_dhcp_revert_script()" "$INSTALL_SCRIPT")
    
    if echo "$revert_content" | grep -q "check_wifi_connection()"; then
        test_passed "DHCP revert WiFi check" "WiFi connectivity check included"
    else
        test_failed "DHCP revert WiFi check" "WiFi check function not found"
    fi
    
    if echo "$revert_content" | grep -q "nmcli connection modify"; then
        test_passed "DHCP revert NetworkManager" "NetworkManager configuration included"
    else
        test_failed "DHCP revert NetworkManager" "NetworkManager commands not found"
    fi
    
    if echo "$revert_content" | grep -q "systemctl disable"; then
        test_passed "DHCP revert service disable" "Service auto-disable included"
    else
        test_failed "DHCP revert service disable" "Service disable not found"
    fi
}

test_systemd_services() {
    echo "Testing systemd service creation..."
    
    local service_content=$(grep -A 100 "create_systemd_services()" "$INSTALL_SCRIPT")
    
    if echo "$service_content" | grep -q "\$SERVICE_NAME"; then
        test_passed "Main service creation" "Main systemd service defined"
    else
        test_failed "Main service creation" "Main service not found"
    fi
    
    if echo "$service_content" | grep -q "\$REVERT_SERVICE_NAME"; then
        test_passed "DHCP revert service creation" "DHCP revert service defined"
    else
        test_failed "DHCP revert service creation" "DHCP revert service not found"
    fi
    
    if echo "$service_content" | grep -q "Type=oneshot"; then
        test_passed "Service configuration" "One-shot service type configured"
    else
        test_failed "Service configuration" "Service type not properly configured"
    fi
}

test_security_considerations() {
    echo "Testing security considerations..."
    
    # Check for proper error handling
    if grep -q "set -e" "$INSTALL_SCRIPT"; then
        test_passed "Error handling" "Script exits on errors"
    else
        test_failed "Error handling" "No error handling configured"
    fi
    
    # Check for root validation
    if grep -q "check_root()" "$INSTALL_SCRIPT"; then
        test_passed "Root check" "Script validates root privileges"
    else
        test_failed "Root check" "No root validation"
    fi
    
    # Check for backup creation
    if grep -q "backup_existing_configs" "$INSTALL_SCRIPT"; then
        test_passed "Configuration backup" "Backup function included"
    else
        test_failed "Configuration backup" "No backup mechanism"
    fi
    
    # Check for systemd security settings
    if grep -q "NoNewPrivileges=true" "$INSTALL_SCRIPT"; then
        test_passed "Systemd security" "Security hardening configured"
    else
        test_failed "Systemd security" "Missing security hardening"
    fi
}

test_no_hostapd_dnsmasq() {
    echo "Testing NO internal AP configuration (as required)..."
    
    # Verify script does NOT install or configure hostapd (excluding comments)
    if ! grep -v "^#" "$INSTALL_SCRIPT" | grep -q "hostapd"; then
        test_passed "No hostapd configuration" "Script correctly avoids internal AP"
    else
        test_failed "No hostapd configuration" "Script contains hostapd references"
    fi
    
    # Verify script does NOT install or configure dnsmasq (excluding comments)
    if ! grep -v "^#" "$INSTALL_SCRIPT" | grep -q "dnsmasq"; then
        test_passed "No dnsmasq configuration" "Script correctly avoids internal DHCP"
    else
        test_failed "No dnsmasq configuration" "Script contains dnsmasq references"
    fi
    
    # Verify script mentions external TP-Link AP usage
    if grep -q "TP-Link" "$INSTALL_SCRIPT"; then
        test_passed "External AP reference" "Script mentions TP-Link external AP"
    else
        test_warning "External AP reference" "No explicit TP-Link reference found"
    fi
}

test_self_contained() {
    echo "Testing self-contained nature..."
    
    # Check that script doesn't source external files (except venv activation)
    local external_sources=$(grep -v "source venv/bin/activate" "$INSTALL_SCRIPT" | grep -c "source.*/" || true)
    if [ "$external_sources" -eq 0 ]; then
        test_passed "No external dependencies" "Script doesn't source external files"
    else
        test_failed "No external dependencies" "Script has external file dependencies"
    fi
    
    # Check that Flask app is embedded
    if grep -q "cat > \"\$CONFIG_DIR/app.py\"" "$INSTALL_SCRIPT"; then
        test_passed "Embedded Flask app" "Flask application is embedded in script"
    else
        test_failed "Embedded Flask app" "Flask application not embedded"
    fi
    
    # Check that DHCP revert script is embedded
    if grep -q "cat > \"\$CONFIG_DIR/revert_to_dhcp.sh\"" "$INSTALL_SCRIPT"; then
        test_passed "Embedded DHCP script" "DHCP revert script is embedded"
    else
        test_failed "Embedded DHCP script" "DHCP revert script not embedded"
    fi
}

test_install_sequence() {
    echo "Testing installation sequence..."
    
    local main_function=$(grep -A 200 "^main()" "$INSTALL_SCRIPT")
    
    # Check that dependencies are installed first
    if echo "$main_function" | grep -B 5 -A 5 "install_system_dependencies" | grep -q "STEP 1"; then
        test_passed "Dependencies first" "Dependencies installed before network config"
    else
        test_failed "Dependencies first" "Installation sequence incorrect"
    fi
    
    # Check that static IP is configured AFTER dependencies
    if echo "$main_function" | grep -B 5 -A 5 "configure_static_ip" | grep -q "STEP 5"; then
        test_passed "Static IP after dependencies" "Static IP configured after dependencies"
    else
        test_failed "Static IP after dependencies" "Static IP timing incorrect"
    fi
    
    # Check that Tailscale is configured before static IP
    local tailscale_line=$(echo "$main_function" | grep -n "configure_tailscale" | cut -d: -f1)
    local static_ip_line=$(echo "$main_function" | grep -n "configure_static_ip" | cut -d: -f1)
    
    if [ -n "$tailscale_line" ] && [ -n "$static_ip_line" ] && [ "$tailscale_line" -lt "$static_ip_line" ]; then
        test_passed "Tailscale before static IP" "Tailscale configured while internet available"
    else
        test_failed "Tailscale before static IP" "Tailscale timing incorrect"
    fi
}

# ============================================
# MAIN TEST EXECUTION
# ============================================

main() {
    echo "============================================"
    echo "Raspberry Pi Gateway Installation Test v$SCRIPT_VERSION"
    echo "============================================"
    echo ""
    
    # Initialize log
    echo "Test started at $(date)" > "$LOG_FILE"
    
    # Run all tests
    test_script_exists
    test_script_syntax
    test_required_functions
    test_configuration_values
    test_flask_application_content
    test_dhcp_revert_script_content
    test_systemd_services
    test_security_considerations
    test_no_hostapd_dnsmasq
    test_self_contained
    test_install_sequence
    
    echo ""
    echo "============================================"
    echo "TEST SUMMARY"
    echo "============================================"
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! Installation script is ready.${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Copy script to target Raspberry Pi"
        echo "2. Run: sudo ./install_raspberry_gateway.sh"
        echo "3. Follow the interactive prompts"
        echo "4. Configure WiFi via web portal at http://192.168.4.100:8080"
        echo ""
        echo "Log file: $LOG_FILE"
        exit 0
    else
        echo -e "${RED}✗ Tests failed. Please fix issues before deployment.${NC}"
        echo "Check log file: $LOG_FILE"
        exit 1
    fi
}

# Run tests
main "$@"