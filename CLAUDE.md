# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

Two parts:

1. **Client scripts** — standalone Windows batch (`cmd.exe`) scripts that generate local system/network/security audit reports. No PowerShell, no dependencies beyond native Windows tools (`wmic`, `netstat`, `wevtutil`, `netsh`, `reg`, `nltest`, `curl`, etc.). No test suite; scripts are validated by running them on a real Windows host and inspecting the generated report. The 3 orchestrated modules plus the orchestrator live in `server/public/scripts/` and are served directly by the backend (see below) — not fetched from GitHub. Two older standalone variants remain at the repo root.
2. **Backend** (`server/`) — Node.js + Express + better-sqlite3 app that serves the client scripts, receives the 3 reports from each server via API, stores them in SQLite, and serves a minimal EJS dashboard to browse/download reports and attach a PDF per run. See `server/README.md` for setup/deploy.

## Client scripts

In `server/public/scripts/` (served statically at `/scripts/*.bat`, no auth — see Backend section):
- `auditoria_sistema.bat` — module 1/3: system info, local accounts, firewall/RDP/UAC registry state, services, running processes, group policy, domain/DC connectivity, hardware inventory. Writes `Reporte_Sistema_CMD.txt` to the Desktop and a parallel debug log `Auditoria_Sistema_LOG.txt`.
- `auditoria_red.bat` — module 2/3: network config, routing table, listening ports/established connections (`netstat`), ARP/NetBIOS neighbors, gateway/DNS connectivity checks. Writes `Reporte_Red_CMD.txt`.
- `auditoria_logs.bat` — module 3/3: Windows Security/System event log queries (`wevtutil`) for failed logons (4625), successful logons (4624), RDP logons (4624 type 10), privilege use (4672), new services (4697/7045), account/group changes (4720/4732), log-clearing events (1102, a tamper indicator), Kerberos pre-auth failures (4771), unexpected shutdowns (6008/41). Writes `Reporte_Logs_CMD.txt`.
- `ejecutar_auditoria.bat` — orchestrator: downloads the 3 module scripts fresh from the backend's own `/scripts/` route into `%TEMP%`, runs them with `/silent`, then POSTs the 3 resulting Desktop `.txt` files to `POST /api/reportes` using an `X-API-Key` header. Reads `API_KEY`/`API_URL` from env vars (`AUDIT_API_KEY`/`AUDIT_API_URL`) or a local, untracked `%USERPROFILE%\.audit_config` file. The API key is only ever used for the upload step, never for downloading the scripts (that route has no auth by design — it holds no secrets).

At the repo root:
- `analisis-windows.bat` / `audit_cmd.bat` — earlier/simpler single-file variants that combine system+network+account+log auditing into one report (`Reporte_CMD.txt`) without the 3-module split. Not part of the orchestrated flow, not served by the backend.

Each of the three "module" scripts is self-contained and can be run independently, in sequence, or via `ejecutar_auditoria.bat` to build a full audit picture and push it to the backend.

## Running the scripts

These only run on Windows (`cmd.exe`); they cannot be executed on macOS/Linux. Run as Administrator for complete results — scripts check for admin privileges via `net session` and note in the report when they were not run elevated.

Common flags (module scripts):
- `/silent` — suppress the trailing `pause` so the script exits without waiting for a keypress.
- `/debug` (`auditoria_sistema.bat` only) — prints extra diagnostics (line count, `errorlevel` after each section) and keeps the temp report file instead of deleting it after copying to the Desktop; useful when antivirus (the scripts specifically call out Kaspersky) truncates the `.bat` file, since a mismatched line count reveals that.

Report generation pattern: each module writes to a randomized temp file (`%TEMP%\Audit<Name>_%COMPUTERNAME%_%RANDOM%.txt`) via a `:seccion` subroutine, then copies the result to a fixed filename on the Desktop at the end. This avoids partial/locked-file issues if a previous report is open in Notepad.

## Backend (`server/`)

- `src/index.js` — Express bootstrap. Serves `public/scripts/*.bat` statically at `/scripts` with no auth (client scripts have no secrets in them), mounts `/api` (API-key auth) and `/` (session/cookie auth) routers, requires `API_KEY` env var to start. `GET /healthz` (no auth) exists solely for the Docker `HEALTHCHECK`.
- `public/scripts/` — the client `.bat` files, served as-is. Edit them here; there is no separate copy anywhere else.
- `src/db.js` — opens `better-sqlite3` at `DB_PATH`, creates the single `reportes` table (`equipo`, `fecha_hora`, `reporte_sistema`, `reporte_red`, `reporte_logs`, `pdf_path`) if missing.
- `src/auth.js` — `requireApiKey` (header `X-API-Key`, timing-safe compare) for the client script; `requireSession` (cookie via `express-session`) for the dashboard. Both check against the same single shared `API_KEY` — there are no per-user accounts by design.
- `src/routes/api.js` — machine-facing endpoints used by `ejecutar_auditoria.bat`: `POST /api/reportes`, `GET /api/equipos`, `GET /api/reportes`.
- `src/routes/web.js` — human-facing endpoints: `/login`, `/dashboard`, per-report `.txt` downloads, PDF upload/download (`multer`, stored at `data/pdfs/<id>.pdf`).
- `src/views/*.ejs` — server-rendered HTML, no frontend build step or JS framework.
- `Dockerfile` — multi-stage: `deps` stage compiles `better-sqlite3`'s native binding (needs `python3`/`make`/`g++`), final stage copies only `node_modules` + app code, no compiler toolchain in the runtime image. Exposes `/healthz` as the `HEALTHCHECK`.
- `docker-compose.yml` (repo root) — single `backend` service, builds from `server/`, reads secrets from `server/.env` (`env_file`), pins `PORT`/`DB_PATH` in `environment:` so they can't drift from what the container actually uses, persists `server/data/` via a bind-mounted volume.
- Run/deploy: see `server/README.md`. `docker compose up -d --build` is the recommended path; plain Node + `pm2`/systemd works too without Docker.

## Editing conventions

Client scripts:
- Written in Spanish (comments, section headers, echoed output); keep new sections consistent with this.
- Structure: `@echo off`, `setlocal EnableDelayedExpansion`, `goto :inicio`, then subroutine labels (`:seccion`, `:verificar_admin`, `:detectar_subred`, `:resumen_*`) defined before `:inicio`. Follow this layout when adding new scripts or subroutines.
- All commands append to `%REPORTE%` with `>>"%REPORTE%" echo ...` or `... >> "%REPORTE%" 2>&1` — always redirect stderr too, since many `wmic`/`reg`/`net` commands fail silently without admin rights and the script should continue regardless.
- New audit sections should go through the `:seccion "[+] TITLE"` subroutine so they get consistent headers in both the console and the report file.
- When adding checks that use delayed-expansion variables inside `for`/`if` blocks, use `!var!` not `%var%`.

Backend:
- Comments/identifiers in Spanish for domain terms (`equipo`, `reportes`), English for generic code — matches what's already there; don't force a full-repo language switch.
- Keep the single-shared-API-key model unless the user explicitly asks for per-user auth — it's an intentional simplicity tradeoff, not an oversight.
