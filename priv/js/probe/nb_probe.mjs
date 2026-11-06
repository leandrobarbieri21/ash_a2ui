/**
 * NB component probe — the real gate for Lane D (CI is Elixir-only by
 * design; this file is the evidence trail).
 *
 *   (cd priv/js && python3 -m http.server 4173 &)
 *   CHROME=/usr/bin/google-chrome \
 *   PLAYWRIGHT_NODE_MODULES=/path/to/node_modules \
 *   node priv/js/probe/nb_probe.mjs [url]
 *
 * Asserts — never assumes — the aria wiring and keyboard behavior of every
 * component on nb_demo.html, plus the motion guard under emulated
 * prefers-reduced-motion. Screenshots land next to this file under
 * screenshots/ for the record. Exit code is the verdict.
 */

import {mkdirSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join} from "node:path";

const url = process.argv[2] || "http://127.0.0.1:4173/nb_demo.html";
const playwrightModule = `${process.env.PLAYWRIGHT_NODE_MODULES ?? `${process.cwd()}/node_modules`}/playwright/index.mjs`;
const {chromium} = await import(playwrightModule);

const shotDir = join(dirname(fileURLToPath(import.meta.url)), "screenshots");
mkdirSync(shotDir, {recursive: true});

const executablePath = process.env.CHROME || "/usr/bin/google-chrome";
const failures = [];
const results = [];

/** Records one assertion group; failures are collected, not thrown, so a
 * full picture lands in one run. */
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

