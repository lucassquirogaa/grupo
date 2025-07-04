# -*- coding: utf-8 -*-
"""
Aplicación Flask principal para el Sistema de Control de Acceso.
Gestiona rutas web, autenticación, interacción con base de datos, hardware,
configuración del sistema y backups automáticos.
"""

# ============================================
# 1. IMPORTS
# ============================================
import os
import sys
import logging
import io
import atexit
import csv
import json
import subprocess
import shutil
import signal # For graceful shutdown
import secrets # For API Key generation
import string # For API Key characters
import threading  # Para crear el hilo del lector
import queue      # Para crear el "buzón" (cola)
import time

from logging.handlers import RotatingFileHandler
# *** timezone ESTÁ IMPORTADO CORRECTAMENTE ***
from datetime import datetime, timezone, timedelta, date, time as dt_time
from functools import wraps
from collections import namedtuple # For pagination fallback
from urllib.parse import urlparse, urljoin # For safe redirect checks (implement is_safe_url if needed)

# --- Third-Party Imports ---
from flask import (
    Flask, render_template, request, flash, redirect, url_for,
    make_response, session, jsonify, current_app, send_from_directory, abort, send_file,
    stream_with_context, Response, has_request_context
)
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from sqlalchemy import or_ # Para búsquedas OR
from flask_login import (
    LoginManager, UserMixin, login_user, logout_user, login_required, current_user
)
from sqlalchemy.exc import OperationalError, SQLAlchemyError, IntegrityError
from sqlalchemy.orm import joinedload
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from flask_mail import Mail, Message
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from forms import EditUserForm

# --- Hardware/System Specific Imports ---
try:
    import pigpio
    PIGPIO_AVAILABLE = True
except ImportError:
    PIGPIO_AVAILABLE = False
    print("ADVERTENCIA: pigpio no instalado o no accesible. Funcionalidad de hardware (Wiegand, Relé) DESACTIVADA.")

try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False
    print("ADVERTENCIA: psutil no instalado. Métricas del sistema no disponibles.")

# ============================================
# 2. CONSTANTES Y CONFIGURACIÓN INICIAL
# ============================================
APP_VERSION = "1.1.1" # Incrementar versión por correcciones
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
INSTANCE_DIR = os.path.join(BASE_DIR, 'instance')
DATABASE_DIR = os.path.join(BASE_DIR, 'database')
DATABASE_PATH = os.path.join(DATABASE_DIR, 'torre_access.db')
MIGRATIONS_DIR = os.path.join(BASE_DIR, 'migrations')
LOG_DIR = os.path.join(BASE_DIR, 'logs')
BACKUP_DIR = os.path.join(BASE_DIR, 'backups')
AUTO_BACKUP_CONFIG_FILE = os.path.join(INSTANCE_DIR, 'auto_backup_config.json')
SYSTEM_SETTINGS_FILE = os.path.join(INSTANCE_DIR, 'system_settings.json') # Para alertas, etc.

APP_DIRECTORY = BASE_DIR
SYSTEMD_SERVICE_NAME = 'access_control.service'

# --- Configuración Wiegand ---
WIEGAND_PIN_D0 = 7
WIEGAND_PIN_D1 = 8
WIEGAND_TIMEOUT_MS = 50
WIEGAND_EXPECTED_BITS = 26

# --- Configuración Hardware Adicional ---
RELAY_PIN = 12

# --- Variables Globales ---
HARDWARE_AVAILABLE = False # Se pondrá a True si setup_gpio() tiene éxito
wiegand_queue = queue.Queue()
_wiegand_bits_collector = []
_last_pulse_tick = 0
wiegand_thread_started = False

# --- Constantes de Umbrales y Paginación ---
ALERT_CPU_THRESHOLD = 85.0
ALERT_MEMORY_THRESHOLD = 85.0
ALERT_DISK_THRESHOLD = 90.0
DEFAULT_ACCESS_LOGS_PER_PAGE = 50
DEFAULT_SYSTEM_EVENTS_PER_PAGE = 50
API_KEY_LENGTH = 32
DEFAULT_OPENING_TIME_SECONDS = 5

# --- Asegurar Directorios ---
os.makedirs(INSTANCE_DIR, exist_ok=True)
os.makedirs(DATABASE_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(BACKUP_DIR, exist_ok=True)

# ============================================
# 3. CREACIÓN DE APP FLASK Y CONFIGURACIÓN
# ============================================
app = Flask(__name__)
app.jinja_env.add_extension('jinja2.ext.do')

# --- Configuración de la Aplicación ---
app.config['SECRET_KEY'] = os.environ.get('FLASK_SECRET_KEY', 'clave-secreta-muy-insegura-por-defecto-cambiar-ya!')
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{DATABASE_PATH}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=7)
app.config['REMEMBER_COOKIE_DURATION'] = timedelta(days=7)
app.config['REMEMBER_COOKIE_HTTPONLY'] = True
app.config['REMEMBER_COOKIE_SECURE'] = os.environ.get('FLASK_ENV') == 'production'
app.config['MIGRATIONS_DIR'] = MIGRATIONS_DIR

# --- Configuración de Flask-Mail ---
app.config['MAIL_SERVER'] = os.environ.get('MAIL_SERVER', 'smtp.gmail.com')
app.config['MAIL_PORT'] = int(os.environ.get('MAIL_PORT', 587))
app.config['MAIL_USE_TLS'] = os.environ.get('MAIL_USE_TLS', 'true').lower() in ['true', '1', 't']
app.config['MAIL_USE_SSL'] = os.environ.get('MAIL_USE_SSL', 'false').lower() in ['true', '1', 't']
app.config['MAIL_USERNAME'] = os.environ.get('MAIL_APP_USER')
app.config['MAIL_PASSWORD'] = os.environ.get('MAIL_APP_PASSWORD')
app.config['MAIL_DEFAULT_SENDER'] = os.environ.get('MAIL_DEFAULT_SENDER', app.config['MAIL_USERNAME'])
app.config['MAIL_SUPPRESS_SEND'] = app.testing

if not app.config['MAIL_USERNAME'] or not app.config['MAIL_PASSWORD']:
    print("ADVERTENCIA: MAIL_APP_USER o MAIL_APP_PASSWORD no están definidas como variables de entorno. El envío de emails fallará.")

# --- Configuración de Logging ---
log_formatter = logging.Formatter(
    '%(asctime)s [%(levelname)s] [%(name)s] in %(module)s:%(lineno)d: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
log_file_handler = RotatingFileHandler(
    os.path.join(LOG_DIR, 'app.log'), maxBytes=10*1024*1024, backupCount=5, encoding='utf-8'
)
log_file_handler.setFormatter(log_formatter)
log_file_handler.setLevel(logging.DEBUG)
app.logger.addHandler(log_file_handler)
app.logger.setLevel(logging.DEBUG if os.environ.get('FLASK_DEBUG') == '1' else logging.INFO)
app.logger.propagate = False
werkzeug_logger = logging.getLogger('werkzeug')
werkzeug_logger.handlers.clear()
werkzeug_logger.addHandler(log_file_handler)
werkzeug_logger.setLevel(logging.INFO)

# ============================================
# 4. INICIALIZACIÓN DE EXTENSIONES FLASK
# ============================================
db = SQLAlchemy(app)
migrate = Migrate(app, db, directory=app.config['MIGRATIONS_DIR'])
login_manager = LoginManager(app)
login_manager.login_view = 'login'
login_manager.login_message = "Debes iniciar sesión para acceder a esta página."
login_manager.login_message_category = "warning"
login_manager.session_protection = "strong"
mail = Mail(app)

# ============================================
# 5. INICIALIZACIÓN DEL SCHEDULER
# ============================================
scheduler = BackgroundScheduler(daemon=True, timezone='UTC')

# ============================================
# 6. MODELOS DE BASE DE DATOS
# ============================================
MODELS_IMPORTED_SUCCESSFULLY = False
try:
    from models import User, Keyfob, AccessLog, BackupLog, SystemEvent, APIKey
    MODELS_IMPORTED_SUCCESSFULLY = True
    app.logger.info("Modelos de base de datos importados correctamente.")
except Exception as e:
    app.logger.critical(f"ERROR CRÍTICO al importar modelos desde 'models.py': {e}. Verifica el archivo y sus dependencias.", exc_info=True)

# ============================================
# 7. USER LOADER PARA FLASK-LOGIN
# ============================================
@login_manager.user_loader
def load_user(user_id):
    if not MODELS_IMPORTED_SUCCESSFULLY: return None
    try: return db.session.get(User, int(user_id))
    except Exception as e:
        app.logger.error(f"Error al cargar usuario {user_id} desde BD: {e}", exc_info=True)
        return None

# ============================================
# 8. DECORADORES PERSONALIZADOS
# ============================================
def admin_required(f):
    @wraps(f)
    @login_required
    def decorated_function(*args, **kwargs):
        if not current_user or not hasattr(current_user, 'role') or current_user.role != 'admin':
            app.logger.warning(f"Acceso admin denegado para usuario '{getattr(current_user, 'username', 'Desconocido')}' a {request.path}")
            flash("No tienes permisos de administrador para acceder a esta página.", "danger")
            return redirect(url_for('dashboard'))
        return f(*args, **kwargs)
    return decorated_function

# ============================================
# 9. DEFINICIÓN DE FUNCIONES HELPER
# ============================================

def check_models_loaded(show_flash=False):
    """Verifica si los modelos de la BD se importaron correctamente."""
    if not MODELS_IMPORTED_SUCCESSFULLY:
        app.logger.error("Operación fallida: Modelos de base de datos no cargados.")
        if show_flash:
            flash("Error crítico: No se pueden realizar operaciones de base de datos.", "danger")
        return False
    return True

def log_system_event(level='INFO', event_type='Unknown', message=None, username=None, commit=True):
    """Registra un evento del sistema en el log y opcionalmente en la BD."""
    level_upper = level.upper()
    effective_username = username
    if effective_username is None:
        if has_request_context() and current_user and current_user.is_authenticated:
            effective_username = current_user.username
        else:
            effective_username = 'System'

    log_message_str = f"SYSTEM EVENT: {event_type} | Level: {level_upper} | User: {effective_username} | Details: {message or 'N/A'}"
    log_func = getattr(app.logger, level_upper.lower(), app.logger.info)
    log_func(log_message_str)

    if not check_models_loaded():
        app.logger.error("No se pudo guardar SystemEvent en BD (modelos no cargados).")
        return None

    try:
        user_db_id = None
        if effective_username != 'System':
            user_obj = User.query.filter(User.username.ilike(effective_username)).first()
            if user_obj: user_db_id = user_obj.id

        event = SystemEvent(
            level=level_upper, event_type=event_type, message=str(message)[:999] if message else None,
            username=effective_username if effective_username != 'System' else None,
            user_id=user_db_id,
            ip_address=request.remote_addr if has_request_context() and request else None,
            timestamp=datetime.now(timezone.utc)
        )
        db.session.add(event)
        if commit: db.session.commit()
        else: db.session.flush()
        return event
    except Exception as e:
        if commit: db.session.rollback()
        app.logger.error(f"Error al guardar SystemEvent en BD: {e}", exc_info=True)
        return None

# --- Helpers JSON Config ---
def load_json_config(filepath, default_config):
    """Carga configuración desde un archivo JSON, usando defaults si falla."""
    if not os.path.exists(filepath):
        app.logger.warning(f"Archivo de configuración no encontrado en {filepath}. Usando valores por defecto.")
        return default_config.copy()
    try:
        with open(filepath, 'r', encoding='utf-8') as f: config = json.load(f)
        for key, value in default_config.items(): config.setdefault(key, value)
        if filepath != AUTO_BACKUP_CONFIG_FILE: app.logger.info(f"Configuración cargada desde {filepath}.")
        return config
    except (json.JSONDecodeError, IOError, TypeError) as e:
        app.logger.error(f"Error leyendo config desde {filepath}: {e}. Usando valores por defecto.")
        return default_config.copy()

def save_json_config(filepath, config):
    """Guarda configuración en un archivo JSON."""
    try:
        with open(filepath, 'w', encoding='utf-8') as f: json.dump(config, f, indent=4)
        app.logger.info(f"Configuración guardada en {filepath}.")
        return True
    except IOError as e: app.logger.error(f"Error guardando config en {filepath}: {e}"); return False

# --- System Settings ---
def load_system_settings():
    """Carga configuraciones generales del sistema."""
    default = {"alerts_enabled": True, "opening_time": DEFAULT_OPENING_TIME_SECONDS}
    return load_json_config(SYSTEM_SETTINGS_FILE, default)

def get_opening_time():
    """Devuelve el tiempo de apertura en segundos desde la configuración."""
    try:
        settings = load_system_settings()
        time_val = int(settings.get('opening_time', DEFAULT_OPENING_TIME_SECONDS))
        return max(1, min(60, time_val)) # Limitar 1-60s
    except (ValueError, TypeError):
        app.logger.error(f"Error al obtener/convertir opening_time. Usando default: {DEFAULT_OPENING_TIME_SECONDS}s")
        return DEFAULT_OPENING_TIME_SECONDS

def save_system_settings(config):
    """Guarda configuraciones generales del sistema."""
    if save_json_config(SYSTEM_SETTINGS_FILE, config): return True
    else: flash("Error al guardar la configuración del sistema.", "danger"); return False

# --- Hardware Status ---
def get_hardware_status():
    """Obtiene el estado detallado de los componentes de hardware."""
    global PIGPIO_AVAILABLE, HARDWARE_AVAILABLE, wiegand_thread_started

    status = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "pigpio_available": PIGPIO_AVAILABLE,
        "gpio_setup_ok": HARDWARE_AVAILABLE,
        "pigpiod_connected": False,
        "relay_status": "unknown",        # Estado de la lectura del relé
        "relay_state_class": "warning",   # Clase CSS para estado lectura relé
        "lock_state": "unknown",          # Estado interpretado (locked/unlocked)
        "lock_state_class": "warning",    # Clase CSS para estado cerradura
        "wiegand_status": "desconocido",  # Estado del lector Wiegand
        "wiegand_status_class": "secondary", # Clase CSS para estado Wiegand
        "opening_time": get_opening_time()
    }

    pi_status = None
    if PIGPIO_AVAILABLE:
        try:
            pi_status = pigpio.pi()
            if pi_status.connected:
                status["pigpiod_connected"] = True
                try:
                    relay_level = pi_status.read(RELAY_PIN)
                    # Asumiendo ALTO=Locked(1), BAJO=Unlocked(0)
                    status['relay_status'] = 'ok'
                    status['relay_state_class'] = "success"
                    status['lock_state'] = 'locked' if relay_level == 1 else 'unlocked'
                    status['lock_state_class'] = "danger" if relay_level == 1 else "success"
                except Exception as e_relay:
                    app.logger.error(f"Error leyendo estado del relé ({RELAY_PIN}): {e_relay}")
                    status['relay_status'] = 'error_read'
                    status['relay_state_class'] = "danger"
                    status['lock_state'] = 'error'
                    status['lock_state_class'] = "danger"
            else:
                app.logger.warning("get_hardware_status: No se pudo conectar a pigpiod.")
                status['relay_status'] = 'error_conn'
                status['relay_state_class'] = "danger"
                status['lock_state'] = 'error'
                status['lock_state_class'] = "danger"
        except Exception as e_conn:
            app.logger.error(f"Error conectando a pigpiod en get_hardware_status: {e_conn}")
            status['relay_status'] = 'error_conn'
            status['relay_state_class'] = "danger"
            status['lock_state'] = 'error'
            status['lock_state_class'] = "danger"
        finally:
            if pi_status and pi_status.connected: pi_status.stop()
    else:
        status['relay_status'] = 'no_pigpio'
        status['relay_state_class'] = "danger"
        status['lock_state'] = 'error'
        status['lock_state_class'] = "danger"

    # Estado Wiegand Simplificado
    if PIGPIO_AVAILABLE and HARDWARE_AVAILABLE and wiegand_thread_started:
        status["wiegand_status"] = "activo" # Asume activo si el hilo se inició y HW ok
        status["wiegand_status_class"] = "success"
    elif not PIGPIO_AVAILABLE:
        status["wiegand_status"] = "error (pigpio)"
        status["wiegand_status_class"] = "danger"
    elif not HARDWARE_AVAILABLE:
        status["wiegand_status"] = "error (GPIO)"
        status["wiegand_status_class"] = "danger"
    else: # HW OK, pero hilo no iniciado
        status["wiegand_status"] = "inactivo"
        status["wiegand_status_class"] = "warning"

    return status

