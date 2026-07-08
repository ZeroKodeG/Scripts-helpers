# Generacion automatica de PDF ejecutivo con opencode

## Contexto

El dashboard ya recibe y almacena los tres reportes de auditoria por equipo: sistema, red y logs. Hoy el PDF ejecutivo se genera manualmente fuera del backend: el usuario pasa esos tres `.txt` a opencode con un prompt guardado, opencode genera y ejecuta un script Python, y luego el PDF final se sube a mano al dashboard.

El nuevo flujo agrega un boton `Generar PDF` en cada fila del dashboard. El backend lanza `opencode` en el VPS con los tres reportes de esa fila y un prompt versionado. Cuando termina, el PDF generado queda asociado automaticamente al reporte.

## Decisiones

- La generacion corre en el VPS donde corre el backend Node.
- Node solo lanza `opencode`; no ejecuta directamente el script Python generado.
- La UX es asincrona: click, estado `Generando...`, refresco automatico y link de descarga al finalizar.
- El modelo se configura una sola vez por ambiente con `OPENCODE_MODEL`.
- La cola es en memoria con concurrencia 1.
- No se agrega worker persistente, Redis, BullMQ, streaming de logs ni selector de modelo por reporte.
- El prompt se versiona como `server/prompts/reporte_ejecutivo.txt` con placeholder editable por el usuario.

## Base De Datos

`server/src/db.js` mantiene la creacion actual de la tabla `reportes` y agrega migraciones idempotentes con `PRAGMA table_info(reportes)` antes de cada `ALTER TABLE ADD COLUMN`.

Columnas nuevas:

- `pdf_status TEXT NOT NULL DEFAULT 'pendiente'`: valores esperados `pendiente`, `generando`, `listo`, `error`.
- `pdf_error TEXT`: ultimo error visible para el dashboard, truncado.

En `server/src/index.js`, al arrancar el backend se ejecuta:

```sql
UPDATE reportes
SET pdf_status = 'error', pdf_error = 'Interrumpido por reinicio del backend'
WHERE pdf_status = 'generando'
```

Esto evita filas colgadas si Node se reinicia mientras una generacion esta corriendo.

Cuando se sube un PDF manualmente por `POST /reportes/:id/pdf`, tambien se actualiza `pdf_status='listo'`, se limpia `pdf_error` y se mantiene `pdf_path`.

## Prompt Versionado

Se agrega `server/prompts/reporte_ejecutivo.txt`.

El archivo inicial contiene un placeholder claro, sin secretos, con el marcador `REEMPLAZAR_PROMPT_EJECUTIVO`. El servicio valida el contenido antes de llamar a opencode. Si el archivo falta o todavia contiene ese marcador, la fila pasa a `error` con un mensaje explicito para reemplazar el prompt.

El prompt debe referirse a estos nombres fijos dentro del directorio de trabajo:

- `reporte_sistema.txt`
- `reporte_red.txt`
- `reporte_logs.txt`

## Servicio De Generacion

Se agrega `server/src/services/pdfGenerator.js`.

Responsabilidades:

- Mantener una cola en memoria con concurrencia 1.
- Evitar duplicados si el mismo `id` ya esta en cola o tiene `pdf_status='generando'`.
- Marcar `pdf_status='generando'` inmediatamente al encolar para feedback rapido.
- Procesar un reporte por vez.
- Crear un directorio temporal aislado en `server/data/tmp/<id>-<random>/`.
- Escribir `reporte_sistema.txt`, `reporte_red.txt` y `reporte_logs.txt` con el contenido de la fila.
- Leer `server/prompts/reporte_ejecutivo.txt`.
- Lanzar `opencode run --auto --model <OPENCODE_MODEL> --dir <workDir> --format json <prompt>`.
- Aplicar timeout con `OPENCODE_TIMEOUT_MS`, default `600000`.
- Capturar `stderr` y truncarlo a un maximo razonable, por ejemplo 2000 caracteres.
- Al finalizar, buscar un `*.pdf` en el directorio temporal.
- Si el proceso sale con codigo 0 y hay PDF, moverlo a `server/data/pdfs/<id>.pdf`, setear `pdf_path='<id>.pdf'`, `pdf_status='listo'` y limpiar `pdf_error`.
- Si el proceso falla, no genera PDF o la configuracion es invalida, setear `pdf_status='error'` y `pdf_error`.
- Borrar siempre el directorio temporal al terminar, tanto en exito como en error.
- Continuar con el siguiente elemento de la cola.

