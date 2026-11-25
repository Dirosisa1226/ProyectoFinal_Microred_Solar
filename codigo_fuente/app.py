"""
Plataforma Transaccional de Energía Solar Compartida (Micro-Grids Barriales)
Aplicación web: Flask + PostgreSQL (psycopg 3)

Variables de entorno requeridas:
  DATABASE_URL  cadena de conexión del usuario app_microred
  SECRET_KEY    clave aleatoria para firmar la sesión
"""
import os
import re
from datetime import date
from decimal import Decimal, InvalidOperation
from functools import wraps

import psycopg
from psycopg import errors, sql
from psycopg.rows import dict_row
from flask import Flask, flash, g, redirect, render_template, request, session, url_for

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.environ["SECRET_KEY"],
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
)
DATABASE_URL = os.environ["DATABASE_URL"]

# Rol de la aplicación -> rol de la base de datos (lista blanca fija)
ROLES_BD = {"ADMIN": "rol_admin_microred", "OPERADOR": "rol_operador_microred"}
RE_CORREO = re.compile(r"[\w.+-]+@[\w-]+(\.[\w-]+)+")


class ErrorValidacion(Exception):
    """Error de datos de entrada detectado por la aplicación."""


# ---------------------------------------------------------------------------
# Conexión a la base de datos
# ---------------------------------------------------------------------------
def db():
    """Una conexión por petición. Si hay sesión iniciada se hace SET ROLE al rol
    de la persona, para que PostgreSQL también aplique los permisos."""
    if "db" not in g:
        conn = psycopg.connect(DATABASE_URL, autocommit=True, row_factory=dict_row)
        if session.get("rol") in ROLES_BD:
            conn.execute(sql.SQL("SET ROLE {}").format(sql.Identifier(ROLES_BD[session["rol"]])))
            conn.execute("SELECT set_config('app.usuario', %s, false)", (session["correo"],))
        g.db = conn
    return g.db


@app.teardown_appcontext
def cerrar_db(_excepcion):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


# Todas las consultas usan parámetros (%s): protección contra inyección SQL.
def consultar(consulta, parametros=()):
    return db().execute(consulta, parametros).fetchall()


def uno(consulta, parametros=()):
    return db().execute(consulta, parametros).fetchone()


def ejecutar(consulta, parametros=()):
    filas = db().execute(consulta, parametros).rowcount
    if filas == 0:
        raise ErrorValidacion("El registro no existe.")


# ---------------------------------------------------------------------------
# Validaciones de entrada
# ---------------------------------------------------------------------------
def campo_texto(nombre, etiqueta, maximo, patron=None, mensaje_patron=None):
    valor = request.form.get(nombre, "").strip()
    if not valor:
        raise ErrorValidacion(f"El campo {etiqueta} es obligatorio.")
    if len(valor) > maximo:
        raise ErrorValidacion(f"{etiqueta} admite máximo {maximo} caracteres.")
    if patron and not re.fullmatch(patron, valor):
        raise ErrorValidacion(mensaje_patron)
    return valor


def campo_entero(nombre, etiqueta):
    valor = request.form.get(nombre, "")
    if not valor.isdigit() or int(valor) <= 0:
        raise ErrorValidacion(f"Seleccione un valor válido para {etiqueta}.")
    return int(valor)


def campo_decimal(nombre, etiqueta, minimo, maximo):
    try:
        valor = Decimal(request.form.get(nombre, "").strip().replace(",", "."))
    except InvalidOperation:
        raise ErrorValidacion(f"{etiqueta} debe ser un número.")
    if not valor.is_finite() or valor < Decimal(minimo) or valor > Decimal(maximo):
        raise ErrorValidacion(f"{etiqueta} debe estar entre {minimo} y {maximo}.")
    return valor


def campo_fecha(nombre, etiqueta):
    try:
        valor = date.fromisoformat(request.form.get(nombre, ""))
    except ValueError:
        raise ErrorValidacion(f"{etiqueta} no es una fecha válida.")
    if valor > date.today():
        raise ErrorValidacion(f"{etiqueta} no puede ser futura.")
    return valor