# --- GPIO Setup & Cleanup ---
def setup_gpio():
    """Configura los pines GPIO necesarios usando pigpio."""
    global HARDWARE_AVAILABLE, PIGPIO_AVAILABLE
    if not PIGPIO_AVAILABLE:
        print("ERROR CRÍTICO: [GPIO Setup] pigpio no disponible. Saltando configuración GPIO.")
        HARDWARE_AVAILABLE = False; return False
    pi_setup = None
    try:
        print("INFO: [GPIO Setup] Intentando conectar a pigpiod...")
        pi_setup = pigpio.pi()
        if not pi_setup.connected: raise ConnectionError("No se pudo conectar a pigpiod daemon.")
        print(f"INFO: [GPIO Setup] Configurando Pin Relé ({RELAY_PIN}) como SALIDA, inicial ALTO (Bloqueado).")
        pi_setup.set_mode(RELAY_PIN, pigpio.OUTPUT); pi_setup.write(RELAY_PIN, 1)
        print(f"INFO: [GPIO Setup] Configurando Pines Wiegand ({WIEGAND_PIN_D0}, {WIEGAND_PIN_D1}) como ENTRADA con PULL_UP.")
        pi_setup.set_mode(WIEGAND_PIN_D0, pigpio.INPUT); pi_setup.set_mode(WIEGAND_PIN_D1, pigpio.INPUT)
        pi_setup.set_pull_up_down(WIEGAND_PIN_D0, pigpio.PUD_UP); pi_setup.set_pull_up_down(WIEGAND_PIN_D1, pigpio.PUD_UP)
        print("INFO: [GPIO Setup] Configuración GPIO con pigpio completada.")
        HARDWARE_AVAILABLE = True; return True
    except Exception as e:
        print(f"ERROR CRÍTICO: [GPIO Setup] Falló la configuración GPIO con pigpio: {e}")
        HARDWARE_AVAILABLE = False; return False
    finally:
        if pi_setup and pi_setup.connected: pi_setup.stop()

def cleanup_gpio():
    """Limpia la configuración de los pines GPIO al salir."""
    global HARDWARE_AVAILABLE, PIGPIO_AVAILABLE
    print("\nINFO: [GPIO Cleanup] Iniciando limpieza de recursos GPIO...")
    if not PIGPIO_AVAILABLE or not HARDWARE_AVAILABLE:
        print("INFO: [GPIO Cleanup] Omitiendo limpieza (pigpio/Hardware no disponible o setup falló)."); return
    pi_cleanup = None
    try:
        pi_cleanup = pigpio.pi()
        if not pi_cleanup.connected: print("WARNING: [GPIO Cleanup] No se pudo conectar a pigpiod para limpiar."); return
        print(f"INFO: [GPIO Cleanup] Asegurando Relé ({RELAY_PIN}) en estado ALTO (Bloqueado) y devolviendo a INPUT.")
        pi_cleanup.set_mode(RELAY_PIN, pigpio.OUTPUT); pi_cleanup.write(RELAY_PIN, 1); pi_cleanup.set_mode(RELAY_PIN, pigpio.INPUT)
        print(f"INFO: [GPIO Cleanup] Devolviendo Pines Wiegand ({WIEGAND_PIN_D0}, {WIEGAND_PIN_D1}) a INPUT sin pull.")
        pi_cleanup.set_pull_up_down(WIEGAND_PIN_D0, pigpio.PUD_OFF); pi_cleanup.set_pull_up_down(WIEGAND_PIN_D1, pigpio.PUD_OFF)
        pi_cleanup.set_mode(WIEGAND_PIN_D0, pigpio.INPUT); pi_cleanup.set_mode(WIEGAND_PIN_D1, pigpio.INPUT)
        print("INFO: [GPIO Cleanup] Limpieza GPIO con pigpio completada.")
    except Exception as e: print(f"ERROR: [GPIO Cleanup] Excepción durante limpieza GPIO con pigpio: {e}")
    finally:
        if pi_cleanup and pi_cleanup.connected: pi_cleanup.stop()

# --- Door Control ---
def activate_relay(duration=None):
    """Activa el relé (abre la puerta) por una duración o usa el tiempo por defecto."""
    global HARDWARE_AVAILABLE
    if not HARDWARE_AVAILABLE: app.logger.warning("activate_relay: Hardware no disponible."); return False, "Hardware no disponible."
    activation_time = duration if duration is not None else get_opening_time()
    pi_relay = None
    try:
        pi_relay = pigpio.pi();
        if not pi_relay.connected: raise ConnectionError("pigpiod no conectado")
        app.logger.info(f"Activando relé ({RELAY_PIN}) por {activation_time} segundos...")
        pi_relay.write(RELAY_PIN, 0) # Activar (BAJO)
        time.sleep(activation_time)
        pi_relay.write(RELAY_PIN, 1) # Desactivar (ALTO)
        app.logger.info(f"Relé ({RELAY_PIN}) desactivado."); return True, f"Relé activado por {activation_time}s."
    except Exception as e:
        msg = f"Error activando relé: {e}"; app.logger.error(msg, exc_info=True)
        try: # Intentar asegurar estado bloqueado
            if pi_relay and pi_relay.connected: pi_relay.write(RELAY_PIN, 1)
        except Exception as e_sec: app.logger.error(f"Error secundario asegurando relé: {e_sec}")
        return False, msg
    finally:
        if pi_relay and pi_relay.connected: pi_relay.stop()

def open_door_momentarily(duration=None): return activate_relay(duration)
def lock_door():
    """Bloquea la puerta (pone el relé en estado inactivo/alto)."""
    global HARDWARE_AVAILABLE
    if not HARDWARE_AVAILABLE: return False, "Hardware no disponible."
    pi_relay = None
    try:
        pi_relay = pigpio.pi();
        if not pi_relay.connected: raise ConnectionError("pigpiod no conectado")
        pi_relay.write(RELAY_PIN, 1); app.logger.info(f"Puerta bloqueada (Relé {RELAY_PIN} -> ALTO)."); return True, "Puerta bloqueada."
    except Exception as e: msg = f"Error bloqueando puerta: {e}"; app.logger.error(msg, exc_info=True); return False, msg
    finally:
        if pi_relay and pi_relay.connected: pi_relay.stop()

def unlock_door_permanently():
    """Desbloquea la puerta permanentemente (pone el relé en estado activo/bajo)."""
    global HARDWARE_AVAILABLE
    if not HARDWARE_AVAILABLE: return False, "Hardware no disponible."
    pi_relay = None
    try:
        pi_relay = pigpio.pi();
        if not pi_relay.connected: raise ConnectionError("pigpiod no conectado")
        pi_relay.write(RELAY_PIN, 0); app.logger.warning(f"Puerta DESBLOQUEADA PERMANENTEMENTE (Relé {RELAY_PIN} -> BAJO)."); return True, "Puerta desbloqueada permanentemente."
    except Exception as e: msg = f"Error desbloqueando permanentemente: {e}"; app.logger.error(msg, exc_info=True); return False, msg
    finally:
        if pi_relay and pi_relay.connected: pi_relay.stop()

def set_opening_time(new_time_seconds):
    """Establece y guarda el tiempo de apertura en la configuración."""
    if not (1 <= new_time_seconds <= 60): return False, "Tiempo fuera de rango (1-60s)."
    try:
        settings = load_system_settings(); settings['opening_time'] = new_time_seconds
        if save_system_settings(settings): app.logger.info(f"Tiempo apertura guardado: {new_time_seconds}s."); return True, f"Tiempo apertura configurado a {new_time_seconds}s."
        else: return False, "Error al guardar config tiempo apertura."
    except Exception as e: app.logger.error(f"Error en set_opening_time: {e}", exc_info=True); return False, "Error interno config tiempo apertura."

# --- System Metrics ---
def get_system_metrics():
    """Obtiene métricas de uso de CPU, memoria, disco y temperatura."""
    global PSUTIL_AVAILABLE
    metrics = {'cpu': 0.0, 'memory': 0.0, 'disk': 0.0, 'cpu_temp': None, 'psutil_available': PSUTIL_AVAILABLE}
    if not PSUTIL_AVAILABLE: return metrics
    try:
        metrics['cpu'] = psutil.cpu_percent(interval=0.1)
        metrics['memory'] = psutil.virtual_memory().percent
        metrics['disk'] = psutil.disk_usage('/').percent
        # Temperatura CPU (varios métodos)
        if hasattr(psutil, "sensors_temperatures"):
            temps = psutil.sensors_temperatures()
            for name in ['coretemp', 'cpu_thermal', 'k10temp', 'acpitz', 'cpu-thermal']:
                 if name in temps:
                    valid_temps = [t.current for t in temps[name] if isinstance(t.current, (int, float)) and -20 < t.current < 120]
                    if valid_temps: metrics['cpu_temp'] = round(sum(valid_temps) / len(valid_temps), 1); break
        if metrics['cpu_temp'] is None:
            try: # Fallback lectura directa
                with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f: temp = int(f.read().strip()) / 1000.0
                if -20 < temp < 120: metrics['cpu_temp'] = round(temp, 1)
            except (FileNotFoundError, ValueError, TypeError, OSError): pass
    except Exception as e: app.logger.error(f"Error obteniendo métricas: {e}", exc_info=True)
    return metrics

# --- Wiegand Processing ---
def _wiegand_pulse_callback(gpio, level, tick):
    """Callback para pulsos Wiegand (solo flanco bajada)."""
    global _wiegand_bits_collector, _last_pulse_tick, WIEGAND_EXPECTED_BITS
    if level == 0:
        if len(_wiegand_bits_collector) >= WIEGAND_EXPECTED_BITS + 8: return
        if gpio == WIEGAND_PIN_D0: _wiegand_bits_collector.append(0)
        elif gpio == WIEGAND_PIN_D1: _wiegand_bits_collector.append(1)
        else: return
        _last_pulse_tick = tick

def _wiegand_process_data(bits):
    """Procesa bits Wiegand, valida y devuelve ID o None."""
    global WIEGAND_EXPECTED_BITS
    if len(bits) != WIEGAND_EXPECTED_BITS:
        app.logger.warning(f"Wiegand Error: Bits recibidos {len(bits)}, esperados {WIEGAND_EXPECTED_BITS}.")
        return None
    try: # Validación Paridad (Estándar 26bit)
        p0_ok = (sum(bits[1:13]) % 2) == bits[0]
        pN_ok = (sum(bits[13:25]) % 2) != bits[25]
        if not p0_ok: app.logger.warning("Wiegand: Falló paridad PAR (bit 0).")
        if not pN_ok: app.logger.warning("Wiegand: Falló paridad IMPAR (bit 25).")
    except IndexError: app.logger.error("Wiegand Error: Índice paridad."); return None

    try: # Extracción Facility Code y Card Number
        fc = int("".join(map(str, bits[1:9])), 2)
        cn = int("".join(map(str, bits[9:25])), 2)
        combined_id = (fc << 16) | cn
        app.logger.debug(f"Wiegand: FC={fc}, CN={cn} -> ID={combined_id}")
        return combined_id
    except (IndexError, ValueError) as e: app.logger.error(f"Wiegand Error extrayendo FC/CN: {e}"); return None

# <<< FUNCIÓN run_wiegand_reader_thread CORREGIDA >>>
def run_wiegand_reader_thread():
    """Función principal para el hilo lector Wiegand."""
    global _wiegand_bits_collector, _last_pulse_tick, PIGPIO_AVAILABLE, HARDWARE_AVAILABLE
    if not PIGPIO_AVAILABLE or not HARDWARE_AVAILABLE:
        app.logger.error("Hilo Wiegand NO INICIADO: pigpio/GPIO no disponible/falló."); return

    pi = None; cb0 = None; cb1 = None; thread_active = True
    app.logger.info("Iniciando hilo lector Wiegand...")

    while thread_active:
        try: # <<< TRY PRINCIPAL DEL BUCLE EXTERNO >>>
            pi = pigpio.pi()
            if not pi.connected:
                 app.logger.error("Wiegand Hilo Error: No se pudo conectar a pigpiod. Reintentando en 10s...")
                 time.sleep(10)
                 continue # Volver al inicio del while thread_active

            # Los pines ya fueron configurados en setup_gpio()
            cb0 = pi.callback(WIEGAND_PIN_D0, pigpio.FALLING_EDGE, _wiegand_pulse_callback)
            cb1 = pi.callback(WIEGAND_PIN_D1, pigpio.FALLING_EDGE, _wiegand_pulse_callback)
            app.logger.info(f"Lector Wiegand [pigpio] conectado y escuchando en D0={WIEGAND_PIN_D0}, D1={WIEGAND_PIN_D1}")
            _last_pulse_tick = pi.get_current_tick()

            # Bucle interno mientras está conectado
            while pi.connected:
                tick_now = pi.get_current_tick()
                if len(_wiegand_bits_collector) > 0:
                    # Verificar timeout desde el último pulso
                    time_since_last_pulse_us = pigpio.tickDiff(_last_pulse_tick, tick_now)
                    if time_since_last_pulse_us > (WIEGAND_TIMEOUT_MS * 1000):
                        # Copiar bits y limpiar colector ANTES de procesar
                        bits = list(_wiegand_bits_collector)
                        _wiegand_bits_collector = []
                        app.logger.debug(f"Wiegand: Timeout! Procesando {len(bits)} bits.")

                        # Procesar los datos copiados
                        cid = _wiegand_process_data(bits)
                        if cid is not None:
                            app.logger.info(f"Wiegand: ID Llavero Leído = {cid}")
                            try:
                                # Poner en la cola para el procesador principal
                                wiegand_queue.put(str(cid), block=False)
                                app.logger.debug(f"Wiegand: ID {cid} puesto en la cola.")
                            except queue.Full:
                                app.logger.error("Wiegand Error: La cola está llena. Descartando ID.")
                            except Exception as qe:
                                app.logger.error(f"Wiegand Error: No se pudo poner ID en la cola: {qe}")

                        # Actualizar el tick del último pulso (o del timeout)
                        _last_pulse_tick = tick_now

                # Pequeña pausa para evitar uso excesivo de CPU
                time.sleep(0.01)

            # Si sale del bucle interno, es porque pi.connected es False
            app.logger.error("Wiegand Hilo: Conexión pigpiod perdida. Intentando reconectar...")
            # El bucle externo (while thread_active) se encargará de reintentar

        except Exception as e: # <<< EXCEPT CORRESPONDIENTE AL TRY PRINCIPAL >>>
            # Captura errores de conexión, callbacks, etc.
            app.logger.error(f"Wiegand Hilo Error Crítico (Bucle Externo): {e}", exc_info=True)
            # Esperar antes de reintentar para no saturar logs si hay un problema persistente
            time.sleep(15)

        finally: # <<< FINALLY CORRESPONDIENTE AL TRY PRINCIPAL >>>
            # Este bloque se ejecuta SIEMPRE al salir del try, ya sea normalmente o por excepción
            app.logger.info("Wiegand Hilo: Limpiando recursos de esta iteración...")
            if cb0:
                try:
                    cb0.cancel()
                    app.logger.debug("Wiegand Hilo: Callback D0 cancelado.")
                except Exception as e_cb0:
                    app.logger.warning(f"Wiegand Hilo: Error menor cancelando callback D0: {e_cb0}")
                finally:
                    cb0 = None # Asegurar que se resetea
            if cb1:
                try:
                    cb1.cancel()
                    app.logger.debug("Wiegand Hilo: Callback D1 cancelado.")
                except Exception as e_cb1:
                    app.logger.warning(f"Wiegand Hilo: Error menor cancelando callback D1: {e_cb1}")
                finally:
                    cb1 = None # Asegurar que se resetea
            if pi and pi.connected:
                try:
                    pi.stop()
                    app.logger.info("Wiegand Hilo: Conexión pigpio detenida limpiamente.")
                except Exception as pe:
                    app.logger.error(f"Wiegand Hilo Error limpiando pigpio: {pe}")
                finally:
                    pi = None # Asegurar que se resetea
            else:
                # Asegurarse que pi es None si no estaba conectado o ya se detuvo
                pi = None

    # Esta línea solo se alcanza si thread_active se pone a False (no implementado ahora)
    app.logger.warning("Hilo lector Wiegand terminado permanentemente.")

