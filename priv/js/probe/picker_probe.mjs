/**
 * Picker composite probe — the verification gate for the searchable-select
 * combobox (`form_select_<field>`) and the plain-select regression path.
 *
 * Assembles a temporary web root (a node_modules tree + this repo's priv/js
 * + the recorded fixtures), serves it, and drives the real catalogs with
 * the real wire payloads captured from `AshA2ui.Test.TicketSearchUI`
 * (searchable `author_id`) and `AshA2ui.Test.Post` (plain ChoicePicker).
 * Fixtures are re-recorded with:
 *
 *     MIX_ENV=test mix run priv/js/probe/record_forms.exs
 *
 * (each surface plus the start_create reply for its _open_ fixture, and
 * `AshA2ui.Test.Post` for the plain path).
 *
 * Run:
 *
 *     node priv/js/probe/picker_probe.mjs [--node-modules DIR] [--port N]
 *
 * `--node-modules` is any tree with @a2ui/lit + @a2ui/web_core 0.15.0 or later and
 * lit 3 (defaults to a sibling clinic-demo checkout — the versions the
 * integration runs against). Chrome comes from $CHROME.
 *
 * Asserts (never assumes):
 *   1. panel gating — the composite is NOT in the DOM before the create
 *      panel opens (the behavior a pre-panel DOM inspection misreads as
 *      "never rendered")
 *   2. after open: the composite upgrades (combobox input, aria contract:
 *      role=combobox, aria-expanded, aria-controls resolves, listbox/
 *      option roles, aria-activedescendant under arrow keys)
 *   3. no options before typing (the flat-list guard)
 *   4. typing dispatches the wire's option_search with the resolved
 *      binding context; a simulated server reply renders the options
 *   5. keyboard + click selection dispatch option_select with the
 *      template-relative option value; the selection chip renders and
 *      /form/<field> reaches the same end state the plain select path
 *      reaches client-side
 *   6. Escape closes
 *   7. degradation: a contract-id composite that fails structural
 *      verification renders the plain composite AND warns by name (the
 *      silence trap behind the intake misdiagnosis)
 *   8. regression: the plain (non-searchable) select still renders as the
 *      native <select> upgrade, sets /form/<field> on change, and no
 *      combobox leaks into it
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
const port = Number(arg("port", "4180"));
const executablePath = process.env.CHROME || "/usr/bin/google-chrome";
const playwrightModule = `${process.env.PLAYWRIGHT_NODE_MODULES ?? `${process.cwd()}/node_modules`}/playwright/index.mjs`;
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

/** Builds the temp web root and serves it; resolves to a base URL + stop(). */
async function serve() {
  const root = mkdtempSync(join("/tmp", "nb-picker-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "picker_probe.html"), join(root, "picker_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  // Wait for readiness.
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/picker_probe.html`, {method: "HEAD"});
      break;
    } catch {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  return {base, stop: () => {
    server.kill();
    rmSync(root, {recursive: true, force: true});
  }};
}

/** The page exposes no helpers for shadow traversal — this is the runner's. */
function deepHelpers() {
  // Serialized into evaluate() calls below.
}

async function openCase(page, base, query) {
  await page.goto(`${base}/picker_probe.html?${query}`, {waitUntil: "load"});
  await page.waitForFunction(() => window.__boot?.stage && window.__boot.stage !== "imports-done");
  await page.waitForTimeout(400);
}

async function pickerColumn(page, id) {
  return page.evaluate((componentId) => {
    const columns = [];
    const walk = (root) => {
      for (const el of root.querySelectorAll("*")) {
        if (el.tagName === "ASH-A2UI-COLUMN") columns.push(el);
        if (el.shadowRoot) walk(el.shadowRoot);
      }
    };
    walk(document);
    const column = columns.find((el) => el.context?.componentModel?.id === componentId);
    return column
      ? {
          found: true,
          picker: !!column.picker,
          comboboxInput: !!column.shadowRoot?.querySelector(".combobox-input"),
          shadowTags: column.shadowRoot
            ? [...column.shadowRoot.querySelectorAll("*")].map((el) => el.tagName.toLowerCase())
            : [],
        }
      : {found: false};
  }, id);
}

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath});

  /* ---- ticket case: bootstrap (panel closed) --------------------------- */
  let page = await browser.newPage();
  const consoleWarnings = [];
  page.on("console", (message) => {
    if (message.type() === "warning") consoleWarnings.push(message.text());
  });
  await openCase(page, base, "payload=ticket");

  await check("gating: composite absent before the create panel opens", async () => {
    const state = await page.evaluate(() => window.__boot);
    expect(state.stage, "booted", "boot stage");
    expect(state.surfaceCreated, true, "surface created");
    const column = await pickerColumn(page, "form_select_author_id");
    expect(column.found, false, "composite must not materialize while the panel is closed");
    expect(
      await page.evaluate(() => {
        let found = false;
        const walk = (root) => {
          for (const el of root.querySelectorAll("*")) {
            if (el.classList?.contains("combobox-input")) found = true;
            if (el.shadowRoot) walk(el.shadowRoot);
          }
        };
        walk(document);
        return found;
      }),
      false,
      "no combobox anywhere",
    );
  });

  /* ---- ticket case: panel open + interaction --------------------------- */
  await page.close();
  page = await browser.newPage();
  const warnings = [];
  page.on("console", (message) => {
    if (message.type() === "warning") warnings.push(message.text());
  });
  await openCase(page, base, "payload=ticket&open=1");

  await check("open: the composite materializes and upgrades", async () => {
    expect(await page.evaluate(() => window.__boot.stage), "panel-open", "stage");
    const column = await pickerColumn(page, "form_select_author_id");
    expect(column.found, true, "composite column renders");
    expect(column.picker, true, "detectPicker verified the composite");
    expect(column.comboboxInput, true, "combobox input rendered");
    const degradations = warnings.filter((text) => text.includes("did not verify") || text.includes("picker detection"));
    expect(degradations.length, 0, `no degradation warnings (got ${degradations.join(" | ")})`);
  });

  let input = page.locator(".combobox-input").first();

  await check("aria: the combobox contract", async () => {
    const aria = await input.evaluate((el) => ({
      role: el.getAttribute("role"),
      expanded: el.getAttribute("aria-expanded"),
      controls: el.getAttribute("aria-controls"),
      autocomplete: el.getAttribute("aria-autocomplete"),
    }));
    expect(aria.role, "combobox", "role");
    expect(aria.expanded, "false", "collapsed at rest");
    expect(aria.autocomplete, "list", "aria-autocomplete");
    // aria-controls must resolve to the popup listbox — which exists only
    // while open, so check with the popup rendered.
    await input.click();
    await page.waitForTimeout(100);
    await input.evaluate((el) => {
      const id = el.getAttribute("aria-controls");
      if (!el.getRootNode().querySelector(`#${CSS.escape(id)}`))
        throw new Error(`aria-controls ${id} does not resolve`);
    });
    await input.press("Escape");
  });

  await check("focus opens; no options before typing (the flat-list guard)", async () => {
    await input.blur();
    await input.click();
    await page.waitForTimeout(100);
    expect(await input.getAttribute("aria-expanded"), "true", "expanded on focus");
    const hint = await page.evaluate(() => {
      let popup = null;
      const walk = (root) => {
        for (const el of root.querySelectorAll("*")) {
          if (el.classList?.contains("combobox-popup")) popup = el;
          if (el.shadowRoot) walk(el.shadowRoot);
        }
      };
      walk(document);
      return popup ? {role: popup.getAttribute("role"), text: popup.textContent.trim()} : null;
    });
    expect(hint.role, "listbox", "popup is a listbox");
    expect(hint.text.includes("Type to search"), true, "hint, not the pre-loaded options");
  });

  await check("typing dispatches option_search with the resolved binding", async () => {
    await input.fill("a");
    await page.waitForTimeout(450); // debounce 250ms + settle
    const dispatched = await page.evaluate(() => window.__dispatched);
    const search = dispatched.find((action) => action.name === "option_search");
    if (!search) throw new Error(`no option_search dispatched (${JSON.stringify(dispatched)})`);
    expect(search.source, "form_select_author_id_search_button", "source is the frozen search-button id");
    expect(search.context.field, "author_id", "field context");
    expect(search.context.search, "a", "search text resolved from /select/author_id/search");
  });

  await check("a simulated reply renders the options", async () => {
    await page.evaluate((surfaceId) => {
      window.__feed([
        {
          version: "1.0",
          updateDataModel: {
            surfaceId,
            path: "/options/author_id",
            value: [
              {label: "Ada Lovelace", value: "11111111-1111-1111-1111-111111111111"},
              {label: "Grace Hopper", value: "22222222-2222-2222-2222-222222222222"},
              {label: "Alan Turing", value: "33333333-3333-3333-3333-333333333333"},
            ],
          },
        },
      ]);
    }, await page.evaluate(() => window.__surfaceId));
    await page.waitForTimeout(200);
    const options = await page.evaluate(() => {
      let popup = null;
      const walk = (root) => {
        for (const el of root.querySelectorAll("*")) {
          if (el.classList?.contains("combobox-popup")) popup = el;
          if (el.shadowRoot) walk(el.shadowRoot);
        }
      };
      walk(document);
      return popup
        ? [...popup.querySelectorAll(".combobox-option")].map((option) => ({
            role: option.getAttribute("role"),
            label: option.textContent.trim(),
          }))
        : null;
    });
    expect(options?.length, 3, "three options");
    expect(options[0].role, "option", "options carry role=option");
    expect(options[0].label, "Ada Lovelace", "option label text");
  });

  await check("arrows drive aria-activedescendant; Enter selects", async () => {
    await input.press("ArrowDown");
    let descendant = await input.getAttribute("aria-activedescendant");
    expect(descendant.endsWith("_opt_0"), true, `first arrow lands on opt_0 (${descendant})`);
    await input.press("ArrowDown");
    await input.press("ArrowDown");
    descendant = await input.getAttribute("aria-activedescendant");
    expect(descendant.endsWith("_opt_2"), true, "wraps through the list");
    await input.press("Enter");
    await page.waitForTimeout(150);
    const dispatched = await page.evaluate(() => window.__dispatched);
    const select = dispatched.find((action) => action.name === "option_select");
    if (!select) throw new Error("no option_select dispatched");
    expect(select.source, "form_select_author_id_option_button", "source is the frozen option-button id");
    expect(select.context.field, "author_id", "field context");
    expect(select.context.value, "33333333-3333-3333-3333-333333333333", "template-relative value resolved");
    expect(await input.getAttribute("aria-expanded"), "false", "popup closed after selection");
  });

  await check("selection round-trip reaches the plain path's end state", async () => {
    // The server's follow-up writes the form value + the resolved label.
    await page.evaluate(async () => {
      const surfaceId = window.__surfaceId;
      window.__feed([
        {version: "1.0", updateDataModel: {surfaceId, path: "/form/author_id", value: "33333333-3333-3333-3333-333333333333"}},
        {version: "1.0", updateDataModel: {surfaceId, path: "/select/author_id/label", value: "Alan Turing"}},
      ]);
    });
    await page.waitForTimeout(250);
    const state = await page.evaluate(() => {
      let chip = null;
      let surface = null;
      const walk = (root) => {
        for (const el of root.querySelectorAll("*")) {
          if (el.classList?.contains("chip") && el.classList.contains("selected")) chip = el;
          if (el.context?.dataContext?.surface) surface = el.context.dataContext.surface;
          if (el.shadowRoot) walk(el.shadowRoot);
        }
      };
      walk(document);
      return {
        chip: chip ? chip.textContent.trim() : null,
        formValue: surface ? surface.dataModel.get("/form/author_id") : null,
      };
    });
    expect(state.chip, "Alan Turing", "selection chip renders the server's label");
    expect(state.formValue, "33333333-3333-3333-3333-333333333333", "/form/author_id set — parity with the plain select path");
  });

  await check("Escape closes the popup", async () => {
    await input.click();
    await page.waitForTimeout(100);
    await input.press("Escape");
    expect(await input.getAttribute("aria-expanded"), "false", "collapsed after Escape");
  });

  /* ---- degradation: contract id, broken structure ---------------------- */
  await page.close();
  page = await browser.newPage();
  const brokenWarnings = [];
  page.on("console", (message) => {
    if (message.type() === "warning") brokenWarnings.push(message.text());
  });
  await openCase(page, base, "payload=ticket&open=1&broken=1");

  await check("degradation: plain render + a named warning", async () => {
    const column = await pickerColumn(page, "form_select_author_id");
    expect(column.found, true, "the composite column still renders");
    expect(column.picker, false, "not upgraded");
    expect(column.comboboxInput, false, "no combobox input");
    // The dead-end plain composite: a basic text input inside the column.
    expect(
      column.shadowTags.includes("input"),
      true,
      "the plain composite renders its label + text input",
    );
    const warning = brokenWarnings.find((text) => text.includes("form_select_author_id"));
    if (!warning) throw new Error(`no degradation warning (got: ${brokenWarnings.join(" | ")})`);
    if (!warning.includes("did not verify") || !warning.includes("_option_button"))
      throw new Error(`warning does not name the failed piece: ${warning}`);
  });

  /* ---- regression: the plain (non-searchable) select path -------------- */
  await page.close();
  page = await browser.newPage();
  await openCase(page, base, "payload=post");

  await check("regression: plain select renders as the native select upgrade", async () => {
    // The Post form is panel-gated like every form — open it first.
    await page.evaluate(async () => {
      const open = await (await fetch("./fixtures/post_open_payload.json")).json();
      window.__feed(open.messages);
    });
    await page.waitForTimeout(300);
    const state = await page.evaluate(() => {
      let picker = null;
      let combobox = false;
      const walk = (root) => {
        for (const el of root.querySelectorAll("*")) {
          if (el.tagName === "ASH-A2UI-CHOICEPICKER") picker = el;
          if (el.classList?.contains("combobox-input")) combobox = true;
          if (el.shadowRoot) walk(el.shadowRoot);
        }
      };
      walk(document);
      return {
        choicepicker: !!picker,
        nativeSelect: picker ? !!picker.shadowRoot.querySelector("select") : false,
        combobox,
        pickerColumnUpgraded: (() => {
          const columns = [];
          const walkColumns = (root) => {
            for (const el of root.querySelectorAll("ASH-A2UI-COLUMN")) columns.push(el);
            for (const el of root.querySelectorAll("*")) if (el.shadowRoot) walkColumns(el.shadowRoot);
          };
          walkColumns(document);
          return columns.some((column) => column.picker);
        })(),
      };
    });
    expect(state.choicepicker, true, "form_input_author_id renders the merged choicepicker");
    expect(state.nativeSelect, true, "with a native <select>");
    expect(state.combobox, false, "no combobox leaked into the plain path");
    expect(state.pickerColumnUpgraded, false, "no column upgraded");
  });

  await check("regression: the native select sets /form/author_id on change", async () => {
    // Fill the static options the way an updateComponents message would.
    await page.evaluate(async () => {
      const boot = await (await fetch("./fixtures/post_payload.json")).json();
      for (const message of boot.messages) {
        if (!message.updateComponents) continue;
        for (const component of message.updateComponents.components) {
          if (component.id === "form_input_author_id") {
            component.options = [
              {label: "Ada Lovelace", value: "11111111-1111-1111-1111-111111111111"},
              {label: "Grace Hopper", value: "22222222-2222-2222-2222-222222222222"},
            ];
          }
        }
        window.__feed([message]);
        break;
      }
    });
    await page.waitForTimeout(250);
    const select = page.locator("ash-a2ui-choicepicker select").first();
    await select.selectOption("22222222-2222-2222-2222-222222222222");
    await page.waitForTimeout(150);
    const formValue = await page.evaluate(() => {
      let surface = null;
      const walk = (root) => {
        for (const el of root.querySelectorAll("*")) {
          if (el.context?.dataContext?.surface) surface = el.context.dataContext.surface;
          if (el.shadowRoot) walk(el.shadowRoot);
        }
      };
      walk(document);
      return surface ? surface.dataModel.get("/form/author_id") : null;
    });
    expect(
      Array.isArray(formValue) ? formValue[0] : formValue,
      "22222222-2222-2222-2222-222222222222",
      "plain path end state (client-side set, binder array shape)",
    );
  });

  await browser.close();
  stop();

  console.log(results.join("\n"));
  if (failures.length) {
    console.error(`\n${failures.join("\n")}`);
    console.error(`\n${failures.length} failure(s)`);
    process.exit(1);
  }
  console.log(`\nall ${results.length} checks passed`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
