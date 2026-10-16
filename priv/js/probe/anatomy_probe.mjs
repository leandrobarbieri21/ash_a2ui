/**
 * CLIN-10 anatomy probe — the verification gate for the neobrutalist
 * surface overrides (merged-catalog Text/Button anatomy + theme type
 * tiers + the encoder's title/carded-form shapes).
 *
 *   node priv/js/probe/anatomy_probe.mjs [--node-modules DIR] [--port N]
 *
 * Asserts COMPUTED STYLES against the digest's spec (never classes alone):
 * badges (border ≥2px, non-grey fill, ≥12px type, not italic, 5px radius),
 * the button system (row-action utility height ≤36px and shadowless, the
 * primary's RESTORED 2px border, the press translate with its
 * reduced-motion collapse), the surface title tier, section-heading chips,
 * the tone-aware status banner, the carded form panel with its footer
 * divider, and the quiet pager — plus aria (banner role, heading
 * structure) and zero console errors.
 *
 * Fixtures are recorded wire payloads (see the header of
 * anatomy_probe.html; re-record with the mix run one-liners in
 * picker_probe.mjs's pattern).
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
const port = Number(arg("port", "4190"));
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
  const root = mkdtempSync(join("/tmp", "nb-anatomy-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "anatomy_probe.html"), join(root, "anatomy_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/anatomy_probe.html`, {method: "HEAD"});
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
      const location = message.location();
      if (location?.url?.includes("favicon")) return;
      errors.push(`CONSOLE: ${message.text().slice(0, 200)}`);
    }
  });
  page.on("requestfailed", (request) => {
    if (request.url().includes("favicon")) return;
    errors.push(`REQFAIL: ${request.url().slice(0, 120)}`);
  });
  page.__errors = errors;
  await page.goto(`${base}/anatomy_probe.html?${query}`, {waitUntil: "load"});
  await page.waitForFunction(() => window.__boot?.stage && window.__boot.stage !== "imports-done");
  await page.waitForTimeout(600);
  return page;
}

/** Resolves one element by a deep (shadow-piercing) selector. */
async function deepQuery(page, selector) {
  return page.evaluate((sel) => {
    const search = (root) => {
      for (const element of root.querySelectorAll(sel)) return element;
      for (const element of root.querySelectorAll("*")) {
        if (element.shadowRoot) {
          const hit = search(element.shadowRoot);
          if (hit) return hit;
        }
      }
      return null;
    };
    return search(document);
  }, selector);
}

/** Finds a rendered inner element of the component whose context id
 * matches, climbing from the component's own host (the basic catalog
 * renders light DOM — getRootNode().host walks are unreliable). */
async function byComponentId(page, id, inner) {
  return page.evaluate(
    ({componentId, innerSelector}) => {
      const search = (root) => {
        for (const element of root.querySelectorAll("*")) {
          if (element.context?.componentModel?.id === componentId) {
            return element.matches?.(innerSelector) ? element : element.querySelector(innerSelector);
          }
          if (element.shadowRoot) {
            const hit = search(element.shadowRoot);
            if (hit) return hit;
          }
        }
        return null;
      };
      return search(document);
    },
    {componentId: id, innerSelector: inner},
  );
}

/** Computed styles of a component's rendered inner element, resolved and
 * measured in-page (elements cannot cross the wire). */
async function computedOfComponent(page, componentId, innerSelector, properties) {
  return page.evaluate(
    ({id, inner, props}) => {
      const search = (root) => {
        for (const element of root.querySelectorAll("*")) {
          if (element.context?.componentModel?.id === id) {
            return element.matches?.(inner) ? element : element.querySelector(inner);
          }
          if (element.shadowRoot) {
            const hit = search(element.shadowRoot);
            if (hit) return hit;
          }
        }
        return null;
      };
      const element = search(document);
      if (!element) return null;
      const style = getComputedStyle(element);
      return Object.fromEntries(props.map((prop) => [prop, style.getPropertyValue(prop)]));
    },
    {id: componentId, inner: innerSelector, props: properties},
  );
}

