/**
 * Date-only display probe: `formatDisplayValue("2026-12-31", "datetime")`
 * must show 31 December in every time zone, not 30 December west of
 * Greenwich. Plain Node, no browser:
 *
 *   node priv/js/probe/dates_probe.mjs
 *
 * Node reads TZ once at start, so the probe re-runs itself once per zone and
 * checks each run against the same day formatted in UTC. Exit code is the
 * verdict.
 */

import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";

const ZONES = ["America/Toronto", "America/Vancouver", "Pacific/Honolulu", "UTC", "Asia/Tokyo", "Pacific/Kiritimati"];
const DAYS = ["2026-12-31", "2026-01-01", "2026-03-08", "2026-11-01", " 2026-06-15 "];

if (process.env.DATES_PROBE_ZONE) {
  const {formatDisplayValue} = await import("../ash_admin_tokens.js");
  const utc = new Intl.DateTimeFormat(undefined, {dateStyle: "medium", timeZone: "UTC"});
  const failures = [];

  for (const day of DAYS) {
    const [year, month, date] = day.trim().split("-").map(Number);
    const expected = utc.format(Date.UTC(year, month - 1, date));
    const actual = formatDisplayValue(day, "datetime");
    if (actual !== expected) failures.push(`${JSON.stringify(day)}: got ${actual}, want ${expected}`);
  }

  console.log(`${process.env.DATES_PROBE_ZONE}: ${failures.length ? failures.join("; ") : "ok"}`);
  process.exit(failures.length ? 1 : 0);
}

let failed = false;
for (const zone of ZONES) {
  const run = spawnSync(process.execPath, [fileURLToPath(import.meta.url)], {
    env: {...process.env, TZ: zone, DATES_PROBE_ZONE: zone},
    encoding: "utf8",
  });
  process.stdout.write(run.stdout + run.stderr);
  if (run.status !== 0) failed = true;
}
process.exit(failed ? 1 : 0);
