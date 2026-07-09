const REPORT_TIME_ZONE = "America/Monterrey";

function parseSqliteUtc(value) {
  if (!value) {
    return null;
  }

  const normalized = String(value).trim().replace(" ", "T");
  const date = new Date(`${normalized}Z`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function formatParts(date, options) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: REPORT_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    ...options,
  })
    .formatToParts(date)
    .reduce((acc, part) => {
      if (part.type !== "literal") {
        acc[part.type] = part.value;
      }
      return acc;
    }, {});
}

function formatDateTimeForDisplay(value) {
  const date = parseSqliteUtc(value);
  if (!date) {
    return value || "";
  }

  const parts = formatParts(date, {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });

  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second}`;
}

function formatDateForFileName(value) {
  const date = parseSqliteUtc(value);
  if (!date) {
    return "sin-fecha";
  }

  const parts = formatParts(date, {});
  return `${parts.year}${parts.month}${parts.day}`;
}

function buildReportDateContext(value) {
  const dateTime = formatDateTimeForDisplay(value);
  const compactDate = formatDateForFileName(value);
  return {
    timeZone: REPORT_TIME_ZONE,
    utcDateTime: value || "",
    localDateTime: dateTime,
    localDate: compactDate === "sin-fecha" ? "" : `${compactDate.slice(0, 4)}-${compactDate.slice(4, 6)}-${compactDate.slice(6, 8)}`,
    compactDate,
  };
}

module.exports = {
  REPORT_TIME_ZONE,
  buildReportDateContext,
  formatDateForFileName,
  formatDateTimeForDisplay,
  parseSqliteUtc,
};
