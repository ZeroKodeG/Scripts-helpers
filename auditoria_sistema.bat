@echo off
:: =============================================================================
::  AUDITORIA 1/3 - SISTEMA, SEGURIDAD LOCAL, DOMINIO Y SERVICIOS
::  Solo CMD - Sin PowerShell | Ejecutar como Administrador
::  Salida: %USERPROFILE%\Desktop\Reporte_Sistema_CMD.txt
:: =============================================================================
setlocal EnableDelayedExpansion
title Auditoria Sistema [1/3]

set "REPORTE=%USERPROFILE%\Desktop\Reporte_Sistema_CMD.txt"
set "FECHA=%DATE% %TIME%"

call :verificar_admin
echo [1/3] Generando reporte de SISTEMA...
echo Destino: %REPORTE%
echo.

(
echo =========================================
echo   AUDITORIA SISTEMA ^(1 de 3^) - CMD
echo =========================================
echo Fecha: %FECHA%
echo Equipo: %COMPUTERNAME%
echo Usuario: %USERNAME%
echo.
) > "%REPORTE%"

call :seccion "[+] INFORMACION DEL SISTEMA"
systeminfo >> "%REPORTE%"

call :seccion "[+] INVENTARIO DE HARDWARE"
wmic computersystem get manufacturer,model,name,domain,totalphysicalmemory >> "%REPORTE%" 2>&1
wmic cpu get name,numberofcores,numberoflogicalprocessors >> "%REPORTE%" 2>&1
wmic diskdrive get deviceid,model,size,status >> "%REPORTE%" 2>&1
wmic memorychip get capacity,speed,manufacturer >> "%REPORTE%" 2>&1

call :seccion "[+] ESTADO OPERATIVO (uptime, CPU, RAM, disco)"
wmic os get caption,version,buildnumber,lastbootuptime,installdate >> "%REPORTE%" 2>&1
wmic cpu get loadpercentage >> "%REPORTE%" 2>&1
wmic OS get freephysicalmemory,totalvisiblememorysize >> "%REPORTE%" 2>&1
wmic logicaldisk where "DriveType=3" get caption,freespace,size,volumename >> "%REPORTE%" 2>&1
echo Nota: disco con menos del 10%% libre requiere atencion. >> "%REPORTE%"

call :seccion "[+] CUENTAS LOCALES"
net user >> "%REPORTE%" 2>&1
echo. >> "%REPORTE%"
echo Miembros del grupo Administrators: >> "%REPORTE%"
net localgroup Administrators >> "%REPORTE%" 2>&1

call :seccion "[+] POLITICA DE CONTRASENAS"
net accounts >> "%REPORTE%" 2>&1

call :seccion "[+] CONTEXTO DE SESION ACTUAL"
whoami /all >> "%REPORTE%" 2>&1

call :seccion "[+] ESTADO DE CUENTAS LOCALES"
wmic useraccount get name,disabled,passwordexpires,sid >> "%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION DE REGISTRO DE EVENTOS"
auditpol /get /category:* >> "%REPORTE%" 2>&1

call :seccion "[+] DIRECTIVAS DE GRUPO APLICADAS"
gpresult /r /scope:computer >> "%REPORTE%" 2>&1
gpresult /r /scope:user >> "%REPORTE%" 2>&1

call :seccion "[+] CONEXIONES SMB ACTIVAS"
net session >> "%REPORTE%" 2>&1
net files >> "%REPORTE%" 2>&1

call :seccion "[+] RECURSOS COMPARTIDOS"
net share >> "%REPORTE%" 2>&1

call :seccion "[+] ESTADO DEL FIREWALL"
netsh advfirewall show allprofiles >> "%REPORTE%" 2>&1

call :seccion "[+] REGLAS DE FIREWALL ENTRANTES PERMITIDAS"
netsh advfirewall firewall show rule name=all dir=in action=allow enable=yes >> "%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION RDP, SMB, WINRM Y UAC"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections >> "%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber >> "%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v RequireSecuritySignature >> "%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v EnableSecuritySignature >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin >> "%REPORTE%" 2>&1
winrm get winrm/config >> "%REPORTE%" 2>&1

call :seccion "[+] PROGRAMAS DE INICIO AUTOMATICO (REGISTRO)"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" >> "%REPORTE%" 2>&1
reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" >> "%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" >> "%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION SMBv1"
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v SMB1 >> "%REPORTE%" 2>&1
sc query lanmanserver >> "%REPORTE%" 2>&1

call :seccion "[+] ACTUALIZACIONES INSTALADAS (tabla)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:table >> "%REPORTE%" 2>&1

call :seccion "[+] ACTUALIZACIONES INSTALADAS (lista)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:list >> "%REPORTE%" 2>&1

