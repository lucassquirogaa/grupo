#!/bin/bash

# ============================================
# Service Installation Script
# Sistema Gateway 24/7
# ============================================
# Installs and configures all monitoring services

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="/opt/gateway"
SERVICE_DIR="/etc/systemd/system"
LOG_FILE="/var/log/service_install.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_message "INFO" "$1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS" "$1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    log_message "WARN" "$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR" "$1"
}

# ============================================
# INSTALL PYTHON DEPENDENCIES
# ============================================

install_python_dependencies() {
    log_info "Installing Python dependencies for monitoring services..."
    
    # Update package list
    apt-get update
    
    # Install system packages
    apt-get install -y \
        python3-pip \
        python3-venv \
        python3-psutil \
        python3-requests \
        curl \
        wget \
        jq \
        htop \
        iotop \
        nethogs
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "$GATEWAY_DIR/venv" ]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv "$GATEWAY_DIR/venv"
    fi
    
    # Activate virtual environment and install packages
    source "$GATEWAY_DIR/venv/bin/activate"
    
    pip install --upgrade pip
    pip install \
        psutil \
        requests \
        schedule \
        python-telegram-bot
    
    deactivate
    
    log_success "Python dependencies installed"
}

# ============================================
# CREATE SYSTEMD SERVICES
# ============================================

create_telegram_service() {
    log_info "Creating Telegram notifier service..."
    
    cat > "$SERVICE_DIR/telegram-notifier.service" << EOF
[Unit]
Description=Telegram Notifier Service - Gateway 24/7
Documentation=Sistema Gateway 24/7
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$GATEWAY_DIR/venv/bin/python $GATEWAY_DIR/services/telegram_notifier.py
Restart=always
RestartSec=10
User=root
WorkingDirectory=$GATEWAY_DIR

# Resource limits for Raspberry Pi 3B+
MemoryMax=50M
CPUQuota=10%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log /tmp /opt/gateway

# Environment
Environment=PYTHONPATH=$GATEWAY_DIR
Environment=PYTHONUNBUFFERED=1

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=telegram-notifier

[Install]
WantedBy=multi-user.target
EOF

    log_success "Telegram notifier service created"
}

create_tailscale_monitor_service() {
    log_info "Creating Tailscale monitor service..."
    
    cat > "$SERVICE_DIR/tailscale-monitor.service" << EOF
[Unit]
Description=Tailscale Monitor Service - Gateway 24/7
Documentation=Sistema Gateway 24/7
After=network-online.target tailscaled.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$GATEWAY_DIR/venv/bin/python $GATEWAY_DIR/services/tailscale_monitor.py
Restart=always
RestartSec=15
User=root
WorkingDirectory=$GATEWAY_DIR

# Resource limits for Raspberry Pi 3B+
MemoryMax=30M
CPUQuota=5%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log /tmp /opt/gateway

# Environment
Environment=PYTHONPATH=$GATEWAY_DIR
Environment=PYTHONUNBUFFERED=1

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tailscale-monitor

[Install]
WantedBy=multi-user.target
EOF

    log_success "Tailscale monitor service created"
}

create_system_watchdog_service() {
    log_info "Creating system watchdog service..."
    
    cat > "$SERVICE_DIR/system-watchdog.service" << EOF
[Unit]
Description=System Watchdog Service - Gateway 24/7
Documentation=Sistema Gateway 24/7
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$GATEWAY_DIR/venv/bin/python $GATEWAY_DIR/services/system_watchdog.py
Restart=always
RestartSec=10
User=root
WorkingDirectory=$GATEWAY_DIR

# Resource limits for Raspberry Pi 3B+
MemoryMax=40M
CPUQuota=8%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log /tmp /opt/gateway /proc/sys/vm

# Environment
Environment=PYTHONPATH=$GATEWAY_DIR
Environment=PYTHONUNBUFFERED=1

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=system-watchdog

[Install]
WantedBy=multi-user.target
EOF

    log_success "System watchdog service created"
}

