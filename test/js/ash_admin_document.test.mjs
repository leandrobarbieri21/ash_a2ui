// Admin catalog 3.4: the document pane and viewer (3.8: a value and its
// region linked both ways). The pure helpers (the
// regions, their drawn states, region links, zoom) and, in happy-dom with a
// stand-in pdf.js engine, the elements: the pane's switch, a region link
// opening the pane, the viewer loading its engine only for a document,
// drawing each region on its page in its state, and a region's activation
// sending the document_region action.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, mergedCatalog, pdfLoads} from "./catalogs.mjs";
import {mountHook, sent} from "./harness.mjs";
import {feedback} from "../../priv/js/ash_a2ui_protocol.js";
import {
  FLASH_MS,
  REGION_ACTIVATE_EVENT,
  REGION_ATTRIBUTE,
  REGION_STATES,
  boxStyle,
  drawnState,
  format,
  keyboardActivation,
  linkSourceOf,
  nextZoom,
  parseRegions,
  regionFromHref,
  regionIdsOf,
  selectedState,
  toPdfEngine,
} from "../../priv/js/ash_admin_document.js";

async function settle(rounds = 8) {
  for (let i = 0; i < rounds; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

function deep(root, selector) {
  const found = root.querySelector(selector);
  if (found) return found;
  for (const node of root.querySelectorAll("*")) {
    const inner = node.shadowRoot && deep(node.shadowRoot, selector);
    if (inner) return inner;
  }
  return null;
}

// --- the pure helpers -----------------------------------------------------

test("regions: a box on a page is kept, anything else dropped; unknown states are pending", () => {
  const regions = parseRegions([
    {id: "fee", page: 1, x: 0.1, y: 0.2, width: 0.3, height: 0.05, state: "reviewed", label: "Fee"},
    {id: "term", page: 2, x: 0, y: 0, width: 1, height: 1, state: "bogus"},
    {id: "", page: 1, x: 0.1, y: 0.1, width: 0.1, height: 0.1},
    {id: "off", page: 0, x: 0.1, y: 0.1, width: 0.1, height: 0.1},
    {id: "big", page: 1, x: 0.1, y: 0.1, width: 1.5, height: 0.1},
    {id: "flat", page: 1, x: 0.1, y: 0.1, width: 0.1, height: 0},
    null,
    "fee",
  ]);
  assert.deepEqual(regions.map((r) => [r.id, r.state, r.label]), [
    ["fee", "reviewed", "Fee"],
    ["term", "pending", ""],
  ]);
  assert.deepEqual(parseRegions(null), []);
  assert.deepEqual(REGION_STATES, ["pending", "reviewed", "selected", "reviewed-selected", "linked", "empty"]);
});

test("drawn state: the selected region is selected, or reviewed-selected once reviewed", () => {
  const pending = {id: "a", state: "pending"};
  const reviewed = {id: "b", state: "reviewed"};
  assert.equal(drawnState(pending, "a"), "selected");
  assert.equal(drawnState(reviewed, "b"), "reviewed-selected");
  assert.equal(drawnState(pending, "b"), "pending");
  assert.equal(drawnState({id: "c", state: "linked"}, "c"), "linked");
  assert.equal(drawnState({id: "d", state: "empty"}, "d"), "empty");
  assert.equal(drawnState(reviewed, null), "reviewed");
});

test("region links: the id after the pane's prefix, decoded", () => {
  assert.equal(regionFromHref("#document=payment_term", "#document="), "payment_term");
  assert.equal(regionFromHref("#document=line%201.price", "#document="), "line 1.price");
  assert.equal(regionFromHref("#document=", "#document="), null);
  assert.equal(regionFromHref("/contracts/1", "#document="), null);
  assert.equal(regionFromHref(null, "#document="), null);
});

test("zoom steps in and out, and stops at the ends", () => {
  assert.equal(nextZoom(1, 1), 1.25);
  assert.equal(nextZoom(1, -1), 0.75);
  assert.equal(nextZoom(3, 1), 3);
  assert.equal(nextZoom(0.5, -1), 0.5);
});

test("a box is placed as percentages of its page; templates fill their placeholders", () => {
  assert.deepEqual(boxStyle({x: 0.0809, y: 0.9223, width: 0.0686, height: 0.0152}), {
    left: "8.090%",
    top: "92.230%",
    width: "6.860%",
    height: "1.520%",
  });
  assert.equal(format("%{page} of %{count}", {page: 2, count: 5}), "2 of 5");
  assert.equal(format("Page %{page}", {}), "Page %{page}");
});

test("the engine: ash_a2ui_pdf.js's engine, or a raw pdf.js module", () => {
  const engine = {open: () => null, TextLayer: class {}};
  assert.equal(toPdfEngine({default: engine}), engine);
  const raw = toPdfEngine({getDocument: (options) => options, TextLayer: class {}});
  assert.deepEqual(raw.open("/doc.pdf"), {url: "/doc.pdf", isEvalSupported: false});
  assert.equal(toPdfEngine({}), null);
});

// --- the elements, with a stand-in engine ------------------------------------

// A two-page US Letter document; each page renders at once and has no text.
function stubEngine() {
  const page = (number) => ({
    number,
    getViewport: ({scale}) => ({
      width: 612 * scale,
      height: 792 * scale,
      scale,
      rotation: 0,
      rawDims: {pageWidth: 612, pageHeight: 792, pageX: 0, pageY: 0},
    }),
    render: () => ({promise: Promise.resolve(), cancel() {}}),
    streamTextContent: () => new ReadableStream({start: (c) => c.close()}),
  });
  const doc = {numPages: 2, getPage: async (n) => page(n)};
  const opened = [];
  return {
    opened,
    open(src) {
      opened.push(src);
      return {promise: Promise.resolve(doc), destroy() {}};
    },
    TextLayer: class {
      render() {
        return Promise.resolve();
      }
      cancel() {}
    },
  };
}

const REGIONS = [
  {id: "payment_term", page: 1, x: 0.08, y: 0.9, width: 0.07, height: 0.02, state: "pending", label: "Payment term"},
  {id: "name", page: 2, x: 0.1, y: 0.1, width: 0.3, height: 0.03, state: "reviewed", label: "Contract name"},
];

function surfaceMessages({document = {src: "/doc.pdf", fileName: "contract.pdf", regions: REGIONS}, shown = false} = {}) {
  return [
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {id: "root", component: "Column", children: ["document_pane_document"]},
          {
            id: "document_pane_document",
            component: "documentPane",
            pane: "document",
            label: "Show document",
            description: "Read-only, for reviewing values",
            document: {"@path": "/detail/contract/_document_document"},
            shown: {"@path": "/ui/documents/document/shown"},
            selected: {"@path": "/ui/documents/document/selected"},
            regionHref: "#document=",
            toggleAction: {name: "document_pane", context: {pane: "document"}},
            viewer: "document_viewer_document",
            children: ["payment_term"],
          },
          {
            id: "payment_term",
            component: "fieldDisplay",
            label: "Payment term",
            value: {"@path": "/detail/contract/payment_term"},
            review: {"@path": "/detail/contract/_review_payment_term"},
          },
          {
            id: "document_viewer_document",
            component: "documentViewer",
            src: {"@path": "/detail/contract/_document_document/src"},
            fileName: {"@path": "/detail/contract/_document_document/fileName"},
            regions: {"@path": "/detail/contract/_document_document/regions"},
            selected: {"@path": "/ui/documents/document/selected"},
            regionAction: {name: "document_region", context: {pane: "document"}},
            strings: {pending: "Not reviewed", reviewed: "Reviewed", pageOf: "%{page} of %{count}"},
          },
        ],
        dataModel: {
          detail: {
            contract: {
              id: "c1",
              payment_term: "Net 30",
              _review_payment_term: {
                state: "pending",
                stateLabel: "Not reviewed",
                page: 1,
                pageLabel: "p. 1",
                href: "#document=payment_term",
              },
              _document_document: document,
            },
          },
          ui: {feedback: feedback(), documents: {document: {shown, selected: null}}},
        },
      },
    },
  ];
}

