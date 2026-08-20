@echo off
setlocal EnableDelayedExpansion
goto :inicio

:: =============================================================================
::  ejecutar_auditoria.bat
::  Descarga los 3 modulos de auditoria desde el propio backend (ruta publica
::  /scripts, sin auth), los ejecuta, y sube los 3 reportes resultantes al
::  backend central via API KEY.
::
::  Compatible con equipos que tengan curl.exe o solo PowerShell/certutil.
::
::  Configuracion (una sola vez por equipo), por cualquiera de estas 2 vias:
::   1) Variables de entorno: AUDIT_API_KEY y AUDIT_API_URL
::   2) Archivo local NO versionado: %TEMP%\.audit_config con lineas:
::        API_KEY=tu-api-key
::        API_URL=https://tu-backend.tld
::
::  Los reportes se escriben en %TEMP% (compatible con SYSTEM).
::  La API KEY NUNCA debe escribirse en este archivo: solo se usa para el
::  POST final de subida de reportes, no para descargar los modulos.
:: =============================================================================

:pausa_si_aplica
if /i not "%MODO_SILENCIOSO%"=="1" pause
exit /b

:cargar_config
if defined AUDIT_API_KEY set "API_KEY=%AUDIT_API_KEY%"
if defined AUDIT_API_URL set "API_URL=%AUDIT_API_URL%"

if not defined API_KEY if exist "%TEMP%\.audit_config" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%TEMP%\.audit_config") do (
        if /i "%%A"=="API_KEY" set "API_KEY=%%B"
        if /i "%%A"=="API_URL" set "API_URL=%%B"
    )
)
exit /b

:limpiar_temporales
del "%TMP_SISTEMA%" >nul 2>&1
del "%TMP_RED%" >nul 2>&1
del "%TMP_LOGS%" >nul 2>&1
del "%UPLOAD_RESP%" >nul 2>&1
exit /b

:limpiar_reportes
del "%REP_SISTEMA%" >nul 2>&1
del "%REP_RED%" >nul 2>&1
del "%REP_LOGS%" >nul 2>&1
del "%REP_LOG_SISTEMA%" >nul 2>&1
exit /b

:descargar_archivo
set "DL_URL=%~1"
set "DL_DEST=%~2"
if exist "%DL_DEST%" del "%DL_DEST%" >nul 2>&1

where curl.exe >nul 2>&1
if !errorlevel! equ 0 (
    curl -s -f --ssl-no-revoke -o "%DL_DEST%" "%DL_URL%"
    if !errorlevel! equ 0 if exist "%DL_DEST%" exit /b 0
)

powershell.exe -NoProfile -Command "[Net.ServicePointManager]::CheckCertificateRevocationList=$false; [Net.ServicePointManager]::SecurityProtocol=[Enum]::ToObject([Net.SecurityProtocolType],3072); (New-Object Net.WebClient).DownloadFile('%DL_URL%','%DL_DEST%')" >nul 2>&1
if exist "%DL_DEST%" exit /b 0

certutil -urlcache -split -f "%DL_URL%" "%DL_DEST%" >nul 2>&1
if exist "%DL_DEST%" exit /b 0

bitsadmin /transfer auditget%RANDOM% /download /priority high "%DL_URL%" "%DL_DEST%" >nul 2>&1
if exist "%DL_DEST%" exit /b 0

exit /b 1

:subir_reportes
set "UPLOAD_RESP=%TEMP%\audit_upload_response.txt"
set "UPLOAD_CODE=000"
del "%UPLOAD_RESP%" >nul 2>&1

set "POST_URL=%API_URL%"
if "%POST_URL:~-1%"=="/" set "POST_URL=%POST_URL:~0,-1%"
set "POST_URL=%POST_URL%/api/reportes"
echo     Destino: %POST_URL%

set "FORM_SISTEMA="
set "FORM_RED="
set "FORM_LOGS="
if exist "%REP_SISTEMA%" set "FORM_SISTEMA=--data-urlencode reporte_sistema@%REP_SISTEMA%"
if exist "%REP_RED%" set "FORM_RED=--data-urlencode reporte_red@%REP_RED%"
if exist "%REP_LOGS%" set "FORM_LOGS=--data-urlencode reporte_logs@%REP_LOGS%"

where curl.exe >nul 2>&1
if !errorlevel! neq 0 goto :subir_powershell
for /f "delims=" %%C in ('curl.exe -sS --ssl-no-revoke -o "%UPLOAD_RESP%" -w "%%{http_code}" -X POST "%POST_URL%" -H "X-API-Key: %API_KEY%" --data-urlencode "equipo=%COMPUTERNAME%" !FORM_SISTEMA! !FORM_RED! !FORM_LOGS! 2^>nul') do set "UPLOAD_CODE=%%C"
if not "!UPLOAD_CODE!"=="000" if not "!UPLOAD_CODE!"=="" goto :subir_mostrar
echo     curl no pudo completar TLS; reintentando con PowerShell...

