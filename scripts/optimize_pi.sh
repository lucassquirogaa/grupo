#!/bin/bash

# ============================================
# Raspberry Pi 3B+ Optimization Script
# Sistema Gateway 24/7
# ============================================
# Optimizations specific for Raspberry Pi 3B+ with Samsung Pro Endurance 64GB
# Reduces writes, optimizes memory usage, and ensures 24/7 operation

set -e

# Configuration
LOG_FILE="/var/log/pi_optimization.log"
CONFIG_DIR="/opt/gateway/config"

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
# MEMORY OPTIMIZATIONS
# ============================================

optimize_memory() {
    log_info "Optimizing memory configuration for 1GB RAM..."
    
    # Configure swap for Samsung Pro Endurance (reduce writes)
    log_info "Configuring optimized swap settings..."
    
    # Reduce swappiness for SSD/SD card longevity
    echo 'vm.swappiness=1' >> /etc/sysctl.conf
    echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
    echo 'vm.dirty_background_ratio=5' >> /etc/sysctl.conf
    echo 'vm.dirty_ratio=10' >> /etc/sysctl.conf
    
    # Configure zram for compressed RAM
    if ! command -v zramctl >/dev/null 2>&1; then
        apt-get update && apt-get install -y util-linux
    fi
    
    # Create zram service
    cat > /etc/systemd/system/zram.service << 'EOF'
[Unit]
Description=zram swap compression
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram && echo lz4 > /sys/block/zram0/comp_algorithm && echo 256M > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 10 /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 && rmmod zram'

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable zram.service
    
    log_success "Memory optimization configured"
}

# ============================================
# STORAGE OPTIMIZATIONS
# ============================================

