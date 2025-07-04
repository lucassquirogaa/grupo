#!/usr/bin/env python3
"""
Test básico de funciones offline sin dependencias Flask
"""

import subprocess
import os

def check_internet_connection():
    """Verifica si hay conexión a internet."""
    try:
        result = subprocess.run(
            ['ping', '-c1', '-W3', '8.8.8.8'], 
            capture_output=True, text=True, timeout=5
        )
        return result.returncode == 0
    except Exception as e:
        print(f"Error verificando conexión internet: {e}")
        return False

def get_offline_access_urls():
    """Retorna las URLs de acceso para modo offline."""
    port = os.environ.get('FLASK_RUN_PORT', '8080')
    return [
        f"http://192.168.100.1:{port}",
        f"http://192.168.1.200:{port}",
        f"http://192.168.0.200:{port}"
    ]

if __name__ == "__main__":
    print("🧪 Test básico de funciones offline")
    print("=" * 40)
    
    # Test 1: Función de URLs offline
    try:
        urls = get_offline_access_urls()
        print("✅ get_offline_access_urls() funciona")
        print(f"   URLs: {urls}")
    except Exception as e:
        print(f"❌ get_offline_access_urls() falló: {e}")
    
    # Test 2: Función de verificación de internet
    try:
        has_internet = check_internet_connection()
        print("✅ check_internet_connection() funciona")
        print(f"   Internet disponible: {has_internet}")
    except Exception as e:
        print(f"❌ check_internet_connection() falló: {e}")
    
    print("\n🎉 Test básico completado")