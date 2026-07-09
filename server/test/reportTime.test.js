const test = require("node:test");
const assert = require("node:assert/strict");

const {
  REPORT_TIME_ZONE,
  buildReportDateContext,
  formatDateForFileName,
  formatDateTimeForDisplay,
} = require("../src/reportTime");

test("formats sqlite UTC timestamps in America/Monterrey for dashboard display", () => {
  assert.equal(REPORT_TIME_ZONE, "America/Monterrey");
  assert.equal(formatDateTimeForDisplay("2026-07-09 17:55:21"), "2026-07-09 11:55:21");
});

test("uses Monterrey date when building compact file names", () => {
  assert.equal(formatDateForFileName("2026-07-10 01:30:00"), "20260709");
});

test("buildReportDateContext exposes both local date and datetime", () => {
  assert.deepEqual(buildReportDateContext("2026-07-10 01:30:00"), {
    timeZone: "America/Monterrey",
    utcDateTime: "2026-07-10 01:30:00",
    localDateTime: "2026-07-09 19:30:00",
    localDate: "2026-07-09",
    compactDate: "20260709",
  });
});
