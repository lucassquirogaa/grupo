# Guía de Uso - Gateway v10.3

## Nuevas Características Implementadas

### 1. 🏢 Identificación de Edificio

Durante la instalación, el sistema solicita identificar la ubicación:

```
============================================
IDENTIFICACIÓN DEL EDIFICIO
============================================
Por favor, ingrese la dirección o nombre
identificatorio de este edificio.

Ejemplos:
  - Edificio Central 123
  - Sucursal Norte
  - Av. Libertador 456

Dirección/Nombre del edificio: _
```

**Características:**
- Mínimo 3 caracteres requeridos
- Se guarda en `/opt/gateway/building_address.txt`
- Se usa para generar hostname único en Tailscale
- Permite cambio posterior si ya existe

### 2. 📶 Access Point Automático

Cuando **NO** hay WiFi configurado, se crea automáticamente:

**Configuración del AP:**
- **SSID**: `ControlsegConfig`
- **Contraseña**: `Grupo1598`
- **IP Gateway**: `192.168.4.100`
- **Red**: `192.168.4.0/24`
- **DNS**: `8.8.8.8`

**Para usar:**
1. Buscar red WiFi `ControlsegConfig`
2. Conectar con contraseña `Grupo1598`
3. Ir a `http://192.168.4.100:8080`
4. Configurar WiFi principal desde el portal

### 3. 🔒 Tailscale Integrado

Instalación y configuración automática:

**Proceso:**
1. Descarga script oficial: `curl -fsSL https://tailscale.com/install.sh | sh`
2. Autentica con clave: `tskey-auth-kpNN1bCPr321CNTRL-QnTaeC2BWaCJE5TY9RJEaCDns9BEzpDZb`
3. Hostname basado en edificio: `"Edificio Central" → "gateway-edificio-central"`
4. Acepta rutas automáticamente

**Resultado:**
- IP Tailscale asignada automáticamente
- Hostname único y reconocible
- Acceso remoto inmediato
- Información guardada en `/opt/gateway/network_info.txt`

### 4. 🛠️ Limpieza de Red Robusta

Antes de configurar la red, se limpia:

**Limpieza automática:**
- ✅ Rutas estáticas conflictivas en `192.168.4.0/24`
- ✅ Múltiples default gateways
- ✅ IPs duplicadas en `eth0`
- ✅ Configuraciones de red obsoletas

### 5. 🔍 Detección WiFi Mejorada

Verificación más estricta de conectividad:

**Verificaciones:**
- ✅ Conexiones WiFi configuradas en NetworkManager
- ✅ Conexiones WiFi actualmente activas
- ✅ Interfaz `wlan0` UP con IP asignada
- ✅ Conectividad real de red

## Flujo de Instalación Completo

```bash
sudo ./install_gateway_v10.sh
```

### Paso a Paso:

1. **PASO 1**: Instalación de dependencias
   - Incluye: `hostapd`, `dnsmasq`, `iptables`
   - Para funcionalidad de Access Point

2. **PASO 2**: Identificación del edificio
   - Prompt interactivo para ubicación
   - Validación y almacenamiento

3. **PASO 3**: Configuración de red
   - Limpieza de configuraciones conflictivas
   - AP si no hay WiFi / DHCP si hay WiFi

4. **PASO 4**: Entorno Python
   - Virtual environment y dependencias

5. **PASO 5**: Tailscale
   - Instalación automática
   - Configuración con hostname personalizado

6. **PASO 6**: Servicio principal
   - Sistema de control de acceso

7. **PASO 7**: Optimizaciones Raspberry Pi
   - Configuraciones específicas de hardware

8. **PASO 8**: Monitoreo 24/7
   - Telegram, watchdog, health monitoring

## Escenarios de Uso

### Escenario 1: Instalación Nueva (Sin WiFi)

```
🔧 Instalación detecta: No hay WiFi configurado
📶 Se crea Access Point: ControlsegConfig
🌐 IP ethernet: 192.168.4.100
📱 Portal: http://192.168.4.100:8080

Usuario:
1. Conecta a ControlsegConfig (password: Grupo1598)
2. Va a http://192.168.4.100:8080
3. Configura WiFi del edificio
4. Sistema cambia automáticamente a DHCP
```

### Escenario 2: Instalación con WiFi Existente

```
🔧 Instalación detecta: WiFi ya configurado
🌐 Configura ethernet en DHCP
📶 No crea Access Point
🔒 Instala Tailscale con hostname personalizado
```

## Verificación Post-Instalación

### Comandos de Estado:

```bash
# Estado completo del sistema
gateway-status

# Estado de servicios específicos
systemctl status access_control.service
systemctl status network-monitor.service

# Información de Tailscale
tailscale status
tailscale ip

# Información de edificio
cat /opt/gateway/building_address.txt

# Información de red guardada
cat /opt/gateway/network_info.txt
```

### Archivos de Configuración:

- `/opt/gateway/building_address.txt` - Identificación del edificio
- `/opt/gateway/network_info.txt` - Información de red (Tailscale IP, hostname)
- `/var/log/gateway_install.log` - Log completo de instalación

## Solución de Problemas

### Access Point no funciona:
```bash
# Verificar interfaz wlan0
ip link show wlan0

# Verificar NetworkManager
systemctl status NetworkManager

# Verificar conexión AP
nmcli connection show ControlsegConfig
```

### Tailscale no conecta:
```bash
# Estado de Tailscale
tailscale status

# Reintentar autenticación
tailscale up --authkey=tskey-auth-kpNN1bCPr321CNTRL-QnTaeC2BWaCJE5TY9RJEaCDns9BEzpDZb

# Logs del servicio
journalctl -u tailscaled -f
```

### Problemas de red:
```bash
# Limpiar configuración manualmente
sudo nmcli connection delete "Wired connection 1"
sudo nmcli connection add type ethernet ifname eth0

# Verificar rutas
ip route show

# Limpiar rutas conflictivas
sudo ip route del 192.168.4.0/24 via [gateway]
```