create_health_monitor_service() {
    log_info "Creating health monitor service..."
    
    cat > "$SERVICE_DIR/health-monitor.service" << EOF
[Unit]
Description=Health Monitor Service - Gateway 24/7
Documentation=Sistema Gateway 24/7
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$GATEWAY_DIR/venv/bin/python $GATEWAY_DIR/services/health_monitor.py
Restart=always
RestartSec=15
User=root
WorkingDirectory=$GATEWAY_DIR

# Resource limits for Raspberry Pi 3B+
MemoryMax=60M
CPUQuota=10%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log /tmp /opt/gateway

# Environment
Environment=PYTHONPATH=$GATEWAY_DIR
Environment=PYTHONUNBUFFERED=1

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=health-monitor

[Install]
WantedBy=multi-user.target
EOF

    log_success "Health monitor service created"
}

create_weekly_report_service() {
    log_info "Creating weekly report service..."
    
    # Create timer for weekly reports
    cat > "$SERVICE_DIR/weekly-report.service" << EOF
[Unit]
Description=Weekly Report Generator - Gateway 24/7
Documentation=Sistema Gateway 24/7

[Service]
Type=oneshot
ExecStart=$GATEWAY_DIR/venv/bin/python -c "
import sys
sys.path.insert(0, '$GATEWAY_DIR/services')
from health_monitor import HealthMonitor
from telegram_notifier import TelegramNotifier

# Generate and send weekly report
monitor = HealthMonitor()
report = monitor.generate_weekly_report()

notifier = TelegramNotifier()
notifier.send_message(report)
"
User=root
WorkingDirectory=$GATEWAY_DIR

# Environment
Environment=PYTHONPATH=$GATEWAY_DIR
Environment=PYTHONUNBUFFERED=1

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=weekly-report
EOF

    cat > "$SERVICE_DIR/weekly-report.timer" << EOF
[Unit]
Description=Weekly Report Timer - Gateway 24/7
Requires=weekly-report.service

[Timer]
OnCalendar=Mon 09:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    log_success "Weekly report service and timer created"
}

# ============================================
# ENABLE AND START SERVICES
# ============================================

enable_services() {
    log_info "Enabling and starting monitoring services..."
    
    # Reload systemd
    systemctl daemon-reload
    
    # List of services to enable
    local services=(
        "telegram-notifier.service"
        "tailscale-monitor.service"
        "system-watchdog.service"
        "health-monitor.service"
        "weekly-report.timer"
    )
    
    # Enable services
    for service in "${services[@]}"; do
        log_info "Enabling $service..."
        systemctl enable "$service"
    done
    
    # Start services (except timer which is already started by enable)
    local start_services=(
        "telegram-notifier.service"
        "tailscale-monitor.service"
        "system-watchdog.service"
        "health-monitor.service"
    )
    
    for service in "${start_services[@]}"; do
        log_info "Starting $service..."
        systemctl start "$service"
        
        # Wait a moment and check status
        sleep 2
        if systemctl is-active --quiet "$service"; then
            log_success "$service started successfully"
        else
            log_warn "$service may have issues - check with: systemctl status $service"
        fi
    done
    
    log_success "All monitoring services enabled and started"
}

# ============================================
# SETUP MONITORING DASHBOARD
# ============================================

setup_monitoring_dashboard() {
    log_info "Setting up monitoring dashboard script..."
    
    cat > "$GATEWAY_DIR/monitor_dashboard.sh" << 'EOF'
#!/bin/bash

# Gateway 24/7 Monitoring Dashboard
clear

echo "========================================"
echo "Gateway 24/7 - System Monitor Dashboard"
echo "========================================"
echo "$(date)"
echo ""

# System Overview
echo "=== SYSTEM OVERVIEW ==="
echo "Uptime: $(uptime -p)"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "Temperature: $(vcgencmd measure_temp 2>/dev/null || echo 'N/A')"
echo "Memory: $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
echo "Disk: $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
echo ""

# Service Status
echo "=== SERVICE STATUS ==="
services=("access_control.service" "network-monitor.service" "telegram-notifier.service" "tailscale-monitor.service" "system-watchdog.service" "health-monitor.service")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "✅ $service"
    else
        echo "❌ $service"
    fi
done
echo ""

# Network Status
echo "=== NETWORK STATUS ==="
echo "Ethernet: $(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 || echo 'Disconnected')"
echo "WiFi: $(iwgetid -r 2>/dev/null || echo 'Disconnected')"
echo "Tailscale: $(tailscale ip 2>/dev/null || echo 'Disconnected')"
echo "Internet: $(ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo 'Connected' || echo 'Disconnected')"
echo ""

# Recent Logs
echo "=== RECENT EVENTS ==="
journalctl --since "1 hour ago" -u telegram-notifier.service -u system-watchdog.service --no-pager -n 5 | tail -5
echo ""

echo "Press Ctrl+C to exit, or wait 30 seconds for refresh..."
sleep 30
exec "$0"
EOF

    chmod +x "$GATEWAY_DIR/monitor_dashboard.sh"
    
    log_success "Monitoring dashboard created at $GATEWAY_DIR/monitor_dashboard.sh"
}