async function mountPane(options) {
  globalThis.__testPdfEngine = stubEngine();
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages(surfaceMessages(options));
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  const pane = deep(element, "ash-admin-document-pane");
  assert.ok(pane, "the pane renders");
  return {hook, element, pane, engine: globalThis.__testPdfEngine};
}

const ashCalls = (hook) =>
  sent(hook)
    .map((message) => message.callAgentFunction?.callFunction?.args)
    .filter(Boolean);

const shownIn = (hook) => hook.processor.getSurface("s1").dataModel.get("/ui/documents/document/shown");

test("hidden by default: the sections alone, the switch off, pdf.js never loaded", async () => {
  const before = pdfLoads.count;
  const {pane} = await mountPane();
  const toggle = pane.renderRoot.querySelector("[data-role='toggle'] input[role='switch']");
  assert.ok(toggle, "the switch");
  assert.equal(toggle.checked, false);
  assert.match(pane.renderRoot.querySelector("[data-role='toggle']").textContent, /Show document/);
  assert.match(pane.renderRoot.querySelector("[data-role='toggle']").textContent, /Read-only, for reviewing values/);
  assert.ok(deep(pane.renderRoot, "ash-admin-field-display"), "the sections");
  assert.equal(pane.renderRoot.querySelector("[data-role='document']"), null);
  assert.equal(pdfLoads.count, before, "no engine load without a shown document");
});