# --- Scheduling & Access Logic ---
def check_schedule(keyfob):
    """Verifica si el llavero está dentro de su horario de activación."""
    if not keyfob.activation_schedule_enabled: return True
    now_local = datetime.now(); current_time = now_local.time(); current_weekday = now_local.strftime('%a').lower()
    if not keyfob.activation_days: app.logger.debug(f"Horario {keyfob.uid}: Hab. sin días."); return False
    allowed_days = keyfob.activation_days.lower().split(',')
    if current_weekday not in allowed_days: app.logger.debug(f"Horario {keyfob.uid}: Día {current_weekday} no en {allowed_days}."); return False
    if not keyfob.activation_start_time or not keyfob.activation_end_time: app.logger.debug(f"Horario {keyfob.uid}: Día OK, sin rango hora."); return True # Permitir todo el día
    start, end = keyfob.activation_start_time, keyfob.activation_end_time
    in_range = (start <= current_time < end) if start <= end else (current_time >= start or current_time < end)
    if not in_range: app.logger.debug(f"Horario {keyfob.uid}: Hora {current_time.strftime('%H:%M')} fuera de {start.strftime('%H:%M')}-{end.strftime('%H:%M')}."); return False
    app.logger.debug(f"Horario {keyfob.uid}: OK."); return True

def log_access_event(uid_attempted, keyfob_id, granted, reason, door_name='Principal'):
    """Registra un evento de intento de acceso en la BD."""
    if not check_models_loaded(): app.logger.error("No se pudo registrar AccessLog (modelos no cargados)."); return
    username = None; keyfob_desc = None
    if has_request_context() and current_user and current_user.is_authenticated: username = current_user.username
    if keyfob_id:
        try: keyfob = db.session.get(Keyfob, keyfob_id); keyfob_desc = keyfob.nombre_propietario or f"P:{keyfob.piso or '?'} D:{keyfob.departamento or '?'}" if keyfob else None
        except Exception as e_kf: app.logger.error(f"Error obteniendo Keyfob {keyfob_id} para log: {e_kf}")
    try:
        log = AccessLog(timestamp=datetime.now(timezone.utc), keyfob_uid_attempted=str(uid_attempted), keyfob_id=keyfob_id, access_granted=granted, reason=str(reason)[:255], username_at_time=username, keyfob_description_at_time=keyfob_desc[:100] if keyfob_desc else None, door_name=str(door_name)[:50])
        db.session.add(log); db.session.commit()
    except Exception as e: db.session.rollback(); app.logger.error(f"Error guardando AccessLog UID {uid_attempted}: {e}", exc_info=True)

# <<< FUNCIÓN process_wiegand_queue_task CORREGIDA >>>
def process_wiegand_queue_task():
    """Tarea del Scheduler para procesar IDs Wiegand de la cola."""
    with app.app_context():
        if not check_models_loaded(): return
        processed = 0; max_per_cycle = 10
        uid = None # Inicializar uid fuera del bucle para el logging de errores

        while not wiegand_queue.empty() and processed < max_per_cycle:
            try:
                uid = wiegand_queue.get_nowait(); processed += 1
                app.logger.info(f"Procesando Wiegand Queue: {uid}")
                keyfob = Keyfob.query.filter(Keyfob.uid.ilike(uid)).first()
                if keyfob:
                    if keyfob.is_active:
                        if check_schedule(keyfob):
                            app.logger.info(f"Acceso Concedido (Wiegand): UID={uid}, Nombre={keyfob.nombre_propietario}")
                            log_access_event(uid, keyfob.id, True, "Acceso Concedido (Wiegand)")
                            activate_relay()
                        else:
                            app.logger.warning(f"Acceso Denegado (Wiegand): UID={uid}, Razón=Fuera de horario")
                            log_access_event(uid, keyfob.id, False, "Acceso Denegado (Wiegand - Fuera de horario)")
                    else:
                        app.logger.warning(f"Acceso Denegado (Wiegand): UID={uid}, Razón=Llavero inactivo")
                        log_access_event(uid, keyfob.id, False, "Acceso Denegado (Wiegand - Llavero inactivo)")
                else:
                    app.logger.warning(f"Acceso Denegado (Wiegand): UID={uid}, Razón=Llavero desconocido")
                    log_access_event(uid, None, False, "Acceso Denegado (Wiegand - Llavero desconocido)")

                wiegand_queue.task_done()

            except queue.Empty:
                break # Salir del while si la cola está vacía
            except OperationalError as db_op_err:
                 app.logger.error(f"Error Operacional BD procesando Wiegand ({uid}): {db_op_err}. Reintentando más tarde.")
                 # No hacer task_done si es error de BD, para reintentar
                 break
            except Exception as e:
                # <<< BLOQUE EXCEPT CORREGIDO CON INDENTACIÓN ADECUADA >>>
                app.logger.error(f"Error procesando UID de Wiegand Queue ({uid}): {e}", exc_info=True)
                # Intentar marcar como hecho para evitar bucles infinitos con un item problemático
                try:
                    wiegand_queue.task_done()
                except ValueError:
                    # Ignorar si ya no estaba en la cola (raro, pero posible)
                    pass
                # <<< FIN BLOQUE EXCEPT CORREGIDO >>>

        # Fin del while not wiegand_queue.empty()

def start_wiegand_thread_once():
    """Inicia el hilo lector Wiegand si no está ya iniciado y el HW está OK."""
    global wiegand_thread_started, PIGPIO_AVAILABLE, HARDWARE_AVAILABLE
    if wiegand_thread_started: return
    if not PIGPIO_AVAILABLE or not HARDWARE_AVAILABLE: app.logger.error("No se inicia hilo Wiegand: pigpio/GPIO no disponible/falló."); return
    pi_check = None # Verificar conexión pigpiod ANTES
    try:
        pi_check = pigpio.pi();
        if not pi_check.connected: raise ConnectionError("No pigpiod daemon. ¿Corriendo? (sudo systemctl start pigpiod)")
        app.logger.info("Conexión pigpiod OK para hilo Wiegand.")
    except Exception as pe: app.logger.critical(f"FALLO CRÍTICO Wiegand pre-check: {pe}. Lector NO iniciado."); return
    finally:
        if pi_check and pi_check.connected: pi_check.stop()
    app.logger.info("Iniciando WiegandReaderThread en segundo plano...")
    thread = threading.Thread(target=run_wiegand_reader_thread, daemon=True, name="WiegandReaderThread")
    thread.start(); wiegand_thread_started = True

# --- Auto Backup ---
def load_auto_backup_config():
    """Carga la configuración del backup automático."""
    default = {"enabled": False, "frequency": "daily", "time": "03:00", "email": ""}
    config = load_json_config(AUTO_BACKUP_CONFIG_FILE, default)
    app.logger.info(f"Config auto-backup cargada: {config}")
    return config

def save_auto_backup_config(config):
    """Guarda la config de auto-backup y actualiza el scheduler."""
    if save_json_config(AUTO_BACKUP_CONFIG_FILE, config):
        try:
            if scheduler and scheduler.running: update_scheduler_job(config)
            else: app.logger.warning("Scheduler no encontrado/corriendo al guardar config backup.")
            return True
        except Exception as e_sched: app.logger.error(f"Error actualizando scheduler tras guardar config backup: {e_sched}"); flash("Config guardada, error actualizando tarea.", "warning"); return False
    else: flash("Error al guardar config backup.", "danger"); return False

def send_backup_email(recipient, attachment_path):
    """Envia el archivo de backup por email."""
    if not os.path.exists(attachment_path): app.logger.error(f"Email Backup: Adjunto no encontrado {attachment_path}"); log_system_event('ERROR', 'Auto Backup Email', f"Adjunto no encontrado: {os.path.basename(attachment_path)}", commit=True); return False
    if not app.config.get('MAIL_USERNAME') or not app.config.get('MAIL_PASSWORD'): app.logger.error("Email Backup: Credenciales email no configuradas."); log_system_event('ERROR', 'Auto Backup Email', "Credenciales email no config", commit=True); return False
    subject = f"Backup Sistema Acceso - {datetime.now(timezone.utc).strftime('%Y-%m-%d')}"
    body = f"Adjunto backup BD.\nFecha: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC\nArchivo: {os.path.basename(attachment_path)}"
    msg = Message(subject, recipients=[recipient], body=body)
    try:
        with open(attachment_path, "rb") as fp: msg.attach(os.path.basename(attachment_path), "application/octet-stream", fp.read())
        mail.send(msg); log_system_event('INFO', 'Auto Backup Email Sent', f"Email a {recipient}, Archivo: {os.path.basename(attachment_path)}", commit=True); return True
    except FileNotFoundError: app.logger.error(f"Email Backup: Archivo desapareció antes de leer: {attachment_path}"); log_system_event('CRITICAL', 'Auto Backup Email', f"Adjunto desapareció: {os.path.basename(attachment_path)}", commit=True); return False
    except Exception as e_mail: app.logger.error(f"Email Backup: Error enviando a {recipient}: {e_mail}", exc_info=True); log_system_event('ERROR', 'Auto Backup Email', f"Fallo envío a {recipient}: {e_mail}", commit=True); return False

def scheduled_backup_job():
    """Tarea Scheduler para backup automático."""
    with app.app_context():
        app.logger.info("APScheduler: Iniciando backup automático.")
        config = load_auto_backup_config()
        if not config.get('enabled'): app.logger.info("APScheduler: Backup auto deshabilitado."); return
        if not config.get('email'): app.logger.error("APScheduler: Backup habilitado sin email."); log_system_event('ERROR', 'Auto Backup Config', "Habilitado sin email", commit=True); return

        recipient = config['email']; backup_filepath = None; backup_success = False; status = "Failure"; message = "Backup auto fallido."; file_size = None
        timestamp_str = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S'); backup_filename = f"auto_backup_{timestamp_str}.db"; backup_filepath = os.path.join(BACKUP_DIR, backup_filename)

        if not os.path.exists(DATABASE_PATH): message = f"Error Crítico Auto Backup: BD no encontrada '{DATABASE_PATH}'"; app.logger.critical(message)
        else:
            try:
                command = ['sqlite3', DATABASE_PATH, f'.backup "{backup_filepath}"']; app.logger.debug(f"APScheduler: Ejecutando: {' '.join(command)}")
                process = subprocess.run(command, capture_output=True, text=True, check=False, timeout=60)
                if process.returncode == 0 and os.path.exists(backup_filepath):
                    file_size = os.path.getsize(backup_filepath)
                    if file_size > 100: status = "Success"; message = f"Backup auto creado: {backup_filename} ({file_size} bytes)."; backup_success = True; app.logger.info(f"APScheduler: {message}")
                    else: message = f"Auto Backup '{backup_filename}' vacío/pequeño ({file_size} bytes)."; app.logger.error(f"APScheduler: {message}")
                else: message = f"Error sqlite3 auto backup (código {process.returncode}): {process.stderr or process.stdout or 'Sin salida'}"; app.logger.error(f"APScheduler: {message}")
            except FileNotFoundError: message = "Error Crítico Auto Backup: 'sqlite3' no encontrado."; app.logger.critical(message)
            except subprocess.TimeoutExpired: message = "Error Auto Backup: Timeout (60s)."; app.logger.error(message)
            except Exception as e: message = f"Excepción auto backup: {e}"; app.logger.error(f"APScheduler: {message}", exc_info=True)

        if not backup_success and os.path.exists(backup_filepath):
            try: os.remove(backup_filepath); app.logger.info(f"APScheduler: Backup fallido {backup_filepath} eliminado.")
            except OSError as e_rm_auto: app.logger.error(f"APScheduler: No se pudo eliminar backup fallido {backup_filepath}: {e_rm_auto}")

        if check_models_loaded():
            try: log = BackupLog(timestamp=datetime.now(timezone.utc), status=status, message=message[:999], file_path=backup_filepath if backup_success else None, file_size=file_size if backup_success else None, triggered_by='AutoScheduler'); db.session.add(log); db.session.commit()
            except Exception as e_log: db.session.rollback(); app.logger.error(f"APScheduler: Error CRÍTICO al guardar log auto backup BD: {e_log}", exc_info=True)

        log_system_event(level='INFO' if backup_success else 'ERROR', event_type='Auto Backup Attempt', message=message, commit=False)
        if backup_success and backup_filepath:
            app.logger.info(f"APScheduler: Intentando enviar backup {backup_filename} a {recipient}")
            if send_backup_email(recipient, backup_filepath): app.logger.info(f"APScheduler: Email backup enviado a {recipient}.")
            else: app.logger.error(f"APScheduler: Backup creado ({backup_filename}) pero falló envío a {recipient}.")
        elif backup_success: app.logger.error("APScheduler: Backup OK pero falta ruta para email.")
        else: app.logger.info(f"APScheduler: No se envió email (backup falló).")

def update_scheduler_job(config):
    """Añade/actualiza jobs en el scheduler (Backup y Wiegand)."""
    global scheduler
    if not scheduler: app.logger.error("update_scheduler_job: Scheduler no encontrado."); return
    backup_job_id = 'scheduled_backup_job'; wiegand_job_id = 'wiegand_processor'
    try: # Backup Job
        if scheduler.get_job(backup_job_id): scheduler.remove_job(backup_job_id); app.logger.info(f"APScheduler: Job '{backup_job_id}' removido.")
    except Exception as e_rem: app.logger.error(f"APScheduler: Error removiendo '{backup_job_id}': {e_rem}")
    if config.get('enabled'):
        try:
            hour, minute = map(int, config.get('time', '03:00').split(':'))
            day_of_week = '*' if config.get('frequency') == 'daily' else config.get('frequency', 'sun')
            scheduler.add_job(scheduled_backup_job, trigger=CronTrigger(day_of_week=day_of_week, hour=hour, minute=minute, timezone='UTC'), id=backup_job_id, name='Automatic DB Backup', replace_existing=True, misfire_grace_time=3600)
            app.logger.info(f"APScheduler: Job '{backup_job_id}' programado. Freq: {config.get('frequency')}, Hora UTC: {hour:02d}:{minute:02d}, DoW: {day_of_week}")
        except Exception as e_add_b: app.logger.error(f"APScheduler: Error programando '{backup_job_id}': {e_add_b}", exc_info=True); log_system_event('ERROR', 'Scheduler Config', f"Error job backup: {e_add_b}", commit=True)
    else: app.logger.info(f"APScheduler: Backup auto deshabilitado, job '{backup_job_id}' no añadido.")
    try: # Wiegand Job
        if HARDWARE_AVAILABLE and PIGPIO_AVAILABLE:
            if not scheduler.get_job(wiegand_job_id): scheduler.add_job(id=wiegand_job_id, func=process_wiegand_queue_task, trigger='interval', seconds=0.1, max_instances=1, name='Wiegand Queue Processor'); app.logger.info(f"APScheduler: Job '{wiegand_job_id}' añadido.")
            else: app.logger.debug(f"APScheduler: Job '{wiegand_job_id}' ya existe.")
        else: # Si HW no disponible, asegurar que no corra
            if scheduler.get_job(wiegand_job_id): scheduler.remove_job(wiegand_job_id); app.logger.warning(f"APScheduler: Job Wiegand '{wiegand_job_id}' removido (HW no disponible).")
    except Exception as e_wiegand: app.logger.error(f"APScheduler: Error con job Wiegand '{wiegand_job_id}': {e_wiegand}", exc_info=True); log_system_event('ERROR', 'Scheduler Config', f"Error job Wiegand: {e_wiegand}", commit=True)

