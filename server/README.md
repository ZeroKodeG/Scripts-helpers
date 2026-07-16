# Backend + stack de auditoria

API JSON (Express + PostgreSQL) y frontend React separado. Los scripts Windows siguen subiendo reportes con `X-API-Key`.

## Arquitectura (Docker Compose)

Servicios en la raiz del repo (`docker-compose.yml`):

| Servicio    | Puerto por defecto | Rol                                      |
|-------------|--------------------|------------------------------------------|
| `postgres`  | 5432               | Persistencia                             |
| `backend`   | 3000               | API, scripts `/scripts`, generacion PDF  |
| `frontend`  | 8080               | Dashboard React (nginx)                  |

No incluye reverse proxy/TLS: apunta tus dominios (ej. `api.` → 3000, `app.` → 8080) desde Traefik/Cloudflare/nginx externo.

## Levantar

```bash
cd server
cp .env.example .env
# editar: API_KEY, JWT_SECRET, OPENCODE_MODEL, ZAI_API_KEY, CORS_ORIGIN, VITE_API_URL
cd ..
docker compose up -d --build
```

- Frontend: `http://localhost:8080`
- API: `http://localhost:3000`
- Scripts: `http://localhost:3000/scripts/ejecutar_auditoria.bat`

`API_KEY` del `.env` **solo se usa como seed** del primer usuario `admin` si la tabla `usuarios` esta vacia. Despues las keys viven en Postgres.

`VITE_API_URL` se congela en el **build** del frontend: debe ser la URL publica del API que ve el navegador.

## Roles

| Rol        | Puede                                              |
|------------|----------------------------------------------------|
| `admin`    | Todo: reportes, generar/subir PDF, usuarios, prompt |
| `consulta` | Login, listar/filtrar, descargar TXT/PDF           |

Login web: `POST /api/auth/login` con `{ "api_key": "..." }` → JWT Bearer.

Upload desde `.bat`: header `X-API-Key` de un **admin** activo → `POST /api/reportes`.

## Endpoints principales

- `GET /healthz` — healthcheck
- `POST /api/auth/login`, `GET /api/auth/me`
- `GET /api/equipos` — JWT
- `GET /api/reportes?equipo=&fecha_desde=&fecha_hasta=&estado_pdf=` — JWT  
  `estado_pdf`: `todos` \| `generados` \| `pendientes`
- `POST /api/reportes` — X-API-Key admin
- `GET /api/reportes/:id/{sistema|red|logs|pdf}` — JWT
- `POST /api/reportes/:id/generar-pdf`, `POST /api/reportes/:id/pdf` — JWT admin
- `GET|POST|PATCH|DELETE /api/usuarios`, `POST .../regenerar-key` — JWT admin
- `GET|PUT /api/prompts/reporte_ejecutivo` — JWT admin

## Datos

- Postgres: tablas `reportes`, `usuarios`, `prompts`
- PDFs en volumen `auditoria_data` → `/app/data/pdfs`
- Prompt: se seed desde `prompts/reporte_ejecutivo.txt` si no existe en BD; luego se edita por web

### Migrar SQLite antiguo → Postgres

No hace falta `better-sqlite3` (falla en la imagen Docker sin compilador C). El script usa Python 3 (`sqlite3` de la stdlib) + el cliente `pg` ya instalado.

Dentro del contenedor backend (con el `.db` montado en `/app/data`):

```bash
# DATABASE_URL ya apunta al servicio postgres del compose
SQLITE_PATH=/app/data/auditoria.db npm run migrate:sqlite
```

En local:

```bash
cd server
DATABASE_URL=postgresql://auditoria:auditoria@localhost:5432/auditoria \
  SQLITE_PATH=./data/auditoria.db \
  npm run migrate:sqlite
```

Los PDF en `data/pdfs/` se reutilizan tal cual. Filas con el mismo `id` se omiten (`ON CONFLICT DO NOTHING`).

## Desarrollo local

Backend (Postgres local o compose solo DB):

```bash
cd server
npm install
cp .env.example .env
# DATABASE_URL apuntando a Postgres
npm run dev
```

Frontend:

```bash
cd frontend
npm install
# VITE_API_URL=http://localhost:3000
npm run dev
```

Tests backend: `cd server && npm test`

## Generacion de PDF

Igual que antes (`opencode` + renderer Python). El prompt se lee desde la tabla `prompts` (`clave = reporte_ejecutivo`). Variables: `OPENCODE_MODEL`, `OPENCODE_TIMEOUT_MS`, `ZAI_API_KEY`.
