# Sistema Gateway 24/7 - Raspberry Pi 3B+

## Descripción

Sistema completo de gateway con monitoreo 24/7 optimizado para Raspberry Pi 3B+ con Samsung Pro Endurance 64GB. Incluye notificaciones Telegram, integración Tailscale, auto-recovery y optimizaciones específicas para operación continua.

### Características Principales

#### 🌐 **Sistema WiFi Robusto con hostapd + dnsmasq** ⭐ NUEVO
- **Access Point robusto** con hostapd en lugar de NetworkManager
- **DHCP confiable** con dnsmasq para el rango 192.168.4.50-150
- **Monitoreo automático** de conectividad WiFi con auto-recuperación
- **Cambio automático de modo** entre AP y cliente según configuración
- **NetworkManager deshabilitado** en wlan0 para máxima estabilidad
- **Configuración plug&play** sin intervención manual
- **Recovery automático** a modo AP si se pierde conexión cliente

#### 🌐 **Red Inteligente con Configuración Diferida**
- **Configuración diferida de red** - Evita desconexiones SSH durante instalación
- **Aplicación automática después del reinicio** para máxima estabilidad
- **Detección automática de WiFi** configurado y conectado
- **Cambio automático a DHCP** después de configurar WiFi exitosamente
- **Limpieza automática de red** para evitar conflictos de rutas y IPs duplicadas
- **Monitoreo continuo de red** para transiciones automáticas
- **Control total del momento del reinicio** para aplicar cambios de red

#### 🏢 **Identificación de Edificio**
- **Prompt interactivo** para identificar la ubicación del gateway
- **Almacenamiento persistente** en `/opt/gateway/building_address.txt`
- **Integración con Tailscale** para hostnames únicos por ubicación

#### 📱 **Sistema de Notificaciones Telegram**
- **Bot Token**: `7954949854:AAHjEYMdvJ9z2jD8pV7fGsI0a6ipTjJHR2M`
- **Chat ID**: `-4812920580`
- **Notificaciones en tiempo real** de conexiones, desconexiones y eventos críticos
- **Bot interactivo** con comandos de control remoto

#### 🔒 **Integración Tailscale Completa**
- **Auto-instalación** durante el setup del gateway usando script oficial
- **Autenticación automática** con clave predefinida
- **Hostname personalizado** basado en la dirección del edificio
- **Monitor de conexiones** en tiempo real con logging de accesos
- **Auto-reconexión** automática si se pierde conexión
- **Gestión de usuarios** y notificaciones de acceso

#### ⚡ **Optimizaciones Raspberry Pi 3B+**
- **CPU**: ARM Cortex-A53 1.4GHz (4 cores) - Gestión térmica optimizada
- **RAM**: 1GB LPDDR2 - Uso eficiente con zram y tmpfs
- **Storage**: Samsung Pro Endurance 64GB - Minimización de escrituras
- **Monitoreo de temperatura** con alertas preventivas

#### 🛡️ **Auto-Recovery y Monitoring 24/7**
- **Hardware watchdog** con reinicio automático en 2 minutos
- **Health checks** cada 5 minutos para CPU/RAM/Temperatura
- **Auto-recovery** de servicios críticos
- **Limpieza automática** de logs y espacio en disco

#### 📊 **Bot Telegram Interactivo**
Comandos disponibles:
- `/status` - Estado completo del sistema
- `/users` - Usuarios Tailscale conectados actualmente  
- `/logs` - Últimos 10 eventos importantes
- `/restart [servicio]` - Reinicio remoto de servicios específicos
- `/health` - Diagnóstico completo con métricas
- `/temp` - Temperatura actual y estado de throttling
- `/network` - Estado de todas las conexiones

## Flujo de Trabajo

### 1. Instalación Completa

```bash
sudo ./install_gateway_v10.sh
```

**El script ejecuta automáticamente:**
1. **Instalación de dependencias** (Python, systemd, red, hostapd, dnsmasq, iptables)
2. **Identificación del edificio** (prompt interactivo para ubicación)
3. **Configuración WiFi robusta** con hostapd + dnsmasq (reemplaza NetworkManager)
4. **Setup del entorno Python** con virtual environment
5. **Instalación y configuración de Tailscale** (automática con hostname personalizado)
6. **Instalación del servicio principal** de control de acceso
7. **Servicios de monitoreo WiFi** (cambio automático de modo AP/cliente)
8. **Optimizaciones Raspberry Pi 3B+** (memoria, CPU, storage)
9. **Configuración monitoreo 24/7** (Telegram, Tailscale, watchdog)