call :seccion "[+] ACTUALIZACIONES INSTALADAS (CSV)"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:csv >> "%REPORTE%" 2>&1

call :seccion "[+] VERSION DE SO Y PARCHES RECIENTES"
wmic os get caption,version,buildnumber,csdversion >> "%REPORTE%" 2>&1
wmic qfe get HotFixID,Description,InstalledOn /format:table >> "%REPORTE%" 2>&1
echo Nota: comparar build y fecha del ultimo parche con el catalogo de Microsoft. >> "%REPORTE%"

call :seccion "[+] SERVICIOS DEL SISTEMA"
sc query type= service state= all | findstr /i "SERVICE_NAME DISPLAY_NAME STATE" >> "%REPORTE%"

call :seccion "[+] SERVICIOS DETALLADOS"
wmic service get name,displayname,state,startmode,pathname >> "%REPORTE%" 2>&1

call :seccion "[+] PROCESOS EN EJECUCION"
wmic process get name,processid,executablepath >> "%REPORTE%" 2>&1

call :seccion "[+] TAREAS PROGRAMADAS (tabla)"
schtasks /query /fo TABLE >> "%REPORTE%" 2>&1

call :seccion "[+] TAREAS PROGRAMADAS (detalle)"
schtasks /query /fo LIST /v >> "%REPORTE%" 2>&1

call :seccion "[+] INICIO AUTOMATICO (CARPETA Y REGISTRO)"
wmic startup get caption,command,location,user >> "%REPORTE%" 2>&1

call :seccion "[+] SERVICIOS CON RUTA DE APLICACION DE TERCEROS"
wmic service where "StartMode='Auto' and State='Running'" get name,displayname,pathname,startname >> "%REPORTE%" 2>&1
wmic service where "PathName like '%%Program%%' OR PathName like '%%AppData%%'" get name,displayname,pathname,startname,state >> "%REPORTE%" 2>&1

call :seccion "[+] DRIVERS INSTALADOS"
driverquery /fo list /v >> "%REPORTE%" 2>&1

:: Descomentar las 2 lineas siguientes si se requiere inventario MSI (tarda varios minutos)
:: call :seccion "[+] INVENTARIO DE SOFTWARE INSTALADO"
:: wmic product get name,version,vendor,installdate >> "%REPORTE%" 2>&1

call :seccion "[+] ALMACEN DE CERTIFICADOS"
certutil -store MY >> "%REPORTE%" 2>&1
certutil -store ROOT >> "%REPORTE%" 2>&1

(
echo =========================================
echo       RELACION CON DOMINIO
echo =========================================
) >> "%REPORTE%"

call :seccion "[+] Dominio y servidor de autenticacion"
systeminfo | findstr /B /C:"Domain" /C:"Logon Server" >> "%REPORTE%"

call :seccion "[+] Controlador de dominio cercano"
nltest /dsgetdc: >> "%REPORTE%" 2>&1

call :seccion "[+] Controladores de dominio registrados"
for /f "tokens=2 delims=:" %%D in ('systeminfo ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" nltest /dclist:!DOM! >> "%REPORTE%" 2>&1
)

call :seccion "[+] Conectividad al controlador de dominio"
for /f "tokens=2 delims=:" %%S in ('systeminfo ^| findstr /i /b "Logon Server"') do (
    set "DC=%%S"
    set "DC=!DC:\\=!"
    set "DC=!DC: =!"
    if not "!DC!"=="" (
        echo Servidor: !DC! >> "%REPORTE%"
        ping -n 3 !DC! >> "%REPORTE%"
    )
)

call :seccion "[+] Equipos visibles en el dominio"
for /f "tokens=2 delims=:" %%D in ('systeminfo ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" net view /domain:!DOM! >> "%REPORTE%" 2>&1
)

call :seccion "[+] Miembros de Domain Admins"
net group "Domain Admins" /domain >> "%REPORTE%" 2>&1

call :seccion "[+] RESUMEN DE INDICADORES DEL SISTEMA"
call :resumen_sistema

(
echo.
echo =========================================
echo     FIN REPORTE SISTEMA (1/3)
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

:resumen_sistema
net session >nul 2>&1
if %errorlevel% equ 0 (echo [OK] Privilegios de Administrador >> "%REPORTE%") else (echo [AVISO] Sin privilegios de Administrador >> "%REPORTE%")
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections 2>nul | findstr "0x0" >nul && echo [INFO] RDP habilitado - verificar acceso >> "%REPORTE%"
netsh advfirewall show allprofiles state 2>nul | findstr /i "OFF" >nul && echo [AVISO] Firewall desactivado en algun perfil >> "%REPORTE%"
goto :eof
