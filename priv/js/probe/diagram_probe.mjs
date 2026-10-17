/**
 * Live-diagram probe — the browser gate for the `diagram` entity (AST-172):
 *
 *   admin catalog (FlowUI under admin_v1, liveDiagram)
 *     - mermaid is not requested before a diagram appears, and is loaded
 *       once when one does (the loader is ash_a2ui_mermaid.js, its own
 *       module, the way a host bundles it);
 *     - the diagram renders as an SVG, and every marker sits on the node
 *       it names; another team's visit has no marker;
 *     - status styling: waiting is dashed, executing pulses, done is muted;
 *     - a linked marker is an anchor with the server-resolved href, and
 *       activating it raises the open-surface event with its surface and
 *       record id;
 *     - a /diagram/<name> data-model write moves a marker without
 *       re-rendering the diagram;
 *     - without a mermaid loader the node list renders instead;
 *     - nothing logs an error.
 *   basic composition (stock basic catalog and the AshA2ui merged one)
 *     - the node list renders each node with its markers; a marker's link
 *       Button dispatches open_surface with the diagram name.
 *
 * Fixtures are recorded wire payloads:
 *
 *     MIX_ENV=test mix run priv/js/probe/record_diagram.exs
 *
 * Run:
 *
 *     node priv/js/probe/diagram_probe.mjs [--node-modules DIR] [--port N]
 *
 * `--node-modules` is any tree with @a2ui/lit + @a2ui/web_core 0.10.x, lit
 * 3 and mermaid 10-12. Chrome comes from $CHROME, Playwright from
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
const port = Number(arg("port", "4194"));
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
  const root = mkdtempSync(join("/tmp", "diagram-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "diagram_probe.html"), join(root, "diagram_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/diagram_probe.html`, {method: "HEAD"});
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
  await page.goto(`${base}/diagram_probe.html?${query}`, {waitUntil: "load"});
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
    window.__diagram = () => window.__deepAll("ash-admin-live-diagram")[0] ?? null;
    window.__markers = () =>
      [...(window.__diagram()?.shadowRoot.querySelectorAll(".diagram-markers .marker") ?? [])].map((m) => ({
        text: m.textContent.trim(),
        tag: m.tagName,
        status: m.dataset.status,
        tone: m.dataset.tone,
        href: m.getAttribute("href"),
        label: m.getAttribute("aria-label"),
        animation: getComputedStyle(m).animationName,
        borderStyle: getComputedStyle(m).borderTopStyle,
        x: m.getBoundingClientRect().left + m.getBoundingClientRect().width / 2,
        y: m.getBoundingClientRect().top + m.getBoundingClientRect().height / 2,
      }));
    // The screen box of the mermaid node `nodeId`.
    window.__nodeBox = (nodeId) => {
      const svg = window.__diagram()?.shadowRoot.querySelector(".diagram-canvas svg");
      const node = [...(svg?.querySelectorAll("g.node") ?? [])].find((g) =>
        new RegExp(`(^|-)${nodeId}(-[0-9]+)?$`).test(g.id),
      );
      if (!node) return null;
      const box = node.getBoundingClientRect();
      return {left: box.left, right: box.right, top: box.top, bottom: box.bottom};
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
    /* --- lazy loading -------------------------------------------------- */
    const empty = await openCase(browser, base, "payload=diagram_admin&boot=empty");
    await check("admin: mermaid is not requested before a diagram appears", async () => {
      expect(await empty.evaluate(() => window.__mermaidLoads), 0, "loads before any diagram");
    });
    await feed(empty, "diagram_admin");
    await empty.waitForFunction(() => window.__diagram()?.shadowRoot.querySelector(".diagram-canvas svg"));
    await check("admin: mermaid loads once when the diagram appears", async () => {
      expect(await empty.evaluate(() => window.__mermaidLoads), 1, "loads after the diagram");
    });
    await empty.close();

    /* --- admin: the live diagram ----------------------------------------- */
    const page = await openCase(browser, base, "payload=diagram_admin");
    await page.waitForFunction(() => window.__diagram()?.shadowRoot.querySelector(".diagram-canvas svg"));
    await page.waitForTimeout(300);

    await check("admin: every marker sits on the node it names", async () => {
      const state = await page.evaluate(() => ({
        markers: window.__markers(),
        boxes: {
          triage: window.__nodeBox("triage"),
          exam: window.__nodeBox("exam"),
          finish: window.__nodeBox("finish"),
        },
      }));
      expect(state.markers.map((m) => m.text).sort(), ["AL", "AT", "GH", "MH"], "one marker per visit");
      const onNode = (marker, box) =>
        box && marker.y >= box.top - 2 && marker.y <= box.bottom + 2 && marker.x >= box.left - 40 && marker.x <= box.right + 40;
      const byText = Object.fromEntries(state.markers.map((m) => [m.text, m]));
      truthy(onNode(byText.AL, state.boxes.triage), `Ada on triage ${JSON.stringify([byText.AL, state.boxes.triage])}`);
      truthy(onNode(byText.AT, state.boxes.triage), "Alan on triage");
      truthy(onNode(byText.GH, state.boxes.exam), "Grace on exam");
      truthy(onNode(byText.MH, state.boxes.finish), "Margaret on finish");
      truthy(byText.AL.x !== byText.AT.x, "two markers on one node sit side by side");
    });

    await check("admin: status styling follows the marker vocabulary", async () => {
      const byText = Object.fromEntries((await page.evaluate(() => window.__markers())).map((m) => [m.text, m]));
      expect(byText.AL.status, "waiting", "Ada waiting");
      expect(byText.AL.borderStyle, "dashed", "waiting is dashed");
      expect(byText.GH.animation, "am-diagram-pulse", "executing pulses");
      expect(byText.AT.borderStyle, "solid", "active is solid");
      expect(byText.MH.status, "done", "done");
    });

    await check("admin: a linked marker opens its server-resolved surface", async () => {
      const marker = await page.evaluate(() => window.__markers().find((m) => m.text === "AL"));
      expect(marker.tag, "A", "anchor");
      truthy(/^\/visits\/[0-9a-f-]{36}$/.test(marker.href), `server href (${marker.href})`);
      truthy(/Ada Lovelace — Triage \(Waiting\)/.test(marker.label), `accessible name (${marker.label})`);
      await page.evaluate(() =>
        [...window.__diagram().shadowRoot.querySelectorAll(".diagram-markers .marker")]
          .find((m) => m.textContent.trim() === "AL")
          .click(),
      );
      const opened = await page.evaluate(() => window.__opened.at(-1));
      expect(opened.surface, "visit", "surface");
      truthy(/^[0-9a-f-]{36}$/.test(opened.recordId), "record id");
      expect(page.url().endsWith("payload=diagram_admin"), true, "no full page navigation");
    });

    await check("admin: a data-model write moves a marker without redrawing", async () => {
      await page.evaluate(() => {
        window.__svgBefore = window.__diagram().shadowRoot.querySelector(".diagram-canvas svg");
      });
      await feed(page, "diagram_moved");
      await page.waitForTimeout(400);
      const state = await page.evaluate(() => ({
        sameSvg: window.__diagram().shadowRoot.querySelector(".diagram-canvas svg") === window.__svgBefore,
        ada: window.__markers().find((m) => m.text === "AL"),
        exam: window.__nodeBox("exam"),
      }));
      expect(state.sameSvg, true, "the diagram did not re-render");
      expect(state.ada.status, "failed", "Ada failed");
      expect(state.ada.tone, "danger", "danger tone");
      truthy(state.ada.y >= state.exam.top - 2 && state.ada.y <= state.exam.bottom + 2, "Ada moved to the exam");
    });

    await check("admin: no console errors", async () => {
      expect(page.__errors, [], "errors");
    });
    await page.screenshot({path: join(probeDir, "screenshots", "diagram_admin.png"), fullPage: true});
    await page.close();

    /* --- admin without a loader: the node list --------------------------- */
    const bare = await openCase(browser, base, "payload=diagram_admin&mermaid=none");
    await check("admin: without mermaid the node list renders", async () => {
      const text = await bare.evaluate(() => window.__deepText(window.__diagram()));
      for (const label of ["Triage", "Exam", "Ada Lovelace (Waiting)", "Grace Hopper (Executing)"]) {
        truthy(text.includes(label), `shows ${label}`);
      }
      expect(await bare.evaluate(() => !!window.__diagram().shadowRoot.querySelector("svg")), false, "no svg");
      expect(bare.__errors, [], "errors");
    });
    await bare.close();

    /* --- basic composition --------------------------------------------- */
    for (const catalog of ["stock", "merged"]) {
      const query = catalog === "stock" ? "payload=diagram_basic&catalog=stock" : "payload=diagram_basic";
      const basic = await openCase(browser, base, query);

      await check(`basic (${catalog}): the node list renders`, async () => {
        const text = await basic.evaluate(() => window.__deepText(document.getElementById("host")));
        for (const label of ["Visits in flight", "Triage", "Exam", "Done", "Ada Lovelace", "Waiting", "GH", "Executing"]) {
          truthy(text.includes(label), `shows ${label}`);
        }
        truthy(!text.includes("Blue Team"), "another team's visit is not there");
      });

      await check(`basic (${catalog}): a marker link dispatches open_surface`, async () => {
        await basic.evaluate(() => {
          window.__dispatched.length = 0;
          window
            .__deepAll("button")
            .find((b) => window.__deepText(b) === "Grace Hopper")
            .click();
        });
        await basic.waitForTimeout(100);
        const sent = await lastDispatch(basic);
        expect(sent?.name, "open_surface", "action");
        expect(sent?.context?.diagram, "flow", "diagram");
        expect(sent?.context?.surface, "visit", "surface");
      });

      await check(`basic (${catalog}): no console errors`, async () => {
        expect(basic.__errors, [], "errors");
      });

      await basic.screenshot({
        path: join(probeDir, "screenshots", `diagram_basic_${catalog}.png`),
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
