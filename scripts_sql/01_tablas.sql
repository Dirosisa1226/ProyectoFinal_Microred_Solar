-- =====================================================================
-- Plataforma Transaccional de Energía Solar Compartida (Micro-Grids Barriales)
-- Script 01: Creación de tablas
-- SGBD: PostgreSQL (16 o superior)
-- Ejecutar con el usuario dueño de la base de datos.
-- =====================================================================

-- pgcrypto: funciones crypt() y gen_salt() para el hashing de contraseñas
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TABLE IF EXISTS auditoria, transaccion_energia, lectura, medidor, tarifa, hogar, usuario CASCADE;

-- Usuarios de la aplicación (la contraseña se guarda solo como hash bcrypt)
CREATE TABLE usuario (
    id_usuario      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    correo          VARCHAR(120) NOT NULL UNIQUE,
    password_hash   TEXT         NOT NULL,
    rol             VARCHAR(10)  NOT NULL CHECK (rol IN ('ADMIN', 'OPERADOR')),
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_registro  TIMESTAMP    NOT NULL DEFAULT now()
);

-- Hogares del barrio que participan en la microrred
CREATE TABLE hogar (
    id_hogar        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    documento       VARCHAR(12)   NOT NULL UNIQUE CHECK (documento ~ '^[0-9]{6,12}$'),
    nombre_titular  VARCHAR(100)  NOT NULL,
    direccion       VARCHAR(120)  NOT NULL,
    barrio          VARCHAR(60)   NOT NULL,
    telefono        VARCHAR(10)   NOT NULL CHECK (telefono ~ '^[0-9]{7,10}$'),
    creditos_kwh    NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK (creditos_kwh >= 0),
    fecha_registro  TIMESTAMP     NOT NULL DEFAULT now()
);

-- Medidores bidireccionales instalados en cada hogar
CREATE TABLE medidor (
    id_medidor        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_hogar          INT          NOT NULL REFERENCES hogar (id_hogar) ON DELETE RESTRICT,
    serial            VARCHAR(30)  NOT NULL UNIQUE,
    capacidad_kw      NUMERIC(6,2) NOT NULL CHECK (capacidad_kw > 0 AND capacidad_kw <= 100),
    estado            VARCHAR(10)  NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'INACTIVO')),
    fecha_instalacion DATE         NOT NULL DEFAULT CURRENT_DATE
);

-- Lecturas diarias de energía generada y consumida por medidor
CREATE TABLE lectura (
    id_lectura     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_medidor     INT           NOT NULL REFERENCES medidor (id_medidor) ON DELETE RESTRICT,
    fecha          DATE          NOT NULL,
    kwh_generado   NUMERIC(10,3) NOT NULL CHECK (kwh_generado >= 0),
    kwh_consumido  NUMERIC(10,3) NOT NULL CHECK (kwh_consumido >= 0),
    UNIQUE (id_medidor, fecha)
);

-- Tarifas del kWh dentro de la microrred (solo una activa a la vez)
CREATE TABLE tarifa (
    id_tarifa      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    precio_kwh     NUMERIC(10,2) NOT NULL CHECK (precio_kwh > 0),
    vigente_desde  TIMESTAMP     NOT NULL DEFAULT now(),
    activa         BOOLEAN       NOT NULL DEFAULT TRUE
);
CREATE UNIQUE INDEX ux_tarifa_unica_activa ON tarifa (activa) WHERE activa;

-- Transacciones de energía entre hogares (vendedor -> comprador)
CREATE TABLE transaccion_energia (
    id_transaccion  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vendedor     INT           NOT NULL REFERENCES hogar (id_hogar) ON DELETE RESTRICT,
    id_comprador    INT           NOT NULL REFERENCES hogar (id_hogar) ON DELETE RESTRICT,
    id_tarifa       INT           NOT NULL REFERENCES tarifa (id_tarifa) ON DELETE RESTRICT,
    id_usuario      INT           REFERENCES usuario (id_usuario) ON DELETE SET NULL,
    kwh             NUMERIC(10,3) NOT NULL CHECK (kwh > 0),
    precio_kwh      NUMERIC(10,2) NOT NULL,
    total           NUMERIC(14,2) NOT NULL,
    fecha           TIMESTAMP     NOT NULL DEFAULT now(),
    CHECK (id_vendedor <> id_comprador)
);

-- Bitácora de auditoría (la llenan los triggers)
CREATE TABLE auditoria (
    id_auditoria      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla             VARCHAR(40) NOT NULL,
    operacion         VARCHAR(10) NOT NULL,
    id_registro       INT,
    datos_anteriores  JSONB,
    datos_nuevos      JSONB,
    usuario_app       VARCHAR(120),
    usuario_bd        VARCHAR(60) NOT NULL,
    fecha             TIMESTAMP   NOT NULL DEFAULT now()
);
