@echo off
:: =============================================================================
::  REPORTE DE AUDITORIA - Windows Server
::  Solo CMD + herramientas nativas (SIN PowerShell)
::  Ejecutar como Administrador para resultados completos
:: =============================================================================
setlocal EnableDelayedExpansion

title Auditoria CMD - Generando reporte...

:: --- Verificar privilegios de administrador ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [AVISO] No se detectaron privilegios de Administrador.
    echo         Algunas secciones mostraran "Can not obtain ownership information".
    echo.
    timeout /t 3 >nul
)

:: --- Archivo de salida ---
set "REPORTE=%USERPROFILE%\Desktop\Reporte_CMD.txt"
set "FECHA=%DATE% %TIME%"
set "SUBNET_BASE="
set "LOCAL_IP="

echo Generando reporte de auditoria... por favor espere.
echo Destino: %REPORTE%
echo.

:: =============================================================================
::  ENCABEZADO
:: =============================================================================
(
echo =========================================
echo        REPORTE DE AUDITORIA (CMD^)
echo        Sin PowerShell - solo herramientas nativas
echo =========================================
echo Fecha de generacion: %FECHA%
echo Equipo: %COMPUTERNAME%
echo Usuario: %USERNAME%
echo.
) > "%REPORTE%"

:: Detectar IP local y base de subred (/24) para escaneos
call :detectar_subred

:: =============================================================================
::  SISTEMA Y HARDWARE
:: =============================================================================
call :seccion "[+] SYSTEM INFO"
systeminfo >> "%REPORTE%"

call :seccion "[+] HARDWARE"
wmic computersystem get manufacturer,model,name,domain,totalphysicalmemory >> "%REPORTE%" 2>&1
wmic cpu get name,numberofcores,numberoflogicalprocessors >> "%REPORTE%" 2>&1
wmic diskdrive get deviceid,model,size,status >> "%REPORTE%" 2>&1
wmic memorychip get capacity,speed,manufacturer >> "%REPORTE%" 2>&1

:: =============================================================================
::  RED - CONFIGURACION
:: =============================================================================
call :seccion "[+] CONFIGURACION DE RED COMPLETA"
ipconfig /all >> "%REPORTE%"

call :seccion "[+] TABLA DE RUTAS"
route print >> "%REPORTE%"

call :seccion "[+] INTERFACES (NETSH)"
netsh interface show interface >> "%REPORTE%" 2>&1
netsh interface ipv4 show config >> "%REPORTE%" 2>&1
netsh interface ipv4 show addresses >> "%REPORTE%" 2>&1

:: =============================================================================
::  RED - PUERTOS Y CONEXIONES
:: =============================================================================
call :seccion "[+] RED Y PUERTOS EN ESCUCHA (LISTENING)"
netstat -nab 2>nul | findstr /i "LISTENING" >> "%REPORTE%"

call :seccion "[+] PUERTOS EN ESCUCHA CON NOMBRE DE PROCESO"
netstat -anb 2>nul | findstr /i "LISTENING UDP" >> "%REPORTE%"

call :seccion "[+] TOTAL CONEXIONES ESTABLECIDAS"
for /f %%C in ('netstat -nab 2^>nul ^| findstr /i "ESTABLISHED" ^| find /c /v ""') do echo %%C >> "%REPORTE%"

call :seccion "[+] CONEXIONES ESTABLECIDAS"
netstat -nab 2>nul | findstr /i "ESTABLISHED" | sort >> "%REPORTE%"

call :seccion "[+] CONEXIONES ESTABLECIDAS CON PID (netstat -ano)"
netstat -ano 2>nul | findstr /i "ESTABLISHED" | sort >> "%REPORTE%"

call :seccion "[+] PROCESOS ASOCIADOS A CONEXIONES (tasklist)"
tasklist /v >> "%REPORTE%" 2>&1

call :seccion "[+] PEERS EN CONEXIONES ACTIVAS"
netstat -n 2>nul | findstr /i "ESTABLISHED" >> "%REPORTE%"

:: =============================================================================
::  RED - ENTORNO / VLAN / VECINOS
:: =============================================================================
call :seccion "[+] VECINOS ARP (EQUIPOS EN LA VLAN RECIENTES)"
arp -a >> "%REPORTE%"
netsh interface ipv4 show neighbors >> "%REPORTE%" 2>&1

call :seccion "[+] NETBIOS LOCAL (nbtstat)"
nbtstat -n >> "%REPORTE%" 2>&1
nbtstat -c >> "%REPORTE%" 2>&1

call :seccion "[+] GATEWAY Y LATENCIA"
for /f "tokens=2 delims=:" %%G in ('ipconfig ^| findstr /i /c:"Puerta de enlace" /c:"Default Gateway"') do (
    set "GW=%%G"
    set "GW=!GW: =!"
    if not "!GW!"=="" (
        echo Gateway detectado: !GW! >> "%REPORTE%"
        ping -n 3 !GW! >> "%REPORTE%"
        echo. >> "%REPORTE%"
        echo Traceroute al gateway: >> "%REPORTE%"
        tracert -d -h 10 !GW! >> "%REPORTE%" 2>&1
    )
)