def get_current_wifi_ssid():
    """Obtiene el SSID WiFi actual usando nmcli o iwgetid."""
    app.logger.debug("Obteniendo SSID actual...")
    try:
        # Intentar con nmcli primero
        res = subprocess.run(
            ['nmcli', '-t', '-f', 'ACTIVE,SSID', 'dev', 'wifi'],
            capture_output=True, text=True, check=True, timeout=5
        )
        for line in res.stdout.strip().split('\n'):
            if line.startswith('yes:'):
                ssid = line.split(':', 1)[1]
                return ssid if ssid else "Conectado (Oculto?)"
        return "Desconectado" # Si 'yes:' no se encontró

    except FileNotFoundError:
        app.logger.error("'nmcli' no encontrado. Intentando con 'iwgetid'...")
        # Fallback a iwgetid si nmcli no está
        try:
            res_iw = subprocess.run(['iwgetid', '-r'], capture_output=True, text=True, check=True, timeout=5)
            return res_iw.stdout.strip() or "Desconectado"
        except FileNotFoundError:
            app.logger.error("'iwgetid' tampoco encontrado.")
            return "Error (cmd no enc.)"
        except Exception as e_iw:
            app.logger.warning(f"iwgetid falló: {e_iw}")
            return "Desconocido (iwgetid err)"

    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        app.logger.warning(f"nmcli falló: {e.stderr or e.stdout or e}. Intentando con 'iwgetid'...")
        # Fallback a iwgetid si nmcli falló
        try:
            res_iw = subprocess.run(['iwgetid', '-r'], capture_output=True, text=True, check=True, timeout=5)
            return res_iw.stdout.strip() or "Desconectado"
        except FileNotFoundError:
            app.logger.error("'iwgetid' no encontrado como fallback.")
            return "Error (cmd no enc.)"
        except Exception as e_iw:
            app.logger.warning(f"iwgetid falló como fallback: {e_iw}")
            return "Desconocido (iwgetid err)"

    except Exception as e_gen:
        app.logger.error(f"Error general obteniendo SSID: {e_gen}")
        return "Error (general)"

# --- Offline Mode Functions ---
def check_internet_connection():
    """Verifica si hay conexión a internet."""
    try:
        result = subprocess.run(
            ['ping', '-c1', '-W3', '8.8.8.8'], 
            capture_output=True, text=True, timeout=5
        )
        return result.returncode == 0
    except Exception as e:
        app.logger.warning(f"Error verificando conexión internet: {e}")
        return False

def configure_offline_ethernet_ip():
    """Configura IPs fijas en ethernet para modo offline."""
    app.logger.info("Detectando modo offline (sin internet)...")
    
    if not check_internet_connection():
        app.logger.info("Sin internet detectado, configurando IP fija para portal offline")
        
        try:
            # Limpiar configuración previa de eth0
            subprocess.run(['ip', 'addr', 'flush', 'dev', 'eth0'], 
                         capture_output=True, check=False)
            
            # Configurar IPs fijas
            offline_ips = [
                "192.168.100.1/24",
                "192.168.1.200/24", 
                "192.168.0.200/24"
            ]
            
            for ip in offline_ips:
                subprocess.run(['ip', 'addr', 'add', ip, 'dev', 'eth0'], 
                             capture_output=True, check=False)
            
            subprocess.run(['ip', 'link', 'set', 'eth0', 'up'], 
                         capture_output=True, check=False)
            
            app.logger.info("✅ IP fija configurada para modo offline")
            app.logger.info("   • IP principal: 192.168.100.1")
            app.logger.info("   • IP alternativa 1: 192.168.1.200") 
            app.logger.info("   • IP alternativa 2: 192.168.0.200")
            
            return True
        except Exception as e:
            app.logger.error(f"Error configurando IPs offline: {e}")
            return False
    
    return False

def get_offline_access_urls():
    """Retorna las URLs de acceso para modo offline."""
    port = os.environ.get('FLASK_RUN_PORT', '5000')
    return [
        f"http://192.168.100.1:{port}",
        f"http://192.168.1.200:{port}",
        f"http://192.168.0.200:{port}"
    ]

def get_system_network_status():
    """Obtiene el estado de red del sistema."""
    try:
        has_internet = check_internet_connection()
        current_ssid = get_current_wifi_ssid()
        
        # Obtener IP actual
        try:
            hostname_result = subprocess.run(['hostname', '-I'], 
                                           capture_output=True, text=True, timeout=5)
            current_ip = hostname_result.stdout.strip().split()[0] if hostname_result.stdout.strip() else "No disponible"
        except:
            current_ip = "No disponible"
        
        return {
            "has_internet": has_internet,
            "current_ssid": current_ssid,
            "current_ip": current_ip,
            "offline_urls": get_offline_access_urls(),
            "is_offline_mode": not has_internet
        }
    except Exception as e:
        app.logger.error(f"Error obteniendo estado de red: {e}")
        return {
            "has_internet": False,
            "current_ssid": "Error",
            "current_ip": "Error", 
            "offline_urls": get_offline_access_urls(),
            "is_offline_mode": True
        }

# --- API Keys ---
def generate_api_key(length=API_KEY_LENGTH):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))
def hash_api_key(api_key): return generate_password_hash(api_key, method='pbkdf2:sha256')
def check_api_key(key_hash, provided_key): return check_password_hash(key_hash, provided_key)

# --- DB Init ---
def initialize_database():
    """Crea tablas y usuario admin inicial si no existen."""
    with app.app_context():
        if not check_models_loaded(): app.logger.critical("SALTANDO init BD: Modelos no cargados."); return
        app.logger.info("Verificando/Creando tablas BD...")
        try: db.create_all(); app.logger.info("Tablas BD OK.")
        except Exception as e_create: app.logger.critical(f"ERROR CRÍTICO CREANDO/CONECTANDO BD: {e_create}", exc_info=True); return
        try:
            if not User.query.filter_by(role='admin').first():
                admin_user = os.environ.get('ADMIN_USER', 'admin'); admin_pass = os.environ.get('ADMIN_PASSWORD', 'password'); admin_email = os.environ.get('ADMIN_EMAIL', '')
                if admin_pass == 'password': app.logger.warning("USANDO CONTRASEÑA ADMIN POR DEFECTO")
                user = User(username=admin_user, role='admin', is_active=True, email=admin_email or None)
                if hasattr(user, 'set_password'): user.set_password(admin_pass)
                else: user.password_hash = generate_password_hash(admin_pass, method='pbkdf2:sha256')
                db.session.add(user); db.session.commit(); app.logger.info(f"Admin inicial '{admin_user}' creado."); log_system_event('INFO', 'System Init', f"Admin '{admin_user}' creado", commit=False)
            else: app.logger.info("Admin ya existe.")
        except Exception as e_admin: db.session.rollback(); app.logger.error(f"Error creando/verificando admin: {e_admin}", exc_info=True)

# --- Shutdown Handling ---
def cleanup_on_shutdown():
    """Tareas de limpieza al cerrar la aplicación."""
    print("\n"); app.logger.info("="*40); app.logger.info("Iniciando cierre limpio..."); app.logger.info("Cierre limpio completado."); app.logger.info("="*40); logging.shutdown()
def handle_signal(sig, frame):
    """Maneja señales SIGINT/SIGTERM para cierre limpio."""
    print("\n"); signal_name = signal.Signals(sig).name; app.logger.warning(f"Señal '{signal_name}' ({sig}) recibida. Iniciando cierre..."); sys.exit(0)
def shutdown_scheduler():
    """Detiene el APScheduler limpiamente."""
    global scheduler
    if 'scheduler' in globals() and scheduler and scheduler.running:
        print("INFO: Deteniendo APScheduler...")
        try:
            scheduler.shutdown()
            print("INFO: APScheduler detenido.")
        except Exception as e:
            print(f"ERROR deteniendo APScheduler: {e}")
    else:
        print("INFO: APScheduler no corriendo/definido al intentar detener.")

# ============================================
# 10. CONTEXT PROCESSORS, HOOKS, ERROR HANDLERS
# ============================================

@app.context_processor
def inject_global_vars():
    """Inyecta variables globales en el contexto de las plantillas."""
    global HARDWARE_AVAILABLE, PSUTIL_AVAILABLE, MODELS_IMPORTED_SUCCESSFULLY, APP_VERSION, RELAY_PIN
    return dict(
        current_year=datetime.now(timezone.utc).year,
        current_time_utc_iso=datetime.now(timezone.utc).isoformat(),
        HARDWARE_AVAILABLE=HARDWARE_AVAILABLE,
        PSUTIL_AVAILABLE=PSUTIL_AVAILABLE,
        MODELS_LOADED=MODELS_IMPORTED_SUCCESSFULLY,
        APP_VERSION=APP_VERSION,
        RELAY_PIN=RELAY_PIN,
        ALERT_CPU_THRESHOLD=ALERT_CPU_THRESHOLD,
        ALERT_MEMORY_THRESHOLD=ALERT_MEMORY_THRESHOLD,
        ALERT_DISK_THRESHOLD=ALERT_DISK_THRESHOLD
    )

# <<< FILTRO format_datetime_local CORREGIDO Y UBICADO AQUÍ >>>
@app.template_filter('format_datetime_local')
def format_datetime_local_filter(dt_utc):
    """Filtro Jinja para formatear un datetime UTC a la zona local del servidor."""
    if dt_utc is None:
        return "" # O puedes devolver 'N/A'

    # Asegurar que el datetime es timezone-aware (UTC)
    try:
        if dt_utc.tzinfo is None:
            # Si es naive, asumimos que es UTC (común desde BD)
            dt_utc = dt_utc.replace(tzinfo=timezone.utc)
        else:
            # Si ya tiene zona, convertir explícitamente a UTC
            dt_utc = dt_utc.astimezone(timezone.utc)
    except Exception as e_tz:
        app.logger.error(f"Error asegurando zona horaria UTC en filtro: {e_tz}. Valor: {dt_utc}")
        return str(dt_utc) + " (Error TZ)" # Devolver algo indicando el error

    # Convertir a la zona horaria local del servidor
    try:
        dt_local = dt_utc.astimezone(None) # None usa la zona local del sistema
    except Exception as e_local:
        # Fallback si hay problemas con la zona local
        app.logger.error(f"Error convirtiendo a zona local en filtro: {e_local}. Devolviendo UTC.")
        try:
            return dt_utc.strftime('%Y-%m-%d %H:%M:%S (UTC)')
        except Exception: # Por si dt_utc es inválido
             return str(dt_utc) + " (Error Local+UTC)"

    # Formatear
    try:
        # Puedes cambiar el formato si prefieres otro (ej. '%d/%m/%Y %H:%M')
        return dt_local.strftime('%Y-%m-%d %H:%M:%S')
    except Exception as e_format:
        app.logger.error(f"Error formateando fecha local en filtro: {e_format}. Devolviendo UTC.")
        try:
            return dt_utc.strftime('%Y-%m-%d %H:%M:%S (UTC)')
        except Exception:
             return str(dt_utc) + " (Error Format)"

@app.before_request
def before_request_func(): pass # Placeholder

@app.after_request
def after_request_func(response):
    """Añade cabeceras de seguridad a todas las respuestas."""
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    return response

@app.teardown_appcontext
def shutdown_session(exception=None):
    """Limpia la sesión de la BD al final de cada request."""
    if not MODELS_IMPORTED_SUCCESSFULLY: return
    if exception:
        try:
            if db.session.is_active: db.session.rollback(); app.logger.warning(f"Rollback DB por excepción en teardown: {exception}")
        except Exception as e_rb: app.logger.error(f"Error rollback en teardown: {e_rb}", exc_info=True)
    try: db.session.remove()
    except Exception as e_rm: app.logger.error(f"Error db.session.remove() en teardown: {e_rm}", exc_info=True)

# --- Error Handlers ---
@app.errorhandler(404)
def page_not_found(e):
    log_system_event('WARNING', 'Not Found', message=f"Ruta no encontrada (404): {request.path}")
    return render_template('error.html', error_code=404, error_message="La página que buscas no existe."), 404

@app.errorhandler(403)
def forbidden(e):
    log_system_event('WARNING', 'Forbidden', message=f"Acceso prohibido (403) a {request.path} por {current_user.username if current_user.is_authenticated else 'anónimo'}")
    return render_template('error.html', error_code=403, error_message="No tienes permiso para acceder a este recurso."), 403

@app.errorhandler(500)
@app.errorhandler(Exception)
def internal_server_error(e):
    original_exception = getattr(e, "original_exception", e)
    app.logger.error(f"Error interno (500/Exception) en {request.path}: {original_exception}", exc_info=True)
    try:
        if MODELS_IMPORTED_SUCCESSFULLY and db.session.is_active: db.session.rollback()
    except Exception as e_rb500: app.logger.error(f"Error rollback en handler 500/Exception: {e_rb500}", exc_info=True)
    error_msg = "Ocurrió un error interno inesperado."
    if app.debug: error_msg += f" ({original_exception})"
    return render_template('error.html', error_code=500, error_message=error_msg), 500

@app.errorhandler(OperationalError)
def handle_db_operational_error(e):
    app.logger.critical(f"Error Operacional BD en {request.path}: {e}", exc_info=True)
    return render_template('error.html', error_code=503, error_message="Error de conexión con la base de datos. Verifica que el servicio esté corriendo."), 503

@app.errorhandler(SQLAlchemyError)
def handle_sqlalchemy_error(e):
    app.logger.error(f"Error SQLAlchemy en {request.path}: {e}", exc_info=True)
    try:
        if MODELS_IMPORTED_SUCCESSFULLY and db.session.is_active: db.session.rollback()
    except Exception as e_rbSQLA: app.logger.error(f"Error rollback en handler SQLAlchemyError: {e_rbSQLA}", exc_info=True)
    return render_template('error.html', error_code=500, error_message="Error relacionado con la base de datos."), 500

# ============================================
# 11. RUTAS FLASK (@app.route)
# ============================================

# --- Autenticación ---
@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated: return redirect(url_for('dashboard'))
    if request.method == 'POST':
        username = request.form.get('username', '').strip(); password = request.form.get('password', ''); remember = 'remember' in request.form
        if not username or not password: flash('Usuario y contraseña requeridos.', 'warning'); return render_template('login.html'), 400
        if not check_models_loaded(show_flash=True): log_system_event('CRITICAL', 'Login Fallido', username, "Modelos no cargados"); return render_template('login.html'), 503
        user = User.query.filter(User.username.ilike(username)).first()
        valid_pass = user and (user.check_password(password) if hasattr(user, 'check_password') else check_password_hash(user.password_hash, password))
        if user and valid_pass:
            if not getattr(user, 'is_active', True): log_system_event('WARNING', 'Login Fallido', username, "Cuenta inactiva"); flash('Tu cuenta está desactivada.', 'danger'); return render_template('login.html'), 403
            try:
                login_user(user, remember=remember)
                if hasattr(user, 'last_login'): user.last_login = datetime.now(timezone.utc); db.session.commit()
                log_system_event('INFO', 'Login Exitoso', username); flash(f'Bienvenido, {user.username}!', 'success')
                next_page = request.args.get('next'); return redirect(next_page) if next_page and urlparse(next_page).netloc == '' else redirect(url_for('dashboard'))
            except Exception as e_login: db.session.rollback(); app.logger.error(f"Error login {username}: {e_login}", exc_info=True); flash("Error inicio sesión.", "danger"); return render_template('login.html'), 500
        else: log_system_event('WARNING', 'Login Fallido', username, "Credenciales incorrectas"); flash('Usuario o contraseña incorrectos.', 'danger'); return render_template('login.html'), 401
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    username = getattr(current_user, 'username', 'Desconocido'); logout_user(); log_system_event('INFO', 'Logout', username); flash("Has cerrado sesión.", "success"); return redirect(url_for('login'))

# --- Dashboard ---
@app.route('/')
@app.route('/dashboard')
@login_required
def dashboard():
    app.logger.debug(f"Accediendo /dashboard ({current_user.username})")
    hardware_status = get_hardware_status()
    system_metrics = get_system_metrics()
    keyfob_stats = {'active': 0, 'inactive': 0, 'total': 0}
    access_stats = {'granted_today': 0, 'denied_today': 0}
    recent_logs = []; recent_system_events = []; backup_alert = False; event_alert = False

    if check_models_loaded():
        try:
            keyfob_stats['active'] = db.session.query(Keyfob.id).filter_by(is_active=True).count()
            keyfob_stats['inactive'] = db.session.query(Keyfob.id).filter_by(is_active=False).count()
            keyfob_stats['total'] = keyfob_stats['active'] + keyfob_stats['inactive']
            today_start_utc = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
            access_stats['granted_today'] = db.session.query(AccessLog.id).filter(AccessLog.timestamp >= today_start_utc, AccessLog.access_granted == True).count()
            access_stats['denied_today'] = db.session.query(AccessLog.id).filter(AccessLog.timestamp >= today_start_utc, AccessLog.access_granted == False).count()
            recent_logs = AccessLog.query.options(joinedload(AccessLog.keyfob)).order_by(AccessLog.timestamp.desc()).limit(3).all()
            recent_system_events = SystemEvent.query.order_by(SystemEvent.timestamp.desc()).limit(5).all()
            # Alertas
            last_backup = BackupLog.query.filter_by(status='Success').order_by(BackupLog.timestamp.desc()).first()
            one_day_ago = datetime.now(timezone.utc) - timedelta(days=1)
            if not last_backup or (last_backup.timestamp and last_backup.timestamp.replace(tzinfo=timezone.utc) < one_day_ago): backup_alert = True
            if db.session.query(SystemEvent.id).filter(SystemEvent.timestamp >= one_day_ago, SystemEvent.level.in_(['ERROR', 'CRITICAL'])).limit(1).count() > 0: event_alert = True
        except Exception as e: app.logger.error(f"Error BD dashboard: {e}", exc_info=True); flash("Error cargando datos dashboard.", "danger")
    else: flash("Advertencia: Funcionalidad BD limitada.", "warning")

    return render_template('dashboard.html',
                           hardware_status=hardware_status, system_metrics=system_metrics,
                           keyfob_stats=keyfob_stats, access_stats=access_stats,
                           recent_logs=recent_logs, recent_system_events=recent_system_events,
                           backup_alert=backup_alert, event_alert=event_alert)

