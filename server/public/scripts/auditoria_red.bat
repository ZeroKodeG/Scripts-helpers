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

:puerto_conocido
set "PTO=%~1"
set "ROL=%~2"
>>"%REPORTE%" echo ----- Puerto %PTO% (%ROL%) -----
set "HIT="
for /f "tokens=1,2,3,4,5" %%A in ('netstat -ano 2^>nul ^| findstr /c:":%PTO% "') do (
    if /i "%%D"=="LISTENING" (
        set "HIT=1"
        >>"%REPORTE%" echo %%A  %%B  %%C  LISTENING  PID=%%E
        if not "%%E"=="" tasklist /fi "PID eq %%E" /fo list >>"%REPORTE%" 2>&1
    )
    if /i "%%A"=="UDP" (
        set "HIT=1"
        >>"%REPORTE%" echo %%A  %%B  %%C  PID=%%D
        if not "%%D"=="" tasklist /fi "PID eq %%D" /fo list >>"%REPORTE%" 2>&1
    )
)
if not defined HIT >>"%REPORTE%" echo (no hay LISTENING ni UDP en puerto %PTO%)
>>"%REPORTE%" echo.
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
set "REPORTE_FINAL=%TEMP%\Reporte_Red_CMD.txt"
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
>>"%REPORTE%" echo Version script: 2026-08-20a
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

call :seccion "[+] SERVICIOS POR PUERTO CONOCIDO"
>>"%REPORTE%" echo 0.0.0.0 y [::] = escucha en todas las interfaces (expuesto a la red).
>>"%REPORTE%" echo 127.0.0.1 y [::1] = solo local. Una IP LAN = exposicion interna.
>>"%REPORTE%" echo Cruzar PID con tasklist de esta seccion y con procesos de aplicativo del modulo sistema.
call :puerto_conocido 21 "FTP"
call :puerto_conocido 22 "SSH"
call :puerto_conocido 23 "Telnet"
call :puerto_conocido 25 "SMTP"
call :puerto_conocido 53 "DNS"
call :puerto_conocido 80 "HTTP"
call :puerto_conocido 110 "POP3"
call :puerto_conocido 135 "RPC"
call :puerto_conocido 139 "NetBIOS"
call :puerto_conocido 143 "IMAP"
call :puerto_conocido 389 "LDAP"
call :puerto_conocido 443 "HTTPS"
call :puerto_conocido 445 "SMB"
call :puerto_conocido 465 "SMTPS"
call :puerto_conocido 587 "Submission"
call :puerto_conocido 636 "LDAPS"
call :puerto_conocido 993 "IMAPS"
call :puerto_conocido 1433 "MSSQL"
call :puerto_conocido 1434 "MSSQL Browser"
call :puerto_conocido 1521 "Oracle"
call :puerto_conocido 3306 "MySQL MariaDB"
call :puerto_conocido 3389 "RDP"
call :puerto_conocido 5432 "PostgreSQL"
call :puerto_conocido 5672 "AMQP RabbitMQ"
call :puerto_conocido 5900 "VNC"
call :puerto_conocido 5985 "WinRM HTTP"
call :puerto_conocido 5986 "WinRM HTTPS"
call :puerto_conocido 6379 "Redis"
call :puerto_conocido 8080 "HTTP alt"
call :puerto_conocido 8443 "HTTPS alt"
call :puerto_conocido 9200 "Elasticsearch"
call :puerto_conocido 27017 "MongoDB"

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