Configuracion requerida:

- `OPENCODE_MODEL`: obligatorio para generar PDFs.
- `OPENCODE_TIMEOUT_MS`: opcional, default `600000`.
- API key del proveedor elegido: nombre segun proveedor, documentado en README.

## Rutas Web

En `server/src/routes/web.js` se agrega:

```text
POST /reportes/:id/generar-pdf
```

La ruta usa el mismo patron existente:

- `router.param("id")` valida que el id sea numerico.
- `requireSession` exige login.
- `requireCsrf` protege el POST.
- La ruta llama a `encolarGeneracion(id)` y redirige a `/dashboard` sin esperar a que termine opencode.

El `GET /dashboard` selecciona tambien `pdf_status` y `pdf_error`, ademas de `pdf_path`.

## Dashboard

La vista real es `server/src/views/dashboard.ejs`.

La celda PDF muestra cuatro estados:

- `listo`: badge verde `PDF ✓ Descargar` y link chico `Regenerar`.
- `generando`: badge neutro `Generando...`, sin acciones.
- `error`: badge rojo con mensaje corto y boton `Reintentar`.
- `pendiente`: boton `Generar PDF` y el formulario manual de subida como alternativa.

Si alguna fila tiene `pdf_status === 'generando'`, el HTML incluye refresco automatico cada 8 segundos. Si no hay generaciones en curso, no se refresca la pagina.

Los estilos se agregan en `server/public/css/style.css`, reutilizando variables existentes. Se agrega `.badge-error` usando `--danger` y `--danger-soft`, y clases pequenas para formularios/botones inline cuando hagan falta.

## Docker Y Entorno

El `server/Dockerfile` debe:

- Instalar opencode en la imagen final usando el metodo oficial confirmado al implementar.
- Copiar `prompts/` con `COPY prompts ./prompts`.

`server/.env.example` agrega:

```dotenv
OPENCODE_MODEL=provider/modelo
OPENCODE_TIMEOUT_MS=600000
# Ejemplo segun proveedor elegido:
# OPENAI_API_KEY=...
# ZHIPU_API_KEY=...
```

El `docker-compose.yml` debe leer secretos desde `server/.env` con `env_file: ./server/.env`, alineado con el README y con la convencion documentada del proyecto. Se mantienen `PORT` y `DB_PATH` fijados en `environment` para que no deriven accidentalmente, y las credenciales nuevas de opencode/proveedor entran por `env_file`.

## Seguridad

`opencode run --auto` puede aprobar permisos y ejecutar codigo generado por el LLM en el VPS. En este diseno no hay sandboxing fuerte. Las mitigaciones son limitadas:

- Directorio de trabajo temporal por reporte.
- Timeout del proceso.
- Cola con concurrencia 1.
- Prompt versionado y controlado por el usuario.
- Entradas provenientes de reportes internos.

Este riesgo debe quedar documentado en `server/README.md`.

## Verificacion

Verificaciones esperadas:

- Crear reporte de prueba via `POST /api/reportes`.
- Desde el dashboard, hacer click en `Generar PDF`.
- Confirmar que la fila pasa a `Generando...`.
- Confirmar que al terminar aparece el link de descarga y que `server/data/pdfs/<id>.pdf` existe.
- Probar error con `OPENCODE_MODEL` invalido y confirmar estado `error` + boton `Reintentar`.
- Reiniciar Node mientras una fila esta en `generando` y confirmar que al arrancar queda en `error`.
- Construir Docker y confirmar que el binario `opencode` y las variables de entorno funcionan dentro del contenedor.

## Fuera De Alcance

- Selector de modelo por reporte.
- Worker separado local o remoto.
- Cola persistente.
- Streaming de progreso en vivo.
- Rate limiting especifico por usuario o por reporte.
