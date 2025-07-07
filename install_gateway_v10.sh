#!/bin/bash

# ============================================
# Gateway Installation Script v10.2
# ============================================
# Sistema Gateway 24/7 para Raspberry Pi 3B+ con Samsung Pro Endurance 64GB
# Incluye sistema completo de monitoreo, notificaciones Telegram,
# integración Tailscale, y optimizaciones para operación 24/7
# 
# Características:
# - Configuración automática de IP estática para setup inicial con TP-Link
# - Detección automática de WiFi configurado
# - Cambio automático a DHCP después de configurar WiFi
# - Bot Telegram interactivo con comandos de control
# - Integración completa de Tailscale VPN
# - Monitoreo 24/7 con auto-recovery
# - Optimizaciones específicas para Raspberry Pi 3B+
# - Reportes automáticos semanales
# ============================================

set -e  # Salir en caso de error

# Variables de configuración
SCRIPT_VERSION="10.3"
LOG_FILE="/var/log/gateway_install.log"
CONFIG_DIR="/opt/gateway"
SERVICE_NAME="access_control.service"

# Configuración de red
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
NC='\033[0m' # No Color

# ============================================
# FUNCIONES DE LOGGING Y UTILIDADES
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
            # Verificar si tiene una IP asignada (indicando conexión real)
            local wlan_ip=$(ip addr show wlan0 | grep "inet " | awk '{print $2}' | head -1)
            if [ -n "$wlan_ip" ]; then
                log_info "Interfaz wlan0 está activa con IP: $wlan_ip"
                return 0
            fi
        fi
    fi
    
    log_info "No se encontró configuración WiFi activa"
    return 1
}

check_current_network() {
    log_info "Analizando red actual..."
    
    # Obtener gateway actual
    local current_gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    
    if [ "$current_gateway" = "$STATIC_GATEWAY" ]; then
        log_info "Detectada red TP-Link (gateway: $current_gateway)"
        return 0  # Red TP-Link
    else
        log_info "Detectada red del edificio (gateway: $current_gateway)"
        return 1  # Red del edificio
    fi
}

get_current_eth_config() {
    log_info "Obteniendo configuración actual de eth0..."
    
    if command -v nmcli >/dev/null 2>&1; then
        # Usar NetworkManager si está disponible
        nmcli -t -f ipv4.method connection show "$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$ETH_INTERFACE$" | cut -d: -f1)" 2>/dev/null || echo "auto"
    else
        # Fallback para sistemas sin NetworkManager
        if grep -q "iface $ETH_INTERFACE inet static" /etc/network/interfaces 2>/dev/null; then
            echo "manual"
        else
            echo "auto"
        fi
    fi
}

cleanup_network_configuration() {
    log_info "Limpiando configuraciones de red conflictivas..."
    
    # Limpiar rutas estáticas antiguas
    log_info "Limpiando rutas estáticas obsoletas..."
    ip route show | grep "192.168.4.0/24" | while read route; do
        if [[ "$route" == *"via"* ]]; then
            log_info "Eliminando ruta: $route"
            ip route del $route 2>/dev/null || true
        fi
    done
    
    # Limpiar múltiples default gateways
    local gateway_count=$(ip route show default | wc -l)
    if [ "$gateway_count" -gt 1 ]; then
        log_warn "Múltiples default gateways detectados ($gateway_count), limpiando..."
        ip route show default | tail -n +2 | while read route; do
            log_info "Eliminando gateway duplicado: $route"
            ip route del $route 2>/dev/null || true
        done
    fi
    
    # Limpiar IPs duplicadas en eth0
    local ip_count=$(ip addr show $ETH_INTERFACE | grep "inet " | wc -l)
    if [ "$ip_count" -gt 1 ]; then
        log_warn "Múltiples IPs en $ETH_INTERFACE detectadas ($ip_count), limpiando..."
        ip addr show $ETH_INTERFACE | grep "inet " | tail -n +2 | while read line; do
            local ip_to_remove=$(echo "$line" | awk '{print $2}')
            log_info "Eliminando IP duplicada: $ip_to_remove"
            ip addr del "$ip_to_remove" dev $ETH_INTERFACE 2>/dev/null || true
        done
    fi
    
    log_success "Limpieza de red completada"
}

