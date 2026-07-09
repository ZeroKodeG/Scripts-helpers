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
::   1) Variables de entorno de sistema: AUDIT_API_KEY y AUDIT_API_URL
::   2) Archivo local NO versionado: %USERPROFILE%\.audit_config con lineas:
::        API_KEY=tu-api-key
::        API_URL=https://tu-backend.tld
::
::  La API KEY NUNCA debe escribirse en este archivo: solo se usa para el
::  POST final de subida de reportes, no para descargar los modulos.
:: =============================================================================

:cargar_config
if defined AUDIT_API_KEY set "API_KEY=%AUDIT_API_KEY%"
if defined AUDIT_API_URL set "API_URL=%AUDIT_API_URL%"

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
del "%UPLOAD_SCRIPT%" >nul 2>&1
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

where /q curl.exe
if !errorlevel! equ 0 (
    curl -s -f -o "%DL_DEST%" "%DL_URL%"
    if !errorlevel! equ 0 if exist "%DL_DEST%" exit /b 0
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
    "$wc = New-Object Net.WebClient;" ^
    "$wc.DownloadFile('%DL_URL%', '%DL_DEST%')" >nul 2>&1
if exist "%DL_DEST%" exit /b 0

certutil -urlcache -split -f "%DL_URL%" "%DL_DEST%" >nul 2>&1
if exist "%DL_DEST%" exit /b 0

exit /b 1

:subir_reportes
set "UPLOAD_SCRIPT=%TEMP%\audit_upload_%RANDOM%.ps1"
set "UPLOAD_RESP=%TEMP%\audit_upload_response.txt"
del "%UPLOAD_SCRIPT%" >nul 2>&1
del "%UPLOAD_RESP%" >nul 2>&1

>"%UPLOAD_SCRIPT%" echo(param(
>>"%UPLOAD_SCRIPT%" echo(    [string]$ApiUrl,
>>"%UPLOAD_SCRIPT%" echo(    [string]$ApiKey,
>>"%UPLOAD_SCRIPT%" echo(    [string]$Equipo,
>>"%UPLOAD_SCRIPT%" echo(    [string]$RepSistema,
>>"%UPLOAD_SCRIPT%" echo(    [string]$RepRed,
>>"%UPLOAD_SCRIPT%" echo(    [string]$RepLogs,
>>"%UPLOAD_SCRIPT%" echo(    [string]$ResponsePath
>>"%UPLOAD_SCRIPT%" echo(^))
>>"%UPLOAD_SCRIPT%" echo([Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12)
>>"%UPLOAD_SCRIPT%" echo(Add-Type -AssemblyName System.Net.Http)
>>"%UPLOAD_SCRIPT%" echo(function Add-TextPart {
>>"%UPLOAD_SCRIPT%" echo(    param([System.Net.Http.MultipartFormDataContent]$Content, [string]$Name, [string]$Path)
>>"%UPLOAD_SCRIPT%" echo(    if (Test-Path $Path) {
>>"%UPLOAD_SCRIPT%" echo(        $Text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::Default)
>>"%UPLOAD_SCRIPT%" echo(        $Content.Add((New-Object System.Net.Http.StringContent($Text, [System.Text.Encoding]::UTF8^)), $Name)
>>"%UPLOAD_SCRIPT%" echo(    }
>>"%UPLOAD_SCRIPT%" echo(})
>>"%UPLOAD_SCRIPT%" echo(try {
>>"%UPLOAD_SCRIPT%" echo(    $Client = New-Object System.Net.Http.HttpClient
>>"%UPLOAD_SCRIPT%" echo(    $Client.DefaultRequestHeaders.Add('X-API-Key', $ApiKey)
>>"%UPLOAD_SCRIPT%" echo(    $Multipart = New-Object System.Net.Http.MultipartFormDataContent
>>"%UPLOAD_SCRIPT%" echo(    $Multipart.Add((New-Object System.Net.Http.StringContent($Equipo, [System.Text.Encoding]::UTF8^)), 'equipo')
>>"%UPLOAD_SCRIPT%" echo(    Add-TextPart $Multipart 'reporte_sistema' $RepSistema
>>"%UPLOAD_SCRIPT%" echo(    Add-TextPart $Multipart 'reporte_red' $RepRed
>>"%UPLOAD_SCRIPT%" echo(    Add-TextPart $Multipart 'reporte_logs' $RepLogs
>>"%UPLOAD_SCRIPT%" echo(    $Url = $ApiUrl.TrimEnd('/'^) + '/api/reportes'
>>"%UPLOAD_SCRIPT%" echo(    $Response = $Client.PostAsync($Url, $Multipart^).Result
>>"%UPLOAD_SCRIPT%" echo(    $Body = $Response.Content.ReadAsStringAsync(^).Result
>>"%UPLOAD_SCRIPT%" echo(    $Lines = @('HTTP ' + [int]$Response.StatusCode)
>>"%UPLOAD_SCRIPT%" echo(    if ($Body) { $Lines += $Body }
>>"%UPLOAD_SCRIPT%" echo(    [System.IO.File]::WriteAllLines($ResponsePath, $Lines)
>>"%UPLOAD_SCRIPT%" echo(    if ($Response.IsSuccessStatusCode) { exit 0 }
>>"%UPLOAD_SCRIPT%" echo(    exit 1
>>"%UPLOAD_SCRIPT%" echo(} catch {
>>"%UPLOAD_SCRIPT%" echo(    $Message = $_.Exception.Message
>>"%UPLOAD_SCRIPT%" echo(    if ($_.Exception.InnerException) {
>>"%UPLOAD_SCRIPT%" echo(        $Message = $Message + ' ^| ' + $_.Exception.InnerException.Message
>>"%UPLOAD_SCRIPT%" echo(    }
>>"%UPLOAD_SCRIPT%" echo(    [System.IO.File]::WriteAllLines($ResponsePath, @('[ERROR] ' + $Message))
>>"%UPLOAD_SCRIPT%" echo(    exit 1
>>"%UPLOAD_SCRIPT%" echo(})

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPLOAD_SCRIPT%" "%API_URL%" "%API_KEY%" "%COMPUTERNAME%" "%REP_SISTEMA%" "%REP_RED%" "%REP_LOGS%" "%UPLOAD_RESP%"
set "UPLOAD_EXIT=%errorlevel%"

if exist "%UPLOAD_RESP%" type "%UPLOAD_RESP%"

exit /b %UPLOAD_EXIT%

:inicio
title Auditoria Completa - Descargando y ejecutando modulos...

set "API_KEY="
set "API_URL="
set "UPLOAD_SCRIPT="
set "UPLOAD_RESP="

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
set "REP_SISTEMA=%USERPROFILE%\Desktop\Reporte_Sistema_CMD.txt"
set "REP_RED=%USERPROFILE%\Desktop\Reporte_Red_CMD.txt"
set "REP_LOGS=%USERPROFILE%\Desktop\Reporte_Logs_CMD.txt"
set "REP_LOG_SISTEMA=%USERPROFILE%\Desktop\Auditoria_Sistema_LOG.txt"

echo [1/5] Descargando modulos desde %API_URL%...
call :descargar_archivo "%API_URL%/scripts/auditoria_sistema.bat" "%TMP_SISTEMA%"
if errorlevel 1 (
    echo [ERROR] No se pudo descargar auditoria_sistema.bat. Revisa conectividad.
    call :limpiar_temporales
    pause
    exit /b 1
)

call :descargar_archivo "%API_URL%/scripts/auditoria_red.bat" "%TMP_RED%"
if errorlevel 1 (
    echo [ERROR] No se pudo descargar auditoria_red.bat. Revisa conectividad.
    call :limpiar_temporales
    pause
    exit /b 1
)

call :descargar_archivo "%API_URL%/scripts/auditoria_logs.bat" "%TMP_LOGS%"
if errorlevel 1 (
    echo [ERROR] No se pudo descargar auditoria_logs.bat. Revisa conectividad.
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

if not exist "%REP_SISTEMA%" echo [AVISO] No se encontro %REP_SISTEMA%
if not exist "%REP_RED%" echo [AVISO] No se encontro %REP_RED%
if not exist "%REP_LOGS%" echo [AVISO] No se encontro %REP_LOGS%

call :subir_reportes
if errorlevel 1 (
    echo.
    echo [ERROR] La subida al backend fallo. Los .txt se conservan en el Escritorio para revision manual.
    echo.
    call :limpiar_temporales
    if /i not "%1"=="/silent" pause
    exit /b 1
)

call :limpiar_temporales
call :limpiar_reportes

echo.
echo Listo. Reportes enviados a %API_URL% y archivos .txt eliminados del Escritorio.
echo.
if /i not "%1"=="/silent" pause
exit /b 0
