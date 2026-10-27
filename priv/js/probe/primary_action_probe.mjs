/**
 * Admin-catalog primary-action probe — the browser gate for
 * `primary_action` on a table (catalog 1.9 rowClick `inline`,
 * `labelPath`, `variantPath`):
 *
 *   - the grid draws one button per row in a final column, its label and
 *     variant read from the row (Review / primary, Finish / default, the
 *     row click's own "View" / borderless);
 *   - activating a button dispatches the row click's envelope for that
 *     row, exactly once (it never also fires the row click);
 *   - activating the row elsewhere still dispatches the row click;
 *   - the narrow (card) layout carries the same button;
 *   - no console errors.
 *
 * Fixtures are recorded wire payloads (synthetic data):
 *
 *     MIX_ENV=test mix run priv/js/probe/record_primary_action.exs
 *
 * Run:
 *
 *     node priv/js/probe/primary_action_probe.mjs [--node-modules DIR] [--port N]
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
const port = Number(arg("port", "4197"));
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
  const root = mkdtempSync(join("/tmp", "primary-action-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "primary_action_probe.html"), join(root, "primary_action_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/primary_action_probe.html`, {method: "HEAD"});
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
  await page.goto(`${base}/primary_action_probe.html?${query}`, {waitUntil: "load"});
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
    const page = await openCase(browser, base, "payload=primary_action_admin");

    const buttons = () =>
      page.evaluate(() =>
        Object.fromEntries(
          window.__deepAll(".grid-table tbody tr").map((tr) => {
            const button = tr.querySelector("button[data-primary-action]");
            return [
              tr.querySelector("th").textContent.trim(),
              button && {
                label: button.textContent.trim(),
                primary: button.classList.contains("am-btn-primary"),
                quiet: button.classList.contains("am-btn-quiet"),
              },
            ];
          }),
        ),
      );

    await check("each row draws its own button: label and variant from the row", async () => {
      const drawn = await buttons();
      expect(drawn["Sent one"], {label: "Review", primary: true, quiet: false}, "Sent one");
      expect(drawn["Draft one"], {label: "Finish", primary: false, quiet: false}, "Draft one");
      expect(drawn["Done one"], {label: "View", primary: false, quiet: true}, "Done one");
    });

    await check("the header has a column for it", async () => {
      const headers = await page.evaluate(() =>
        window.__deepAll(".grid-table thead th").map((th) => th.textContent.trim()),
      );
      truthy(headers.includes("View"), `a header cell named by the row click (${headers})`);
    });

    await check("a row's button dispatches the row click for that row, once", async () => {
      const before = await page.evaluate(() => window.__dispatched.length);
      const recordId = await page.evaluate(() => {
        const tr = window
          .__deepAll(".grid-table tbody tr")
          .find((row) => row.querySelector("th").textContent.trim() === "Sent one");
        tr.querySelector("button[data-primary-action]").click();
        return tr.id.replace(/^row-/, "");
      });
      await page.waitForTimeout(200);
      const dispatched = await page.evaluate((n) => window.__dispatched.slice(n), before);
      expect(dispatched.length, 1, "dispatch count");
      expect(dispatched[0].name, "view_record", "action");
      expect(dispatched[0].context.recordId, recordId, "record");
    });

    await check("the row click itself still works", async () => {
      const before = await page.evaluate(() => window.__dispatched.length);
      await page.evaluate(() => {
        const tr = window
          .__deepAll(".grid-table tbody tr")
          .find((row) => row.querySelector("th").textContent.trim() === "Done one");
        tr.querySelector("td").click();
      });
      await page.waitForTimeout(200);
      const dispatched = await page.evaluate((n) => window.__dispatched.slice(n), before);
      expect(dispatched.map((d) => d.name), ["view_record"], "row click");
    });

    await check("no console errors", async () => expect(page.__errors, []));

    const narrow = await openCase(browser, base, "payload=primary_action_admin", {
      width: 420,
      height: 900,
    });

    await check("the card layout carries the same buttons", async () => {
      const labels = await narrow.evaluate(() =>
        window
          .__deepAll(".grid-cards li")
          .filter((li) => li.offsetParent !== null)
          .map((li) => li.querySelector("button[data-primary-action]")?.textContent.trim())
          .sort(),
      );
      expect(labels, ["Finish", "Review", "View"]);
    });
  } finally {
    await browser.close();
    stop();
  }

  console.log(results.join("\n"));
  if (failures.length > 0) {
    console.log(failures.join("\n"));
    process.exit(1);
  }
  console.log(`\n${results.length} checks passed`);
}

await main();