# --- Keyfobs ---
@app.route('/keyfobs')
@login_required
def manage_keyfobs():
    app.logger.debug(f"Accediendo /keyfobs ({current_user.username})")
    id_search = request.args.get('id_search', '').strip(); piso_search = request.args.get('piso_search', '').strip()
    pagination = None
    if check_models_loaded():
        try:
            query = Keyfob.query; filters = []
            if id_search: filters.append(Keyfob.uid.ilike(f"%{id_search}%"))
            if piso_search: filters.append(Keyfob.piso.ilike(f"%{piso_search}%"))
            if filters: query = query.filter(*filters)
            page = request.args.get('page', 1, type=int); per_page = 12
            pagination = query.order_by(Keyfob.uid).paginate(page=page, per_page=per_page, error_out=False)
        except Exception as e: app.logger.error(f"Error llaveros: {e}", exc_info=True); flash("Error cargando llaveros.", "danger")
    else: flash("No se pueden gestionar llaveros (Error BD).", "danger")
    return render_template('manage_keyfobs.html', keyfobs=pagination.items if pagination else [], pagination=pagination, id_search=id_search, piso_search=piso_search)

@app.route('/keyfobs/add', methods=['POST'])
@login_required
def add_keyfob():
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_keyfobs'))
    uid = request.form.get('uid', '').strip()[:50]; piso = request.form.get('piso', '').strip()[:50]; depto = request.form.get('departamento', '').strip()[:50]; nombre = request.form.get('nombre_propietario', '').strip()[:100]; is_active = 'is_active' in request.form; schedule_enabled = 'activation_schedule_enabled' in request.form; days_list = request.form.getlist('activation_days'); start_str = request.form.get('activation_start_time'); end_str = request.form.get('activation_end_time')
    if not uid: flash("UID obligatorio.", "warning"); return redirect(url_for('manage_keyfobs'))
    if Keyfob.query.filter(Keyfob.uid.ilike(uid)).first(): flash(f"UID '{uid}' ya registrado.", "danger"); return redirect(url_for('manage_keyfobs'))
    days, start, end = None, None, None
    if schedule_enabled:
        days = ",".join(days_list) if days_list else None
        try:
            if start_str: start = datetime.strptime(start_str, '%H:%M').time()
            if end_str: end = datetime.strptime(end_str, '%H:%M').time()
        except ValueError: flash("Formato hora inválido.", "warning"); schedule_enabled=False
    try:
        kf = Keyfob(uid=uid, piso=piso or None, departamento=depto or None, nombre_propietario=nombre or None, is_active=is_active, last_edited_by=current_user.username, activation_schedule_enabled=schedule_enabled, activation_days=days, activation_start_time=start, activation_end_time=end)
        db.session.add(kf); db.session.commit(); log_system_event('INFO', 'Llavero Añadido', f"UID: {uid}, Nombre: {nombre}, Act: {is_active}"); flash(f"Llavero '{uid}' añadido.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error añadiendo llavero {uid}: {e}", exc_info=True); flash(f"Error añadiendo '{uid}'.", "danger")
    return redirect(url_for('manage_keyfobs'))

@app.route('/keyfobs/edit/<int:keyfob_id>', methods=['POST'])
@login_required
def edit_keyfob(keyfob_id):
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_keyfobs'))
    kf = db.session.get(Keyfob, keyfob_id);
    if not kf: flash("Llavero no encontrado.", "danger"); return redirect(url_for('manage_keyfobs'))
    uid = request.form.get('uid', '').strip()[:50]; piso = request.form.get('piso', '').strip()[:50]; depto = request.form.get('departamento', '').strip()[:50]; nombre = request.form.get('nombre_propietario', '').strip()[:100]; is_active = 'is_active' in request.form; schedule_enabled = 'activation_schedule_enabled' in request.form; days_list = request.form.getlist('activation_days'); start_str = request.form.get('activation_start_time'); end_str = request.form.get('activation_end_time')
    if not uid: flash("UID no puede estar vacío.", "warning"); return redirect(url_for('manage_keyfobs'))
    if uid.lower() != kf.uid.lower() and Keyfob.query.filter(Keyfob.uid.ilike(uid), Keyfob.id != keyfob_id).count() > 0: flash(f"UID '{uid}' ya asignado.", "danger"); return redirect(url_for('manage_keyfobs'))
    days, start, end = None, None, None; horario_ok = True
    if schedule_enabled:
        days = ",".join(days_list) if days_list else None
        try:
            if start_str: start = datetime.strptime(start_str, '%H:%M').time()
            if end_str: end = datetime.strptime(end_str, '%H:%M').time()
        except ValueError: flash("Formato hora inválido.", "warning"); horario_ok = False
    if not horario_ok: return redirect(url_for('manage_keyfobs'))
    try:
        kf.uid = uid; kf.piso = piso or None; kf.departamento = depto or None; kf.nombre_propietario = nombre or None; kf.is_active = is_active; kf.last_edited_by = current_user.username; kf.activation_schedule_enabled = schedule_enabled; kf.activation_days = days if schedule_enabled else None; kf.activation_start_time = start if schedule_enabled else None; kf.activation_end_time = end if schedule_enabled else None
        if hasattr(kf, 'updated_at'): kf.updated_at = datetime.now(timezone.utc)
        db.session.commit(); log_system_event('INFO', 'Llavero Editado', f"ID: {kf.id}, UID: {uid}, Act: {is_active}"); flash(f"Llavero '{uid}' actualizado.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error editando llavero {keyfob_id}: {e}", exc_info=True); flash(f"Error actualizando '{uid}'.", "danger")
    return redirect(url_for('manage_keyfobs'))

@app.route('/keyfobs/toggle/<int:keyfob_id>', methods=['POST'])
@login_required
def toggle_keyfob(keyfob_id):
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_keyfobs'))
    kf = db.session.get(Keyfob, keyfob_id);
    if not kf: abort(404)
    try:
        kf.is_active = not kf.is_active; kf.last_edited_by = current_user.username
        if hasattr(kf, 'updated_at'): kf.updated_at = datetime.now(timezone.utc)
        db.session.commit(); status = "activado" if kf.is_active else "desactivado"; log_system_event('INFO', f'Llavero {status.capitalize()}', f"ID: {kf.id}, UID: {kf.uid}"); flash(f"Llavero '{kf.uid}' {status}.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error toggle llavero {keyfob_id}: {e}", exc_info=True); flash(f"Error cambiando estado '{kf.uid}'.", "danger")
    return redirect(url_for('manage_keyfobs'))

@app.route('/keyfobs/delete/<int:keyfob_id>', methods=['POST'])
@login_required
def delete_keyfob(keyfob_id):
    code = request.form.get('delete_confirmation_code'); DELETE_CODE = "6729671"
    if code != DELETE_CODE: flash("Código confirmación incorrecto.", "danger"); log_system_event('WARNING', 'Elim Llavero Fallido', f"ID: {keyfob_id}, Código incorrecto"); return redirect(url_for('manage_keyfobs'))
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_keyfobs'))
    kf = db.session.get(Keyfob, keyfob_id);
    if not kf: abort(404)
    if db.session.query(AccessLog.id).filter(AccessLog.keyfob_id == keyfob_id).limit(1).count() > 0: flash(f"No se puede eliminar '{kf.uid}' (tiene logs). Desactívalo.", "warning"); log_system_event('WARNING', 'Elim Llavero Bloqueado', f"ID: {kf.id}, UID: {kf.uid}, Tiene logs"); return redirect(url_for('manage_keyfobs'))
    try:
        uid_del = kf.uid; db.session.delete(kf); db.session.commit(); log_system_event('WARNING', 'Llavero Eliminado', f"ID: {keyfob_id}, UID: {uid_del}"); flash(f"Llavero '{uid_del}' eliminado.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error eliminando llavero {keyfob_id}: {e}", exc_info=True); flash(f"Error eliminando '{uid_del}'.", "danger")
    return redirect(url_for('manage_keyfobs'))

# --- Users ---
@app.route('/users')
@admin_required
def manage_users():
    app.logger.debug(f"Accediendo /users ({current_user.username})")
    page = request.args.get('page', 1, type=int); per_page = 15; search = request.args.get('search', '').strip()
    pagination = None
    if check_models_loaded():
        try:
            query = User.query
            if search: query = query.filter(or_(User.username.ilike(f"%{search}%"), User.full_name.ilike(f"%{search}%"), User.email.ilike(f"%{search}%")))
            pagination = query.order_by(User.username).paginate(page=page, per_page=per_page, error_out=False)
            if pagination and pagination.items: # Calcular banderas
                total_active_admins = User.query.filter(User.role == 'admin', User.is_active == True).count()
                total_admins = User.query.filter(User.role == 'admin').count()
                for user in pagination.items:
                    user.cannot_be_deleted = (user.id == current_user.id) or (user.role == 'admin' and total_admins <= 1)
                    user.cannot_be_deactivated = (user.id == current_user.id) or (user.role == 'admin' and user.is_active and total_active_admins <= 1)
                    user.is_last_active_admin = (user.role == 'admin' and user.is_active and total_active_admins == 1)
        except Exception as e: app.logger.error(f"Error usuarios: {e}", exc_info=True); flash("Error cargando usuarios.", "danger"); pagination = None
    else: flash("No se pueden gestionar usuarios (Error BD).", "danger")
    return render_template('manage_users.html', pagination=pagination, search=search)

@app.route('/users/add', methods=['POST'])
@admin_required
def add_user():
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_users'))
    username = request.form.get('username', '').strip()[:80]; full_name = request.form.get('full_name', '').strip()[:120]; email = request.form.get('email', '').strip().lower()[:120]; password = request.form.get('password'); role = request.form.get('role', 'user'); is_active = 'is_active' in request.form
    if not username or not password: flash("Usuario y contraseña obligatorios.", "warning"); return redirect(url_for('manage_users'))
    if len(password) < 6: flash("Contraseña >= 6 caracteres.", "warning"); return redirect(url_for('manage_users'))
    if role not in ['admin', 'user']: flash("Rol inválido.", "warning"); return redirect(url_for('manage_users'))
    if email and '@' not in email: flash("Formato email inválido.", "warning"); return redirect(url_for('manage_users'))
    existing = User.query.filter(or_(User.username.ilike(username), User.email == email if email else False)).first()
    if existing: flash(f"{'Username' if existing.username.lower() == username.lower() else 'Email'} ya existe.", "danger"); return redirect(url_for('manage_users'))
    try:
        user = User(username=username, full_name=full_name or None, email=email or None, role=role, is_active=is_active)
        if hasattr(user, 'set_password'): user.set_password(password)
        else: user.password_hash = generate_password_hash(password, method='pbkdf2:sha256')
        db.session.add(user); db.session.commit(); log_system_event('INFO', 'Usuario Creado', f"User: {username}, Role: {role}, Act: {is_active}"); flash(f"Usuario '{username}' creado.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error creando user {username}: {e}", exc_info=True); flash(f"Error creando '{username}'.", "danger")
    return redirect(url_for('manage_users'))

@app.route('/edit_user/<int:user_id>', methods=['GET', 'POST'])
@login_required
@admin_required # O tu decorador
def edit_user(user_id):
    user_to_edit = User.query.get_or_404(user_id)
    # --- CÁLCULO DE is_last_admin (como antes) ---
    is_last_admin_flag = False
    if user_to_edit.role == 'admin' and user_to_edit.is_active:
        other_active_admin_count = User.query.filter(
            User.is_active == True,
            User.role == 'admin',
            User.id != user_to_edit.id
        ).count()
        if other_active_admin_count == 0:
            is_last_admin_flag = True
    # --- FIN CÁLCULO ---

    # --- CREAR INSTANCIA DEL FORMULARIO ---
    form = EditUserForm(obj=user_to_edit) # obj= pre-rellena el form con datos del user en GET

    # --- LÓGICA POST (Usando Flask-WTF) ---
    if form.validate_on_submit(): # Esto valida en POST y verifica CSRF
        # Validar si se intenta modificar al último admin
        if is_last_admin_flag:
            if form.role.data != 'admin' or not form.is_active.data:
                 flash('No se puede cambiar el rol ni desactivar al último administrador.', 'danger')
                 # ¡Importante! Volver a renderizar con el formulario *actual* para mostrar errores si los hubiera
                 return render_template('edit_user.html',
                                       user=user_to_edit,
                                       is_last_admin=is_last_admin_flag,
                                       form=form) # Pasar el form

        # Validar si el usuario intenta modificarse a sí mismo (rol/activo)
        if user_to_edit.id == current_user.id:
             if form.role.data != 'admin':
                 flash('No puedes quitarte a ti mismo el rol de administrador.', 'danger')
                 return render_template('edit_user.html', user=user_to_edit, is_last_admin=is_last_admin_flag, form=form)
             if not form.is_active.data:
                 flash('No puedes desactivarte a ti mismo.', 'danger')
                 return render_template('edit_user.html', user=user_to_edit, is_last_admin=is_last_admin_flag, form=form)


        # Actualizar los datos del usuario desde el formulario
        user_to_edit.username = form.username.data
        user_to_edit.full_name = form.full_name.data
        user_to_edit.email = form.email.data
        # Solo actualizar rol y estado si no son las restricciones anteriores
        if not (is_last_admin_flag and user_to_edit.is_active):
             user_to_edit.role = form.role.data
        if not (is_last_admin_flag and user_to_edit.is_active) and user_to_edit.id != current_user.id:
             user_to_edit.is_active = form.is_active.data

        try:
            db.session.commit()
            log_system_event('Usuario Editado', 'INFO', f"Usuario '{user_to_edit.username}' (ID: {user_to_edit.id}) editado por '{current_user.username}'.")
            flash(f'Usuario "{user_to_edit.username}" actualizado correctamente.', 'success')
            return redirect(url_for('manage_users')) # O a donde quieras ir después
        except Exception as e:
            db.session.rollback()
            log_system_event('Error Edición Usuario', 'ERROR', f"Error al editar usuario '{user_to_edit.username}': {e}", exc_info=True)
            flash(f'Error al actualizar el usuario: {e}', 'danger')

    # --- RENDERIZAR EN GET (o si la validación POST falló) ---
    # Asegurarse de pasar 'form' a la plantilla
    return render_template(
        'edit_user.html',
        user=user_to_edit,
        is_last_admin=is_last_admin_flag,
        form=form  # <--- PASAR EL FORMULARIO AQUÍ
    )

@app.route('/users/change_password/<int:user_id>', methods=['POST'])
@admin_required
def change_user_password(user_id):
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_users'))
    user = db.session.get(User, user_id);
    if not user: flash("Usuario no encontrado.", "danger"); return redirect(url_for('manage_users'))
    new_pass = request.form.get('new_password'); confirm = request.form.get('confirm_password')
    if not new_pass or not confirm: flash("Ingresa y confirma contraseña.", "warning"); return redirect(url_for('manage_users'))
    if len(new_pass) < 6: flash("Contraseña >= 6 caracteres.", "warning"); return redirect(url_for('manage_users'))
    if new_pass != confirm: flash("Contraseñas no coinciden.", "warning"); return redirect(url_for('manage_users'))
    try:
        if hasattr(user, 'set_password'): user.set_password(new_pass)
        else: user.password_hash = generate_password_hash(new_pass, method='pbkdf2:sha256')
        if hasattr(user, 'updated_at'): user.updated_at = datetime.now(timezone.utc)
        db.session.commit(); log_system_event('INFO', 'Contraseña Cambiada', f"Pass cambiada para user ID: {user_id}, User: {user.username}"); flash(f"Contraseña actualizada para '{user.username}'.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error cambiando pass user {user_id}: {e}", exc_info=True); flash(f"Error cambiando pass '{user.username}'.", "danger")
    return redirect(url_for('manage_users'))