:subir_powershell
set "AUDIT_POST_URL=%POST_URL%"
set "AUDIT_POST_RESP=%UPLOAD_RESP%"
powershell.exe -NoProfile -Command "trap { [IO.File]::WriteAllText($env:AUDIT_POST_RESP, $_.Exception.Message); exit 1 }; [Net.ServicePointManager]::CheckCertificateRevocationList=$false; [Net.ServicePointManager]::SecurityProtocol=[Enum]::ToObject([Net.SecurityProtocolType],3072); $c=New-Object Net.WebClient; $c.Headers.Add('X-API-Key',$env:API_KEY); $f=New-Object System.Collections.Specialized.NameValueCollection; $f['equipo']=$env:COMPUTERNAME; if (Test-Path $env:REP_SISTEMA) { $f['reporte_sistema']=[IO.File]::ReadAllText($env:REP_SISTEMA,[Text.Encoding]::Default) }; if (Test-Path $env:REP_RED) { $f['reporte_red']=[IO.File]::ReadAllText($env:REP_RED,[Text.Encoding]::Default) }; if (Test-Path $env:REP_LOGS) { $f['reporte_logs']=[IO.File]::ReadAllText($env:REP_LOGS,[Text.Encoding]::Default) }; $b=$c.UploadValues($env:AUDIT_POST_URL,'POST',$f); [IO.File]::WriteAllText($env:AUDIT_POST_RESP,[Text.Encoding]::UTF8.GetString($b))"
if !errorlevel! equ 0 (set "UPLOAD_CODE=201") else (set "UPLOAD_CODE=000")

:subir_mostrar
echo     HTTP !UPLOAD_CODE!
if exist "%UPLOAD_RESP%" type "%UPLOAD_RESP%"
echo.
if "!UPLOAD_CODE!"=="201" exit /b 0
exit /b 1

:inicio
title Auditoria Completa - Descargando y ejecutando modulos...

set "MODO_SILENCIOSO=0"
if /i "%~1"=="/silent" set "MODO_SILENCIOSO=1"

set "API_KEY="
set "API_URL="
set "UPLOAD_RESP="

call :cargar_config

if not defined API_KEY (
    echo [ERROR] No se encontro la API KEY.
    echo         Definila con la variable de entorno AUDIT_API_KEY, o crea
    echo         %TEMP%\.audit_config con una linea API_KEY=tu-api-key
    call :pausa_si_aplica
    exit /b 1
)
if not defined API_URL (
    echo [ERROR] No se encontro la URL del backend.
    echo         Definila con la variable de entorno AUDIT_API_URL, o agrega
    echo         una linea API_URL=https://tu-backend.tld a %TEMP%\.audit_config
    call :pausa_si_aplica
    exit /b 1
)

set "TMP_SISTEMA=%TEMP%\auditoria_sistema_%RANDOM%.bat"
set "TMP_RED=%TEMP%\auditoria_red_%RANDOM%.bat"
set "TMP_LOGS=%TEMP%\auditoria_logs_%RANDOM%.bat"
set "REP_SISTEMA=%TEMP%\Reporte_Sistema_CMD.txt"
set "REP_RED=%TEMP%\Reporte_Red_CMD.txt"
set "REP_LOGS=%TEMP%\Reporte_Logs_CMD.txt"
set "REP_LOG_SISTEMA=%TEMP%\Auditoria_Sistema_LOG.txt"

echo [1/5] Descargando modulos desde %API_URL%...
call :descargar_archivo "%API_URL%/scripts/auditoria_sistema.bat" "%TMP_SISTEMA%"
if errorlevel 1 (
    echo [ERROR] No se pudo descargar auditoria_sistema.bat. Revisa conectividad.
    call :limpiar_temporales
    call :pausa_si_aplica
    exit /b 1
)

call :descargar_archivo "%API_URL%/scripts/auditoria_red.bat" "%TMP_RED%"
if errorlevel 1 (
    echo [ERROR] No se pudo descargar auditoria_red.bat. Revisa conectividad.
    call :limpiar_temporales
    call :pausa_si_aplica
    exit /b 1
)

call :descargar_archivo "%API_URL%/scripts/auditoria_logs.bat" "%TMP_LOGS%"
if errorlevel 1 (
    echo [ERROR] No se pudo descargar auditoria_logs.bat. Revisa conectividad.
    call :limpiar_temporales
    call :pausa_si_aplica
    exit /b 1
)

echo [2/5] Ejecutando modulo de SISTEMA...
call "%TMP_SISTEMA%" /silent

echo [3/5] Ejecutando modulo de RED...
call "%TMP_RED%" /silent

echo [4/5] Ejecutando modulo de LOGS...
call "%TMP_LOGS%" /silent

echo [5/5] Subiendo reportes al backend...

if not exist "%REP_SISTEMA%" echo [AVISO] No se encontro %REP_SISTEMA%
if not exist "%REP_RED%" echo [AVISO] No se encontro %REP_RED%
if not exist "%REP_LOGS%" echo [AVISO] No se encontro %REP_LOGS%

call :subir_reportes
if errorlevel 1 (
    echo.
    echo [ERROR] La subida al backend fallo. Los .txt se conservan en %TEMP% para revision manual.
    echo.
    call :limpiar_temporales
    call :pausa_si_aplica
    exit /b 1
)

call :limpiar_temporales
call :limpiar_reportes

echo.
echo Listo. Reportes enviados a %API_URL% y archivos .txt eliminados de %TEMP%.
echo.
call :pausa_si_aplica
exit /b 0
