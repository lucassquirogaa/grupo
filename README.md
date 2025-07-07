# Gateway Installation Script v10.1

## Descripción

Sistema de instalación y configuración automática de gateway para control de acceso PCT con soporte para configuración de red automática.

### Características Principales

- **Configuración automática de IP estática** para setup inicial con modem TP-Link
- **Detección automática de WiFi** configurado
- **Cambio automático a DHCP** después de configurar WiFi exitosamente
- **Monitoreo continuo de red** para transiciones automáticas
- **Portal web integrado** en puerto 8080 para configuración
- **Logs detallados** para troubleshooting
- **Compatibilidad con NetworkManager** y sistemas legacy

## Flujo de Trabajo

### 1. Instalación Inicial

```bash
sudo ./install_gateway_v10.sh
```

### 2. Configuración de Red Automática

1. **Sin WiFi configurado**: 
   - IP estática: `192.168.4.100/24`
   - Gateway: `192.168.4.1`
   - Acceso web: `http://192.168.4.100:8080`

2. **Con WiFi configurado**:
   - Ethernet: DHCP automático
   - WiFi: Conexión a red del edificio
   - Tailscale: Acceso remoto

### 3. Transición Automática

El script `network_monitor.sh` detecta cuando se configura WiFi exitosamente y cambia automáticamente ethernet de IP estática a DHCP.

## Archivos del Sistema

### Scripts Principales

- `install_gateway_v10.sh` - Script principal de instalación
- `network_monitor.sh` - Monitor de configuración de red
- `network-monitor.service` - Servicio systemd para monitoreo

### Aplicación Web

- `pi@raspberrypi~access_control_syste.txt` - Aplicación Flask con funcionalidades de red

### APIs de Red Añadidas

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