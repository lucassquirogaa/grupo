#!/bin/bash

# ============================================
# Test Script para Modo Offline
# ============================================

echo "🧪 Ejecutando pruebas del modo offline..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

success_count=0
test_count=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    test_count=$((test_count + 1))
    echo -e "\n${YELLOW}Test $test_count: $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✅ PASÓ${NC}"
        success_count=$((success_count + 1))
    else
        echo -e "${RED}❌ FALLÓ${NC}"
    fi
}

# Test 1: Verificar que existe el script de instalación
run_test "Script de instalación existe" "[ -f 'install.sh' ]"

# Test 2: Verificar que el script es ejecutable
run_test "Script de instalación es ejecutable" "[ -x 'install.sh' ]"

# Test 3: Verificar que existe app.py
run_test "Archivo app.py existe" "[ -f 'app.py' ]"

# Test 4: Verificar que existe forms.py
run_test "Archivo forms.py existe" "[ -f 'forms.py' ]"

# Test 5: Verificar que existe requirements.txt
run_test "Archivo requirements.txt existe" "[ -f 'requirements.txt' ]"

# Test 6: Verificar funciones offline en app.py
run_test "Función check_internet_connection existe" "grep -q 'def check_internet_connection' app.py"

# Test 7: Verificar función configure_offline_ethernet_ip
run_test "Función configure_offline_ethernet_ip existe" "grep -q 'def configure_offline_ethernet_ip' app.py"

# Test 8: Verificar API offline
run_test "API offline/activate existe" "grep -q '/api/offline/activate' app.py"

# Test 9: Verificar puerto 8080 por defecto
run_test "Puerto por defecto es 8080" "grep -q 'FLASK_RUN_PORT.*8080' app.py"

# Test 10: Verificar IPs offline en app.py
run_test "IPs offline definidas correctamente" "grep -q '192.168.100.1' app.py && grep -q '192.168.1.200' app.py && grep -q '192.168.0.200' app.py"

echo -e "\n${YELLOW}============================================${NC}"
echo -e "${YELLOW}Resumen de pruebas:${NC}"
echo -e "Tests ejecutados: $test_count"
echo -e "Tests exitosos: ${GREEN}$success_count${NC}"
echo -e "Tests fallidos: ${RED}$((test_count - success_count))${NC}"

if [ $success_count -eq $test_count ]; then
    echo -e "\n${GREEN}🎉 ¡Todas las pruebas pasaron!${NC}"
    echo -e "${GREEN}El sistema está listo para la instalación.${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Algunas pruebas fallaron.${NC}"
    echo -e "${RED}Revisar la implementación antes de continuar.${NC}"
    exit 1
fi