### 2. Sistema WiFi Robusto

#### Modo Access Point (Sin WiFi configurado):
- **Tecnología**: hostapd + dnsmasq (no NetworkManager)
- **SSID**: `ControlsegConfig`
- **Contraseña**: `Grupo1598`
- **Gateway**: `192.168.4.100`
- **DHCP**: `192.168.4.50-150`
- **DNS**: `8.8.8.8, 8.8.4.4`
- **Portal**: `http://192.168.4.100:8080`

#### Modo Cliente WiFi (Con configuración):
- **Tecnología**: wpa_supplicant + dhcpcd
- **Configuración**: Via portal web
- **Auto-switch**: Automático al guardar config
- **Recovery**: Vuelve a AP si pierde conexión
- **Monitoreo**: Continuo cada 30 segundos

#### Comandos manuales WiFi:
```bash
# Cambiar a modo AP manualmente
sudo /opt/gateway/scripts/ap_mode.sh

# Cambiar a modo cliente (requiere configuración)
sudo /opt/gateway/scripts/client_mode.sh

# Ejecutar una verificación del monitor
sudo /opt/gateway/scripts/wifi_mode_monitor.sh once

# Escanear redes WiFi
sudo /opt/gateway/scripts/web_wifi_api.sh scan

# Conectar a red WiFi
sudo /opt/gateway/scripts/web_wifi_api.sh connect "NombreRed" "contraseña"

# Desconectar WiFi (vuelve a modo AP)
sudo /opt/gateway/scripts/web_wifi_api.sh disconnect
```

### 3. Configuración Ethernet Automática

#### Sin WiFi configurado:
- **IP estática ethernet**: `192.168.4.100/24`
- **Acceso web**: `http://192.168.4.100:8080`
- **Portal de configuración** accesible vía WiFi AP o ethernet

#### Con WiFi configurado:
- **Ethernet**: DHCP automático  
- **WiFi**: Conexión a red del edificio
- **Tailscale**: Acceso remoto seguro con hostname personalizado

### 4. Monitoreo Automático 24/7

- **Notificaciones Telegram** en tiempo real
- **Health checks** continuos del sistema
- **Auto-recovery** de servicios críticos
- **Reportes semanales** automáticos
- **Control remoto** via bot Telegram

## Archivos del Sistema

### Scripts Principales

- `install_gateway_v10.sh` - **Script principal** de instalación completa
- `network_config_applier.sh` - Aplicador de configuración de red diferida
- `network_monitor.sh` - Monitor de configuración de red  

### Sistema WiFi Robusto

- `scripts/ap_mode.sh` - **Cambio a modo Access Point** con hostapd + dnsmasq
- `scripts/client_mode.sh` - **Cambio a modo cliente WiFi** con wpa_supplicant
- `scripts/wifi_mode_monitor.sh` - **Monitor automático** de modo WiFi
- `scripts/wifi_config_manager.sh` - **Gestor de configuraciones** WiFi cliente
- `scripts/web_wifi_api.sh` - **API helper** para portal web
- `scripts/patch_web_portal.sh` - **Patcher** para migrar portal web

### Servicios SystemD

- `network-config-applier.service` - Aplicación de configuración de red al boot
- `wifi-mode-monitor.service` - **Monitoreo continuo** de modo WiFi
- `network-monitor.service` - Monitoreo general de red

### Configuración WiFi

- `config/hostapd.conf.template` - **Plantilla hostapd** para modo AP
- `config/dnsmasq.conf.template` - **Plantilla dnsmasq** para DHCP
- `config/dhcpcd.conf.backup` - **Backup dhcpcd** para modo cliente
- `config/01-netcfg.yaml.template` - **NetworkManager** ignora wlan0

### Sistema de Monitoreo 24/7

- `services/telegram_notifier.py` - **Bot Telegram** y sistema de notificaciones
- `services/tailscale_monitor.py` - **Monitor Tailscale** con auto-reconnect
- `services/system_watchdog.py` - **Watchdog del sistema** con auto-recovery
- `services/health_monitor.py` - **Monitor de salud** y reportes automáticos

