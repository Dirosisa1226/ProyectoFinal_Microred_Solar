-- =====================================================================
-- Script 05: Datos iniciales
-- Los créditos de energía de cada hogar NO se insertan a mano: los
-- calcula el trigger trg_creditos_lectura al insertar las lecturas.
-- =====================================================================

SET app.usuario = 'script_datos_iniciales';

-- Tarifa interna de la microrred (COP por kWh)
INSERT INTO tarifa (precio_kwh) VALUES (650.00);

-- Usuarios (la contraseña se guarda con hash bcrypt dentro del procedimiento)
CALL sp_registrar_usuario('Administrador General', 'admin@microred.co',    'Admin2026*',    'ADMIN');
CALL sp_registrar_usuario('Operador de Turno',     'operador@microred.co', 'Operador2026*', 'OPERADOR');

-- Hogares
INSERT INTO hogar (documento, nombre_titular, direccion, barrio, telefono) VALUES
('1012345678', 'María Fernanda Rojas',  'Cra 72 # 40-15 Sur',  'Timiza', '3104567890'),
('79845123',   'Carlos Andrés Peña',    'Cl 42 Sur # 71-20',   'Timiza', '3125558899'),
('1023456789', 'Luz Marina Cárdenas',   'Cra 74 # 38-60 Sur',  'Timiza', '3008881122'),
('52789456',   'Jorge Eliécer Moreno',  'Cl 40 Sur # 73-11',   'Timiza', '3159994455'),
('1030567812', 'Paola Andrea Gil',      'Cra 71D # 41-05 Sur', 'Timiza', '3207771234'),
('80123987',   'Héctor Julio Ramírez',  'Cl 43 Sur # 72-33',   'Timiza', '6017654321');

-- Medidores bidireccionales
INSERT INTO medidor (id_hogar, serial, capacidad_kw, fecha_instalacion) VALUES
(1, 'MED-TMZ-001', 3.50, '2026-08-01'),
(2, 'MED-TMZ-002', 5.00, '2026-08-01'),
(3, 'MED-TMZ-003', 2.80, '2026-08-03'),
(4, 'MED-TMZ-004', 4.20, '2026-08-03'),
(5, 'MED-TMZ-005', 3.00, '2026-08-05'),
(6, 'MED-TMZ-006', 6.00, '2026-08-05');

-- Lecturas diarias (kWh generados y consumidos)
INSERT INTO lectura (id_medidor, fecha, kwh_generado, kwh_consumido) VALUES
(1, '2026-11-01', 13.2,  7.4), (1, '2026-11-02', 12.8,  8.1), (1, '2026-11-03', 10.5,  7.9),
(1, '2026-11-04', 14.1,  6.8), (1, '2026-11-05', 11.9,  7.2),
(2, '2026-11-01', 18.6,  9.2), (2, '2026-11-02', 17.9, 10.1), (2, '2026-11-03', 14.2,  9.8),
(2, '2026-11-04', 19.4,  8.7), (2, '2026-11-05', 16.8,  9.5),
(3, '2026-11-01',  9.1, 11.3), (3, '2026-11-02',  8.7, 10.8), (3, '2026-11-03',  7.2, 11.9),
(3, '2026-11-04',  9.8, 10.4), (3, '2026-11-05',  8.4, 11.1),
(4, '2026-11-01', 15.3, 12.4), (4, '2026-11-02', 14.6, 13.0), (4, '2026-11-03', 12.1, 12.7),
(4, '2026-11-04', 16.2, 11.8), (4, '2026-11-05', 13.9, 12.2),
(5, '2026-11-01', 10.8, 12.6), (5, '2026-11-02', 10.2, 13.2), (5, '2026-11-03',  8.6, 12.9),
(5, '2026-11-04', 11.5, 12.1), (5, '2026-11-05',  9.9, 12.8),
(6, '2026-11-01', 22.4, 10.5), (6, '2026-11-02', 21.6, 11.2), (6, '2026-11-03', 17.3, 10.8),
(6, '2026-11-04', 23.5,  9.9), (6, '2026-11-05', 20.2, 10.6);
