#!/bin/bash

# ============================================
# Network Configuration Applier
# ============================================
# Script que se ejecuta al inicio del sistema para aplicar
# configuraciones de red diferidas durante la instalación.
# Se ejecuta una sola vez después del reboot post-instalación.
# ============================================

set -e

# Variables de configuración
APPLIER_VERSION="1.0"
LOG_FILE="/var/log/network_config_applier.log"
CONFIG_DIR="/opt/gateway"
PENDING_CONFIG_DIR="$CONFIG_DIR/pending_network_config"
APPLIED_FLAG="$CONFIG_DIR/.network_config_applied"

# Configuración de red por defecto
STATIC_IP="192.168.4.100"
STATIC_NETMASK="24"
STATIC_GATEWAY="192.168.4.1"
STATIC_DNS="8.8.8.8,8.8.4.4"
ETH_INTERFACE="eth0"

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
# FUNCIONES DE DETECCIÓN DE RED
# ============================================

check_wifi_configured() {
    log_info "Verificando configuración WiFi existente..."
    
    # Verificar si hay archivo de configuración WiFi cliente
    if [ -f "$CONFIG_DIR/wifi_client.conf" ] && [ -s "$CONFIG_DIR/wifi_client.conf" ]; then
        log_info "Encontrada configuración WiFi cliente guardada"
        return 0
    fi
    
    # Verificar si wpa_supplicant tiene configuraciones activas
    if [ -f "/etc/wpa_supplicant/wpa_supplicant.conf" ]; then
        if grep -q "network={" "/etc/wpa_supplicant/wpa_supplicant.conf" 2>/dev/null; then
            log_info "Encontrada configuración en wpa_supplicant"
            return 0
        fi
    fi
    
    # Verificar si hay procesos wpa_supplicant activos con conexión
    if command -v wpa_cli >/dev/null 2>&1; then
        if wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
            log_info "Encontrada conexión WiFi activa"
            return 0
        fi
    fi
    
    # Verificar si wlan0 está activo y conectado (método básico)
    if ip link show wlan0 >/dev/null 2>&1; then
        local wlan_status=$(ip link show wlan0 | grep "state UP" || true)
        if [ -n "$wlan_status" ]; then
            # Verificar si tiene IP asignada (no en rango AP)
            local wlan_ip=$(ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
            if [ -n "$wlan_ip" ] && [ "$wlan_ip" != "192.168.4.100" ]; then
                log_info "WiFi conectado con IP: $wlan_ip"
                return 0
            fi
        fi
    fi
    
    log_info "WiFi no configurado o no conectado"
    return 1
}

# ============================================
# FUNCIONES DE LIMPIEZA DE RED
# ============================================

cleanup_network_configuration() {
    log_info "Limpiando configuraciones de red conflictivas..."
    
    # Limpiar IPs duplicadas en eth0
    local eth_ips=$(ip addr show $ETH_INTERFACE 2>/dev/null | grep "inet " | wc -l || echo "0")
    if [ "$eth_ips" -gt 1 ]; then
        log_info "Eliminando IPs duplicadas en $ETH_INTERFACE"
        ip addr show $ETH_INTERFACE | grep "inet " | while read line; do
            local ip=$(echo "$line" | awk '{print $2}')
            if [[ "$ip" != *"192.168.4."* ]] && [[ "$ip" != *"/32"* ]]; then
                ip addr del "$ip" dev $ETH_INTERFACE 2>/dev/null || true
            fi
        done
    fi
    
    # Limpiar rutas estáticas obsoletas
    log_info "Limpiando rutas estáticas obsoletas..."
    ip route show | grep "192.168.4.0/24" | while read route; do
        log_info "Eliminando ruta obsoleta: $route"
        ip route del $route 2>/dev/null || true
    done
    
    # Asegurar solo un default gateway
    local gw_count=$(ip route show default | wc -l)
    if [ "$gw_count" -gt 1 ]; then
        log_info "Múltiples default gateways detectados, limpiando..."
        ip route show default | head -n -1 | while read route; do
            ip route del $route 2>/dev/null || true
        done
    fi
    
    log_success "Limpieza de red completada"
}

# ============================================
# FUNCIONES DE CONFIGURACIÓN DE RED
# ============================================

setup_networkmanager_ignore_wlan0() {
    log_info "Configurando NetworkManager para ignorar wlan0..."
    
    # Crear archivo de configuración para que NetworkManager ignore wlan0
    local nm_config_dir="/etc/NetworkManager/conf.d"
    local nm_config_file="$nm_config_dir/99-unmanaged-wlan0.conf"
    
    # Crear directorio si no existe
    mkdir -p "$nm_config_dir"
    
    # Crear configuración para ignorar wlan0
    cat > "$nm_config_file" << EOF
# NetworkManager configuration to ignore wlan0
# This allows hostapd and manual configuration to manage wlan0
[device]
wifi.scan-rand-mac-address=no

[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
    
    # Establecer permisos correctos
    chmod 644 "$nm_config_file"
    chown root:root "$nm_config_file"
    
    # Reiniciar NetworkManager si está activo
    if systemctl is-active --quiet NetworkManager; then
        log_info "Reiniciando NetworkManager..."
        systemctl reload NetworkManager || systemctl restart NetworkManager
        sleep 2
    fi
    
    log_success "NetworkManager configurado para ignorar wlan0"
}

setup_access_point() {
    log_info "Configurando Access Point WiFi con hostapd + dnsmasq..."
    
    local ap_ssid="ControlsegConfig"
    local ap_password="Grupo1598"
    local ap_ip="192.168.4.100"
    
    # Verificar que wlan0 esté disponible
    if ! ip link show wlan0 >/dev/null 2>&1; then
        log_error "Interfaz wlan0 no encontrada - no se puede crear Access Point"
        log_error "Verifique que el dispositivo WiFi esté conectado y funcionando"
        log_error "Ejecute 'ip link show' para ver interfaces disponibles"
        return 1
    fi
    
    log_info "Interfaz wlan0 detectada correctamente"
    
    # Verificar que los scripts de modo están disponibles
    local ap_mode_script="$CONFIG_DIR/../scripts/ap_mode.sh"
    if [ ! -x "$ap_mode_script" ]; then
        log_error "Script de modo AP no encontrado o no ejecutable: $ap_mode_script"
        return 1
    fi
    
    # Configurar NetworkManager para ignorar wlan0
    log_info "Configurando NetworkManager para ignorar wlan0..."
    setup_networkmanager_ignore_wlan0
    
    # Ejecutar script de modo AP
    log_info "Ejecutando script de modo Access Point..."
    if "$ap_mode_script"; then
        log_success "Access Point creado exitosamente"
        log_info "SSID: $ap_ssid"
        log_info "Contraseña: $ap_password"
        log_info "IP: $ap_ip"
        log_info "DHCP Range: 192.168.4.50-150"
        return 0
    else
        log_error "Error ejecutando script de modo Access Point"
        return 1
    fi
}

configure_static_ip() {
    log_info "Configurando IP estática en $ETH_INTERFACE: $STATIC_IP/$STATIC_NETMASK"
    
    if command -v nmcli >/dev/null 2>&1; then
        # Usar NetworkManager
        local connection_name="Wired connection 1"
        
        # Buscar conexión ethernet existente
        local existing_conn=$(nmcli -t -f NAME,TYPE connection show | grep ":ethernet$" | cut -d: -f1 | head -1)
        if [ -n "$existing_conn" ]; then
            connection_name="$existing_conn"
        fi
        
        log_info "Configurando conexión: $connection_name"
        
        # Configurar IP estática
        nmcli connection modify "$connection_name" \
            ipv4.method manual \
            ipv4.addresses "$STATIC_IP/$STATIC_NETMASK" \
            ipv4.gateway "$STATIC_GATEWAY" \
            ipv4.dns "$STATIC_DNS" || {
            log_error "Error configurando IP estática con NetworkManager"
            return 1
        }
        
        # Activar conexión
        nmcli connection up "$connection_name" || {
            log_warn "No se pudo activar inmediatamente la conexión"
        }
        
    else
        # Fallback para sistemas sin NetworkManager
        log_info "NetworkManager no disponible, usando configuración manual"
        
        # Backup de configuración actual
        cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s) 2>/dev/null || true
        
        # Configurar interfaz estática
        cat > /etc/network/interfaces.d/eth0-static << EOF
auto $ETH_INTERFACE
iface $ETH_INTERFACE inet static
    address $STATIC_IP
    netmask $(echo $STATIC_NETMASK | xargs)
    gateway $STATIC_GATEWAY
    dns-nameservers $STATIC_DNS
EOF
        
        # Reiniciar interfaz
        ifdown $ETH_INTERFACE 2>/dev/null || true
        ifup $ETH_INTERFACE || {
            log_error "Error activando interfaz $ETH_INTERFACE"
            return 1
        }
    fi
    
    log_success "IP estática configurada correctamente"
    return 0
}

configure_dhcp() {
    log_info "Configurando DHCP en $ETH_INTERFACE"
    
    if command -v nmcli >/dev/null 2>&1; then
        # Usar NetworkManager
        local connection_name="Wired connection 1"
        
        # Buscar conexión ethernet existente
        local existing_conn=$(nmcli -t -f NAME,TYPE connection show | grep ":ethernet$" | cut -d: -f1 | head -1)
        if [ -n "$existing_conn" ]; then
            connection_name="$existing_conn"
        fi
        
        log_info "Configurando DHCP en conexión: $connection_name"
        
        # Configurar DHCP
        nmcli connection modify "$connection_name" \
            ipv4.method auto \
            ipv4.addresses "" \
            ipv4.gateway "" \
            ipv4.dns "" || {
            log_error "Error configurando DHCP con NetworkManager"
            return 1
        }
        
        # Activar conexión
        nmcli connection up "$connection_name" || {
            log_warn "No se pudo activar inmediatamente la conexión DHCP"
        }
        
    else
        # Fallback para sistemas sin NetworkManager
        log_info "NetworkManager no disponible, usando configuración manual"
        
        # Remover configuración estática
        rm -f /etc/network/interfaces.d/eth0-static
        
        # Configurar DHCP
        cat > /etc/network/interfaces.d/eth0-dhcp << EOF
auto $ETH_INTERFACE
iface $ETH_INTERFACE inet dhcp
EOF
        
        # Reiniciar interfaz
        ifdown $ETH_INTERFACE 2>/dev/null || true
        ifup $ETH_INTERFACE || {
            log_error "Error activando DHCP en $ETH_INTERFACE"
            return 1
        }
    fi
    
    log_success "DHCP configurado correctamente"
    return 0
}

# ============================================
# FUNCIONES PRINCIPALES
# ============================================

apply_pending_network_configuration() {
    log_info "Aplicando configuración de red diferida..."
    
    # Verificar si hay configuración pendiente
    if [ ! -d "$PENDING_CONFIG_DIR" ]; then
        log_info "No hay configuración de red pendiente"
        return 0
    fi
    
    # Limpiar configuraciones conflictivas
    cleanup_network_configuration
    
    # Leer tipo de configuración pendiente
    local config_type=""
    if [ -f "$PENDING_CONFIG_DIR/config_type" ]; then
        config_type=$(cat "$PENDING_CONFIG_DIR/config_type")
        log_info "Tipo de configuración pendiente: $config_type"
    else
        log_error "No se encontró archivo de tipo de configuración"
        return 1
    fi
    
    case "$config_type" in
        "dhcp")
            log_info "Aplicando configuración DHCP..."
            if configure_dhcp; then
                log_success "Configuración DHCP aplicada exitosamente"
            else
                log_error "Error aplicando configuración DHCP"
                return 1
            fi
            ;;
        "static_ap")
            log_info "Aplicando configuración estática + Access Point..."
            if configure_static_ip && setup_access_point; then
                log_success "Configuración estática + AP aplicada exitosamente"
                log_info "====================================="
                log_info "CONFIGURACIÓN INICIAL COMPLETADA"
                log_info "====================================="
                log_info "🔗 Ethernet IP: $STATIC_IP"
                log_info "📶 WiFi AP: ControlsegConfig"
                log_info "🌐 Portal web: http://$STATIC_IP:8080"
                log_info "📱 Conecte a la red WiFi para configurar"
                log_info "====================================="
            else
                log_error "Error aplicando configuración estática + AP"
                return 1
            fi
            ;;
        "static_only")
            log_info "Aplicando configuración estática solamente..."
            if configure_static_ip; then
                log_success "Configuración estática aplicada exitosamente"
                log_info "====================================="
                log_info "CONFIGURACIÓN BÁSICA COMPLETADA"
                log_info "====================================="
                log_info "🔗 IP estática configurada: $STATIC_IP"
                log_info "🌐 Acceda al portal web en: http://$STATIC_IP:8080"
                log_info "Configure WiFi desde el portal web"
                log_info "====================================="
            else
                log_error "Error aplicando configuración estática"
                return 1
            fi
            ;;
        *)
            log_error "Tipo de configuración desconocido: $config_type"
            return 1
            ;;
    esac
    
    # Marcar configuración como aplicada
    touch "$APPLIED_FLAG"
    
    # Limpiar configuración pendiente
    rm -rf "$PENDING_CONFIG_DIR"
    
    log_success "Configuración de red aplicada exitosamente"
    return 0
}

