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

:detectar_subred
for /f "tokens=* delims=:" %%a in ('ipconfig ^| findstr /i /c:"IPv4"') do (
    set "IPLINE=%%a"
    set "IPLINE=!IPLINE: =!"
    if not "!IPLINE!"=="" if not "!IPLINE!"=="..." (
        set "LOCAL_IP=!IPLINE!"
        goto :parse_ip
    )
)
for /f "skip=1 tokens=1" %%i in ('wmic nicconfig where "IPEnabled=True" get IPAddress 2^>nul') do (
    set "RAW=%%i"
    set "RAW=!RAW:{=!"
    set "RAW=!RAW:}=!"
    set "RAW=!RAW:,= !"
    for %%j in (!RAW!) do (
        echo %%j | findstr /r "^[0-9][0-9]*\.[0-9]" >nul
        if !errorlevel! equ 0 (
            set "LOCAL_IP=%%j"
            goto :parse_ip
        )
    )
)
exit /b
:parse_ip
for /f "tokens=1-3 delims=." %%a in ("!LOCAL_IP!") do set "SUBNET_BASE=%%a.%%b.%%c"
exit /b

:inicio
title Auditoria Red [2/3]

set "REPORTE=%TEMP%\AuditRed_%COMPUTERNAME%_%RANDOM%.txt"
set "REPORTE_FINAL=%USERPROFILE%\Desktop\Reporte_Red_CMD.txt"
set "FECHA=%DATE% %TIME%"
set "SUBNET_BASE="
set "LOCAL_IP="

call :verificar_admin
echo [2/3] Generando reporte de RED...

>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo     AUDITORIA RED (2 de 3) - CMD
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo Fecha: %FECHA%
>>"%REPORTE%" echo Equipo: %COMPUTERNAME%
>>"%REPORTE%" echo Usuario: %USERNAME%
>>"%REPORTE%" echo.

call :detectar_subred

call :seccion "[+] CONFIGURACION DE RED"
ipconfig /all >>"%REPORTE%" 2>&1

call :seccion "[+] TABLA DE RUTAS"
route print >>"%REPORTE%" 2>&1

call :seccion "[+] INTERFACES DE RED"
netsh interface show interface >>"%REPORTE%" 2>&1
netsh interface ipv4 show config >>"%REPORTE%" 2>&1
netsh interface ipv4 show addresses >>"%REPORTE%" 2>&1

call :seccion "[+] ADAPTADORES DE RED"
wmic nic where "NetEnabled=True" get name,macaddress,speed,adaptertype >>"%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION IP POR ADAPTADOR"
wmic nicconfig where "IPEnabled=True" get description,ipaddress,ipsubnet,defaultipgateway,dnsserversearchorder >>"%REPORTE%" 2>&1

call :seccion "[+] PUERTOS EN ESCUCHA"
netstat -nab 2>nul | findstr /i "LISTENING" >>"%REPORTE%" 2>&1

call :seccion "[+] PUERTOS Y PROCESOS ASOCIADOS"
netstat -anb 2>nul | findstr /i "LISTENING UDP" >>"%REPORTE%" 2>&1

call :seccion "[+] TOTAL DE CONEXIONES ESTABLECIDAS"
for /f %%C in ('netstat -nab 2^>nul ^| findstr /i "ESTABLISHED" ^| find /c /v ""') do >>"%REPORTE%" echo %%C

call :seccion "[+] CONEXIONES ESTABLECIDAS"
netstat -nab 2>nul | findstr /i "ESTABLISHED" | sort >>"%REPORTE%" 2>&1

call :seccion "[+] CONEXIONES ESTABLECIDAS CON PID"
netstat -ano 2>nul | findstr /i "ESTABLISHED" | sort >>"%REPORTE%" 2>&1

call :seccion "[+] PROCESOS DE RED ACTIVOS"
tasklist /v >>"%REPORTE%" 2>&1

call :seccion "[+] DIRECCIONES REMOTAS CONECTADAS"
netstat -n 2>nul | findstr /i "ESTABLISHED" >>"%REPORTE%" 2>&1

call :seccion "[+] RESUMEN DE PUERTOS - netstat ano"
netstat -ano 2>nul | findstr /i "LISTENING ESTABLISHED" >>"%REPORTE%" 2>&1

call :seccion "[+] TABLA ARP Y VECINOS DE RED"
arp -a >>"%REPORTE%" 2>&1
netsh interface ipv4 show neighbors >>"%REPORTE%" 2>&1

call :seccion "[+] NOMBRES NETBIOS LOCALES"
nbtstat -n >>"%REPORTE%" 2>&1
nbtstat -c >>"%REPORTE%" 2>&1

call :seccion "[+] CONECTIVIDAD AL GATEWAY"
set "GATEWAY_PROBADO="
for /f "tokens=1,* delims=:" %%A in ('ipconfig ^| findstr /i /c:"Puerta de enlace" /c:"Default Gateway"') do (
    set "GW=%%B"
    set "GW=!GW: =!"
    if not "!GW!"=="" if not defined GATEWAY_PROBADO (
        echo !GW! | findstr /r "^[0-9][0-9]*\.[0-9]" >nul
        if !errorlevel! equ 0 (
            set "GATEWAY_PROBADO=1"
            >>"%REPORTE%" echo Gateway: !GW!
            ping -n 2 -w 1000 !GW! >>"%REPORTE%" 2>&1
            >>"%REPORTE%" echo Ruta al gateway:
            tracert -d -w 750 -h 5 !GW! >>"%REPORTE%" 2>&1
        )
    )
)
if not defined GATEWAY_PROBADO >>"%REPORTE%" echo No se detecto un gateway IPv4 util para la prueba.

call :seccion "[+] CACHE DNS LOCAL"
ipconfig /displaydns >>"%REPORTE%" 2>&1

call :seccion "[+] RESOLUCION DNS DEL DOMINIO"
for /f "tokens=2 delims=:" %%D in ('systeminfo 2^>nul ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" (
        >>"%REPORTE%" echo Dominio: !DOM!
        nslookup !DOM! >>"%REPORTE%" 2>&1
    )
)

call :seccion "[+] RESUMEN DE INDICADORES DE RED"
if defined LOCAL_IP >>"%REPORTE%" echo IP local: !LOCAL_IP!
if defined SUBNET_BASE >>"%REPORTE%" echo Subred detectada: !SUBNET_BASE!.0/24
for /f %%C in ('netstat -ano 2^>nul ^| findstr /i "LISTENING" ^| find /c /v ""') do >>"%REPORTE%" echo Puertos en escucha: %%C lineas

>>"%REPORTE%" echo.
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo      FIN REPORTE RED (2/3)
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
