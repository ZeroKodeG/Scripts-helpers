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

call :seccion "[+] SALUD DEL SISTEMA (uptime, CPU, RAM, disco)"
wmic os get caption,version,buildnumber,lastbootuptime,installdate >> "%REPORTE%" 2>&1
wmic cpu get loadpercentage >> "%REPORTE%" 2>&1
wmic OS get freephysicalmemory,totalvisiblememorysize >> "%REPORTE%" 2>&1
wmic logicaldisk where "DriveType=3" get caption,freespace,size,volumename >> "%REPORTE%" 2>&1
echo Nota: disco con menos del 10%% libre requiere atencion. >> "%REPORTE%"

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

call :seccion "[+] POLITICA DE CONTRASENAS LOCAL"
net accounts >> "%REPORTE%" 2>&1

call :seccion "[+] USUARIO Y PRIVILEGIOS ACTUALES (whoami)"
whoami /all >> "%REPORTE%" 2>&1

call :seccion "[+] CUENTAS DESHABILITADAS Y CON PASSWORD SIN EXPIRAR"
wmic useraccount get name,disabled,passwordexpires,sid >> "%REPORTE%" 2>&1

call :seccion "[+] POLITICA DE AUDITORIA (auditpol)"
auditpol /get /category:* >> "%REPORTE%" 2>&1

call :seccion "[+] GROUP POLICY APLICADA (gpresult)"
gpresult /r /scope:computer >> "%REPORTE%" 2>&1
gpresult /r /scope:user >> "%REPORTE%" 2>&1

call :seccion "[+] SESIONES SMB ENTRANTES"
net session >> "%REPORTE%" 2>&1
net files >> "%REPORTE%" 2>&1

call :seccion "[+] SHARES EXPUESTOS"
net share >> "%REPORTE%" 2>&1

call :seccion "[+] FIREWALL WINDOWS (ESTADO)"
netsh advfirewall show allprofiles >> "%REPORTE%" 2>&1

call :seccion "[+] REGLAS DE FIREWALL ENTRANTES HABILITADAS (resumen)"
netsh advfirewall firewall show rule name=all dir=in action=allow enable=yes >> "%REPORTE%" 2>&1

call :seccion "[+] HARDENING - RDP, SMB, WINRM, UAC"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections >> "%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber >> "%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v RequireSecuritySignature >> "%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v EnableSecuritySignature >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin >> "%REPORTE%" 2>&1
winrm get winrm/config >> "%REPORTE%" 2>&1

call :seccion "[+] PERSISTENCIA - CLAVES RUN Y RUNONCE"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" >> "%REPORTE%" 2>&1
reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" >> "%REPORTE%" 2>&1

call :seccion "[+] SMBv1 (deshabilitado = recomendado)"
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v SMB1 >> "%REPORTE%" 2>&1
sc query lanmanserver >> "%REPORTE%" 2>&1

:: =============================================================================
::  PARCHES Y ACTUALIZACIONES (sin PowerShell)
:: =============================================================================
call :seccion "[+] PARCHES Y SISTEMA (formato tabla)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:table >> "%REPORTE%" 2>&1

call :seccion "[+] PARCHES Y SISTEMA (formato lista)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:list >> "%REPORTE%" 2>&1

call :seccion "[+] PARCHES Y SISTEMA (formato CSV)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:csv >> "%REPORTE%" 2>&1

call :seccion "[+] VERSION DE SO Y ULTIMO PARCHE INSTALADO"
wmic os get caption,version,buildnumber,csdversion >> "%REPORTE%" 2>&1
echo --- Ultimos 5 parches por fecha --- >> "%REPORTE%"
wmic qfe get HotFixID,Description,InstalledOn /format:table >> "%REPORTE%" 2>&1
echo Nota: comparar build y fecha del ultimo parche con el catalogo de Microsoft. >> "%REPORTE%"

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

call :seccion "[+] SERVICIOS AUTO INICIADOS FUERA DE System32 (revisar)"
wmic service where "StartMode='Auto' and State='Running'" get name,displayname,pathname,startname >> "%REPORTE%" 2>&1
echo --- Servicios con ruta fuera de Windows\System32 --- >> "%REPORTE%"
wmic service where "PathName like '%%Program%%' OR PathName like '%%AppData%%' OR PathName like '%%Temp%%'" get name,displayname,pathname,startname,state >> "%REPORTE%" 2>&1

call :seccion "[+] DRIVERS DEL SISTEMA"
driverquery /fo list /v >> "%REPORTE%" 2>&1

:: Tarda varios minutos en ejecutar, habilitar si se requiere
call :seccion "[+] SOFTWARE INSTALADO (puede tardar varios minutos)"
wmic product get name,version,vendor,installdate >> "%REPORTE%" 2>&1

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

