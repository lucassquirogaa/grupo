# Guía de Uso - Gateway v10.3

## Características Principales

### 🚀 **NUEVA: Configuración de Red Diferida**

⚠️ **CAMBIO IMPORTANTE**: A partir de la v10.3, la configuración de red se aplica **DESPUÉS del reinicio** para evitar desconexiones SSH durante la instalación.

#### Flujo de Instalación:
1. **Durante la Instalación**: Se prepara la configuración de red sin aplicar cambios
2. **Mensaje Claro**: Se informa que los cambios se aplicarán después del reinicio
3. **Reinicio**: Se ejecuta `sudo reboot` cuando esté listo
4. **Aplicación Automática**: La configuración se aplica automáticamente al iniciar

#### Beneficios:
- ✅ SSH no se desconecta durante la instalación
- ✅ Instalación completamente exitosa sin interrupciones
- ✅ Control total del momento del reinicio
- ✅ Logs completos de todo el proceso

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

### 2. 📶 Access Point Automático (Aplicado después del reinicio)

Cuando **NO** hay WiFi configurado, se programa la creación automática de:

**Configuración del AP:**
- **SSID**: `ControlsegConfig`
- **Contraseña**: `Grupo1598`
- **IP Gateway**: `192.168.4.100`
- **Red**: `192.168.4.0/24`
- **DNS**: `8.8.8.8`

**Para usar después del reinicio:**
1. Reiniciar: `sudo reboot`
2. Buscar red WiFi `ControlsegConfig`
3. Conectar con contraseña `Grupo1598`
4. Ir a `http://192.168.4.100:8080`
5. Configurar WiFi principal desde el portal

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

3. **PASO 3**: Configuración de red (DIFERIDA)
   - Preparación sin aplicar cambios inmediatamente
   - Configuración de servicio para aplicar después del reinicio
   - AP si no hay WiFi / DHCP si hay WiFi (aplicado tras reinicio)

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

### Escenario 1: Instalación Nueva (Sin WiFi) - CON CONFIGURACIÓN DIFERIDA

```
🔧 Durante la instalación:
   ✅ Instalación detecta: No hay WiFi configurado
   ✅ Se prepara configuración: IP estática + Access Point
   ⚠️  NO se aplican cambios inmediatamente
   📋 Mensaje: Configuración se aplicará después del reinicio

🔄 Después de 'sudo reboot':
   ✅ Se aplica IP estática: 192.168.4.100
   ✅ Se crea Access Point: ControlsegConfig
   📱 Portal disponible: http://192.168.4.100:8080

Usuario:
1. Conecta a ControlsegConfig (password: Grupo1598)
2. Va a http://192.168.4.100:8080
3. Configura WiFi del edificio
4. Sistema cambia automáticamente a DHCP
```

### Escenario 2: Instalación con WiFi Existente - CON CONFIGURACIÓN DIFERIDA

```
🔧 Durante la instalación:
   ✅ Instalación detecta: WiFi ya configurado
   ✅ Se prepara configuración: DHCP en ethernet
   ⚠️  NO se aplican cambios inmediatamente
   📋 Mensaje: Configuración se aplicará después del reinicio

🔄 Después de 'sudo reboot':
   ✅ Se aplica configuración DHCP
   🌐 IP asignada automáticamente por router
   📶 No se crea Access Point
   🔒 Tailscale activo con hostname personalizado
```

## Verificación Post-Instalación

### Comandos de Estado:

```bash
# Estado completo del sistema
gateway-status

# Estado de servicios específicos
systemctl status access_control.service
systemctl status network-monitor.service
systemctl status network-config-applier.service

# Verificar si hay configuración de red pendiente
ls -la /opt/gateway/pending_network_config/

# Ver logs de aplicación de configuración de red
journalctl -u network-config-applier.service
tail -f /var/log/network_config_applier.log

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