def campo_opcion(nombre, etiqueta, opciones):
    valor = request.form.get(nombre, "")
    if valor not in opciones:
        raise ErrorValidacion(f"Valor no permitido para {etiqueta}.")
    return valor


def id_edicion(nombre):
    valor = request.form.get(nombre, "")
    if valor and not valor.isdigit():
        raise ErrorValidacion("Identificador inválido.")
    return int(valor) if valor else None


def mensaje_error(e):
    if isinstance(e, ErrorValidacion):
        return str(e)
    if isinstance(e, errors.RaiseException):          # mensajes de procedimientos y triggers
        return e.diag.message_primary
    if isinstance(e, errors.UniqueViolation):
        return "Ya existe un registro con ese dato único (documento, serial, correo o lectura del mismo día)."
    if isinstance(e, errors.ForeignKeyViolation):
        if "update or delete" in (e.diag.message_primary or ""):
            return "No se puede eliminar: tiene registros relacionados."
        return "El registro relacionado no existe."
    if isinstance(e, errors.CheckViolation):
        return "Algún dato no cumple las reglas de la base de datos."
    if isinstance(e, errors.InsufficientPrivilege):
        return "Su rol no tiene permiso para esta operación."
    app.logger.exception(e)
    return "Ocurrió un error en la base de datos."


def operar(accion, mensaje_exito, destino):
    try:
        accion()
        flash(mensaje_exito, "ok")
    except (ErrorValidacion, psycopg.Error) as e:
        flash(mensaje_error(e), "error")
    return redirect(destino)


# ---------------------------------------------------------------------------
# Sesión y permisos de la aplicación
# ---------------------------------------------------------------------------
def requiere_login(vista):
    @wraps(vista)
    def envoltura(*args, **kwargs):
        if "id_usuario" not in session:
            return redirect(url_for("login"))
        return vista(*args, **kwargs)
    return envoltura


def solo_admin(vista):
    @wraps(vista)
    @requiere_login
    def envoltura(*args, **kwargs):
        if session.get("rol") != "ADMIN":
            flash("Solo el administrador puede realizar esta acción.", "error")
            return redirect(url_for("hogares"))
        return vista(*args, **kwargs)
    return envoltura


@app.context_processor
def datos_plantillas():
    return {"hoy": date.today().isoformat(), "es_admin": session.get("rol") == "ADMIN"}


@app.template_filter("num")
def formato_numero(valor, decimales=2):
    if valor is None:
        return ""
    texto = f"{valor:,.{decimales}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        correo = request.form.get("correo", "").strip().lower()
        clave = request.form.get("password", "")
        if not RE_CORREO.fullmatch(correo) or not clave or len(clave) > 72:
            flash("Correo o contraseña con formato inválido.", "error")
        else:
            fila = uno("SELECT * FROM fn_validar_login(%s, %s)", (correo, clave))
            if fila:
                session.clear()
                session.update(id_usuario=fila["id_usuario"], nombre=fila["nombre"],
                               rol=fila["rol"], correo=correo)
                return redirect(url_for("hogares"))
            flash("Correo o contraseña incorrectos.", "error")
    return render_template("login.html")


@app.route("/salir")
def salir():
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
@requiere_login
def inicio():
    return redirect(url_for("hogares"))


# ---------------------------------------------------------------------------
# HOGARES
# ---------------------------------------------------------------------------
@app.route("/hogares")
@requiere_login
def hogares():
    q = request.args.get("q", "").strip()[:60]
    filas = consultar("""
        SELECT h.*, r.*,
               (SELECT count(*) FROM medidor m WHERE m.id_hogar = h.id_hogar) AS medidores
          FROM hogar h CROSS JOIN LATERAL fn_resumen_hogar(h.id_hogar) r
         WHERE %(q)s = '' OR h.nombre_titular ILIKE %(p)s
               OR h.documento ILIKE %(p)s OR h.barrio ILIKE %(p)s
         ORDER BY h.id_hogar""", {"q": q, "p": f"%{q}%"})
    edicion = None
    if request.args.get("editar", "").isdigit():
        edicion = uno("SELECT * FROM hogar WHERE id_hogar = %s", (int(request.args["editar"]),))
    return render_template("hogares.html", filas=filas, q=q, edicion=edicion)


