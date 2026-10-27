/**
 * Column cells probe (catalog 1.8): the pure helpers the data grid draws a
 * column's icon, "+N more" tag and detail line with. Plain Node, no
 * browser:
 *
 *   node priv/js/probe/column_cells_probe.mjs
 *
 * The detail date is checked west of Greenwich, where a date-only value is
 * most likely to drift a day. Exit code is the verdict.
 */

import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";

if (!process.env.COLUMN_CELLS_PROBE_CHILD) {
  const run = spawnSync(process.execPath, [fileURLToPath(import.meta.url)], {
    env: {...process.env, TZ: "America/Toronto", COLUMN_CELLS_PROBE_CHILD: "1"},
    encoding: "utf8",
  });
  process.stdout.write(run.stdout);
  process.stderr.write(run.stderr);
  process.exit(run.status ?? 1);
}

const {cellIcon, moreCount, detailText, CELL_ICONS, formatDisplayValue} = await import("../ash_admin_tokens.js");

const failures = [];
const expect = (label, actual, expected) => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) failures.push(`${label}: expected ${e}, got ${a}`);
};

// icons: the catalog's vocabulary, nothing else
expect("icon vocabulary", Object.keys(CELL_ICONS), ["check", "x", "user_check", "user_x", "alert", "clock", "info"]);
expect("known icon", cellIcon("user_check"), CELL_ICONS.user_check);
expect("no icon", cellIcon(""), null);
expect("unknown icon", cellIcon("rocket"), null);
expect("prototype key", cellIcon("toString"), null);

// "+N more": the rest after the first value
expect("count 3", moreCount(3), 2);
expect("count 2", moreCount(2), 1);
expect("count 1", moreCount(1), 0);
expect("count 0", moreCount(0), 0);
expect("count as string", moreCount("4"), 3);
expect("no count", moreCount(null), 0);

// detail line: the date placeholder filled, nothing left dangling
const day = formatDisplayValue("2026-11-01", "datetime");
expect("detail with date", detailText("Due {date}", "2026-11-01"), `Due ${day}`);
expect("detail without date", detailText("Overdue since {date}", null), "Overdue since");
expect("separator dropped", detailText("Scheduled · {date}", ""), "Scheduled");
expect("no placeholder", detailText("Blocked", "2026-11-01"), "Blocked");
expect("no detail", detailText("", "2026-11-01"), "");
expect("absent detail", detailText(undefined, null), "");

console.log(failures.length ? failures.join("\n") : "column cells: ok");
process.exit(failures.length ? 1 : 0);
