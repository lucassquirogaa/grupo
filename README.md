# Sistema de Control de Acceso con Modo Offline

Sistema de control de acceso para Raspberry Pi con soporte para modo offline cuando se conecta a TP-Link 3040 por ethernet.

## Características

- **Modo Online**: Funciona normalmente con conexión a internet
- **Modo Offline**: Se activa automáticamente cuando no hay internet, configurando IPs fijas
- **Portal Web**: Accesible a través de múltiples IPs para compatibilidad con diferentes TP-Link
- **Configuración WiFi**: Permite configurar WiFi desde el portal web

## Instalación

```bash
# Clonar el repositorio
git clone https://github.com/lucassquirogaa/grupo.git
cd grupo

# Ejecutar instalador (requiere sudo)
sudo ./install.sh
```

## Modo Offline

Cuando no hay conexión a internet, el sistema automáticamente:

1. **Detecta** la falta de conexión
2. **Configura** IPs fijas en ethernet:
   - `192.168.100.1` (principal)
   - `192.168.1.200` (alternativa 1)
   - `192.168.0.200` (alternativa 2)
3. **Hace accesible** el portal en `http://192.168.100.1:8080`

## Uso con TP-Link 3040

### Escenario típico:

1. **Instalar** en Raspberry Pi (con internet)
2. **Desconectar** WiFi del Raspberry Pi
3. **Conectar** Raspberry Pi al TP-Link por ethernet
4. **Conectar** PC/móvil al WiFi del TP-Link
5. **Acceder** a `http://192.168.100.1:8080`
6. **Configurar** WiFi del sitio desde el portal
7. **Desconectar** ethernet - Raspberry Pi se conecta al WiFi configurado

### URLs de acceso offline:

- **Principal**: `http://192.168.100.1:8080`
- **Alternativa 1**: `http://192.168.1.200:8080`
- **Alternativa 2**: `http://192.168.0.200:8080`

## Activación Manual

Si necesitas forzar el modo offline:

```bash
sudo /opt/enable-offline-portal.sh
```

## Comandos Útiles

```bash
# Ver estado del servicio
sudo systemctl status access_control

# Ver logs en tiempo real
sudo journalctl -u access_control -f

# Reiniciar servicio
sudo systemctl restart access_control

# Ver estado de red
sudo systemctl status offline-portal-detector
```

## Credenciales por Defecto

- **Usuario**: `admin`
- **Contraseña**: `admin123`

**¡IMPORTANTE!** Cambiar la contraseña inmediatamente después de la instalación.

## Arquitectura

```
┌─────────────────┐    ethernet    ┌─────────────────┐
│  Raspberry Pi   │ ──────────────► │   TP-Link 3040  │
│                 │                 │                 │
│ Portal: 8080    │                 │   WiFi AP Mode  │
│ IPs: 192.168.   │                 │                 │
│ 100.1/1.200/    │                 │                 │
│ 0.200           │                 │                 │
└─────────────────┘                 └─────────────────┘
                                             │ WiFi
                                             ▼
                                    ┌─────────────────┐
                                    │   PC/Móvil      │
                                    │                 │
                                    │ Accede:         │
                                    │ 192.168.100.1   │
                                    │ :8080           │
                                    └─────────────────┘
```

## Troubleshooting

### Portal no accesible

1. Verificar que el servicio esté ejecutándose:
   ```bash
   sudo systemctl status access_control
   ```

2. Verificar IPs configuradas:
   ```bash
   ip addr show eth0
   ```

3. Activar modo offline manualmente:
   ```bash
   sudo /opt/enable-offline-portal.sh
   ```

### No detecta modo offline

1. Verificar conectividad:
   ```bash
   ping -c1 8.8.8.8
   ```

2. Forzar activación:
   ```bash
   sudo systemctl start offline-portal-detector
   ```

## Estructura de Archivos

```
grupo/
├── install.sh              # Script de instalación principal
├── app.py                  # Aplicación Flask principal
├── forms.py                # Formularios WTF
├── requirements.txt        # Dependencias Python
├── README.md              # Este archivo
└── /opt/enable-offline-portal.sh  # Script activación manual
```

## Servicios Systemd

- `access_control.service`: Servicio principal del portal
- `offline-portal-detector.service`: Detector automático de modo offline

## Logs

Los logs se almacenan en:
- Servicio principal: `journalctl -u access_control`
- Detector offline: `journalctl -u offline-portal-detector`
- Aplicación: `logs/` (directorio del proyecto)