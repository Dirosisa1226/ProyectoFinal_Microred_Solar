# Proyecto Final – Microred Solar

Sistema web (Flask + PostgreSQL) para gestionar una microred solar comunitaria: hogares, medidores, lecturas, tarifas, transferencias de energía, usuarios y auditoría.

**Autores:** Diego Rolando Silva Sánchez, Julián Sneyder Tocanchón Moncada, Andrea Caterin Basto Martin

## Contenido

| Ruta | Descripción |
|------|-------------|
| `Informe_Proyecto_Final_Microred_Solar.pdf` | Informe del proyecto |
| `scripts_sql/` | Tablas, funciones/procedimientos, triggers, roles y permisos, datos iniciales, transacciones y concurrencia |
| `codigo_fuente/` | Aplicación web Flask (`app.py`, plantillas HTML y estilos) |
| `1_instalar_base_datos.bat` | Crea la base de datos `microred` en PostgreSQL local |
| `2_iniciar_sistema.bat` | Instala dependencias e inicia el sistema en http://127.0.0.1:5000 |

## Versión en línea

El sistema también está desplegado en la nube con Render (`render.yaml` y `despliegue/iniciar_render.py`).
En el plan gratuito, la primera visita después de un rato sin uso puede tardar cerca de un minuto en cargar.

## Cómo ejecutarlo (Windows)

1. Instalar PostgreSQL 16+ y Python 3.11+.
2. Ejecutar `1_instalar_base_datos.bat` (pide la clave del usuario `postgres`).
3. Ejecutar `2_iniciar_sistema.bat`; se abre el navegador en http://127.0.0.1:5000.
