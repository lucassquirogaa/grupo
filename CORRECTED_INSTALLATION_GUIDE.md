# Corrected Raspberry Pi Gateway Installation Script

## Overview

The `install_raspberry_gateway.sh` script has been **corrected** to follow safe network configuration practices as specified in the requirements. The script now guarantees that all dependencies, web portal, Tailscale, and internet-requiring components are installed **BEFORE** making any network changes that could break connectivity.

## Key Corrections Made

### ✅ Problem Solved: Safe Installation Flow

**BEFORE (Problematic):**
- Network configuration (static IP) was applied during installation
- Could break SSH/internet connectivity before dependencies were installed
- SystemD services that modify network were enabled immediately
- No user confirmation before breaking changes
- Limited backup and recovery options

**AFTER (Corrected):**
- **ALL dependencies installed FIRST** while maintaining internet connectivity
- **User confirmation required** before network changes
- **Three configuration options**: immediate, deferred, or manual
- **Comprehensive backup** with automatic restore scripts
- **Clear phase separation** for maximum safety

### ✅ Three-Phase Safe Installation Process

#### **FASE 1: Dependencies Installation (Safe - No Network Changes)**
1. System dependencies (Python, pip, curl, etc.)
2. Python virtual environment setup
3. Tailscale installation and configuration
4. Building identification collection
5. Flask application creation
6. SystemD service preparation (without enabling network-modifying services)

#### **FASE 2: Network Configuration (User Choice - Potentially Breaking)**
- **Comprehensive backup** of all network configurations
- **User prompt** with three options:
  1. **Apply NOW** - Configure static IP immediately (recommended for local installation)
  2. **Defer to REBOOT** - Apply after system restart (safe for SSH remote installation)
  3. **Manual LATER** - Show instructions for manual configuration

#### **FASE 3: Validation and Completion**
- Service validation and startup
- Installation verification
- Comprehensive status reporting

## User Experience Improvements

### ⚠️ User Warning and Confirmation

```bash
============================================
⚠️  CONFIGURACIÓN DE RED
============================================

TODAS las dependencias, Tailscale y servicios han sido
instalados exitosamente manteniendo la conectividad actual.

AHORA es necesario configurar la IP estática para el
setup inicial con TP-Link:

🔗 IP estática: 192.168.4.100
🌐 Gateway: 192.168.4.1
📡 Interface: eth0

⚠️  ADVERTENCIA:
Este cambio puede cortar la conexión SSH/network actual.
El sistema será accesible después en la nueva IP.

Opciones:
1. Aplicar AHORA (recomendado si instalación local)
2. Diferir hasta después del REINICIO (recomendado para SSH remoto)
3. Configurar MANUALMENTE más tarde

Elija una opción (1/2/3):
```

### 📋 Manual Configuration Instructions

When option 3 is selected, complete instructions are provided:

```bash
============================================
📋 INSTRUCCIONES PARA CONFIGURACIÓN MANUAL
============================================

Para aplicar la configuración de red manualmente más tarde:

1. Ejecutar el script aplicador:
   sudo /opt/raspberry_gateway/apply_network_config.sh

2. O reiniciar el sistema para aplicación automática:
   sudo reboot

3. O configurar manualmente la IP estática:
   # Con NetworkManager:
   sudo nmcli connection modify "Wired connection 1" \
     ipv4.method manual \
     ipv4.addresses "192.168.4.100/24" \
     ipv4.gateway "192.168.4.1" \
     ipv4.dns "8.8.8.8,8.8.4.4"
   sudo nmcli connection up "Wired connection 1"

Después de la configuración:
🌐 Portal web: http://192.168.4.100:8080
🔧 Configurar WiFi desde el portal web
```

## Technical Implementation Details

### 🔧 Deferred Network Configuration

The script creates an auxiliary network configuration applier that can run safely after reboot:

**Created Files:**
- `/opt/raspberry_gateway/apply_network_config.sh` - Network configuration applier
- `/opt/raspberry_gateway/pending_network_config/` - Configuration to apply
- `/etc/systemd/system/network-config-applier.service` - SystemD service for auto-application

