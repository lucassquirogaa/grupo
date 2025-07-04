#!/bin/bash

# ============================================
# Script de Instalación - Sistema de Control de Acceso
# con Modo Offline para TP-Link 3040
# ============================================

set -e  # Salir en caso de error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="access_control"
SERVICE_USER="pi"
WEB_PORT="8080"
OFFLINE_SCRIPT_PATH="/opt/enable-offline-portal.sh"

# IPs fijas para modo offline
OFFLINE_IP_PRIMARY="192.168.100.1"
OFFLINE_IP_ALT1="192.168.1.200"
OFFLINE_IP_ALT2="192.168.0.200"
OFFLINE_NETMASK="24"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Sistema de Control de Acceso - Instalador${NC}"
echo -e "${BLUE}Versión con Modo Offline para TP-Link 3040${NC}"
echo -e "${BLUE}============================================${NC}"

# ============================================
# FASE 1: Verificaciones previas
# ============================================
echo -e "\n${YELLOW}-> FASE 1: Verificaciones previas${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

# Verificar que existe el archivo principal de la aplicación
if [[ ! -f "$SCRIPT_DIR/pi@raspberrypi~access_control_syste.txt" ]]; then
    echo -e "${RED}Error: No se encuentra el archivo principal de la aplicación${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Verificaciones completadas${NC}"

# ============================================
# FASE 2: Instalación de dependencias
# ============================================
echo -e "\n${YELLOW}-> FASE 2: Instalación de dependencias${NC}"

apt-get update
apt-get install -y python3-pip python3-venv python3-dev
apt-get install -y network-manager git sqlite3
apt-get install -y pigpio python3-pigpio
apt-get install -y psutil

echo -e "${GREEN}✅ Dependencias instaladas${NC}"

# ============================================
# FASE 3: Configuración del entorno Python
# ============================================
echo -e "\n${YELLOW}-> FASE 3: Configuración del entorno Python${NC}"

cd "$SCRIPT_DIR"

# Crear entorno virtual si no existe
if [[ ! -d "venv" ]]; then
    python3 -m venv venv
fi

source venv/bin/activate

# Instalar dependencias Python (crear requirements.txt básico)
cat > requirements.txt << EOF
Flask>=2.3.0
Flask-SQLAlchemy>=3.0.0
Flask-Migrate>=4.0.0
Flask-Login>=0.6.0
Flask-Mail>=0.9.0
Werkzeug>=2.3.0
APScheduler>=3.10.0
psutil>=5.9.0
WTForms>=3.0.0
pigpio>=1.78
EOF

pip install -r requirements.txt

echo -e "${GREEN}✅ Entorno Python configurado${NC}"

# ============================================
# FASE 4: Configuración de archivos
# ============================================
echo -e "\n${YELLOW}-> FASE 4: Configuración de archivos${NC}"

# Renombrar el archivo principal
mv "pi@raspberrypi~access_control_syste.txt" "app.py"

# Crear estructura de directorios
mkdir -p instance database logs backups migrations

# Crear archivo de configuración para forms.py (básico)
cat > forms.py << 'EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SelectField, TextAreaField
from wtforms.validators import DataRequired, Length, Email, Optional

class EditUserForm(FlaskForm):
    username = StringField('Usuario', validators=[DataRequired(), Length(min=3, max=80)])
    full_name = StringField('Nombre Completo', validators=[Length(max=120)])
    email = StringField('Email', validators=[Email(), Length(max=120)])
    role = SelectField('Rol', choices=[('user', 'Usuario'), ('admin', 'Administrador')])
    is_active = BooleanField('Cuenta Activa')
EOF

echo -e "${GREEN}✅ Archivos configurados${NC}"

# ============================================
# FASE 5: Función de detección de modo offline
# ============================================
echo -e "\n${YELLOW}-> FASE 5: Configuración de modo offline${NC}"

configure_offline_ethernet_ip() {
    echo "-> Detectando modo offline (sin internet)..."
    
    if ! ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
        echo "-> Sin internet detectado, configurando IP fija para portal offline"
        
        # Limpiar configuración previa de eth0
        ip addr flush dev eth0 2>/dev/null || true
        
        # Configurar IPs fijas
        ip addr add ${OFFLINE_IP_PRIMARY}/${OFFLINE_NETMASK} dev eth0 2>/dev/null || true
        ip addr add ${OFFLINE_IP_ALT1}/${OFFLINE_NETMASK} dev eth0 2>/dev/null || true
        ip addr add ${OFFLINE_IP_ALT2}/${OFFLINE_NETMASK} dev eth0 2>/dev/null || true
        ip link set eth0 up
        
        echo "-> ✅ IP fija configurada para modo offline"
        echo "   • IP principal: ${OFFLINE_IP_PRIMARY}"
        echo "   • IP alternativa 1: ${OFFLINE_IP_ALT1}" 
        echo "   • IP alternativa 2: ${OFFLINE_IP_ALT2}"
        
        return 0
    fi
    
    return 1
}

