const { spawn } = require("node:child_process");

function runRenderer({ pythonBin = "python3", scriptPath, inputPath, outputPath, timeoutMs = 120000 }) {
  return new Promise((resolve) => {
    const child = spawn(pythonBin, [scriptPath, inputPath, outputPath], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    let settled = false;

    function resolveOnce(result) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(result);
    }

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      resolveOnce({ code: null, stdout, stderr: `${stderr}\nrenderer timeout`, timedOut: true });
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("close", (code) => {
      resolveOnce({ code, stdout, stderr, timedOut: false });
    });

    child.on("error", (error) => {
      resolveOnce({ code: null, stdout, stderr: `${stderr}\n${error.message}`, timedOut: false });
    });
  });
}

module.exports = {
  runRenderer,
};