# ============================================
# VALIDATION
# ============================================

validate_installation() {
    log_info "Validating service installation..."
    
    local all_good=true
    
    # Check if services exist
    local services=(
        "telegram-notifier.service"
        "tailscale-monitor.service"
        "system-watchdog.service"
        "health-monitor.service"
        "weekly-report.service"
        "weekly-report.timer"
    )
    
    for service in "${services[@]}"; do
        if [ -f "$SERVICE_DIR/$service" ]; then
            log_success "✅ $service exists"
        else
            log_error "❌ $service missing"
            all_good=false
        fi
    done
    
    # Check if Python services are executable
    local python_services=(
        "telegram_notifier.py"
        "tailscale_monitor.py"
        "system_watchdog.py"
        "health_monitor.py"
    )
    
    for service in "${python_services[@]}"; do
        if [ -f "$GATEWAY_DIR/services/$service" ]; then
            log_success "✅ $service exists"
            # Check if it's executable
            if python3 -m py_compile "$GATEWAY_DIR/services/$service" 2>/dev/null; then
                log_success "✅ $service syntax OK"
            else
                log_error "❌ $service syntax error"
                all_good=false
            fi
        else
            log_error "❌ $service missing"
            all_good=false
        fi
    done
    
    # Check virtual environment
    if [ -d "$GATEWAY_DIR/venv" ] && [ -f "$GATEWAY_DIR/venv/bin/python" ]; then
        log_success "✅ Virtual environment OK"
    else
        log_error "❌ Virtual environment missing"
        all_good=false
    fi
    
    # Check configuration files
    local configs=(
        "telegram.conf"
        "tailscale.conf"
        "monitoring.conf"
    )
    
    for config in "${configs[@]}"; do
        if [ -f "$GATEWAY_DIR/config/$config" ]; then
            log_success "✅ $config exists"
        else
            log_error "❌ $config missing"
            all_good=false
        fi
    done
    
    if $all_good; then
        log_success "All services validated successfully"
        return 0
    else
        log_error "Some services failed validation"
        return 1
    fi
}

# ============================================
# MAIN FUNCTION
# ============================================

main() {
    echo "============================================"
    echo "Service Installation Script"
    echo "Sistema Gateway 24/7"
    echo "============================================"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Usage: sudo $0"
        exit 1
    fi
    
    # Create directories
    mkdir -p "$GATEWAY_DIR"/{services,config,logs}
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_info "Starting monitoring services installation..."
    
    # Install dependencies
    install_python_dependencies
    
    # Create systemd services
    create_telegram_service
    create_tailscale_monitor_service
    create_system_watchdog_service
    create_health_monitor_service
    create_weekly_report_service
    
    # Setup dashboard
    setup_monitoring_dashboard
    
    # Enable and start services
    enable_services
    
    # Validate installation
    if validate_installation; then
        log_success "Service installation completed successfully!"
        
        echo ""
        echo "=========================================="
        echo "SERVICE INSTALLATION COMPLETED"
        echo "=========================================="
        echo "Monitoring services installed and started:"
        echo "• Telegram Notifier - Bot and notifications"
        echo "• Tailscale Monitor - VPN monitoring"
        echo "• System Watchdog - Auto-recovery"
        echo "• Health Monitor - Comprehensive health checks"
        echo "• Weekly Reports - Automated reporting"
        echo ""
        echo "Check service status:"
        echo "  sudo systemctl status telegram-notifier.service"
        echo "  sudo systemctl status system-watchdog.service"
        echo ""
        echo "View monitoring dashboard:"
        echo "  sudo $GATEWAY_DIR/monitor_dashboard.sh"
        echo ""
        echo "Check logs:"
        echo "  sudo journalctl -u telegram-notifier.service -f"
        echo "=========================================="
        
    else
        log_error "Service installation completed with errors"
        echo "Please check the logs and fix any issues before proceeding"
        exit 1
    fi
}

# Run main function
main "$@"