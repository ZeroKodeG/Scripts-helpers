@echo off
setlocal EnableDelayedExpansion
goto :inicio

:: =============================================================================
::  ejecutar_auditoria.bat
::  Descarga los 3 modulos de auditoria desde el propio backend (ruta publica
::  /scripts, sin auth), los ejecuta, y sube los 3 reportes resultantes al
::  backend central via API KEY.
::
::  Requiere curl (incluido de forma nativa desde Windows 10 1803+).
::
::  Configuracion (una sola vez por equipo), por cualquiera de estas 2 vias:
::   1) Variables de entorno de sistema: AUDIT_API_KEY y AUDIT_API_URL
::   2) Archivo local NO versionado: %USERPROFILE%\.audit_config con lineas:
::        API_KEY=tu-api-key
::        API_URL=https://tu-backend.tld
::
::  La API KEY NUNCA debe escribirse en este archivo: solo se usa para el
::  POST final de subida de reportes, no para descargar los modulos.
:: =============================================================================

:cargar_config
:: Prioridad 1: variables de entorno ya definidas en el sistema
if defined AUDIT_API_KEY set "API_KEY=%AUDIT_API_KEY%"
if defined AUDIT_API_URL set "API_URL=%AUDIT_API_URL%"

:: Prioridad 2: archivo local %USERPROFILE%\.audit_config (no versionado)
if not defined API_KEY if exist "%USERPROFILE%\.audit_config" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%USERPROFILE%\.audit_config") do (
        if /i "%%A"=="API_KEY" set "API_KEY=%%B"
        if /i "%%A"=="API_URL" set "API_URL=%%B"
    )
)
exit /b

:limpiar_temporales
del "%TMP_SISTEMA%" >nul 2>&1
del "%TMP_RED%" >nul 2>&1
del "%TMP_LOGS%" >nul 2>&1
exit /b

:inicio
title Auditoria Completa - Descargando y ejecutando modulos...

set "API_KEY="
set "API_URL="

call :cargar_config

if not defined API_KEY (
    echo [ERROR] No se encontro la API KEY.
    echo         Definila con la variable de entorno AUDIT_API_KEY, o crea
    echo         %USERPROFILE%\.audit_config con una linea API_KEY=tu-api-key
    pause
    exit /b 1
)
if not defined API_URL (
    echo [ERROR] No se encontro la URL del backend.
    echo         Definila con la variable de entorno AUDIT_API_URL, o agrega
    echo         una linea API_URL=https://tu-backend.tld a %USERPROFILE%\.audit_config
    pause
    exit /b 1
)

set "TMP_SISTEMA=%TEMP%\auditoria_sistema_%RANDOM%.bat"
set "TMP_RED=%TEMP%\auditoria_red_%RANDOM%.bat"
set "TMP_LOGS=%TEMP%\auditoria_logs_%RANDOM%.bat"

echo [1/5] Descargando modulos desde %API_URL%...
curl -s -f -o "%TMP_SISTEMA%" "%API_URL%/scripts/auditoria_sistema.bat"
curl -s -f -o "%TMP_RED%" "%API_URL%/scripts/auditoria_red.bat"
curl -s -f -o "%TMP_LOGS%" "%API_URL%/scripts/auditoria_logs.bat"

if not exist "%TMP_SISTEMA%" (
    echo [ERROR] No se pudo descargar auditoria_sistema.bat. Revisa conectividad.
    call :limpiar_temporales
    pause
    exit /b 1
)

echo [2/5] Ejecutando modulo de SISTEMA...
call "%TMP_SISTEMA%" /silent

echo [3/5] Ejecutando modulo de RED...
call "%TMP_RED%" /silent

echo [4/5] Ejecutando modulo de LOGS...
call "%TMP_LOGS%" /silent

echo [5/5] Subiendo reportes al backend...
set "REP_SISTEMA=%USERPROFILE%\Desktop\Reporte_Sistema_CMD.txt"
set "REP_RED=%USERPROFILE%\Desktop\Reporte_Red_CMD.txt"
set "REP_LOGS=%USERPROFILE%\Desktop\Reporte_Logs_CMD.txt"

if not exist "%REP_SISTEMA%" echo [AVISO] No se encontro %REP_SISTEMA%
if not exist "%REP_RED%" echo [AVISO] No se encontro %REP_RED%
if not exist "%REP_LOGS%" echo [AVISO] No se encontro %REP_LOGS%

curl -s -o "%TEMP%\audit_upload_response.txt" -w "HTTP %%{http_code}\n" ^
    -H "X-API-Key: %API_KEY%" ^
    -F "equipo=%COMPUTERNAME%" ^
    -F "reporte_sistema=<%REP_SISTEMA%" ^
    -F "reporte_red=<%REP_RED%" ^
    -F "reporte_logs=<%REP_LOGS%" ^
    "%API_URL%/api/reportes"

type "%TEMP%\audit_upload_response.txt"
del "%TEMP%\audit_upload_response.txt" >nul 2>&1

call :limpiar_temporales

echo.
echo Listo. Reportes generados en el Escritorio y enviados a %API_URL%
echo.
if /i not "%1"=="/silent" pause
exit /b 0