test("no document: no switch, and a region link does nothing", async () => {
  const {pane, hook} = await mountPane({document: null});
  assert.equal(pane.renderRoot.querySelector("[data-role='toggle']"), null);
  pane.openAt && pane.onLinkClick({composedPath: () => [], button: 0});
  assert.deepEqual(ashCalls(hook), []);
});

test("the switch shows the pane at once and sends document_pane with shown", async () => {
  const {pane, hook, engine} = await mountPane();
  const toggle = pane.renderRoot.querySelector("input[role='switch']");
  toggle.checked = true;
  toggle.dispatchEvent(new Event("change"));
  await settle();

  assert.equal(shownIn(hook), true);
  assert.ok(pane.renderRoot.querySelector("[data-role='document'] ash-admin-document-viewer"), "the viewer");
  assert.deepEqual(engine.opened, ["/doc.pdf"]);
  const call = ashCalls(hook).find((args) => args.name === "document_pane");
  assert.deepEqual(call.context, {pane: "document", shown: true});
});

test("the viewer draws each region on its page, in its state, named by its field", async () => {
  const {pane} = await mountPane({shown: true});
  await settle(20);
  const viewer = pane.renderRoot.querySelector("ash-admin-document-viewer");
  const root = viewer.renderRoot;
  assert.equal(root.querySelector("[data-status]").dataset.status, "ready");
  const sheets = [...root.querySelectorAll("[data-page-sheet]")];
  assert.equal(sheets.length, 2);
  assert.equal(sheets[0].getAttribute("role"), "group");

  const fee = sheets[0].querySelector("[data-region='payment_term']");
  assert.equal(fee.dataset.state, "pending");
  assert.equal(fee.getAttribute("aria-label"), "Payment term, Not reviewed");
  assert.match(fee.getAttribute("style"), /left:8\.000%;top:90\.000%;width:7\.000%;height:2\.000%/);
  const name = sheets[1].querySelector("[data-region='name']");
  assert.equal(name.dataset.state, "reviewed");
  assert.equal(name.getAttribute("aria-label"), "Contract name, Reviewed");
});

