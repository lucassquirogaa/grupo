# Gateway Installation Quick Start Guide

## Scenario: Setting up Raspberry Pi with TP-Link Modem

### Step 1: Initial Setup
```bash
# Connect Raspberry Pi ethernet to TP-Link modem
# TP-Link should be configured as Access Point (192.168.4.1)

# Download and extract installation files
git clone https://github.com/lucassquirogaa/grupo.git
cd grupo

# Validate installation package
./validate_installation.sh
```

### Step 2: Run Installation (New Deferred Network Configuration)
```bash
# Execute installation (requires sudo)
sudo ./install_gateway_v10.sh
```

**Expected Output:**
```
============================================
Gateway Installation Script v10.3
Sistema Gateway 24/7 - Raspberry Pi 3B+
============================================
[INFO] Iniciando instalación del Sistema Gateway 24/7 v10.3
=== PASO 1: Instalando dependencias ===
[INFO] Instalando dependencias del sistema...
[SUCCESS] Dependencias instaladas correctamente
=== PASO 2: Identificación del edificio ===
[INFO] Prompt para identificar ubicación del edificio...
=== PASO 3: Configurando red ===
[INFO] Iniciando configuración de red diferida...
[INFO] Preparando configuración de red diferida...
[INFO] WiFi no configurado - preparando configuración estática + Access Point
[SUCCESS] Configuración de red diferida preparada exitosamente
=====================================
CONFIGURACIÓN DE RED PREPARADA
=====================================
⚠️  Los cambios de red se aplicarán después del REINICIO
🔄 La configuración se aplicará automáticamente al iniciar
📋 Configuración programada: IP estática + Access Point
🔗 IP ethernet: 192.168.4.100 (después del reinicio)
📶 WiFi AP: ControlsegConfig (después del reinicio)
🌐 Portal web: http://192.168.4.100:8080 (después del reinicio)
=====================================
...
⚠️  REINICIO OBLIGATORIO PARA APLICAR CONFIGURACIÓN
========================================
🔄 Los cambios de red se aplicarán automáticamente
💡 La conexión SSH actual se mantendrá hasta reiniciar
⏰ Ejecute el reinicio cuando esté listo:
   sudo reboot
========================================
```

### Step 3: Reboot to Apply Network Configuration
```bash
# When ready, reboot to apply network changes
sudo reboot
```

**What happens during reboot:**
- Network configuration is applied automatically
- Static IP 192.168.4.100 is configured
- Access Point "ControlsegConfig" is created
- Web portal becomes available at http://192.168.4.100:8080

### Step 4: Access Web Portal (After Reboot)
```
URL: http://192.168.4.100:8080
Default credentials: [check existing system docs]
```

### Step 4: Configure WiFi
1. Navigate to "Configuración" → "WiFi"
2. Scan for building WiFi networks
3. Connect to building WiFi with credentials
4. **Automatic transition**: System detects WiFi connection and switches ethernet to DHCP

**Expected Network State After WiFi:**
```
eth0: DHCP (building network)
wlan0: Connected to building WiFi
tailscale0: Tailscale VPN (for remote access)
```

### Step 5: Verify Installation
```bash
# Check service status
sudo systemctl status access_control.service
sudo systemctl status network-monitor.service
sudo systemctl status network-config-applier.service

# Check if network configuration was applied
sudo journalctl -u network-config-applier.service

# Check network configuration
curl -s http://localhost:8080/api/system/network-status | jq

# View logs
sudo journalctl -u access_control.service -f
sudo journalctl -u network-monitor.service -f
tail -f /var/log/network_config_applier.log
```

## Troubleshooting

### Issue: Can't access web portal at 192.168.4.100 after reboot
```bash
# Check if network configuration was applied
sudo systemctl status network-config-applier.service
sudo journalctl -u network-config-applier.service

# Check IP assignment
ip addr show eth0

# Check if pending configuration exists
ls -la /opt/gateway/pending_network_config/

# Check service status
sudo systemctl status access_control.service

# Restart services if needed
sudo systemctl restart access_control.service
```

### Issue: Network configuration not applied after reboot
```bash
# Check if service ran
sudo journalctl -u network-config-applier.service

# Check for pending configuration
ls -la /opt/gateway/pending_network_config/

# Manually run the applier (for debugging)
sudo /opt/gateway/network_config_applier.sh

# Check applier logs
tail -f /var/log/network_config_applier.log
```

### Issue: Network doesn't switch to DHCP after WiFi
```bash
# Check network monitor service
sudo systemctl status network-monitor.service

# Manual force to DHCP
curl -X POST http://localhost:8080/api/system/network-force-dhcp

# Check monitor logs
sudo tail -f /var/log/network_monitor.log
```

### Issue: WiFi connection fails
```bash
# Manual WiFi scan
sudo nmcli dev wifi rescan
sudo nmcli dev wifi list

# Manual WiFi connection
sudo nmcli dev wifi connect "SSID" password "PASSWORD"
```

## File Structure After Installation

```
/opt/gateway/                        # Main installation directory
├── venv/                           # Python virtual environment
├── app.py                          # Flask application (copied from repo)
├── network_monitor.sh              # Network monitoring script
├── instance/                       # Configuration files
│   ├── database.db                # SQLite database
│   ├── auto_backup_config.json    # Backup configuration
│   └── system_settings.json       # System settings
└── logs/                           # Application logs

/etc/systemd/system/                # System services
├── access_control.service         # Main application service
└── network-monitor.service        # Network monitoring service

/var/log/                           # System logs
├── gateway_install.log            # Installation log
└── network_monitor.log            # Network monitor log
```

## Services Management

```bash
# Start services
sudo systemctl start access_control.service
sudo systemctl start network-monitor.service

# Stop services
sudo systemctl stop access_control.service
sudo systemctl stop network-monitor.service

# Enable auto-start on boot
sudo systemctl enable access_control.service
sudo systemctl enable network-monitor.service

# View service logs
sudo journalctl -u access_control.service -f
sudo journalctl -u network-monitor.service -f
```

This installation process solves the original problem by providing a fixed IP (192.168.4.100) for initial configuration with the TP-Link modem, then automatically transitioning to DHCP once WiFi is configured for the building network.