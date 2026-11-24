/**
 * Document-pane probe — the browser gate for `document_pane` (admin
 * catalog 3.4, lukegalea/ash_a2ui#120):
 *
 *   - pdf.js is not requested before a document is shown, and is loaded once
 *     when the pane opens (the loader imports ash_a2ui_pdf.js, the way a host
 *     bundles it);
 *   - pages render: one sheet per page, each canvas inked;
 *   - regions sit on their boxes (fractions of their page, ±1.5px) at two
 *     zoom levels, and zoom and page navigation work;
 *   - activating a region (click, Enter) dispatches document_region with its
 *     id and shows it selected; a review's page tag opens the hidden pane at
 *     its region;
 *   - each page's text is in the accessibility tree (Chrome's, through CDP);
 *   - 3.8, a value and its region linked both ways: pointing at or focusing
 *     a value shows its region linked without scrolling the page, moving
 *     focus or sending anything, and leaving clears it; clicking a region
 *     brings its value into view and flashes it for 3 s, Enter also moves
 *     focus to it; a hidden or stacked pane links nothing;
 *   - nothing logs an error and the CSP is never violated.
 *
 * Every check runs under a strict CSP (`script-src 'self' 'unsafe-inline'`:
 * no 'unsafe-eval', no 'wasm-unsafe-eval'), set on every response, worker
 * scripts included. With `--corpus DIR` it also runs the pre-build checks:
 * each PDF in DIR (a scanned JBIG2 one, JPX ones, one with an ICC profile, a
 * tagged one; see the ADR 0002 notes) opened under the strict CSP and under
 * a host CSP that allows 'unsafe-eval', reporting whether it drew, what
 * the CSP blocked and whether any WebAssembly was fetched.
 *
 * Fixtures are recorded wire payloads and a generated PDF:
 *
 *     MIX_ENV=test mix run priv/js/probe/record_document.exs
 *
 * Run:
 *
 *     node priv/js/probe/document_probe.mjs --node-modules DIR [--port N] [--corpus DIR]
 *
 * (`--serve` stages and serves the page without running the checks.)
 *
 * `--node-modules` is any tree with @a2ui/lit + @a2ui/web_core after 0.15.0,
 * lit 3 and pdfjs-dist 6.2.108 or later. Chrome comes from $CHROME (else
 * Playwright's own Chromium), Playwright from $PLAYWRIGHT_NODE_MODULES (else
 * the --node-modules tree). Exit code is the verdict.
 */

import {cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync} from "node:fs";
import {createServer} from "node:http";
import {tmpdir} from "node:os";
import {fileURLToPath} from "node:url";
import {dirname, extname, join, resolve} from "node:path";

const probeDir = dirname(fileURLToPath(import.meta.url));
const repoPrivJs = resolve(probeDir, "..");

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const index = args.indexOf(`--${name}`);
  return index !== -1 ? args[index + 1] : fallback;
};
const nodeModules = resolve(arg("node-modules", join(repoPrivJs, "../../../clinic-demo/assets/node_modules")));
const port = Number(arg("port", "4196"));
const corpus = arg("corpus", null);
const playwrightModule = `${process.env.PLAYWRIGHT_NODE_MODULES ?? nodeModules}/playwright/index.mjs`;
const {chromium} = await import(playwrightModule);

const CSP = {
  strict: [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self' data:",
    "connect-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
  ].join("; "),
  // A host CSP that allows 'unsafe-eval', which also lets WebAssembly compile.
  eval: [
    "default-src 'self'",
    "img-src 'self' data: blob:",
    "font-src 'self' data:",
    "style-src 'self' 'unsafe-inline'",
    "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
    "connect-src 'self' ws: wss:",
    "object-src 'none'",
    "base-uri 'self'",
  ].join("; "),
};

const results = [];
const failures = [];
const notes = [];

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

const TYPES = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".json": "application/json",
  ".css": "text/css",
  ".pdf": "application/pdf",
  ".wasm": "application/wasm",
  ".bcmap": "application/octet-stream",
  ".pfb": "application/octet-stream",
};

