"""
Arranque del sistema en Render (nube).

1. Si la base de datos está vacía, ejecuta los scripts 01 a 05 con el
   usuario dueño de la base (el mismo orden que 1_instalar_base_datos.bat).
2. Cambia la clave del usuario app_microred por una clave secreta
   (variable APP_DB_PASSWORD), porque la de los scripts es pública en GitHub.
3. Inicia la aplicación Flask con gunicorn conectada como app_microred,
   igual que 2_iniciar_sistema.bat.

Variables de entorno: DATABASE_URL (dueño de la base), APP_DB_PASSWORD,
SECRET_KEY y PORT (las define Render).
"""
import os
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit

import psycopg
from psycopg import sql

RAIZ = Path(__file__).resolve().parent.parent
SCRIPTS = ["01_tablas.sql", "02_funciones_procedimientos.sql", "03_triggers.sql",
           "04_roles_permisos.sql", "05_datos_iniciales.sql"]

url_dueno = os.environ["DATABASE_URL"]
clave_app = os.environ["APP_DB_PASSWORD"]

with psycopg.connect(url_dueno, autocommit=True) as conn:
    instalada = conn.execute("SELECT to_regclass('public.usuario') IS NOT NULL").fetchone()[0]
    if not instalada:
        for nombre in SCRIPTS:
            print(f"Ejecutando {nombre} ...", flush=True)
            texto = (RAIZ / "scripts_sql" / nombre).read_text(encoding="utf-8")
            with conn.transaction():
                conn.execute(texto)
        print("Base de datos instalada.", flush=True)
    conn.execute(sql.SQL("ALTER ROLE app_microred PASSWORD {}").format(sql.Literal(clave_app)))

# Misma base y servidor, pero con el usuario de la aplicación
partes = urlsplit(url_dueno)
servidor = partes.hostname + (f":{partes.port}" if partes.port else "")
os.environ["DATABASE_URL"] = urlunsplit(
    partes._replace(netloc=f"app_microred:{quote(clave_app, safe='')}@{servidor}"))

os.chdir(RAIZ / "codigo_fuente")
puerto = os.environ.get("PORT", "10000")
os.execvp("gunicorn", ["gunicorn", "app:app", "--bind", f"0.0.0.0:{puerto}", "--workers", "2"])
