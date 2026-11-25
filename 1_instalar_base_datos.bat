@echo off
REM ==================================================================
REM  Paso 1: instala la base de datos "microred" en PostgreSQL local
REM  Requiere PostgreSQL 16 o superior instalado en Windows.
REM ==================================================================
setlocal
cd /d "%~dp0scripts_sql"
set "PSQL="
where psql >nul 2>nul && set "PSQL=psql"
if not defined PSQL for /d %%D in ("C:\Program Files\PostgreSQL\*") do if exist "%%D\bin\psql.exe" set "PSQL=%%D\bin\psql.exe"
if not defined PSQL (
    echo No se encontro PostgreSQL. Instalelo desde https://www.postgresql.org/download/windows/
    pause & exit /b 1
)
set PGCLIENTENCODING=UTF8
echo.
echo Se creara (o se reemplazara) la base de datos "microred".
set /p "PGPASSWORD=Escriba la clave del usuario postgres y presione Enter: "
"%PSQL%" -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -q -c "DROP DATABASE IF EXISTS microred" -c "CREATE DATABASE microred" || goto error
for %%F in (01_tablas.sql 02_funciones_procedimientos.sql 03_triggers.sql 04_roles_permisos.sql 05_datos_iniciales.sql) do (
    echo Ejecutando %%F ...
    "%PSQL%" -h localhost -U postgres -d microred -v ON_ERROR_STOP=1 -q -f %%F || goto error
)
echo.
echo Base de datos instalada correctamente. Ahora ejecute 2_iniciar_sistema.bat
pause
exit /b 0
:error
echo.
echo Ocurrio un error. Revise la clave de postgres y que el servicio de PostgreSQL este iniciado.
pause
exit /b 1