@app.post("/hogares/guardar")
@requiere_login
def guardar_hogar():
    def accion():
        id_hogar = id_edicion("id_hogar")
        datos = (
            campo_texto("documento", "Documento", 12, r"[0-9]{6,12}",
                        "El documento debe tener entre 6 y 12 dígitos."),
            campo_texto("nombre_titular", "Titular", 100),
            campo_texto("direccion", "Dirección", 120),
            campo_texto("barrio", "Barrio", 60),
            campo_texto("telefono", "Teléfono", 10, r"[0-9]{7,10}",
                        "El teléfono debe tener entre 7 y 10 dígitos."),
        )
        if id_hogar:
            ejecutar("""UPDATE hogar SET documento = %s, nombre_titular = %s, direccion = %s,
                        barrio = %s, telefono = %s WHERE id_hogar = %s""", (*datos, id_hogar))
        else:
            ejecutar("""INSERT INTO hogar (documento, nombre_titular, direccion, barrio, telefono)
                        VALUES (%s, %s, %s, %s, %s)""", datos)
    return operar(accion, "Hogar guardado correctamente.", url_for("hogares"))


@app.post("/hogares/<int:id_hogar>/eliminar")
@solo_admin
def eliminar_hogar(id_hogar):
    return operar(lambda: ejecutar("DELETE FROM hogar WHERE id_hogar = %s", (id_hogar,)),
                  "Hogar eliminado.", url_for("hogares"))


# ---------------------------------------------------------------------------
# MEDIDORES
# ---------------------------------------------------------------------------
@app.route("/medidores")
@requiere_login
def medidores():
    filas = consultar("""
        SELECT m.*, h.nombre_titular,
               (SELECT count(*) FROM lectura l WHERE l.id_medidor = m.id_medidor) AS lecturas
          FROM medidor m JOIN hogar h ON h.id_hogar = m.id_hogar
         ORDER BY m.id_medidor""")
    lista_hogares = consultar("SELECT id_hogar, nombre_titular FROM hogar ORDER BY nombre_titular")
    edicion = None
    if request.args.get("editar", "").isdigit():
        edicion = uno("SELECT * FROM medidor WHERE id_medidor = %s", (int(request.args["editar"]),))
    return render_template("medidores.html", filas=filas, hogares=lista_hogares, edicion=edicion)


@app.post("/medidores/guardar")
@requiere_login
def guardar_medidor():
    def accion():
        id_medidor = id_edicion("id_medidor")
        datos = (
            campo_entero("id_hogar", "Hogar"),
            campo_texto("serial", "Serial", 30, r"[A-Z0-9-]{4,30}",
                        "El serial solo admite mayúsculas, números y guiones (4 a 30)."),
            campo_decimal("capacidad_kw", "Capacidad (kW)", "0.1", "100"),
            campo_opcion("estado", "Estado", ("ACTIVO", "INACTIVO")),
            campo_fecha("fecha_instalacion", "Fecha de instalación"),
        )
        if id_medidor:
            ejecutar("""UPDATE medidor SET id_hogar = %s, serial = %s, capacidad_kw = %s,
                        estado = %s, fecha_instalacion = %s WHERE id_medidor = %s""",
                     (*datos, id_medidor))
        else:
            ejecutar("""INSERT INTO medidor (id_hogar, serial, capacidad_kw, estado, fecha_instalacion)
                        VALUES (%s, %s, %s, %s, %s)""", datos)
    return operar(accion, "Medidor guardado correctamente.", url_for("medidores"))


@app.post("/medidores/<int:id_medidor>/eliminar")
@solo_admin
def eliminar_medidor(id_medidor):
    return operar(lambda: ejecutar("DELETE FROM medidor WHERE id_medidor = %s", (id_medidor,)),
                  "Medidor eliminado.", url_for("medidores"))


