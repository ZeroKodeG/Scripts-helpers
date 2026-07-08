# Backend de auditoria

API + dashboard web para centralizar los reportes generados por `ejecutar_auditoria.bat` en cada servidor.

## Levantar con Docker Compose (recomendado, mas rapido)

Requiere Docker + Docker Compose. Desde la raiz del repo:

```
cd server
cp .env.example .env
# editar .env: definir API_KEY y SESSION_SECRET propios
cd ..
docker compose up -d --build
```

Queda en `http://localhost:3000`. Los datos (SQLite + PDFs) persisten en `server/data/` en el host via volumen, aunque recrees el contenedor.

Comandos utiles:
```
docker compose logs -f        # ver logs
docker compose down           # parar (no borra los datos)
docker compose up -d --build  # reconstruir tras cambios de codigo
```

## Desarrollo local sin Docker

```
cd server
npm install
cp .env.example .env
# editar .env: definir API_KEY y SESSION_SECRET propios
npm start
```

Por defecto queda en `http://localhost:3000`.

## Endpoints

- Dashboard web: `http://localhost:3000/login` (pedir la misma API KEY del `.env`).
- Scripts cliente: `http://localhost:3000/scripts/ejecutar_auditoria.bat` (y los 3 modulos), servidos sin auth desde `public/scripts/`. No tienen secretos, asi que no hace falta protegerlos; lo unico protegido es la subida de reportes.
- `GET /healthz` — sin auth, usado por el `HEALTHCHECK` del Dockerfile.
- API para el script cliente:
  - `POST /api/reportes` — header `X-API-Key`, body `multipart/form-data` con `equipo`, `reporte_sistema`, `reporte_red`, `reporte_logs`.
  - `GET /api/equipos` — header `X-API-Key`, lista de equipos distintos.
  - `GET /api/reportes?equipo=NOMBRE` — header `X-API-Key`, lista de corridas ordenadas por fecha DESC.

Prueba manual:
```
curl -X POST http://localhost:3000/api/reportes \
  -H "X-API-Key: TU_API_KEY" \
  -F "equipo=PRUEBA" \
  -F "reporte_sistema=contenido de prueba" \
  -F "reporte_red=contenido de prueba" \
  -F "reporte_logs=contenido de prueba"
```

## Datos

- SQLite en `data/auditoria.db` (una fila por corrida: equipo, fecha_hora, los 3 textos de reporte, ruta del PDF si se subio).
- PDFs subidos manualmente desde el dashboard en `data/pdfs/<id>.pdf`.
- Ambos quedan fuera de git (ver `.gitignore` en la raiz del repo) y, con Docker, persisten en el host via el volumen `./server/data:/app/data` del `docker-compose.yml`.

## Despliegue en VPS

**Opcion A — Docker Compose (recomendado):**
1. Clonar el repo en el VPS, `docker compose pull` no aplica (imagen se construye local): `docker compose build`.
2. Crear `server/.env` con `API_KEY` y `SESSION_SECRET` propios (no reusar los de ejemplo). `PORT`/`DB_PATH` estan fijados en `docker-compose.yml`, no hace falta tocarlos.
3. `docker compose up -d`. El contenedor reinicia solo (`restart: unless-stopped`) si el VPS reinicia o el proceso cae.
4. Si se expone a internet, poner nginx (u otro reverse proxy) delante con HTTPS (Let's Encrypt/certbot) — no incluido en este proyecto.
5. Actualizar `AUDIT_API_URL` / `.audit_config` en cada servidor Windows para que apunte a esta URL.

**Opcion B — Node directo (sin Docker):**
1. Clonar el repo en el VPS, `cd server && npm install --production`.
2. Crear `.env` con `API_KEY`, `SESSION_SECRET` y `PORT` propios.
3. Correr con `pm2 start src/index.js --name auditoria-backend` (o un servicio systemd equivalente) para que sobreviva reinicios.
4. Mismos pasos 4 y 5 que en la Opcion A.