**Safety Features:**
- Only enables network-modifying services AFTER configuration is complete
- Creates backup with automatic restore script
- Validates configuration before marking as complete
- Self-disabling to prevent re-execution

### 💾 Comprehensive Backup System

**Backup Contents:**
- All network configuration files (`/etc/network/interfaces`, `/etc/dhcpcd.conf`, etc.)
- NetworkManager configurations
- Current network state (IP addresses, routes, DNS)
- SystemD network configurations

**Backup Features:**
- Automatic restore script generation
- Detailed backup summary with timestamps
- Current network state snapshot
- Recovery instructions

**Generated Files:**
```
/root/gateway_config_backup_[timestamp]/
├── interfaces                    # Network interfaces backup
├── dhcpcd.conf                  # DHCP client daemon config
├── wpa_supplicant.conf          # WiFi configuration
├── NetworkManager/              # NetworkManager configs
├── current_ip_addresses.txt     # Current IP state
├── current_routes.txt           # Current routing table
├── current_dns.txt              # Current DNS configuration
├── restore_network.sh           # Automatic restore script
└── backup_summary.txt           # Human-readable summary
```

### 🛡️ SystemD Services Safety

**Main Flask Service:**
- Always enabled (no network impact)
- Starts immediately for current connectivity

**DHCP Revert Service:**
- Created but **NOT enabled** during installation
- Only enabled AFTER static IP is successfully configured
- Prevents interference with installation process

**Network Config Applier Service:**
- Only enabled when deferred configuration is chosen
- Self-disabling after successful execution
- Runs once after reboot to apply pending changes

## Installation Options and Use Cases

### Option 1: Apply NOW (Local Installation)
**Best for:**
- Local installation with direct access to Raspberry Pi
- Installation via monitor and keyboard
- When immediate configuration is acceptable

**Process:**
1. Install all dependencies
2. Apply static IP immediately
3. Enable DHCP revert service
4. Start all services
5. Ready for immediate use

### Option 2: Defer to REBOOT (Remote SSH Installation)
**Best for:**
- Remote installation via SSH
- When maintaining current connectivity is critical
- Automated deployment scenarios

**Process:**
1. Install all dependencies
2. Prepare network configuration for application after reboot
3. Enable network-config-applier service
4. User reboots when ready
5. Configuration applied automatically on boot

### Option 3: Manual LATER (Custom Scenarios)
**Best for:**
- Custom deployment environments
- When network configuration timing needs to be controlled externally
- Integration with configuration management systems

**Process:**
1. Install all dependencies
2. Prepare configuration scripts
3. Provide detailed manual instructions
4. User applies configuration when ready

## Validation and Testing

### ✅ Comprehensive Test Suite

The `test_corrected_gateway.sh` script validates:

**Safety Validations:**
- Dependencies installed before network changes
- Tailscale configured while internet available
- No immediate enabling of network-modifying services
- User confirmation prompts present

**Functional Validations:**
- All deferred configuration functions present
- Three configuration options implemented
- Comprehensive backup system
- Clear phase separation
- Manual configuration instructions

**Technical Validations:**
- Script syntax correctness
- Network applier script creation
- Service configuration correctness
- Installation flow ordering

### 🧪 Test Results
```bash
$ bash test_corrected_gateway.sh

============================================
TEST SUMMARY
============================================
Total tests: 13
Passed: 13
Failed: 0

✓ All tests passed! Corrected installation script is ready.

Key improvements validated:
• Dependencies installed before network changes
• User confirmation required before network changes  
• Three configuration options (immediate/deferred/manual)
• Comprehensive backup and restore system
• Clear phase separation for maximum safety
• Tailscale configured while internet is available
```

## Usage Examples

### Remote SSH Installation (Recommended)
```bash
# 1. SSH to Raspberry Pi
ssh pi@raspberrypi.local

# 2. Download and run installer
wget https://raw.githubusercontent.com/lucassquirogaa/grupo/main/install_raspberry_gateway.sh
chmod +x install_raspberry_gateway.sh
sudo ./install_raspberry_gateway.sh

# 3. When prompted, choose option 2 (defer to reboot)
# 4. Installation completes with all dependencies installed
# 5. SSH connection remains stable
# 6. Reboot when ready: sudo reboot
# 7. Access at new IP after reboot: http://192.168.4.100:8080
```

