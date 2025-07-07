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

### Step 2: Run Installation
```bash
# Execute installation (requires sudo)
sudo ./install_gateway_v10.sh
```

**Expected Output:**
```
============================================
Gateway Installation Script v10.1
Sistema de Control de Acceso PCT
============================================
[INFO] Iniciando instalación del gateway v10.1
=== PASO 1: Instalando dependencias ===
[INFO] Instalando dependencias del sistema...
[SUCCESS] Dependencias instaladas correctamente
=== PASO 2: Configurando red ===
[INFO] Verificando configuración WiFi existente...
[INFO] No se encontró configuración WiFi activa
[INFO] WiFi no configurado - usando IP estática para setup inicial
[INFO] Configurando IP estática en eth0: 192.168.4.100/24
[SUCCESS] IP estática configurada correctamente
=====================================
CONFIGURACIÓN INICIAL COMPLETADA
=====================================
IP estática configurada: 192.168.4.100
Acceda al portal web en: http://192.168.4.100:8080
Configure WiFi desde el portal web
=====================================
```

### Step 3: Access Web Portal
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

# Check network configuration
curl -s http://localhost:8080/api/system/network-status | jq

# View logs
sudo journalctl -u access_control.service -f
sudo journalctl -u network-monitor.service -f
```

## Troubleshooting

### Issue: Can't access web portal at 192.168.4.100
```bash
# Check IP assignment
ip addr show eth0

# Check service status
sudo systemctl status access_control.service

# Restart services if needed
sudo systemctl restart access_control.service
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