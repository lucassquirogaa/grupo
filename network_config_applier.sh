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
    
    # Verificar si hay conexiones WiFi configuradas en NetworkManager
    if command -v nmcli >/dev/null 2>&1; then
        local wifi_connections=$(nmcli -t -f NAME,TYPE connection show | grep ":wifi$" | wc -l)
        if [ "$wifi_connections" -gt 0 ]; then
            # Verificar si alguna conexión WiFi está actualmente conectada
            local active_wifi=$(nmcli -t -f ACTIVE,TYPE connection show | grep ":wifi$" | grep "^yes:" | wc -l)
            if [ "$active_wifi" -gt 0 ]; then
                log_info "Encontrada conexión WiFi activa"
                return 0
            else
                log_info "Conexiones WiFi configuradas pero no activas"
                return 1
            fi
        fi
    fi
    
    # Verificar si wlan0 está activo y conectado
    if ip link show wlan0 >/dev/null 2>&1; then
        local wlan_status=$(ip link show wlan0 | grep "state UP" || true)
        if [ -n "$wlan_status" ]; then
            # Verificar si tiene IP asignada
            local wlan_ip=$(ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
            if [ -n "$wlan_ip" ]; then
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

setup_access_point() {
    log_info "Configurando Access Point WiFi para setup inicial..."
    
    local ap_ssid="ControlsegConfig"
    local ap_password="Grupo1598"
    local ap_ip="192.168.4.100"
    
    # Verificar que wlan0 esté disponible
    if ! ip link show wlan0 >/dev/null 2>&1; then
        log_error "Interfaz wlan0 no encontrada - no se puede crear Access Point"
        return 1
    fi
    
    # Detener conexiones WiFi existentes
    log_info "Deteniendo conexiones WiFi existentes..."
    nmcli device disconnect wlan0 2>/dev/null || true
    
    # Eliminar conexiones WiFi existentes que puedan interferir
    nmcli connection show | grep wifi | awk '{print $1}' | while read conn; do
        if [ "$conn" != "$ap_ssid" ]; then
            log_info "Eliminando conexión WiFi existente: $conn"
            nmcli connection delete "$conn" 2>/dev/null || true
        fi
    done
    
    # Verificar si ya existe la conexión del AP
    if nmcli connection show "$ap_ssid" >/dev/null 2>&1; then
        log_info "Conexión AP existente encontrada, eliminando..."
        nmcli connection delete "$ap_ssid" || true
    fi
    
    log_info "Creando Access Point: $ap_ssid"
    
    # Crear la conexión hotspot
    nmcli connection add \
        type wifi \
        ifname wlan0 \
        con-name "$ap_ssid" \
        autoconnect yes \
        wifi.mode ap \
        wifi.ssid "$ap_ssid" \
        wifi.security wpa-psk \
        wifi.psk "$ap_password" \
        ipv4.method shared \
        ipv4.addresses "$ap_ip/24" \
        ipv4.gateway "$ap_ip" \
        ipv4.dns "8.8.8.8" || {
        log_error "Error creando configuración del Access Point"
        return 1
    }
    
    # Activar el Access Point
    log_info "Activando Access Point..."
    nmcli connection up "$ap_ssid" || {
        log_error "Error activando Access Point"
        return 1
    }
    
    # Verificar que el AP esté funcionando
    sleep 5
    if nmcli device status | grep wlan0 | grep -q "connected"; then
        log_success "Access Point creado exitosamente"
        log_info "SSID: $ap_ssid"
        log_info "Contraseña: $ap_password"
        log_info "IP: $ap_ip"
        return 0
    else
        log_error "Access Point no está funcionando correctamente"
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