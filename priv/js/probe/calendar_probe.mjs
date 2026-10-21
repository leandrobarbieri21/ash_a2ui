/**
 * Calendar probe — the browser gate for `display :calendar` (AST-173):
 *
 *   admin catalog (MonthUI under admin_v1)
 *     - the calendarView paints the window month with its marked days and
 *       wraps the table's dataGrid (the window's rows);
 *     - picking a day highlights it at once and dispatches `query` with
 *       the picked ISO date; the reply narrows the grid and the heading;
 *     - Next month paints the next month at once and dispatches the
 *       ABSOLUTE anchor; two quick clicks dispatch two anchors, and the
 *       stale reply of the first does not move the grid back;
 *     - Today dispatches today's date as the anchor;
 *     - nothing logs an error.
 *   admin catalog, a switchable calendar (SwitchUI: month, week, day)
 *     - the Month/Week/Day switch shows with Month pressed;
 *     - Week dispatches `query` with granularity "week";
 *     - the reply paints a one-week grid and lists that week's rows.
 *   basic composition (stock basic catalog and the AshA2ui merged one)
 *     - the agenda renders: window label, one Button per marked day, the
 *       rows with their date text; a day Button dispatches `query` with
 *       its date.
 *
 * Fixtures are recorded wire payloads:
 *
 *     MIX_ENV=test mix run priv/js/probe/record_calendar.exs
 *
 * Run:
 *
 *     node priv/js/probe/calendar_probe.mjs [--node-modules DIR] [--port N]
 *
 * `--node-modules` is any tree with @a2ui/lit + @a2ui/web_core 0.10.x and
 * lit 3. Chrome comes from $CHROME, Playwright from
 * $PLAYWRIGHT_NODE_MODULES. Exit code is the verdict.
 */

import {cpSync, mkdirSync, mkdtempSync, rmSync, symlinkSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join, resolve} from "node:path";
import {spawn} from "node:child_process";

const probeDir = dirname(fileURLToPath(import.meta.url));
const repoPrivJs = resolve(probeDir, "..");

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const index = args.indexOf(`--${name}`);
  return index !== -1 ? args[index + 1] : fallback;
};
const nodeModules = arg("node-modules", join(repoPrivJs, "../../../clinic-demo/assets/node_modules"));
const port = Number(arg("port", "4193"));
const executablePath = process.env.CHROME || "/usr/bin/google-chrome";
const playwrightModule = `${process.env.PLAYWRIGHT_NODE_MODULES ?? "/home/lukegalea/vendorpm/quality-assurance/node_modules"}/playwright/index.mjs`;
const {chromium} = await import(playwrightModule);

const results = [];
const failures = [];

async function check(label, fn) {
  try {
    await fn();
    results.push(`ok    ${label}`);
  } catch (error) {
    failures.push(`FAIL  ${label}: ${error.message.split("\n")[0]}`);
  }
}

const expect = (actual, expected, note = "") => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${note} expected ${e}, got ${a}`);
};

const truthy = (value, note) => {
  if (!value) throw new Error(`${note} (got ${JSON.stringify(value)})`);
};

async function serve() {
  const root = mkdtempSync(join("/tmp", "calendar-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "calendar_probe.html"), join(root, "calendar_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/calendar_probe.html`, {method: "HEAD"});
      break;
    } catch {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  return {
    base,
    stop: () => {
      server.kill();
      rmSync(root, {recursive: true, force: true});
    },
  };
}

async function openCase(browser, base, query, viewport = {width: 1280, height: 900}) {
  const page = await browser.newPage({viewport});
  const errors = [];
  page.on("pageerror", (error) => errors.push(`PAGEERROR: ${error.message.slice(0, 200)}`));
  page.on("console", (message) => {
    if (message.type() === "error") {
      if (message.location()?.url?.includes("favicon")) return;
      errors.push(`CONSOLE: ${message.text().slice(0, 200)}`);
    }
  });
  page.__errors = errors;
  await page.goto(`${base}/calendar_probe.html?${query}`, {waitUntil: "load"});
  await page.waitForFunction(() => window.__boot?.stage && window.__boot.stage !== "imports-done");
  await page.waitForTimeout(600);
  const stage = await page.evaluate(() => window.__boot);
  if (stage.stage === "error") throw new Error(`boot failed: ${stage.error}`);
  await page.evaluate(() => {
    window.__deepAll = (selector) => {
      const found = [];
      const search = (root) => {
        for (const element of root.querySelectorAll(selector)) found.push(element);
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) search(element.shadowRoot);
        }
      };
      search(document);
      return found;
    };
    window.__deepText = (root) => {
      let text = "";
      const walk = (node) => {
        for (const child of node.childNodes) {
          if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
          else walk(child);
        }
        if (node.shadowRoot) walk(node.shadowRoot);
      };
      walk(root);
      return text.replace(/\s+/g, " ").trim();
    };
    window.__cal = () => window.__deepAll("nb-calendar")[0] ?? null;
    window.__calTitle = () => window.__cal()?.shadowRoot.querySelector(".title")?.textContent.trim();
    window.__marked = () =>
      [...(window.__cal()?.shadowRoot.querySelectorAll("button.day--items") ?? [])].map((b) => b.dataset.date);
    window.__selectedDay = () =>
      window.__cal()?.shadowRoot.querySelector("button.day--selected")?.dataset.date ?? null;
    window.__gridTitles = () =>
      window.__deepAll(".grid-table tbody tr th").map((th) => th.textContent.trim());
  });
  return page;
}

