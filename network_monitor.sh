#!/bin/bash

# ============================================
# Network Configuration Monitor
# ============================================
# Script que monitorea cambios en la configuración WiFi y
# automáticamente cambia de IP estática a DHCP cuando se
# configura WiFi exitosamente.
# ============================================

set -e

# Variables de configuración
MONITOR_VERSION="1.0"
LOG_FILE="/var/log/network_monitor.log"
STATIC_IP="192.168.4.100"
ETH_INTERFACE="eth0"
CHECK_INTERVAL=30  # segundos

# Estado anterior (para detectar cambios)
PREVIOUS_WIFI_STATE=""
PREVIOUS_ETH_CONFIG=""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# FUNCIONES DE LOGGING
# ============================================

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
}

log_warn() {
    log_message "WARN" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

log_success() {
    log_message "SUCCESS" "$1"
}

# ============================================
# FUNCIONES DE DETECCIÓN
# ============================================

get_wifi_status() {
    # Retorna el SSID si está conectado, "DISCONNECTED" si no
    if command -v nmcli >/dev/null 2>&1; then
        local active_ssid=$(nmcli -t -f ACTIVE,SSID dev wifi | grep "^yes:" | cut -d: -f2)
        if [ -n "$active_ssid" ]; then
            echo "$active_ssid"
        else
            echo "DISCONNECTED"
        fi
    else
        # Fallback usando iwgetid
        local ssid=$(iwgetid -r 2>/dev/null || echo "")
        if [ -n "$ssid" ]; then
            echo "$ssid"
        else
            echo "DISCONNECTED"
        fi
    fi
}

get_eth_config_method() {
    # Retorna "static" o "dhcp" según la configuración actual
    if command -v nmcli >/dev/null 2>&1; then
        local connection_name=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$ETH_INTERFACE$" | cut -d: -f1)
        if [ -n "$connection_name" ]; then
            local method=$(nmcli -t -f ipv4.method connection show "$connection_name" | cut -d: -f2)
            if [ "$method" = "manual" ]; then
                echo "static"
            else
                echo "dhcp"
            fi
        else
            echo "unknown"
        fi
    else
        # Fallback para sistemas sin NetworkManager
        if grep -q "iface $ETH_INTERFACE inet static" /etc/network/interfaces* 2>/dev/null; then
            echo "static"
        else
            echo "dhcp"
        fi
    fi
}

is_on_tplink_network() {
    # Verifica si estamos en la red TP-Link (192.168.4.x)
    local current_ip=$(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [[ "$current_ip" == 192.168.4.* ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================
# FUNCIONES DE CONFIGURACIÓN
# ============================================

switch_to_dhcp() {
    log_info "Cambiando configuración ethernet a DHCP..."
    
    if command -v nmcli >/dev/null 2>&1; then
        local connection_name=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$ETH_INTERFACE$" | cut -d: -f1)
        if [ -n "$connection_name" ]; then
            nmcli connection modify "$connection_name" \
                ipv4.method auto \
                ipv4.addresses "" \
                ipv4.gateway "" \
                ipv4.dns "" && \
            nmcli connection up "$connection_name" && {
                log_success "Ethernet configurado exitosamente para DHCP"
                return 0
            }
        fi
    fi
    
    log_error "Error configurando DHCP en ethernet"
    return 1
}

notify_web_service() {
    # Notifica al servicio web sobre el cambio de configuración
    local message="$1"
    
    # Intentar notificar vía curl si el servicio está corriendo
    if curl -s "http://localhost:8080/api/system/network-change" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"message\": \"$message\", \"timestamp\": \"$(date -Iseconds)\"}" \
        >/dev/null 2>&1; then
        log_info "Notificación enviada al servicio web"
    else
        log_warn "No se pudo notificar al servicio web (posiblemente no está corriendo)"
    fi
}

# ============================================
# FUNCIÓN PRINCIPAL DE MONITOREO
# ============================================

monitor_network_changes() {
    log_info "Iniciando monitoreo de cambios de red..."
    
    while true; do
        local current_wifi_status=$(get_wifi_status)
        local current_eth_config=$(get_eth_config_method)
        
        # Log estado actual (solo si cambió)
        if [ "$current_wifi_status" != "$PREVIOUS_WIFI_STATUS" ] || \
           [ "$current_eth_config" != "$PREVIOUS_ETH_CONFIG" ]; then
            log_info "Estado actual - WiFi: $current_wifi_status, Ethernet: $current_eth_config"
        fi
        
        # Lógica de cambio automático
        if [ "$current_wifi_status" != "DISCONNECTED" ] && \
           [ "$current_eth_config" = "static" ] && \
           is_on_tplink_network; then
            
            log_info "WiFi conectado a '$current_wifi_status' - cambiando ethernet a DHCP"
            
            if switch_to_dhcp; then
                notify_web_service "Configuración cambiada automáticamente a DHCP después de conectar WiFi a '$current_wifi_status'"
                log_success "Cambio automático completado exitosamente"
            else
                log_error "Fallo en cambio automático a DHCP"
            fi
        fi
        
        # Actualizar estado anterior
        PREVIOUS_WIFI_STATUS="$current_wifi_status"
        PREVIOUS_ETH_CONFIG="$current_eth_config"
        
        # Esperar antes del siguiente chequeo
        sleep $CHECK_INTERVAL
    done
}

# ============================================
# FUNCIONES DE CONTROL DE SERVICIO
# ============================================

start_monitor() {
    log_info "Iniciando monitor de red v$MONITOR_VERSION"
    
    # Crear directorio de logs si no existe
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Verificar dependencias
    if ! command -v nmcli >/dev/null 2>&1 && ! command -v iwgetid >/dev/null 2>&1; then
        log_error "No se encontraron herramientas de red necesarias (nmcli o iwgetid)"
        exit 1
    fi
    
    # Iniciar monitoreo
    monitor_network_changes
}

stop_monitor() {
    log_info "Deteniendo monitor de red"
    exit 0
}

# ============================================
# MANEJO DE SEÑALES
# ============================================

trap stop_monitor SIGTERM SIGINT

# ============================================
# FUNCIÓN PRINCIPAL
# ============================================

main() {
    case "${1:-start}" in
        start)
            start_monitor
            ;;
        stop)
            stop_monitor
            ;;
        status)
            echo "WiFi Status: $(get_wifi_status)"
            echo "Ethernet Config: $(get_eth_config_method)"
            echo "On TP-Link Network: $(is_on_tplink_network && echo 'Yes' || echo 'No')"
            ;;
        *)
            echo "Uso: $0 {start|stop|status}"
            echo ""
            echo "start  - Iniciar monitoreo de red"
            echo "stop   - Detener monitoreo"
            echo "status - Mostrar estado actual"
            exit 1
            ;;
    esac
}

# Ejecutar función principal
main "$@"