test("activating a region selects it and sends document_region with its id", async () => {
  const {pane, hook} = await mountPane({shown: true});
  await settle(20);
  const viewer = pane.renderRoot.querySelector("ash-admin-document-viewer");
  viewer.renderRoot.querySelector("[data-region='name']").click();
  await settle();

  assert.equal(viewer.renderRoot.querySelector("[data-region='name']").dataset.state, "reviewed-selected");
  assert.equal(hook.processor.getSurface("s1").dataModel.get("/ui/documents/document/selected"), "name");
  const call = ashCalls(hook).find((args) => args.name === "document_region");
  assert.deepEqual(call.context, {pane: "document", regionId: "name"});
});

test("a review's page tag opens the hidden pane at its region", async () => {
  const {pane, hook} = await mountPane();
  const field = deep(pane.renderRoot, "ash-admin-field-display");
  const link = field.renderRoot.querySelector("a.field-review-page");
  assert.equal(link.getAttribute("href"), "#document=payment_term");
  link.click();
  await settle(20);

  assert.equal(shownIn(hook), true);
  const viewer = pane.renderRoot.querySelector("ash-admin-document-viewer");
  assert.ok(viewer, "the pane opened");
  assert.equal(viewer.renderRoot.querySelector("[data-region='payment_term']").dataset.state, "selected");
  const names = ashCalls(hook).map((args) => args.name);
  assert.ok(names.includes("document_pane") && names.includes("document_region"), names.join());
});

// --- 3.8: a value and its region, linked both ways ----------------------------

test("drawn state: a linked region is drawn in linkedState, linked by default; the selected one wins", () => {
  const pending = {id: "a", state: "pending"};
  const reviewed = {id: "b", state: "reviewed"};
  assert.equal(drawnState(pending, null, {linked: ["a"]}), "linked");
  assert.equal(drawnState(reviewed, null, {linked: ["a", "b"]}), "linked");
  assert.equal(drawnState(pending, null, {linked: ["b"]}), "pending");
  assert.equal(drawnState(pending, "a", {linked: ["a"], linkedState: () => "linked"}), "selected");
  const asSelected = {linked: ["a", "b"], linkedState: (region) => selectedState(region.state)};
  assert.equal(drawnState(pending, null, asSelected), "selected");
  assert.equal(drawnState(reviewed, null, asSelected), "reviewed-selected");
  assert.equal(drawnState({id: "c", state: "empty"}, null, {...asSelected, linked: ["c"]}), "empty");
  assert.equal(drawnState(pending, null, {linked: null}), "pending");
});

test("region ids: the addresses a marked value carries, under the pane's prefix, each once", () => {
  assert.equal(REGION_ATTRIBUTE, "data-a2ui-region");
  assert.deepEqual(regionIdsOf("#document=lines.0.price #document=lines.0.period_start", "#document="), [
    "lines.0.price",
    "lines.0.period_start",
  ]);
  assert.deepEqual(regionIdsOf("#document=a  #other=b #document=a #document=line+1", "#document="), ["a", "line 1"]);
  assert.deepEqual(regionIdsOf(null, "#document="), []);
  assert.deepEqual(regionIdsOf("#document=a", ""), []);
});

test("link source: the nearest marked element or region link on the path, never past a stop", () => {
  const node = (attrs) => ({getAttribute: (name) => attrs[name] ?? null});
  const tag = node({href: "#document=fee"});
  const row = node({[REGION_ATTRIBUTE]: "#document=fee #document=term"});
  const plain = node({});
  const viewer = node({});
  assert.deepEqual(linkSourceOf([plain, row, plain], "#document=").ids, ["fee", "term"]);
  assert.equal(linkSourceOf([plain, row], "#document=").element, row);
  assert.deepEqual(linkSourceOf([tag, row], "#document=").ids, ["fee"]);
  assert.equal(linkSourceOf([plain, viewer, row], "#document=", [viewer]), null);
  assert.equal(linkSourceOf([node({href: "/contracts/1"}), node({[REGION_ATTRIBUTE]: "#other=x"})], "#document="), null);
  assert.equal(linkSourceOf(null, "#document="), null);
});

