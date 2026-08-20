# Scripts-helpers

Auditoria de servidores Windows centralizada en un backend propio:

1. **Scripts cliente** (`.bat`, en `server/public/scripts/`) — se ejecutan en cada servidor Windows y generan 3 reportes de texto (sistema, red, logs). El backend los sirve directamente, no dependen de GitHub.
2. **Backend** (`server/`) — API Node.js + SQLite que sirve esos scripts, recibe los reportes, y expone un dashboard web simple para listarlos por equipo/fecha, descargarlos y adjuntarles un PDF.

## Uso rapido en un servidor

Los reportes viven en `%TEMP%` (compatible con SYSTEM: suele ser `C:\Windows\Temp`). La API key se pasa por variables de entorno del proceso (`AUDIT_API_KEY` / `AUDIT_API_URL`) o, si no estan, por `%TEMP%\.audit_config`.

### Manual (PowerShell como Administrador)

```powershell
$env:AUDIT_API_URL='https://api-tertius-auditoria.alvesc.com'
$env:AUDIT_API_KEY='XXXXXXXXXXX'
$p = Join-Path $env:TEMP 'ejecutar_auditoria.bat'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(New-Object Net.WebClient).DownloadFile(($env:AUDIT_API_URL + '/scripts/ejecutar_auditoria.bat'), $p)
& $p
```

En **Windows Server 2008/2008 R2** no existe `[Net.SecurityProtocolType]::Tls12` ni `Register-ScheduledTask`. Usa TLS por numero (3072) y `cmd /c`:

```powershell
$env:AUDIT_API_URL='https://api-tertius-auditoria.alvesc.com'
$env:AUDIT_API_KEY='XXXXXXXXXXX'
$p = Join-Path $env:TEMP 'ejecutar_auditoria.bat'
[Net.ServicePointManager]::CheckCertificateRevocationList = $false
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
(New-Object Net.WebClient).DownloadFile(($env:AUDIT_API_URL + '/scripts/ejecutar_auditoria.bat'), $p)
cmd /c "`"$p`""
```

Si falla con "Could not create SSL/TLS secure channel", el OS no habla TLS 1.2: instala SP2 y el hotfix [KB4019276](https://support.microsoft.com/help/4019276) (2008) o el equivalente de TLS 1.2 en 2008 R2. Sin eso un HTTPS moderno no va a conectar.

En 2008 no existe `Register-ScheduledTask`. Crea la tarea con `schtasks` (una sola linea; sustituye URL y key):

```
schtasks /Create /TN "Auditoria_Programada" /SC DAILY /ST 03:00 /RU SYSTEM /RL HIGHEST /F /TR "powershell.exe -NoProfile -Command \"[Net.ServicePointManager]::CheckCertificateRevocationList=$false; [Net.ServicePointManager]::SecurityProtocol=[Enum]::ToObject([Net.SecurityProtocolType],3072); $env:AUDIT_API_URL='https://api-tertius-auditoria.alvesc.com'; $env:AUDIT_API_KEY='XXXXXXXXXXX'; $p=Join-Path $env:TEMP 'ejecutar_auditoria.bat'; (New-Object Net.WebClient).DownloadFile(($env:AUDIT_API_URL+'/scripts/ejecutar_auditoria.bat'),$p); cmd /c $p /silent\""
```

### Tarea programada (SYSTEM)

Igual que el manual, con `/silent` para que no se quede en un `pause`. Registrar la tarea **una vez** (PowerShell elevado). Cambia hora, URL y key:

```powershell
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument @'
-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "$env:AUDIT_API_URL='https://api-tertius-auditoria.alvesc.com'; $env:AUDIT_API_KEY='XXXXXXXXXXX'; $p=Join-Path $env:TEMP 'ejecutar_auditoria.bat'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile(($env:AUDIT_API_URL + '/scripts/ejecutar_auditoria.bat'), $p); & $p /silent"
'@
$trigger = New-ScheduledTaskTrigger -Daily -At 03:00
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'Auditoria_Programada' -Action $action -Trigger $trigger -Principal $principal -Force
```

- Usuario: `SYSTEM`, "Ejecutar aunque el usuario no haya iniciado sesion"
- La key viaja en el comando de la tarea (solo admins la ven con `Get-ScheduledTaskInfo` / Task Scheduler)
- Si el equipo sale a internet con proxy autenticado por usuario, SYSTEM puede no tener salida; usar proxy/PAC de maquina

Ver `CLAUDE.md` para el detalle de cada script y las convenciones de edicion.

## Backend

Ver `server/README.md` para instalacion y despliegue.
