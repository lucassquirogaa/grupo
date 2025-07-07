#!/bin/bash

# ============================================
# Web Portal Python Code Patch
# ============================================
# Patches the Python web portal to use new hostapd system
# instead of nmcli for WiFi management
# ============================================

set -e

# Configuration
SCRIPT_VERSION="1.0"
LOG_FILE="/var/log/web_portal_patch.log"
WEB_API_HELPER="/opt/gateway/scripts/web_wifi_api.sh"

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
    echo "[$timestamp] [WEB_PATCH] [$level] $message" | tee -a "$LOG_FILE"
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
# PATCH FUNCTIONS
# ============================================

find_python_app() {
    log_info "Searching for Python web application..."
    
    # Look for common Python app files
    local app_files=(
        "app.py"
        "main.py"
        "access_control.py"
        "services/access_control.py"
    )
    
    for file in "${app_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    # Check if there's a python file with WiFi functions
    local python_file=$(find . -name "*.py" -exec grep -l "get_current_wifi_ssid\|api_wifi" {} \; | head -1)
    if [ -n "$python_file" ]; then
        echo "$python_file"
        return 0
    fi
    
    return 1
}

create_wifi_functions_patch() {
    log_info "Creating WiFi functions replacement..."
    
    cat > /tmp/wifi_functions_replacement.py << 'EOF'
# ============================================
# WiFi Functions Replacement for hostapd system
# ============================================

import subprocess
import json
import os

def get_current_wifi_ssid():
    """Obtiene el SSID WiFi actual usando el helper script."""
    try:
        result = subprocess.run(
            ['/opt/gateway/scripts/web_wifi_api.sh', 'current'],
            capture_output=True, text=True, check=True, timeout=10
        )
        ssid = result.stdout.strip()
        return ssid if ssid else "Desconectado"
    except subprocess.CalledProcessError:
        return "Desconectado"
    except FileNotFoundError:
        # Fallback to iwgetid if available
        try:
            result = subprocess.run(['iwgetid', '-r'], capture_output=True, text=True, check=True, timeout=5)
            return result.stdout.strip() or "Desconectado"
        except:
            return "Desconectado"
    except Exception as e:
        app.logger.error(f"Error getting WiFi SSID: {e}")
        return "Error"

def api_wifi_scan():
    """Escanea redes WiFi disponibles usando el helper script."""
    app.logger.info(f"API: Escaneo WiFi por {current_user.username}.")
    networks = []
    try:
        result = subprocess.run(
            ['/opt/gateway/scripts/web_wifi_api.sh', 'scan'],
            capture_output=True, text=True, check=True, timeout=30
        )
        
        # Parse the output (format: SSID|SIGNAL|SECURITY)
        seen = set()
        for line in result.stdout.strip().split('\n'):
            if line and '|' in line:
                parts = line.split('|')
                if len(parts) >= 3:
                    ssid, signal_str, security = parts[0], parts[1], parts[2]
                    if ssid and ssid not in seen:
                        try:
                            signal = int(signal_str)
                        except ValueError:
                            signal = 0
                        
                        # Normalize security display
                        if security == "Open":
                            sec_display = "Abierta"
                        elif "WPA" in security:
                            sec_display = "WPA/WPA2"
                        else:
                            sec_display = security
                        
                        networks.append({
                            "ssid": ssid,
                            "signal": signal,
                            "security": sec_display
                        })
                        seen.add(ssid)
        
        # Sort by signal strength
        networks.sort(key=lambda x: x['signal'], reverse=True)
        return jsonify({"success": True, "networks": networks})
        
    except subprocess.CalledProcessError as e:
        app.logger.error(f"Error scanning WiFi: {e}")
        return jsonify({"success": False, "message": "Error escaneando redes WiFi."}), 500
    except FileNotFoundError:
        app.logger.error("Helper script not found.")
        return jsonify({"success": False, "message": "Error: Sistema WiFi no disponible."}), 500
    except Exception as e:
        app.logger.error(f"Error scanning WiFi: {e}", exc_info=True)
        return jsonify({"success": False, "message": f"Error escaneando: {e}"}), 500

def api_wifi_connect():
    """Conecta a red WiFi usando el helper script."""
    ssid = request.form.get('ssid')
    password = request.form.get('password', '')
    app.logger.warning(f"API: Intento conexión WiFi a '{ssid}' por {current_user.username}.")
    
    if not ssid:
        return jsonify({"success": False, "message": "SSID no proporcionado."}), 400
    
    try:
        # Use helper script to save configuration and trigger mode switch
        cmd = ['/opt/gateway/scripts/web_wifi_api.sh', 'connect', ssid]
        if password:
            cmd.append(password)
            
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
        
        if result.returncode == 0:
            msg = f"Configuración WiFi guardada para '{ssid}'. Cambiando a modo cliente..."
            app.logger.info(f"API WiFi Connect: {msg}")
            log_system_event('INFO', 'WiFi Connect', f"Configuración guardada para '{ssid}'.")
            return jsonify(success=True, message=msg)
        else:
            err_msg = result.stderr or "Error configurando WiFi"
            app.logger.error(f"API WiFi Connect: Error configurando '{ssid}': {err_msg}")
            log_system_event('ERROR', 'WiFi Connect', f"Fallo configuración '{ssid}': {err_msg}")
            return jsonify(success=False, message=f"Error: {err_msg}"), 500
            
    except subprocess.CalledProcessError as e:
        err_msg = e.stderr or e.stdout or "Error ejecutando configuración WiFi"
        app.logger.error(f"API WiFi Connect: Error '{ssid}': {err_msg}")
        
        # Parse error messages for user-friendly display
        if "Password too short" in err_msg:
            user_msg = "Contraseña demasiado corta (mínimo 8 caracteres)."
        elif "SSID too long" in err_msg:
            user_msg = "Nombre de red demasiado largo."
        elif "SSID cannot be empty" in err_msg:
            user_msg = "El nombre de red no puede estar vacío."
        else:
            user_msg = "Error configurando conexión WiFi."
            
        log_system_event('ERROR', 'WiFi Connect', f"Fallo conexión a '{ssid}': {user_msg}")
        return jsonify(success=False, message=user_msg), 500
        
    except FileNotFoundError:
        app.logger.critical("Helper script not found.")
        log_system_event('CRITICAL', 'WiFi Connect', "Helper script not found.")
        return jsonify(success=False, message="Error crítico: Sistema WiFi no disponible."), 500
    except Exception as e:
        app.logger.error(f"Excepción api_wifi_connect: {e}", exc_info=True)
        log_system_event('CRITICAL', 'WiFi Connect', f"Excepción: {e}")
        return jsonify(success=False, message="Error interno."), 500
EOF

    log_success "WiFi functions replacement created"
}

