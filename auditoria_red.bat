@echo off
:: =============================================================================
::  AUDITORIA 2/3 - RED, PUERTOS Y CONECTIVIDAD
::  Solo CMD - Sin PowerShell | Ejecutar como Administrador
::  Salida: %USERPROFILE%\Desktop\Reporte_Red_CMD.txt
:: =============================================================================
setlocal EnableDelayedExpansion
title Auditoria Red [2/3]

set "REPORTE=%USERPROFILE%\Desktop\Reporte_Red_CMD.txt"
set "FECHA=%DATE% %TIME%"
set "SUBNET_BASE="
set "LOCAL_IP="

call :verificar_admin
echo [2/3] Generando reporte de RED...
echo Destino: %REPORTE%
echo.

(
echo =========================================
echo     AUDITORIA RED ^(2 de 3^) - CMD
echo =========================================
echo Fecha: %FECHA%
echo Equipo: %COMPUTERNAME%
echo Usuario: %USERNAME%
echo.
) > "%REPORTE%"

call :detectar_subred

call :seccion "[+] CONFIGURACION DE RED"
ipconfig /all >> "%REPORTE%"

call :seccion "[+] TABLA DE RUTAS"
route print >> "%REPORTE%"

call :seccion "[+] INTERFACES DE RED"
netsh interface show interface >> "%REPORTE%" 2>&1
netsh interface ipv4 show config >> "%REPORTE%" 2>&1
netsh interface ipv4 show addresses >> "%REPORTE%" 2>&1

call :seccion "[+] ADAPTADORES DE RED"
wmic nic where "NetEnabled=True" get name,macaddress,speed,adaptertype >> "%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION IP POR ADAPTADOR"
wmic nicconfig where "IPEnabled=True" get description,ipaddress,ipsubnet,defaultipgateway,dnsserversearchorder >> "%REPORTE%" 2>&1

call :seccion "[+] PUERTOS EN ESCUCHA"
netstat -nab 2>nul | findstr /i "LISTENING" >> "%REPORTE%"

call :seccion "[+] PUERTOS Y PROCESOS ASOCIADOS"
netstat -anb 2>nul | findstr /i "LISTENING UDP" >> "%REPORTE%"

call :seccion "[+] TOTAL DE CONEXIONES ESTABLECIDAS"
for /f %%C in ('netstat -nab 2^>nul ^| findstr /i "ESTABLISHED" ^| find /c /v ""') do echo %%C >> "%REPORTE%"

call :seccion "[+] CONEXIONES ESTABLECIDAS"
netstat -nab 2>nul | findstr /i "ESTABLISHED" | sort >> "%REPORTE%"

call :seccion "[+] CONEXIONES ESTABLECIDAS CON PID"
netstat -ano 2>nul | findstr /i "ESTABLISHED" | sort >> "%REPORTE%"

call :seccion "[+] PROCESOS DE RED ACTIVOS"
tasklist /v >> "%REPORTE%" 2>&1

call :seccion "[+] DIRECCIONES REMOTAS CONECTADAS"
netstat -n 2>nul | findstr /i "ESTABLISHED" >> "%REPORTE%"

call :seccion "[+] RESUMEN DE PUERTOS (netstat -ano)"
netstat -ano | findstr /i "LISTENING ESTABLISHED" >> "%REPORTE%"

call :seccion "[+] TABLA ARP Y VECINOS DE RED"
arp -a >> "%REPORTE%"
netsh interface ipv4 show neighbors >> "%REPORTE%" 2>&1

call :seccion "[+] NOMBRES NETBIOS LOCALES"
nbtstat -n >> "%REPORTE%" 2>&1
nbtstat -c >> "%REPORTE%" 2>&1

call :seccion "[+] CONECTIVIDAD AL GATEWAY"
for /f "tokens=2 delims=:" %%G in ('ipconfig ^| findstr /i /c:"Puerta de enlace" /c:"Default Gateway"') do (
    set "GW=%%G"
    set "GW=!GW: =!"
    if not "!GW!"=="" (
        echo Gateway: !GW! >> "%REPORTE%"
        ping -n 3 !GW! >> "%REPORTE%"
        echo Ruta al gateway: >> "%REPORTE%"
        tracert -d -h 10 !GW! >> "%REPORTE%" 2>&1
    )
)

:: --- OPCIONAL: inventario de hosts en subred (descomentar si se necesita) ---
:: Puede ser detectado por antivirus. Habilitar solo con exclusion en Kaspersky.
:: call :seccion "[+] INVENTARIO DE HOSTS EN SUBRED LOCAL"
:: if defined SUBNET_BASE (
::     echo IP local: !LOCAL_IP!  Subred: !SUBNET_BASE!.0/24 >> "%REPORTE%"
::     set "HOSTS_VIVOS=0"
::     for /L %%i in (1,1,254) do (
::         ping -n 1 -w 200 !SUBNET_BASE!.%%i >nul 2>&1
::         if !errorlevel! equ 0 (
::             echo   Responde: !SUBNET_BASE!.%%i >> "%REPORTE%"
::             set /a HOSTS_VIVOS+=1
::         )
::     )
::     echo Total: !HOSTS_VIVOS! hosts >> "%REPORTE%"
::     arp -a >> "%REPORTE%"
:: ) else (
::     echo No se detecto subred local. >> "%REPORTE%"
:: )

:: --- OPCIONAL: consulta NetBIOS por vecino ARP (descomentar si se necesita) ---
:: call :seccion "[+] NOMBRES NETBIOS DE VECINOS CONOCIDOS"
:: for /f "tokens=1" %%A in ('arp -a ^| findstr /r "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"') do (
::     echo --- %%A --- >> "%REPORTE%"
::     nbtstat -A %%A >> "%REPORTE%" 2>&1
:: )

call :seccion "[+] CACHE DNS LOCAL"
ipconfig /displaydns >> "%REPORTE%"

call :seccion "[+] RESOLUCION DNS DEL DOMINIO"
for /f "tokens=2 delims=:" %%D in ('systeminfo ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" (
        echo Dominio: !DOM! >> "%REPORTE%"
        nslookup !DOM! >> "%REPORTE%" 2>&1
    )
)

call :seccion "[+] RESUMEN DE INDICADORES DE RED"
if defined LOCAL_IP echo IP local: !LOCAL_IP! >> "%REPORTE%"
if defined SUBNET_BASE echo Subred detectada: !SUBNET_BASE!.0/24 >> "%REPORTE%"
for /f %%C in ('netstat -ano 2^>nul ^| findstr /i "LISTENING" ^| find /c /v ""') do echo Puertos en escucha: %%C lineas >> "%REPORTE%"

(
echo.
echo =========================================
echo      FIN REPORTE RED (2/3)
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
goto :eof
:parse_ip
for /f "tokens=1-3 delims=." %%a in ("!LOCAL_IP!") do set "SUBNET_BASE=%%a.%%b.%%c"
goto :eof