# ---------------------------------------------------------------------------
# LECTURAS
# ---------------------------------------------------------------------------
@app.route("/lecturas")
@requiere_login
def lecturas():
    filtro = request.args.get("medidor", "")
    filtro = int(filtro) if filtro.isdigit() else None
    filas = consultar("""
        SELECT l.*, m.serial, h.nombre_titular,
               GREATEST(l.kwh_generado - l.kwh_consumido, 0) AS excedente
          FROM lectura l
          JOIN medidor m ON m.id_medidor = l.id_medidor
          JOIN hogar h   ON h.id_hogar = m.id_hogar
         WHERE %(f)s::int IS NULL OR l.id_medidor = %(f)s::int
         ORDER BY l.fecha DESC, l.id_medidor
         LIMIT 200""", {"f": filtro})
    lista_medidores = consultar("""SELECT m.id_medidor, m.serial, m.estado, h.nombre_titular
                                     FROM medidor m JOIN hogar h ON h.id_hogar = m.id_hogar
                                    ORDER BY m.serial""")
    edicion = None
    if request.args.get("editar", "").isdigit():
        edicion = uno("SELECT * FROM lectura WHERE id_lectura = %s", (int(request.args["editar"]),))
    return render_template("lecturas.html", filas=filas, medidores=lista_medidores,
                           edicion=edicion, filtro=filtro)


@app.post("/lecturas/guardar")
@requiere_login
def guardar_lectura():
    def accion():
        id_lectura = id_edicion("id_lectura")
        datos = (
            campo_entero("id_medidor", "Medidor"),
            campo_fecha("fecha", "Fecha"),
            campo_decimal("kwh_generado", "kWh generados", "0", "2400"),
            campo_decimal("kwh_consumido", "kWh consumidos", "0", "2400"),
        )
        if id_lectura:
            ejecutar("""UPDATE lectura SET id_medidor = %s, fecha = %s, kwh_generado = %s,
                        kwh_consumido = %s WHERE id_lectura = %s""", (*datos, id_lectura))
        else:
            ejecutar("""INSERT INTO lectura (id_medidor, fecha, kwh_generado, kwh_consumido)
                        VALUES (%s, %s, %s, %s)""", datos)
    return operar(accion, "Lectura guardada correctamente.", url_for("lecturas"))


@app.post("/lecturas/<int:id_lectura>/eliminar")
@solo_admin
def eliminar_lectura(id_lectura):
    return operar(lambda: ejecutar("DELETE FROM lectura WHERE id_lectura = %s", (id_lectura,)),
                  "Lectura eliminada.", url_for("lecturas"))


# ---------------------------------------------------------------------------
# TRANSFERENCIAS DE ENERGÍA (procedimiento transaccional)
# ---------------------------------------------------------------------------
@app.route("/transferencias")
@requiere_login
def transferencias():
    filas = consultar("""
        SELECT t.*, v.nombre_titular AS vendedor, c.nombre_titular AS comprador,
               u.nombre AS registrado_por
          FROM transaccion_energia t
          JOIN hogar v ON v.id_hogar = t.id_vendedor
          JOIN hogar c ON c.id_hogar = t.id_comprador
          LEFT JOIN usuario u ON u.id_usuario = t.id_usuario
         ORDER BY t.id_transaccion DESC
         LIMIT 200""")
    lista_hogares = consultar("""SELECT id_hogar, nombre_titular, creditos_kwh
                                   FROM hogar ORDER BY nombre_titular""")
    try:
        precio = uno("SELECT fn_precio_vigente() AS precio")["precio"]
    except errors.RaiseException:
        precio = None
    return render_template("transferencias.html", filas=filas, hogares=lista_hogares, precio=precio)


@app.post("/transferencias/registrar")
@requiere_login
def registrar_transferencia():
    def accion():
        vendedor = campo_entero("id_vendedor", "Vendedor")
        comprador = campo_entero("id_comprador", "Comprador")
        kwh = campo_decimal("kwh", "kWh a transferir", "0.001", "100000")
        if vendedor == comprador:
            raise ErrorValidacion("El vendedor y el comprador deben ser hogares distintos.")
        db().execute("CALL sp_transferir_energia(%s::int, %s::int, %s::numeric, %s::int)",
                     (vendedor, comprador, kwh, session["id_usuario"]))
    return operar(accion, "Transferencia registrada correctamente.", url_for("transferencias"))


# ---------------------------------------------------------------------------
# TARIFAS (solo administrador)
# ---------------------------------------------------------------------------
@app.route("/tarifas")
@solo_admin
def tarifas():
    filas = consultar("SELECT * FROM tarifa ORDER BY id_tarifa DESC")
    return render_template("tarifas.html", filas=filas)


