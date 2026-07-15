# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

Three parts:

1. **Client scripts** — standalone Windows batch (`cmd.exe`) scripts that generate local system/network/security audit reports. No PowerShell, no dependencies beyond native Windows tools (`wmic`, `netstat`, `wevtutil`, `netsh`, `reg`, `nltest`, `curl`, etc.). No test suite; scripts are validated by running them on a real Windows host and inspecting the generated report. The 3 orchestrated modules plus the orchestrator live in `server/public/scripts/` and are served directly by the backend — not fetched from GitHub. Two older standalone variants remain at the repo root.
2. **Backend** (`server/`) — Node.js + Express + PostgreSQL (`pg`) API that serves the client scripts, receives reports via API, stores them in Postgres, manages users/API keys and the executive prompt, and runs the PDF generation pipeline. See `server/README.md` for setup/deploy.
3. **Frontend** (`frontend/`) — Vite + React SPA (nginx in Docker) that talks to the backend with JWT. Separate container/domain from the API.

## Client scripts

In `server/public/scripts/` (served statically at `/scripts/*.bat`, no auth — see Backend section):
- `auditoria_sistema.bat` — module 1/3: system info, local accounts, firewall/RDP/UAC registry state, services, running processes, group policy, domain/DC connectivity, hardware inventory. Writes `Reporte_Sistema_CMD.txt` to the Desktop and a parallel debug log `Auditoria_Sistema_LOG.txt`.
- `auditoria_red.bat` — module 2/3: network config, routing table, listening ports/established connections (`netstat`), ARP/NetBIOS neighbors, gateway/DNS connectivity checks. Writes `Reporte_Red_CMD.txt`.
- `auditoria_logs.bat` — module 3/3: Windows Security/System event log queries (`wevtutil`) for failed logons (4625), successful logons (4624), RDP logons (4624 type 10), privilege use (4672), new services (4697/7045), account/group changes (4720/4732), log-clearing events (1102, a tamper indicator), Kerberos pre-auth failures (4771), unexpected shutdowns (6008/41). Writes `Reporte_Logs_CMD.txt`.
- `ejecutar_auditoria.bat` — orchestrator: downloads the 3 module scripts fresh from the backend's own `/scripts/` route into `%TEMP%`, runs them with `/silent`, then POSTs the 3 resulting Desktop `.txt` files to `POST /api/reportes` using an `X-API-Key` header. The key must belong to an **active admin** user in Postgres. Reads `API_KEY`/`API_URL` from env vars (`AUDIT_API_KEY`/`AUDIT_API_URL`) or a local, untracked `%USERPROFILE%\.audit_config` file. The API key is only ever used for the upload step, never for downloading the scripts (that route has no auth by design — it holds no secrets).

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

- `src/index.js` — Express bootstrap. Serves `public/scripts/*.bat` statically at `/scripts` with no auth, mounts `/api` JSON router, CORS for the React origin. Requires `API_KEY` (seed), `JWT_SECRET` (or `SESSION_SECRET`), and `DATABASE_URL`. `GET /healthz` (no auth) for Docker HEALTHCHECK.
- `public/scripts/` — the client `.bat` files, served as-is. Edit them here; there is no separate copy anywhere else.
- `src/db.js` — `pg` pool; idempotent schema for `reportes`, `usuarios`, `prompts`; seeds first admin from `API_KEY` and prompt from `prompts/reporte_ejecutivo.txt` if missing.
- `src/auth.js` — SHA-256 hashes for API keys; `requireApiKey` (header `X-API-Key`, admin only, for machine upload); `requireJwt` / `requireRole` for the dashboard; login issues JWT (~8h).
- `src/routes/api.js` — mounts auth, reportes, usuarios, prompts, equipos.
- Roles: `admin` (full) and `consulta` (read/download only).
- PDF pipeline: `src/services/pdfGenerator.js` reads the prompt from Postgres (`prompts.reporte_ejecutivo`), falls back to file only when the store has no row (tests use `preferPromptFile`).
- `Dockerfile` — Node 20 + Python/reportlab + opencode; no native sqlite build step.
- `docker-compose.yml` (repo root) — `postgres` + `backend` + `frontend`; volumes `auditoria_pg` and `auditoria_data` (PDFs). No edge reverse proxy — expose two domains externally.

## Frontend (`frontend/`)

- Vite + React + React Router; JWT in `localStorage`.
- Pages: Login, Dashboard (filters: equipo, fecha desde/hasta, Generados/Pendientes), Usuarios (admin), Prompt editor (admin).
- Build arg / env: `VITE_API_URL` (public API base URL). Served by nginx in its own container.

## Editing conventions

Client scripts:
- Written in Spanish (comments, section headers, echoed output); keep new sections consistent with this.
- Structure: `@echo off`, `setlocal EnableDelayedExpansion`, `goto :inicio`, then subroutine labels (`:seccion`, `:verificar_admin`, `:detectar_subred`, `:resumen_*`) defined before `:inicio`. Follow this layout when adding new scripts or subroutines.
- All commands append to `%REPORTE%` with `>>"%REPORTE%" echo ...` or `... >> "%REPORTE%" 2>&1` — always redirect stderr too, since many `wmic`/`reg`/`net` commands fail silently without admin rights and the script should continue regardless.
- New audit sections should go through the `:seccion "[+] TITLE"` subroutine so they get consistent headers in both the console and the report file.
- When adding checks that use delayed-expansion variables inside `for`/`if` blocks, use `!var!` not `%var%`.
- **All `.bat` files must use CRLF line endings.** They're authored/edited from a non-Windows environment, and LF-only files download fine (correct byte content, correct line count) but `goto :label` becomes unreliable in `cmd.exe` — it can fail with "The system cannot find the batch label specified" even though the label is right there in the file. After editing any `.bat` file, verify with `python3 -c "print(open('FILE','rb').read().count(b'\r\n'))"` and compare to the line count; if it's 0 or lower than expected, reconvert (`data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')`) before committing.

Backend:
- Comments/identifiers in Spanish for domain terms (`equipo`, `reportes`), English for generic code — matches what's already there; don't force a full-repo language switch.
- Multi-user API keys in Postgres (roles `admin` / `consulta`) are intentional; do not revert to a single shared env-only key for auth.
