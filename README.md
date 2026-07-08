# Scripts-helpers

Auditoria de servidores Windows centralizada en un backend propio:

1. **Scripts cliente** (`.bat`, en `server/public/scripts/`) — se ejecutan en cada servidor Windows y generan 3 reportes de texto (sistema, red, logs). El backend los sirve directamente, no dependen de GitHub.
2. **Backend** (`server/`) — API Node.js + SQLite que sirve esos scripts, recibe los reportes, y expone un dashboard web simple para listarlos por equipo/fecha, descargarlos y adjuntarles un PDF.

## Uso rapido en un servidor

1. Configura una vez por equipo (nunca en el repo):
   - Variables de entorno `AUDIT_API_KEY` y `AUDIT_API_URL`, o
   - Archivo `%USERPROFILE%\.audit_config`:
     ```
     API_KEY=tu-api-key
     API_URL=https://tu-backend.tld
     ```
2. Ejecuta como Administrador (reemplaza la URL por tu backend):
   ```
   curl -s -o "%TEMP%\ejecutar_auditoria.bat" https://tu-backend.tld/scripts/ejecutar_auditoria.bat && "%TEMP%\ejecutar_auditoria.bat"
   ```
   Esto descarga (desde el propio backend) y corre los 3 modulos (`auditoria_sistema.bat`, `auditoria_red.bat`, `auditoria_logs.bat`), deja los `.txt` en el Escritorio, y sube los 3 reportes al backend via API key.

Ver `CLAUDE.md` para el detalle de cada script y las convenciones de edicion.

## Backend

Ver `server/README.md` para instalacion y despliegue.
