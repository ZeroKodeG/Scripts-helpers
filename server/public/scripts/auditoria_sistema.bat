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
if defined DEBUG echo       errorlevel=%errorlevel%
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
reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile" /v EnableFirewall 2>nul | findstr "0x0" >nul
if !errorlevel! equ 0 (
    >>"%REPORTE%" echo [AVISO] Firewall perfil estandar desactivado en registro
)
exit /b
:inicio
title Auditoria Sistema [1/3]
set "DEBUG="
set "MODO_SILENCIOSO=0"
if /i "%1"=="/silent" set "MODO_SILENCIOSO=1"
if /i "%1"=="/debug" set "DEBUG=1"
set "REPORTE=%TEMP%\AuditSistema_%COMPUTERNAME%_%RANDOM%.txt"
set "REPORTE_FINAL=%USERPROFILE%\Desktop\Reporte_Sistema_CMD.txt"
set "LOG=%USERPROFILE%\Desktop\Auditoria_Sistema_LOG.txt"
set "FECHA=%DATE% %TIME%"
del "%LOG%" >nul 2>&1
call :log "=== INICIO AUDITORIA SISTEMA ==="
if defined DEBUG (
    for /f %%C in ('find /c /v "" ^< "%~f0"') do echo [DEBUG] Lineas en este archivo: %%C ^(esperado: 168-175^)
    echo [DEBUG] Archivo: %~f0
    echo.
)
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
>>"%REPORTE%" echo Version script: 2026-06-17e
>>"%REPORTE%" echo.
call :seccion "[+] INFORMACION DEL SISTEMA"
systeminfo >>"%REPORTE%" 2>&1
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
call :seccion "[+] ESTADO DEL FIREWALL"
reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile" >>"%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile" >>"%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile" >>"%REPORTE%" 2>&1
call :seccion "[+] CONFIGURACION RDP SMB Y UAC"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections >>"%REPORTE%" 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber >>"%REPORTE%" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA >>"%REPORTE%" 2>&1
sc query TermService >>"%REPORTE%" 2>&1
sc query WinRM >>"%REPORTE%" 2>&1
call :seccion "[+] ACTUALIZACIONES INSTALADAS"
systeminfo | findstr /i /c:"KB" /c:"Hotfix" >>"%REPORTE%" 2>&1
call :seccion "[+] SERVICIOS DEL SISTEMA"
sc query TermService >>"%REPORTE%" 2>&1
sc query WinRM >>"%REPORTE%" 2>&1
sc query LanmanServer >>"%REPORTE%" 2>&1
sc query W3SVC >>"%REPORTE%" 2>&1
call :seccion "[+] PROCESOS EN EJECUCION"
tasklist >>"%REPORTE%" 2>&1
call :seccion "[+] DIRECTIVAS DE GRUPO APLICADAS"
gpresult /r /scope:computer >>"%REPORTE%" 2>&1
call :seccion "[+] RECURSOS COMPARTIDOS"
net share >>"%REPORTE%" 2>&1
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
call :seccion "[+] Miembros de Domain Admins"
net group "Domain Admins" /domain >>"%REPORTE%" 2>&1
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
    if not defined DEBUG del "%REPORTE%" >nul 2>&1
    if defined DEBUG echo [DEBUG] Reporte temporal conservado: %REPORTE%
)
echo.
echo Revise el log: %LOG%
echo.
if defined DEBUG (
    echo =========================================
    echo   MODO DEBUG - la ventana no se cierra sola
    echo =========================================
    echo Si faltan secciones arriba, Kaspersky recorto el .bat
    echo o el archivo no es el mas reciente.
    echo.
    pause
) else if "%MODO_SILENCIOSO%"=="0" pause
exit /b 0
