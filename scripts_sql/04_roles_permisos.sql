-- =====================================================================
-- Script 04: Roles y permisos
-- * rol_admin_microred    : CRUD completo, usuarios, tarifas y auditoría
-- * rol_operador_microred : registra/edita hogares, medidores, lecturas
--                           y transferencias; NO elimina, NO ve usuarios
--                           ni auditoría
-- * app_microred          : usuario de conexión de la aplicación web.
--   Es NOINHERIT: no tiene permisos propios; en cada petición la app hace
--   SET ROLE al rol de la persona que inició sesión, así la base de datos
--   también aplica los permisos (no solo la interfaz).
-- =====================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_admin_microred') THEN
        CREATE ROLE rol_admin_microred NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_operador_microred') THEN
        CREATE ROLE rol_operador_microred NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_microred') THEN
        CREATE ROLE app_microred LOGIN NOINHERIT PASSWORD 'ProyectoFinal2026*';
    END IF;
END;
$$;

GRANT rol_admin_microred, rol_operador_microred TO app_microred;

-- Quitar los permisos por defecto de PUBLIC
REVOKE ALL ON usuario, hogar, medidor, lectura, tarifa, transaccion_energia, auditoria FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_precio_vigente(), fn_resumen_hogar(INT),
                           fn_validar_login(VARCHAR, TEXT), fn_ajustar_creditos(INT, NUMERIC)
    FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE sp_registrar_usuario(VARCHAR, VARCHAR, TEXT, VARCHAR),
                            sp_transferir_energia(INT, INT, NUMERIC, INT),
                            sp_cambiar_tarifa(NUMERIC)
    FROM PUBLIC;

-- Usuario de conexión: solo puede validar el login antes del SET ROLE
GRANT EXECUTE ON FUNCTION fn_validar_login(VARCHAR, TEXT) TO app_microred;

-- Permisos comunes
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO rol_admin_microred, rol_operador_microred;
GRANT EXECUTE ON FUNCTION fn_precio_vigente(), fn_resumen_hogar(INT), fn_ajustar_creditos(INT, NUMERIC)
    TO rol_admin_microred, rol_operador_microred;

-- ADMINISTRADOR
GRANT SELECT, INSERT, UPDATE, DELETE
    ON usuario, hogar, medidor, lectura, tarifa, transaccion_energia TO rol_admin_microred;
GRANT SELECT ON auditoria TO rol_admin_microred;          -- la auditoría es de solo lectura
GRANT EXECUTE ON PROCEDURE sp_registrar_usuario(VARCHAR, VARCHAR, TEXT, VARCHAR),
                           sp_transferir_energia(INT, INT, NUMERIC, INT),
                           sp_cambiar_tarifa(NUMERIC)
    TO rol_admin_microred;

-- OPERADOR
GRANT SELECT ON hogar, medidor, lectura, tarifa, transaccion_energia TO rol_operador_microred;
GRANT SELECT (id_usuario, nombre) ON usuario TO rol_operador_microred;
GRANT INSERT, UPDATE ON hogar, medidor, lectura TO rol_operador_microred;
GRANT INSERT ON transaccion_energia TO rol_operador_microred;
GRANT EXECUTE ON PROCEDURE sp_transferir_energia(INT, INT, NUMERIC, INT) TO rol_operador_microred;
