@echo off
echo Generando reporte de auditoria... por favor espere.
set REPORTE=%USERPROFILE%\Desktop\Reporte_CMD.txt

echo ========================================= > "%REPORTE%"
echo        REPORTE DE AUDITORIA (CMD)       >> "%REPORTE%"
echo ========================================= >> "%REPORTE%"

echo [+] HARDWARE >> "%REPORTE%"
wmic computersystem get manufacturer,model >> "%REPORTE%"
wmic cpu get name >> "%REPORTE%"
wmic diskdrive get deviceid,model,status >> "%REPORTE%"

echo [+] RED Y PUERTOS EN ESCUCHA (LISTENING) >> "%REPORTE%"
netstat -nab | findstr /i "listening" >> "%REPORTE%"

echo [+] CONEXIONES ESTABLECIDAS >> "%REPORTE%"
netstat -nab | findstr /i "established" | find /c /v "" >> "%REPORTE%"

echo [+] CONEXIONES ESTABLECIDAS (ORDENADAS POR PUERTO) >> "%REPORTE%"
netstat -nab | findstr /i "established" | sort >> "%REPORTE%"

echo [+] CUENTAS Y SEGURIDAD >> "%REPORTE%"
net user >> "%REPORTE%"
echo Members of Administrators Group: >> "%REPORTE%"
net localgroup Administrators >> "%REPORTE%"

echo [+] PARCHES Y SISTEMA >> "%REPORTE%"
wmic qfe list brief >> "%REPORTE%"

echo [+] LOGS FALLIDOS RECIENTES >> "%REPORTE%"
wevtutil qe Security "/q:*[System[(EventID=4625)]]" /c:10 /f:text >> "%REPORTE%"

echo [+] DETECCION DE PRIVILEGIOS Y NUEVOS SERVICIOS (ID 4672, 4697) >> "%REPORTE%"
wevtutil qe Security "/q:*[System[(EventID=4672 or EventID=4697)]]" /c:20 /f:text >> "%REPORTE%"

echo [+] MODIFICACIONES DE CUENTAS Y GRUPOS (ID 4720, 4732) >> "%REPORTE%"
wevtutil qe Security "/q:*[System[(EventID=4720 or EventID=4732)]]" /c:15 /f:text >> "%REPORTE%"

echo [+] ALERTA: INTENTOS DE BORRADO DE LOGS (ID 1102) >> "%REPORTE%"
wevtutil qe Security "/q:*[System[(EventID=1102)]]" /c:5 /f:text >> "%REPORTE%"

echo Reporte finalizado en el Escritorio: Reporte_CMD.txt
pause