test("keyboard activation: no event, a key event, or a click with no pointer behind it", () => {
  assert.equal(keyboardActivation(undefined), true);
  assert.equal(keyboardActivation({type: "keydown"}), true);
  assert.equal(keyboardActivation({type: "click", detail: 0}), true);
  assert.equal(keyboardActivation({type: "click", detail: 1}), false);
});

const fieldOf = (pane) => deep(pane.renderRoot, "ash-admin-field-display");
const fieldRow = (pane) => fieldOf(pane).renderRoot.querySelector("dl.field");
const regionState = (pane, id) =>
  pane.renderRoot.querySelector("ash-admin-document-viewer").renderRoot.querySelector(`[data-region='${id}']`).dataset.state;
const selectedIn = (hook) => hook.processor.getSurface("s1").dataModel.get("/ui/documents/document/selected");

function fire(target, type, init = {}) {
  const Kind = type.startsWith("pointer") ? PointerEvent : type.startsWith("focus") ? FocusEvent : Event;
  target.dispatchEvent(new Kind(type, {bubbles: true, composed: true, ...init}));
}

test("a review field carries its region's address", async () => {
  const {pane} = await mountPane();
  assert.equal(fieldRow(pane).getAttribute(REGION_ATTRIBUTE), "#document=payment_term");
});

test("pointing at a value links its region, writing and sending nothing; leaving clears it", async () => {
  const {pane, hook} = await mountPane({shown: true});
  await settle(20);
  const before = ashCalls(hook).length;
  fire(fieldRow(pane), "pointerover", {pointerType: "mouse"});
  await settle();
  assert.equal(regionState(pane, "payment_term"), "linked");
  assert.equal(regionState(pane, "name"), "reviewed");
  assert.equal(selectedIn(hook), null);
  assert.equal(ashCalls(hook).length, before, "nothing sent");

  fire(fieldRow(pane), "pointerout", {pointerType: "mouse", relatedTarget: document.body});
  await settle();
  assert.equal(regionState(pane, "payment_term"), "pending");
});

test("focus inside a value links its region without moving focus; blur clears it", async () => {
  const {pane, hook} = await mountPane({shown: true});
  await settle(20);
  const tag = fieldOf(pane).renderRoot.querySelector("a.field-review-page");
  const focused = document.activeElement;
  fire(tag, "focusin");
  await settle();
  assert.equal(regionState(pane, "payment_term"), "linked");
  assert.equal(document.activeElement, focused, "focus stays");
  // A pointer passing over something else does not end a link made by focus.
  fire(pane.renderRoot.querySelector(".content"), "pointerover", {pointerType: "mouse"});
  await settle();
  assert.equal(regionState(pane, "payment_term"), "linked");

  fire(tag, "focusout");
  await settle();
  assert.equal(regionState(pane, "payment_term"), "pending");
  assert.equal(selectedIn(hook), null);
});

test("a host draws a linked region in its own state (linkedState)", async () => {
  const {pane} = await mountPane({shown: true});
  await settle(20);
  const viewer = pane.renderRoot.querySelector("ash-admin-document-viewer");
  viewer.linkedState = (region) => selectedState(region.state);
  fire(fieldRow(pane), "pointerover", {pointerType: "mouse"});
  await settle();
  assert.equal(regionState(pane, "payment_term"), "selected");
  const box = viewer.renderRoot.querySelector("[data-region='payment_term']");
  assert.equal(box.hasAttribute("aria-current"), false, "linked, not the one a person went to");
  box.click();
  await settle();
  assert.equal(box.getAttribute("aria-current"), "true");
});