function serve(root, csp, listenPort) {
  const server = createServer((request, response) => {
    const path = decodeURIComponent(new URL(request.url, "http://x").pathname);
    let file = join(root, path);
    try {
      if (statSync(file).isDirectory()) file = join(file, "index.html");
      const body = readFileSync(file);
      response.writeHead(200, {
        "content-type": TYPES[extname(file)] ?? "application/octet-stream",
        ...(csp ? {"content-security-policy": csp} : {}),
      });
      response.end(body);
    } catch {
      response.writeHead(404, csp ? {"content-security-policy": csp} : {});
      response.end("not found");
    }
  });
  return new Promise((done) => server.listen(listenPort, "127.0.0.1", () => done(server)));
}

// A web_core build after 0.15.0 (and signal-utils) export subpaths by wildcard
// ("./data/*" -> "./src/v0_8/data/*.js"), which an import map cannot express:
// each file a wildcard covers gets its own entry.
function wildcardEntries(pkgName) {
  const pkgDir = join(nodeModules, pkgName);
  const pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8"));
  const entries = {};
  for (const [key, target] of Object.entries(pkg.exports ?? {})) {
    const file = typeof target === "string" ? target : target?.default;
    if (!key.endsWith("/*") || !file?.includes("*")) continue;
    const [prefix, suffix] = file.slice(2).split("*");
    const dir = join(pkgDir, prefix);
    if (!existsSync(dir)) continue;
    for (const name of readdirSync(dir).filter((f) => f.endsWith(suffix))) {
      const stem = name.slice(0, name.length - suffix.length);
      entries[`${pkgName}/${key.slice(2, -1)}${stem}`] = `./nm/${pkgName}/${prefix}${name}`;
    }
  }
  return entries;
}

function withWildcardExports(html) {
  const extra = {...wildcardEntries("@a2ui/web_core"), ...wildcardEntries("signal-utils")};
  return html.replace(/<script type="importmap">([\s\S]*?)<\/script>/, (_match, json) => {
    const map = JSON.parse(json);
    map.imports = {...extra, ...map.imports};
    return `<script type="importmap">${JSON.stringify(map, null, 2)}</script>`;
  });
}

function stage() {
  const root = mkdtempSync(join(tmpdir(), "document-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  writeFileSync(join(root, "document_probe.html"), withWildcardExports(readFileSync(join(probeDir, "document_probe.html"), "utf8")));
  if (corpus) symlinkSync(resolve(corpus), join(root, "corpus"), "dir");
  return root;
}

async function openCase(browser, base, query, viewport = {width: 1440, height: 1000}) {
  const page = await browser.newPage({viewport});
  const errors = [];
  const requests = [];
  page.on("pageerror", (error) => errors.push(`PAGEERROR: ${error.message.slice(0, 200)}`));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(`CONSOLE: ${message.text().slice(0, 200)}`);
  });
  page.on("request", (request) => requests.push(request.url()));
  page.on("response", (response) => {
    if (response.status() >= 400) errors.push(`HTTP ${response.status()}: ${response.url()}`);
  });
  page.__errors = errors;
  page.__requests = requests;
  await page.goto(`${base}/document_probe.html?${query}`, {waitUntil: "load"});
  await page
    .waitForFunction(() => window.__boot?.stage && window.__boot.stage !== "imports-done", null, {timeout: 20_000})
    .catch(() => {
      throw new Error(`the page did not boot: ${errors.slice(0, 5).join(" | ")}`);
    });
  const boot = await page.evaluate(() => window.__boot);
  if (boot.stage === "error") throw new Error(`boot failed: ${boot.error}`);
  await page.evaluate(() => {
    window.__deep = (selector, root = document) => {
      const found = root.querySelector(selector);
      if (found) return found;
      for (const element of root.querySelectorAll("*")) {
        const inner = element.shadowRoot && window.__deep(selector, element.shadowRoot);
        if (inner) return inner;
      }
      return null;
    };
    window.__pane = () => window.__deep("ash-admin-document-pane");
    window.__viewer = () => window.__deep("ash-admin-document-viewer");
    window.__vroot = () => window.__viewer()?.renderRoot;
    window.__status = () => window.__vroot()?.querySelector("[data-status]")?.dataset.status ?? null;
    // Each region's box (its content box, inside the 2px state border) beside the box its
    // fractions give on its sheet.
    window.__geometry = () =>
      [...window.__vroot().querySelectorAll("[data-region]")].map((el) => {
        const sheet = el.closest("[data-page-sheet]").getBoundingClientRect();
        const box = el.getBoundingClientRect();
        const style = el.getAttribute("style");
        const pct = (key) => Number(new RegExp(`${key}:([0-9.]+)%`).exec(style)[1]) / 100;
        return {
          id: el.dataset.region,
          drawn: {x: box.left + 2, y: box.top + 2, w: box.width - 4, h: box.height - 4},
          expected: {
            x: sheet.left + pct("left") * sheet.width,
            y: sheet.top + pct("top") * sheet.height,
            w: pct("width") * sheet.width,
            h: pct("height") * sheet.height,
          },
          sheetWidth: sheet.width,
        };
      });
    window.__ink = (n) => {
      const canvas = window.__vroot().querySelector(`[data-page-sheet="${n}"] canvas`);
      if (!canvas || !canvas.width) return 0;
      const data = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data;
      let dark = 0;
      for (let i = 0; i < data.length; i += 4) if (data[i] < 200 || data[i + 1] < 200 || data[i + 2] < 200) dark++;
      return dark;
    };
  });
  return page;
}