### Scripts de Optimización

- `scripts/optimize_pi.sh` - **Optimizaciones Raspberry Pi 3B+**
- `scripts/setup_monitoring.sh` - **Configuración del monitoreo completo**
- `scripts/install_services.sh` - **Instalación de servicios de monitoreo**

### Configuración

- `config/telegram.conf` - Configuración del bot Telegram
- `config/tailscale.conf` - Configuración de Tailscale VPN
- `config/monitoring.conf` - Configuración del sistema de monitoreo

### Aplicación Web

- `pi@raspberrypi~access_control_syste.txt` - Aplicación Flask principal

### APIs de Red

- `GET /api/system/network-status` - Estado actual de la red
- `POST /api/system/network-change` - Notificaciones de cambio  
- `POST /api/system/network-force-dhcp` - Forzar cambio a DHCP

## Instalación

### Prerrequisitos

- Sistema Linux (Raspberry Pi recomendado)
- Acceso root/sudo
- Conexión ethernet al modem TP-Link

### Instalación Automática

```bash
# Clonar repositorio
git clone https://github.com/lucassquirogaa/grupo.git
cd grupo

# Ejecutar instalación
sudo ./install_gateway_v10.sh
```

### Verificación

```bash
# Estado de servicios
sudo systemctl status access_control.service
sudo systemctl status network-monitor.service
sudo systemctl status wifi-mode-monitor.service

# Logs
sudo journalctl -u access_control.service -f
sudo journalctl -u network-monitor.service -f
sudo journalctl -u wifi-mode-monitor.service -f

# Estado de red
sudo ./network_monitor.sh status

# Estado WiFi
cat /opt/gateway/current_wifi_mode
sudo /opt/gateway/scripts/wifi_mode_monitor.sh once
```

## Configuración de Red

### Configuración TP-Link (Setup Inicial)

**Configuración automática:**
```bash
# Configuración ethernet
Interface: eth0
IP: 192.168.4.100/24
Gateway: 192.168.4.100

# Configuración Access Point WiFi
SSID: ControlsegConfig
Contraseña: Grupo1598
IP Gateway: 192.168.4.100
DNS: 8.8.8.8
```

**Para configurar WiFi principal (después del reinicio):**
1. Ejecute: `sudo reboot`
2. Espere a que se aplique la configuración automáticamente
3. Conecte a la red WiFi: `ControlsegConfig`
4. Use la contraseña: `Grupo1598`
5. Abra el navegador en: `http://192.168.4.100:8080`
6. Configure su red WiFi del edificio
7. El sistema cambiará automáticamente a esa red

### Configuración Final (Post-WiFi)

**Configuración automática después de WiFi:**
```bash
Interface: eth0 - DHCP
Interface: wlan0 - WiFi del edificio
Interface: tailscale0 - Red Tailscale (hostname personalizado)
Access Point: Desactivado automáticamente
```

## Monitoreo y Logs

### Logs del Sistema

- `/var/log/gateway_install.log` - Log de instalación
- `/var/log/network_monitor.log` - Log del monitor de red
- `/var/log/network_config_applier.log` - Log de aplicación de configuración de red
- `journalctl -u access_control.service` - Log del servicio principal
- `journalctl -u network-monitor.service` - Log del monitor
- `journalctl -u network-config-applier.service` - Log del aplicador de configuración

### Comandos de Diagnóstico

```bash
# Estado actual de la red
curl -s http://localhost:8080/api/system/network-status | jq

# Forzar cambio a DHCP
curl -X POST http://localhost:8080/api/system/network-force-dhcp

# Estado del monitor
sudo ./network_monitor.sh status
```

## Solución de Problemas

### Problemas Comunes

1. **No se puede acceder al portal web**
   ```bash
   # Verificar IP asignada
   ip addr show eth0
   
   # Verificar servicio
   sudo systemctl status access_control.service
   ```

2. **No cambia automáticamente a DHCP**
   ```bash
   # Verificar monitor
   sudo systemctl status network-monitor.service
   
   # Ver logs del monitor
   sudo journalctl -u network-monitor.service -f
   ```

