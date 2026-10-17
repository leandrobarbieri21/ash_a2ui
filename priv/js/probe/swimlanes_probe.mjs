/**
 * Board-swimlanes probe — the browser gate for swimlaned boards
 * (`swimlanes_by`, see the Boards section of the multi-section topic):
 *
 *   merged catalog (createAshA2uiCatalog)
 *     - every swimlane row is painted from its tone: the row carries
 *       `data-swimlane-tone` from `/_swimlane_tone_<swimlane>` and the
 *       tone's band background, and two tones give two backgrounds;
 *     - every text in a swimlane row reads at WCAG AA (4.5:1) on the
 *       surface it sits on — the band for the headings, totals and pager
 *       text, a Card or Button within it otherwise — in the light and the
 *       dark scheme;
 *     - the board stays horizontal: the stage columns sit side by side and
 *       every cell sits under its stage (same left edge and width), inside
 *       its band;
 *     - at a narrow viewport the stages and swimlanes scroll together
 *       inside the board (`.board-lanes`), the page does not scroll
 *       sideways, the lanes keep their minimum width, and each band spans
 *       all of its cells.
 *   admin catalog (createAshAdminCatalog over the merged catalog)
 *     - the admin_v1 surface renders the board with the basic composition,
 *       so its swimlane rows are painted from their tones the same way.
 *   stock basic catalog
 *     - the same payload renders every swimlane row and cell without
 *       errors (no colour: the basic catalog has no colour props).
 *
 * Fixtures are recorded wire payloads:
 *
 *     MIX_ENV=test mix run priv/js/probe/record_swimlanes.exs
 *
 * Run:
 *
 *     node priv/js/probe/swimlanes_probe.mjs [--node-modules DIR] [--port N]
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

const SWIMLANES = ["board__very_high", "board__low"];
const TONES = {board__very_high: "danger", board__low: "success"};
const STAGES = ["board_open", "board_claimed", "board_completed"];

async function serve() {
  const root = mkdtempSync(join("/tmp", "swimlanes-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "swimlanes_probe.html"), join(root, "swimlanes_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/swimlanes_probe.html`, {method: "HEAD"});
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
  await page.goto(`${base}/swimlanes_probe.html?${query}`, {waitUntil: "load"});
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
    // The rendered element of a component id.
    window.__byId = (id) =>
      window.__deepAll("*").find((el) => el.context?.componentModel?.id === id) ?? null;
    window.__rect = (id) => {
      const rect = window.__byId(id)?.getBoundingClientRect();
      return rect && {left: Math.round(rect.left), right: Math.round(rect.right), width: Math.round(rect.width)};
    };
    // WCAG contrast ratio of two computed rgb()/rgba() colours.
    window.__contrast = (a, b) => {
      const channels = (color) => color.match(/[\d.]+/g).slice(0, 3).map(Number);
      const luminance = (color) => {
        const [r, g, b] = channels(color).map((c) => {
          const v = c / 255;
          return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
        });
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
      };
      const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
      return (hi + 0.05) / (lo + 0.05);
    };
  });
  return page;
}

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath, headless: true});

  try {
    for (const scheme of ["light", "dark"]) {
      const page = await openCase(browser, base, `payload=swimlanes&catalog=ash&scheme=${scheme}`);

      await check(`swimlanes (ash, ${scheme}): each row is painted from its tone`, async () => {
        const rows = await page.evaluate((names) =>
          names.map((name) => {
            const el = window.__byId(`swimlane_${name}`);
            return {
              tone: el?.dataset.swimlaneTone ?? null,
              background: el ? getComputedStyle(el).backgroundColor : null,
            };
          }), SWIMLANES);
        expect(rows.map((row) => row.tone), SWIMLANES.map((name) => TONES[name]), "tones");
        for (const row of rows) {
          truthy(row.background && !/rgba\(0, 0, 0, 0\)|transparent/.test(row.background),
            `a band background (${row.background})`);
        }
        truthy(rows[0].background !== rows[1].background,
          `two tones, two backgrounds (${rows.map((row) => row.background)})`);
      });

      await check(`swimlanes (ash, ${scheme}): every text on a band meets WCAG AA`, async () => {
        // Every rendered Text inside a swimlane row — on the band itself
        // (headings, totals, empty-state and pagination texts) or on a
        // Card or Button within it — against the surface it sits on: the
        // nearest ancestor with an opaque background.
        const {checked, low} = await page.evaluate(() => {
          const parentOf = (node) => node.parentElement ?? node.getRootNode?.()?.host ?? null;
          const inBand = (el) => {
            for (let node = parentOf(el); node; node = parentOf(node)) {
              if (node.context?.componentModel?.id?.startsWith("swimlane_")) return true;
            }
            return false;
          };
          const surface = (el) => {
            for (let node = el; node; node = parentOf(node)) {
              const background = getComputedStyle(node).backgroundColor;
              const alpha = background.startsWith("rgba") ? Number(background.match(/[\d.]+/g)[3]) : 1;
              if (alpha > 0) return background;
            }
            return getComputedStyle(document.body).backgroundColor;
          };
          const seen = new Set();
          const checked = [];
          const low = [];
          for (const el of window.__deepAll("*")) {
            const model = el.context?.componentModel;
            if (model?.type !== "Text" || seen.has(model.id) || !inBand(el)) continue;
            // 0.11.x colours an inner .a2ui-text span, 0.10.x the host.
            const root = el.renderRoot ?? el.shadowRoot ?? el;
            const span = root.querySelector?.(".a2ui-text") ?? el;
            const rect = span.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0 || root.textContent.trim() === "") continue;
            seen.add(model.id);
            const ratio = window.__contrast(getComputedStyle(span).color, surface(span));
            checked.push(model.id);
            if (ratio < 4.5) low.push(`${model.id}=${ratio.toFixed(2)}`);
          }
          return {checked, low};
        });
        expect(low, [], "below 4.5:1");
        // The fixture puts every kind of band text on screen: swimlane
        // headings and totals, cell totals, a page text and a pager button.
        for (const pattern of [/^swimlane_.+_heading$/, /^swimlane_.+_total$/, /^lane_.+__.+_total$/,
          /_page_text$/, /_next_text$/]) {
          truthy(checked.some((id) => pattern.test(id)), `a ${pattern} text was checked (${checked.length} checked)`);
        }
      });

      await check(`swimlanes (ash, ${scheme}): only texts on a band take its ink`, async () => {
        const stray = await page.evaluate(() => {
          const parentOf = (node) => node.parentElement ?? node.getRootNode?.()?.host ?? null;
          const inBand = (el) => {
            for (let node = parentOf(el); node; node = parentOf(node)) {
              if (node.context?.componentModel?.id?.startsWith("swimlane_")) return true;
            }
            return false;
          };
          return window.__deepAll("[data-swimlane-ink]")
            .filter((el) => !inBand(el))
            .map((el) => el.context?.componentModel?.id ?? el.tagName);
        });
        expect(stray, [], "inked outside a band");
      });

      if (scheme === "light") {
        await check("swimlanes (ash): stages side by side, every cell under its stage", async () => {
          const layout = await page.evaluate(({names, stages}) => ({
            stages: stages.map((stage) => window.__rect(`stage_${stage}`)),
            rows: names.map((name) => ({
              band: window.__rect(`swimlane_${name}`),
              cells: stages.map((stage) => window.__rect(`lane_${stage}__${name.split("__")[1]}`)),
            })),
          }), {names: SWIMLANES, stages: STAGES});
          for (let i = 1; i < layout.stages.length; i++) {
            truthy(layout.stages[i].left >= layout.stages[i - 1].right,
              `stage ${i} right of stage ${i - 1} (${JSON.stringify(layout.stages)})`);
          }
          for (const row of layout.rows) {
            row.cells.forEach((cell, i) => {
              const stage = layout.stages[i];
              truthy(Math.abs(cell.left - stage.left) <= 2 && Math.abs(cell.width - stage.width) <= 2,
                `cell ${i} under its stage (cell ${JSON.stringify(cell)}, stage ${JSON.stringify(stage)})`);
              truthy(cell.left >= row.band.left && cell.right <= row.band.right,
                `cell ${i} inside its band (${JSON.stringify(cell)} in ${JSON.stringify(row.band)})`);
            });
          }
        });

        await check("swimlanes (ash): a narrow board scrolls stages and swimlanes together", async () => {
          await page.setViewportSize({width: 600, height: 900});
          await page.waitForTimeout(300);
          const layout = await page.evaluate(({names, stages}) => {
            const scroller = window.__deepAll(".board-lanes")[0];
            return {
              pageWidth: document.documentElement.scrollWidth,
              overflow: scroller && getComputedStyle(scroller).overflowX,
              scrolls: scroller && scroller.scrollWidth > scroller.clientWidth,
              stages: stages.map((stage) => window.__rect(`stage_${stage}`)),
              rows: names.map((name) => ({
                band: window.__rect(`swimlane_${name}`),
                cells: stages.map((stage) => window.__rect(`lane_${stage}__${name.split("__")[1]}`)),
              })),
            };
          }, {names: SWIMLANES, stages: STAGES});
          truthy(layout.pageWidth <= 600, `the page does not scroll sideways (${layout.pageWidth}px)`);
          expect(layout.overflow, "auto", "the board frame scrolls");
          expect(layout.scrolls, true, "stages and swimlanes overflow inside the frame");
          truthy(Math.min(...layout.stages.map((stage) => stage.width)) >= 200,
            `stages keep a minimum width (${layout.stages.map((stage) => stage.width)})`);
          for (const row of layout.rows) {
            const last = row.cells[row.cells.length - 1];
            truthy(row.band.right >= last.right, `the band spans its cells (${row.band.right} < ${last.right})`);
            row.cells.forEach((cell, i) =>
              truthy(Math.abs(cell.left - layout.stages[i].left) <= 2, `cell ${i} still under its stage`));
          }
          await page.setViewportSize({width: 1280, height: 900});
          await page.waitForTimeout(200);
        });
      }

      await check(`no console errors (swimlanes, ash, ${scheme})`, async () => {
        expect(page.__errors, [], "errors");
      });
      await page.screenshot({path: join(probeDir, "screenshots", `swimlanes_ash_${scheme}.png`), fullPage: true});
      await page.close();
    }

    const admin = await openCase(browser, base, "payload=swimlanes_admin&catalog=ash");
    await check("swimlanes (admin): the basic fallback paints each row from its tone", async () => {
      const tones = await admin.evaluate((names) =>
        names.map((name) => window.__byId(`swimlane_${name}`)?.dataset.swimlaneTone ?? null), SWIMLANES);
      expect(tones, SWIMLANES.map((name) => TONES[name]), "tones");
    });
    await check("no console errors (swimlanes, admin)", async () => {
      expect(admin.__errors, [], "errors");
    });
    await admin.close();

    const page = await openCase(browser, base, "payload=swimlanes&catalog=stock");
    await check("swimlanes (stock): every row and cell renders", async () => {
      const present = await page.evaluate(({names, stages}) =>
        names.flatMap((name) =>
          [`swimlane_${name}`].concat(stages.map((stage) => `lane_${stage}__${name.split("__")[1]}`)),
        ).map((id) => Boolean(window.__byId(id))), {names: SWIMLANES, stages: STAGES});
      truthy(present.every(Boolean), `all rendered (${present})`);
    });
    await check("no console errors (swimlanes, stock)", async () => {
      expect(page.__errors, [], "errors");
    });
    await page.screenshot({path: join(probeDir, "screenshots", "swimlanes_stock.png"), fullPage: true});
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
