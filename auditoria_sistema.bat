@echo off
setlocal EnableDelayedExpansion
goto :inicio

:log
echo [%time%] %~1
>>"%LOG%" echo [%time%] %~1
exit /b

:seccion
echo %~1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo %~1
>>"%REPORTE%" echo.
call :log "OK: %~1"
exit /b

:verificar_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [AVISO] Ejecutar como Administrador para datos completos.
    call :log "AVISO: sin privilegios de administrador"
    timeout /t 2 >nul
) else (
    call :log "Privilegios de administrador confirmados"
)
exit /b

:resumen_sistema
net session >nul 2>&1
if %errorlevel% equ 0 (
    >>"%REPORTE%" echo [OK] Privilegios de Administrador
) else (
    >>"%REPORTE%" echo [AVISO] Sin privilegios de Administrador
)
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections 2>nul | findstr "0x0" >nul
if !errorlevel! equ 0 (
    >>"%REPORTE%" echo [INFO] RDP habilitado - verificar acceso
)
netsh advfirewall show allprofiles state 2>nul | findstr /i "OFF" >nul
if !errorlevel! equ 0 (
    >>"%REPORTE%" echo [AVISO] Firewall desactivado en algun perfil
)
exit /b

:inicio
title Auditoria Sistema [1/3]

set "REPORTE=%TEMP%\AuditSistema_%COMPUTERNAME%_%RANDOM%.txt"
set "REPORTE_FINAL=%USERPROFILE%\Desktop\Reporte_Sistema_CMD.txt"
set "LOG=%USERPROFILE%\Desktop\Auditoria_Sistema_LOG.txt"
set "FECHA=%DATE% %TIME%"

del "%LOG%" >nul 2>&1
call :log "=== INICIO AUDITORIA SISTEMA ==="

call :verificar_admin
echo [1/3] Generando reporte de SISTEMA...
echo Log de depuracion: %LOG%
echo.

>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo   AUDITORIA SISTEMA - modulo 1 de 3 - CMD
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo Fecha: %FECHA%
>>"%REPORTE%" echo Equipo: %COMPUTERNAME%
>>"%REPORTE%" echo Usuario: %USERNAME%
>>"%REPORTE%" echo.

call :seccion "[+] INFORMACION DEL SISTEMA"
systeminfo >>"%REPORTE%" 2>&1

call :seccion "[+] INVENTARIO DE HARDWARE"
wmic computersystem get manufacturer,model,name,domain,totalphysicalmemory >>"%REPORTE%" 2>&1
wmic cpu get name,numberofcores,numberoflogicalprocessors >>"%REPORTE%" 2>&1
wmic diskdrive get deviceid,model,size,status >>"%REPORTE%" 2>&1
wmic memorychip get capacity,speed,manufacturer >>"%REPORTE%" 2>&1

call :seccion "[+] ESTADO OPERATIVO - uptime CPU RAM disco"
wmic os get caption,version,buildnumber,lastbootuptime,installdate >>"%REPORTE%" 2>&1
wmic cpu get loadpercentage >>"%REPORTE%" 2>&1
wmic os get freephysicalmemory,totalvisiblememorysize >>"%REPORTE%" 2>&1
wmic logicaldisk get caption,freespace,size,volumename >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo Nota: disco con menos del 10%% libre requiere atencion.

call :seccion "[+] CUENTAS LOCALES"
net user >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo Miembros del grupo Administrators:
net localgroup Administrators >>"%REPORTE%" 2>&1

call :seccion "[+] CONTRASENAS LOCALES"
net accounts >>"%REPORTE%" 2>&1

call :seccion "[+] CONTEXTO DE SESION ACTUAL"
>>"%REPORTE%" echo Usuario: %USERDOMAIN%\%USERNAME%
>>"%REPORTE%" echo Equipo: %COMPUTERNAME%
>>"%REPORTE%" echo Sesion: %SESSIONNAME%
net user "%USERNAME%" >>"%REPORTE%" 2>&1

call :seccion "[+] ESTADO DE CUENTAS LOCALES"
wmic useraccount get name,disabled,passwordexpires,sid >>"%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION DE REGISTRO DE EVENTOS"
auditpol /get /category:^* >>"%REPORTE%" 2>&1

call :seccion "[+] DIRECTIVAS DE GRUPO APLICADAS"
gpresult /r /scope:computer >>"%REPORTE%" 2>&1
gpresult /r /scope:user >>"%REPORTE%" 2>&1

call :seccion "[+] CONEXIONES SMB ACTIVAS"
net session >>"%REPORTE%" 2>&1
net files >>"%REPORTE%" 2>&1

call :seccion "[+] RECURSOS COMPARTIDOS"
net share >>"%REPORTE%" 2>&1

call :seccion "[+] ESTADO DEL FIREWALL"
netsh advfirewall show allprofiles >>"%REPORTE%" 2>&1

call :seccion "[+] REGLAS DE FIREWALL ENTRANTES PERMITIDAS"
netsh advfirewall firewall show rule name=all dir=in action=allow enable=yes >>"%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION RDP SMB WINRM Y UAC"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections >>"%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber >>"%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v RequireSecuritySignature >>"%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v EnableSecuritySignature >>"%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA >>"%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin >>"%REPORTE%" 2>&1
winrm get winrm/config >>"%REPORTE%" 2>&1