validate_network_configuration() {
    log_info "Validando configuración de red aplicada..."
    
    # Verificar IP asignada
    local current_ip=$(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    
    if [ -n "$current_ip" ]; then
        log_success "IP asignada en $ETH_INTERFACE: $current_ip"
        
        # Test de conectividad al gateway
        local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
        if [ -n "$gateway" ]; then
            if ping -c 1 -W 3 "$gateway" >/dev/null 2>&1; then
                log_success "Conectividad al gateway ($gateway) exitosa"
            else
                log_warn "No hay conectividad al gateway ($gateway)"
            fi
        else
            log_warn "No se encontró gateway por defecto"
        fi
    else
        log_error "No se pudo obtener IP en $ETH_INTERFACE"
        return 1
    fi
    
    return 0
}

main() {
    echo "============================================"
    echo "Network Configuration Applier v$APPLIER_VERSION"
    echo "Aplicando configuración de red diferida"
    echo "============================================"
    
    # Crear directorio de logs
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_info "Iniciando aplicación de configuración de red diferida"
    
    # Verificar si ya se aplicó la configuración
    if [ -f "$APPLIED_FLAG" ]; then
        log_info "La configuración de red ya fue aplicada anteriormente"
        exit 0
    fi
    
    # Aplicar configuración pendiente
    if apply_pending_network_configuration; then
        # Validar configuración aplicada
        sleep 5
        validate_network_configuration
        
        log_success "Proceso de aplicación de configuración de red completado exitosamente"
        
        # Deshabilitar este servicio para que no se ejecute nuevamente
        systemctl disable network-config-applier.service 2>/dev/null || true
        
    else
        log_error "Error aplicando configuración de red"
        exit 1
    fi
}

# Ejecutar función principal
main "$@"