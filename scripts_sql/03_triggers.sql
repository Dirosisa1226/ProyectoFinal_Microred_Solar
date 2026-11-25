-- =====================================================================
-- Script 03: Triggers de auditoría y validación
-- =====================================================================

-- ---------------------------------------------------------------------
-- TRIGGER DE AUDITORÍA (INSERT, UPDATE, DELETE)
-- Guarda el registro anterior y el nuevo en formato JSON, el usuario de
-- la aplicación (variable de sesión app.usuario) y el usuario de la BD.
-- Nunca guarda el hash de la contraseña.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_auditoria()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_anterior JSONB;
    v_nuevo    JSONB;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_anterior := to_jsonb(OLD) - 'password_hash';
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_nuevo := to_jsonb(NEW) - 'password_hash';
    END IF;

    INSERT INTO auditoria (tabla, operacion, id_registro, datos_anteriores,
                           datos_nuevos, usuario_app, usuario_bd)
    VALUES (TG_TABLE_NAME, TG_OP,
            (COALESCE(v_nuevo, v_anterior) ->> TG_ARGV[0])::INT,
            v_anterior, v_nuevo,
            current_setting('app.usuario', true), session_user);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_aud_usuario AFTER INSERT OR UPDATE OR DELETE ON usuario
    FOR EACH ROW EXECUTE FUNCTION fn_trg_auditoria('id_usuario');
CREATE TRIGGER trg_aud_hogar AFTER INSERT OR UPDATE OR DELETE ON hogar
    FOR EACH ROW EXECUTE FUNCTION fn_trg_auditoria('id_hogar');
CREATE TRIGGER trg_aud_medidor AFTER INSERT OR UPDATE OR DELETE ON medidor
    FOR EACH ROW EXECUTE FUNCTION fn_trg_auditoria('id_medidor');
CREATE TRIGGER trg_aud_lectura AFTER INSERT OR UPDATE OR DELETE ON lectura
    FOR EACH ROW EXECUTE FUNCTION fn_trg_auditoria('id_lectura');
CREATE TRIGGER trg_aud_tarifa AFTER INSERT OR UPDATE OR DELETE ON tarifa
    FOR EACH ROW EXECUTE FUNCTION fn_trg_auditoria('id_tarifa');
CREATE TRIGGER trg_aud_transaccion AFTER INSERT OR UPDATE OR DELETE ON transaccion_energia
    FOR EACH ROW EXECUTE FUNCTION fn_trg_auditoria('id_transaccion');

-- ---------------------------------------------------------------------
-- TRIGGER DE VALIDACIÓN de lecturas (BEFORE INSERT/UPDATE)
--  * el medidor debe existir y estar ACTIVO
--  * la fecha no puede ser futura
--  * lo generado no puede superar la capacidad del panel x 24 horas
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_validar_lectura()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacidad NUMERIC;
    v_estado    VARCHAR;
BEGIN
    SELECT capacidad_kw, estado INTO v_capacidad, v_estado
      FROM medidor WHERE id_medidor = NEW.id_medidor;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El medidor % no existe', NEW.id_medidor;
    END IF;
    IF v_estado <> 'ACTIVO' THEN
        RAISE EXCEPTION 'El medidor % está INACTIVO y no puede registrar lecturas', NEW.id_medidor;
    END IF;
    IF NEW.fecha > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de la lectura no puede ser futura';
    END IF;
    IF NEW.kwh_generado > v_capacidad * 24 THEN
        RAISE EXCEPTION 'La generación (% kWh) supera el máximo posible del medidor (% kW x 24 h = % kWh)',
              replace(to_char(NEW.kwh_generado, 'FM9999990.000'), '.', ','),
              replace(to_char(v_capacidad, 'FM9990.00'), '.', ','),
              replace(to_char(v_capacidad * 24, 'FM9999990.00'), '.', ',');
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_lectura BEFORE INSERT OR UPDATE ON lectura
    FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_lectura();

-- ---------------------------------------------------------------------
-- TRIGGER que mantiene los créditos de energía del hogar.
-- Excedente de una lectura = MAX(generado - consumido, 0).
-- Si modificar o borrar una lectura deja créditos negativos (porque esa
-- energía ya se vendió), la operación se rechaza.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ajustar_creditos(p_id_hogar INT, p_delta NUMERIC)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_creditos NUMERIC;
BEGIN
    IF p_delta = 0 THEN
        RETURN;
    END IF;
    SELECT creditos_kwh INTO v_creditos FROM hogar WHERE id_hogar = p_id_hogar FOR UPDATE;
    IF v_creditos + p_delta < 0 THEN
        RAISE EXCEPTION 'Operación rechazada: el hogar ya vendió esa energía (créditos disponibles: % kWh)',
              replace(to_char(v_creditos, 'FM9999999990.000'), '.', ',');
    END IF;
    UPDATE hogar SET creditos_kwh = creditos_kwh + p_delta WHERE id_hogar = p_id_hogar;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_creditos_lectura()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_hogar_ant INT;
    v_hogar_nue INT;
    v_exc_ant   NUMERIC := 0;
    v_exc_nue   NUMERIC := 0;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT id_hogar INTO v_hogar_ant FROM medidor WHERE id_medidor = OLD.id_medidor;
        v_exc_ant := GREATEST(OLD.kwh_generado - OLD.kwh_consumido, 0);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT id_hogar INTO v_hogar_nue FROM medidor WHERE id_medidor = NEW.id_medidor;
        v_exc_nue := GREATEST(NEW.kwh_generado - NEW.kwh_consumido, 0);
    END IF;

    IF TG_OP = 'UPDATE' AND v_hogar_ant = v_hogar_nue THEN
        PERFORM fn_ajustar_creditos(v_hogar_nue, v_exc_nue - v_exc_ant);
    ELSE
        IF v_hogar_ant IS NOT NULL THEN
            PERFORM fn_ajustar_creditos(v_hogar_ant, -v_exc_ant);
        END IF;
        IF v_hogar_nue IS NOT NULL THEN
            PERFORM fn_ajustar_creditos(v_hogar_nue, v_exc_nue);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_creditos_lectura AFTER INSERT OR UPDATE OR DELETE ON lectura
    FOR EACH ROW EXECUTE FUNCTION fn_trg_creditos_lectura();