call :seccion "[+] PROGRAMAS DE INICIO AUTOMATICO - REGISTRO"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" >>"%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" >>"%REPORTE%" 2>&1
reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" >>"%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" >>"%REPORTE%" 2>&1

call :seccion "[+] CONFIGURACION SMBv1"
reg query "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v SMB1 >>"%REPORTE%" 2>&1
sc query lanmanserver >>"%REPORTE%" 2>&1

call :seccion "[+] ACTUALIZACIONES INSTALADAS - tabla"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:table >>"%REPORTE%" 2>&1

call :seccion "[+] ACTUALIZACIONES INSTALADAS - lista"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:list >>"%REPORTE%" 2>&1

call :seccion "[+] ACTUALIZACIONES INSTALADAS - CSV"
wmic qfe get Description,HotFixID,InstalledOn,InstalledBy /format:csv >>"%REPORTE%" 2>&1

call :seccion "[+] VERSION DE SO Y PARCHES RECIENTES"
wmic os get caption,version,buildnumber,csdversion >>"%REPORTE%" 2>&1
wmic qfe get HotFixID,Description,InstalledOn /format:table >>"%REPORTE%" 2>&1

call :seccion "[+] SERVICIOS DEL SISTEMA"
sc query type= service state= all | findstr /i "SERVICE_NAME DISPLAY_NAME STATE" >>"%REPORTE%" 2>&1

call :seccion "[+] SERVICIOS DETALLADOS"
wmic service get name,displayname,state,startmode,pathname >>"%REPORTE%" 2>&1

call :seccion "[+] PROCESOS EN EJECUCION"
tasklist /v /fo list >>"%REPORTE%" 2>&1

call :seccion "[+] TAREAS PROGRAMADAS - tabla"
schtasks /query /fo TABLE >>"%REPORTE%" 2>&1

call :seccion "[+] TAREAS PROGRAMADAS - detalle"
schtasks /query /fo LIST /v >>"%REPORTE%" 2>&1

call :seccion "[+] INICIO AUTOMATICO - CARPETA Y REGISTRO"
wmic startup get caption,command,location,user >>"%REPORTE%" 2>&1

call :seccion "[+] SERVICIOS DE APLICACIONES DE TERCEROS"
wmic service where "StartMode='Auto' and State='Running'" get name,displayname,pathname,startname >>"%REPORTE%" 2>&1

call :seccion "[+] DRIVERS INSTALADOS"
driverquery /fo list /v >>"%REPORTE%" 2>&1

call :seccion "[+] ALMACEN DE CERTIFICADOS"
certutil -store MY >>"%REPORTE%" 2>&1
certutil -store ROOT >>"%REPORTE%" 2>&1


>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo       RELACION CON DOMINIO
>>"%REPORTE%" echo =========================================

call :seccion "[+] Dominio y servidor de autenticacion"
systeminfo | findstr /B /C:"Domain" /C:"Logon Server" >>"%REPORTE%" 2>&1

call :seccion "[+] Controlador de dominio cercano"
nltest /dsgetdc: >>"%REPORTE%" 2>&1

call :seccion "[+] Controladores de dominio registrados"
for /f "tokens=2 delims=:" %%D in ('systeminfo 2^>nul ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" nltest /dclist:!DOM! >>"%REPORTE%" 2>&1
)

call :seccion "[+] Conectividad al controlador de dominio"
for /f "tokens=2 delims=:" %%S in ('systeminfo 2^>nul ^| findstr /i /b "Logon Server"') do (
    set "DC=%%S"
    set "DC=!DC:\\=!"
    set "DC=!DC: =!"
    if not "!DC!"=="" (
        >>"%REPORTE%" echo Servidor: !DC!
        ping -n 3 !DC! >>"%REPORTE%" 2>&1
    )
)

call :seccion "[+] Equipos visibles en el dominio"
for /f "tokens=2 delims=:" %%D in ('systeminfo 2^>nul ^| findstr /i /b "Domain:"') do (
    set "DOM=%%D"
    set "DOM=!DOM: =!"
    if not "!DOM!"=="" net view /domain:!DOM! >>"%REPORTE%" 2>&1
)

call :seccion "[+] Miembros de Domain Admins"
net group "Domain Admins" /domain >>"%REPORTE%" 2>&1

call :seccion "[+] RESUMEN DE INDICADORES DEL SISTEMA"
call :resumen_sistema

>>"%REPORTE%" echo.
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo     FIN REPORTE SISTEMA - modulo 1 de 3
>>"%REPORTE%" echo =========================================
>>"%REPORTE%" echo Generado: %FECHA%

call :log "=== FIN - copiando reporte al Escritorio ==="

copy /y "%REPORTE%" "%REPORTE_FINAL%" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] No se pudo copiar al Escritorio. Cierre Notepad si tiene abierto el reporte.
    echo Reporte temporal: %REPORTE%
    call :log "ERROR al copiar al Escritorio"
) else (
    echo Listo: %REPORTE_FINAL%
    call :log "Reporte copiado OK"
    del "%REPORTE%" >nul 2>&1
)

echo.
echo Revise el log: %LOG%
echo Debe mostrar ~35 lineas "OK: [+] ..."
echo.
if /i not "%1"=="/silent" pause
exit /b 0