optimize_storage() {
    log_info "Optimizing storage for Samsung Pro Endurance longevity..."
    
    # Create tmpfs for temporary files and logs
    log_info "Setting up tmpfs for reduced SD card writes..."
    
    # Backup original fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%s)
    
    # Add tmpfs entries
    cat >> /etc/fstab << 'EOF'

# tmpfs optimizations for Samsung Pro Endurance
tmpfs /tmp tmpfs defaults,noatime,nosuid,size=100m 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,size=50m 0 0
tmpfs /var/log tmpfs defaults,noatime,nosuid,size=50m 0 0
tmpfs /var/cache/apt tmpfs defaults,noatime,nosuid,size=50m 0 0
EOF

    # Configure log rotation to minimize writes
    log_info "Configuring aggressive log rotation..."
    
    cat > /etc/logrotate.d/gateway-optimization << 'EOF'
/var/log/*.log {
    daily
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl reload rsyslog
    endscript
}

/opt/gateway/logs/*.log {
    daily
    rotate 2
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

    # Configure journal to limit size
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/00-gateway.conf << 'EOF'
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=50M
SystemMaxFileSize=10M
RuntimeMaxFileSize=10M
MaxRetentionSec=3day
MaxFileSec=1day
EOF

    # Disable unnecessary file system features that increase writes
    tune2fs -O ^has_journal /dev/mmcblk0p2 2>/dev/null || true
    
    log_success "Storage optimization configured"
}

# ============================================
# CPU AND THERMAL OPTIMIZATIONS
# ============================================

optimize_cpu() {
    log_info "Optimizing CPU for 24/7 operation..."
    
    # Configure CPU governor for efficiency
    log_info "Setting up CPU frequency scaling..."
    
    # Install cpufrequtils if not present
    if ! command -v cpufreq-set >/dev/null 2>&1; then
        apt-get update && apt-get install -y cpufrequtils
    fi
    
    # Set conservative governor for 24/7 operation
    cat > /etc/default/cpufrequtils << 'EOF'
GOVERNOR="ondemand"
MIN_SPEED="600000"
MAX_SPEED="1400000"
EOF

    # Configure thermal management
    log_info "Setting up thermal management..."
    
    cat > /boot/config.txt.new << 'EOF'
# Thermal and performance optimizations for Gateway 24/7
# Raspberry Pi 3B+ specific settings

# Thermal management
temp_limit=75
initial_turbo=30

# Memory split optimized for headless operation
gpu_mem=16

# Overclock settings for stability
arm_freq=1300
core_freq=400
sdram_freq=500
over_voltage=2

# Power management
avoid_pwm_pll=1

# Disable unnecessary features
dtparam=audio=off
camera_auto_detect=0
display_auto_detect=0

# Enable hardware watchdog
dtparam=watchdog=on

# Optimize I/O performance
dtoverlay=sd_overclock,poll_once=on
EOF

    # Backup and replace config.txt (keep existing settings that don't conflict)
    if [ -f /boot/config.txt ]; then
        cp /boot/config.txt /boot/config.txt.backup.$(date +%s)
        
        # Merge configurations (prioritize our optimizations)
        grep -v "^temp_limit\|^gpu_mem\|^arm_freq\|^core_freq\|^avoid_pwm_pll\|^dtparam=audio\|^dtparam=watchdog" /boot/config.txt > /boot/config.txt.merged
        cat /boot/config.txt.new >> /boot/config.txt.merged
        mv /boot/config.txt.merged /boot/config.txt
    else
        mv /boot/config.txt.new /boot/config.txt
    fi
    
    # Set up thermal monitoring script
    cat > /usr/local/bin/thermal-monitor.sh << 'EOF'
#!/bin/bash
# Thermal monitoring for Raspberry Pi 3B+

TEMP_THRESHOLD=80
CHECK_INTERVAL=30

while true; do
    TEMP=$(vcgencmd measure_temp | cut -d= -f2 | cut -d\' -f1)
    TEMP_INT=${TEMP%.*}
    
    if [ "$TEMP_INT" -gt "$TEMP_THRESHOLD" ]; then
        logger "High temperature detected: ${TEMP}°C - Reducing CPU frequency"
        echo "powersave" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        sleep 60
        echo "ondemand" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    fi
    
    sleep "$CHECK_INTERVAL"
done
EOF

    chmod +x /usr/local/bin/thermal-monitor.sh
    
    # Create thermal monitor service
    cat > /etc/systemd/system/thermal-monitor.service << 'EOF'
[Unit]
Description=Thermal Monitor for Raspberry Pi
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/thermal-monitor.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable thermal-monitor.service
    
    log_success "CPU optimization configured"
}

# ============================================
# NETWORK OPTIMIZATIONS
# ============================================

optimize_network() {
    log_info "Optimizing network settings for 24/7 operation..."
    
    # Configure network buffer sizes for low memory system
    cat >> /etc/sysctl.conf << 'EOF'

# Network optimizations for Raspberry Pi 3B+
net.core.rmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_default=262144
net.core.wmem_max=16777216
net.core.netdev_max_backlog=1000

# TCP optimizations
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 16384 16777216
net.ipv4.tcp_congestion_control=bbr

# Reduce TIME_WAIT sockets
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_tw_reuse=1

# Connection tracking optimizations
net.netfilter.nf_conntrack_max=32768
net.netfilter.nf_conntrack_tcp_timeout_established=3600
EOF

    # Configure NetworkManager for reliability
    cat > /etc/NetworkManager/conf.d/99-gateway-optimization.conf << 'EOF'
[main]
# Disable IPv6 for simplicity and reduced overhead
ipv6.disable=1

[connectivity]
# Reduce connectivity check interval
interval=300
uri=http://connectivitycheck.gstatic.com/generate_204

[device]
# Optimize WiFi power management
wifi.powersave=2
wifi.scan-rand-mac-address=no
EOF

    log_success "Network optimization configured"
}

# ============================================
# SERVICE OPTIMIZATIONS
# ============================================

optimize_services() {
    log_info "Optimizing system services for 24/7 operation..."
    
    # Disable unnecessary services
    local services_to_disable=(
        "bluetooth.service"
        "hciuart.service"
        "avahi-daemon.service"
        "cups.service"
        "cups-browsed.service"
        "ModemManager.service"
        "wpa_supplicant.service"  # We use NetworkManager
    )
    
    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log_info "Disabling $service..."
            systemctl disable "$service" 2>/dev/null || true
        fi
    done
    
    # Configure systemd for faster boot and recovery
    cat > /etc/systemd/system.conf.d/99-gateway.conf << 'EOF'
[Manager]
# Faster startup and shutdown
DefaultTimeoutStartSec=30s
DefaultTimeoutStopSec=15s
DefaultRestartSec=5s

# Memory management
RuntimeWatchdogSec=30s
RebootWatchdogSec=10min
EOF

    # Configure rsyslog for minimal writes
    cat > /etc/rsyslog.d/99-gateway-optimization.conf << 'EOF'
# Optimize syslog for reduced writes
$WorkDirectory /var/spool/rsyslog
$ActionQueueFileName fwdRule1
$ActionQueueMaxDiskSpace 50m
$ActionQueueSaveOnShutdown on
$ActionQueueType LinkedList
$ActionResumeRetryCount -1

# Reduce sync frequency
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$ActionFileEnableSync off
$OMFileAsyncWriting on
$OMFileFlushOnTXEnd off
$OMFileIOBufferSize 64k
EOF

    log_success "Service optimization configured"
}

# ============================================
# HARDWARE WATCHDOG SETUP
# ============================================

setup_hardware_watchdog() {
    log_info "Setting up hardware watchdog for 24/7 reliability..."
    
    # Install watchdog daemon
    if ! command -v watchdog >/dev/null 2>&1; then
        apt-get update && apt-get install -y watchdog
    fi
    
    # Configure watchdog
    cat > /etc/watchdog.conf << 'EOF'
# Hardware watchdog configuration for Raspberry Pi 3B+
watchdog-device = /dev/watchdog

# Timeout before reboot (seconds)
watchdog-timeout = 15

# Interval between checks (seconds) 
interval = 1

# Test file system
file = /var/log/watchdog.log
change = 1407

# Test network interfaces
interface = eth0

# Test system load
max-load-1 = 24
max-load-5 = 18
max-load-15 = 12

# Test memory usage
min-memory = 1

# Test temperature (if available)
temperature-device = /sys/class/thermal/thermal_zone0/temp
max-temperature = 85000

# Enable logging
logtick = 1
verbose = 1

# Test if we can allocate memory
allocatable-memory = 1

# Repair binary
repair-binary = /usr/local/bin/watchdog-repair.sh
test-timeout = 60
EOF

    # Create repair script
    cat > /usr/local/bin/watchdog-repair.sh << 'EOF'
#!/bin/bash
# Watchdog repair script

logger "Watchdog: Attempting system repair"

# Free memory caches
echo 3 > /proc/sys/vm/drop_caches

# Restart critical services if they're not running
systemctl is-active --quiet access_control.service || systemctl restart access_control.service
systemctl is-active --quiet network-monitor.service || systemctl restart network-monitor.service

# Check disk space and clean if needed
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    logger "Watchdog: High disk usage, cleaning up"
    apt-get clean
    journalctl --vacuum-time=1d
    find /tmp -type f -mtime +1 -delete
fi

# Check temperature and throttle if needed
TEMP=$(vcgencmd measure_temp | cut -d= -f2 | cut -d\' -f1 | cut -d. -f1)
if [ "$TEMP" -gt 80 ]; then
    logger "Watchdog: High temperature, throttling CPU"
    echo "powersave" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
fi

logger "Watchdog: Repair attempts completed"
EOF

    chmod +x /usr/local/bin/watchdog-repair.sh
    
    # Enable watchdog service
    systemctl enable watchdog.service
    
    log_success "Hardware watchdog configured"
}

# ============================================
# BOOT OPTIMIZATIONS
# ============================================

optimize_boot() {
    log_info "Optimizing boot process for faster startup..."
    
    # Configure cmdline.txt for faster boot
    if [ -f /boot/cmdline.txt ]; then
        cp /boot/cmdline.txt /boot/cmdline.txt.backup.$(date +%s)
        
        # Add optimization parameters
        sed -i 's/$/ fastboot noswap/' /boot/cmdline.txt
        
        # Remove unnecessary parameters that slow boot
        sed -i 's/quiet//g' /boot/cmdline.txt
        sed -i 's/splash//g' /boot/cmdline.txt
    fi
    
    # Disable unnecessary boot services
    systemctl disable raspi-config.service 2>/dev/null || true
    systemctl disable keyboard-setup.service 2>/dev/null || true
    
    log_success "Boot optimization configured"
}

# ============================================
# MONITORING SETUP
# ============================================

setup_optimization_monitoring() {
    log_info "Setting up optimization monitoring..."
    
    # Create optimization status script
    cat > /usr/local/bin/optimization-status.sh << 'EOF'
#!/bin/bash
# Check optimization status

echo "=== Raspberry Pi 3B+ Optimization Status ==="
echo "Date: $(date)"
echo ""

# Memory status
echo "Memory Usage:"
free -h

echo ""
echo "Swap Usage:"
swapon --show

echo ""
echo "Temperature:"
vcgencmd measure_temp

echo ""
echo "CPU Frequency:"
vcgencmd measure_clock arm

echo ""
echo "Throttling Status:"
vcgencmd get_throttled

echo ""
echo "Disk Usage:"
df -h /

echo ""
echo "System Load:"
uptime

echo ""
echo "Critical Services:"
systemctl is-active access_control.service
systemctl is-active network-monitor.service
systemctl is-active watchdog.service

echo ""
echo "Optimization Features:"
echo "  tmpfs /var/log: $(mountpoint -q /var/log && echo 'Active' || echo 'Inactive')"
echo "  tmpfs /tmp: $(mountpoint -q /tmp && echo 'Active' || echo 'Inactive')"
echo "  zram: $(swapon --show | grep -q zram && echo 'Active' || echo 'Inactive')"
echo "  watchdog: $(systemctl is-active watchdog.service)"
echo "  thermal-monitor: $(systemctl is-active thermal-monitor.service)"
EOF

    chmod +x /usr/local/bin/optimization-status.sh
    
    # Create daily optimization report
    cat > /etc/cron.daily/optimization-report << 'EOF'
#!/bin/bash
# Daily optimization report

/usr/local/bin/optimization-status.sh >> /var/log/optimization-daily.log

# Rotate log to prevent growth
if [ -f /var/log/optimization-daily.log ]; then
    tail -n 100 /var/log/optimization-daily.log > /var/log/optimization-daily.log.tmp
    mv /var/log/optimization-daily.log.tmp /var/log/optimization-daily.log
fi
EOF

    chmod +x /etc/cron.daily/optimization-report
    
    log_success "Optimization monitoring configured"
}

# ============================================
# MAIN FUNCTION
# ============================================

main() {
    echo "============================================"
    echo "Raspberry Pi 3B+ Optimization Script"
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
    mkdir -p "$CONFIG_DIR"
    
    log_info "Starting Raspberry Pi 3B+ optimization for 24/7 operation..."
    
    # Run optimization steps
    optimize_memory
    optimize_storage
    optimize_cpu
    optimize_network
    optimize_services
    setup_hardware_watchdog
    optimize_boot
    setup_optimization_monitoring
    
    log_success "Raspberry Pi 3B+ optimization completed!"
    
    echo ""
    echo "=========================================="
    echo "OPTIMIZATION COMPLETED"
    echo "=========================================="
    echo "The system has been optimized for:"
    echo "• Samsung Pro Endurance 64GB longevity"
    echo "• 1GB RAM efficient usage"
    echo "• 24/7 reliable operation"
    echo "• Minimal SD card writes"
    echo "• Thermal management"
    echo "• Hardware watchdog protection"
    echo ""
    echo "IMPORTANT: Reboot required to apply all optimizations"
    echo "Run: sudo reboot"
    echo ""
    echo "After reboot, check status with:"
    echo "  sudo /usr/local/bin/optimization-status.sh"
    echo "=========================================="
}

# Run main function
main "$@"