call :seccion "[+] ESCANEO SIMPLE DE SUBRED (ping /24)"
if defined SUBNET_BASE (
    echo IP local detectada: !LOCAL_IP! >> "%REPORTE%"
    echo Subred a escanear: !SUBNET_BASE!.1 - !SUBNET_BASE!.254 >> "%REPORTE%"
    echo Este paso puede tardar 2-4 minutos. >> "%REPORTE%"
    echo. >> "%REPORTE%"
    set "HOSTS_VIVOS=0"
    for /L %%i in (1,1,254) do (
        ping -n 1 -w 200 !SUBNET_BASE!.%%i >nul 2>&1
        if !errorlevel! equ 0 (
            echo   [ACTIVO] !SUBNET_BASE!.%%i >> "%REPORTE%"
            set /a HOSTS_VIVOS+=1
        )
    )
    echo. >> "%REPORTE%"
    echo Total hosts que respondieron ping: !HOSTS_VIVOS! >> "%REPORTE%"
) else (
    echo No se pudo detectar la subred local automaticamente. >> "%REPORTE%"
    echo Revise la seccion ipconfig /all para escanear manualmente. >> "%REPORTE%"
)

call :seccion "[+] ARP TRAS ESCANEO DE SUBRED"
arp -a >> "%REPORTE%"

call :seccion "[+] NETBIOS DE HOSTS EN ARP (nbtstat -A)"
if defined SUBNET_BASE (
    echo Consultando nombres NetBIOS de entradas ARP conocidas... >> "%REPORTE%"
    for /f "tokens=1" %%A in ('arp -a ^| findstr /r "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"') do (
        echo --- Host: %%A --- >> "%REPORTE%"
        nbtstat -A %%A >> "%REPORTE%" 2>&1
    )
) else (
    echo Omitido: subred no detectada. >> "%REPORTE%"
)

call :seccion "[+] CACHE DNS (HOSTS CONSULTADOS RECIENTEMENTE)"
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

:: =============================================================================
::  CUENTAS Y SEGURIDAD LOCAL
:: =============================================================================
call :seccion "[+] CUENTAS Y SEGURIDAD"
net user >> "%REPORTE%" 2>&1
echo. >> "%REPORTE%"
echo Members of Administrators Group: >> "%REPORTE%"
net localgroup Administrators >> "%REPORTE%" 2>&1

call :seccion "[+] SESIONES SMB ENTRANTES"
net session >> "%REPORTE%" 2>&1
net files >> "%REPORTE%" 2>&1

call :seccion "[+] SHARES EXPUESTOS"
net share >> "%REPORTE%" 2>&1

call :seccion "[+] FIREWALL WINDOWS (ESTADO)"
netsh advfirewall show allprofiles >> "%REPORTE%" 2>&1

call :seccion "[+] REGLAS DE FIREWALL ENTRANTES HABILITADAS (resumen)"
netsh advfirewall firewall show rule name=all dir=in action=allow enable=yes >> "%REPORTE%" 2>&1

:: =============================================================================
::  PARCHES Y ACTUALIZACIONES (sin PowerShell)
:: =============================================================================
call :seccion "[+] PARCHES Y SISTEMA (formato tabla)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:table >> "%REPORTE%" 2>&1

call :seccion "[+] PARCHES Y SISTEMA (formato lista)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:list >> "%REPORTE%" 2>&1

call :seccion "[+] PARCHES Y SISTEMA (formato CSV)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:csv >> "%REPORTE%" 2>&1

:: =============================================================================
::  SERVICIOS, PROCESOS Y TAREAS
:: =============================================================================
call :seccion "[+] SERVICIOS EN EJECUCION"
sc query type= service state= all | findstr /i "SERVICE_NAME DISPLAY_NAME STATE" >> "%REPORTE%"

call :seccion "[+] SERVICIOS DETALLADOS (WMIC)"
wmic service get name,displayname,state,startmode,pathname >> "%REPORTE%" 2>&1

call :seccion "[+] PROCESOS CON RUTA"
wmic process get name,processid,executablepath,commandline >> "%REPORTE%" 2>&1

call :seccion "[+] TAREAS PROGRAMADAS"
schtasks /query /fo TABLE >> "%REPORTE%" 2>&1

call :seccion "[+] PROGRAMAS DE INICIO AUTOMATICO (WMIC)"
wmic startup get caption,command,location,user >> "%REPORTE%" 2>&1