# ============================================
# FASE 6: Configuración de red y modo offline
# ============================================
echo -e "\n${YELLOW}-> FASE 6: Configuración de red y detección offline${NC}"

# Intentar configurar modo offline si no hay internet
if configure_offline_ethernet_ip; then
    echo -e "${YELLOW}-> Modo offline activado automáticamente${NC}"
    OFFLINE_MODE_ACTIVE=true
else
    echo -e "${GREEN}-> Conexión a internet disponible${NC}"
    OFFLINE_MODE_ACTIVE=false
fi

# ============================================
# FASE 7: Crear script de activación manual
# ============================================
echo -e "\n${YELLOW}-> FASE 7: Creando script de activación manual${NC}"

cat > "$OFFLINE_SCRIPT_PATH" << EOF
#!/bin/bash
# Script de activación manual para modo offline
# Usar cuando se necesite forzar el modo offline

echo "Activando modo offline manual..."

# Limpiar configuración previa de eth0
ip addr flush dev eth0 2>/dev/null || true

# Configurar IPs fijas
ip addr add ${OFFLINE_IP_PRIMARY}/${OFFLINE_NETMASK} dev eth0 2>/dev/null || true
ip addr add ${OFFLINE_IP_ALT1}/${OFFLINE_NETMASK} dev eth0 2>/dev/null || true
ip addr add ${OFFLINE_IP_ALT2}/${OFFLINE_NETMASK} dev eth0 2>/dev/null || true
ip link set eth0 up

echo "✅ Modo offline activado manualmente"
echo "Portal accesible en:"
echo "  • http://${OFFLINE_IP_PRIMARY}:${WEB_PORT}"
echo "  • http://${OFFLINE_IP_ALT1}:${WEB_PORT}"
echo "  • http://${OFFLINE_IP_ALT2}:${WEB_PORT}"
EOF

chmod +x "$OFFLINE_SCRIPT_PATH"

echo -e "${GREEN}✅ Script manual creado en $OFFLINE_SCRIPT_PATH${NC}"

# ============================================
# FASE 8: Configuración NetworkManager
# ============================================
echo -e "\n${YELLOW}-> FASE 8: Configuración NetworkManager${NC}"

# Crear configuración para NetworkManager que mantenga las IPs fijas
cat > /etc/NetworkManager/system-connections/offline-ethernet.nmconnection << EOF
[connection]
id=offline-ethernet
type=ethernet
interface-name=eth0
autoconnect=false

[ethernet]

[ipv4]
method=manual
address1=${OFFLINE_IP_PRIMARY}/${OFFLINE_NETMASK}
address2=${OFFLINE_IP_ALT1}/${OFFLINE_NETMASK}
address3=${OFFLINE_IP_ALT2}/${OFFLINE_NETMASK}

[ipv6]
method=ignore
EOF

chmod 600 /etc/NetworkManager/system-connections/offline-ethernet.nmconnection

echo -e "${GREEN}✅ Configuración NetworkManager creada${NC}"

# ============================================
# FASE 9: Servicio systemd para modo offline
# ============================================
echo -e "\n${YELLOW}-> FASE 9: Creando servicio systemd para modo offline${NC}"

cat > /etc/systemd/system/offline-portal-detector.service << EOF
[Unit]
Description=Detector de Modo Offline para Portal de Acceso
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if ! ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then nmcli connection up offline-ethernet; fi'
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable offline-portal-detector.service

echo -e "${GREEN}✅ Servicio offline creado y habilitado${NC}"

# ============================================
# FASE 10: Configuración del servicio principal
# ============================================
echo -e "\n${YELLOW}-> FASE 10: Configuración del servicio principal${NC}"

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Sistema de Control de Acceso
After=network.target
Requires=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SCRIPT_DIR
Environment=FLASK_RUN_HOST=0.0.0.0
Environment=FLASK_RUN_PORT=$WEB_PORT
Environment=PYTHONPATH=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/venv/bin/python app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service

