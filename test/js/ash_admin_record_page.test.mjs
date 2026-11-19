// Admin catalog 3.5: a record page the surface draws whole. The stock
// entityPage draws the declared header from its record (the breadcrumb
// reading the host page's values at /page), offers a button that runs an
// action only while the record says so and sends it as the page_action
// ashAction, draws its lead components while their gates hold, and its
// section nav marks and goes to sections. The alertBanner draws a :detail
// as an alert.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, mergedCatalog} from "./catalogs.mjs";
import {mountHook, sent} from "./harness.mjs";
import {feedback} from "../../priv/js/ash_a2ui_protocol.js";

async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
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

const header = {
  context: "dossier",
  path: "/detail/dossier",
  title: "name",
  breadcrumbLabel: "Breadcrumb",
  breadcrumb: [{label: "Dossiers", href: "/dossiers", pagePath: "/page/back"}],
  tags: [{field: "state_text", tone: "state_tone", helpField: "state_help"}],
  meta: [{field: "owner", help: "Who looks after it"}, {field: "empty_note"}],
  actions: [
    {name: "open_file", label: "Open file", variant: "secondary", href: "file_url"},
    {name: "missing_link", label: "Nowhere", variant: "secondary", href: "no_url"},
    {
      name: "close",
      label: "Close",
      variant: "primary",
      visible: "_header_action_close",
      action: {
        label: "Close",
        action: "page_action",
        context: {action: "close", recordId: {"@path": "/detail/dossier/id"}},
      },
    },
  ],
};

const record = {
  id: "d1",
  name: "Harbour lease",
  state_text: "Open",
  state_tone: "info",
  state_help: "Still being worked on",
  owner: "Ana",
  empty_note: "",
  file_url: "/files/7",
  no_url: "",
  closed_note: "",
  "closed?": false,
  _header_action_close: true,
};

async function mountPage({page = {back: "/dossiers?q=lease"}, data = {}} = {}) {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {
            id: "root",
            component: "entityPage",
            title: "Dossier",
            children: ["section_facts", "section_notes"],
            header,
            lead: ["detail_closed"],
            leadVisible: {detail_closed: "/detail/dossier/closed?"},
            nav: {
              label: "Sections",
              id: "dossier-sections",
              items: [
                {label: "Facts", anchor: "facts", target: "section_facts", id: "facts-link"},
                {label: "Notes", anchor: "notes", target: "section_notes"},
                {label: "Later", anchor: "later", target: "section_later"},
              ],
            },
          },
          {
            id: "detail_closed",
            component: "alertBanner",
            variant: "neutral",
            layout: "inline",
            title: "This dossier is closed",
            message: {"@path": "/detail/dossier/closed_note"},
          },
          {id: "section_facts", component: "Column", children: ["facts_text"]},
          {id: "facts_text", component: "Text", text: "Facts"},
          {id: "section_notes", component: "Column", children: ["notes_text"]},
          {id: "notes_text", component: "Text", text: "Notes"},
        ],
        dataModel: {
          detail: {dossier: {...record, ...data}},
          page,
          ui: {feedback: feedback()},
        },
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  const pageEl = deep(element, "ash-admin-entity-page");
  assert.ok(pageEl, "the page renders");
  return {hook, element, pageEl};
}

const write = (hook, path, value) =>
  hook.processMessages([{version: "1.0", updateDataModel: {surfaceId: "s1", path, value}}]);

const root = (pageEl) => pageEl.renderRoot;

test("the header reads its record: breadcrumb, title, tags, meta and links", async () => {
  const {pageEl} = await mountPage();
  const head = root(pageEl).querySelector("[data-a2ui-page-header]");
  assert.ok(head, "the declared header replaces the plain heading");
  assert.equal(root(pageEl).querySelector("h1").textContent.trim(), "Harbour lease");

  const crumbs = [...head.querySelectorAll("nav li")].map((li) => li.textContent.trim());
  assert.deepEqual(crumbs, ["Dossiers", "Harbour lease"]);
  // The host page's value replaces the declared address.
  assert.equal(head.querySelector("nav a").getAttribute("href"), "/dossiers?q=lease");

  const tag = head.querySelector("[data-field='state_text']");
  assert.equal(tag.textContent.trim(), "Open");
  assert.equal(tag.getAttribute("data-tone"), "info");
  assert.equal(tag.getAttribute("title"), "Still being worked on");
  assert.equal(head.querySelector("[data-field='owner']").getAttribute("title"), "Who looks after it");
  // An empty value hides its item.
  assert.equal(head.querySelector("[data-field='empty_note']"), null);

  assert.equal(head.querySelector("a[data-a2ui-action='open_file']").getAttribute("href"), "/files/7");
  // A link without an address draws no button.
  assert.equal(head.querySelector("[data-a2ui-action='missing_link']"), null);
});

