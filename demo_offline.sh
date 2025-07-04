#!/bin/bash

# ============================================
# Demo Script - Simulación Modo Offline
# ============================================

echo "🎬 Demostración del Modo Offline"
echo "================================"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${BLUE}Escenario: Raspberry Pi conectado al TP-Link 3040${NC}"
echo -e "${BLUE}============================================${NC}"

echo -e "\n${YELLOW}1. Estado inicial - Con internet:${NC}"
echo -e "   📡 WiFi conectado: SitioPrincipal"
echo -e "   🌐 Internet: ✅ Disponible"
echo -e "   🔗 Portal: http://192.168.1.150:8080"

echo -e "\n${YELLOW}2. Desconectar WiFi y conectar ethernet al TP-Link:${NC}"
echo -e "   📡 WiFi: ❌ Desconectado"
echo -e "   🔌 Ethernet: ✅ Conectado al TP-Link"
echo -e "   🌐 Internet: ❌ No disponible"

echo -e "\n${RED}[DETECTOR] Sin internet detectado...${NC}"
echo -e "${GREEN}[OFFLINE] Configurando IPs fijas:${NC}"
echo -e "   • IP principal: ${GREEN}192.168.100.1/24${NC}"
echo -e "   • IP alternativa 1: ${GREEN}192.168.1.200/24${NC}"
echo -e "   • IP alternativa 2: ${GREEN}192.168.0.200/24${NC}"

echo -e "\n${YELLOW}3. PC/móvil conectado al WiFi del TP-Link:${NC}"
echo -e "   📱 Dispositivo conectado a: TP-Link_3040"
echo -e "   🔗 Red: 192.168.100.x"

echo -e "\n${GREEN}4. Portal accesible en modo offline:${NC}"
echo -e "   🎯 URL principal: ${GREEN}http://192.168.100.1:8080${NC}"
echo -e "   🎯 URL alternativa 1: ${GREEN}http://192.168.1.200:8080${NC}"
echo -e "   🎯 URL alternativa 2: ${GREEN}http://192.168.0.200:8080${NC}"

echo -e "\n${YELLOW}5. Configurar WiFi desde el portal:${NC}"
echo -e "   🔧 Acceder a: Configuración > WiFi"
echo -e "   📝 Ingresar: SSID y contraseña del sitio"
echo -e "   💾 Guardar configuración"

echo -e "\n${YELLOW}6. Desconectar ethernet:${NC}"
echo -e "   🔌 Ethernet: ❌ Desconectado"
echo -e "   📡 WiFi: ✅ Conectando automáticamente..."
echo -e "   🌐 Internet: ✅ Restaurado"
echo -e "   🔗 Portal: http://[nueva-ip-wifi]:8080"

echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}✅ Configuración completada exitosamente${NC}"
echo -e "${BLUE}============================================${NC}"

echo -e "\n${YELLOW}Comandos para activación manual:${NC}"
echo -e "   ${GREEN}sudo /opt/enable-offline-portal.sh${NC}"
echo -e "   ${GREEN}sudo systemctl start offline-portal-detector${NC}"

echo -e "\n${YELLOW}Estado del sistema:${NC}"
echo -e "   Servicio principal: ${GREEN}access_control.service${NC}"
echo -e "   Detector offline: ${GREEN}offline-portal-detector.service${NC}"
echo -e "   Puerto web: ${GREEN}8080${NC}"
echo -e "   Usuario admin: ${GREEN}admin / admin123${NC}"

echo -e "\n${BLUE}Demo completada! 🎉${NC}"