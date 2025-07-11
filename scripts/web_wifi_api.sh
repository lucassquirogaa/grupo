#!/bin/bash

# ============================================
# Web Portal WiFi API Helper
# ============================================
# Helper script for web portal to manage WiFi without nmcli
# Provides compatibility layer for existing portal API
# ============================================

set -e

# Configuration
CONFIG_DIR="/opt/gateway"
WIFI_CONFIG_SCRIPT="$CONFIG_DIR/scripts/wifi_config_manager.sh"
WIFI_MONITOR_SCRIPT="$CONFIG_DIR/scripts/wifi_mode_monitor.sh"
LOG_FILE="/var/log/web_wifi_api.log"

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
    echo "[$timestamp] [WEB_WIFI_API] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

log_success() {
    log_message "SUCCESS" "$1"
}

# ============================================
# WIFI FUNCTIONS
# ============================================

scan_wifi_networks() {
    log_info "Scanning WiFi networks..."
    
    # Paso 1: Verificar que wlan0 existe
    if ! ip link show wlan0 >/dev/null 2>&1; then
        log_error "Interfaz wlan0 no encontrada - no se puede escanear WiFi"
        log_error "Ejecute 'ip link show' para ver interfaces disponibles"
        log_error "Verifique que el hardware WiFi esté conectado y funcionando"
        return 1
    fi
    
    # Paso 2: Verificar estado de rfkill
    if command -v rfkill >/dev/null 2>&1; then
        local wifi_blocked=$(rfkill list wifi | grep -c "blocked: yes" || echo "0")
        if [ "$wifi_blocked" -gt 0 ]; then
            log_warn "WiFi está bloqueado por rfkill, intentando desbloquear..."
            rfkill unblock wifi 2>/dev/null || {
                log_error "No se pudo desbloquear WiFi con rfkill"
                log_error "Ejecute manualmente: sudo rfkill unblock wifi"
                return 1
            }
            log_info "WiFi desbloqueado exitosamente"
        fi
    fi
    
    # Paso 3: Verificar que wlan0 está activo
    local wlan_state=$(ip link show wlan0 | grep -o "state [A-Z]*" | cut -d' ' -f2 2>/dev/null || echo "DOWN")
    if [ "$wlan_state" != "UP" ] && [ "$wlan_state" != "UNKNOWN" ]; then
        log_info "Activando interfaz wlan0..."
        ip link set wlan0 up 2>/dev/null || {
            log_error "No se pudo activar wlan0"
            log_error "Ejecute manualmente: sudo ip link set wlan0 up"
            return 1
        }
        # Esperar un momento para que la interfaz se active
        sleep 2
    fi
    
    # Paso 4: Proceder con el escaneo
    # Use iwlist or iw for scanning
    if command -v iwlist >/dev/null 2>&1; then
        log_info "Ejecutando escaneo WiFi con iwlist..."
        # Enhanced iwlist scan with better parsing
        iwlist wlan0 scan 2>/dev/null | awk '
        /Cell [0-9]/ {
            if (ssid != "" && essid != "") {
                gsub(/^"/, "", essid)
                gsub(/"$/, "", essid)
                if (essid != "" && essid !~ /^\\x00/) {
                    printf "%s|%s|%s\n", essid, signal, security
                }
            }
            ssid = ""
            signal = "0"
            security = "Open"
        }
        /ESSID:/ {
            essid = $0
            gsub(/.*ESSID:/, "", essid)
            gsub(/^"/, "", essid)
            gsub(/"$/, "", essid)
        }
        /Quality=/ {
            split($0, arr, "=")
            if (length(arr) >= 2) {
                split(arr[2], qual, "/")
                if (length(qual) >= 2) {
                    signal = int((qual[1] / qual[2]) * 100)
                }
            }
        }
        /Signal level=/ {
            gsub(/.*Signal level=/, "", $0)
            gsub(/ dBm.*/, "", $0)
            signal_dbm = $0
            # Convert dBm to percentage (rough approximation)
            if (signal_dbm >= -50) signal = 100
            else if (signal_dbm >= -60) signal = 80
            else if (signal_dbm >= -70) signal = 60
            else if (signal_dbm >= -80) signal = 40
            else signal = 20
        }
        /Encryption key:on/ {
            security = "WPA/WPA2"
        }
        /WPA Version/ {
            security = "WPA/WPA2"
        }
        /WPA2 Version/ {
            security = "WPA2"
        }
        END {
            if (essid != "" && essid !~ /^\\x00/) {
                gsub(/^"/, "", essid)
                gsub(/"$/, "", essid)
                printf "%s|%s|%s\n", essid, signal, security
            }
        }' | sort -t'|' -k2,2nr | head -20
        
        # Verificar si se encontraron redes
        local scan_result=$(iwlist wlan0 scan 2>/dev/null | awk '
        /Cell [0-9]/ {
            if (ssid != "" && essid != "") {
                gsub(/^"/, "", essid)
                gsub(/"$/, "", essid)
                if (essid != "" && essid !~ /^\\x00/) {
                    printf "%s|%s|%s\n", essid, signal, security
                }
            }
            ssid = ""
            signal = "0"
            security = "Open"
        }
        /ESSID:/ {
            essid = $0
            gsub(/.*ESSID:/, "", essid)
            gsub(/^"/, "", essid)
            gsub(/"$/, "", essid)
        }
        /Quality=/ {
            split($0, arr, "=")
            if (length(arr) >= 2) {
                split(arr[2], qual, "/")
                if (length(qual) >= 2) {
                    signal = int((qual[1] / qual[2]) * 100)
                }
            }
        }
        /Signal level=/ {
            gsub(/.*Signal level=/, "", $0)
            gsub(/ dBm.*/, "", $0)
            signal_dbm = $0
            # Convert dBm to percentage (rough approximation)
            if (signal_dbm >= -50) signal = 100
            else if (signal_dbm >= -60) signal = 80
            else if (signal_dbm >= -70) signal = 60
            else if (signal_dbm >= -80) signal = 40
            else signal = 20
        }
        /Encryption key:on/ {
            security = "WPA/WPA2"
        }
        /WPA Version/ {
            security = "WPA/WPA2"
        }
        /WPA2 Version/ {
            security = "WPA2"
        }
        END {
            if (essid != "" && essid !~ /^\\x00/) {
                gsub(/^"/, "", essid)
                gsub(/"$/, "", essid)
                printf "%s|%s|%s\n", essid, signal, security
            }
        }' | sort -t'|' -k2,2nr | head -20)
        
        if [ -z "$scan_result" ]; then
            log_warn "No se encontraron redes WiFi"
            log_warn "Posibles causas:"
            log_warn "  - No hay redes WiFi en el área"
            log_warn "  - Interfaz WiFi aún inicializándose"
            log_warn "  - Problemas de hardware WiFi"
            return 1
        else
            echo "$scan_result"
            log_info "Escaneo completado exitosamente"
            return 0
        fi
    else
        log_error "No WiFi scanning tool available"
        log_error "Instale wireless-tools: apt-get install wireless-tools"
        return 1
    fi
}

connect_to_wifi() {
    local ssid="$1"
    local password="$2"
    
    log_info "Connecting to WiFi: $ssid"
    
    # Validate inputs
    if [ -z "$ssid" ]; then
        log_error "SSID is required"
        return 1
    fi
    
    # Save WiFi configuration
    if [ -x "$WIFI_CONFIG_SCRIPT" ]; then
        if [ -n "$password" ]; then
            "$WIFI_CONFIG_SCRIPT" save "$ssid" "$password" "WPA2"
        else
            "$WIFI_CONFIG_SCRIPT" save "$ssid"
        fi
        
        if [ $? -eq 0 ]; then
            log_success "WiFi configuration saved"
            
            # Trigger mode monitor to check and switch
            if [ -x "$WIFI_MONITOR_SCRIPT" ]; then
                log_info "Triggering WiFi mode check..."
                "$WIFI_MONITOR_SCRIPT" once &
            fi
            
            return 0
        else
            log_error "Failed to save WiFi configuration"
            return 1
        fi
    else
        log_error "WiFi configuration script not found"
        return 1
    fi
}

get_current_wifi_ssid() {
    # Check if in client mode and connected
    if [ -f "$CONFIG_DIR/current_wifi_mode" ]; then
        local mode=$(cat "$CONFIG_DIR/current_wifi_mode")
        if [ "$mode" = "client" ]; then
            # Get SSID from wpa_cli if available
            if command -v wpa_cli >/dev/null 2>&1; then
                local ssid=$(wpa_cli -i wlan0 status 2>/dev/null | grep "^ssid=" | cut -d'=' -f2)
                if [ -n "$ssid" ]; then
                    echo "$ssid"
                    return 0
                fi
            fi
        fi
    fi
    
    # Check if we're in AP mode
    if systemctl is-active --quiet hostapd; then
        echo "ControlsegConfig"
        return 0
    fi
    
    echo "Desconectado"
    return 1
}

disconnect_wifi() {
    log_info "Disconnecting from WiFi..."
    
    # Remove WiFi configuration
    if [ -x "$WIFI_CONFIG_SCRIPT" ]; then
        "$WIFI_CONFIG_SCRIPT" remove
        
        # Trigger mode monitor to switch back to AP
        if [ -x "$WIFI_MONITOR_SCRIPT" ]; then
            log_info "Triggering mode switch to AP..."
            "$WIFI_MONITOR_SCRIPT" once &
        fi
        
        log_success "WiFi disconnected"
        return 0
    else
        log_error "WiFi configuration script not found"
        return 1
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    local command="$1"
    
    case "$command" in
        "scan")
            scan_wifi_networks
            ;;
        
        "connect")
            local ssid="$2"
            local password="$3"
            connect_to_wifi "$ssid" "$password"
            ;;
        
        "current")
            get_current_wifi_ssid
            ;;
        
        "disconnect")
            disconnect_wifi
            ;;
        
        *)
            echo "Usage: $0 {scan|connect|current|disconnect}"
            echo ""
            echo "Commands:"
            echo "  scan                    - Scan for available WiFi networks"
            echo "  connect <ssid> [pass]   - Connect to WiFi network"
            echo "  current                 - Get current WiFi SSID"
            echo "  disconnect              - Disconnect from WiFi"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"