test("without a page value the breadcrumb keeps its declared address", async () => {
  const {pageEl} = await mountPage({page: {}});
  assert.equal(root(pageEl).querySelector("[data-a2ui-page-header] nav a").getAttribute("href"), "/dossiers");
});

test("a button that runs an action shows while offered and sends page_action", async () => {
  const {hook, pageEl} = await mountPage();
  const button = () => root(pageEl).querySelector("[data-a2ui-action='close'] button");
  assert.equal(button().textContent.trim(), "Close");

  button().click();
  await settle();
  const call = sent(hook)
    .map((message) => message.callAgentFunction?.callFunction?.args)
    .find((args) => args?.name === "page_action");
  assert.ok(call, "page_action was sent");
  assert.deepEqual(call.context, {action: "close", recordId: "d1"});
  assert.equal(button().getAttribute("aria-busy"), "true");

  write(hook, "/detail/dossier/_header_action_close", false);
  await settle();
  assert.equal(button(), null);
});

test("a lead component shows only while its gate holds", async () => {
  const {hook, pageEl} = await mountPage();
  const lead = () => root(pageEl).querySelector(".page-lead");
  assert.equal(lead(), null);

  write(hook, "/detail/dossier/closed?", true);
  write(hook, "/detail/dossier/closed_note", "Nothing more is done on it.");
  await settle();
  const alert = deep(lead(), "[role]");
  assert.ok(alert, "the alert is drawn");
  assert.match(alert.textContent, /This dossier is closed/);
  assert.match(alert.textContent, /Nothing more is done on it\./);
});

test("the nav lists its sections and marks the first on arrival", async () => {
  const {pageEl} = await mountPage();
  const nav = root(pageEl).querySelector("[data-a2ui-nav]");
  assert.equal(nav.id, "dossier-sections");
  assert.equal(nav.getAttribute("aria-label"), "Sections");

  const entries = [...nav.querySelectorAll("[data-a2ui-nav-item]")];
  assert.deepEqual(
    entries.map((entry) => [entry.getAttribute("href"), entry.textContent.trim()]),
    [
      ["#facts", "Facts"],
      ["#notes", "Notes"],
      ["#later", "Later"],
    ],
  );
  assert.equal(entries[0].id, "facts-link");
  assert.ok(entries[0].hasAttribute("selected"));
  assert.equal(entries[0].getAttribute("aria-current"), "location");
  pageEl.stopNav();
});

test("choosing an entry goes to its section, outlines it and puts its anchor in the address", async () => {
  const {pageEl} = await mountPage();
  const target = pageEl.section(1);
  assert.ok(target, "the section is found through the shadow roots");
  let scrolled = 0;
  target.scrollIntoView = () => scrolled++;

  root(pageEl).querySelector("[data-a2ui-nav-item='1']").click();
  await settle();

  // At least once: the stock DOM has no layout, so a held arrival may scroll again.
  assert.ok(scrolled >= 1);
  assert.equal(location.hash, "#notes");
  assert.ok(target.hasAttribute("data-outlined"));
  assert.ok(root(pageEl).querySelector("[data-a2ui-nav-item='1']").hasAttribute("selected"));
  assert.ok(!root(pageEl).querySelector("[data-a2ui-nav-item='0']").hasAttribute("selected"));
  pageEl.stopNav();
  history.replaceState(null, "", "#");
});

test("a link elsewhere on the page to a section's anchor goes there too", async () => {
  const {pageEl} = await mountPage();
  const target = pageEl.section(0);
  let scrolled = 0;
  target.scrollIntoView = () => scrolled++;

  const link = document.createElement("a");
  link.href = "#facts";
  document.body.append(link);
  link.click();
  await settle();

  assert.ok(scrolled >= 1);
  assert.equal(location.hash, "#facts");
  pageEl.stopNav();
  link.remove();
  history.replaceState(null, "", "#");
});

test("an arrival waits for a section that is not drawn yet", async () => {
  const {pageEl} = await mountPage();
  assert.equal(pageEl.section(2), null);

  pageEl.arrive(2);
  await new Promise((resolve) => setTimeout(resolve, 150));
  assert.notEqual(location.hash, "#later");

  // The section arrives late (a slow surface): the page goes there then.
  const later = document.createElement("section");
  later.id = "section_later";
  let scrolled = 0;
  later.scrollIntoView = () => scrolled++;
  root(pageEl).append(later);
  await new Promise((resolve) => setTimeout(resolve, 150));

  assert.ok(scrolled >= 1, "it went there once the section appeared");
  assert.equal(location.hash, "#later");
  pageEl.stopNav();
  history.replaceState(null, "", "#");
});