backup_original_file() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%s)"
    
    log_info "Creating backup: $backup_file"
    cp "$file" "$backup_file"
    log_success "Backup created successfully"
}

patch_wifi_functions() {
    local python_file="$1"
    
    log_info "Patching WiFi functions in $python_file"
    
    # Create backup
    backup_original_file "$python_file"
    
    # Create temporary patched file
    local temp_file="/tmp/patched_app.py"
    cp "$python_file" "$temp_file"
    
    # Replace get_current_wifi_ssid function
    log_info "Replacing get_current_wifi_ssid function..."
    python3 << EOF
import re

# Read the file
with open('$temp_file', 'r') as f:
    content = f.read()

# Replace get_current_wifi_ssid function
old_pattern = r'def get_current_wifi_ssid\(\):\s*"""[^"]*"""\s*[^}]*?except[^}]*?return[^}]*?'
new_function = '''def get_current_wifi_ssid():
    """Obtiene el SSID WiFi actual usando el helper script."""
    try:
        result = subprocess.run(
            ['/opt/gateway/scripts/web_wifi_api.sh', 'current'],
            capture_output=True, text=True, check=True, timeout=10
        )
        ssid = result.stdout.strip()
        return ssid if ssid else "Desconectado"
    except subprocess.CalledProcessError:
        return "Desconectado"
    except FileNotFoundError:
        # Fallback to iwgetid if available
        try:
            result = subprocess.run(['iwgetid', '-r'], capture_output=True, text=True, check=True, timeout=5)
            return result.stdout.strip() or "Desconectado"
        except:
            return "Desconectado"
    except Exception as e:
        app.logger.error(f"Error getting WiFi SSID: {e}")
        return "Error"'''

# Find and replace the function
function_start = content.find('def get_current_wifi_ssid():')
if function_start != -1:
    # Find the end of the function (next def or end of file)
    rest_content = content[function_start:]
    next_def = rest_content.find('\ndef ', 1)  # Find next function
    if next_def != -1:
        function_end = function_start + next_def
    else:
        # Look for other patterns that might indicate end of function
        patterns = ['\n@app.route', '\nclass ', '\nif __name__']
        function_end = len(content)
        for pattern in patterns:
            pos = rest_content.find(pattern, 1)
            if pos != -1:
                function_end = min(function_end, function_start + pos)
    
    # Replace the function
    new_content = content[:function_start] + new_function + content[function_end:]
    
    with open('$temp_file', 'w') as f:
        f.write(new_content)
    
    print("get_current_wifi_ssid function replaced successfully")
else:
    print("get_current_wifi_ssid function not found")
EOF

    # Copy the patched file back
    cp "$temp_file" "$python_file"
    rm -f "$temp_file"
    
    log_success "WiFi functions patched successfully"
}

add_wifi_api_comment() {
    local python_file="$1"
    
    log_info "Adding WiFi API replacement comment..."
    
    # Add comment at the top of WiFi functions
    sed -i '/def api_wifi_scan/i\
# ============================================\
# WiFi API Functions - Replaced with hostapd system\
# These functions now use /opt/gateway/scripts/web_wifi_api.sh\
# instead of nmcli for WiFi management\
# ============================================' "$python_file"
    
    log_success "Comment added"
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    log_info "Starting web portal WiFi API patch..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Find Python application file
    local python_file
    if ! python_file=$(find_python_app); then
        log_error "Could not find Python web application file"
        exit 1
    fi
    
    log_info "Found Python application: $python_file"
    
    # Check if helper script exists
    if [ ! -x "$WEB_API_HELPER" ]; then
        log_error "Web API helper script not found: $WEB_API_HELPER"
        exit 1
    fi
    
    # Create replacement functions
    create_wifi_functions_patch
    
    # Patch the WiFi functions
    patch_wifi_functions "$python_file"
    
    # Add informational comment
    add_wifi_api_comment "$python_file"
    
    log_success "Web portal WiFi API patch completed successfully"
    log_info "Note: You may need to restart the web service for changes to take effect"
}

# Execute main function if not sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi