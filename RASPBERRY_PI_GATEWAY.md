# Raspberry Pi 3B+ Gateway Installation Script

## Overview

This repository contains a comprehensive, single-file installation script for setting up a Raspberry Pi 3B+ as a network gateway using an external TP-Link device as Access Point. The script follows the specific requirements for robust, secure, and automated installation.

## Key Features

### ✅ Requirements Compliance

- **Single Self-Contained Script**: Everything embedded in one bash file
- **No Internal AP Configuration**: Uses external TP-Link as AP (no hostapd/dnsmasq/wifi monitor)
- **Dependencies First**: Installs all dependencies while maintaining internet connectivity
- **Static IP After Dependencies**: Configures eth0 (192.168.4.100/24) only AFTER installing everything
- **Flask Web Portal**: Accessible at 0.0.0.0:8080 for WiFi configuration
- **DHCP Revert Script**: Auxiliary script to revert eth0 to DHCP after WiFi setup
- **Tailscale Integration**: Auto-install and authenticate with building-based hostname
- **Comprehensive Error Handling**: Clear messages, backups, and error detection
- **No External Dependencies**: No external files, templates, or unnecessary services

### 🔧 Technical Specifications

- **Target Platform**: Raspberry Pi 3B+ with Raspberry Pi OS Lite
- **Network Setup**: External TP-Link (e.g., MR3040) as AP
- **Static IP**: 192.168.4.100/24 (Gateway: 192.168.4.1)
- **Web Portal**: http://192.168.4.100:8080
- **Tailscale Auth Key**: Pre-configured with provided key
- **Building-Based Hostname**: Prompts for building identification

### 🏗️ Architecture

```
Internet → TP-Link (AP) → Raspberry Pi (Gateway) → Building WiFi
           192.168.4.1     192.168.4.100         DHCP after config
```

## Installation

### Prerequisites

- Raspberry Pi 3B+ with Raspberry Pi OS Lite
- Internet connectivity via ethernet
- TP-Link device configured as Access Point (192.168.4.1)

### Quick Start

1. **Download the script**:
   ```bash
   wget https://raw.githubusercontent.com/lucassquirogaa/grupo/main/install_raspberry_gateway.sh
   chmod +x install_raspberry_gateway.sh
   ```

2. **Run the installation**:
   ```bash
   sudo ./install_raspberry_gateway.sh
   ```

3. **Follow the interactive prompts**:
   - Enter building address/identification
   - Wait for dependency installation
   - Allow static IP configuration

4. **Access the web portal**:
   - Connect to TP-Link WiFi: "ControlsegConfig" (Password: "Grupo1598")
   - Open browser: http://192.168.4.100:8080
   - Configure building WiFi connection

5. **Automatic DHCP transition**:
   - System automatically switches ethernet to DHCP after WiFi configuration
   - Remote access available via Tailscale VPN

## What the Script Does

### Phase 1: Dependencies (Internet Required)
- ✅ Updates package repositories
- ✅ Installs Python 3, pip, venv, Flask, and system packages
- ✅ Installs Tailscale VPN client
- ✅ Creates Python virtual environment with required packages

### Phase 2: Configuration
- ✅ Prompts for building identification
- ✅ Creates comprehensive Flask web application
- ✅ Creates DHCP revert auxiliary script
- ✅ Sets up systemd services for automation

### Phase 3: Network Setup (After Dependencies)
- ✅ Configures Tailscale with building-based hostname
- ✅ Sets static IP on eth0 (192.168.4.100/24)
- ✅ Starts web portal service

### Phase 4: Validation
- ✅ Validates all components
- ✅ Tests Flask application startup
- ✅ Provides comprehensive status report

## Files Created

After installation, the following structure is created:

```
/opt/raspberry_gateway/
├── app.py                      # Flask web application
├── revert_to_dhcp.sh          # DHCP revert auxiliary script
├── venv/                      # Python virtual environment
├── gateway.db                 # SQLite database
├── building_address.txt       # Building identification
├── tailscale_info.txt         # Tailscale connection info
└── backup_location.txt        # Configuration backup location

/etc/systemd/system/
├── raspberry_gateway.service        # Main Flask service
└── ethernet_dhcp_revert.service     # DHCP revert service

/var/log/
├── raspberry_gateway_install.log    # Installation log
└── raspberry_gateway_app.log        # Application log
```

## Web Portal Features

### Main Dashboard
- **WiFi Status**: Shows current connection status
- **Network Information**: Displays ethernet and WiFi IPs
- **Setup Instructions**: Step-by-step configuration guide

### WiFi Configuration
- **Network Scanning**: Automatically detects available networks
- **Security Support**: WPA2/WPA3 and open networks
- **Connection Management**: Save and connect to building WiFi

### System API
- **Status Endpoint**: `/api/status` - System information JSON
- **WiFi Management**: Programmatic WiFi configuration
- **Tailscale Integration**: VPN status and connectivity

