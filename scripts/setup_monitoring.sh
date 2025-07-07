#!/bin/bash

# ============================================
# Setup Monitoring Script
# Sistema Gateway 24/7
# ============================================
# Comprehensive setup script for all monitoring components

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="/opt/gateway"
LOG_FILE="/var/log/setup_monitoring.log"

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
# COPY FILES TO GATEWAY DIRECTORY
# ============================================

copy_files() {
    log_info "Copying files to gateway directory..."
    
    # Create directory structure
    mkdir -p "$GATEWAY_DIR"/{services,config,scripts,logs}
    
    # Copy service files
    if [ -d "$SCRIPT_DIR/../services" ]; then
        cp -r "$SCRIPT_DIR/../services/"* "$GATEWAY_DIR/services/"
        log_success "Service files copied"
    else
        log_error "Services directory not found"
        return 1
    fi
    
    # Copy configuration files
    if [ -d "$SCRIPT_DIR/../config" ]; then
        cp -r "$SCRIPT_DIR/../config/"* "$GATEWAY_DIR/config/"
        log_success "Configuration files copied"
    else
        log_error "Config directory not found"
        return 1
    fi
    
    # Copy scripts
    if [ -d "$SCRIPT_DIR" ]; then
        cp "$SCRIPT_DIR/"*.sh "$GATEWAY_DIR/scripts/"
        log_success "Scripts copied"
    else
        log_warn "Scripts directory not found"
    fi
    
    # Make Python services executable
    chmod +x "$GATEWAY_DIR/services/"*.py
    chmod +x "$GATEWAY_DIR/scripts/"*.sh
    
    log_success "Files copied successfully"
}

# ============================================
# INSTALL TAILSCALE
# ============================================

install_tailscale() {
    log_info "Installing Tailscale..."
    
    # Check if already installed
    if command -v tailscale >/dev/null 2>&1; then
        log_info "Tailscale already installed"
        return 0
    fi
    
    # Download and install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh
    
    # Enable Tailscale service
    systemctl enable tailscaled
    systemctl start tailscaled
    
    log_success "Tailscale installed and started"
}

# ============================================
# CONFIGURE TAILSCALE
# ============================================

configure_tailscale() {
    log_info "Configuring Tailscale with provided auth key..."
    
    # Read auth key from config
    local tskey
    if [ -f "$GATEWAY_DIR/config/tailscale.conf" ]; then
        tskey=$(grep "^TSKEY=" "$GATEWAY_DIR/config/tailscale.conf" | cut -d= -f2)
    else
        log_error "Tailscale config file not found"
        return 1
    fi
    
    if [ -z "$tskey" ]; then
        log_error "Tailscale auth key not found in config"
        return 1
    fi
    
    # Check if already authenticated
    if tailscale status >/dev/null 2>&1; then
        local status_output=$(tailscale status 2>&1)
        if [[ ! "$status_output" =~ "Logged out" ]]; then
            log_info "Tailscale already authenticated"
            return 0
        fi
    fi
    
    # Authenticate Tailscale
    log_info "Authenticating Tailscale..."
    tailscale up --authkey="$tskey" --accept-routes --hostname="gateway-$(hostname)"
    
    if [ $? -eq 0 ]; then
        log_success "Tailscale authentication successful"
        
        # Get assigned IP
        local tailscale_ip=$(tailscale ip)
        log_info "Tailscale IP assigned: $tailscale_ip"
    else
        log_error "Tailscale authentication failed"
        return 1
    fi
}

# ============================================
# SETUP LOG ROTATION
# ============================================

