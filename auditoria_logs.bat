@echo off
:: =============================================================================
::  AUDITORIA 3/3 - EVENTOS Y LOGS DEL SISTEMA
::  Solo CMD - Sin PowerShell | Ejecutar como Administrador
::  Salida: %USERPROFILE%\Desktop\Reporte_Logs_CMD.txt
:: =============================================================================
setlocal EnableDelayedExpansion
title Auditoria Logs [3/3]

set "REPORTE=%USERPROFILE%\Desktop\Reporte_Logs_CMD.txt"
set "FECHA=%DATE% %TIME%"

call :verificar_admin
echo [3/3] Generando reporte de LOGS...
echo Destino: %REPORTE%
echo.

(
echo =========================================
echo    AUDITORIA LOGS ^(3 de 3^) - CMD
echo =========================================
echo Fecha: %FECHA%
echo Equipo: %COMPUTERNAME%
echo Usuario: %USERNAME%
echo.
) > "%REPORTE%"

call :seccion "[+] EVENTOS DE INICIO DE SESION FALLIDO (ID 4625)"
wevtutil qe Security "/q:*[System[(EventID=4625)]]" /c:10 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE INICIO DE SESION EXITOSO (ID 4624)"
wevtutil qe Security "/q:*[System[(EventID=4624)]]" /c:10 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE ACCESO REMOTO RDP (ID 4624 tipo 10)"
wevtutil qe Security "/q:*[System[(EventID=4624)]] and EventData[Data[@Name='LogonType']='10']" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE PRIVILEGIOS DE SESION (ID 4672)"
wevtutil qe Security "/q:*[System[(EventID=4672)]]" /c:20 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE INSTALACION DE SERVICIO (ID 4697)"
wevtutil qe Security "/q:*[System[(EventID=4697)]]" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE CUENTAS Y GRUPOS (ID 4720, 4732)"
wevtutil qe Security "/q:*[System[(EventID=4720 or EventID=4732)]]" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE AUTENTICACION ALTERNATIVA (ID 4648)"
wevtutil qe Security "/q:*[System[(EventID=4648)]]" /c:10 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS KERBEROS NO EXITOSOS (ID 4771)"
wevtutil qe Security "/q:*[System[(EventID=4771)]]" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE CAMBIO EN AUDITORIA (ID 4719)"
wevtutil qe Security "/q:*[System[(EventID=4719)]]" /c:5 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE MANTENIMIENTO DE LOGS (ID 1102)"
wevtutil qe Security "/q:*[System[(EventID=1102)]]" /c:5 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE NUEVO SERVICIO EN SYSTEM (ID 7045)"
wevtutil qe System "/q:*[System[(EventID=7045)]]" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] EVENTOS DE APAGADO INESPERADO (ID 6008, 41)"
wevtutil qe System "/q:*[System[(EventID=6008)]]" /c:5 /f:text >> "%REPORTE%" 2>&1
wevtutil qe System "/q:*[System[(EventID=41)]]" /c:5 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] ERRORES DEL LOG SYSTEM (ultimas 24h)"
wevtutil qe System "/q:*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 86400000]]]" /c:20 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] ERRORES DEL LOG APPLICATION (ultimas 24h)"
wevtutil qe Application "/q:*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 86400000]]]" /c:20 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION DE LOGS (tamano y retencion)"
wevtutil gl Security >> "%REPORTE%" 2>&1
wevtutil gl System >> "%REPORTE%" 2>&1
wevtutil gl Application >> "%REPORTE%" 2>&1

call :seccion "[+] RESUMEN DE INDICADORES DE LOGS"
call :resumen_logs

(
echo.
echo =========================================
echo     FIN REPORTE LOGS (3/3)
echo =========================================
echo Generado: %FECHA%
) >> "%REPORTE%"

echo Listo: %REPORTE%
if /i not "%1"=="/silent" pause
goto :eof

:verificar_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [AVISO] Ejecutar como Administrador para datos completos.
    timeout /t 2 >nul
)
goto :eof

:seccion
echo %~1
echo. >> "%REPORTE%"
echo %~1 >> "%REPORTE%"
echo. >> "%REPORTE%"
goto :eof

:resumen_logs
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4625)]]" /c:50 /f:text 2^>nul ^| find /c "Event ID"') do (
    echo Logons fallidos en muestra: %%C de 50 >> "%REPORTE%"
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=1102)]]" /c:10 /f:text 2^>nul ^| find /c "Event ID"') do (
    if %%C gtr 0 echo [REVISAR] Eventos de mantenimiento de logs (1102): %%C >> "%REPORTE%"
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4720)]]" /c:10 /f:text 2^>nul ^| find /c "Event ID"') do (
    if %%C gtr 0 echo [REVISAR] Cuentas nuevas detectadas (4720): %%C >> "%REPORTE%"
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4672)]]" /c:50 /f:text 2^>nul ^| find /c "Event ID"') do (
    echo Eventos de privilegios de sesion (4672): %%C en muestra >> "%REPORTE%"
)
goto :eof
