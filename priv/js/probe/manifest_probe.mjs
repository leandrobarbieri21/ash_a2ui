/**
 * AshA2ui.Manifest probe — the browser gate for the manifest and the
 * selection attributes the catalogs draw for it. Per recorded case (both
 * catalogs, a translated one, and the admin grid's narrow layout):
 *
 *   - every table's `component_id` names a rendered element, and each of its
 *     rows is found by `data-a2ui-row-id` (one visible element per record);
 *   - every row action renders on exactly the rows its `visible_when` (the
 *     server's `_visible_<action>` verdict) allows, as a control carrying
 *     `data-a2ui-action` whose button's accessible name is the manifest's
 *     `label`;
 *   - clicking it dispatches for that row: directly, or (`confirm`) through
 *     a prompt whose inputs are labelled with the `prompt_fields` labels, or
 *     a destructive confirmation, whose confirm button's accessible name is
 *     the manifest's `confirm_label`;
 *   - roles: the admin grid's rows are `row`s of a table named by the
 *     table's `label`; the basic composition has no `row` at all (why the
 *     attributes exist);
 *   - no console errors.
 *
 * Fixtures are recorded wire payloads plus manifests (synthetic data):
 *
 *     MIX_ENV=test mix run priv/js/probe/record_manifest.exs
 *
 * Run:
 *
 *     node priv/js/probe/manifest_probe.mjs [--node-modules DIR] [--port N]
 *
 * `--node-modules` is any tree with @a2ui/lit + @a2ui/web_core 0.10.x or
 * 0.11.x and lit 3. Chrome comes from $CHROME, Playwright from
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
const port = Number(arg("port", "4198"));
const executablePath = process.env.CHROME || "/usr/bin/google-chrome";
const playwrightModule = `${process.env.PLAYWRIGHT_NODE_MODULES ?? `${process.cwd()}/node_modules`}/playwright/index.mjs`;
const {chromium} = await import(playwrightModule);

const results = [];
const failures = [];

async function check(label, fn) {
  try {
    await fn();
    results.push(`ok    ${label}`);
    if (process.env.VERBOSE) console.log(`ok    ${label}`);
  } catch (error) {
    failures.push(`FAIL  ${label}: ${error.message.split("\n")[0]}`);
    if (process.env.VERBOSE) console.log(failures[failures.length - 1]);
  }
}

const expect = (actual, expected, note = "") => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${note} expected ${e}, got ${a}`);
};

async function serve() {
  const root = mkdtempSync(join("/tmp", "manifest-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "manifest_probe.html"), join(root, "manifest_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--bind", "127.0.0.1", "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/manifest_probe.html`, {method: "HEAD"});
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

async function openCase(browser, base, name, viewport = {width: 1280, height: 900}) {
  const page = await browser.newPage({viewport});
  // A missing element fails its check in seconds, not after Playwright's 30.
  page.setDefaultTimeout(3000);
  const errors = [];
  page.on("pageerror", (error) => errors.push(`PAGEERROR: ${error.message.slice(0, 200)}`));
  page.on("console", (message) => {
    if (message.type() === "error") {
      if (message.location()?.url?.includes("favicon")) return;
      errors.push(`CONSOLE: ${message.text().slice(0, 200)}`);
    }
  });
  page.__errors = errors;
  await page.goto(`${base}/manifest_probe.html?payload=${name}`, {waitUntil: "load", timeout: 30000});
  await page.waitForFunction(() => window.__boot?.stage && window.__boot.stage !== "imports-done");
  await page.waitForTimeout(600);
  const stage = await page.evaluate(() => window.__boot);
  if (stage.stage === "error") throw new Error(`boot failed: ${stage.error}`);
  return page;
}

const manifestOf = (page) => page.evaluate(() => window.__manifest);
const rowsOf = (page, path) => page.evaluate((p) => window.__surface.dataModel.get(p) || [], path);
const dispatched = (page) => page.evaluate(() => window.__dispatched.splice(0));

// The rendered row of `record` in `table`: the element carrying both the
// table's component id and the row id (basic), or a row inside the element
// carrying the component id (admin grid). Playwright's CSS crosses shadow
// roots; only the visible one counts (the admin grid draws a table and a
// card list, one of them hidden by the viewport).
function rowLocator(page, table, id) {
  const cid = JSON.stringify(table.component_id);
  const rid = JSON.stringify(String(id));
  return page
    .locator(`[data-a2ui-id=${cid}][data-a2ui-row-id=${rid}], [data-a2ui-id=${cid}] [data-a2ui-row-id=${rid}]`)
    .filter({visible: true});
}

const offered = (row, action) => {
  const slot = row[`_visible_${action.ash_action}`];
  return Array.isArray(slot) ? slot.length > 0 : true;
};

async function checkRowsAndActions(page, caseName, {narrow = false} = {}) {
  const manifest = await manifestOf(page);

  for (const table of manifest.tables) {
    const rows = await rowsOf(page, table.records_path);
    const actions = manifest.row_actions.filter((action) => action.table === table.id);

    await check(`${caseName}: ${table.id}: every record is one row by data-a2ui-row-id`, async () => {
      if (rows.length === 0) throw new Error("no rows recorded");
      for (const row of rows) expect(await rowLocator(page, table, row.id).count(), 1, `row ${row.id}`);
    });

    await check(`${caseName}: ${table.id}: row actions render where visible_when allows, named by label`, async () => {
      for (const row of rows) {
        const rowEl = rowLocator(page, table, row.id);
        for (const action of actions) {
          const want = offered(row, action) ? 1 : 0;
          const control = rowEl.locator(`[data-a2ui-action=${JSON.stringify(action.ash_action)}]`).filter({visible: true});
          expect(await control.count(), want, `${action.id} control on ${row.id}`);
          const named = rowEl.getByRole("button", {name: action.label, exact: true});
          expect(await named.count(), want, `${action.id} button "${action.label}" on ${row.id}`);
          if (want) {
            expect(await control.getByRole("button", {name: action.label, exact: true}).count(), 1,
              `${action.id}: the attribute marks the labelled button`);
          }
        }
      }
    });

    for (const action of actions) {
      const row = rows.find((candidate) => offered(candidate, action));
      if (!row) {
        await check(`${caseName}: ${action.id}: offered on no row, so no control anywhere`, async () => {
          expect(await page.locator(`[data-a2ui-action=${JSON.stringify(action.ash_action)}]`).filter({visible: true}).count(), 0);
        });
        continue;
      }

      await check(`${caseName}: ${action.id}: clicking it acts on its row (confirm: ${action.confirm})`, async () => {
        await dispatched(page);
        const rowEl = rowLocator(page, table, row.id);
        await rowEl.getByRole("button", {name: action.label, exact: true}).click();
        await page.waitForTimeout(200);

        if (action.confirm === "prompt") {
          for (const field of action.prompt_fields) {
            const input = page.getByLabel(field.label, {exact: true}).filter({visible: true});
            expect(await input.count(), 1, `prompt input "${field.label}"`);
          }
          await page.getByRole("button", {name: action.confirm_label, exact: true}).filter({visible: true}).click();
          await page.waitForTimeout(200);
        } else if (action.confirm === "destructive") {
          await page.getByRole("button", {name: action.confirm_label, exact: true}).filter({visible: true}).last().click();
          await page.waitForTimeout(200);
        }

        const invoke = (await dispatched(page)).filter((event) => event.name === "invoke");
        expect(invoke.map((event) => [event.context.action, event.context.recordId]), [[action.ash_action, row.id]]);
      });

      // Close a prompt still open (the probe has no server to answer).
      await page.keyboard.press("Escape");
      for (const close of await page.getByRole("button", {name: /^(Cancel|Close|×)$/}).filter({visible: true}).all()) {
        await close.click().catch(() => {});
      }
    }

    await check(`${caseName}: ${table.id}: roles`, async () => {
      if (narrow) {
        // The narrow layout is a card list: no visible table, no row role.
        expect(await page.getByRole("table").count(), 0, "visible tables");
        expect(await page.getByRole("row").count(), 0, "visible rows");
      } else if (manifest.catalog === "admin_v1") {
        const grid = page.getByRole("table", {name: table.label, exact: true});
        expect(await grid.count(), 1, `table named "${table.label}"`);
        expect(await grid.getByRole("row").count(), rows.length + 1, "rows + header");
      } else {
        expect(await page.getByRole("row").count(), 0, "basic rows have no row role");
      }
    });
  }

  // A refresh that moves records between positions: each rendered row's
  // data-a2ui-row-id follows its record, not its position.
  for (const table of manifest.tables) {
    await check(`${caseName}: ${table.id}: row ids follow a refresh that reorders the rows`, async () => {
      const rows = await rowsOf(page, table.records_path);
      if (rows.length < 2) return;
      await page.evaluate(
        ({path, value}) => {
          const surface = window.__surface;
          window.__feed([
            {version: "v0.9.1", updateDataModel: {surfaceId: surface.id, path, value}},
          ]);
        },
        {path: table.records_path, value: [...rows].reverse()},
      );
      await page.waitForTimeout(300);
      const first = table.columns[0].name;
      for (const row of rows) {
        const rowEl = rowLocator(page, table, row.id);
        expect(await rowEl.count(), 1, `row ${row.id}`);
        const text = await rowEl.evaluate((el) => {
          // Text across shadow roots: innerText stops at a custom element's root.
          const walk = (node) =>
            node.nodeType === Node.TEXT_NODE
              ? node.textContent
              : [...(node.shadowRoot ? [node.shadowRoot] : []), ...node.childNodes].map(walk).join(" ");
          return walk(el);
        });
        if (!text.includes(String(row[first]))) throw new Error(`row ${row.id} shows "${text}", not ${row[first]}`);
      }
    });
  }

  await check(`${caseName}: no console errors`, async () => expect(page.__errors, []));
}

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath});

  try {
    for (const name of [
      "manifest_tasks_admin",
      "manifest_tasks_admin_pseudo",
      "manifest_tasks_basic",
      "manifest_referrals_admin",
      "manifest_referrals_basic",
    ]) {
      const page = await openCase(browser, base, name);
      await checkRowsAndActions(page, name);
      await page.close();
    }

    // The admin grid's narrow layout: cards, not table rows.
    const narrow = await openCase(browser, base, "manifest_referrals_admin", {width: 420, height: 900});
    await check("manifest_referrals_admin (narrow): the table is hidden, so tr finds no visible row", async () => {
      expect(await narrow.locator("tr[data-a2ui-row-id]").filter({visible: true}).count(), 0);
    });
    await checkRowsAndActions(narrow, "manifest_referrals_admin (narrow)", {narrow: true});
    await narrow.close();
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
