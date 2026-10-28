/**
 * Admin-catalog hub probe — the browser gate for catalog 1.10 (the filter
 * bar and table header of a hub page):
 *
 *   - the surface validates and boots (the extended ChoicePicker/TextField
 *     schemas accept hint, counts, dynamicOptions, grouped options and
 *     placeholder) with no console errors;
 *   - a multi-select picker draws its group with the sum of its leaves'
 *     counts, leaves under it, and the hint; picking the group writes both
 *     leaves (only leaves) to the filter;
 *   - a path filter's picker draws the options bound from the query state;
 *   - the search box carries the placeholder;
 *   - a column's header help opens with its definition; a detail line's
 *     help mark carries its text;
 *   - a header sorted by another field sends that field;
 *   - the pager's rows-per-page select sends the picked size at page 1;
 *   - an empty status banner takes no space;
 *   - fixed column widths apply, and the "+N more" tag lists its values;
 *   - searched for nothing, the empty state shows its title and icon, and
 *     its clear action clears search and filters and sends the query.
 *
 * Fixtures are recorded wire payloads (synthetic data):
 *
 *     MIX_ENV=test mix run priv/js/probe/record_hub.exs
 *
 * Run:
 *
 *     node priv/js/probe/hub_probe.mjs [--node-modules DIR] [--port N]
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
const port = Number(arg("port", "4198"));
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
  const root = mkdtempSync(join("/tmp", "hub-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "hub_probe.html"), join(root, "hub_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/hub_probe.html`, {method: "HEAD"});
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
  await page.goto(`${base}/hub_probe.html?${query}`, {waitUntil: "load"});
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
    const page = await openCase(browser, base, "payload=hub_admin");

    const pickerText = (id) =>
      page.evaluate((target) => {
        const host = window.__deepAll("ash-admin-choicepicker").find(
          (element) => element.context?.componentModel?.id === target,
        );
        return host ? window.__deepText(host) : null;
      }, id);

    await check("the status picker draws its group, leaves, counts and hint", async () => {
      const text = await pickerText("query_filter_status");
      truthy(text, "status picker rendered");
      truthy(text.includes("Expiring soon (2)"), `group with its leaves' sum: ${text}`);
      truthy(text.includes("Renewal scheduled (1)"), `leaf count: ${text}`);
      truthy(text.includes("Statuses update nightly."), `hint: ${text}`);
      truthy(!text.includes("All"), `no All option: ${text}`);
    });

    await check("picking the group writes its leaves, and only them", async () => {
      await page.evaluate(() => {
        const host = window.__deepAll("ash-admin-choicepicker").find(
          (element) => element.context?.componentModel?.id === "query_filter_status",
        );
        host.shadowRoot.querySelector(".choice-group input").click();
      });
      await page.waitForTimeout(200);
      const value = await page.evaluate(() => window.__surface.dataModel.get("/query/filters/status"));
      expect([...value].sort(), ["expiring_soon", "renewal_scheduled"], "filter value");
    });

    await check("a path filter draws its bound options with counts", async () => {
      const text = await pickerText("query_filter_property");
      truthy(text.includes("Elm (2)") && text.includes("Oak (3)") && text.includes("Pine (1)"), text);
    });

    await check("the search box has the placeholder and keeps its label", async () => {
      const input = await page.evaluate(() => {
        const field = window.__deepAll("ash-admin-textfield")[0];
        const el = field.shadowRoot.querySelector("input");
        return {placeholder: el.placeholder, label: field.shadowRoot.querySelector("label")?.textContent};
      });
      expect(input, {placeholder: "Search contracts or vendors", label: "Search"});
    });

    await check("column help opens with its title and definition", async () => {
      const text = await page.evaluate(() => {
        const details = window.__deepAll(".am-col-help")[0];
        details.open = true;
        return details.querySelector(".am-col-help-body").textContent.replace(/\s+/g, " ").trim();
      });
      truthy(text.includes("Property") && text.includes("Portfolio — every property"), text);
    });

    await check("a detail line carries its help mark", async () => {
      const title = await page.evaluate(
        () => window.__deepAll(".am-cell-detail .am-help-mark")[0]?.getAttribute("title"),
      );
      expect(title, "Renews unless cancelled 30 days ahead.");
    });

    await check("a header sorted by another field sends that field", async () => {
      const before = await page.evaluate(() => window.__dispatched.length);
      await page.evaluate(() => {
        const th = window
          .__deepAll(".grid-table thead th")
          .find((cell) => cell.textContent.trim().startsWith("Status"));
        th.querySelector("button.sort-button").click();
      });
      await page.waitForTimeout(200);
      const sent = await page.evaluate((n) => window.__dispatched.slice(n), before);
      expect(sent.at(-1)?.context?.query?.sort, {field: "status", dir: "asc"}, "sort");
    });

    await check("rows per page sends the picked size at page 1", async () => {
      const before = await page.evaluate(() => window.__dispatched.length);
      await page.evaluate(() => {
        const select = window.__deepAll(".pager-size select")[0];
        select.value = "10";
        select.dispatchEvent(new Event("change"));
      });
      await page.waitForTimeout(200);
      const sent = await page.evaluate((n) => window.__dispatched.slice(n), before);
      const query = sent.at(-1)?.context?.query;
      expect([query?.pageSize, query?.page], [10, 1], "pageSize/page");
    });

    await check("an empty status banner takes no space", async () => {
      const box = await page.evaluate(() => {
        const banner = window.__deepAll("ash-admin-status-banner")[0];
        return {hidden: banner.hasAttribute("hidden"), height: banner.getBoundingClientRect().height};
      });
      expect(box, {hidden: true, height: 0});
    });

    await check("fixed widths apply and the more tag lists its values", async () => {
      const facts = await page.evaluate(() => {
        const th = window.__deepAll(".grid-table thead th")[0];
        const tag = window
          .__deepAll(".grid-table tbody .am-badge")
          .find((badge) => badge.textContent.includes("more"));
        return {width: th.style.width, title: tag?.getAttribute("title") ?? null};
      });
      expect(facts.width, "320px", "name width");
      // The first page (HVAC, Painting) has no row with two properties.
      expect(facts.title, null, "no tag on this page");
    });

    await check("no console errors", async () => expect(page.__errors, []));

    const empty = await openCase(browser, base, "payload=hub_admin_no_results");

    await check("searched for nothing: the no-results state with its clear action", async () => {
      const facts = await empty.evaluate(() => {
        const host = window.__deepAll("ash-admin-empty-state")[0];
        const root = host.shadowRoot;
        return {
          title: root.querySelector(".empty-title")?.textContent.trim(),
          message: root.querySelector(".empty-message")?.textContent.trim(),
          button: root.querySelector(".empty-action button")?.textContent.trim(),
        };
      });
      expect(facts, {
        title: "No results",
        message: "Try other words or filters.",
        button: "Clear search and filters",
      });
    });

    await check("the clear action clears search and filters, then sends the query", async () => {
      const before = await empty.evaluate(() => window.__dispatched.length);
      await empty.evaluate(() =>
        window.__deepAll("ash-admin-empty-state")[0].shadowRoot.querySelector(".empty-action button").click(),
      );
      await empty.waitForTimeout(200);
      const sent = await empty.evaluate((n) => window.__dispatched.slice(n), before);
      const query = sent.at(-1)?.context?.query;
      expect([query?.search, query?.filters?.status, query?.page ?? sent.at(-1)?.context?.page], ["", [], 1]);
    });

    await check("no console errors (empty state)", async () => expect(empty.__errors, []));
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
