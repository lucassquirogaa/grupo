#!/bin/bash

# ============================================
# Validation Script for Gateway Installation
# ============================================
# Script para validar que todos los componentes del gateway
# estén correctamente instalados y configurados.
# ============================================

# Remove set -e for validation script since we expect some tests to fail
# set -e

VALIDATION_VERSION="1.0"
LOG_FILE="/tmp/gateway_validation.log"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# ============================================
# FUNCIONES DE LOGGING Y UTILIDADES
# ============================================

log_test() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] TEST: $test_name - $status: $details" >> "$LOG_FILE"
    
    ((TESTS_TOTAL++))
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        [ -n "$details" ] && echo "  $details"
        ((TESTS_PASSED++))
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗${NC} $test_name"
        [ -n "$details" ] && echo "  Error: $details"
        ((TESTS_FAILED++))
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $test_name"
        [ -n "$details" ] && echo "  Warning: $details"
    else
        echo -e "${BLUE}ℹ${NC} $test_name"
        [ -n "$details" ] && echo "  Info: $details"
    fi
}

# ============================================
# TESTS DE VALIDACIÓN
# ============================================

test_install_script_exists() {
    if [ -f "install_gateway_v10.sh" ] && [ -x "install_gateway_v10.sh" ]; then
        log_test "Install script exists and is executable" "PASS" "Found install_gateway_v10.sh"
    else
        log_test "Install script exists and is executable" "FAIL" "install_gateway_v10.sh not found or not executable"
    fi
}

test_network_monitor_exists() {
    if [ -f "network_monitor.sh" ] && [ -x "network_monitor.sh" ]; then
        log_test "Network monitor script exists and is executable" "PASS" "Found network_monitor.sh"
    else
        log_test "Network monitor script exists and is executable" "FAIL" "network_monitor.sh not found or not executable"
    fi
}

test_systemd_service_file() {
    if [ -f "network-monitor.service" ]; then
        log_test "Systemd service file exists" "PASS" "Found network-monitor.service"
    else
        log_test "Systemd service file exists" "FAIL" "network-monitor.service not found"
    fi
}

test_flask_app_network_endpoints() {
    if [ -f "pi@raspberrypi~access_control_syste.txt" ]; then
        # Check for new API endpoints
        local endpoints_found=0
        
        if grep -q "/api/system/network-status" "pi@raspberrypi~access_control_syste.txt"; then
            ((endpoints_found++))
        fi
        
        if grep -q "/api/system/network-change" "pi@raspberrypi~access_control_syste.txt"; then
            ((endpoints_found++))
        fi
        
        if grep -q "/api/system/network-force-dhcp" "pi@raspberrypi~access_control_syste.txt"; then
            ((endpoints_found++))
        fi
        
        if [ "$endpoints_found" -eq 3 ]; then
            log_test "Flask app has network endpoints" "PASS" "Found all 3 network API endpoints"
        else
            log_test "Flask app has network endpoints" "FAIL" "Only found $endpoints_found out of 3 network endpoints"
        fi
    else
        log_test "Flask app has network endpoints" "FAIL" "Flask app file not found"
    fi
}

test_script_syntax() {
    echo "Testing script syntax..."
    
    if bash -n "install_gateway_v10.sh" 2>/dev/null; then
        log_test "Install script syntax" "PASS" "No syntax errors in install_gateway_v10.sh"
    else
        log_test "Install script syntax" "FAIL" "Syntax errors found in install_gateway_v10.sh"
    fi
    
    if bash -n "network_monitor.sh" 2>/dev/null; then
        log_test "Network monitor syntax" "PASS" "No syntax errors in network_monitor.sh"
    else
        log_test "Network monitor syntax" "FAIL" "Syntax errors found in network_monitor.sh"
    fi
}

test_required_functions() {
    echo "Testing required functions in scripts..."
    
    # Test install script functions
    local install_functions=(
        "check_wifi_configured"
        "configure_static_ip"
        "configure_dhcp"
        "install_dependencies"
        "setup_python_environment"
    )
    
    local found_functions=0
    for func in "${install_functions[@]}"; do
        if grep -q "^$func()" "install_gateway_v10.sh"; then
            ((found_functions++))
        fi
    done
    
    if [ "$found_functions" -eq "${#install_functions[@]}" ]; then
        log_test "Install script has required functions" "PASS" "Found all $found_functions functions"
    else
        log_test "Install script has required functions" "FAIL" "Only found $found_functions out of ${#install_functions[@]} functions"
    fi
    
    # Test network monitor functions
    local monitor_functions=(
        "get_wifi_status"
        "get_eth_config_method"
        "switch_to_dhcp"
        "monitor_network_changes"
    )
    
    found_functions=0
    for func in "${monitor_functions[@]}"; do
        if grep -q "^$func()" "network_monitor.sh"; then
            ((found_functions++))
        fi
    done
    
    if [ "$found_functions" -eq "${#monitor_functions[@]}" ]; then
        log_test "Network monitor has required functions" "PASS" "Found all $found_functions functions"
    else
        log_test "Network monitor has required functions" "FAIL" "Only found $found_functions out of ${#monitor_functions[@]} functions"
    fi
}

