require("dotenv").config();
const path = require("path");
const express = require("express");
const cors = require("cors");

const db = require("./db");
const { hashApiKey } = require("./auth");
const apiRoutes = require("./routes/api");

async function main() {
  if (!process.env.API_KEY) {
    console.error(
      "Falta API_KEY en el entorno (.env). Se usa como seed del primer admin si la BD esta vacia."
    );
    process.exit(1);
  }

  if (!process.env.JWT_SECRET && !process.env.SESSION_SECRET) {
    console.error("Falta JWT_SECRET (o SESSION_SECRET) en el entorno (.env).");
    process.exit(1);
  }

  if (!process.env.DATABASE_URL) {
    console.error("Falta DATABASE_URL en el entorno (.env).");
    process.exit(1);
  }

  await db.initDb({ hashApiKey });

  const app = express();
  const corsOrigin = process.env.CORS_ORIGIN || process.env.FRONTEND_URL || true;

  app.use(
    cors({
      origin: corsOrigin,
      credentials: true,
    })
  );
  app.use(express.json({ limit: "2mb" }));

  app.get("/healthz", (req, res) => res.status(200).send("ok"));

  // Scripts .bat servidos sin auth: no contienen secretos.
  app.use(
    "/scripts",
    express.static(path.join(__dirname, "..", "public", "scripts"), {
      setHeaders: (res) => res.type("text/plain"),
    })
  );

  app.use("/api", apiRoutes);

  app.get("/", (req, res) => {
    res.json({
      service: "auditoria-backend",
      health: "/healthz",
      api: "/api",
      scripts: "/scripts",
    });
  });

  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => {
    console.log(`Backend de auditoria escuchando en http://localhost:${PORT}`);
  });
}

main().catch((error) => {
  console.error("No se pudo iniciar el backend:", error);
  process.exit(1);
});