async function feed(page, name) {
  await page.evaluate((fixture) => window.__feedFixture(fixture), name);
  await page.waitForTimeout(300);
}

const lastDispatch = (page) => page.evaluate(() => window.__dispatched.at(-1) ?? null);

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath});

  try {
    /* --- admin: the calendarView ----------------------------------------- */
    const page = await openCase(browser, base, "payload=calendar_admin");

    await check("admin: the window month paints with its marked days", async () => {
      const state = await page.evaluate(() => ({
        title: window.__calTitle(),
        marked: window.__marked(),
        rows: window.__gridTitles(),
      }));
      expect(state.title, "October 2026", "calendar title");
      expect(state.marked, ["2026-10-03", "2026-10-16", "2026-10-17", "2026-10-18"], "marked days");
      // Same-day rows tie-break on the (random) primary key.
      expect(state.rows[0], "Kickoff", "date order");
      expect([...state.rows].sort(), ["Boiler service", "Kickoff", "Offsite"], "the grid holds the window rows");
    });

    await check("admin: picking a day highlights it at once and dispatches its date", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        window.__cal().shadowRoot.querySelector('button.day[data-date="2026-10-16"]').click();
      });
      const immediate = await page.evaluate(() => window.__selectedDay());
      expect(immediate, "2026-10-16", "selected before any reply");
      const sent = await lastDispatch(page);
      expect(sent.name, "query", "action");
      expect(sent.context.date, "2026-10-16", "picked date");
      expect(sent.context.component, "schedule", "component");
      expect(sent.context.query.window.anchor, "2026-10-01", "carried window");
    });

    await check("admin: the pick reply narrows the grid and the heading", async () => {
      await feed(page, "calendar_admin_pick");
      const state = await page.evaluate(() => ({
        rows: window.__gridTitles().sort(),
        selected: window.__selectedDay(),
        text: window.__deepText(window.__deepAll("ash-admin-calendar-view")[0]),
      }));
      expect(state.rows, ["Boiler service", "Offsite"], "the picked day's rows");
      expect(state.selected, "2026-10-16", "the pick stays highlighted");
      truthy(/October 16, 2026/.test(state.text), "the heading names the day");
      truthy(/All days/.test(state.text), "an All days control is offered");
    });

    await check("admin: Next paints at once and dispatches absolute anchors", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        window.__cal().shadowRoot.querySelector(".next").click();
      });
      expect(await page.evaluate(() => window.__calTitle()), "November 2026", "November at once");
      await page.evaluate(() => window.__cal().shadowRoot.querySelector(".next").click());
      expect(await page.evaluate(() => window.__calTitle()), "December 2026", "December at once");
      const anchors = await page.evaluate(() => window.__dispatched.map((d) => d.context.anchor));
      expect(anchors, ["2026-11-01", "2026-12-01"], "absolute anchors, not deltas");
    });

    await check("admin: a stale reply does not move the grid back", async () => {
      await feed(page, "calendar_admin_november");
      expect(await page.evaluate(() => window.__calTitle()), "December 2026", "still December");
      await feed(page, "calendar_admin_december");
      const state = await page.evaluate(() => ({
        title: window.__calTitle(),
        marked: window.__marked(),
        rows: window.__gridTitles(),
      }));
      expect(state.title, "December 2026", "December after its own reply");
      expect(state.marked, ["2026-12-09"], "December's marks");
      expect(state.rows, ["Year-end walk"], "December's rows");
    });

    await check("admin: Today dispatches today's date", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        const view = window.__deepAll("ash-admin-calendar-view")[0];
        [...view.shadowRoot.querySelectorAll("button")].find((b) => b.textContent.trim() === "Today").click();
      });
      const sent = await lastDispatch(page);
      const today = await page.evaluate(() => {
        const d = new Date();
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
      });
      expect(sent.context.anchor, today, "today's anchor");
    });

    await check("admin: no console errors", async () => {
      expect(page.__errors, [], "errors");
    });

    await page.close();

    // A fresh page for the screenshot: no request of its own in flight.
    const shot = await openCase(browser, base, "payload=calendar_admin");
    await feed(shot, "calendar_admin_pick");
    await check("admin: a reply with no request in flight sets the pick", async () => {
      expect(await shot.evaluate(() => window.__selectedDay()), "2026-10-16", "selected");
    });
    await shot.screenshot({path: join(probeDir, "screenshots", "calendar_admin.png"), fullPage: true});
    await shot.close();

    /* --- admin: the month/week/day switch -------------------------------- */
    const switcher = await openCase(browser, base, "payload=calendar_switch");
    const sizes = () =>
      switcher.evaluate(() => {
        const view = window.__deepAll("ash-admin-calendar-view")[0];
        return [...view.shadowRoot.querySelectorAll(".cal-sizes button")].map((b) => ({
          label: b.textContent.trim(),
          pressed: b.getAttribute("aria-pressed"),
        }));
      });

    await check("admin switch: Month, Week and Day show, Month pressed", async () => {
      expect(
        await sizes(),
        [
          {label: "Month", pressed: "true"},
          {label: "Week", pressed: "false"},
          {label: "Day", pressed: "false"},
        ],
        "the switch",
      );
      expect(await switcher.evaluate(() => window.__cal().getAttribute("view")), "month", "grid view");
    });

    await check("admin switch: Week dispatches the granularity", async () => {
      await switcher.evaluate(() => {
        window.__dispatched.length = 0;
        const view = window.__deepAll("ash-admin-calendar-view")[0];
        [...view.shadowRoot.querySelectorAll(".cal-sizes button")]
          .find((b) => b.textContent.trim() === "Week")
          .click();
      });
      const sent = await lastDispatch(switcher);
      expect(sent?.name, "query", "action");
      expect(sent?.context?.granularity, "week", "granularity");
    });

    await check("admin switch: the reply paints the week and its rows", async () => {
      await feed(switcher, "calendar_switch_week");
      const state = await switcher.evaluate(() => ({
        view: window.__cal().getAttribute("view"),
        rows: window.__gridTitles().sort(),
      }));
      expect(state.view, "week", "grid view");
      expect(state.rows, ["Boiler service", "Offsite"], "the picked day's rows");
      expect((await sizes()).find((size) => size.pressed === "true")?.label, "Week", "Week pressed");
    });

    await check("admin switch: no console errors", async () => {
      expect(switcher.__errors, [], "errors");
    });

    await switcher.screenshot({path: join(probeDir, "screenshots", "calendar_switch_week.png"), fullPage: true});
    await switcher.close();

    /* --- basic composition --------------------------------------------- */
    for (const catalog of ["stock", "merged"]) {
      const query = catalog === "stock" ? "payload=calendar_basic&catalog=stock" : "payload=calendar_basic";
      const basic = await openCase(browser, base, query);

      await check(`basic (${catalog}): the agenda renders`, async () => {
        const text = await basic.evaluate(() => window.__deepText(document.getElementById("host")));
        truthy(text.includes("2026-10"), "window label");
        for (const label of ["2026-10-03 (1)", "2026-10-16 (2)", "Previous", "Next", "Today", "All days"]) {
          truthy(text.includes(label), `shows ${label}`);
        }
        for (const title of ["Kickoff", "Boiler service", "Offsite"]) truthy(text.includes(title), `row ${title}`);
        truthy(text.includes("2026-10-16 – 2026-10-18"), "a row's date text");
        truthy(!text.includes("Blue team only"), "another team's event is not there");
      });

      await check(`basic (${catalog}): a day button dispatches its date`, async () => {
        await basic.evaluate(() => {
          window.__dispatched.length = 0;
          window
            .__deepAll("button")
            .find((b) => window.__deepText(b) === "2026-10-03 (1)")
            .click();
        });
        await basic.waitForTimeout(100);
        const sent = await lastDispatch(basic);
        expect(sent?.name, "query", "action");
        expect(sent?.context?.date, "2026-10-03", "date");
      });

      await check(`basic (${catalog}): no console errors`, async () => {
        expect(basic.__errors, [], "errors");
      });

      await basic.screenshot({
        path: join(probeDir, "screenshots", `calendar_basic_${catalog}.png`),
        fullPage: true,
      });
      await basic.close();
    }
  } finally {
    await browser.close();
    stop();
  }

  for (const line of results) console.log(line);
  for (const line of failures) console.log(line);
  console.log(`\n${results.length} passed, ${failures.length} failed`);
  process.exit(failures.length === 0 ? 0 : 1);
}

await main();
