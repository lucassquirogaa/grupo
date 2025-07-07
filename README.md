# Sistema Gateway 24/7 - Raspberry Pi 3B+

## Descripción

Sistema completo de gateway con monitoreo 24/7 optimizado para Raspberry Pi 3B+ con Samsung Pro Endurance 64GB. Incluye notificaciones Telegram, integración Tailscale, auto-recovery y optimizaciones específicas para operación continua.

### Características Principales

#### 🌐 **Red Inteligente**
- **Configuración automática de IP estática** para setup inicial con modem TP-Link
- **Detección automática de WiFi** configurado
- **Cambio automático a DHCP** después de configurar WiFi exitosamente
- **Monitoreo continuo de red** para transiciones automáticas

#### 📱 **Sistema de Notificaciones Telegram**
- **Bot Token**: `7954949854:AAHjEYMdvJ9z2jD8pV7fGsI0a6ipTjJHR2M`
- **Chat ID**: `-4812920580`
- **Notificaciones en tiempo real** de conexiones, desconexiones y eventos críticos
- **Bot interactivo** con comandos de control remoto

#### 🔒 **Integración Tailscale Completa**
- **Auto-instalación** durante el setup del gateway
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
1. **Instalación de dependencias** (Python, systemd, red)
2. **Configuración de red inteligente** (estática → WiFi → DHCP)
3. **Setup del entorno Python** con virtual environment
4. **Instalación del servicio principal** de control de acceso
5. **Optimizaciones Raspberry Pi 3B+** (memoria, CPU, storage)
6. **Configuración monitoreo 24/7** (Telegram, Tailscale, watchdog)

### 2. Configuración de Red Automática

1. **Sin WiFi configurado**: 
   - IP estática: `192.168.4.100/24`
   - Gateway: `192.168.4.1`
   - Acceso web: `http://192.168.4.100:8080`

2. **Con WiFi configurado**:
   - Ethernet: DHCP automático  
   - WiFi: Conexión a red del edificio
   - Tailscale: Acceso remoto seguro

### 3. Monitoreo Automático 24/7

- **Notificaciones Telegram** en tiempo real
- **Health checks** continuos del sistema
- **Auto-recovery** de servicios críticos
- **Reportes semanales** automáticos
- **Control remoto** via bot Telegram

## Archivos del Sistema

### Scripts Principales

- `install_gateway_v10.sh` - **Script principal** de instalación completa
- `network_monitor.sh` - Monitor de configuración de red  
- `network-monitor.service` - Servicio systemd para monitoreo de red

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

# Logs
sudo journalctl -u access_control.service -f
sudo journalctl -u network-monitor.service -f

# Estado de red
sudo ./network_monitor.sh status
```

## Configuración de Red

### Configuración TP-Link (Setup Inicial)

```bash
# Configuración automática
Interface: eth0
IP: 192.168.4.100/24
Gateway: 192.168.4.1
DNS: 8.8.8.8, 8.8.4.4
```

### Configuración Final (Post-WiFi)

```bash
# Configuración automática después de WiFi
Interface: eth0 - DHCP
Interface: wlan0 - WiFi del edificio
Interface: tailscale0 - Red Tailscale
```

## Monitoreo y Logs

### Logs del Sistema

- `/var/log/gateway_install.log` - Log de instalación
- `/var/log/network_monitor.log` - Log del monitor de red
- `journalctl -u access_control.service` - Log del servicio principal
- `journalctl -u network-monitor.service` - Log del monitor

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
   # Escanear redes disponibles
   sudo nmcli dev wifi rescan
   sudo nmcli dev wifi list
   
   # Intentar conexión manual
   sudo nmcli dev wifi connect "SSID" password "PASSWORD"
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

**Versión**: 10.1  
**Fecha**: 2024  
**Autor**: Sistema PCT  
**Repositorio**: https://github.com/lucassquirogaa/grupo