const lastDispatch = (page, name) =>
  page.evaluate((n) => [...window.__dispatched].reverse().find((d) => d.name === n) ?? null, name);

async function waitReady(page, timeout = 30_000) {
  await page.waitForFunction(() => ["ready", "failed"].includes(window.__status()), null, {timeout}).catch(async () => {
    const status = await page
      .evaluate(() => `${window.__status()} pane=${!!window.__pane()} ctrl=${!!window.__pane()?.controller} props=${JSON.stringify(Object.keys(window.__pane()?.controller?.props ?? {}))} html=${(window.__pane()?.renderRoot?.innerHTML ?? "").replace(/<!--[^>]*-->/g, "").slice(0, 400)} shown=${JSON.stringify(window.__surface?.dataModel.get("/ui/documents"))}`)
      .catch((e) => `? ${e.message}`);
    throw new Error(`the viewer is not ready (status ${status}): ${page.__errors.slice(0, 5).join(" | ")}`);
  });
  // The pages drawn and their text laid out.
  await page.waitForTimeout(700);
}

const near = (a, b) => Math.abs(a - b) <= 1.5;

async function assertGeometry(page, note) {
  const geometry = await page.evaluate(() => window.__geometry());
  truthy(geometry.length === 3, `${note}: three regions (${geometry.length})`);
  for (const g of geometry) {
    for (const key of ["x", "y", "w", "h"]) {
      truthy(near(g.drawn[key], g.expected[key]), `${note}: ${g.id} ${key} ${g.drawn[key].toFixed(2)} vs ${g.expected[key].toFixed(2)}`);
    }
  }
  return geometry;
}

// The page text Chrome exposes to assistive technology, through CDP (it pierces shadow roots).
async function accessibleText(page) {
  const session = await page.context().newCDPSession(page);
  await session.send("Accessibility.enable");
  const {nodes} = await session.send("Accessibility.getFullAXTree");
  await session.detach();
  return nodes
    .filter((node) => !node.ignored && ["StaticText", "text", "InlineTextBox"].includes(node.role?.value))
    .map((node) => node.name?.value ?? "")
    .join(" ");
}

