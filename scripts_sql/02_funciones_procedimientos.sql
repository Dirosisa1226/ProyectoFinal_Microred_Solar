-- =====================================================================
-- Script 02: Funciones y procedimientos almacenados (PL/pgSQL,
-- equivalente de PL/SQL en PostgreSQL)
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCIÓN: precio vigente del kWh
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_precio_vigente()
RETURNS NUMERIC
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_precio NUMERIC;
BEGIN
    SELECT precio_kwh INTO v_precio FROM tarifa WHERE activa;
    IF v_precio IS NULL THEN
        RAISE EXCEPTION 'No hay una tarifa activa registrada';
    END IF;
    RETURN v_precio;
END;
$$;

-- ---------------------------------------------------------------------
-- FUNCIÓN: resumen energético de un hogar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_resumen_hogar(p_id_hogar INT)
RETURNS TABLE (total_generado NUMERIC, total_consumido NUMERIC,
               kwh_vendidos NUMERIC, kwh_comprados NUMERIC)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE((SELECT SUM(l.kwh_generado) FROM lectura l
                    JOIN medidor m ON m.id_medidor = l.id_medidor
                   WHERE m.id_hogar = p_id_hogar), 0),
        COALESCE((SELECT SUM(l.kwh_consumido) FROM lectura l
                    JOIN medidor m ON m.id_medidor = l.id_medidor
                   WHERE m.id_hogar = p_id_hogar), 0),
        COALESCE((SELECT SUM(t.kwh) FROM transaccion_energia t
                   WHERE t.id_vendedor = p_id_hogar), 0),
        COALESCE((SELECT SUM(t.kwh) FROM transaccion_energia t
                   WHERE t.id_comprador = p_id_hogar), 0);
END;
$$;

-- ---------------------------------------------------------------------
-- FUNCIÓN: validar inicio de sesión comparando el hash bcrypt.
-- SECURITY DEFINER: se ejecuta con permisos del dueño, así el usuario de
-- conexión de la aplicación no necesita leer la tabla usuario.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_login(p_correo VARCHAR, p_password TEXT)
RETURNS TABLE (id_usuario INT, nombre VARCHAR, rol VARCHAR)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id_usuario, u.nombre, u.rol
      FROM usuario u
     WHERE u.correo = lower(trim(p_correo))
       AND u.activo
       AND u.password_hash = crypt(p_password, u.password_hash);
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDIMIENTO: registrar usuario con contraseña hasheada (bcrypt)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_usuario(p_nombre VARCHAR, p_correo VARCHAR,
                                                 p_password TEXT, p_rol VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_password IS NULL OR length(p_password) < 8 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres';
    END IF;
    INSERT INTO usuario (nombre, correo, password_hash, rol)
    VALUES (trim(p_nombre), lower(trim(p_correo)),
            crypt(p_password, gen_salt('bf', 10)), upper(p_rol));
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDIMIENTO TRANSACCIONAL: transferir energía entre dos hogares.
-- Usa COMMIT si todo sale bien y ROLLBACK si alguna validación falla.
-- Concurrencia: bloquea con SELECT ... FOR UPDATE las filas de ambos
-- hogares, siempre en el mismo orden (id menor primero) para evitar
-- interbloqueos (deadlocks) entre transferencias simultáneas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_transferir_energia(p_vendedor INT, p_comprador INT,
                                                  p_kwh NUMERIC, p_id_usuario INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_creditos  NUMERIC;
    v_bloqueados INT;
    v_id_tarifa INT;
    v_precio    NUMERIC;
BEGIN
    IF p_vendedor = p_comprador THEN
        ROLLBACK;
        RAISE EXCEPTION 'El vendedor y el comprador deben ser hogares distintos';
    END IF;

    IF p_kwh IS NULL OR p_kwh <= 0 THEN
        ROLLBACK;
        RAISE EXCEPTION 'La cantidad de kWh debe ser mayor que cero';
    END IF;

    -- Bloqueo pesimista de las dos filas en orden fijo
    SELECT count(*) INTO v_bloqueados
      FROM (SELECT id_hogar FROM hogar
             WHERE id_hogar IN (p_vendedor, p_comprador)
             ORDER BY id_hogar
               FOR UPDATE) AS bloqueo;

    IF v_bloqueados <> 2 THEN
        ROLLBACK;
        RAISE EXCEPTION 'El hogar vendedor o el comprador no existe';
    END IF;

    SELECT creditos_kwh INTO v_creditos FROM hogar WHERE id_hogar = p_vendedor;

    IF v_creditos < p_kwh THEN
        ROLLBACK;
        RAISE EXCEPTION 'Créditos insuficientes: el vendedor solo tiene % kWh disponibles',
              replace(to_char(v_creditos, 'FM9999999990.000'), '.', ',');
    END IF;

    SELECT id_tarifa, precio_kwh INTO v_id_tarifa, v_precio FROM tarifa WHERE activa;
    IF v_id_tarifa IS NULL THEN
        ROLLBACK;
        RAISE EXCEPTION 'No hay una tarifa activa registrada';
    END IF;

    UPDATE hogar SET creditos_kwh = creditos_kwh - p_kwh WHERE id_hogar = p_vendedor;
    UPDATE hogar SET creditos_kwh = creditos_kwh + p_kwh WHERE id_hogar = p_comprador;

    INSERT INTO transaccion_energia (id_vendedor, id_comprador, id_tarifa, id_usuario,
                                     kwh, precio_kwh, total)
    VALUES (p_vendedor, p_comprador, v_id_tarifa, p_id_usuario,
            p_kwh, v_precio, round(p_kwh * v_precio, 2));

    COMMIT;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDIMIENTO TRANSACCIONAL: cambiar la tarifa vigente.
-- LOCK TABLE evita que dos administradores cambien la tarifa a la vez.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cambiar_tarifa(p_precio NUMERIC)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_precio IS NULL OR p_precio <= 0 THEN
        ROLLBACK;
        RAISE EXCEPTION 'El precio por kWh debe ser mayor que cero';
    END IF;

    LOCK TABLE tarifa IN EXCLUSIVE MODE;

    UPDATE tarifa SET activa = FALSE WHERE activa;
    INSERT INTO tarifa (precio_kwh) VALUES (p_precio);

    COMMIT;
END;
$$;
