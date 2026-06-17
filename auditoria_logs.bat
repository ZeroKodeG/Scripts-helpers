@echo off
setlocal EnableDelayedExpansion
goto :inicio

:seccion
echo %~1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo %~1
>>"%REPORTE%" echo.
exit /b

:verificar_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [AVISO] Ejecutar como Administrador para datos completos.
    timeout /t 2 >nul
)
exit /b

:resumen_logs
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4625)]]" /c:50 /f:text 2^>nul ^| find /c "Event ID"') do (
    >>"%REPORTE%" echo Logons fallidos en muestra: %%C de 50
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=1102)]]" /c:10 /f:text 2^>nul ^| find /c "Event ID"') do (
    if %%C gtr 0 >>"%REPORTE%" echo [REVISAR] Eventos mantenimiento logs 1102: %%C
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4720)]]" /c:10 /f:text 2^>nul ^| find /c "Event ID"') do (
    if %%C gtr 0 >>"%REPORTE%" echo [REVISAR] Cuentas nuevas 4720: %%C
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4672)]]" /c:50 /f:text 2^>nul ^| find /c "Event ID"') do (
    >>"%REPORTE%" echo Eventos privilegios sesion 4672: %%C en muestra
)
exit /b

:inicio
title Auditoria Logs [3/3]

set "REPORTE=%TEMP%\AuditLogs_%COMPUTERNAME%_%RANDOM%.txt"
set "REPORTE_FINAL=%USERPROFILE%\Desktop\Reporte_Logs_CMD.txt"
set "FECHA=%DATE% %TIME%"

call :verificar_admin
echo [3/3] Generando reporte de LOGS...

>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo    AUDITORIA LOGS (3 de 3) - CMD
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo Fecha: %FECHA%
>>"%REPORTE%" echo Equipo: %COMPUTERNAME%
>>"%REPORTE%" echo Usuario: %USERNAME%
>>"%REPORTE%" echo.

call :seccion "[+] EVENTOS INICIO SESION FALLIDO - ID 4625"
wevtutil qe Security "/q:*[System[(EventID=4625)]]" /c:10 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS INICIO SESION EXITOSO - ID 4624"
wevtutil qe Security "/q:*[System[(EventID=4624)]]" /c:10 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS ACCESO REMOTO RDP - ID 4624 tipo 10"
wevtutil qe Security "/q:*[System[(EventID=4624)]] and EventData[Data[@Name='LogonType']='10']" /c:15 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS PRIVILEGIOS DE SESION - ID 4672"
wevtutil qe Security "/q:*[System[(EventID=4672)]]" /c:20 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS INSTALACION DE SERVICIO - ID 4697"
wevtutil qe Security "/q:*[System[(EventID=4697)]]" /c:15 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS CUENTAS Y GRUPOS - ID 4720 4732"
wevtutil qe Security "/q:*[System[(EventID=4720 or EventID=4732)]]" /c:15 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS AUTENTICACION ALTERNATIVA - ID 4648"
wevtutil qe Security "/q:*[System[(EventID=4648)]]" /c:10 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS KERBEROS NO EXITOSOS - ID 4771"
wevtutil qe Security "/q:*[System[(EventID=4771)]]" /c:15 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS CAMBIO EN AUDITORIA - ID 4719"
wevtutil qe Security "/q:*[System[(EventID=4719)]]" /c:5 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS MANTENIMIENTO DE LOGS - ID 1102"
wevtutil qe Security "/q:*[System[(EventID=1102)]]" /c:5 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS NUEVO SERVICIO SYSTEM - ID 7045"
wevtutil qe System "/q:*[System[(EventID=7045)]]" /c:15 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] EVENTOS APAGADO INESPERADO - ID 6008 y 41"
wevtutil qe System "/q:*[System[(EventID=6008)]]" /c:5 /f:text >>"%REPORTE%" 2>&1
wevtutil qe System "/q:*[System[(EventID=41)]]" /c:5 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] ERRORES LOG SYSTEM ultimas 24h"
wevtutil qe System "/q:*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 86400000]]]" /c:20 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] ERRORES LOG APPLICATION ultimas 24h"
wevtutil qe Application "/q:*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 86400000]]]" /c:20 /f:text >>"%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION DE LOGS - tamano y retencion"
wevtutil gl Security >>"%REPORTE%" 2>&1
wevtutil gl System >>"%REPORTE%" 2>&1
wevtutil gl Application >>"%REPORTE%" 2>&1

call :seccion "[+] RESUMEN DE INDICADORES DE LOGS"
call :resumen_logs

>>"%REPORTE%" echo.
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo     FIN REPORTE LOGS (3/3)
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo Generado: %FECHA%

copy /y "%REPORTE%" "%REPORTE_FINAL%" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Cierre Notepad si tiene abierto el reporte.
    echo Reporte en: %REPORTE%
) else (
    echo Listo: %REPORTE_FINAL%
    del "%REPORTE%" >nul 2>&1
)

if /i not "%1"=="/silent" pause
exit /b 0