:: =============================================================================
::  LOGS DE SEGURIDAD
:: =============================================================================
call :seccion "[+] LOGS FALLIDOS RECIENTES (ID 4625 - Logon fallido)"
wevtutil qe Security "/q:*[System[(EventID=4625)]]" /c:10 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] DETECCION DE PRIVILEGIOS Y NUEVOS SERVICIOS (ID 4672, 4697)"
wevtutil qe Security "/q:*[System[(EventID=4672 or EventID=4697)]]" /c:20 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] MODIFICACIONES DE CUENTAS Y GRUPOS (ID 4720, 4732)"
wevtutil qe Security "/q:*[System[(EventID=4720 or EventID=4732)]]" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] ALERTA: INTENTOS DE BORRADO DE LOGS (ID 1102)"
wevtutil qe Security "/q:*[System[(EventID=1102)]]" /c:5 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] INICIOS DE SESION EXITOSOS RECIENTES (ID 4624)"
wevtutil qe Security "/q:*[System[(EventID=4624)]]" /c:10 /f:text >> "%REPORTE%" 2>&1

:: =============================================================================
::  DOMINIO Y ACTIVE DIRECTORY
:: =============================================================================
(
echo =========================================
echo       AUDITORIA DE RELACION CON DOMINIO
echo =========================================
) >> "%REPORTE%"

call :seccion "[+] Dominio y Servidor de Autenticacion"
systeminfo | findstr /B /C:"Domain" /C:"Logon Server" >> "%REPORTE%"

call :seccion "[+] Controlador de Dominio mas cercano (NLTEST)"
nltest /dsgetdc: >> "%REPORTE%" 2>&1

call :seccion "[+] Lista de Controladores de Dominio"
for /f "tokens=2 delims=:" %%D in ('systeminfo ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" nltest /dclist:!DOM! >> "%REPORTE%" 2>&1
)

call :seccion "[+] Latencia al Controlador de Dominio"
for /f "tokens=2 delims=:" %%S in ('systeminfo ^| findstr /i /b "Logon Server"') do (
    set "DC=%%S"
    set "DC=!DC:\\=!"
    set "DC=!DC: =!"
    if not "!DC!"=="" (
        echo DC: !DC! >> "%REPORTE%"
        ping -n 3 !DC! >> "%REPORTE%"
        echo. >> "%REPORTE%"
        echo Traceroute al DC: >> "%REPORTE%"
        tracert -d -h 15 !DC! >> "%REPORTE%" 2>&1
    )
)

call :seccion "[+] Equipos visibles en el dominio"
for /f "tokens=2 delims=:" %%D in ('systeminfo ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" net view /domain:!DOM! >> "%REPORTE%" 2>&1
)
net view >> "%REPORTE%" 2>&1

call :seccion "[+] Miembros de Domain Admins en la Red"
net group "Domain Admins" /domain >> "%REPORTE%" 2>&1

call :seccion "[+] Grupos y Usuarios con Poder de Administrador Local"
net localgroup Administrators >> "%REPORTE%" 2>&1

:: =============================================================================
::  INVENTARIO DE RED ADICIONAL (CMD puro)
:: =============================================================================
call :seccion "[+] ADAPTADORES DE RED (WMIC)"
wmic nic where "NetEnabled=True" get name,macaddress,speed,adaptertype >> "%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION IP POR ADAPTADOR (WMIC)"
wmic nicconfig where "IPEnabled=True" get description,ipaddress,ipsubnet,defaultipgateway,dnsserversearchorder >> "%REPORTE%" 2>&1

call :seccion "[+] LISTA DE PUERTOS ABIERTOS POR PROCESO (netstat resumen)"
netstat -ano | findstr /i "LISTENING ESTABLISHED" >> "%REPORTE%"

:: =============================================================================
::  PIE DE REPORTE
:: =============================================================================
(
echo.
echo =========================================
echo           FIN DEL REPORTE
echo =========================================
echo Generado: %FECHA%
echo Archivo: %REPORTE%
echo IP local: %LOCAL_IP%
echo Subred escaneada: %SUBNET_BASE%.0/24
) >> "%REPORTE%"

echo.
echo =========================================
echo  Reporte finalizado exitosamente.
echo  Ubicacion: %REPORTE%
echo =========================================
echo.
pause
goto :eof

:: =============================================================================
::  Subrutina: encabezado de seccion
:: =============================================================================
:seccion
echo %~1
echo. >> "%REPORTE%"
echo %~1 >> "%REPORTE%"
echo. >> "%REPORTE%"
goto :eof

:: =============================================================================
::  Subrutina: detectar IP local y base /24 (Espanol e Ingles)
:: =============================================================================
:detectar_subred
:: Metodo 1: ipconfig (IPv4)
for /f "tokens=* delims=:" %%a in ('ipconfig ^| findstr /i /c:"IPv4" /c:"ipv4"') do (
    set "IPLINE=%%a"
    set "IPLINE=!IPLINE: =!"
    if not "!IPLINE!"=="" if not "!IPLINE!"=="..." (
        set "LOCAL_IP=!IPLINE!"
        goto :parse_ip
    )
)

:: Metodo 2: wmic si ipconfig no funciono
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