## DHCP Revert Mechanism

The auxiliary script (`revert_to_dhcp.sh`) automatically:

1. **Detects WiFi Connection**: Verifies wlan0 is connected and has IP
2. **Switches Ethernet to DHCP**: Changes eth0 from static to DHCP
3. **Validates New Configuration**: Ensures DHCP assignment is successful
4. **Self-Disables**: Prevents script from running again
5. **Logs Everything**: Comprehensive logging for troubleshooting

## Tailscale Integration

### Automatic Setup
- **Hostname Generation**: `gateway-{building-address}` format
- **Authentication**: Uses pre-configured auth key
- **Network Access**: Accepts subnet routes for building connectivity
- **Status Monitoring**: Real-time connection status via web portal

### Building-Based Hostnames
Examples:
- "Central Building 123" → `gateway-central-building-123`
- "North Branch" → `gateway-north-branch`
- "Av. Libertador 456" → `gateway-av-libertador-456`

## Management Commands

### Service Management
```bash
# Check main service status
sudo systemctl status raspberry_gateway.service

# Check DHCP revert service
sudo systemctl status ethernet_dhcp_revert.service

# View application logs
sudo journalctl -u raspberry_gateway.service -f

# Manual DHCP revert (if needed)
sudo /opt/raspberry_gateway/revert_to_dhcp.sh
```

### Network Status
```bash
# Check current IP assignments
ip addr show eth0
ip addr show wlan0

# Check Tailscale status
sudo tailscale status

# View installation log
sudo tail -f /var/log/raspberry_gateway_install.log
```

## Security Features

### System Hardening
- **Root Privilege Validation**: Ensures proper installation privileges
- **Configuration Backups**: Automatic backup of existing network configs
- **Systemd Security**: NoNewPrivileges, PrivateTmp for services
- **Error Handling**: Comprehensive error detection and reporting

### Network Security
- **Static IP Timing**: Only configured after dependency installation
- **WiFi Validation**: Verifies connectivity before DHCP transition
- **Tailscale VPN**: Secure remote access with authentication
- **Web Portal Authentication**: Secure WiFi configuration interface

## Troubleshooting

### Common Issues

1. **Cannot access web portal**:
   ```bash
   # Check if service is running
   sudo systemctl status raspberry_gateway.service
   
   # Check IP assignment
   ip addr show eth0
   
   # Restart service if needed
   sudo systemctl restart raspberry_gateway.service
   ```

2. **WiFi configuration not working**:
   ```bash
   # Check WiFi interface
   ip link show wlan0
   
   # Manual WiFi scan
   sudo nmcli dev wifi rescan
   sudo nmcli dev wifi list
   
   # Check wpa_supplicant status
   sudo wpa_cli -i wlan0 status
   ```

3. **DHCP revert not working**:
   ```bash
   # Check if WiFi is connected first
   ip addr show wlan0
   
   # Manually run revert script
   sudo /opt/raspberry_gateway/revert_to_dhcp.sh
   
   # Check revert service logs
   sudo journalctl -u ethernet_dhcp_revert.service
   ```

4. **Tailscale connection issues**:
   ```bash
   # Check Tailscale status
   sudo tailscale status
   
   # Re-authenticate if needed
   sudo tailscale up --authkey="..." --hostname="gateway-building"
   
   # Check Tailscale logs
   sudo journalctl -u tailscaled
   ```

### Log Files
- **Installation**: `/var/log/raspberry_gateway_install.log`
- **Application**: `/var/log/raspberry_gateway_app.log`
- **DHCP Revert**: `/var/log/ethernet_dhcp_revert.log`
- **Systemd Services**: `sudo journalctl -u raspberry_gateway.service`

## Testing

A comprehensive test suite is included:

```bash
# Run all tests
./test_raspberry_gateway.sh

# Test results show:
# - Script syntax validation
# - Configuration value verification
# - Flask application structure
# - Security compliance
# - Self-contained nature
# - Installation sequence validation
```

## Hardware Compatibility

### Recommended Setup
- **Raspberry Pi 3B+**: Optimized for this hardware
- **Samsung Pro Endurance 64GB**: Recommended SD card
- **TP-Link MR3040**: External Access Point
- **Ethernet Connection**: Required for initial setup

### Network Requirements
- **Internet Access**: Required during dependency installation
- **TP-Link Configuration**: Must be set as AP (192.168.4.1)
- **Building WiFi**: Target network for permanent connection

## Version Information

- **Script Version**: 1.0
- **Target OS**: Raspberry Pi OS Lite
- **Python Version**: 3.7+
- **Flask Version**: 2.3.3
- **Tailscale**: Latest stable

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review log files for detailed error information
3. Ensure all prerequisites are met
4. Verify network connectivity and configuration

## License

This project is part of the grupo repository and follows the same licensing terms.