test_network_configuration_values() {
    echo "Testing network configuration values..."
    
    # Check static IP configuration
    if grep -q "STATIC_IP=\"192.168.4.100\"" "install_gateway_v10.sh"; then
        log_test "Static IP configuration" "PASS" "Correct static IP (192.168.4.100) configured"
    else
        log_test "Static IP configuration" "FAIL" "Static IP not set to 192.168.4.100"
    fi
    
    if grep -q "STATIC_GATEWAY=\"192.168.4.1\"" "install_gateway_v10.sh"; then
        log_test "Static gateway configuration" "PASS" "Correct gateway (192.168.4.1) configured"
    else
        log_test "Static gateway configuration" "FAIL" "Gateway not set to 192.168.4.1"
    fi
    
    if grep -q "ETH_INTERFACE=\"eth0\"" "install_gateway_v10.sh"; then
        log_test "Ethernet interface configuration" "PASS" "Correct interface (eth0) configured"
    else
        log_test "Ethernet interface configuration" "FAIL" "Interface not set to eth0"
    fi
}

test_logging_configuration() {
    echo "Testing logging configuration..."
    
    # Check log file paths
    if grep -q "LOG_FILE=\"/var/log/gateway_install.log\"" "install_gateway_v10.sh"; then
        log_test "Install script logging" "PASS" "Log file configured correctly"
    else
        log_test "Install script logging" "FAIL" "Log file not configured"
    fi
    
    if grep -q "LOG_FILE=\"/var/log/network_monitor.log\"" "network_monitor.sh"; then
        log_test "Monitor script logging" "PASS" "Log file configured correctly"
    else
        log_test "Monitor script logging" "FAIL" "Log file not configured"
    fi
}

test_documentation_exists() {
    if [ -f "README.md" ]; then
        # Check for key sections in README
        local sections_found=0
        
        if grep -q "## Instalación" "README.md"; then
            ((sections_found++))
        fi
        
        if grep -q "## Configuración de Red" "README.md"; then
            ((sections_found++))
        fi
        
        if grep -q "## Solución de Problemas" "README.md"; then
            ((sections_found++))
        fi
        
        if [ "$sections_found" -eq 3 ]; then
            log_test "Documentation completeness" "PASS" "README.md has all required sections"
        else
            log_test "Documentation completeness" "WARN" "README.md missing some sections ($sections_found/3)"
        fi
    else
        log_test "Documentation exists" "FAIL" "README.md not found"
    fi
}

test_system_requirements() {
    echo "Testing system requirements..."
    
    # Check for required commands
    local required_commands=("ip" "ping" "curl" "systemctl" "python3")
    local found_commands=0
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ((found_commands++))
        fi
    done
    
    if [ "$found_commands" -eq "${#required_commands[@]}" ]; then
        log_test "System requirements" "PASS" "All required commands available ($found_commands/${#required_commands[@]})"
    else
        log_test "System requirements" "WARN" "Some commands missing ($found_commands/${#required_commands[@]} available)"
    fi
}

# ============================================
# FUNCIÓN PRINCIPAL DE VALIDACIÓN
# ============================================

run_validation() {
    echo "============================================"
    echo "Gateway Installation Validation v$VALIDATION_VERSION"
    echo "============================================"
    echo ""
    
    # Initialize log file
    echo "Starting validation at $(date)" > "$LOG_FILE"
    
    echo "Running validation tests..."
    echo ""
    
    # File existence tests
    test_install_script_exists
    test_network_monitor_exists
    test_systemd_service_file
    
    # Code quality tests
    test_script_syntax
    test_required_functions
    test_flask_app_network_endpoints
    
    # Configuration tests
    test_network_configuration_values
    test_logging_configuration
    
    # Documentation tests
    test_documentation_exists
    
    # System tests
    test_system_requirements
    
    echo ""
    echo "============================================"
    echo "VALIDATION SUMMARY"
    echo "============================================"
    echo "Total tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! Gateway installation package is ready.${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Copy files to target Raspberry Pi"
        echo "2. Run: sudo ./install_gateway_v10.sh"
        echo "3. Configure WiFi via web portal at http://192.168.4.100:8080"
        echo ""
        return 0
    else
        echo -e "${RED}✗ $TESTS_FAILED test(s) failed. Please fix issues before deployment.${NC}"
        echo ""
        echo "Check log file: $LOG_FILE"
        echo ""
        return 1
    fi
}

# ============================================
# FUNCIÓN PRINCIPAL
# ============================================

main() {
    case "${1:-validate}" in
        validate|test)
            run_validation
            ;;
        log)
            if [ -f "$LOG_FILE" ]; then
                cat "$LOG_FILE"
            else
                echo "No log file found at $LOG_FILE"
            fi
            ;;
        clean)
            rm -f "$LOG_FILE"
            echo "Validation log cleaned"
            ;;
        *)
            echo "Usage: $0 {validate|test|log|clean}"
            echo ""
            echo "validate - Run all validation tests (default)"
            echo "test     - Alias for validate"
            echo "log      - Show validation log"
            echo "clean    - Remove validation log"
            exit 1
            ;;
    esac
}

# Ejecutar función principal
main "$@"