require("dotenv").config();
const path = require("path");
const express = require("express");
const session = require("express-session");

const db = require("./db");
const apiRoutes = require("./routes/api");
const webRoutes = require("./routes/web");

if (!process.env.API_KEY) {
  console.error("Falta API_KEY en el entorno (.env). Copia .env.example a .env y completalo.");
  process.exit(1);
}

db.prepare(
  "UPDATE reportes SET pdf_status = 'error', pdf_error = 'Interrumpido por reinicio del backend' WHERE pdf_status = 'generando'"
).run();

const app = express();

app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "views"));

app.use(express.json());
app.use(
  session({
    secret: process.env.SESSION_SECRET || "cambia-este-secret",
    resave: false,
    saveUninitialized: false,
    cookie: {
      maxAge: 8 * 60 * 60 * 1000, // 8 horas
      httpOnly: true,
      sameSite: "strict",
    },
  })
);

app.get("/", (req, res) => res.redirect("/dashboard"));

// Endpoint liviano sin auth para HEALTHCHECK de Docker / probes externos.
app.get("/healthz", (req, res) => res.status(200).send("ok"));

// Scripts .bat servidos sin auth: no contienen secretos, solo logica de
// auditoria. La API key sigue exigiendose en /api/reportes para escribir.
app.use(
  "/scripts",
  express.static(path.join(__dirname, "..", "public", "scripts"), {
    setHeaders: (res) => res.type("text/plain"),
  })
);

// CSS de las paginas del dashboard - estatico, sin auth.
app.use("/css", express.static(path.join(__dirname, "..", "public", "css")));

app.use("/api", apiRoutes);
app.use("/", webRoutes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Backend de auditoria escuchando en http://localhost:${PORT}`);
});
