/**
 * Adoption-findings probe — the browser gate for the renderer half of the
 * issues adopting ash_a2ui in ash_enterprise and clinic-demo surfaced:
 *
 *   admin catalog (JobsUI under admin_v1)
 *     - a prompt row action opens a prompt dialog that collects its values,
 *       pre-fills through `prompt`, dispatches `invoke` with the typed
 *       values, stays open (showing the error) on a failed confirm and
 *       closes on success; Tab and Shift+Tab stay inside the dialog;
 *     - relationship and enum prompt fields render as pickers;
 *     - row actions with `visible_when` show only on the rows they apply to;
 *     - a row action's busy state settles once on its outcome and then
 *       releases its data-model subscriptions;
 *     - the read-only View panel has a control that closes it.
 *   boards (JobBoardUI, basic composition)
 *     - lanes share the board's width instead of sizing to their cards, on
 *       the stock basic catalog and on the AshA2ui merged catalog (where
 *       the lanes scroll horizontally inside the board).
 *
 * Fixtures are recorded wire payloads:
 *
 *     MIX_ENV=test mix run priv/js/probe/record_adoption.exs
 *
 * Run:
 *
 *     node priv/js/probe/adoption_probe.mjs [--node-modules DIR] [--port N]
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
const port = Number(arg("port", "4192"));
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
  const root = mkdtempSync(join("/tmp", "adoption-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "adoption_probe.html"), join(root, "adoption_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/adoption_probe.html`, {method: "HEAD"});
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
  await page.goto(`${base}/adoption_probe.html?${query}`, {waitUntil: "load"});
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
    // The buttons of the grid row whose first cell reads `title`.
    window.__rowButtons = (title) => {
      const row = window
        .__deepAll(".grid-table tbody tr")
        .find((tr) => tr.querySelector("th")?.textContent.trim() === title);
      return row ? [...row.querySelectorAll("td.cell-actions button")] : null;
    };
    window.__dialog = () =>
      window.__deepAll('[role="dialog"]').find((el) => el.getClientRects().length > 0) ?? null;
    // Text of an element including its descendants' shadow roots.
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

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath});

  try {
    /* --- admin: per-row visibility -------------------------------------- */
    let page = await openCase(browser, base, "payload=adoption_admin");

    await check("admin: a visible_when row action shows only on the rows it applies to", async () => {
      const labels = await page.evaluate(() => ({
        open: window.__rowButtons("Open job")?.map((b) => b.textContent.trim()),
        claimed: window.__rowButtons("Claimed job")?.map((b) => b.textContent.trim()),
      }));
      truthy(labels.open && labels.claimed, "both rows render");
      const claim = (list) => list.some((text) => /^(Claim|Take it)$/.test(text));
      expect(claim(labels.open), true, `open row offers the claim (${labels.open})`);
      expect(claim(labels.claimed), false, `claimed row hides it (${labels.claimed})`);
      expect(labels.claimed.includes("Lock"), true, "unconditional actions stay");
    });

    /* --- admin: a prompt row action ------------------------------------- */
    await check("admin: a prompt row action opens a dialog and pre-fills through `prompt`", async () => {
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        window.__rowButtons("Open job").find((b) => b.textContent.trim() === "Annotate").click();
      });
      await page.waitForTimeout(200);
      const state = await page.evaluate(() => ({
        dispatched: window.__dispatched,
        dialog: !!window.__dialog(),
        heading: window.__dialog()?.querySelector("h2")?.textContent.trim(),
      }));
      expect(state.dialog, true, "dialog visible");
      expect(state.heading, "Annotate", "dialog heading");
      expect(state.dispatched.map((d) => d.name), ["prompt"], "only the pre-fill dispatched");
      expect(state.dispatched[0].context.action, "annotate", "prompt action");
      expect(typeof state.dispatched[0].context.recordId, "string", "row id resolved");
    });

    await check("admin: Confirm dispatches invoke with the typed values", async () => {
      const input = await page.evaluateHandle(() => {
        const dialog = window.__dialog();
        const find = (root) => {
          for (const el of root.querySelectorAll("*")) {
            if (el.tagName === "INPUT" || el.tagName === "TEXTAREA") return el;
            if (el.shadowRoot) {
              const found = find(el.shadowRoot);
              if (found) return found;
            }
          }
          return null;
        };
        return find(dialog);
      });
      truthy(await input.evaluate((el) => !!el), "dialog has an input");
      await input.fill("Called the owner");
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        [...window.__dialog().querySelectorAll("button")]
          .find((b) => b.textContent.trim() === "Confirm")
          .click();
      });
      await page.waitForTimeout(200);
      const dispatched = await page.evaluate(() => window.__dispatched);
      expect(dispatched.length, 1, "one dispatch");
      expect(dispatched[0].name, "invoke", "invoke");
      expect(dispatched[0].context.action, "annotate", "action");
      expect(dispatched[0].context.values, {note: "Called the owner"}, "values");
    });

    await check("admin: a failed confirm keeps the dialog open with the message", async () => {
      await feed(page, "adoption_admin_annotate_error");
      const state = await page.evaluate(() => ({
        dialog: !!window.__dialog(),
        text: window.__dialog() ? window.__deepText(window.__dialog()) : "",
      }));
      expect(state.dialog, true, "still open");
      truthy(/required/i.test(state.text), `the field error shows (${state.text.slice(0, 160)})`);
    });

    await check("admin: a successful confirm closes the dialog", async () => {
      await page.evaluate(() => {
        [...window.__dialog().querySelectorAll("button")]
          .find((b) => b.textContent.trim() === "Confirm")
          .click();
      });
      await feed(page, "adoption_admin_annotate_ok");
      expect(await page.evaluate(() => !!window.__dialog()), false, "closed");
    });

    await check("admin: Cancel closes the prompt without dispatching", async () => {
      await page.evaluate(() => {
        window.__rowButtons("Open job").find((b) => b.textContent.trim() === "Annotate").click();
      });
      await page.waitForTimeout(200);
      await page.evaluate(() => {
        window.__dispatched.length = 0;
        [...window.__dialog().querySelectorAll("button")]
          .find((b) => b.textContent.trim() === "Cancel")
          .click();
      });
      await page.waitForTimeout(150);
      expect(await page.evaluate(() => !!window.__dialog()), false, "closed");
      expect(await page.evaluate(() => window.__dispatched.length), 0, "nothing dispatched");
    });

    await check("admin: Tab and Shift+Tab stay inside the prompt dialog", async () => {
      await page.evaluate(() => {
        window.__rowButtons("Open job").find((b) => b.textContent.trim() === "Annotate").click();
      });
      await page.waitForTimeout(200);
      // What has focus inside the dialog's shadow root: "heading", a
      // button's text, "inside" (a nested input) or "outside".
      const focused = () =>
        page.evaluate(() => {
          const dialog = window.__dialog();
          if (!dialog) return "no dialog";
          const active = dialog.getRootNode().activeElement;
          if (!active || !dialog.contains(active)) return "outside";
          if (active.hasAttribute("data-prompt-heading")) return "heading";
          if (active.tagName === "BUTTON") return active.textContent.trim();
          return "inside";
        });
      expect(await focused(), "heading", "focus starts on the heading");
      await page.keyboard.press("Shift+Tab");
      expect(await focused(), "Confirm", "Shift+Tab from the heading wraps to the last button");
      await page.keyboard.press("Tab");
      expect(await focused(), "heading", "Tab from the last button wraps to the heading");
      await page.keyboard.press("Tab");
      expect(await focused(), "inside", "Tab from the heading reaches the input");
      await page.keyboard.press("Shift+Tab");
      expect(await focused(), "Confirm", "Shift+Tab from the first input wraps to the last button");
      await page.evaluate(() => {
        [...window.__dialog().querySelectorAll("button")]
          .find((b) => b.textContent.trim() === "Cancel")
          .click();
      });
      await page.waitForTimeout(100);
    });

    await check("admin: relationship and enum prompt fields render as pickers", async () => {
      const pickers = {};
      for (const action of ["Assign", "Reprioritize"]) {
        await page.evaluate((label) => {
          window.__rowButtons("Open job").find((b) => b.textContent.trim().startsWith(label)).click();
        }, action);
        await page.waitForTimeout(200);
        pickers[action] = await page.evaluate(() => {
          const dialog = window.__dialog();
          if (!dialog) return null;
          const options = [];
          const walk = (root) => {
            for (const el of root.querySelectorAll("*")) {
              if (el.tagName === "OPTION" || (el.tagName === "INPUT" && el.type === "radio")) {
                options.push((el.textContent || el.value || "").trim());
              }
              if (el.shadowRoot) walk(el.shadowRoot);
            }
          };
          walk(dialog);
          return options;
        });
        await page.evaluate(() => {
          [...window.__dialog().querySelectorAll("button")]
            .find((b) => b.textContent.trim() === "Cancel")
            .click();
        });
        await page.waitForTimeout(100);
      }
      truthy(pickers.Assign && pickers.Assign.length >= 2, `clerk options (${JSON.stringify(pickers.Assign)})`);
      truthy(
        pickers.Reprioritize && pickers.Reprioritize.length >= 3,
        `priority options (${JSON.stringify(pickers.Reprioritize)})`,
      );
    });

    /* --- admin: a settled row action releases its subscriptions --------- */
    await check("admin: a settled row action releases its outcome subscriptions", async () => {
      const writeFeedback = (message) =>
        page.evaluate((text) => {
          window.__feed([
            {
              version: "v0.9",
              updateDataModel: {surfaceId: "adoption_jobs", path: "/ui/feedback/message", value: text},
            },
          ]);
        }, message);
      const state = await page.evaluate(() => {
        const baseline = window.__surface.dataModel.subscriptions.size;
        window.__dispatched.length = 0;
        window.__rowButtons("Open job").find((b) => b.textContent.trim() === "Lock").click();
        const grid = window.__deepAll("*").find((el) => el._amBusyRowAction);
        window.__settled = 0;
        if (grid) {
          const original = grid.onActionSettled.bind(grid);
          grid.onActionSettled = () => {
            window.__settled += 1;
            original();
          };
        }
        return {
          baseline,
          busy: window.__surface.dataModel.subscriptions.size,
          grid: !!grid,
          dispatched: window.__dispatched.map((d) => d.name),
        };
      });
      truthy(state.grid, "the clicked grid is busy");
      expect(state.dispatched, ["invoke"], "the row action dispatched");
      expect(state.busy, state.baseline + 2, "busy subscribes to the two outcome paths");

      await writeFeedback(`Locked ${Date.now()}`);
      await page.waitForTimeout(100);
      await writeFeedback(`Later feedback ${Date.now()}`);
      await page.waitForTimeout(100);
      const after = await page.evaluate(() => ({
        size: window.__surface.dataModel.subscriptions.size,
        settled: window.__settled,
      }));
      expect(after.settled, 1, "the action settles once, not on every later feedback write");
      expect(after.size, state.baseline, "the outcome subscriptions are released");
    });

    /* --- admin: the View panel closes ------------------------------------ */
    await check("admin: the read-only View panel has a control that closes it", async () => {
      await feed(page, "adoption_admin_view");
      const panel = await page.evaluate(() => {
        const host = window.__deepAll("ash-admin-record-panel")[0];
        const section = host?.shadowRoot?.querySelector("section.panel");
        if (!section) return null;
        const buttons = [];
        const walk = (root) => {
          for (const el of root.querySelectorAll("*")) {
            if (el.tagName === "BUTTON") buttons.push(window.__deepText(el));
            if (el.shadowRoot) walk(el.shadowRoot);
          }
        };
        walk(section);
        return {buttons};
      });
      truthy(panel, "the view panel is open");
      truthy(panel.buttons.some((text) => /^(Cancel|Close)$/.test(text)), `a close control (${panel.buttons})`);

      await page.evaluate(() => {
        window.__dispatched.length = 0;
        const section = window.__deepAll("ash-admin-record-panel")[0].shadowRoot.querySelector("section.panel");
        const walk = (root) => {
          for (const el of root.querySelectorAll("*")) {
            if (el.tagName === "BUTTON" && /^(Cancel|Close)$/.test(window.__deepText(el))) return el;
            if (el.shadowRoot) {
              const found = walk(el.shadowRoot);
              if (found) return found;
            }
          }
          return null;
        };
        walk(section).click();
      });
      await page.waitForTimeout(150);
      const names = await page.evaluate(() => window.__dispatched.map((d) => d.name));
      expect(names, ["cancel_record_task"], "the close dispatches cancel_record_task");
    });

    await check("no console errors (admin case)", async () => {
      expect(page.__errors, [], "errors");
    });
    await page.screenshot({path: join(probeDir, "screenshots", "adoption_admin.png"), fullPage: true});
    await page.close();

    /* --- boards: lane widths --------------------------------------------- */
    for (const catalog of ["stock", "ash"]) {
      page = await openCase(browser, base, `payload=adoption_board&catalog=${catalog}`);

      await check(`board (${catalog}): lanes share the board width, not their cards'`, async () => {
        const layout = await page.evaluate(() => {
          const surface = document.querySelector("a2ui-surface");
          const lanes = window
            .__deepAll("*")
            .filter((el) => /^lane_board_/.test(el.context?.componentModel?.id ?? "") &&
              /^lane_board_[a-z]+$/.test(el.context.componentModel.id));
          return {
            pageWidth: document.documentElement.scrollWidth,
            surfaceWidth: surface.getBoundingClientRect().width,
            lanes: lanes.map((el) => Math.round(el.getBoundingClientRect().width)),
          };
        });
        expect(layout.lanes.length, 3, "three lanes");
        truthy(layout.pageWidth <= 1280, `the page does not scroll sideways (${layout.pageWidth}px)`);
        const [min, max] = [Math.min(...layout.lanes), Math.max(...layout.lanes)];
        truthy(max - min <= 2, `equal lanes (${layout.lanes})`);
        truthy(max <= layout.surfaceWidth / 3, `bounded lanes (${layout.lanes} in ${layout.surfaceWidth})`);
      });

      if (catalog === "ash") {
        await check("board (ash): many lanes scroll inside the board at their minimum width", async () => {
          await page.setViewportSize({width: 600, height: 900});
          await page.waitForTimeout(300);
          const layout = await page.evaluate(() => {
            const lanes = window
              .__deepAll("*")
              .filter((el) => /^lane_board_[a-z]+$/.test(el.context?.componentModel?.id ?? ""));
            const scroller = window.__deepAll(".board-lanes")[0];
            return {
              pageWidth: document.documentElement.scrollWidth,
              lanes: lanes.map((el) => Math.round(el.getBoundingClientRect().width)),
              overflow: scroller && getComputedStyle(scroller).overflowX,
              scrolls: scroller && scroller.scrollWidth > scroller.clientWidth,
            };
          });
          truthy(layout.pageWidth <= 600, `the page does not scroll sideways (${layout.pageWidth}px)`);
          expect(layout.overflow, "auto", "the lanes frame scrolls");
          expect(layout.scrolls, true, "lanes overflow inside the frame");
          truthy(Math.min(...layout.lanes) >= 200, `lanes keep a minimum width (${layout.lanes})`);
        });
      }

      await check(`no console errors (board, ${catalog})`, async () => {
        expect(page.__errors, [], "errors");
      });
      await page.screenshot({
        path: join(probeDir, "screenshots", `adoption_board_${catalog}.png`),
        fullPage: true,
      });
      await page.close();
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