async function main() {
  const root = stage();
  const servers = {
    strict: await serve(root, CSP.strict, port),
    eval: await serve(root, CSP.eval, port + 1),
  };
  // --serve: stage and serve only (strict CSP on --port, the eval CSP on the next), to look by hand.
  if (args.includes("--serve")) {
    console.log(`serving ${root} on http://127.0.0.1:${port}/document_probe.html (Ctrl-C to stop)`);
    return;
  }
  const base = {strict: `http://127.0.0.1:${port}`, eval: `http://127.0.0.1:${port + 1}`};
  const browser = await chromium.launch(process.env.CHROME ? {executablePath: process.env.CHROME} : {});

  try {
    /* --- lazy loading ---------------------------------------------------- */
    const lazy = await openCase(browser, base.strict, "boot=empty");
    await check("pdf.js is not requested before a document is shown", async () => {
      await lazy.evaluate(() => window.__feedFixture("document_admin"));
      await lazy.waitForTimeout(500);
      truthy(await lazy.evaluate(() => !!window.__pane()), "the pane is drawn");
      expect(await lazy.evaluate(() => window.__pdfLoads), 0, "loads while hidden");
      truthy(!lazy.__requests.some((url) => url.includes("pdfjs-dist") || url.includes("ash_a2ui_pdf")), "no engine request");
    });
    await check("the switch opens the pane, and pdf.js loads once", async () => {
      await lazy.evaluate(() => {
        const input = window.__pane().renderRoot.querySelector("input[role='switch']");
        input.click();
      });
      await waitReady(lazy);
      expect(await lazy.evaluate(() => window.__pdfLoads), 1, "loads");
      expect(await lazy.evaluate(() => window.__status()), "ready", "status");
      const sent = await lastDispatch(lazy, "document_pane");
      expect(sent?.context, {pane: "referral", shown: true}, "document_pane");
    });
    await lazy.close();

    /* --- the viewer ------------------------------------------------------- */
    const page = await openCase(browser, base.strict, "payload=document_shown");
    await waitReady(page);

    await check("pages render: one sheet per page, each inked", async () => {
      expect(await page.evaluate(() => window.__vroot().querySelectorAll("[data-page-sheet]").length), 2, "sheets");
      truthy((await page.evaluate(() => window.__ink(1))) > 100, "page 1 inked");
      truthy((await page.evaluate(() => window.__ink(2))) > 100, "page 2 inked");
      expect(await page.evaluate(() => window.__vroot().querySelector("[data-role='page-info']").textContent.trim()), "1 of 2", "page info");
    });

    await check("the sections sit beside the document, one part to two", async () => {
      const widths = await page.evaluate(() => {
        const root = window.__pane().renderRoot;
        return [root.querySelector(".content").getBoundingClientRect().width, root.querySelector(".document").getBoundingClientRect().width];
      });
      truthy(Math.abs(widths[1] / widths[0] - 2) < 0.15, `ratio ${widths.map((w) => w.toFixed(0)).join(":")}`);
    });

    await check("a box's words show through it (multiply, no stacking context between it and the page)", async () => {
      const style = await page.evaluate(() => {
        const region = window.__vroot().querySelector("[data-region='title']");
        return [getComputedStyle(region.parentElement).zIndex, getComputedStyle(region).mixBlendMode];
      });
      expect(style, ["auto", "multiply"], "regions layer z-index, region blend");
    });

    let fitWidth = 0;
    await check("regions sit on their boxes at the width that fits", async () => {
      const geometry = await assertGeometry(page, "fit");
      fitWidth = geometry[0].sheetWidth;
    });

    await check("zoom in redraws the pages larger, and the regions stay on their boxes", async () => {
      const before = await page.evaluate(() => window.__vroot().querySelector("[data-role='zoom']").textContent.trim());
      await page.evaluate(() =>
        [...window.__vroot().querySelectorAll("button")].find((b) => /Zoom in/.test(b.textContent + b.getAttribute("aria-label"))).click(),
      );
      await page.waitForTimeout(800);
      const after = await page.evaluate(() => window.__vroot().querySelector("[data-role='zoom']").textContent.trim());
      truthy(before !== after, `zoom label ${before} -> ${after}`);
      const geometry = await assertGeometry(page, "zoomed");
      truthy(Math.abs(geometry[0].sheetWidth / fitWidth - 1.25) < 0.02, `sheet ${fitWidth} -> ${geometry[0].sheetWidth}`);
      truthy((await page.evaluate(() => window.__ink(1))) > 100, "redrawn");
    });

    await check("page navigation moves to the next page", async () => {
      await page.evaluate(() =>
        [...window.__vroot().querySelectorAll("button")].find((b) => /Next page/.test(b.textContent + b.getAttribute("aria-label"))).click(),
      );
      await page.waitForTimeout(800);
      expect(await page.evaluate(() => window.__vroot().querySelector("[data-role='page-info']").textContent.trim()), "2 of 2", "page info");
    });

    await check("activating a region dispatches document_region and selects it", async () => {
      await page.evaluate(() => window.__vroot().querySelector("[data-region='status']").click());
      await page.waitForTimeout(200);
      const sent = await lastDispatch(page, "document_region");
      expect(sent?.context, {pane: "referral", regionId: "status"}, "action");
      expect(await page.evaluate(() => window.__vroot().querySelector("[data-region='status']").dataset.state), "selected", "state");
      expect(
        await page.evaluate(() => window.__surface.dataModel.get("/ui/documents/referral/selected")),
        "status",
        "selected in the data model",
      );
    });

    await check("a region is a keyboard control: Enter activates it", async () => {
      await page.evaluate(() => window.__vroot().querySelector("[data-region='stamp']").focus());
      await page.keyboard.press("Enter");
      await page.waitForTimeout(200);
      const sent = await lastDispatch(page, "document_region");
      expect(sent?.context?.regionId, "stamp", "action");
      expect(await page.evaluate(() => window.__vroot().querySelector("[data-region='stamp']").dataset.state), "empty", "empty stays empty");
    });

    await check("each page's text is in the accessibility tree", async () => {
      const text = await accessibleText(page);
      for (const words of ["Referral for Checkup", "Reason for visit", "Status: scheduled", "Clinic stamp"]) {
        truthy(text.includes(words), `"${words}" is readable`);
      }
      const groups = await page.evaluate(() =>
        [...window.__vroot().querySelectorAll("[data-page-sheet]")].map((s) => `${s.getAttribute("role")}:${s.getAttribute("aria-label")}`),
      );
      expect(groups, ["group:Page 1 of 2", "group:Page 2 of 2"], "page names");
      const label = await page.evaluate(() => window.__vroot().querySelector("[data-region='title']").getAttribute("aria-label"));
      expect(label, "Title, Not reviewed", "a region's name");
    });

    await check("no console errors and no CSP violation (strict CSP)", async () => {
      expect(page.__errors, [], "errors");
      expect(await page.evaluate(() => window.__csp), [], "csp");
    });
    await page.screenshot({path: join(probeDir, "screenshots", "document_pane.png"), fullPage: false});
    await page.close();

    /* --- a review's page tag ---------------------------------------------- */
    const tag = await openCase(browser, base.strict, "payload=document_admin");
    await check("a review's page tag opens the hidden pane at its region", async () => {
      await tag.evaluate(() => {
        const field = [...document.querySelectorAll("*")].length && window.__deep("a[href='#document=status']");
        field.click();
      });
      await waitReady(tag);
      expect(await tag.evaluate(() => window.__surface.dataModel.get("/ui/documents/referral/shown")), true, "shown");
      expect(await tag.evaluate(() => window.__vroot().querySelector("[data-region='status']").dataset.state), "selected", "selected");
      const names = await tag.evaluate(() => window.__dispatched.map((d) => d.name));
      truthy(names.includes("document_pane") && names.includes("document_region"), names.join());
      expect(tag.url().endsWith("payload=document_admin"), true, "no navigation");
      // the region is scrolled into the viewer's view
      const visible = await tag.evaluate(() => {
        const box = window.__vroot().querySelector("[data-region='status']").getBoundingClientRect();
        const area = window.__vroot().querySelector("[data-role='canvas']").getBoundingClientRect();
        return box.top >= area.top && box.bottom <= area.bottom;
      });
      truthy(visible, "scrolled into view");
      expect(tag.__errors, [], "errors");
    });
    await tag.close();

    /* --- 3.8: a value and its region, linked both ways --------------------------- */
    const links = await openCase(browser, base.strict, "payload=document_shown");
    await waitReady(links);
    await links.evaluate(() => {
      window.__source = (id) => window.__deep(`[data-a2ui-region='#document=${id}']`);
      window.__state = (id) => window.__vroot().querySelector(`[data-region='${id}']`).dataset.state;
      window.__active = () => {
        let element = document.activeElement;
        while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement;
        return element;
      };
      window.__inWindow = (element) => {
        const box = element.getBoundingClientRect();
        return box.top >= 0 && box.bottom <= window.innerHeight;
      };
    });
    const centre = (id) =>
      links.evaluate((id) => {
        const box = window.__source(id).getBoundingClientRect();
        return {x: box.left + box.width / 2, y: box.top + box.height / 2};
      }, id);

    await check("3.8: each review field carries its region's address", async () => {
      expect(await links.evaluate(() => [!!window.__source("title"), !!window.__source("status")]), [true, true], "marked");
    });

    await check("3.8: pointing at a value links its region; nothing scrolls the page, moves focus or is sent", async () => {
      const base = await links.evaluate(() => window.__state("status"));
      const sentBefore = await links.evaluate(() => window.__dispatched.length);
      const scrollBefore = await links.evaluate(() => window.scrollY);
      const at = await centre("status");
      await links.mouse.move(at.x, at.y);
      await links.waitForTimeout(400);
      expect(await links.evaluate(() => window.__state("status")), "linked", "hovered");
      expect(await links.evaluate(() => window.scrollY), scrollBefore, "the page did not scroll");
      expect(await links.evaluate(() => window.__dispatched.length), sentBefore, "nothing sent");
      expect(await links.evaluate(() => window.__surface.dataModel.get("/ui/documents/referral/selected") ?? null), null, "nothing written");
      const visible = await links.evaluate(() => {
        const box = window.__vroot().querySelector("[data-region='status']").getBoundingClientRect();
        const area = window.__viewer().scrollArea().getBoundingClientRect();
        return box.top >= area.top && box.bottom <= area.bottom;
      });
      truthy(visible, "the region is in the viewer's view");
      await links.mouse.move(2, 2);
      await links.waitForTimeout(200);
      expect(await links.evaluate(() => window.__state("status")), base, "cleared on leave");
    });

    await check("3.8: focusing a value's page tag links its region and keeps focus there", async () => {
      await links.evaluate(() => window.__deep("a[href='#document=title']").focus());
      await links.waitForTimeout(300);
      expect(await links.evaluate(() => window.__state("title")), "linked", "focused");
      expect(await links.evaluate(() => window.__active()?.getAttribute("href")), "#document=title", "focus stays on the tag");
      await links.evaluate(() => window.__active().blur());
      await links.waitForTimeout(200);
      truthy((await links.evaluate(() => window.__state("title"))) !== "linked", "cleared on blur");
    });

    await check("3.8: clicking a region brings its value into view and flashes it for 3 s", async () => {
      await links.evaluate(() => window.scrollTo(0, document.scrollingElement.scrollHeight));
      await links.evaluate(() => window.__vroot().querySelector("[data-region='title']").scrollIntoView({block: "center"}));
      const box = await links.evaluate(() => {
        const r = window.__vroot().querySelector("[data-region='title']").getBoundingClientRect();
        return {x: r.left + r.width / 2, y: r.top + r.height / 2};
      });
      await links.mouse.click(box.x, box.y);
      await links.waitForTimeout(800);
      expect(await links.evaluate(() => window.__source("title").hasAttribute("data-a2ui-flashed")), true, "flashed");
      truthy(await links.evaluate(() => window.__inWindow(window.__source("title"))), "in the window");
      expect(await links.evaluate(() => getComputedStyle(window.__source("title")).outlineStyle), "solid", "outlined");
      truthy((await links.evaluate(() => window.__active()?.dataset?.region)) === "title", "a click keeps focus on the region");
      await links.waitForTimeout(2600);
      expect(await links.evaluate(() => window.__source("title").hasAttribute("data-a2ui-flashed")), false, "unflashed after 3 s");
    });

    await check("3.8: Enter on a region moves focus to its value", async () => {
      await links.evaluate(() => window.__vroot().querySelector("[data-region='status']").focus());
      await links.keyboard.press("Enter");
      await links.waitForTimeout(800);
      expect(await links.evaluate(() => window.__active() === window.__source("status")), true, "focus on the value");
      expect(await links.evaluate(() => window.__source("status").hasAttribute("data-a2ui-flashed")), true, "flashed");
      truthy(await links.evaluate(() => window.__inWindow(window.__source("status"))), "in the window");
      expect(links.__errors, [], "errors");
    });
    await links.screenshot({path: join(probeDir, "screenshots", "document_links.png"), fullPage: false});
    await links.close();

    const hiddenLinks = await openCase(browser, base.strict, "payload=document_admin");
    await check("3.8: with the pane hidden, pointing at a value does nothing", async () => {
      await hiddenLinks.waitForTimeout(500);
      await hiddenLinks.evaluate(() => (window.__source = (id) => window.__deep(`[data-a2ui-region='#document=${id}']`)));
      const at = await hiddenLinks.evaluate(() => {
        const box = window.__source("status").getBoundingClientRect();
        return {x: box.left + box.width / 2, y: box.top + box.height / 2};
      });
      await hiddenLinks.mouse.move(at.x, at.y);
      await hiddenLinks.waitForTimeout(300);
      expect(await hiddenLinks.evaluate(() => [!!window.__viewer(), window.__pdfLoads, window.__dispatched.length]), [false, 0, 0], "viewer, loads, sent");
    });
    await hiddenLinks.close();

    /* --- narrow: stacked ---------------------------------------------------- */
    const narrow = await openCase(browser, base.strict, "payload=document_shown", {width: 700, height: 900});
    await waitReady(narrow);
    await check("narrow: the document stacks under the sections", async () => {
      const boxes = await narrow.evaluate(() => {
        const root = window.__pane().renderRoot;
        return [root.querySelector(".content").getBoundingClientRect(), root.querySelector(".document").getBoundingClientRect()].map((r) => ({top: r.top, bottom: r.bottom, left: r.left}));
      });
      truthy(boxes[1].top >= boxes[0].bottom - 1, "below");
      truthy(Math.abs(boxes[0].left - boxes[1].left) < 1, "aligned");
      await assertGeometry(narrow, "narrow");
    });
    await check("3.8 narrow: pointing at a value does not link it (the document is not beside it)", async () => {
      const before = await narrow.evaluate(() => window.__vroot().querySelector("[data-region='status']").dataset.state);
      const at = await narrow.evaluate(() => {
        const box = window.__deep("[data-a2ui-region='#document=status']").getBoundingClientRect();
        return {x: box.left + box.width / 2, y: box.top + box.height / 2};
      });
      await narrow.mouse.move(at.x, at.y);
      await narrow.waitForTimeout(300);
      expect(await narrow.evaluate(() => window.__vroot().querySelector("[data-region='status']").dataset.state), before, "state");
    });
    await narrow.close();

    /* --- pre-build checks: the corpus under two CSPs ---------------- */
    if (corpus && existsSync(corpus)) {
      const files = readdirSync(corpus).filter((f) => f.endsWith(".pdf")).sort();
      for (const mode of ["strict", "eval"]) {
        for (const wasm of [false, true]) {
          for (const file of files) {
            const src = encodeURIComponent(`./corpus/${file}`);
            const probe = await openCase(browser, base[mode], `payload=document_shown&src=${src}${wasm ? "&wasm=1" : ""}`);
            let status = null;
            try {
              await waitReady(probe, 45_000);
              status = await probe.evaluate(() => window.__status());
            } catch {
              status = "timeout";
            }
            // pdf.js decodes images off the main thread; give the canvas a moment.
            await probe.waitForTimeout(Number(process.env.DECODE_WAIT_MS ?? 6000));
            const ink = status === "ready" ? await probe.evaluate(() => window.__ink(1)) : 0;
            const pages = await probe.evaluate(() => window.__vroot()?.querySelectorAll("[data-page-sheet]").length ?? 0);
            const csp = await probe.evaluate(() => window.__csp);
            const fetched = (pattern) => probe.__requests.filter((url) => pattern.test(url)).map((url) => url.split("/").pop());
            const label = `${mode}${wasm ? "+wasmUrl" : ""}`;
            notes.push(
              `${label.padEnd(17)} ${file.padEnd(38)} ${String(status).padEnd(7)} pages=${pages} ink=${String(ink).padEnd(7)} ` +
                `csp=${JSON.stringify(csp)} decoders=${JSON.stringify(fetched(/\/wasm\//))} errors=${probe.__errors.length}`,
            );
            // Every file must open; with the decoders served, every page must draw.
            await check(`pre-build (${label}): ${file} ${wasm ? "draws" : "opens"}`, async () => {
              expect(status, "ready", "status");
              if (wasm) truthy(ink > 0, "page 1 inked");
            });
            await probe.close();
          }
        }
      }
    }
  } finally {
    await browser.close();
    Object.values(servers).forEach((server) => server.close());
    rmSync(root, {recursive: true, force: true});
  }

  for (const line of results) console.log(line);
  for (const line of failures) console.log(line);
  if (notes.length) console.log(`\npre-build checks\n${notes.join("\n")}`);
  console.log(`\n${results.length} passed, ${failures.length} failed`);
  process.exit(failures.length === 0 ? 0 : 1);
}

await main();
