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
:listar_grupos_locales
for /f "delims=" %%G in ('net localgroup 2^>nul') do (
    set "GLINE=%%G"
    if "!GLINE:~0,1!"=="*" (
        set "GNAME=!GLINE:~1!"
        >>"%REPORTE%" echo ---------- Grupo local: !GNAME! ----------
        net localgroup "!GNAME!" >>"%REPORTE%" 2>&1
        >>"%REPORTE%" echo.
    )
)
exit /b
:detalle_usuarios_locales
for /f "tokens=2 delims==" %%U in ('wmic useraccount where "LocalAccount=True" get Name /value 2^>nul ^| findstr /i "^Name="') do (
    for /f "delims=" %%N in ("%%U") do (
        >>"%REPORTE%" echo ---------- Cuenta local: %%N ----------
        net user "%%N" >>"%REPORTE%" 2>&1
        >>"%REPORTE%" echo.
    )
)
exit /b
:exportar_derechos_usuario
set "SECINF=%TEMP%\AuditSecedit_%COMPUTERNAME%_%RANDOM%.inf"
del "%SECINF%" >nul 2>&1
secedit /export /cfg "%SECINF%" /areas USER_RIGHTS >nul 2>&1
if exist "%SECINF%" (
    type "%SECINF%" >>"%REPORTE%" 2>&1
    del /q "%SECINF%" >nul 2>&1
) else (
    >>"%REPORTE%" echo [AVISO] No se pudo exportar secedit USER_RIGHTS. Ejecutar como Administrador.
)
exit /b
:inventario_uninstall_clave
set "UKEY=%~1"
>>"%REPORTE%" echo --- Clave: %UKEY% ---
for /f "delims=" %%K in ('reg query "%UKEY%" 2^>nul') do (
    set "DN="
    set "DV="
    set "PB="
    for /f "tokens=2,*" %%A in ('reg query "%%K" /v DisplayName 2^>nul') do set "DN=%%B"
    if defined DN (
        for /f "tokens=2,*" %%A in ('reg query "%%K" /v DisplayVersion 2^>nul') do set "DV=%%B"
        for /f "tokens=2,*" %%A in ('reg query "%%K" /v Publisher 2^>nul') do set "PB=%%B"
        if not defined DV set "DV=?"
        if not defined PB set "PB=?"
        >>"%REPORTE%" echo [APP] !DN!  Version=!DV!  Publisher=!PB!
    )
)
>>"%REPORTE%" echo.
exit /b
:detectar_procesos_aplicativo
tasklist /v >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo --- Coincidencias por nombre de proceso conocido ---
tasklist /fo table | findstr /i /c:"sqlservr" /c:"sqlagent" /c:"sqlbrowser" /c:"fdhost" /c:"mysqld" /c:"mariadbd" /c:"postgres" /c:"oracle" /c:"tnslsnr" /c:"mongod" /c:"redis-server" /c:"memcached" /c:"w3wp" /c:"iisexpress" /c:"inetinfo" /c:"httpd" /c:"nginx" /c:"tomcat" /c:"java.exe" /c:"node.exe" /c:"php-cgi" /c:"python.exe" /c:"docker" /c:"com.docker" /c:"sshd" /c:"FileZilla" /c:"ftp" /c:"TeamViewer" /c:"AnyDesk" /c:"WinVNC" /c:"tvnserver" /c:"vnc" /c:"Splashtop" /c:"ScreenConnect" /c:"beserver" /c:"ReportingServices" /c:"MsDtsSrvr" /c:"hMail" >>"%REPORTE%" 2>&1
if errorlevel 1 >>"%REPORTE%" echo (sin coincidencias de procesos de aplicativo conocidos)
exit /b
:consultar_servicios_clave
for %%S in (TermService WinRM LanmanServer LanmanWorkstation W3SVC WAS IISADMIN RemoteRegistry MSSQLSERVER SQLSERVERAGENT SQLBrowser SQLWriter MySQL MariaDB sshd FTPSVC Docker WinDefend Sense) do (
    >>"%REPORTE%" echo --- sc query %%S ---
    sc query "%%S" >>"%REPORTE%" 2>&1
    >>"%REPORTE%" echo.
)
>>"%REPORTE%" echo --- Servicios cuyo nombre o display sugiere aplicativo ---
sc query type= service state= all | findstr /i /c:"SERVICE_NAME:" /c:"DISPLAY_NAME:" /c:"MSSQL" /c:"SQL Server" /c:"MySQL" /c:"MariaDB" /c:"postgres" /c:"Oracle" /c:"World Wide Web" /c:"IIS" /c:"Apache" /c:"nginx" /c:"Tomcat" /c:"Mongo" /c:"Redis" /c:"Docker" /c:"OpenSSH" /c:"FileZilla" /c:"TeamViewer" /c:"AnyDesk" /c:"VNC" /c:"WinRM" /c:"Remote Desktop" >>"%REPORTE%" 2>&1
exit /b
:inicio
title Auditoria Sistema [1/3]
set "DEBUG="
set "MODO_SILENCIOSO=0"
if /i "%1"=="/silent" set "MODO_SILENCIOSO=1"
if /i "%1"=="/debug" set "DEBUG=1"
set "REPORTE=%TEMP%\AuditSistema_%COMPUTERNAME%_%RANDOM%.txt"
set "REPORTE_FINAL=%TEMP%\Reporte_Sistema_CMD.txt"
set "LOG=%TEMP%\Auditoria_Sistema_LOG.txt"
set "FECHA=%DATE% %TIME%"
del "%LOG%" >nul 2>&1
call :log "=== INICIO AUDITORIA SISTEMA ==="
if defined DEBUG (
    for /f %%C in ('find /c /v "" ^< "%~f0"') do echo [DEBUG] Lineas en este archivo: %%C ^(esperado: 280-292^)
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
>>"%REPORTE%" echo Version script: 2026-08-20a
>>"%REPORTE%" echo.
>>"%REPORTE%" echo --- Licencia del sistema operativo ---
>>"%REPORTE%" echo LicenseStatus WMI: 0=Sin licencia  1=Licenciada  2=Gracia OOB  3=Gracia OOT  4=No genuina  5=Notificacion  6=Gracia extendida
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /dli >>"%REPORTE%" 2>&1
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /xpr >>"%REPORTE%" 2>&1
wmic path SoftwareLicensingProduct where (PartialProductKey is not null) get Name,Description,LicenseStatus,PartialProductKey /format:list >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
call :seccion "[+] INFORMACION DEL SISTEMA"
systeminfo >>"%REPORTE%" 2>&1
call :seccion "[+] CUENTAS LOCALES"
net user >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo Miembros del grupo Administrators:
net localgroup Administrators >>"%REPORTE%" 2>&1
call :seccion "[+] DETALLE DE CADA CUENTA LOCAL"
>>"%REPORTE%" echo Incluye membresias de grupo local, caducidad de contrasena y estado.
call :detalle_usuarios_locales
call :seccion "[+] GRUPOS LOCALES Y MIEMBROS"
>>"%REPORTE%" echo Lista completa de alias locales y sus miembros.
net localgroup >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
call :listar_grupos_locales
call :seccion "[+] DERECHOS DE USUARIO - secedit USER_RIGHTS"
>>"%REPORTE%" echo Leyenda SID de grupos locales frecuentes:
>>"%REPORTE%" echo S-1-5-32-544 Administrators / S-1-5-32-545 Users / S-1-5-32-546 Guests
>>"%REPORTE%" echo S-1-5-32-547 Power Users / S-1-5-32-551 Backup Operators / S-1-5-32-555 Remote Desktop Users
>>"%REPORTE%" echo S-1-5-32-562 Distributed COM Users / S-1-5-32-568 IIS_IUSRS / S-1-5-32-578 Hyper-V Administrators
>>"%REPORTE%" echo S-1-5-32-580 Remote Management Users / S-1-5-32-544 es el grupo Administrators
>>"%REPORTE%" echo Derechos sensibles: SeTcbPrivilege SeDebugPrivilege SeBackupPrivilege SeRestorePrivilege
>>"%REPORTE%" echo SeTakeOwnershipPrivilege SeLoadDriverPrivilege SeImpersonatePrivilege SeAssignPrimaryTokenPrivilege
>>"%REPORTE%" echo SeCreateTokenPrivilege SeSecurityPrivilege SeEnableDelegationPrivilege
call :exportar_derechos_usuario
call :seccion "[+] USUARIOS Y PERFILES"
>>"%REPORTE%" echo --- Cuentas locales (detalle WMI) ---
wmic useraccount where "LocalAccount=True" get Name,Domain,Disabled,Lockout,Status,SID,PasswordRequired,PasswordExpires >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo --- Sesiones de usuario activas ---
query user >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo --- Perfiles de usuario ---
wmic userprofile get LocalPath,SID,LastUseTime,Loaded,Special,Status >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo --- Carpetas de perfil en %SystemDrive%\Users ---
dir /a:d "%SystemDrive%\Users" >>"%REPORTE%" 2>&1
>>"%REPORTE%" echo.
>>"%REPORTE%" echo --- ProfileList (ruta de cada perfil) ---
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" /s /v ProfileImagePath >>"%REPORTE%" 2>&1
call :seccion "[+] CONTRASENAS LOCALES"
net accounts >>"%REPORTE%" 2>&1
call :seccion "[+] CONTEXTO DE SESION ACTUAL"
>>"%REPORTE%" echo Usuario: %USERDOMAIN%\%USERNAME%
>>"%REPORTE%" echo Equipo: %COMPUTERNAME%
>>"%REPORTE%" echo Sesion: %SESSIONNAME%
>>"%REPORTE%" echo.
whoami /all >>"%REPORTE%" 2>&1
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
call :seccion "[+] SERVICIOS DEL SISTEMA - inventario WMI"
>>"%REPORTE%" echo Columnas: Name DisplayName State StartMode StartName PathName
>>"%REPORTE%" echo StartName es la cuenta con la que corre el servicio. PathName sin comillas es riesgo.
wmic service get Name,DisplayName,State,StartMode,StartName,PathName /format:list >>"%REPORTE%" 2>&1
call :seccion "[+] SERVICIOS WIN32 - sc query state= all"
sc query type= service state= all >>"%REPORTE%" 2>&1
call :seccion "[+] SERVICIOS CLAVE Y DE APLICATIVO"
call :consultar_servicios_clave
call :seccion "[+] SOFTWARE INSTALADO - registro Uninstall"
>>"%REPORTE%" echo No usa wmic product (incompleto y lento). Fuente: DisplayName del registro.
call :inventario_uninstall_clave "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
call :inventario_uninstall_clave "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
call :inventario_uninstall_clave "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
call :seccion "[+] PROCESOS EN EJECUCION"
tasklist >>"%REPORTE%" 2>&1
call :seccion "[+] PROCESOS DE APLICATIVO DETECTADOS"
call :detectar_procesos_aplicativo
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
call :log "=== FIN - copiando reporte a %TEMP% ==="
copy /y "%REPORTE%" "%REPORTE_FINAL%" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] No se pudo copiar a %TEMP%. Cierre Notepad si tiene abierto el reporte.
    echo Reporte temporal: %REPORTE%
    call :log "ERROR al copiar a %TEMP%"
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