@app.post("/tarifas/nueva")
@solo_admin
def nueva_tarifa():
    def accion():
        precio = campo_decimal("precio_kwh", "Precio por kWh", "1", "100000")
        db().execute("CALL sp_cambiar_tarifa(%s::numeric)", (precio,))
    return operar(accion, "Nueva tarifa activa.", url_for("tarifas"))


# ---------------------------------------------------------------------------
# USUARIOS (solo administrador)
# ---------------------------------------------------------------------------
@app.route("/usuarios")
@solo_admin
def usuarios():
    filas = consultar("""SELECT id_usuario, nombre, correo, rol, activo, fecha_registro
                           FROM usuario ORDER BY id_usuario""")
    edicion = None
    if request.args.get("editar", "").isdigit():
        edicion = uno("SELECT id_usuario, nombre, correo, rol, activo FROM usuario WHERE id_usuario = %s",
                      (int(request.args["editar"]),))
    return render_template("usuarios.html", filas=filas, edicion=edicion)


@app.post("/usuarios/guardar")
@solo_admin
def guardar_usuario():
    def accion():
        id_usuario = id_edicion("id_usuario")
        nombre = campo_texto("nombre", "Nombre", 100)
        rol = campo_opcion("rol", "Rol", tuple(ROLES_BD))
        if id_usuario:
            activo = request.form.get("activo") == "on"
            if id_usuario == session["id_usuario"] and (rol != "ADMIN" or not activo):
                raise ErrorValidacion("No puede quitarse su propio rol de administrador ni desactivarse.")
            ejecutar("UPDATE usuario SET nombre = %s, rol = %s, activo = %s WHERE id_usuario = %s",
                     (nombre, rol, activo, id_usuario))
        else:
            correo = campo_texto("correo", "Correo", 120).lower()
            if not RE_CORREO.fullmatch(correo):
                raise ErrorValidacion("El correo no tiene un formato válido.")
            clave = request.form.get("password", "")
            if not 8 <= len(clave) <= 72:
                raise ErrorValidacion("La contraseña debe tener entre 8 y 72 caracteres.")
            if not (re.search(r"[A-Za-z]", clave) and re.search(r"[0-9]", clave)):
                raise ErrorValidacion("La contraseña debe combinar letras y números.")
            db().execute("CALL sp_registrar_usuario(%s, %s, %s, %s)", (nombre, correo, clave, rol))
    return operar(accion, "Usuario guardado correctamente.", url_for("usuarios"))


@app.post("/usuarios/<int:id_usuario>/eliminar")
@solo_admin
def eliminar_usuario(id_usuario):
    def accion():
        if id_usuario == session["id_usuario"]:
            raise ErrorValidacion("No puede eliminar su propio usuario.")
        ejecutar("DELETE FROM usuario WHERE id_usuario = %s", (id_usuario,))
    return operar(accion, "Usuario eliminado.", url_for("usuarios"))


# ---------------------------------------------------------------------------
# AUDITORÍA (solo administrador, solo lectura)
# ---------------------------------------------------------------------------
TABLAS_AUDITADAS = ("usuario", "hogar", "medidor", "lectura", "tarifa", "transaccion_energia")


@app.route("/auditoria")
@solo_admin
def auditoria():
    tabla = request.args.get("tabla", "")
    tabla = tabla if tabla in TABLAS_AUDITADAS else ""
    filas = consultar("""SELECT * FROM auditoria
                          WHERE %(t)s = '' OR tabla = %(t)s
                          ORDER BY id_auditoria DESC LIMIT 200""", {"t": tabla})
    for fila in filas:
        antes = fila["datos_anteriores"] or {}
        despues = fila["datos_nuevos"] or {}
        if fila["operacion"] == "UPDATE":   # solo los campos que cambiaron
            fila["detalle"] = [(k, antes.get(k), v) for k, v in despues.items() if antes.get(k) != v]
        else:
            fila["detalle"] = [(k, None, v) for k, v in (despues or antes).items()]
    return render_template("auditoria.html", filas=filas, tabla=tabla, tablas=TABLAS_AUDITADAS)


if __name__ == "__main__":
    app.run(debug=False)