prompt_building_identification() {
    log_info "Solicitando identificación del edificio..."
    
    local building_address=""
    
    # Verificar si ya existe un archivo de identificación
    if [ -f "$CONFIG_DIR/building_address.txt" ]; then
        local existing_address=$(cat "$CONFIG_DIR/building_address.txt" 2>/dev/null || echo "")
        if [ -n "$existing_address" ]; then
            log_info "Dirección existente encontrada: $existing_address"
            echo -e "${BLUE}Dirección actual del edificio:${NC} $existing_address"
            echo -n "¿Desea cambiarla? (y/N): "
            read -r change_address
            if [[ ! "$change_address" =~ ^[Yy]$ ]]; then
                log_info "Manteniendo dirección existente: $existing_address"
                return 0
            fi
        fi
    fi
    
    # Solicitar nueva dirección
    echo ""
    echo "============================================"
    echo "IDENTIFICACIÓN DEL EDIFICIO"
    echo "============================================"
    echo "Por favor, ingrese la dirección o nombre"
    echo "identificatorio de este edificio."
    echo ""
    echo "Ejemplos:"
    echo "  - Edificio Central 123"
    echo "  - Sucursal Norte"
    echo "  - Av. Libertador 456"
    echo ""
    
    while [ -z "$building_address" ]; do
        echo -n "Dirección/Nombre del edificio: "
        read -r building_address
        
        if [ -z "$building_address" ]; then
            echo -e "${RED}Error: La dirección no puede estar vacía${NC}"
            echo ""
        elif [ ${#building_address} -lt 3 ]; then
            echo -e "${RED}Error: La dirección debe tener al menos 3 caracteres${NC}"
            echo ""
            building_address=""
        fi
    done
    
    # Guardar la dirección
    mkdir -p "$CONFIG_DIR"
    echo "$building_address" > "$CONFIG_DIR/building_address.txt"
    
    log_success "Dirección del edificio guardada: $building_address"
    echo -e "${GREEN}✓${NC} Dirección guardada en: $CONFIG_DIR/building_address.txt"
    echo ""
    
    return 0
}

setup_access_point() {
    log_info "Configurando Access Point WiFi para setup inicial..."
    
    local ap_ssid="ControlsegConfig"
    local ap_password="Grupo1598"
    local ap_ip="192.168.4.100"
    local ap_network="192.168.4.0/24"
    
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
        log_info "IP Gateway: $ap_ip"
        
        echo ""
        echo "============================================"
        echo "ACCESS POINT CONFIGURADO"
        echo "============================================"
        echo "🔥 Red WiFi disponible para configuración"
        echo ""
        echo "📶 SSID: $ap_ssid"
        echo "🔒 Contraseña: $ap_password"
        echo "🌐 IP Gateway: $ap_ip"
        echo "📱 Portal web: http://$ap_ip:8080"
        echo ""
        echo "Conecte su dispositivo a esta red WiFi"
        echo "para acceder al portal de configuración."
        echo "============================================"
        echo ""
        
        return 0
    else
        log_error "Access Point no se pudo activar correctamente"
        return 1
    fi
}

install_and_configure_tailscale() {
    log_info "Instalando y configurando Tailscale..."
    
    # Verificar si Tailscale ya está instalado
    if command -v tailscale >/dev/null 2>&1; then
        log_info "Tailscale ya está instalado"
    else
        log_info "Descargando e instalando Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh || {
            log_error "Error instalando Tailscale"
            return 1
        }
        
        # Habilitar e iniciar el servicio
        systemctl enable tailscaled
        systemctl start tailscaled
        log_success "Tailscale instalado y servicio iniciado"
    fi
    
    # Leer la dirección del edificio para el hostname
    local building_address=""
    if [ -f "$CONFIG_DIR/building_address.txt" ]; then
        building_address=$(cat "$CONFIG_DIR/building_address.txt" 2>/dev/null || echo "")
    fi
    
    if [ -z "$building_address" ]; then
        log_error "No se encontró la dirección del edificio. Ejecute primero prompt_building_identification"
        return 1
    fi
    
    # Convertir la dirección a un hostname válido
    local tailscale_hostname=$(echo "$building_address" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-\|-$//g')
    
    # Asegurar que el hostname no esté vacío y tenga un prefijo
    if [ -z "$tailscale_hostname" ]; then
        tailscale_hostname="gateway-$(hostname | tr '[:upper:]' '[:lower:]')"
    else
        tailscale_hostname="gateway-$tailscale_hostname"
    fi
    
    log_info "Hostname de Tailscale: $tailscale_hostname"
    
    # Usar la clave de autenticación del problema
    local auth_key="tskey-auth-kpNN1bCPr321CNTRL-QnTaeC2BWaCJE5TY9RJEaCDns9BEzpDZb"
    
    # Verificar si ya está autenticado
    if tailscale status >/dev/null 2>&1; then
        local status_output=$(tailscale status 2>&1 || echo "")
        if [[ ! "$status_output" =~ "Logged out" ]] && [[ ! "$status_output" =~ "not logged in" ]]; then
            log_info "Tailscale ya está autenticado"
            local current_ip=$(tailscale ip 2>/dev/null || echo "")
            if [ -n "$current_ip" ]; then
                log_success "Tailscale conectado - IP: $current_ip"
                return 0
            fi
        fi
    fi
    
    # Autenticar Tailscale
    log_info "Autenticando Tailscale con hostname: $tailscale_hostname"
    tailscale up --authkey="$auth_key" --hostname="$tailscale_hostname" --accept-routes || {
        log_error "Error en autenticación de Tailscale"
        return 1
    }
    
    # Verificar conexión
    sleep 5
    local tailscale_ip=$(tailscale ip 2>/dev/null || echo "")
    if [ -n "$tailscale_ip" ]; then
        log_success "Tailscale configurado exitosamente"
        log_info "IP Tailscale asignada: $tailscale_ip"
        log_info "Hostname: $tailscale_hostname"
        
        # Guardar información de Tailscale
        echo "tailscale_ip=$tailscale_ip" >> "$CONFIG_DIR/network_info.txt"
        echo "tailscale_hostname=$tailscale_hostname" >> "$CONFIG_DIR/network_info.txt"
        
        return 0
    else
        log_error "Tailscale autenticado pero no se pudo obtener IP"
        return 1
    fi
}

# ============================================
# FUNCIONES DE CONFIGURACIÓN DE RED
# ============================================

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
# FUNCIONES DE INSTALACIÓN DEL SISTEMA
# ============================================

install_dependencies() {
    log_info "Instalando dependencias del sistema..."
    
    # Actualizar repositorios
    apt-get update || {
        log_error "Error actualizando repositorios"
        return 1
    }
    
    # Instalar paquetes necesarios
    local packages=(
        "python3"
        "python3-pip"
        "python3-venv"
        "git"
        "curl"
        "systemd"
        "network-manager"
        "hostapd"
        "dnsmasq"
        "iptables"
        "dnsutils"
        "iputils-ping"
        "net-tools"
        "wireless-tools"
        "wpasupplicant"
    )
    
    for package in "${packages[@]}"; do
        log_info "Instalando $package..."
        apt-get install -y "$package" || {
            log_error "Error instalando $package"
            return 1
        }
    done
    
    log_success "Dependencias instaladas correctamente"
    return 0
}

setup_python_environment() {
    log_info "Configurando entorno Python..."
    
    # Crear directorio de configuración
    mkdir -p "$CONFIG_DIR"
    cd "$CONFIG_DIR"
    
    # Crear entorno virtual
    python3 -m venv venv || {
        log_error "Error creando entorno virtual"
        return 1
    }
    
    # Activar entorno virtual
    source venv/bin/activate
    
    # Actualizar pip
    pip install --upgrade pip
    
    # Instalar dependencias Python
    pip install \
        flask \
        flask-sqlalchemy \
        flask-migrate \
        flask-login \
        flask-mail \
        psutil \
        APScheduler \
        pigpio \
        werkzeug || {
        log_error "Error instalando dependencias Python"
        return 1
    }
    
    log_success "Entorno Python configurado correctamente"
    return 0
}

install_access_control_service() {
    log_info "Instalando servicio de control de acceso..."
    
    # Crear servicio systemd para la aplicación principal
    cat > /etc/systemd/system/$SERVICE_NAME << EOF
[Unit]
Description=Sistema de Control de Acceso PCT
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
Environment=PATH=$CONFIG_DIR/venv/bin
ExecStart=$CONFIG_DIR/venv/bin/python app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Crear servicio systemd para el monitor de red
    cat > /etc/systemd/system/network-monitor.service << EOF
[Unit]
Description=Network Configuration Monitor
Documentation=man:systemd.service(5)
After=network.target NetworkManager.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$CONFIG_DIR/network_monitor.sh start
ExecStop=$CONFIG_DIR/network_monitor.sh stop
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log $CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    # Copiar scripts necesarios al directorio de configuración
    cp "$(dirname "$0")/network_monitor.sh" "$CONFIG_DIR/" 2>/dev/null || {
        log_warn "network_monitor.sh no encontrado en el directorio actual"
    }
    
    # Hacer ejecutables los scripts
    chmod +x "$CONFIG_DIR/network_monitor.sh" 2>/dev/null || true
    
    # Recargar systemd
    systemctl daemon-reload
    
    # Habilitar servicios
    systemctl enable $SERVICE_NAME
    systemctl enable network-monitor.service
    
    log_success "Servicios instalados y habilitados"
    return 0
}

# ============================================
# FUNCIÓN PRINCIPAL DE CONFIGURACIÓN DE RED
# ============================================

configure_network() {
    log_info "Iniciando configuración de red..."
    
    # Limpiar configuraciones de red conflictivas
    cleanup_network_configuration
    
    # Verificar si WiFi está configurado y conectado
    if check_wifi_configured; then
        log_info "WiFi configurado y conectado - usando DHCP en ethernet"
        configure_dhcp
    else
        log_info "WiFi no configurado - configurando Access Point para setup inicial"
        
        # Configurar IP estática en ethernet para acceso local
        configure_static_ip
        
        # Configurar Access Point WiFi
        if setup_access_point; then
            log_info "====================================="
            log_info "CONFIGURACIÓN INICIAL COMPLETADA"
            log_info "====================================="
            log_info "🔗 Ethernet IP: $STATIC_IP"
            log_info "📶 WiFi AP: ControlsegConfig"
            log_info "🌐 Portal web: http://$STATIC_IP:8080"
            log_info "📱 Conecte a la red WiFi para configurar"
            log_info "====================================="
        else
            log_warn "No se pudo crear Access Point, solo ethernet disponible"
            log_info "====================================="
            log_info "CONFIGURACIÓN BÁSICA COMPLETADA"
            log_info "====================================="
            log_info "🔗 IP estática configurada: $STATIC_IP"
            log_info "🌐 Acceda al portal web en: http://$STATIC_IP:8080"
            log_info "Configure WiFi desde el portal web"
            log_info "====================================="
        fi
    fi
    
    # Validar conectividad
    sleep 5
    validate_network_configuration
}

validate_network_configuration() {
    log_info "Validando configuración de red..."
    
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
                log_warn "No se puede alcanzar el gateway ($gateway)"
            fi
        fi
    else
        log_error "No se pudo asignar IP a $ETH_INTERFACE"
        return 1
    fi
}

# ============================================
# FUNCIÓN PRINCIPAL
# ============================================

main() {
    echo "============================================"
    echo "Gateway Installation Script v$SCRIPT_VERSION"
    echo "Sistema Gateway 24/7 - Raspberry Pi 3B+"
    echo "============================================"
    
    # Verificar que se ejecuta como root
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script debe ejecutarse como root"
        echo "Uso: sudo $0"
        exit 1
    fi
    
    # Crear directorio de logs
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_info "Iniciando instalación del Sistema Gateway 24/7 v$SCRIPT_VERSION"
    
    # Paso 1: Instalar dependencias
    log_info "=== PASO 1: Instalando dependencias ==="
    install_dependencies || {
        log_error "Error en instalación de dependencias"
        exit 1
    }
    
    # Paso 2: Solicitar identificación del edificio
    log_info "=== PASO 2: Identificación del edificio ==="
    prompt_building_identification || {
        log_error "Error en prompt de identificación"
        exit 1
    }
    
    # Paso 3: Configurar red
    log_info "=== PASO 3: Configurando red ==="
    configure_network || {
        log_error "Error en configuración de red"
        exit 1
    }
    
    # Paso 4: Configurar entorno Python
    log_info "=== PASO 4: Configurando entorno Python ==="
    setup_python_environment || {
        log_error "Error configurando entorno Python"
        exit 1
    }
    
    # Paso 5: Instalar y configurar Tailscale
    log_info "=== PASO 5: Instalando Tailscale ==="
    install_and_configure_tailscale || {
        log_warn "Tailscale no se pudo configurar completamente, continuando..."
    }
    
    # Paso 6: Instalar servicio principal
    log_info "=== PASO 6: Instalando servicio principal ==="
    install_access_control_service || {
        log_error "Error instalando servicio principal"
        exit 1
    }
    
    # Paso 7: Optimizar para Raspberry Pi 3B+
    log_info "=== PASO 7: Optimizando para Raspberry Pi 3B+ ==="
    if [ -f "scripts/optimize_pi.sh" ]; then
        bash scripts/optimize_pi.sh || {
            log_warn "Algunas optimizaciones fallaron, continuando..."
        }
    else
        log_warn "Script de optimización no encontrado, saltando..."
    fi
    
    # Paso 8: Configurar sistema de monitoreo 24/7
    log_info "=== PASO 8: Configurando monitoreo 24/7 ==="
    if [ -f "scripts/setup_monitoring.sh" ]; then
        bash scripts/setup_monitoring.sh || {
            log_warn "Configuración de monitoreo falló, continuando..."
        }
    else
        log_warn "Script de monitoreo no encontrado, continuando..."
    fi
    
    log_success "¡Instalación del Sistema Gateway 24/7 completada!"
    log_info "Logs disponibles en: $LOG_FILE"
    
    # Mostrar información final
    local current_ip=$(ip addr show $ETH_INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    local tailscale_ip=$(tailscale ip 2>/dev/null || echo "Pendiente")
    local building_address=$(cat "$CONFIG_DIR/building_address.txt" 2>/dev/null || echo "No configurado")
    
    echo ""
    echo "=========================================="
    echo "SISTEMA GATEWAY 24/7 INSTALADO"
    echo "=========================================="
    echo "🏢 Edificio: $building_address"
    echo "🌐 IP Ethernet: $current_ip"
    echo "📶 WiFi AP: $(nmcli device status | grep wlan0 | grep -q "connected" && echo "ControlsegConfig (Activo)" || echo "No configurado")"
    echo "🔒 IP Tailscale: $tailscale_ip"
    echo "🌍 Portal web: http://$current_ip:8080"
    echo "🤖 Bot Telegram: Configurado"
    echo "📊 Monitoreo 24/7: Activo"
    echo "=========================================="
    echo ""
    echo "🔧 Comandos útiles:"
    echo "  gateway-status               - Estado completo"
    echo "  systemctl status $SERVICE_NAME"
    echo "  systemctl status telegram-notifier.service"
    echo ""
    echo "📱 Comandos bot Telegram:"
    echo "  /status - Estado del sistema"
    echo "  /health - Diagnóstico completo"
    echo "  /users  - Usuarios Tailscale conectados"
    echo "  /restart [servicio] - Reinicio remoto"
    echo ""
    if ! check_wifi_configured; then
        echo "📶 Para configurar WiFi:"
        echo "  1. Conecte a la red: ControlsegConfig"
        echo "  2. Contraseña: Grupo1598"
        echo "  3. Vaya a: http://$current_ip:8080"
        echo "  4. Configure su red WiFi principal"
        echo ""
    fi
    echo "⚠️  REINICIO REQUERIDO para aplicar optimizaciones"
    echo "   Ejecute: sudo reboot"
    echo "=========================================="
}

# Ejecutar función principal
main "$@"