async function main() {
  const browser = await chromium.launch({executablePath});
  const page = await (await browser.newContext({viewport: {width: 1280, height: 900}})).newPage();
  page.on("pageerror", (error) => failures.push(`FAIL  pageerror: ${error.message}`));
  await page.goto(url, {waitUntil: "load"});

  // The demo page defers its wiring to the load event; the log starts
  // empty (zero height, so "visible" would never match) — wait for it to
  // exist and for the components to have upgraded.
  await page.waitForSelector("#log", {state: "attached"});
  await page.waitForFunction(() => customElements.get("nb-calendar") !== undefined);

  /* ---------------------------------------------------------------- nb-item */
  await check("nb-item: status dot + selectable wiring", async () => {
    const dots = await page.locator("nb-item").evaluateAll((items) =>
      items.map((item) => {
        const dot = item.shadowRoot.querySelector(".dot");
        return {
          status: item.getAttribute("status"),
          fill: dot ? getComputedStyle(dot).backgroundColor : null,
          role: item.getAttribute("role"),
          tabindex: item.getAttribute("tabindex"),
        };
      }),
    );
    expect(dots.length, 3, "three demo items");
    expect(dots[0].role, "button", "selectable item has role=button");
    expect(dots[0].tabindex, "0", "selectable item is tabbable");
    expect(dots[1].role, null, "plain item has no button role");
    for (const dot of dots) expect(dot.fill.startsWith("rgb("), true, `dot ${dot.status} has a fill`);
    // Different statuses paint different fills.
    expect(new Set(dots.map((d) => d.fill)).size, 3, "statuses paint distinct fills");
  });

  await check("nb-item: Enter fires nb-select", async () => {
    await page.locator("#item-booked").focus();
    await page.keyboard.press("Enter");
    await expectLogged(page, "nb-select", /Rex/);
  });

  /* ---------------------------------------------------------------- nb-menu */
  await check("nb-menu: aria + open/close + keyboard nav", async () => {
    const menu = page.locator("#demo-menu");
    const state = () => menu.evaluate((el) => ({
      expanded: el.shadowRoot.querySelector(".trigger").getAttribute("aria-expanded"),
      hasPopup: el.shadowRoot.querySelector(".trigger").getAttribute("aria-haspopup"),
      open: el.shadowRoot.querySelector(".popup").dataset.open,
    }));
    expect((await state()).hasPopup, "menu", "trigger declares aria-haspopup");
    expect((await state()).expanded, "false", "collapsed at rest");

    // Open with the keyboard (ArrowDown from the trigger). NB: Locator
    // .focus() uses an internal protocol that bypasses a component's
    // focus() override — and the platform refuses a bare shadow host — so
    // focus through the element's own method.
    await menu.evaluate((el) => el.focus());
    await page.keyboard.press("ArrowDown");
    expect((await state()).expanded, "true", "ArrowDown opens");
    const items = () => menu.evaluate((el) => [...el.shadowRoot.querySelectorAll(".mi")].map((b) => ({
      label: b.textContent.trim(),
      disabled: b.disabled,
      role: b.getAttribute("role"),
      checked: b.getAttribute("aria-checked"),
    })));
    expect((await items()).length, 4, "four items rendered from light DOM");
    expect((await items())[0].role, "menuitem", "items are menuitems");
    expect((await items())[1].role, "menuitemcheckbox", "selected item is a checkbox item");
    expect((await items())[1].checked, "true", "selected item is aria-checked");
    await focusIs(menu, "Check in", "ArrowDown focuses the first item");

    // Arrows skip the disabled item.
    await page.keyboard.press("ArrowDown");
    await focusIs(menu, "Triage", "ArrowDown moves to next enabled item");
    await page.keyboard.press("ArrowDown");
    await focusIs(menu, "Discharge", "ArrowDown skips the disabled item");
    await page.keyboard.press("Home");
    await focusIs(menu, "Check in", "Home returns to the first item");
    await page.keyboard.press("End");
    await focusIs(menu, "Discharge", "End jumps to the last item");

    // Escape closes and restores trigger focus.
    await page.keyboard.press("Escape");
    expect((await state()).expanded, "false", "Escape closes");
    await menu.evaluate((el) => {
      if (el.shadowRoot.activeElement !== el.shadowRoot.querySelector(".trigger"))
        throw new Error("focus not returned to trigger");
    });

    // Outside click dismisses.
    await page.locator("#demo-menu .trigger" /* pierces shadow */).click();
    expect((await state()).expanded, "true", "click opens");
    await page.locator("h1").click();
    expect((await state()).expanded, "false", "outside click closes");

    // Select fires nb-select with the item value.
    await page.locator("#demo-menu .trigger").click();
    await menu.evaluate((el) => {
      const target = [...el.shadowRoot.querySelectorAll(".mi")].find((b) => b.dataset.value === "discharge");
      target.focus();
    });
    await page.keyboard.press("Enter");
    await expectLogged(page, "nb-select", /discharge/);
    expect((await state()).expanded, "false", "selection closes the menu");
  });

  /* ---------------------------------------------------------------- nb-tabs */
  await check("nb-tabs: roles, roving tabindex, arrow navigation", async () => {
    const tabs = page.locator("#demo-tabs");
    const tabState = () => tabs.evaluate((el) => ({
      tabs: [...el.shadowRoot.querySelectorAll(".tab")].map((button) => ({
        selected: button.getAttribute("aria-selected"),
        tabindex: button.getAttribute("tabindex"),
        controls: button.getAttribute("aria-controls"),
        role: button.getAttribute("role"),
      })),
      panels: [...el.querySelectorAll("nb-tab")].map((tab) => getComputedStyle(tab).display),
    }));
    let state = await tabState();
    expect(state.tabs[0].role, "tab", "buttons are tabs");
    expect(state.tabs.map((t) => t.selected), ["true", "false", "false"], "first tab selected");
    expect(state.tabs.map((t) => t.tabindex), ["0", "-1", "-1"], "roving tabindex: one stop");
    expect(state.panels, ["block", "none", "none"], "only the active panel renders");

    // aria wiring: the strip button's aria-controls resolves to the panel;
    // the panel carries its label by value (an id ref from light DOM cannot
    // resolve into the shadow tree where the strip button lives).
    await tabs.evaluate((el) => {
      const button = el.shadowRoot.querySelector(".tab");
      const panel = document.getElementById(button.getAttribute("aria-controls"));
      if (!panel) throw new Error("aria-controls does not resolve");
      const label = panel.shadowRoot.querySelector(".panel").getAttribute("aria-label");
      if (label !== "Board") throw new Error(`panel aria-label was ${label}`);
    });

    // ArrowRight: focus + selection follow.
    await tabs.evaluate((el) => el.shadowRoot.querySelector(".tab").focus());
    await page.keyboard.press("ArrowRight");
    state = await tabState();
    expect(state.tabs.map((t) => t.selected), ["false", "true", "false"], "ArrowRight selects the next tab");
    expect(state.panels, ["none", "block", "none"], "the next panel shows");
    await expectLogged(page, "nb-change", /Day/);
    await page.keyboard.press("End");
    state = await tabState();
    expect(state.tabs[2].selected, "true", "End selects the last tab");
    await page.keyboard.press("Home");
    state = await tabState();
    expect(state.tabs[0].selected, "true", "Home selects the first tab");
  });

  /* --------------------------------------------------------------- nb-table */
  await check("nb-table: grid roles, sticky header, aligned cells", async () => {
    const frame = await page.locator("#demo-table").evaluate((el) => {
      const grid = el.shadowRoot.querySelector('[role="grid"]');
      const head = el.shadowRoot.querySelector('[role="row"]');
      const headers = [...el.shadowRoot.querySelectorAll('[role="columnheader"]')];
      return {
        gridRole: !!grid,
        headPosition: getComputedStyle(head).position,
        headFill: getComputedStyle(head).backgroundColor,
        labels: headers.map((cell) => cell.textContent),
        rowRole: el.querySelector("#row-1").getAttribute("role"),
        cellRole: el.querySelector("#row-1 nb-cell").getAttribute("role"),
        cellAlign: el.querySelector("#row-1 nb-cell:last-child").style.textAlign,
      };
    });
    expect(frame.gridRole, true, "frame is a role=grid");
    expect(frame.headPosition, "sticky", "header row is sticky");
    expect(frame.headFill, "rgb(214, 235, 252)", "header fill is opaque (no bleed-through)");
    expect(frame.labels, ["Patient", "When", "Urgency"], "headers from nb-column children");
    expect(frame.rowRole, "row", "nb-row carries role=row");
    expect(frame.cellRole, "gridcell", "nb-cell carries role=gridcell");
    expect(frame.cellAlign, "right", "cells align with their column definition");
    expect(await page.locator("#row-1 nb-cell").count(), 3, "light-DOM rows project");
  });

  /* ------------------------------------------------------------- nb-calendar */
  await check("nb-calendar: states, select event, grid keyboard", async () => {
    const calendar = page.locator("#demo-calendar");
    const dayState = () => calendar.evaluate((el) => {
      const today = el.shadowRoot.querySelector('[aria-current="date"]');
      const selected = el.shadowRoot.querySelector(".day--selected");
      const dotted = el.shadowRoot.querySelector(".day--items .day-dot");
      const tabbable = [...el.shadowRoot.querySelectorAll("button.day")].filter((b) => b.getAttribute("tabindex") === "0");
      return {
        today: today?.dataset.date,
        selected: selected?.dataset.date,
        itemDot: !!dotted,
        dottedDate: el.shadowRoot.querySelector(".day--items")?.dataset.date,
        tabStops: tabbable.map((b) => b.dataset.date),
        title: el.shadowRoot.querySelector(".title").textContent,
      };
    });
    const state = await dayState();
    expect(state.today, "2026-09-23", "today wears aria-current=date");
    expect(state.selected, "2026-09-24", "selected day is filled + lifted");
    expect(state.itemDot, true, "days with items carry the sticker dot");
    expect(state.tabStops, ["2026-09-24"], "exactly one tab stop (the focused day)");
    expect(state.title, "September 2026", "title renders the month");

    // Arrow keys move the focused day; selection via Enter.
    await calendar.evaluate((el) => el.shadowRoot.querySelector("button.day[tabindex='0']").focus());
    await page.keyboard.press("ArrowRight");
    expect((await dayState()).tabStops, ["2026-09-25"], "ArrowRight moves the stop by a day");
    await page.keyboard.press("Enter");
    await expectLogged(page, "nb-select", /2026-09-25/);

    // PageDown crosses the month and reports nb-month-change.
    await page.keyboard.press("PageDown");
    const after = await dayState();
    expect(after.title, "October 2026", "PageDown navigates to October");
    await expectLogged(page, "nb-month-change", /2026-10/);

    // A click selects too (the pointer path) — October is rendered now.
    await page.locator('#demo-calendar button.day[data-date="2026-10-15"]').click();
    await expectLogged(page, "nb-select", /2026-10-15/);
  });

  /* -------------------------------------------------------------- nb-scroller */
  await check("nb-scroller: pin, detach, no yank, re-pin", async () => {
    const scroller = page.locator("#demo-scroller");
    // Fill until the pane overflows.
    await scroller.evaluate((el) => {
      for (let index = 0; index < 20; index++) {
        const message = document.createElement("p");
        message.textContent = `filler ${index}`;
        el.appendChild(message);
      }
    });
    await scroller.evaluate((el) => el.scrollToLatest());

    // Pinned: appending keeps the bottom.
    await scroller.evaluate((el) => {
      el.appendChild(Object.assign(document.createElement("p"), {textContent: "pinned-append"}));
    });
    await page.waitForTimeout(60);
    let atBottom = await scroller.evaluate(
      (el) => el.shadowRoot.querySelector(".view").scrollHeight - el.shadowRoot.querySelector(".view").scrollTop,
    );
    // The wait for a rAF happened; the view must sit at its bottom.
    const viewHeight = await scroller.evaluate((el) => el.shadowRoot.querySelector(".view").clientHeight);
    expect(atBottom <= viewHeight + 32, true, "pinned append keeps the bottom");

    // Detach by scrolling up: appends must NOT yank.
    await scroller.evaluate((el) => {
      const view = el.shadowRoot.querySelector(".view");
      view.scrollTop = 0;
      view.dispatchEvent(new Event("scroll"));
    });
    await page.waitForTimeout(30);
    expect(await scroller.evaluate((el) => el.dataset.pinned), "false", "detached state exposed");
    await scroller.evaluate((el) => {
      el.appendChild(Object.assign(document.createElement("p"), {textContent: "detached-append"}));
    });
    await page.waitForTimeout(60);
    const scrollTop = await scroller.evaluate((el) => el.shadowRoot.querySelector(".view").scrollTop);
    expect(scrollTop, 0, "detached append does not yank");
    await expectLogged(page, "nb-pinned-change", /false/);

    // The jump pill re-pins.
    await page.locator("#demo-scroller .jump").click();
    await page.waitForTimeout(30);
    expect(await scroller.evaluate((el) => el.dataset.pinned), "true", "jump pill re-pins");
  });

  /* ------------------------------------------------------------ nb-pagination */
  await check("nb-pagination: chips, aria-current, bounds", async () => {
    const pager = page.locator("#demo-pagination");
    const chips = () => pager.evaluate((el) => [...el.shadowRoot.querySelectorAll(".chip, .gap")].map((node) => ({
      text: node.textContent.trim(),
      current: node.getAttribute("aria-current"),
      disabled: node.disabled === true,
    })));
    let state = await chips();
    expect(state.filter((chip) => chip.current === "page"), [{text: "5", current: "page", disabled: false}], "page 5 is aria-current");
    expect(state.some((chip) => chip.text === "…"), true, "windowed chips include ellipses");
    expect(state[0].disabled, false, "prev enabled mid-range");

    // Selecting a page fires nb-change; the host writes the attr back.
    await pager.evaluate((el) => {
      [...el.shadowRoot.querySelectorAll("[data-go]")].find((button) => button.dataset.go === "1").click();
    });
    await expectLogged(page, "nb-change", /"page":1/);
    await pager.evaluate((el) => el.setAttribute("page", "1"));
    state = await chips();
    expect(state[0].disabled, true, "prev disabled on page 1");
  });

  /* ---------------------------------------------------------------- nb-sheet */
  await check("nb-sheet: dialog semantics, focus trap, escape, backdrop", async () => {
    await page.locator("#open-sheet").click();
    const sheet = page.locator("#demo-sheet");
    await sheet.evaluate((el) => {
      const dialog = el.shadowRoot.querySelector('[role="dialog"]');
      if (!dialog) throw new Error("no dialog");
      if (dialog.getAttribute("aria-modal") !== "true") throw new Error("not aria-modal");
      if (!dialog.getAttribute("aria-label")) throw new Error("no aria-label");
    });
    // Focus moves into the sheet (one frame for the reveal).
    await page.waitForFunction(() => {
      const el = document.getElementById("demo-sheet");
      const active = el.shadowRoot.activeElement;
      return active && el.shadowRoot.querySelector(".sheet").contains(active);
    });

    // Focus trap: Tab off the last focusable wraps to the first.
    await sheet.evaluate((el) => {
      const items = [];
      const sheet = el.shadowRoot.querySelector(".sheet");
      for (const node of sheet.querySelectorAll("button, input, [href]")) items.push(node);
      items[items.length - 1].focus();
    });
    await page.keyboard.press("Tab");
    await sheet.evaluate((el) => {
      const active = el.shadowRoot.activeElement;
      if (!active || active.getAttribute("aria-label") !== "Close panel")
        throw new Error("Tab did not wrap to the first focusable");
    });

    await page.keyboard.press("Escape");
    await expectLogged(page, "nb-close", /{}/);
    expect(await sheet.evaluate((el) => el.hasAttribute("open")), false, "Escape closed the sheet");
    // Focus restores to the opener (light DOM) — document, not shadow.
    await page.waitForFunction(
      () => document.activeElement === document.getElementById("open-sheet"),
    );

    // Backdrop press closes; a cancelling host keeps it open.
    await page.locator("#open-sheet").click();
    await page.locator("#demo-sheet .backdrop").click({position: {x: 10, y: 10}});
    expect(await sheet.evaluate((el) => el.hasAttribute("open")), false, "backdrop closes");
    await page.locator("#open-sheet").click();
    await page.evaluate(() => document.getElementById("demo-sheet").addEventListener("nb-close", (event) => event.preventDefault()));
    await page.locator("#demo-sheet .backdrop").click({position: {x: 10, y: 10}});
    expect(await sheet.evaluate((el) => el.hasAttribute("open")), true, "preventDefault keeps the sheet open");
    await page.evaluate(() => {
      const sheet = document.getElementById("demo-sheet");
      sheet.removeEventListener("nb-close", sheet.__nbCancelStub);
    });
    await page.keyboard.press("Escape");
  });

  await page.screenshot({path: join(shotDir, "nb-demo.png"), fullPage: true});

  /* --------------------------------------------------- motion + reduced motion */
  await check("motion: utilities animate; reduced motion collapses them", async () => {
    const animated = await page.evaluate(() => ({
      container: getComputedStyle(document.querySelector(".nb-move-container")).animationName,
      spring: getComputedStyle(document.querySelector(".nb-spring-in")).animationName,
      pressable: getComputedStyle(document.querySelector(".nb-pressable")).transitionProperty,
    }));
    expect(animated.container, "nb-container-in", "container move animates");
    expect(animated.spring, "nb-spring-in-kf", "spring move animates");
    expect(animated.pressable.includes("transform"), true, "pressable transitions transform");

    const reduced = await (await browser.newContext({reducedMotion: "reduce"})).newPage();
    await reduced.goto(url, {waitUntil: "load"});
    const collapsed = await reduced.evaluate(() => ({
      container: getComputedStyle(document.querySelector(".nb-move-container")).animationName,
      spring: getComputedStyle(document.querySelector(".nb-spring-in")).animationName,
      menu: (() => {
        const menu = document.getElementById("demo-menu");
        menu.shadowRoot.querySelector(".trigger").click();
        return getComputedStyle(menu.shadowRoot.querySelector(".popup")).animationName;
      })(),
    }));
    expect(collapsed.container, "none", "reduced: container move collapsed");
    expect(collapsed.spring, "none", "reduced: spring move collapsed");
    expect(collapsed.menu, "none", "reduced: menu entrance collapsed (still opens instantly)");
    const openState = await reduced.evaluate(() => document.getElementById("demo-menu").shadowRoot.querySelector(".popup").dataset.open);
    expect(openState, "true", "reduced: the menu still opens — state, not animation");
  });

  await browser.close();

  console.log(results.join("\n"));
  if (failures.length) {
    console.error(`\n${failures.join("\n")}`);
    console.error(`\n${failures.length} failure(s)`);
    process.exit(1);
  }
  console.log(`\nall ${results.length} checks passed`);
}

/** Asserts the shadow-active menu item matches `label`. */
async function focusIs(menu, label, note) {
  await menu.evaluate((el, expected) => {
    const active = el.shadowRoot.activeElement;
    if (!active || !active.textContent.trim().startsWith(expected))
      throw new Error(`${el.shadowRoot.activeElement?.textContent} is focused, wanted ${expected}`);
  }, label);
  results.push(`ok    ${note}`);
}

/** Asserts the demo page's event log carries `type` matching `pattern`. */
async function expectLogged(page, type, pattern) {
  const found = await page.evaluate(
    ([event, match]) =>
      [...document.querySelectorAll(`#log li[data-event="${event}"]`)].some((li) => match.test(li.textContent)),
    [type, pattern],
  );
  if (!found) throw new Error(`no ${type} log entry matching ${pattern}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