call :seccion "[+] LOGON TIPO 10 - RDP EXITOSO (ID 4624 Task 10)"
wevtutil qe Security "/q:*[System[(EventID=4624)]] and EventData[Data[@Name='LogonType']='10']" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] CREDENCIALES EXPLICITAS USADAS (ID 4648)"
wevtutil qe Security "/q:*[System[(EventID=4648)]]" /c:10 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] KERBEROS PRE-AUTH FALLIDO (ID 4771) - posible brute force"
wevtutil qe Security "/q:*[System[(EventID=4771)]]" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] CAMBIO EN POLITICA DE AUDITORIA (ID 4719)"
wevtutil qe Security "/q:*[System[(EventID=4719)]]" /c:5 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] NUEVO SERVICIO INSTALADO - System log (ID 7045)"
wevtutil qe System "/q:*[System[(EventID=7045)]]" /c:15 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] APAGADOS INESPERADOS (ID 6008) y KERNEL-POWER (ID 41)"
wevtutil qe System "/q:*[System[(EventID=6008)]]" /c:5 /f:text >> "%REPORTE%" 2>&1
wevtutil qe System "/q:*[System[(EventID=41)]]" /c:5 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] ERRORES CRITICOS SYSTEM (ultimas 24h)"
wevtutil qe System "/q:*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 86400000]]]" /c:20 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] ERRORES APPLICATION (ultimas 24h)"
wevtutil qe Application "/q:*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 86400000]]]" /c:20 /f:text >> "%REPORTE%" 2>&1

call :seccion "[+] TAMANO Y RETENCION DE LOGS"
wevtutil gl Security >> "%REPORTE%" 2>&1
wevtutil gl System >> "%REPORTE%" 2>&1
wevtutil gl Application >> "%REPORTE%" 2>&1

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

call :seccion "[+] CERTIFICADOS INSTALADOS (resumen)"
certutil -store MY >> "%REPORTE%" 2>&1
certutil -store ROOT >> "%REPORTE%" 2>&1

call :seccion "[+] TAREAS PROGRAMADAS DETALLADAS (con comando)"
schtasks /query /fo LIST /v >> "%REPORTE%" 2>&1

call :seccion "[+] RESUMEN EJECUTIVO - INDICADORES CLAVE"
call :resumen_ejecutivo

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

:: =============================================================================
::  Subrutina: resumen ejecutivo con alertas basicas
:: =============================================================================
:resumen_ejecutivo
echo === CHECKLIST RAPIDO === >> "%REPORTE%"
echo. >> "%REPORTE%"

:: Admin check
net session >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Ejecutado con privilegios de Administrador >> "%REPORTE%"
) else (
    echo [ALERTA] NO se ejecuto como Administrador - datos incompletos >> "%REPORTE%"
)

:: RDP habilitado
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections 2>nul | findstr "0x0" >nul
if %errorlevel% equ 0 (
    echo [INFO] RDP parece HABILITADO - verificar acceso y NLA >> "%REPORTE%"
) else (
    echo [OK] RDP parece deshabilitado o no detectado >> "%REPORTE%"
)

:: Firewall deshabilitado
netsh advfirewall show allprofiles state 2>nul | findstr /i "OFF" >nul
if %errorlevel% equ 0 (
    echo [ALERTA] Firewall Windows DESACTIVADO en algun perfil >> "%REPORTE%"
) else (
    echo [OK] Firewall Windows activo en todos los perfiles >> "%REPORTE%"
)

:: Guest habilitado
net user guest 2>nul | findstr /i "activada yes si" >nul
if %errorlevel% equ 0 (
    echo [ALERTA] Cuenta Guest podria estar activa - revisar >> "%REPORTE%"
)

:: Contadores rapidos de eventos criticos
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4625)]]" /c:50 /f:text 2^>nul ^| find /c "Event ID"') do (
    echo [INFO] Logons fallidos recientes en muestra: %%C de 50 >> "%REPORTE%"
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=1102)]]" /c:10 /f:text 2^>nul ^| find /c "Event ID"') do (
    if %%C gtr 0 echo [CRITICO] Detectados %%C eventos de BORRADO DE LOGS ^(ID 1102^) >> "%REPORTE%"
)
for /f %%C in ('wevtutil qe Security "/q:*[System[(EventID=4720)]]" /c:10 /f:text 2^>nul ^| find /c "Event ID"') do (
    if %%C gtr 0 echo [ALERTA] Detectadas %%C creaciones de cuenta nuevas ^(ID 4720^) >> "%REPORTE%"
)

echo. >> "%REPORTE%"
echo Revisar manualmente: puertos 3389/445/5985 expuestos, servicios fuera de System32, >> "%REPORTE%"
echo tareas programadas desconocidas, y parches mas antiguos de 60 dias. >> "%REPORTE%"
goto :eof