# Cambiar propiedad de archivos al usuario del servicio
chown -R $SERVICE_USER:$SERVICE_USER "$SCRIPT_DIR"

echo -e "${GREEN}✅ Servicio principal configurado${NC}"

# ============================================
# FASE 11: Inicialización de la base de datos
# ============================================
echo -e "\n${YELLOW}-> FASE 11: Inicialización de la base de datos${NC}"

# Activar entorno virtual y ejecutar inicialización
cd "$SCRIPT_DIR"
source venv/bin/activate

# Crear usuario administrador por defecto si no existe
export FLASK_APP=app.py
sudo -u $SERVICE_USER bash -c "cd '$SCRIPT_DIR' && source venv/bin/activate && python -c \"
import os
os.environ['FLASK_APP'] = 'app.py'
from app import app, db, User
from werkzeug.security import generate_password_hash

with app.app_context():
    db.create_all()
    admin = User.query.filter_by(username='admin').first()
    if not admin:
        admin_user = User(
            username='admin',
            full_name='Administrador',
            email='admin@localhost',
            password_hash=generate_password_hash('admin123'),
            role='admin',
            is_active=True
        )
        db.session.add(admin_user)
        db.session.commit()
        print('Usuario admin creado con contraseña: admin123')
    else:
        print('Usuario admin ya existe')
\""

echo -e "${GREEN}✅ Base de datos inicializada${NC}"

# ============================================
# FASE 12: Iniciar servicios
# ============================================
echo -e "\n${YELLOW}-> FASE 12: Iniciando servicios${NC}"

systemctl start ${SERVICE_NAME}.service
systemctl start offline-portal-detector.service

echo -e "${GREEN}✅ Servicios iniciados${NC}"

# ============================================
# FASE 13: Mensaje final con URLs
# ============================================
echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA${NC}"
echo -e "${BLUE}============================================${NC}"

echo -e "\n${YELLOW}Portal de Control de Acceso configurado correctamente${NC}"
echo -e "\n${YELLOW}Acceso al portal:${NC}"

if [[ "$OFFLINE_MODE_ACTIVE" == "true" ]]; then
    echo -e "${YELLOW}MODO OFFLINE ACTIVO - Sin conexión a internet detectada${NC}"
    echo -e "Portal accesible en:"
    echo -e "  • ${GREEN}http://${OFFLINE_IP_PRIMARY}:${WEB_PORT}${NC} (IP principal)"
    echo -e "  • ${GREEN}http://${OFFLINE_IP_ALT1}:${WEB_PORT}${NC} (IP alternativa 1)"
    echo -e "  • ${GREEN}http://${OFFLINE_IP_ALT2}:${WEB_PORT}${NC} (IP alternativa 2)"
    echo -e "\n${YELLOW}Para conectar al TP-Link 3040:${NC}"
    echo -e "1. Conectar Raspberry Pi al TP-Link por ethernet"
    echo -e "2. Conectar PC/móvil al WiFi del TP-Link"
    echo -e "3. Ir a http://${OFFLINE_IP_PRIMARY}:${WEB_PORT}"
else
    echo -e "${GREEN}MODO ONLINE - Conexión a internet disponible${NC}"
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    echo -e "Portal accesible en:"
    echo -e "  • ${GREEN}http://${LOCAL_IP}:${WEB_PORT}${NC} (IP actual)"
    echo -e "  • ${GREEN}http://localhost:${WEB_PORT}${NC} (local)"
fi

echo -e "\n${YELLOW}Credenciales por defecto:${NC}"
echo -e "  Usuario: ${GREEN}admin${NC}"
echo -e "  Contraseña: ${GREEN}admin123${NC}"
echo -e "  ${RED}¡CAMBIAR LA CONTRASEÑA INMEDIATAMENTE!${NC}"

echo -e "\n${YELLOW}Script de activación manual offline:${NC}"
echo -e "  ${GREEN}sudo $OFFLINE_SCRIPT_PATH${NC}"

echo -e "\n${YELLOW}Comandos útiles:${NC}"
echo -e "  Ver estado: ${GREEN}sudo systemctl status ${SERVICE_NAME}${NC}"
echo -e "  Ver logs: ${GREEN}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
echo -e "  Reiniciar: ${GREEN}sudo systemctl restart ${SERVICE_NAME}${NC}"

echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}Instalación finalizada correctamente${NC}"
echo -e "${BLUE}============================================${NC}"