@app.route('/users/toggle/<int:user_id>', methods=['POST'])
@admin_required
def toggle_user(user_id):
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_users'))
    user = db.session.get(User, user_id);
    if not user: abort(404)
    if user.id == current_user.id: flash("No puedes cambiar tu propio estado.", "warning"); return redirect(url_for('manage_users'))
    new_status = not user.is_active
    if not new_status and user.role == 'admin': # Check last active admin
        if User.query.filter(User.role == 'admin', User.is_active == True).count() <= 1 and user.is_active: flash("No puedes desactivar último admin activo.", "warning"); return redirect(url_for('manage_users'))
    try:
        user.is_active = new_status
        if hasattr(user, 'updated_at'): user.updated_at = datetime.now(timezone.utc)
        db.session.commit(); status = "activado" if user.is_active else "desactivado"; log_system_event('INFO', f'Usuario {status.capitalize()}', f"ID: {user.id}, User: {user.username}"); flash(f"Usuario '{user.username}' {status}.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error toggle user {user.id}: {e}", exc_info=True); flash(f"Error cambiando estado '{user.username}'.", "danger")
    return redirect(url_for('manage_users'))

@app.route('/users/delete/<int:user_id>', methods=['POST'])
@admin_required
def delete_user(user_id):
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_users'))
    user = db.session.get(User, user_id);
    if not user: abort(404)
    if user.id == current_user.id: flash("No puedes eliminar tu cuenta.", "warning"); return redirect(url_for('manage_users'))
    if user.role == 'admin' and User.query.filter(User.role == 'admin').count() <= 1: flash("No puedes eliminar último admin.", "warning"); return redirect(url_for('manage_users'))
    try:
        username_del = user.username; keys = APIKey.query.filter_by(user_id=user_id).all()
        if keys: [db.session.delete(key) for key in keys]; app.logger.info(f"Eliminando {len(keys)} claves API de {username_del}")
        db.session.delete(user); db.session.commit(); log_system_event('WARNING', 'Usuario Eliminado', f"ID: {user_id}, User: {username_del}"); flash(f"Usuario '{username_del}' eliminado.", "success")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error eliminando user {user_id}: {e}", exc_info=True); flash(f"Error eliminando '{username_del}'.", "danger")
    return redirect(url_for('manage_users'))

# --- Logs ---
PaginationFallback = namedtuple('Pagination', ['items', 'page', 'per_page', 'total', 'pages', 'has_prev', 'has_next', 'prev_num', 'next_num', 'iter_pages'])
def create_fallback_pagination(page=1, per_page=DEFAULT_ACCESS_LOGS_PER_PAGE): return PaginationFallback([], page, per_page, 0, 0, False, False, None, None, lambda: iter([]))

@app.route('/access-logs')
@login_required
def view_access_logs():
    app.logger.debug(f"Accediendo /access-logs ({current_user.username})")
    page = request.args.get('page', 1, type=int); per_page = request.args.get('per_page', DEFAULT_ACCESS_LOGS_PER_PAGE, type=int); search = request.args.get('search', '').strip(); date_str = request.args.get('date', ''); result = request.args.get('result', '')
    pagination = create_fallback_pagination(page, per_page); total_logs = 0
    if check_models_loaded():
        try:
            query = AccessLog.query
            if search: query = query.filter(or_(AccessLog.keyfob_uid_attempted.ilike(f"%{search}%"), AccessLog.username_at_time.ilike(f"%{search}%"), AccessLog.keyfob_description_at_time.ilike(f"%{search}%"), AccessLog.reason.ilike(f"%{search}%")))
            if date_str:
                try: filter_date = datetime.strptime(date_str, '%Y-%m-%d').date(); start_dt = datetime.combine(filter_date, dt_time.min, tzinfo=timezone.utc); end_dt = datetime.combine(filter_date, dt_time.max, tzinfo=timezone.utc); query = query.filter(AccessLog.timestamp >= start_dt, AccessLog.timestamp <= end_dt)
                except ValueError: flash("Formato fecha inválido (YYYY-MM-DD).", "warning"); date_str = ''
            if result == 'granted': query = query.filter(AccessLog.access_granted == True)
            elif result == 'denied': query = query.filter(AccessLog.access_granted == False)
            pagination = query.order_by(AccessLog.timestamp.desc()).options(joinedload(AccessLog.keyfob)).paginate(page=page, per_page=per_page, error_out=False); total_logs = pagination.total
        except Exception as e: app.logger.error(f"Error logs acceso: {e}", exc_info=True); flash("Error cargando logs acceso.", "danger")
    else: flash("No se pueden ver logs (Error BD).", "danger")
    return render_template('access_logs.html', pagination=pagination, total_logs=total_logs, search=search, date=date_str, result=result)

@app.route('/access-logs/export')
@login_required
def export_access_logs():
    app.logger.info(f"{current_user.username} exportando logs acceso.")
    if not check_models_loaded(show_flash=True): return redirect(url_for('view_access_logs'))
    try:
        search = request.args.get('search', '').strip(); date_str = request.args.get('date', ''); result = request.args.get('result', '')
        query = AccessLog.query # Aplicar mismos filtros que en view_access_logs
        if search: query = query.filter(or_(AccessLog.keyfob_uid_attempted.ilike(f"%{search}%"), AccessLog.username_at_time.ilike(f"%{search}%"), AccessLog.keyfob_description_at_time.ilike(f"%{search}%"), AccessLog.reason.ilike(f"%{search}%")))
        if date_str:
            try:
                filter_date = datetime.strptime(date_str, '%Y-%m-%d').date()
                start_dt = datetime.combine(filter_date, dt_time.min, tzinfo=timezone.utc)
                end_dt = datetime.combine(filter_date, dt_time.max, tzinfo=timezone.utc)
                query = query.filter(AccessLog.timestamp >= start_dt, AccessLog.timestamp <= end_dt)
            except ValueError:
                # Si la fecha es inválida, simplemente la ignoramos (no filtramos por fecha)
                app.logger.warning(f"Exportación: Formato fecha inválido '{date_str}', ignorando filtro fecha.")
                pass # O podrías hacer flash y redirect si prefieres
        # <<< FIN: BLOQUE if date_str CORREGIDO >>>

        if result == 'granted': query = query.filter(AccessLog.access_granted == True)
        elif result == 'denied': query = query.filter(AccessLog.access_granted == False)

        logs = query.order_by(AccessLog.timestamp.desc()).all()
        if result == 'granted': query = query.filter(AccessLog.access_granted == True)
        elif result == 'denied': query = query.filter(AccessLog.access_granted == False)
        logs = query.order_by(AccessLog.timestamp.desc()).all()
        output = io.StringIO(); writer = csv.writer(output)
        writer.writerow(['ID', 'Timestamp(UTC)', 'UID Intentado', 'Concedido', 'Razón', 'Username', 'Desc Llavero', 'Puerta'])
        for log in logs: writer.writerow([log.id, log.timestamp.strftime('%Y-%m-%d %H:%M:%S') if log.timestamp else '', log.keyfob_uid_attempted or 'N/A', 'Sí' if log.access_granted else 'No', log.reason or '', log.username_at_time or 'N/A', log.keyfob_description_at_time or 'N/A', log.door_name or 'Principal'])
        output.seek(0); filename = f"access_logs_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.csv"
        response = make_response(output.getvalue().encode('utf-8-sig')); response.headers["Content-Disposition"] = f"attachment; filename=\"{filename}\""; response.headers["Content-type"] = "text/csv; charset=utf-8-sig"
        log_system_event('INFO', 'Logs Acceso Exportados', f"Filename: {filename}, Filters: {request.args.to_dict()}"); return response
    except Exception as e: app.logger.error(f"Error exportando logs acceso: {e}", exc_info=True); flash("Error generando exportación.", "danger"); return redirect(url_for('view_access_logs'))

@app.route('/system-events')
@admin_required
def view_system_events():
    app.logger.debug(f"Accediendo /system-events ({current_user.username})")
    page = request.args.get('page', 1, type=int); per_page = request.args.get('per_page', DEFAULT_SYSTEM_EVENTS_PER_PAGE, type=int); level = request.args.get('level', '').upper(); type_f = request.args.get('type', '').strip(); search = request.args.get('search', '').strip()
    pagination = create_fallback_pagination(page, per_page); total_events = 0; event_levels = ['INFO', 'WARNING', 'ERROR', 'CRITICAL']; event_types = [] # Podrías popular esto dinámicamente
    if check_models_loaded():
        try:
            query = SystemEvent.query
            if level and level in event_levels: query = query.filter(SystemEvent.level == level)
            if type_f: query = query.filter(SystemEvent.event_type.ilike(f"%{type_f}%"))
            if search: query = query.filter(or_(SystemEvent.message.ilike(f"%{search}%"), SystemEvent.username.ilike(f"%{search}%"), SystemEvent.ip_address.ilike(f"%{search}%")))
            pagination = query.order_by(SystemEvent.timestamp.desc()).paginate(page=page, per_page=per_page, error_out=False); total_events = pagination.total
        except Exception as e: app.logger.error(f"Error eventos sistema: {e}", exc_info=True); flash("Error cargando eventos sistema.", "danger")
    else: flash("No se pueden ver eventos (Error BD).", "danger")
    return render_template('system_events.html', pagination=pagination, total_events=total_events, levels=event_levels, current_level=level, types=event_types, current_type=type_f, search=search)

# --- Backups ---
@app.route('/backups')
@login_required
def manage_backups():
    app.logger.debug(f"Accediendo /backups ({current_user.username})")
    backups = []
    try:
        if not os.path.exists(BACKUP_DIR): os.makedirs(BACKUP_DIR)
        for filename in sorted(os.listdir(BACKUP_DIR), reverse=True):
            if filename.lower().endswith(('.db', '.sqlite', '.sqlite3', '.backup')):
                path = os.path.join(BACKUP_DIR, filename)
                try:
                    stat = os.stat(path); ts = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc); size = stat.st_size
                    size_h = f"{size} B" if size < 1024 else f"{size/1024:.1f} KB" if size < 1024**2 else f"{size/1024**2:.1f} MB" if size < 1024**3 else f"{size/1024**3:.1f} GB"
                    backups.append({"filename": filename, "timestamp": ts, "size_bytes": size, "size_human": size_h})
                except Exception as e_stat: app.logger.warning(f"Error info backup '{filename}': {e_stat}"); backups.append({"filename": filename, "timestamp": None, "size_bytes": None, "size_human": "Error"})
    except Exception as e_list: app.logger.error(f"Error listando backups: {e_list}", exc_info=True); flash("Error listando backups.", "danger")
    auto_config = load_auto_backup_config()
    return render_template('backup.html', system_backups=backups, auto_backup_config=auto_config)

@app.route('/backups/configure_auto', methods=['POST'])
@admin_required
def configure_auto_backup():
    try:
        config = {
            "enabled": 'auto_backup_enabled' in request.form,
            "frequency": request.form.get('auto_backup_frequency', 'daily'),
            "time": request.form.get('auto_backup_time', '03:00'),
            "email": request.form.get('auto_backup_email', '').strip()
        }
        if config['enabled']:
            # Validar email
            if not config['email'] or '@' not in config['email']:
                flash("Email inválido.", "warning")
                return redirect(url_for('manage_backups'))
            # Validar formato hora
            try:
                datetime.strptime(config['time'], '%H:%M')
            except ValueError:
                flash("Formato hora inválido (HH:MM).", "warning")
                return redirect(url_for('manage_backups'))

        # Si las validaciones pasan (o si está deshabilitado), guardar
        if save_auto_backup_config(config):
            flash("Config backup automático guardada.", "success")
        # save_auto_backup_config ya muestra flash de error si falla

    except Exception as e:
        app.logger.error(f"Error config auto backup: {e}", exc_info=True)
        flash("Error guardando config.", "danger")

    return redirect(url_for('manage_backups'))

@app.route('/backups/export/keyfobs_csv')
@login_required
def export_keyfobs_csv():
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_backups'))
    app.logger.info(f"{current_user.username} exportando TODOS los llaveros CSV.")
    try:
        keyfobs = Keyfob.query.order_by(Keyfob.uid).all()
        def generate(): # Use generator for large datasets
            data = io.StringIO(); writer = csv.writer(data)
            writer.writerow(['UID', 'Nombre', 'Piso', 'Depto', 'Activo', 'Creado(UTC)', 'HorarioActivo', 'DiasActivo', 'HoraInicio', 'HoraFin'])
            yield data.getvalue(); data.seek(0); data.truncate(0) # Yield header
            for kf in keyfobs:
                writer.writerow([kf.uid, kf.nombre_propietario or '', kf.piso or '', kf.departamento or '', str(kf.is_active), kf.created_at.strftime('%Y-%m-%d %H:%M:%S') if kf.created_at else '', str(kf.activation_schedule_enabled), kf.activation_days or '', kf.activation_start_time.strftime('%H:%M') if kf.activation_start_time else '', kf.activation_end_time.strftime('%H:%M') if kf.activation_end_time else ''])
                yield data.getvalue(); data.seek(0); data.truncate(0) # Yield row
        filename = f"backup_llaveros_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.csv"
        response = Response(stream_with_context(generate()), mimetype='text/csv; charset=utf-8-sig'); response.headers.set("Content-Disposition", "attachment", filename=filename)
        log_system_event('INFO', 'Exportación Llaveros CSV', f"Exportados {len(keyfobs)} a {filename}"); return response
    except Exception as e: app.logger.error(f"Error CSV llaveros: {e}", exc_info=True); flash("Error generando CSV llaveros.", "danger"); return redirect(url_for('manage_backups'))