setup_log_rotation() {
    log_info "Setting up log rotation for monitoring services..."
    
    cat > /etc/logrotate.d/gateway-monitoring << 'EOF'
/var/log/telegram_notifier.log
/var/log/tailscale_monitor.log
/var/log/system_watchdog.log
/var/log/health_monitor.log
/var/log/setup_monitoring.log
/var/log/service_install.log
/var/log/pi_optimization.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        # Signal services to reopen log files if needed
        systemctl reload-or-restart telegram-notifier.service >/dev/null 2>&1 || true
        systemctl reload-or-restart tailscale-monitor.service >/dev/null 2>&1 || true
        systemctl reload-or-restart system-watchdog.service >/dev/null 2>&1 || true
        systemctl reload-or-restart health-monitor.service >/dev/null 2>&1 || true
    endscript
}

/opt/gateway/logs/*.log {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}

/tmp/health_reports/*.json {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

    log_success "Log rotation configured"
}

# ============================================
# SETUP CRON JOBS
# ============================================

setup_cron_jobs() {
    log_info "Setting up cron jobs for maintenance tasks..."
    
    # Create cron job for system maintenance
    cat > /etc/cron.d/gateway-maintenance << 'EOF'
# Gateway 24/7 Maintenance Tasks

# Daily system health check (every day at 6 AM)
0 6 * * * root /opt/gateway/venv/bin/python /opt/gateway/services/health_monitor.py --daily-report >> /var/log/cron.log 2>&1

# Weekly disk cleanup (every Sunday at 3 AM)
0 3 * * 0 root /opt/gateway/scripts/optimize_pi.sh --cleanup >> /var/log/cron.log 2>&1

# Hourly connectivity check
0 * * * * root /bin/bash -c 'ping -c 1 8.8.8.8 >/dev/null || systemctl restart network-monitor.service' >> /var/log/cron.log 2>&1

# Daily log rotation check
30 23 * * * root /usr/sbin/logrotate /etc/logrotate.conf >> /var/log/cron.log 2>&1

# Monthly service restart (first day of month at 4 AM)
0 4 1 * * root systemctl restart telegram-notifier.service tailscale-monitor.service system-watchdog.service health-monitor.service >> /var/log/cron.log 2>&1
EOF

    log_success "Cron jobs configured"
}

# ============================================
# CREATE SYSTEM STATUS COMMAND
# ============================================

create_status_command() {
    log_info "Creating system status command..."
    
    cat > /usr/local/bin/gateway-status << 'EOF'
#!/bin/bash

# Gateway 24/7 Status Command
echo "========================================"
echo "Gateway Sistema 24/7 - Status Report"
echo "========================================"
echo "Generated: $(date)"
echo ""

# System Information
echo "=== SYSTEM INFORMATION ==="
echo "Hostname: $(hostname)"
echo "Model: $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo 'Unknown')"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# Hardware Status
echo "=== HARDWARE STATUS ==="
echo "Temperature: $(vcgencmd measure_temp 2>/dev/null || echo 'N/A')"
echo "Throttling: $(vcgencmd get_throttled 2>/dev/null || echo 'N/A')"
echo "Memory: $(free -h | awk '/^Mem:/{print $3 "/" $2 " (" int($3/$2*100) "%)"}')"
echo "Disk: $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
echo ""

# Service Status
echo "=== SERVICE STATUS ==="
services=("access_control.service" "network-monitor.service" "telegram-notifier.service" "tailscale-monitor.service" "system-watchdog.service" "health-monitor.service")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        status="🟢 Active"
        uptime=$(systemctl show "$service" --property=ActiveEnterTimestamp --value | xargs -I {} date -d {} +%s 2>/dev/null || echo "0")
        if [ "$uptime" != "0" ]; then
            current=$(date +%s)
            duration=$((current - uptime))
            if [ $duration -gt 86400 ]; then
                duration_str="$(($duration / 86400))d $(($duration % 86400 / 3600))h"
            elif [ $duration -gt 3600 ]; then
                duration_str="$(($duration / 3600))h $(($duration % 3600 / 60))m"
            else
                duration_str="$(($duration / 60))m"
            fi
            status="$status (${duration_str})"
        fi
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        status="🔴 Inactive"
    else
        status="⚫ Disabled"
    fi
    printf "%-30s %s\n" "$service" "$status"
done
echo ""

# Network Status
echo "=== NETWORK STATUS ==="
echo "Ethernet: $(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 || echo 'Disconnected')"
echo "WiFi SSID: $(iwgetid -r 2>/dev/null || echo 'Disconnected')"
echo "WiFi IP: $(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 || echo 'Disconnected')"
echo "Tailscale: $(tailscale ip 2>/dev/null || echo 'Disconnected')"
echo "Internet: $(ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo '🟢 Connected' || echo '🔴 Disconnected')"
echo ""

# Tailscale Users
echo "=== TAILSCALE USERS ==="
if command -v tailscale >/dev/null 2>&1; then
    tailscale status 2>/dev/null | grep -v "^$" | tail -n +2 | head -10 || echo "No users connected"
else
    echo "Tailscale not installed"
fi
echo ""

# Recent Events
echo "=== RECENT EVENTS (Last 24h) ==="
journalctl --since "24 hours ago" -u telegram-notifier.service -u system-watchdog.service -u tailscale-monitor.service --no-pager -n 5 2>/dev/null | grep -v "^$" || echo "No recent events"
echo ""

# Quick Actions
echo "=== QUICK ACTIONS ==="
echo "View detailed logs: sudo journalctl -u telegram-notifier.service -f"
echo "Restart services: sudo systemctl restart telegram-notifier.service"
echo "Monitor dashboard: sudo /opt/gateway/monitor_dashboard.sh"
echo "Optimization status: sudo /usr/local/bin/optimization-status.sh"
echo "========================================"
EOF

    chmod +x /usr/local/bin/gateway-status
    
    log_success "Gateway status command created: gateway-status"
}

# ============================================
# SEND INITIAL TELEGRAM NOTIFICATION
# ============================================

send_initial_notification() {
    log_info "Sending initial setup notification to Telegram..."
    
    # Wait a moment for services to start
    sleep 5
    
    # Try to send notification using the Telegram service
    local message="🚀 *Sistema Gateway 24/7 Configurado*\n\n"
    message+="✅ Instalación completada exitosamente\n"
    message+="🤖 Bot Telegram activo\n"
    message+="🔒 Tailscale configurado\n"
    message+="🛡️ Monitoreo 24/7 activo\n"
    message+="📊 Reportes automáticos habilitados\n\n"
    message+="*Prueba los comandos:*\n"
    message+="/status - Estado del sistema\n"
    message+="/health - Diagnóstico completo\n"
    message+="/network - Estado de red\n\n"
    message+="⏰ $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Try to send via Python script
    python3 << EOF
import sys
sys.path.insert(0, '$GATEWAY_DIR/services')
try:
    from telegram_notifier import TelegramNotifier
    notifier = TelegramNotifier()
    notifier.send_message("""$message""")
    print("Initial notification sent successfully")
except Exception as e:
    print(f"Failed to send initial notification: {e}")
EOF

    log_success "Initial notification sent"
}

# ============================================
# FINAL VALIDATION
# ============================================

final_validation() {
    log_info "Performing final validation..."
    
    local validation_passed=true
    
    # Check critical services
    local critical_services=(
        "access_control.service"
        "telegram-notifier.service"
        "system-watchdog.service"
    )
    
    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_success "✅ $service is running"
        else
            log_error "❌ $service is not running"
            validation_passed=false
        fi
    done
    
    # Check Tailscale
    if command -v tailscale >/dev/null 2>&1; then
        if tailscale status >/dev/null 2>&1; then
            local tailscale_ip=$(tailscale ip 2>/dev/null)
            if [ -n "$tailscale_ip" ]; then
                log_success "✅ Tailscale is connected (IP: $tailscale_ip)"
            else
                log_warn "⚠️ Tailscale installed but not connected"
            fi
        else
            log_warn "⚠️ Tailscale installed but not authenticated"
        fi
    else
        log_error "❌ Tailscale not installed"
        validation_passed=false
    fi
    
    # Check network connectivity
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "✅ Internet connectivity available"
    else
        log_warn "⚠️ No internet connectivity"
    fi
    
    # Check configuration files
    local config_files=(
        "$GATEWAY_DIR/config/telegram.conf"
        "$GATEWAY_DIR/config/tailscale.conf"
        "$GATEWAY_DIR/config/monitoring.conf"
    )
    
    for config in "${config_files[@]}"; do
        if [ -f "$config" ]; then
            log_success "✅ $(basename "$config") exists"
        else
            log_error "❌ $(basename "$config") missing"
            validation_passed=false
        fi
    done
    
    if $validation_passed; then
        log_success "All validation checks passed"
        return 0
    else
        log_error "Some validation checks failed"
        return 1
    fi
}

# ============================================
# MAIN FUNCTION
# ============================================

main() {
    echo "============================================"
    echo "Setup Monitoring Script"
    echo "Sistema Gateway 24/7"
    echo "============================================"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Usage: sudo $0"
        exit 1
    fi
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_info "Starting comprehensive monitoring setup..."
    
    # Run setup steps
    copy_files || { log_error "Failed to copy files"; exit 1; }
    
    install_tailscale || { log_error "Failed to install Tailscale"; exit 1; }
    
    configure_tailscale || { log_warn "Tailscale configuration may need manual attention"; }
    
    setup_log_rotation || { log_warn "Log rotation setup failed"; }
    
    setup_cron_jobs || { log_warn "Cron jobs setup failed"; }
    
    create_status_command || { log_warn "Status command creation failed"; }
    
    # Install services (call the service installation script)
    if [ -f "$GATEWAY_DIR/scripts/install_services.sh" ]; then
        log_info "Installing monitoring services..."
        bash "$GATEWAY_DIR/scripts/install_services.sh"
    else
        log_error "Service installation script not found"
        exit 1
    fi
    
    # Send initial notification
    send_initial_notification || { log_warn "Initial notification failed"; }
    
    # Final validation
    if final_validation; then
        log_success "Setup completed successfully!"
        
        echo ""
        echo "=========================================="
        echo "SISTEMA GATEWAY 24/7 CONFIGURADO"
        echo "=========================================="
        echo "✅ Instalación completada exitosamente"
        echo ""
        echo "🤖 Bot Telegram configurado:"
        echo "   Token: 7954949854:AAHjEYMdvJ9z2jD8pV7fGsI0a6ipTjJHR2M"
        echo "   Chat ID: -4812920580"
        echo ""
        echo "🔒 Tailscale VPN configurado:"
        local tailscale_ip=$(tailscale ip 2>/dev/null || echo "Pendiente de configuración")
        echo "   IP Tailscale: $tailscale_ip"
        echo ""
        echo "📊 Servicios de monitoreo activos:"
        echo "   • Notificaciones Telegram"
        echo "   • Monitor Tailscale"
        echo "   • Watchdog del sistema"
        echo "   • Monitor de salud"
        echo "   • Reportes semanales automáticos"
        echo ""
        echo "🔧 Comandos útiles:"
        echo "   gateway-status           - Estado completo"
        echo "   systemctl status telegram-notifier.service"
        echo "   /opt/gateway/monitor_dashboard.sh"
        echo ""
        echo "📱 Comandos bot Telegram:"
        echo "   /status - Estado del sistema"
        echo "   /health - Diagnóstico completo"
        echo "   /users  - Usuarios Tailscale"
        echo "   /logs   - Eventos recientes"
        echo "   /restart [servicio] - Reinicio remoto"
        echo "=========================================="
        
    else
        log_error "Setup completed with errors - manual intervention may be required"
        exit 1
    fi
}

# Run main function
main "$@"