3. **WiFi no se conecta**
   ```bash
   # Verificar estado del monitor WiFi
   sudo systemctl status wifi-mode-monitor.service
   
   # Ver logs del monitor WiFi
   sudo journalctl -u wifi-mode-monitor.service -f
   
   # Verificar modo actual
   cat /opt/gateway/current_wifi_mode
   
   # Escanear redes disponibles (sin nmcli)
   sudo /opt/gateway/scripts/web_wifi_api.sh scan
   
   # Forzar modo AP manualmente
   sudo /opt/gateway/scripts/ap_mode.sh
   
   # Verificar configuración WiFi guardada
   sudo /opt/gateway/scripts/wifi_config_manager.sh show
   ```

4. **Access Point no se inicia**
   ```bash
   # Verificar hostapd y dnsmasq
   sudo systemctl status hostapd
   sudo systemctl status dnsmasq
   
   # Ver logs de hostapd
   sudo journalctl -u hostapd -f
   
   # Verificar interfaz wlan0
   ip link show wlan0
   
   # Forzar reinicio de AP
   sudo /opt/gateway/scripts/ap_mode.sh
   
   # Verificar NetworkManager no interfiere
   cat /etc/NetworkManager/conf.d/99-unmanaged-wlan0.conf
   ```

### Comandos de Recuperación

```bash
# Resetear configuración de red
sudo nmcli connection delete "Wired connection 1"
sudo nmcli connection add type ethernet ifname eth0

# Forzar IP estática
sudo nmcli connection modify "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses "192.168.4.100/24" \
    ipv4.gateway "192.168.4.1" \
    ipv4.dns "8.8.8.8"

# Forzar DHCP
sudo nmcli connection modify "Wired connection 1" \
    ipv4.method auto \
    ipv4.addresses "" \
    ipv4.gateway "" \
    ipv4.dns ""
```

## Estructura de Directorios

```
/opt/gateway/                 # Directorio principal
├── venv/                    # Entorno virtual Python
├── app.py                   # Aplicación Flask principal
├── network_monitor.sh       # Script monitor de red
├── instance/                # Configuraciones
└── logs/                    # Logs locales

/etc/systemd/system/         # Servicios
├── access_control.service   # Servicio principal
└── network-monitor.service  # Servicio monitor

/var/log/                    # Logs del sistema
├── gateway_install.log      # Log de instalación
└── network_monitor.log      # Log del monitor
```

## Seguridad

### Configuraciones de Seguridad

- Servicios ejecutan con permisos mínimos necesarios
- Logs rotan automáticamente
- Validación de parámetros de entrada
- Timeouts en operaciones de red

### Acceso Web

- Autenticación requerida para APIs administrativas
- Logs de acceso detallados
- Validación de parámetros

## Compatibilidad

### Sistemas Operativos

- Raspberry Pi OS (recomendado)
- Ubuntu 20.04+
- Debian 10+

### Hardware

- Raspberry Pi 3/4 (recomendado)
- Interfaz ethernet eth0
- Interfaz WiFi wlan0 (opcional)

### Dependencias

- Python 3.7+
- NetworkManager (recomendado)
- systemd
- curl, ip, ping

## Versión

**Versión**: 10.3  
**Fecha**: 2024  
**Autor**: Sistema PCT  
**Repositorio**: https://github.com/lucassquirogaa/grupo

### Changelog v10.3

#### Nuevas Características
- ✅ **Access Point automático** cuando no hay WiFi configurado
- ✅ **Identificación de edificio** con prompt interactivo  
- ✅ **Integración Tailscale** con hostname personalizado
- ✅ **Limpieza automática de red** para evitar conflictos
- ✅ **Detección WiFi mejorada** con verificación de conectividad real

#### Mejoras Técnicas
- 🔧 Limpieza de rutas estáticas conflictivas y gateways duplicados
- 🔧 Validación de IPs múltiples en interfaces
- 🔧 Instalación automática de Tailscale con clave predefinida
- 🔧 Hostname basado en dirección del edificio
- 🔧 Dependencias adicionales: hostapd, dnsmasq, iptables

#### Flujo Mejorado
1. Prompt de identificación del edificio
2. Limpieza de configuración de red
3. Access Point si no hay WiFi / DHCP si hay WiFi
4. Instalación y configuración automática de Tailscale
5. Configuración completa del sistema de monitoreo