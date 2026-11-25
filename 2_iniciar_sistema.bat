@echo off
REM ==================================================================
REM  Paso 2: inicia el sistema web en http://127.0.0.1:5000
REM  Requiere Python 3.11 o superior (marcar "Add python.exe to PATH").
REM ==================================================================
setlocal
cd /d "%~dp0codigo_fuente"
python --version >nul 2>nul || (
    echo No se encontro Python. Instalelo desde https://www.python.org/downloads/
    pause & exit /b 1
)
if not exist ".venv\Scripts\python.exe" (
    echo Primera ejecucion: instalando librerias, espere un momento...
    python -m venv .venv || goto error
    ".venv\Scripts\python.exe" -m pip install -q -r requirements.txt || goto error
)
set "DATABASE_URL=postgresql://app_microred:ProyectoFinal2026*@localhost:5432/microred"
for /f %%K in ('".venv\Scripts\python.exe" -c "import secrets; print(secrets.token_hex(32))"') do set "SECRET_KEY=%%K"
echo.
echo Sistema iniciado en http://127.0.0.1:5000  (cierre esta ventana para detenerlo)
start "" cmd /c "timeout /t 3 >nul & start http://127.0.0.1:5000"
".venv\Scripts\python.exe" -m flask --app app run --host 127.0.0.1 --port 5000
exit /b 0
:error
echo Ocurrio un error al instalar las librerias. Revise su conexion a internet.
pause
exit /b 1