@app.route('/backups/import/keyfobs_csv', methods=['POST'])
@login_required
def import_keyfobs_csv():
    if 'keyfob_file' not in request.files or not request.files['keyfob_file'].filename: flash('No se seleccionó archivo.', 'warning'); return redirect(url_for('manage_backups'))
    file = request.files['keyfob_file']
    if not file.filename.lower().endswith('.csv'): flash('Formato inválido. Sube .csv', 'warning'); return redirect(url_for('manage_backups'))
    if not check_models_loaded(show_flash=True): return redirect(url_for('manage_backups'))
    app.logger.info(f"{current_user.username} importando llaveros CSV: {file.filename}")
    added, updated, skipped, errors = 0, 0, 0, []
    try:
        stream = io.StringIO(file.stream.read().decode("utf-8", errors='ignore'), newline=None)
        header = stream.readline(); delimiter = ';' if header.count(';') > header.count(',') else ','
        raw_headers = [h.strip().lower().replace(' ', '_') for h in header.strip().split(delimiter)]
        # Mapa flexible de cabeceras esperadas
        header_map = {'uid': 'uid', 'nombre_propietario': 'nombre', 'nombre': 'nombre', 'piso': 'piso', 'departamento': 'depto', 'depto': 'depto', 'activo': 'activo', 'horario_activo': 'schedule_enabled', 'dias_activo': 'days', 'hora_inicio': 'start', 'hora_fin': 'end'}
        fieldnames = [header_map.get(h) for h in raw_headers if header_map.get(h) is not None]
        if 'uid' not in fieldnames or 'activo' not in fieldnames: flash("CSV debe contener al menos 'uid' y 'activo'", 'danger'); return redirect(url_for('manage_backups'))
        csv_reader = csv.DictReader(stream, fieldnames=fieldnames, delimiter=delimiter, restkey='_extra', restval='') # Ignorar columnas extra
        for row_num, row in enumerate(csv_reader, start=2):
            uid = row.get('uid', '').strip()[:50]
            if not uid: errors.append(f"Fila {row_num}: Falta UID."); skipped += 1; continue
            is_active = row.get('activo', 'True').strip().lower() in ['true', '1', 'yes', 'activo', 'sí']
            schedule_enabled = row.get('schedule_enabled', 'False').strip().lower() in ['true', '1', 'yes', 'activo', 'sí']
            days = row.get('days', '').strip() or None; start_str = row.get('start', '').strip(); end_str = row.get('end', '').strip(); start, end = None, None
            try:
                if schedule_enabled and start_str: start = datetime.strptime(start_str, '%H:%M').time()
                if schedule_enabled and end_str: end = datetime.strptime(end_str, '%H:%M').time()
            except ValueError: errors.append(f"Fila {row_num} ({uid}): Formato hora inválido. Horario ignorado."); schedule_enabled, days, start, end = False, None, None, None
            try:
                kf = Keyfob.query.filter(Keyfob.uid.ilike(uid)).first()
                if kf: # Actualizar
                    kf.nombre_propietario = row.get('nombre', '').strip()[:100] or None; kf.piso = row.get('piso', '').strip()[:50] or None; kf.departamento = row.get('depto', '').strip()[:50] or None; kf.is_active = is_active; kf.activation_schedule_enabled = schedule_enabled; kf.activation_days = days if schedule_enabled else None; kf.activation_start_time = start if schedule_enabled else None; kf.activation_end_time = end if schedule_enabled else None; kf.last_edited_by = current_user.username; updated += 1
                else: # Añadir nuevo
                    kf = Keyfob(uid=uid, nombre_propietario=row.get('nombre', '').strip()[:100] or None, piso=row.get('piso', '').strip()[:50] or None, departamento=row.get('depto', '').strip()[:50] or None, is_active=is_active, activation_schedule_enabled=schedule_enabled, activation_days=days if schedule_enabled else None, activation_start_time=start if schedule_enabled else None, activation_end_time=end if schedule_enabled else None, last_edited_by=current_user.username); db.session.add(kf); added += 1
            except Exception as inner_e: errors.append(f"Fila {row_num} ({uid}): Error BD - {inner_e}"); skipped += 1; db.session.rollback(); continue
        db.session.commit(); flash(f"Importación CSV: Añadidos: {added}, Actualizados: {updated}, Omitidos/Errores: {skipped}.", 'success')
        if errors: flash("Problemas:", 'warning'); [flash(e, 'warning') for e in errors[:10]]; [flash(f"... y {len(errors)-10} más.", 'warning') if len(errors) > 10 else None]
        log_system_event('INFO', 'Importación Llaveros CSV', f"Add: {added}, Upd: {updated}, Skip: {skipped}, File: {file.filename}")
    except Exception as e: db.session.rollback(); app.logger.error(f"Error procesando CSV llaveros: {e}", exc_info=True); flash(f"Error fatal procesando CSV: {e}", 'danger')
    finally:
         if 'stream' in locals() and not stream.closed: stream.close()
    return redirect(url_for('manage_backups'))

@app.route('/backups/create', methods=['POST'])
@admin_required
def create_backup():
    app.logger.info(f"{current_user.username} creando backup.")
    ts = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
    filename = f"backup_{ts}.db"
    path = os.path.join(BACKUP_DIR, filename)
    status, msg, size = "Failure", "Backup fallido.", None

    if not os.path.exists(DATABASE_PATH):
        msg = f"Error Crítico: BD no encontrada '{DATABASE_PATH}'"
        app.logger.critical(msg)
    else:
        try:
            cmd = ['sqlite3', DATABASE_PATH, f'.backup "{path}"']
            app.logger.debug(f"Ejecutando: {' '.join(cmd)}")
            proc = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=60)
            if proc.returncode == 0:
                if os.path.exists(path):
                    size = os.path.getsize(path)
                    if size > 100:
                        status = "Success"
                        msg = f"Backup creado: {filename} ({size} bytes)."
                        app.logger.info(msg)
                    else:
                        msg = f"Comando ok, backup '{filename}' vacío/pequeño ({size} bytes)."
                        app.logger.error(msg)
                else:
                    msg = f"Comando ok, archivo '{filename}' no encontrado."
                    app.logger.error(msg)
            else:
                msg = f"Error sqlite3 (código {proc.returncode}): {proc.stderr or proc.stdout or 'Sin salida'}"
                app.logger.error(msg)
        except FileNotFoundError:
            msg = "Error Crítico: 'sqlite3' no encontrado."
            app.logger.critical(msg)
            status = "Failure" # Asegurar que status sea Failure
        except subprocess.TimeoutExpired:
            msg = "Error: Timeout backup (60s)."
            app.logger.error(msg)
            status = "Failure" # Asegurar que status sea Failure
        except Exception as e:
            msg = f"Error inesperado backup: {e}"
            app.logger.error(msg, exc_info=True)
            status = "Failure" # Asegurar que status sea Failure

    # Eliminar archivo de backup fallido (BLOQUE CORREGIDO)
    if status != "Success" and os.path.exists(path):
        try:
            os.remove(path)
            app.logger.info(f"Backup fallido {path} eliminado.")
        except OSError as e_rm:
            app.logger.error(f"No se pudo eliminar backup fallido {path}: {e_rm}")

    # Registrar log del backup
    if check_models_loaded():
        try:
            log = BackupLog(
                timestamp=datetime.now(timezone.utc),
                status=status,
                message=msg[:999],
                file_path=path if status=='Success' else None,
                file_size=size if status=='Success' else None,
                triggered_by=current_user.username
            )
            db.session.add(log)
            db.session.commit()
        except Exception as e_log:
            db.session.rollback()
            app.logger.error(f"Error CRÍTICO guardando log backup BD: {e_log}", exc_info=True)

    # Loguear evento del sistema y mostrar mensaje flash
    log_system_event(level='INFO' if status=='Success' else 'ERROR', event_type='Backup Attempt', message=msg, commit=False) # Commit ya hecho en log BD
    flash(msg, "success" if status == "Success" else "danger")
    return redirect(url_for('manage_backups'))

@app.route('/backups/download/<path:filename>')
@login_required
def download_backup(filename):
    safe = secure_filename(filename); allowed = ('.db', '.sqlite', '.sqlite3', '.backup')
    if not safe or safe != filename or not safe.lower().endswith(allowed): abort(404, "Nombre archivo inválido.")
    app.logger.info(f"{current_user.username} descargando backup: {safe}")
    try: response = send_from_directory(directory=BACKUP_DIR, path=safe, as_attachment=True); log_system_event('INFO', 'Backup BD Descargado', f"Filename: {safe}"); return response
    except FileNotFoundError: abort(404, "Archivo backup no encontrado.")
    except Exception as e: app.logger.error(f"Error descargando backup {safe}: {e}", exc_info=True); flash("Error procesando descarga.", "danger"); return redirect(url_for('manage_backups'))

@app.route('/backups/delete/<path:filename>', methods=['POST'])
@admin_required
def delete_backup(filename):
    safe = secure_filename(filename); allowed = ('.db', '.sqlite', '.sqlite3', '.backup')
    if not safe or safe != filename or not safe.lower().endswith(allowed): flash("Nombre archivo inválido.", "danger"); return redirect(url_for('manage_backups'))
    path = os.path.join(BACKUP_DIR, safe); app.logger.warning(f"{current_user.username} eliminando backup: {safe}")
    try:
        if os.path.isfile(path): os.remove(path); log_system_event('WARNING', 'Backup BD Eliminado', f"Filename: {safe}"); flash(f"Backup '{safe}' eliminado.", "success")
        else: flash("Archivo no existe.", "warning")
    except Exception as e: app.logger.error(f"Error eliminando backup {safe}: {e}", exc_info=True); flash(f"Error eliminando '{safe}'.", "danger")
    return redirect(url_for('manage_backups'))

# --- Door Control & Hardware API ---
@app.route('/door-control')
@login_required
def door_control():
    app.logger.debug(f"Accediendo /door-control ({current_user.username})")
    current_status = get_hardware_status() # Usa la función unificada
    show_controls = current_status.get('gpio_setup_ok', False) and current_status.get('pigpiod_connected', False)
    if not show_controls:
        if not current_status.get('gpio_setup_ok'): msg = "Control manual no disponible (setup GPIO falló)."
        elif not current_status.get('pigpiod_connected'): msg = "Control manual no disponible (pigpiod no conectado)."
        else: msg = "Control manual no disponible (hardware no detectado)."
        flash(msg, "warning")
    opening_time = current_status.get('opening_time', DEFAULT_OPENING_TIME_SECONDS)
    return render_template('door_control.html', current_status=current_status, opening_time=opening_time, show_controls=show_controls)

@app.route('/api/door/status')
@login_required
def api_door_status(): return jsonify(get_hardware_status())

@app.route('/api/door/open', methods=['POST'])
@login_required
def api_door_open():
    if not HARDWARE_AVAILABLE: return jsonify({"success": False, "message": "Hardware no disponible."}), 503
    app.logger.info(f"API: Apertura manual por {current_user.username}.")
    try: success, message = open_door_momentarily(); log_system_event('INFO' if success else 'ERROR', 'Puerta Abierta (API)', message); return jsonify({"success": success, "message": message or ("Éxito" if success else "Fallo")}), 200 if success else 500
    except Exception as e: app.logger.error(f"Excepción API /api/door/open: {e}", exc_info=True); log_system_event('CRITICAL', 'Excepción API Apertura', str(e)); return jsonify({"success": False, "message": "Error interno."}), 500

@app.route('/api/door/lock', methods=['POST'])
@login_required
def api_door_lock():
    if not HARDWARE_AVAILABLE: return jsonify({"success": False, "message": "Hardware no disponible."}), 503
    app.logger.info(f"API: Bloqueo manual por {current_user.username}.")
    try: success, message = lock_door(); log_system_event('WARNING' if success else 'ERROR', 'Puerta Bloqueada (API)', message); return jsonify({"success": success, "message": message or ("Éxito" if success else "Fallo")}), 200 if success else 500
    except Exception as e: app.logger.error(f"Excepción API /api/door/lock: {e}", exc_info=True); log_system_event('CRITICAL', 'Excepción API Bloqueo', str(e)); return jsonify({"success": False, "message": "Error interno."}), 500

@app.route('/api/door/unlock', methods=['POST'])
@login_required
def api_door_unlock():
    if not HARDWARE_AVAILABLE: return jsonify({"success": False, "message": "Hardware no disponible."}), 503
    app.logger.warning(f"API: DESBLOQUEO PERMANENTE por {current_user.username}.")
    try: success, message = unlock_door_permanently(); log_system_event('WARNING' if success else 'ERROR', 'Puerta Desbloqueada Perm (API)', message); return jsonify({"success": success, "message": message or ("Éxito" if success else "Fallo")}), 200 if success else 500
    except Exception as e: app.logger.error(f"Excepción API /api/door/unlock: {e}", exc_info=True); log_system_event('CRITICAL', 'Excepción API Desbloqueo Perm', str(e)); return jsonify({"success": False, "message": "Error interno."}), 500

@app.route('/api/door/set_opening_time', methods=['POST'])
@login_required
def api_set_opening_time():
    data = request.get_json() if request.is_json else request.form; time_str = data.get('opening_time')
    try:
        if time_str is None: raise ValueError("'opening_time' requerido.")
        new_time = int(time_str);
        if not (1 <= new_time <= 60): raise ValueError("Tiempo fuera de rango (1-60s).")
    except (ValueError, TypeError) as e: return jsonify({"success": False, "message": str(e)}), 400
    app.logger.info(f"API: Cambiando tiempo apertura a {new_time}s por {current_user.username}.")
    try:
        success, message = set_opening_time(new_time)
        if success: log_system_event('INFO', 'Tiempo Apertura Cambiado (API)', f"Nuevo: {new_time}s."); return jsonify({"success": True, "message": message}), 200
        else: log_system_event('ERROR', 'Tiempo Apertura Cambiado (API)', f"Fallo guardando {new_time}s. Razón: {message}"); return jsonify({"success": False, "message": message}), 500
    except Exception as e: app.logger.error(f"Excepción API /api/door/set_opening_time: {e}", exc_info=True); log_system_event('CRITICAL', 'Excepción API Set Time', str(e)); return jsonify({"success": False, "message": "Error interno."}), 500

# --- Configuration Page & APIs ---
@app.route('/configuration', methods=['GET'])
@admin_required
def configuration_page():
    app.logger.debug(f"Accediendo /configuration ({current_user.username})")
    settings = load_system_settings()
    api_keys = [] # Inicializar como lista vacía

    # Cargar claves API
    if check_models_loaded():
        try:
            api_keys = APIKey.query.options(joinedload(APIKey.user)).order_by(APIKey.created_at.desc()).all()
        except Exception as e:
            app.logger.error(f"Error cargando claves API: {e}", exc_info=True)
            flash("Error al cargar claves API.", "danger")
            # api_keys permanecerá como lista vacía si hay error

    # >>> LÍNEA RESTAURADA <<<
    ssid = get_current_wifi_ssid()
    
    # Obtener estado de red para modo offline
    network_status = get_system_network_status()

    opening_time = settings.get('opening_time', DEFAULT_OPENING_TIME_SECONDS)

    # Recuperar y limpiar la clave API recién creada de la sesión, si existe
    new_api_key_value = session.pop('new_api_key_value', None)
    new_api_key_name = session.pop('new_api_key_name', None)

    return render_template(
        'configuracion.html',
        current_ssid=ssid, # Ahora 'ssid' debería estar definida
        api_keys=api_keys,
        system_settings=settings,
        current_opening_time=opening_time,
        new_api_key_value=new_api_key_value,
        new_api_key_name=new_api_key_name,
        network_status=network_status
    )

@app.route('/api/wifi/scan', methods=['GET'])
@admin_required
def api_wifi_scan():
    app.logger.info(f"API: Escaneo WiFi por {current_user.username}.")
    networks = []
    seen = set()
    try:
        # Intentar refrescar la lista de redes WiFi
        subprocess.run(['sudo', 'nmcli', 'dev', 'wifi', 'rescan'], check=False, timeout=10) # Best effort rescan

        # Obtener la lista de redes
        res = subprocess.run(
            ['nmcli', '-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi', 'list'],
            capture_output=True, text=True, check=True, timeout=15
        )

        # Procesar cada línea de la salida
        for line in res.stdout.strip().split('\n'):
            parts = line.split(':')
            if len(parts) == 3:
                ssid, sig_str, sec = parts
                if ssid and ssid not in seen:
                    # Convertir señal a entero (BLOQUE CORREGIDO)
                    try:
                        sig = int(sig_str)
                    except ValueError:
                        sig = 0 # Usar 0 si la conversión falla

                    # Determinar tipo de seguridad simplificado
                    sec_s = 'Open' if not sec or sec == '--' else \
                            'WEP' if 'WEP' in sec else \
                            'WPA/WPA2' if 'WPA' in sec else \
                            sec # Usar el valor original si no coincide

                    networks.append({"ssid": ssid, "signal": sig, "security": sec_s})
                    seen.add(ssid)

        # Ordenar por señal descendente
        networks.sort(key=lambda x: x['signal'], reverse=True)
        return jsonify({"success": True, "networks": networks})

    except FileNotFoundError:
        app.logger.error("'nmcli' no encontrado.")
        return jsonify({"success": False, "message": "Error: nmcli no encontrado."}), 500
    except Exception as e:
        app.logger.error(f"Error escaneo WiFi: {e}", exc_info=True)
        return jsonify({"success": False, "message": f"Error escaneando: {e}"}), 500

@app.route('/api/wifi/connect', methods=['POST'])
@admin_required
def api_wifi_connect():
    ssid = request.form.get('ssid'); password = request.form.get('password', '')
    app.logger.warning(f"API: Intento conexión WiFi a '{ssid}' por {current_user.username}.")
    if not ssid: return jsonify({"success": False, "message": "SSID no proporcionado."}), 400
    try:
        cmd = ['sudo', 'nmcli', 'device', 'wifi', 'connect', ssid]; [cmd.extend(['password', password]) if password else None]
        app.logger.debug(f"Ejecutando: {' '.join(cmd[:5])} ...")
        res = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=60)
        if res.returncode == 0: msg = f"Comando conexión a '{ssid}' ejecutado."; app.logger.info(f"API WiFi Connect: {msg}"); log_system_event('INFO', 'WiFi Connect', f"Intento conexión a '{ssid}' iniciado."); return jsonify(success=True, message=msg)
        else:
            err_msg = res.stderr or res.stdout or "Error nmcli."; app.logger.error(f"API WiFi Connect: Error '{ssid}'. Salida: {err_msg}")
            err_disp = "Contraseña incorrecta/requerida." if "Secrets were required" in err_msg or "incorrect password" in err_msg.lower() else f"No se encontró red '{ssid}'." if "No network with SSID" in err_msg else "Falló activación conexión." if "Connection activation failed" in err_msg else "Error nmcli."
            log_system_event('ERROR', 'WiFi Connect', f"Fallo conexión a '{ssid}'. Razón: {err_disp}"); return jsonify(success=False, message=f"Error: {err_disp}"), 500
    except FileNotFoundError: app.logger.critical("sudo/nmcli no encontrado."); log_system_event('CRITICAL', 'WiFi Connect', "sudo/nmcli no encontrado."); return jsonify(success=False, message="Error crítico: Falta comando."), 500
    except Exception as e: app.logger.error(f"Excepción api_wifi_connect: {e}", exc_info=True); log_system_event('CRITICAL', 'WiFi Connect', f"Excepción: {e}"); return jsonify(success=False, message="Error interno."), 500