async function computed(page, selector, properties, pseudo = null) {
  return page.evaluate(
    ({sel, props, pseudo}) => {
      const search = (root) => {
        for (const element of root.querySelectorAll(sel)) return element;
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) {
            const hit = search(element.shadowRoot);
            if (hit) return hit;
          }
        }
        return null;
      };
      const element = search(document);
      if (!element) return null;
      const style = getComputedStyle(element, pseudo);
      return Object.fromEntries(props.map((prop) => [prop, style.getPropertyValue(prop)]));
    },
    {sel: selector, props: properties, pseudo},
  );
}

const rgb = (value) => {
  const match = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(value ?? "");
  return match ? match.slice(1, 4).map(Number) : null;
};

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath});

  /* --- promotion: badges, headings, quiet row actions ------------------ */
  let page = await openCase(browser, base, "payload=promotion");

  // Rows need data for the badge binding to resolve; inject results.
  await page.evaluate(async () => {
    const surfaceId = window.__surfaceId;
    window.__feed([
      {
        version: "v0.9.1",
        updateDataModel: {
          surfaceId,
          path: "/records",
          value: [
            {"id": "1", "_badge_is_active": "Active", "name": "Spring sale"},
            {"id": "2", "_badge_is_active": "Inactive", "name": "Winter sale"},
            {"id": "3", "_badge_is_active": "Noncompliant", "name": "Bundle breach"},
            {"id": "4", "_badge_is_active": "Compliant", "name": "Bundle clear"},
          ],
        },
      },
    ]);
  });
  await page.waitForTimeout(500);

  await check("badge anatomy: border ≥2px, non-grey fill, ≥12px, not italic, 5px radius", async () => {
    const badge = await computed(page, ".a2ui-badge", [
      "border-top-width",
      "border-radius",
      "font-size",
      "font-style",
      "background-color",
      "font-weight",
    ]);
    if (!badge) throw new Error("no badge rendered (is the rows data bound?)");
    expect(parseFloat(badge["border-top-width"]) >= 2, true, "2px border");
    expect(badge["border-radius"], "5px", "rounded-base");
    expect(parseFloat(badge["font-size"]) >= 12, true, `12px floor (got ${badge["font-size"]})`);
    expect(badge["font-style"], "normal", "no italic");
    expect(parseFloat(badge["font-weight"]) >= 500, true, "medium weight");
    const fill = rgb(badge["background-color"]);
    if (!fill) throw new Error(`unparseable fill: ${badge["background-color"]}`);
    // "Active" maps to the routine tone — a saturated green, never grey.
    const isGrey = fill[0] === fill[1] && fill[1] === fill[2];
    expect(isGrey, false, `fill must be chromatic (got rgb(${fill.join(",")}))`);
    expect(fill[1] > fill[0], true, "routine green: green channel dominates");
    console.log(
      `       badge: border ${badge["border-top-width"]}, ${badge["font-size"]}, fill rgb(${fill.join(",")})`,
    );
  });

  await check("compliance badge pair: Noncompliant red, Compliant green, black ink", async () => {
    const badges = await page.evaluate(() => {
      const found = [];
      const search = (root) => {
        for (const element of root.querySelectorAll(".a2ui-badge")) {
          found.push({
            text: element.textContent.trim(),
            fill: getComputedStyle(element).getPropertyValue("background-color"),
            color: getComputedStyle(element).getPropertyValue("color"),
          });
        }
        for (const element of root.querySelectorAll("*")) if (element.shadowRoot) search(element.shadowRoot);
      };
      search(document);
      return found;
    });
    const noncompliant = badges.find((badge) => badge.text === "Noncompliant");
    const compliant = badges.find((badge) => badge.text === "Compliant");
    if (!noncompliant || !compliant) throw new Error(`compliance badges missing (${badges.map((b) => b.text).join(", ")})`);
    const rgb = (value) => (value.match(/\d+/g) ?? []).map(Number).slice(0, 3);
    const bad = rgb(noncompliant.fill);
    const good = rgb(compliant.fill);
    expect(bad[0] > bad[1], true, `noncompliant reads red (got rgb(${bad.join(",")}))`);
    expect(good[1] > good[0], true, `compliant reads green (got rgb(${good.join(",")}))`);
    // Black-on-color: near-black ink on both fills.
    for (const [label, badge] of [["noncompliant", noncompliant], ["compliant", compliant]]) {
      const ink = rgb(badge.color);
      expect(ink[0] < 60 && ink[1] < 60 && ink[2] < 60, true, `${label} ink is black (got rgb(${ink.join(",")}))`);
    }
    console.log(`       compliance: noncompliant rgb(${bad.join(",")}), compliant rgb(${good.join(",")}), black ink`);
  });

  await check("section heading: h2 with the tone chip", async () => {
    const chip = await computed(page, ".a2ui-text.nb-section", ["width", "background-color"], "::before");
    if (!chip) throw new Error("no heading rendered (nb-section class missing?)");
    if (chip.width === "auto" || chip.width === "0px")
      throw new Error(`chip has no size (got ${chip.width}) — the ::before anatomy is not applied`);
    const fill = rgb(chip["background-color"]);
    if (!fill) throw new Error(`chip has no fill: ${chip["background-color"]}`);
    const isGrey = fill[0] === fill[1] && fill[1] === fill[2];
    expect(isGrey, false, "chip fill is chromatic");
    console.log(`       chip: ${chip.width} rgb(${fill.join(",")})`);
  });

  await check("row action: the quiet utility tier (≤36px, shadowless)", async () => {
    const button = await computed(page, "button.a2ui-button.nb-quiet", [
      "min-height",
      "box-shadow",
      "font-size",
    ]);
    if (!button) throw new Error("no quiet row-action button rendered");
    expect(parseFloat(button["min-height"]) <= 36, true, `height ≤36px (got ${button["min-height"]})`);
    expect(button["box-shadow"], "none", "utility tier is shadowless");
    console.log(`       row action: ${button["min-height"]} min-height, ${button["font-size"]} text`);
  });

  await check("create button: primary with the RESTORED border + press", async () => {
    const button = await computed(page, "button.a2ui-button.primary", [
      "border-top-width",
      "border-color",
      "box-shadow",
      "background-color",
    ]);
    if (!button) throw new Error("no primary button rendered");
    expect(parseFloat(button["border-top-width"]) >= 2, true, "border restored over border:none");
    const shadow = button["box-shadow"];
    expect(shadow.includes("0px 0px"), true, `hard shadow (got ${shadow})`);
    expect(shadow.split(" ").some((part) => part === "4px"), true, "4px offset");
    const fill = rgb(button["background-color"]);
    expect(fill[2] > fill[0], true, "accent blue fill");
    console.log(`       primary: border ${button["border-top-width"]}, shadow ${shadow}`);
  });

  await check("button press: hover translates into the shadow's place", async () => {
    const handle = await page.locator("button.a2ui-button.primary").first();
    if (!handle) throw new Error("no primary to hover");
    await handle.hover();
    await page.waitForTimeout(250);
    const transform = await computed(page, "button.a2ui-button.primary", ["transform", "box-shadow"]);
    expect(transform.transform.includes("4"), true, `translate 4px (got ${transform.transform})`);
    expect(transform["box-shadow"], "none", "shadow collapsed");
    console.log(`       press: ${transform.transform}`);
  });

  await check("reduced motion collapses the press, not the button", async () => {
    // The guard's effect: under emulated reduce, the hover translate is
    // zero (transition AND transform suppressed) while the button still
    // renders with its border — state survives, travel drops.
    const reduced = await browser.newPage({reducedMotion: "reduce"});
    await reduced.goto(`${base}/anatomy_probe.html?payload=promotion`, {waitUntil: "load"});
    await reduced.emulateMedia({reducedMotion: "reduce"});
    await reduced.waitForFunction(() => window.__boot?.stage === "booted");
    await reduced.waitForTimeout(600);
    const mediaMatchesFirst = await reduced.evaluate(() =>
      matchMedia("(prefers-reduced-motion: reduce)").matches,
    );
    expect(mediaMatchesFirst, true, "the emulation applied (media matches)");
    const handle = reduced.locator("button.a2ui-button").first();
    await handle.hover();
    await reduced.waitForTimeout(250);
    const style = await reduced.evaluate(() => {
      const search = (root) => {
        for (const element of root.querySelectorAll("button.a2ui-button")) return element;
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) {
            const hit = search(element.shadowRoot);
            if (hit) return hit;
          }
        }
        return null;
      };
      const element = search(document);
      if (!element) return null;
      const computed = getComputedStyle(element);
      return {
        transform: computed.getPropertyValue("transform"),
        transition: computed.getPropertyValue("transition-duration"),
        border: computed.getPropertyValue("border-top-width"),
      };
    });
    if (!style) throw new Error("no button rendered under reduced motion");
    expect(style.transform, "none", `no travel under reduce (got ${style.transform})`);
    expect(parseFloat(style.border) >= 2, true, "the button still renders");
    await reduced.close();
  });

  await check("status banner: tone-aware, bordered, aria-live", async () => {
    await page.evaluate(() => {
      const surfaceId = window.__surfaceId;
      window.__feed([
        {version: "v0.9.1", updateDataModel: {surfaceId, path: "/ui/feedback/message", value: "Promotion created."}},
        {version: "v0.9.1", updateDataModel: {surfaceId, path: "/ui/feedback/kind", value: "success"}},
      ]);
    });
    await page.waitForTimeout(400);
    const banner = await computed(page, ".a2ui-banner", ["border-top-width", "background-color"]);
    if (!banner) throw new Error("no banner rendered");
    expect(parseFloat(banner["border-top-width"]) >= 2, true, "bordered banner");
    const successFill = rgb(banner["background-color"]);
    expect(successFill[1] > successFill[0], true, "success tone is a saturated green");
    const aria = await page.evaluate(() => {
      const search = (root) => {
        for (const element of root.querySelectorAll(".a2ui-banner")) return element;
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) {
            const hit = search(element.shadowRoot);
            if (hit) return hit;
          }
        }
        return null;
      };
      const element = search(document);
      return element ? {role: element.getAttribute("role"), live: element.getAttribute("aria-live")} : null;
    });
    expect(aria.role, "status", "role=status for non-error tones");
    expect(aria.live, "polite", "aria-live=polite");

    // The destructive tone inverts: black card, white ink, role=alert.
    await page.evaluate(() => {
      const surfaceId = window.__surfaceId;
      window.__feed([
        {version: "v0.9.1", updateDataModel: {surfaceId, path: "/ui/feedback/message", value: "Refused."}},
        {version: "v0.9.1", updateDataModel: {surfaceId, path: "/ui/feedback/kind", value: "error"}},
      ]);
    });
    await page.waitForTimeout(400);
    const errorBanner = await computed(page, ".a2ui-banner.nb-banner-error", ["background-color", "color"]);
    if (!errorBanner) throw new Error("no error banner after the tone flip");
    const errorFill = rgb(errorBanner["background-color"]);
    expect(errorFill[0] < 40 && errorFill[1] < 40 && errorFill[2] < 40, true, `black inversion (got ${errorBanner["background-color"]})`);
    console.log(`       banner: success green, error ${errorBanner["background-color"]}`);
  });

  await check("promotion surface: zero console errors", async () => {
    expect(page.__errors.length, 0, page.__errors.join(" | "));
  });

  /* --- promotion, panel open: the carded form -------------------------- */
  await page.close();
  page = await openCase(browser, base, "payload=promotion&open=1");

  await check("form panel: carded with a footer zone", async () => {
    // The form Card keeps its frozen id — resolve it by its own component
    // context, then measure the rendered card box.
    const card = await computedOfComponent(page, "form", ".a2ui-card", [
      "border-top-width",
      "box-shadow",
      "border-radius",
    ]);
    if (!card) throw new Error("the form panel is not carded (no card under the form component)");
    expect(parseFloat(card["border-top-width"]) >= 2, true, "2px border");
    expect(card["box-shadow"].includes("0px 0px"), true, `hard shadow (got ${card["box-shadow"]})`);
    console.log(`       form card: border ${card["border-top-width"]}, shadow ${card["box-shadow"]}`);
  });

  await check("form footer: divider + submit/cancel zone", async () => {
    const divider = await byComponentId(page, "form_footer_divider", "*");
    expect(!!divider, true, "the footer divider renders");
    // The submit keeps the primary tier inside the card.
    const submit = await computed(page, "button.a2ui-button.primary", ["border-top-width"]);
    if (!submit) throw new Error("no submit button in the panel");
    expect(parseFloat(submit["border-top-width"]) >= 2, true, "submit is a bordered primary");
  });

  await check("open panel surface: zero console errors", async () => {
    expect(page.__errors.length, 0, page.__errors.join(" | "));
  });

  /* --- estate_user: the title tier ------------------------------------- */
  await page.close();
  page = await openCase(browser, base, "payload=estate_user");

  await check("surface title: the display tier as the page's h1", async () => {
    const title = await page.evaluate(() => {
      const search = (root) => {
        for (const element of root.querySelectorAll("h1")) return element;
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) {
            const hit = search(element.shadowRoot);
            if (hit) return hit;
          }
        }
        return null;
      };
      const element = search(document);
      if (!element) return null;
      const style = getComputedStyle(element);
      return {
        text: element.textContent.trim(),
        size: style.getPropertyValue("font-size"),
        weight: style.getPropertyValue("font-weight"),
        family: style.getPropertyValue("font-family"),
      };
    });
    if (!title) throw new Error("no h1 rendered");
    expect(title.text, "Legacy users", "the declared title");
    expect(parseFloat(title.size) >= 24, true, `display tier ≥24px (got ${title.size})`);
    expect(parseFloat(title.weight) >= 700, true, "heading weight");
    // The page's only h1 is the surface title.
    console.log(`       title: ${title.text} @ ${title.size}/${title.weight}`);
  });

  await check("estate surface: zero console errors", async () => {
    expect(page.__errors.length, 0, page.__errors.join(" | "));
  });

  /* --- paginated: the quiet pager -------------------------------------- */
  await page.close();
  page = await openCase(browser, base, "payload=paginated");

  await check("pagination: the quiet utility pair", async () => {
    // Make the pager visible: flip the pagination visibility sentinels (the same
    // zero-or-one gates the server writes on a real query reply).
    await page.evaluate(() => {
      const surfaceId = window.__surfaceId;
      const sentinel = (path) => ({
        version: "v0.9.1",
        updateDataModel: {surfaceId, path, value: [{"id": "on"}]},
      });
      window.__feed([
        sentinel("/query/_pagination_visible"),
        sentinel("/query/_previous_visible"),
        sentinel("/query/_next_visible"),
      ]);
    });
    await page.waitForTimeout(400);
    const buttons = await page.evaluate(() => {
      const found = [];
      const search = (root) => {
        for (const element of root.querySelectorAll("*")) {
          const id = element.context?.componentModel?.id ?? "";
          if (id.endsWith("_prev_button") || id.endsWith("_next_button")) {
            const button = element.matches?.("button") ? element : element.querySelector("button");
            if (button) {
              found.push({
                id,
                min: getComputedStyle(button).getPropertyValue("min-height"),
                shadow: getComputedStyle(button).getPropertyValue("box-shadow"),
              });
            }
          }
          if (element.shadowRoot) search(element.shadowRoot);
        }
      };
      search(document);
      return found;
    });
    if (buttons.length === 0) throw new Error("no pager buttons rendered (sentinels?)");
    for (const button of buttons) {
      expect(parseFloat(button.min) <= 36, true, `${button.id} height ≤36px (got ${button.min})`);
      expect(button.shadow, "none", `${button.id} shadowless`);
    }
    console.log(`       pager: ${buttons.length} buttons @ ${buttons[0].min}`);
  });

  await check("paginated surface: zero console errors", async () => {
    expect(page.__errors.length, 0, page.__errors.join(" | "));
  });

  await page.screenshot({path: join(probeDir, "screenshots", "anatomy-promotion.png"), fullPage: true});
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
