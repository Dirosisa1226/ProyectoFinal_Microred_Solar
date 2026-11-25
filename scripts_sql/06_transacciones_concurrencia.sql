-- =====================================================================
-- Script 06: Pruebas de transacciones (COMMIT / ROLLBACK) y concurrencia
-- Ejecutar cada bloque por separado (por ejemplo en psql), en modo
-- autocommit, porque los procedimientos hacen COMMIT/ROLLBACK internos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Transferencia válida -> el procedimiento termina con COMMIT
-- ---------------------------------------------------------------------
CALL sp_transferir_energia(6, 3, 8.5, 1);   -- Héctor (vendedor) -> Luz Marina (compradora)
SELECT id_hogar, nombre_titular, creditos_kwh FROM hogar WHERE id_hogar IN (3, 6);

-- ---------------------------------------------------------------------
-- 2) Transferencia inválida (créditos insuficientes) -> ROLLBACK
--    Resultado esperado: ERROR "Créditos insuficientes ..." y ningún cambio
-- ---------------------------------------------------------------------
CALL sp_transferir_energia(1, 5, 9999, 1);
SELECT id_hogar, creditos_kwh FROM hogar WHERE id_hogar IN (1, 5);

-- ---------------------------------------------------------------------
-- 3) Transacción manual con ROLLBACK: los cambios se descartan
-- ---------------------------------------------------------------------
BEGIN;
    UPDATE medidor SET estado = 'INACTIVO' WHERE id_medidor = 1;
    SELECT id_medidor, estado FROM medidor WHERE id_medidor = 1;   -- INACTIVO dentro de la transacción
ROLLBACK;
SELECT id_medidor, estado FROM medidor WHERE id_medidor = 1;       -- vuelve a ACTIVO

-- ---------------------------------------------------------------------
-- 4) Transacción manual con COMMIT: los cambios quedan guardados
-- ---------------------------------------------------------------------
BEGIN;
    UPDATE hogar SET telefono = '3104567891' WHERE id_hogar = 1;
COMMIT;
SELECT id_hogar, telefono FROM hogar WHERE id_hogar = 1;

-- ---------------------------------------------------------------------
-- 5) Concurrencia: dos sesiones intentan mover créditos del mismo hogar
--    (abrir dos ventanas de psql conectadas a la misma base)
-- ---------------------------------------------------------------------
-- SESIÓN A:
--   BEGIN;
--   SELECT creditos_kwh FROM hogar WHERE id_hogar = 2 FOR UPDATE;   -- bloquea la fila
--
-- SESIÓN B (queda en espera hasta que A termine):
--   CALL sp_transferir_energia(2, 5, 1.0, 1);
--
-- SESIÓN A:
--   COMMIT;   -- en ese momento B continúa, lee el saldo ya actualizado y hace su COMMIT
--
-- Nivel de aislamiento por defecto en PostgreSQL:
SHOW transaction_isolation;   -- read committed