@app.route('/api/offline/activate', methods=['POST'])
@admin_required
def api_offline_activate():
    """API para activar manualmente el modo offline."""
    app.logger.warning(f"API: Activación manual modo offline por {current_user.username}.")
    
    try:
        if configure_offline_ethernet_ip():
            log_system_event('INFO', 'Offline Mode', f"Modo offline activado manualmente por {current_user.username}")
            return jsonify(success=True, message="Modo offline activado correctamente.", urls=get_offline_access_urls())
        else:
            return jsonify(success=False, message="No se pudo activar modo offline. Hay conexión a internet.")
    except Exception as e:
        app.logger.error(f"Excepción api_offline_activate: {e}", exc_info=True)
        log_system_event('ERROR', 'Offline Mode', f"Error activando modo offline: {e}")
        return jsonify(success=False, message="Error interno activando modo offline."), 500

@app.route('/api/network/status', methods=['GET'])
@admin_required  
def api_network_status():
    """API para obtener el estado actual de la red."""
    try:
        status = get_system_network_status()
        return jsonify(success=True, status=status)
    except Exception as e:
        app.logger.error(f"Error obteniendo estado de red: {e}", exc_info=True)
        return jsonify(success=False, message="Error obteniendo estado de red."), 500

@app.route('/api/api_keys', methods=['GET'])
@admin_required
def api_get_api_keys():
    if not check_models_loaded(): return jsonify({"error": "Error BD (modelos)."}), 500
    try:
        keys = APIKey.query.options(joinedload(APIKey.user)).order_by(APIKey.created_at.desc()).all()
        data = [{"id": k.id, "name": k.name, "prefix": k.key_prefix, "user": k.user.username if k.user else 'N/A', "created_at": k.created_at.strftime('%Y-%m-%d %H:%M') if k.created_at else 'N/A', "last_used_at": k.last_used_at.strftime('%Y-%m-%d %H:%M') if k.last_used_at else 'Nunca', "is_active": k.is_active} for k in keys]
        return jsonify(data)
    except Exception as e: app.logger.error(f"Error API get_api_keys: {e}", exc_info=True); return jsonify({"error": "Fallo al obtener claves API"}), 500

@app.route('/api/api_keys', methods=['POST'], endpoint='api_create_api_key')
@admin_required
def api_create_api_key():
    if not check_models_loaded(): return jsonify({"success": False, "message": "Error BD (modelos)."}), 500
    name = request.form.get('name', '').strip()[:100] # Limitar longitud
    if not name: return jsonify({"success": False, "message": "Nombre clave requerido."}), 400
    try:
        key_val = generate_api_key(); prefix = key_val[:8]
        while APIKey.query.filter_by(key_prefix=prefix).count() > 0: key_val = generate_api_key(); prefix = key_val[:8] # Asegurar prefijo único
        hash_val = hash_api_key(key_val)
        new_key = APIKey(name=name, key_prefix=prefix, key_hash=hash_val, user_id=current_user.id, is_active=True)
        db.session.add(new_key); db.session.commit(); log_system_event('INFO', 'API Key Creada', f"Clave '{name}' (Prefix: {prefix}) por {current_user.username}")
        session['new_api_key_value'] = key_val; session['new_api_key_name'] = name # Guardar para mostrar una vez
        flash(f"¡Clave API '{name}' creada! Cópiala ahora, no se mostrará de nuevo.", "success"); return redirect(url_for('configuration_page'))
    except Exception as e: db.session.rollback(); app.logger.error(f"Error API create_api_key: {e}", exc_info=True); return jsonify({"success": False, "message": "Error interno generando clave."}), 500

@app.route('/api/api_keys/<int:key_id>', methods=['DELETE'])
@admin_required
def api_revoke_api_key(key_id):
    if not check_models_loaded(): return jsonify({"error": "Error BD (modelos)."}), 500
    try:
        key = db.session.get(APIKey, key_id);
        if not key: return jsonify({"success": False, "message": "Clave API no encontrada."}), 404
        name, prefix = key.name, key.key_prefix; db.session.delete(key); db.session.commit(); log_system_event('WARNING', 'API Key Revocada', f"Clave '{name}' (Prefix: {prefix}) revocada por {current_user.username}"); flash(f"Clave API '{name}' revocada.", "success"); return jsonify({"success": True, "message": "Clave API revocada."})
    except Exception as e: db.session.rollback(); app.logger.error(f"Error API revoke_api_key: {e}", exc_info=True); return jsonify({"success": False, "message": "Error al revocar clave."}), 500

@app.route('/configuration/settings/general', methods=['POST'])
@admin_required
def configure_general_settings():
    try:
        settings = load_system_settings(); settings['alerts_enabled'] = 'alerts_enabled' in request.form
        if save_system_settings(settings): flash("Config general guardada.", "success")
    except Exception as e: app.logger.error(f"Error config general: {e}", exc_info=True); flash("Error guardando config.", "danger")
    return redirect(url_for('configuration_page'))

# --- Cleanup Logs ---
@app.route('/configuration/logs/cleanup', methods=['POST'])
@admin_required
def cleanup_old_logs():
    if not check_models_loaded(show_flash=True): return redirect(url_for('configuration_page'))
    days_str = request.form.get('log_retention_days', '365'); export = 'export_logs' in request.form
    try: days = int(days_str); assert days > 0
    except (ValueError, AssertionError): flash("Días retención inválido.", "warning"); return redirect(url_for('configuration_page'))
    cutoff = datetime.now(timezone.utc) - timedelta(days=days); cutoff_str = cutoff.strftime('%Y-%m-%d')
    app.logger.info(f"Limpieza/Export logs < {cutoff_str} por {current_user.username}. Exportar: {export}")
    if export: # CASO 1: Exportar y NO eliminar
        try:
            logs = AccessLog.query.filter(AccessLog.timestamp < cutoff).order_by(AccessLog.timestamp.asc()).all()
            events = SystemEvent.query.filter(SystemEvent.timestamp < cutoff).order_by(SystemEvent.timestamp.asc()).all()
            if not logs and not events: flash(f"No hay logs/eventos < {cutoff_str} para exportar.", "info"); return redirect(url_for('configuration_page'))
            output = io.StringIO(); writer = csv.writer(output)
            writer.writerow(['LogType', 'ID', 'TimestampUTC', 'Level/Granted', 'Type/UID', 'Message/Reason', 'Username', 'IP/KeyfobDesc', 'Door'])
            for log in logs: writer.writerow(['Access', log.id, log.timestamp.strftime('%Y-%m-%d %H:%M:%S') if log.timestamp else '', 'GRANTED' if log.access_granted else 'DENIED', log.keyfob_uid_attempted or 'N/A', log.reason or '', log.username_at_time or 'N/A', log.keyfob_description_at_time or 'N/A', log.door_name or 'Principal'])
            for ev in events: writer.writerow(['System', ev.id, ev.timestamp.strftime('%Y-%m-%d %H:%M:%S') if ev.timestamp else '', ev.level, ev.event_type, ev.message or '', ev.username or 'System', ev.ip_address or 'N/A', 'N/A'])
            output.seek(0); filename = f"exported_logs_before_{cutoff_str}_{datetime.now(timezone.utc).strftime('%Y%m%d%H%M')}.csv"
            response = Response(output.getvalue().encode('utf-8-sig'), mimetype='text/csv; charset=utf-8-sig'); response.headers["Content-Disposition"] = f"attachment; filename=\"{filename}\""
            log_system_event('INFO', 'Logs Exportados (Cleanup)', f"Exportados {len(logs)} acceso, {len(events)} sistema a {filename} (< {cutoff_str})"); return response
        except Exception as e_export: app.logger.error(f"Error exportando logs: {e_export}", exc_info=True); flash("Error generando exportación.", "danger"); return redirect(url_for('configuration_page'))
    else: # CASO 2: Eliminar SIN exportar
        try:
            del_access = AccessLog.query.filter(AccessLog.timestamp < cutoff).delete(synchronize_session=False)
            del_event = SystemEvent.query.filter(SystemEvent.timestamp < cutoff).delete(synchronize_session=False)
            db.session.commit(); msg = f"Limpieza OK. {del_access} logs acceso y {del_event} eventos sistema eliminados (< {cutoff_str})."; log_system_event('WARNING', 'Logs Cleanup', msg); flash(msg, "success"); return redirect(url_for('configuration_page'))
        except Exception as e_delete: db.session.rollback(); app.logger.error(f"Error eliminando logs: {e_delete}", exc_info=True); flash("Error eliminando logs.", "danger"); return redirect(url_for('configuration_page'))

# --- System Update ---
@app.route('/api/system/check_update', methods=['GET'])
@admin_required
def api_check_system_update():
    app.logger.info(f"API: Check updates (Git) por {current_user.username}.")
    try:
        fetch = subprocess.run(['git', 'fetch'], cwd=APP_DIRECTORY, capture_output=True, text=True, check=False, timeout=30)
        if fetch.returncode != 0: app.logger.error(f"Git fetch failed: {fetch.stderr or fetch.stdout}"); return jsonify({"update_available": False, "message": f"Fallo git fetch: {fetch.stderr or 'Error'}"}), 500
        status = subprocess.run(['git', 'status', '-uno'], cwd=APP_DIRECTORY, capture_output=True, text=True, check=True, timeout=10).stdout
        if "up to date" in status: return jsonify({"update_available": False, "current_version": APP_VERSION, "message": "Actualizado."})
        elif "behind" in status:
            log = subprocess.run(['git', 'log', '..origin/main', '--oneline'], cwd=APP_DIRECTORY, capture_output=True, text=True, check=False, timeout=10) # Ajusta rama si es necesario
            clog = log.stdout.strip() if log.returncode == 0 else "No se pudo obtener changelog."
            return jsonify({"update_available": True, "current_version": APP_VERSION, "new_version": "Nueva versión", "changelog": clog})
        elif "diverged" in status: return jsonify({"update_available": False, "message": "Rama local divergente."}), 409
        else: return jsonify({"update_available": False, "message": f"Estado Git desconocido: {status[:200]}..."}), 400
    except FileNotFoundError: app.logger.error("'git' no encontrado."); return jsonify({"update_available": False, "message": "Error: git no encontrado."}), 500
    except Exception as e: app.logger.error(f"Error check updates: {e}", exc_info=True); return jsonify({"update_available": False, "message": f"Error verificando: {e}"}), 500

@app.route('/api/system/install_update', methods=['POST'])
@admin_required
def api_install_system_update():
    app.logger.warning(f"API: Instalación update REAL por {current_user.username}.")
    log_system_event('WARNING', 'Update Install Attempt', f"Instalación REAL iniciada por {current_user.username}")
    try:
        pull_cmd = ['git', 'pull']; app.logger.info(f"Ejecutando: {' '.join(pull_cmd)} en {APP_DIRECTORY}")
        pull = subprocess.run(pull_cmd, cwd=APP_DIRECTORY, capture_output=True, text=True, check=False, timeout=120)
        if pull.returncode != 0: err = f"Error 'git pull': {pull.stderr or pull.stdout}"; app.logger.error(err); log_system_event('ERROR', 'Update Install Failed', f"Fallo git pull: {err[:200]}"); return jsonify(success=False, message=err), 500
        if "Already up to date." in pull.stdout: log_system_event('INFO', 'Update Install', "Sistema ya actualizado."); return jsonify(success=True, message="Sistema ya actualizado.")
        app.logger.info(f"Git pull OK: {pull.stdout[:200]}...")
        # Aquí podrías añadir pasos: pip install -r requirements.txt, flask db upgrade
        restart_cmd = ['sudo', 'systemctl', 'restart', SYSTEMD_SERVICE_NAME]; app.logger.warning(f"Ejecutando reinicio: {' '.join(restart_cmd)}")
        try: subprocess.Popen(restart_cmd); log_system_event('WARNING', 'Update Install Complete', "Reinicio servicio solicitado."); return jsonify(success=True, message="Actualización OK. Reiniciando servicio...")
        except Exception as e_popen: # Fallback síncrono
             app.logger.error(f"Fallo Popen reinicio, intentando síncrono: {e_popen}")
             restart = subprocess.run(restart_cmd, capture_output=True, text=True, check=False, timeout=30)
             if restart.returncode != 0: err = f"Fallo reinicio síncrono: {restart.stderr or restart.stdout}"; app.logger.error(err); log_system_event('ERROR', 'Update Install Failed', f"Fallo reinicio systemctl: {err[:200]}"); return jsonify(success=False, message=f"Update OK, fallo reinicio: {err[:100]}..."), 500
             else: log_system_event('WARNING', 'Update Install Complete', "Reinicio síncrono solicitado."); return jsonify(success=True, message="Actualización OK. Reiniciando (síncrono)...")
    except FileNotFoundError: app.logger.critical("git/sudo/systemctl no encontrado."); log_system_event('CRITICAL', 'Update Install Failed', "git/sudo/systemctl no encontrado."); return jsonify(success=False, message="Error crítico: Falta comando."), 500
    except Exception as e: app.logger.error(f"Excepción update: {e}", exc_info=True); log_system_event('CRITICAL', 'Update Install Failed', f"Excepción: {e}"); return jsonify(success=False, message="Error interno."), 500

# ============================================
# 12. BLOQUE DE INICIALIZACIÓN PRINCIPAL
# ============================================
app.logger.info("="*40); app.logger.info(f"App Access Control v{APP_VERSION} Inicializada"); print("--- Iniciando Bloque Init Principal ---")
initialize_database()
print("INFO: Ejecutando setup_gpio()..."); setup_gpio(); print(f"INFO: Estado HARDWARE_AVAILABLE: {HARDWARE_AVAILABLE}")

# Verificar modo offline al inicio
print("INFO: Verificando modo offline...")
if configure_offline_ethernet_ip():
    print("INFO: Modo offline activado automáticamente")
    log_system_event('INFO', 'Startup', "Modo offline activado automáticamente al inicio", commit=True)
else:
    print("INFO: Modo online - conexión a internet disponible")

with app.app_context(): initial_backup_config = load_auto_backup_config(); update_scheduler_job(initial_backup_config)
start_wiegand_thread_once()
try:
    if not scheduler.running: scheduler.start(); app.logger.info("APScheduler iniciado.")
    else: app.logger.info("APScheduler ya corriendo.")
except Exception as e_start: app.logger.critical(f"APScheduler: ERROR AL INICIAR: {e_start}", exc_info=True)
atexit.register(cleanup_gpio); print("INFO: cleanup_gpio registrada atexit.")
atexit.register(shutdown_scheduler); print("INFO: shutdown_scheduler registrada atexit.")
atexit.register(cleanup_on_shutdown); print("INFO: cleanup_on_shutdown registrada atexit.")
signal.signal(signal.SIGINT, handle_signal); signal.signal(signal.SIGTERM, handle_signal)
print("--- Fin Bloque Init Principal ---")

# ============================================
# 13. BLOQUE DE EJECUCIÓN DIRECTA
# ============================================
if __name__ == '__main__':
    host = os.environ.get('FLASK_RUN_HOST', '0.0.0.0'); port = int(os.environ.get('FLASK_RUN_PORT', 8080)); debug = os.environ.get('FLASK_DEBUG', '0') == '1'
    app.logger.info(f"Iniciando servidor Flask v{APP_VERSION} en {host}:{port} (Debug: {debug})...")
    app.run(host=host, port=port, debug=debug)