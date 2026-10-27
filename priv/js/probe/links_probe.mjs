/**
 * Links + table-lifts probe — the browser gate for admin catalog 1.1
 * (reference links, badge pills, per-type cells, sticky token-driven grid,
 * whole-row click, windowed pagination, link/list-aware FieldDisplay).
 *
 * Assembles a temporary web root (a node_modules tree + this repo's priv/js
 * + the recorded fixtures), serves it, and drives the real admin catalog
 * with real wire payloads recorded from the synthetic link fixtures
 * (`AshA2ui.Test.Links.NotesUI` / `PagedNotesUI`, test/support/links.ex):
 *
 *     MIX_ENV=test mix run priv/js/probe/record_links.exs
 *
 * Run:
 *
 *     node priv/js/probe/links_probe.mjs [--node-modules DIR] [--port N]
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
const port = Number(arg("port", "4191"));
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

async function serve() {
  const root = mkdtempSync(join("/tmp", "links-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "links_probe.html"), join(root, "links_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/links_probe.html`, {method: "HEAD"});
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

async function openCase(browser, base, query) {
  const page = await browser.newPage({viewport: {width: 1280, height: 900}});
  const errors = [];
  page.on("pageerror", (error) => errors.push(`PAGEERROR: ${error.message.slice(0, 200)}`));
  page.on("console", (message) => {
    if (message.type() === "error") {
      if (message.location()?.url?.includes("favicon")) return;
      errors.push(`CONSOLE: ${message.text().slice(0, 200)}`);
    }
  });
  page.__errors = errors;
  await page.goto(`${base}/links_probe.html?${query}`, {waitUntil: "load"});
  await page.waitForFunction(() => window.__boot?.stage && window.__boot.stage !== "imports-done");
  await page.waitForTimeout(600);
  const stage = await page.evaluate(() => window.__boot);
  if (stage.stage === "error") throw new Error(`boot failed: ${stage.error}`);
  return page;
}

// In-page helpers: a deep (shadow-piercing) querySelectorAll, installed once
// per page so every evaluate can use it.
async function installDeep(page) {
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
  });
}

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath});

  try {
    /* --- link cells, badges, typed cells, row click --------------------- */
    let page = await openCase(browser, base, "payload=links");
    await installDeep(page);

    await check("grid: link cells render as anchors with the server href", async () => {
      const links = await page.evaluate(() =>
        window.__deepAll(".grid-table a.am-link").map((a) => ({
          text: a.textContent.trim(),
          href: a.getAttribute("href"),
          surface: a.dataset.surface,
        })),
      );
      const person = links.find((link) => link.text === "Dr. Ada");
      if (!person) throw new Error(`no "Dr. Ada" link (got ${JSON.stringify(links)})`);
      expect(person.surface, "person", "surface");
      expect(/^\/app\/r\/person\/[0-9a-f-]{36}$/.test(person.href), true, `href ${person.href}`);
      // the multi-valued participants column: hidden participant pruned
      const labels = links.map((link) => link.text);
      expect(labels.includes("Ada") && labels.includes("Bob"), true, `participants ${labels}`);
      expect(labels.includes("Hidden"), false, "pruned participant");
    });

    await check("grid: a plain link click raises openSurface (no navigation, no row action)", async () => {
      await page.evaluate(() => {
        window.__opened.length = 0;
        window.__dispatched.length = 0;
        const anchor = window
          .__deepAll(".grid-table a.am-link")
          .find((a) => a.textContent.trim() === "Dr. Ada");
        anchor.click();
      });
      await page.waitForTimeout(100);
      const {opened, dispatched} = await page.evaluate(() => ({
        opened: window.__opened,
        dispatched: window.__dispatched,
      }));
      expect(opened.length, 1, "one openSurface");
      expect(opened[0].surface, "person", "surface");
      expect(typeof opened[0].recordId, "string", "recordId");
      expect(opened[0].surfaceId, "notes", "surfaceId");
      expect(dispatched.length, 0, "the row action must not fire");
    });

    await check("grid: a modified (new-tab) click is left to the browser", async () => {
      const outcome = await page.evaluate(() => {
        window.__opened.length = 0;
        const anchor = window
          .__deepAll(".grid-table a.am-link")
          .find((a) => a.textContent.trim() === "Dr. Ada");
        const href = anchor.getAttribute("href");
        // Neutralize the browser's own navigation for the probe page.
        anchor.setAttribute("href", "javascript:void(0)");
        let seenAtWindow = null;
        const listener = (event) => {
          seenAtWindow = event.defaultPrevented;
        };
        window.addEventListener("click", listener, {once: true});
        anchor.dispatchEvent(
          new MouseEvent("click", {bubbles: true, composed: true, cancelable: true, metaKey: true}),
        );
        window.removeEventListener("click", listener);
        anchor.setAttribute("href", href);
        return {seenAtWindow, opened: window.__opened.length};
      });
      // The click bubbled untouched (not prevented, not swallowed) and no
      // openSurface was raised: the browser's new-tab behavior applies.
      expect(outcome, {seenAtWindow: false, opened: 0}, "meta-click");
    });

    await check("grid: badge pill with the row tone", async () => {
      const badges = await page.evaluate(() =>
        window.__deepAll(".grid-table .am-badge").map((badge) => ({
          text: badge.textContent.trim(),
          tone: badge.dataset.tone,
        })),
      );
      const open = badges.find((badge) => badge.text === "Open");
      const closed = badges.find((badge) => badge.text === "Closed");
      if (!open || !closed) throw new Error(`badges ${JSON.stringify(badges)}`);
      expect(open.tone, "success", "open tone");
      expect(closed.tone, "neutral", "closed tone");
    });

    await check("grid: numbers end-aligned with tabular figures; sticky header", async () => {
      const styles = await page.evaluate(() => {
        const header = window.__deepAll(".grid-table thead th")[0];
        const amount = window.__deepAll(".grid-table td.align-end")[0];
        return {
          headerPosition: getComputedStyle(header).position,
          headerTransform: getComputedStyle(header).textTransform,
          amountAlign: amount && getComputedStyle(amount).textAlign,
          amountText: amount && amount.textContent.trim(),
          numeric: amount && getComputedStyle(amount).fontVariantNumeric,
        };
      });
      expect(styles.headerPosition, "sticky", "sticky header");
      expect(styles.headerTransform, "none", "no hardcoded uppercase");
      expect(styles.amountAlign, "right", "end-aligned");
      expect(styles.numeric, "tabular-nums", "tabular figures");
    });

    await check("grid: whole-row click dispatches the row's primary action", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        const row = window.__deepAll(".grid-table tbody tr.is-clickable")[0];
        row.querySelector("td").click();
      });
      await page.waitForTimeout(100);
      const dispatched = await page.evaluate(() => window.__dispatched);
      expect(dispatched.length, 1, "one dispatch");
      expect(dispatched[0].name, "context_select", "master/detail select");
      expect(dispatched[0].context.context, "note", "context name");
      expect(typeof dispatched[0].context.value, "string", "row id resolved");
    });

    await check("no console errors (links case)", async () => {
      expect(page.__errors, [], "errors");
    });
    await page.close();

    /* --- link-aware, list-aware detail FieldDisplays --------------------- */
    page = await openCase(browser, base, "payload=links&select=1");
    await installDeep(page);

    await check("detail: link field renders a link, bulleted text a list", async () => {
      const detail = await page.evaluate(() => {
        const displays = window.__deepAll("ash-admin-field-display");
        const textOf = (label) =>
          displays.find((d) => d.shadowRoot?.querySelector(".field-label")?.textContent.trim() === label);
        const person = textOf("Person");
        const body = textOf("Body");
        return {
          personLink: person?.shadowRoot?.querySelector(".am-link")?.textContent.trim(),
          bodyItems: [...(body?.shadowRoot?.querySelectorAll("ul.am-list li") ?? [])].map((li) =>
            li.textContent.trim(),
          ),
          participants: [
            ...(textOf("Participants")?.shadowRoot?.querySelectorAll(".am-link") ?? []),
          ].map((a) => a.textContent.trim()),
        };
      });
      expect(detail.personLink, "Dr. Ada", "person link");
      expect(detail.bodyItems, ["first point", "second point", "third point"], "body list");
      expect([...detail.participants].sort(), ["Ada", "Bob"], "participant links");
    });

    await check("no console errors (detail case)", async () => {
      expect(page.__errors, [], "errors");
    });
    await page.close();

    /* --- windowed pagination ---------------------------------------------- */
    page = await openCase(browser, base, "payload=links_paged");
    await installDeep(page);

    await check("pager: windowed chips 1 … 3 4 5 … 7 with aria-current", async () => {
      const pager = await page.evaluate(() => {
        const host = window.__deepAll("ash-admin-pagination")[0];
        const chips = [...host.shadowRoot.querySelectorAll(".pager-pages > *")].map((el) =>
          el.textContent.trim(),
        );
        const current = host.shadowRoot.querySelector('[aria-current="page"]')?.textContent.trim();
        return {chips, current};
      });
      expect(pager.chips, ["1", "…", "3", "4", "5", "…", "7"], "window");
      expect(pager.current, "4", "current page");
    });

    await check("pager: a chip jumps with the existing query envelope (pageDelta = distance)", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        const host = window.__deepAll("ash-admin-pagination")[0];
        [...host.shadowRoot.querySelectorAll("button.pager-chip")]
          .find((button) => button.textContent.trim() === "7")
          .click();
      });
      await page.waitForTimeout(100);
      const dispatched = await page.evaluate(() => window.__dispatched);
      expect(dispatched.length, 1, "one dispatch");
      expect(dispatched[0].name, "query", "query action");
      expect(dispatched[0].context.pageDelta, 3, "4 → 7");
      expect(typeof dispatched[0].context.query, "object", "query state resolved");
    });

    await check("pager: Previous keeps its ∓1 envelope", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        const host = window.__deepAll("ash-admin-pagination")[0];
        [...host.shadowRoot.querySelectorAll("button")]
          .find((button) => button.textContent.includes("Previous"))
          .click();
      });
      await page.waitForTimeout(100);
      const dispatched = await page.evaluate(() => window.__dispatched);
      expect(dispatched[0]?.context?.pageDelta, -1, "previous");
    });

    await check("no console errors (paged case)", async () => {
      expect(page.__errors, [], "errors");
    });
    await page.screenshot({path: join(probeDir, "screenshots", "links_paged.png"), fullPage: true});
    await page.close();

    /* --- sortable headers (1.7) ------------------------------------------- */
    page = await openCase(browser, base, "payload=sort");
    await installDeep(page);

    await check("sort: only the sortable column's header is a button, marked by aria-sort", async () => {
      const headers = await page.evaluate(() =>
        window.__deepAll(".grid-table thead th").map((th) => ({
          text: th.textContent.replace(/\s+/g, " ").trim(),
          ariaSort: th.getAttribute("aria-sort"),
          button: !!th.querySelector("button.sort-button"),
        })),
      );
      const title = headers.find((h) => h.text.startsWith("Title"));
      const amount = headers.find((h) => h.text === "Amount");
      if (!title || !amount) throw new Error(`headers ${JSON.stringify(headers)}`);
      expect(title.button, true, "title is a sort control");
      expect(title.ariaSort, "ascending", "default sort title asc");
      expect(amount.button, false, "amount is plain");
      expect(amount.ariaSort, null, "no aria-sort on a plain header");
    });

    await check("sort: a click sends the query envelope with the toggled sort and page 1", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        window.__deepAll(".grid-table thead th button.sort-button")[0].click();
      });
      await page.waitForTimeout(100);
      const dispatched = await page.evaluate(() => window.__dispatched);
      expect(dispatched.length, 1, "one dispatch");
      expect(dispatched[0].name, "query", "query action");
      expect(dispatched[0].context.page, 1, "page reset");
      expect(dispatched[0].context.component, "table", "component");
      expect(dispatched[0].context.query.sort, {field: "title", dir: "desc"}, "asc → desc");
      expect(dispatched[0].context.query.pageSize, 1, "rest of the query state resolved");
    });

    await check("no console errors (sort case)", async () => {
      expect(page.__errors, [], "errors");
    });
    await page.close();

    /* --- host tokens drive the grid -------------------------------------- */
    page = await openCase(browser, base, "payload=links&nb=1");
    await installDeep(page);

    await check("tokens: border width, header, scroll frame and tone fills follow --ash-admin-*", async () => {
      const styles = await page.evaluate(() => {
        const frame = window.__deepAll(".grid-frame")[0];
        const header = window.__deepAll(".grid-table thead th")[0];
        const success = window.__deepAll('.grid-table .am-badge[data-tone="success"]')[0];
        return {
          frameBorder: getComputedStyle(frame).borderTopWidth,
          frameMaxHeight: getComputedStyle(frame).maxHeight,
          frameOverflow: getComputedStyle(frame).overflowY,
          headerTransform: getComputedStyle(header).textTransform,
          headerBg: getComputedStyle(header).backgroundColor,
          successBg: getComputedStyle(success).backgroundColor,
        };
      });
      expect(styles.frameBorder, "3px", "border width token");
      expect(styles.frameMaxHeight, "160px", "scroll frame token");
      expect(styles.frameOverflow, "auto", "scroll frame");
      expect(styles.headerTransform, "uppercase", "header transform token");
      expect(styles.headerBg, "rgb(10, 20, 30)", "header background token");
      expect(styles.successBg, "rgb(0, 200, 80)", "badge tone token");
    });
    await page.screenshot({path: join(probeDir, "screenshots", "links_tokens.png"), fullPage: true});
    await page.close();
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