### Local Installation
```bash
# 1. Connect monitor and keyboard to Raspberry Pi
# 2. Run installer locally
sudo ./install_raspberry_gateway.sh

# 3. When prompted, choose option 1 (apply now)
# 4. Network configuration applied immediately
# 5. Connect to TP-Link WiFi and access portal
```

### Automated Deployment
```bash
# Use environment variable to select option
export GATEWAY_NETWORK_CONFIG=defer
sudo ./install_raspberry_gateway.sh

# Or use non-interactive mode
echo "2" | sudo ./install_raspberry_gateway.sh
```

## Migration from Previous Version

If upgrading from the problematic version:

1. **Backup current system:**
   ```bash
   sudo cp -r /opt/raspberry_gateway /opt/raspberry_gateway.backup
   ```

2. **Run corrected installer:**
   ```bash
   sudo ./install_raspberry_gateway.sh
   ```

3. **Choose deferred configuration** to avoid disruption

4. **Reboot when ready** to apply new configuration

## Troubleshooting

### Installation Issues

**Problem:** Script stops with "No internet connectivity"
**Solution:** Run deferred configuration option, ensure WiFi/ethernet works first

**Problem:** SSH connection lost during installation
**Solution:** Should not happen with corrected script. Use deferred option for remote installations.

### Network Configuration Issues

**Problem:** Cannot access portal after configuration
**Solution:** Use backup restore script:
```bash
sudo /root/gateway_config_backup_[timestamp]/restore_network.sh
```

**Problem:** Need to change configuration after installation
**Solution:** Run network applier manually:
```bash
sudo /opt/raspberry_gateway/apply_network_config.sh
```

### Service Issues

**Problem:** Flask service not starting
**Solution:** Check logs and restart:
```bash
sudo journalctl -u raspberry_gateway.service
sudo systemctl restart raspberry_gateway.service
```

## File Locations

**Main Installation:**
- `/opt/raspberry_gateway/` - Main configuration directory
- `/opt/raspberry_gateway/app.py` - Flask web application
- `/opt/raspberry_gateway/venv/` - Python virtual environment

**Network Configuration:**
- `/opt/raspberry_gateway/apply_network_config.sh` - Network applier script
- `/opt/raspberry_gateway/pending_network_config/` - Deferred configuration
- `/opt/raspberry_gateway/backup_location.txt` - Backup directory reference

**SystemD Services:**
- `/etc/systemd/system/raspberry_gateway.service` - Main Flask service
- `/etc/systemd/system/ethernet_dhcp_revert.service` - DHCP revert service
- `/etc/systemd/system/network-config-applier.service` - Network config applier

**Logs:**
- `/var/log/raspberry_gateway_install.log` - Installation log
- `/var/log/raspberry_gateway_app.log` - Application log
- `/var/log/network_config_applier.log` - Network configuration log

## Security Considerations

**Backup Security:**
- Backups stored in `/root/` with proper permissions
- Network credentials may be stored in backups
- Automatic cleanup of old backups recommended

**Service Security:**
- SystemD services run with security hardening
- `NoNewPrivileges=true` and `PrivateTmp=true`
- Services only enabled when needed

**Network Security:**
- Static IP only applied when explicitly confirmed
- Original network configuration always backed up
- Restore scripts provided for quick recovery

## Summary

The corrected `install_raspberry_gateway.sh` script successfully addresses all the requirements:

✅ **Dependencies installed FIRST** before touching network  
✅ **No network-modifying services** enabled before final step  
✅ **User confirmation** before network changes with warning  
✅ **Option to defer** to manual execution later  
✅ **Clear backups and logs** of each network change  
✅ **Maximum robustness** to avoid connection loss  
✅ **Well-documented** safe flow  

The script is now **production-ready** and safe for both local and remote installations.