test("nothing links while the pane is hidden, or stacked under the sections, or by touch", async () => {
  const hidden = await mountPane();
  const before = ashCalls(hidden.hook).length;
  fire(fieldRow(hidden.pane), "pointerover", {pointerType: "mouse"});
  fire(fieldRow(hidden.pane), "focusin");
  await settle();
  assert.equal(hidden.pane.renderRoot.querySelector("[data-role='document']"), null);
  assert.equal(ashCalls(hidden.hook).length, before);
  assert.equal(shownIn(hidden.hook), false);

  const stacked = await mountPane({shown: true});
  await settle(20);
  stacked.pane.sideBySide = () => false;
  fire(fieldRow(stacked.pane), "pointerover", {pointerType: "mouse"});
  fire(fieldRow(stacked.pane), "focusin");
  await settle();
  assert.equal(regionState(stacked.pane, "payment_term"), "pending");

  stacked.pane.sideBySide = () => true;
  fire(fieldRow(stacked.pane), "pointerover", {pointerType: "touch"});
  await settle();
  assert.equal(regionState(stacked.pane, "payment_term"), "pending");
});

test("activating a region goes to its value and flashes it for 3 seconds; a click keeps focus", async (t) => {
  const {pane} = await mountPane({shown: true});
  await settle(20);
  const viewer = pane.renderRoot.querySelector("ash-admin-document-viewer");
  const row = fieldRow(pane);
  let scrolled = null;
  row.scrollIntoView = (options) => (scrolled = options);
  const events = [];
  pane.addEventListener(REGION_ACTIVATE_EVENT, (event) => events.push(event.detail));

  t.mock.timers.enable({apis: ["setTimeout"]});
  const focused = document.activeElement;
  viewer.renderRoot
    .querySelector("[data-region='payment_term']")
    .dispatchEvent(new MouseEvent("click", {bubbles: true, composed: true, detail: 1}));
  assert.deepEqual(events, [{id: "payment_term", keyboard: false}]);
  assert.equal(scrolled?.block, "start");
  assert.ok(row.hasAttribute("data-a2ui-flashed"), "flashed");
  // The section nav's outline (happy-dom drops a var() outline, so its offset stands in).
  assert.equal(row.style.outlineOffset, "2px");
  assert.equal(document.activeElement, focused, "a click keeps focus");
  assert.equal(row.hasAttribute("tabindex"), false);

  t.mock.timers.tick(FLASH_MS - 1);
  assert.ok(row.hasAttribute("data-a2ui-flashed"), "still flashed");
  t.mock.timers.tick(1);
  assert.equal(row.hasAttribute("data-a2ui-flashed"), false);
  assert.equal(row.style.outlineOffset, "");
});

test("from the keyboard, activating a region moves focus to its value; a host draws the flash", async () => {
  const {pane} = await mountPane({shown: true});
  await settle(20);
  const viewer = pane.renderRoot.querySelector("ash-admin-document-viewer");
  const flashes = [];
  pane.flashSource = (element, on) => flashes.push([element.localName, on]);
  const row = fieldRow(pane);
  row.scrollIntoView = () => {};

  // Enter on the stock region button is a click with detail 0.
  viewer.renderRoot.querySelector("[data-region='payment_term']").click();
  await settle();
  assert.equal(row.getAttribute("tabindex"), "-1");
  assert.equal(fieldOf(pane).renderRoot.activeElement, row, "focus on the value");
  assert.deepEqual(flashes, [["dl", true]]);
  assert.equal(row.style.outlineOffset, "", "the host's flash, not the stock outline");
  // Focus on the value links its region back.
  assert.equal(regionState(pane, "payment_term"), "selected");
  pane.stopFlash();
  assert.deepEqual(flashes, [["dl", true], ["dl", false]]);
});

test("a region no value cites goes nowhere", async () => {
  const {pane} = await mountPane({shown: true});
  await settle(20);
  const flashes = [];
  pane.flashSource = (element, on) => flashes.push(on);
  pane.renderRoot.querySelector("ash-admin-document-viewer").renderRoot.querySelector("[data-region='name']").click();
  await settle();
  assert.deepEqual(flashes, []);
});
