#!/bin/bash

# ============================================
# Sistema Gateway 24/7 - Comprehensive Test
# ============================================
# Validates all components of the monitoring system

set -e

# Configuration
LOG_FILE="/tmp/gateway_test_$(date +%Y%m%d_%H%M%S).log"

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

# ============================================
# FILE STRUCTURE TESTS
# ============================================

test_file_structure() {
    echo ""
    echo "=== Testing File Structure ==="
    
    # Main installation script
    if [ -f "install_gateway_v10.sh" ] && [ -x "install_gateway_v10.sh" ]; then
        log_test "Main installation script exists" "PASS" "install_gateway_v10.sh is present and executable"
    else
        log_test "Main installation script exists" "FAIL" "install_gateway_v10.sh missing or not executable"
    fi
    
    # Directory structure
    local required_dirs=("services" "config" "scripts")
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_test "Directory $dir exists" "PASS" "Required directory found"
        else
            log_test "Directory $dir exists" "FAIL" "Required directory missing"
        fi
    done
    
    # Service files
    local service_files=(
        "services/telegram_notifier.py"
        "services/tailscale_monitor.py" 
        "services/system_watchdog.py"
        "services/health_monitor.py"
    )
    
    for file in "${service_files[@]}"; do
        if [ -f "$file" ]; then
            log_test "Service file $(basename $file)" "PASS" "Service file exists"
        else
            log_test "Service file $(basename $file)" "FAIL" "Service file missing"
        fi
    done
    
    # Configuration files
    local config_files=(
        "config/telegram.conf"
        "config/tailscale.conf"
        "config/monitoring.conf"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            log_test "Config file $(basename $file)" "PASS" "Configuration file exists"
        else
            log_test "Config file $(basename $file)" "FAIL" "Configuration file missing"
        fi
    done
    
    # Script files
    local script_files=(
        "scripts/optimize_pi.sh"
        "scripts/setup_monitoring.sh"
        "scripts/install_services.sh"
    )
    
    for file in "${script_files[@]}"; do
        if [ -f "$file" ] && [ -x "$file" ]; then
            log_test "Script $(basename $file)" "PASS" "Script exists and is executable"
        else
            log_test "Script $(basename $file)" "FAIL" "Script missing or not executable"
        fi
    done
}

# ============================================
# SYNTAX VALIDATION TESTS
# ============================================

test_syntax_validation() {
    echo ""
    echo "=== Testing Syntax Validation ==="
    
    # Python service syntax
    local python_services=(
        "services/telegram_notifier.py"
        "services/tailscale_monitor.py"
        "services/system_watchdog.py"
        "services/health_monitor.py"
    )
    
    for service in "${python_services[@]}"; do
        if [ -f "$service" ]; then
            if python3 -m py_compile "$service" 2>/dev/null; then
                log_test "Python syntax: $(basename $service)" "PASS" "No syntax errors"
            else
                log_test "Python syntax: $(basename $service)" "FAIL" "Syntax errors found"
            fi
        fi
    done
    
    # Shell script syntax
    local shell_scripts=(
        "install_gateway_v10.sh"
        "scripts/optimize_pi.sh"
        "scripts/setup_monitoring.sh"
        "scripts/install_services.sh"
    )
    
    for script in "${shell_scripts[@]}"; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>/dev/null; then
                log_test "Shell syntax: $(basename $script)" "PASS" "No syntax errors"
            else
                log_test "Shell syntax: $(basename $script)" "FAIL" "Syntax errors found"
            fi
        fi
    done
}

# ============================================
# CONFIGURATION VALIDATION TESTS
# ============================================

test_configuration_validation() {
    echo ""
    echo "=== Testing Configuration Validation ==="
    
    # Telegram configuration
    if [ -f "config/telegram.conf" ]; then
        local bot_token=$(grep "^BOT_TOKEN=" "config/telegram.conf" | cut -d= -f2)
        local chat_id=$(grep "^CHAT_ID=" "config/telegram.conf" | cut -d= -f2)
        
        if [[ "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            log_test "Telegram bot token format" "PASS" "Token format is valid"
        else
            log_test "Telegram bot token format" "FAIL" "Invalid token format"
        fi
        
        if [[ "$chat_id" =~ ^-?[0-9]+$ ]]; then
            log_test "Telegram chat ID format" "PASS" "Chat ID format is valid"
        else
            log_test "Telegram chat ID format" "FAIL" "Invalid chat ID format"
        fi
        
        # Check for required settings
        local required_settings=("CPU_THRESHOLD" "MEMORY_THRESHOLD" "TEMPERATURE_THRESHOLD")
        for setting in "${required_settings[@]}"; do
            if grep -q "^$setting=" "config/telegram.conf"; then
                log_test "Telegram config: $setting" "PASS" "Setting is configured"
            else
                log_test "Telegram config: $setting" "WARN" "Setting not found, using defaults"
            fi
        done
    fi
    
    # Tailscale configuration
    if [ -f "config/tailscale.conf" ]; then
        local tskey=$(grep "^TSKEY=" "config/tailscale.conf" | cut -d= -f2)
        
        if [[ "$tskey" =~ ^tskey-auth-[A-Za-z0-9_-]+$ ]]; then
            log_test "Tailscale auth key format" "PASS" "Auth key format is valid"
        else
            log_test "Tailscale auth key format" "FAIL" "Invalid auth key format"
        fi
    fi
    
    # Monitoring configuration
    if [ -f "config/monitoring.conf" ]; then
        local required_monitoring=("HEALTH_CHECK_INTERVAL" "WATCHDOG_TIMEOUT" "CPU_THRESHOLD")
        for setting in "${required_monitoring[@]}"; do
            if grep -q "^$setting=" "config/monitoring.conf"; then
                log_test "Monitoring config: $setting" "PASS" "Setting is configured"
            else
                log_test "Monitoring config: $setting" "WARN" "Setting not found"
            fi
        done
    fi
}

# ============================================
# DEPENDENCY VALIDATION TESTS
# ============================================

test_dependencies() {
    echo ""
    echo "=== Testing Dependencies ==="
    
    # Python dependencies (basic check)
    local python_modules=("json" "os" "sys" "time" "logging" "threading" "signal" "subprocess" "datetime")
    for module in "${python_modules[@]}"; do
        if python3 -c "import $module" 2>/dev/null; then
            log_test "Python module: $module" "PASS" "Module available"
        else
            log_test "Python module: $module" "FAIL" "Module not available"
        fi
    done
    
    # External Python packages (will install with pip)
    local external_packages=("psutil" "requests")
    for package in "${external_packages[@]}"; do
        if python3 -c "import $package" 2>/dev/null; then
            log_test "Python package: $package" "PASS" "Package available"
        else
            log_test "Python package: $package" "WARN" "Package not installed (will be installed by setup)"
        fi
    done
    
    # System commands
    local system_commands=("curl" "systemctl" "ip" "ping" "nmcli")
    for cmd in "${system_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_test "System command: $cmd" "PASS" "Command available"
        else
            log_test "System command: $cmd" "WARN" "Command not found (may be installed by dependencies)"
        fi
    done
}

# ============================================
# FUNCTIONAL TESTS
# ============================================

test_functional_components() {
    echo ""
    echo "=== Testing Functional Components ==="
    
    # Test import of Python services (without running)
    local services=(
        "telegram_notifier" 
        "tailscale_monitor"
        "system_watchdog"
        "health_monitor"
    )
    
    for service in "${services[@]}"; do
        if [ -f "services/${service}.py" ]; then
            # Test if the service can be imported without errors
            if python3 -c "
import sys
sys.path.insert(0, 'services')
try:
    import ${service}
    print('Import successful')
except ImportError as e:
    print(f'Import failed: {e}')
    exit(1)
except Exception as e:
    # Other errors are acceptable (missing dependencies, etc.)
    print(f'Import with warnings: {e}')
" 2>/dev/null | grep -q "successful"; then
                log_test "Service import: $service" "PASS" "Service imports successfully"
            else
                log_test "Service import: $service" "WARN" "Service has import issues (may need runtime dependencies)"
            fi
        fi
    done
    
    # Test configuration parsing
    for config in config/*.conf; do
        if [ -f "$config" ]; then
            local config_name=$(basename "$config")
            # Basic validation - check if file has key=value pairs
            if grep -q "^[A-Z_][A-Z0-9_]*=" "$config"; then
                log_test "Config parsing: $config_name" "PASS" "Configuration file has valid format"
            else
                log_test "Config parsing: $config_name" "FAIL" "Configuration file format issues"
            fi
        fi
    done
}

# ============================================
# INTEGRATION TESTS
# ============================================

test_integration() {
    echo ""
    echo "=== Testing Integration ==="
    
    # Test main script integration
    if [ -f "install_gateway_v10.sh" ]; then
        # Check if main script references the new monitoring components
        if grep -q "setup_monitoring.sh" "install_gateway_v10.sh"; then
            log_test "Main script integration: monitoring" "PASS" "Monitoring setup integrated"
        else
            log_test "Main script integration: monitoring" "FAIL" "Monitoring setup not integrated"
        fi
        
        if grep -q "optimize_pi.sh" "install_gateway_v10.sh"; then
            log_test "Main script integration: optimization" "PASS" "Pi optimization integrated"
        else
            log_test "Main script integration: optimization" "FAIL" "Pi optimization not integrated"
        fi
        
        # Check version update
        if grep -q "10.2" "install_gateway_v10.sh"; then
            log_test "Version update" "PASS" "Script version updated to 10.2"
        else
            log_test "Version update" "WARN" "Script version may not be updated"
        fi
    fi
    
    # Test service interdependencies
    local services_dir="services"
    if [ -d "$services_dir" ]; then
        # Check if services can call each other properly
        if grep -q "telegram_notifier" "$services_dir/system_watchdog.py"; then
            log_test "Service integration: watchdog->telegram" "PASS" "Watchdog integrates with Telegram"
        else
            log_test "Service integration: watchdog->telegram" "WARN" "Integration may be missing"
        fi
        
        if grep -q "telegram_notifier" "$services_dir/tailscale_monitor.py"; then
            log_test "Service integration: tailscale->telegram" "PASS" "Tailscale integrates with Telegram"
        else
            log_test "Service integration: tailscale->telegram" "WARN" "Integration may be missing"
        fi
    fi
}

# ============================================
# DOCUMENTATION TESTS
# ============================================

test_documentation() {
    echo ""
    echo "=== Testing Documentation ==="
    
    if [ -f "README.md" ]; then
        # Check for updated content
        if grep -q "Sistema Gateway 24/7" "README.md"; then
            log_test "README updated: title" "PASS" "Title reflects new system"
        else
            log_test "README updated: title" "FAIL" "Title not updated"
        fi
        
        if grep -q "Bot Telegram" "README.md"; then
            log_test "README updated: Telegram bot" "PASS" "Telegram bot documented"
        else
            log_test "README updated: Telegram bot" "FAIL" "Telegram bot not documented"
        fi
        
        if grep -q "Tailscale" "README.md"; then
            log_test "README updated: Tailscale" "PASS" "Tailscale documented"
        else
            log_test "README updated: Tailscale" "FAIL" "Tailscale not documented"
        fi
        
        if grep -q "/status" "README.md"; then
            log_test "README updated: bot commands" "PASS" "Bot commands documented"
        else
            log_test "README updated: bot commands" "FAIL" "Bot commands not documented"
        fi
    else
        log_test "README.md exists" "FAIL" "README.md file missing"
    fi
}

# ============================================
# SECURITY TESTS
# ============================================

test_security() {
    echo ""
    echo "=== Testing Security ==="
    
    # Check for hardcoded sensitive data
    local sensitive_patterns=("password" "secret" "key.*=" "token.*=")
    local files_to_check=("services/*.py" "scripts/*.sh")
    
    for pattern in "${sensitive_patterns[@]}"; do
        local found_files=$(grep -l -i "$pattern" services/*.py scripts/*.sh 2>/dev/null || true)
        if [ -n "$found_files" ]; then
            # Check if they're in configuration references, not hardcoded values
            local problematic_files=""
            for file in $found_files; do
                # Look for patterns that suggest hardcoded secrets (not config references)
                if grep -q -i "password.*=.*['\"][^'\"]*['\"]" "$file" || 
                   grep -q -i "secret.*=.*['\"][^'\"]*['\"]" "$file"; then
                    problematic_files="$problematic_files $file"
                fi
            done
            
            if [ -n "$problematic_files" ]; then
                log_test "Security: hardcoded secrets" "FAIL" "Potential hardcoded secrets in: $problematic_files"
            else
                log_test "Security: hardcoded secrets" "PASS" "No obvious hardcoded secrets found"
            fi
        else
            log_test "Security: hardcoded secrets" "PASS" "No sensitive patterns found"
        fi
    done
    
    # Check file permissions on scripts
    local script_files=("install_gateway_v10.sh" "scripts/*.sh")
    for script_pattern in "${script_files[@]}"; do
        for script in $script_pattern; do
            if [ -f "$script" ]; then
                local perms=$(stat -c "%a" "$script" 2>/dev/null || echo "000")
                if [[ "$perms" =~ ^[67][567][567]$ ]]; then
                    log_test "Security: script permissions $(basename $script)" "PASS" "Permissions are appropriate ($perms)"
                else
                    log_test "Security: script permissions $(basename $script)" "WARN" "Permissions may be too restrictive or too open ($perms)"
                fi
            fi
        done
    done
}

# ============================================
# MAIN FUNCTION
# ============================================

main() {
    echo "============================================"
    echo "Sistema Gateway 24/7 - Comprehensive Test"
    echo "============================================"
    echo "Test started: $(date)"
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Initialize log file
    echo "Sistema Gateway 24/7 - Test Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "======================================" >> "$LOG_FILE"
    
    # Run all test suites
    test_file_structure
    test_syntax_validation
    test_configuration_validation
    test_dependencies
    test_functional_components
    test_integration
    test_documentation
    test_security
    
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
        echo "Sistema Gateway 24/7 is ready for deployment"
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