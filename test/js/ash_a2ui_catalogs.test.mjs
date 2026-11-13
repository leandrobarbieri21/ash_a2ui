// The merged basic catalog and the admin catalog, built against the pinned
// @a2ui runtime and rendered in happy-dom through the hook: what they
// declare, and that their own action paths reach the agent as the 1.0
// ashAction contract.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, adminCatalog, basicCatalog, mergedCatalog} from "./catalogs.mjs";
import {feedbackOf, mountHook, sent, tick} from "./harness.mjs";
import {readJson} from "./support.mjs";
import {ASH_A2UI_CATALOG_ID, feedback} from "../../priv/js/ash_a2ui_protocol.js";

const ADMIN_JSON = readJson("priv/a2ui/admin_v1/catalog.json");

// Renders surface `surfaceId` of `hook` into a fresh <a2ui-surface>.
async function render(hook, surfaceId) {
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface(surfaceId);
  await settle();
  return element;
}

async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

// querySelector through every open shadow root.
function deep(root, selector) {
  const found = root.querySelector(selector);
  if (found) return found;
  for (const node of root.querySelectorAll("*")) {
    const inner = node.shadowRoot && deep(node.shadowRoot, selector);
    if (inner) return inner;
  }
  return null;
}

function deepAll(root, selector, out = []) {
  out.push(...root.querySelectorAll(selector));
  for (const node of root.querySelectorAll("*"))
    if (node.shadowRoot) deepAll(node.shadowRoot, selector, out);
  return out;
}

const answer = (functionCallId, kind, message = "") => [
  {
    version: "1.0",
    updateDataModel: {
      surfaceId: "s1",
      path: "/ui/feedback",
      value: feedback(kind, message, {functionCallId}),
    },
  },
  {version: "1.0", agentFunctionResponse: {functionCallId, value: {kind}}},
];

test("the merged catalog is the basic catalog with AshA2ui's elements", () => {
  assert.equal(mergedCatalog.id, basicCatalog.id);
  assert.equal(mergedCatalog.protocolVersion, "1.0");
  assert.deepEqual([...mergedCatalog.components.keys()], [...basicCatalog.components.keys()]);
  assert.deepEqual([...mergedCatalog.functions.keys()], [...basicCatalog.functions.keys()]);

  const tags = Object.fromEntries(
    [...mergedCatalog.components.values()].map((c) => [c.name, c.tagName]),
  );
  assert.deepEqual(
    ["ChoicePicker", "Column", "Text", "Button", "Row", "TextField", "Modal"].map(
      (name) => tags[name],
    ),
    [
      "ash-a2ui-choicepicker",
      "ash-a2ui-column",
      "ash-a2ui-text",
      "ash-a2ui-button",
      "ash-a2ui-row",
      "ash-a2ui-textfield",
      "ash-a2ui-modal",
    ],
  );
  for (const component of mergedCatalog.components.values()) {
    assert.equal(
      customElements.get(component.tagName) ?? component.element,
      component.element,
      component.name,
    );
  }
});

test("the admin catalog declares what its catalog document declares", () => {
  assert.equal(admin.id, ADMIN_JSON.catalogId);
  assert.equal(admin.protocolVersion, ADMIN_JSON.protocolVersion);
  assert.equal(adminCatalog.ADMIN_CATALOG_VERSION, ADMIN_JSON.metadata.extensions.ash_a2ui.version);

  for (const name of Object.keys(ADMIN_JSON.components)) {
    assert.ok(admin.components.has(name), `admin component ${name}`);
  }
  for (const name of basicCatalog.components.keys()) {
    assert.ok(admin.components.has(name), `basic component ${name} on admin surfaces`);
  }

  const openSurface = admin.functions.get("openSurface");
  assert.equal(openSurface.requiresUserActivation, true);
  assert.equal(openSurface.allowedCallers, undefined);
});

test("the admin schemas take 1.0 bindings and leave the envelope to the renderer", () => {
  const {schemas} = {schemas: adminCatalog.buildSchemas(basicCatalog)};
  const pagination = schemas.pagination.parse({
    page: {"@path": "/query/page"},
    nextAction: {name: "query", context: {query: {"@path": "/query"}, pageDelta: 1}},
    "@accessibility": {label: "Pages"},
  });
  assert.deepEqual(pagination.page, {"@path": "/query/page"});
  assert.equal("@accessibility" in pagination, false);
  assert.equal("accessibility" in schemas.dataGrid.shape, false);
});

const QUERY = {
  page: 1,
  pageSize: 10,
  totalCount: 30,
  hasMore: true,
  paginationVisible: true,
  previousVisible: false,
  nextVisible: true,
  _range_text: "1–10 of 30",
  search: "ada",
};

function adminSurface(hook, components, dataModel = {}) {
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {id: "root", component: "Column", children: components.map((c) => c.id)},
          ...components,
        ],
        dataModel: {query: QUERY, ui: {feedback: feedback()}, ...dataModel},
      },
    },
  ]);
  assert.deepEqual(sent(hook), [], "the surface applies");
}

const banner = {
  id: "status_banner",
  component: "statusBanner",
  kind: {"@path": "/ui/feedback/kind"},
  message: {"@path": "/ui/feedback/message"},
};

const pagination = {
  id: "pagination",
  component: "pagination",
  page: {"@path": "/query/page"},
  pageSize: {"@path": "/query/pageSize"},
  total: {"@path": "/query/totalCount"},
  hasNext: {"@path": "/query/hasMore"},
  visible: {"@path": "/query/paginationVisible"},
  previousVisible: {"@path": "/query/previousVisible"},
  nextVisible: {"@path": "/query/nextVisible"},
  rangeText: {"@path": "/query/_range_text"},
  nextAction: {
    name: "query",
    context: {query: {"@path": "/query"}, pageDelta: 1, component: "tasks"},
  },
};

test("a pagination page turn is a quiet ashAction with its bindings resolved", async () => {
  const hook = mountHook({catalogs: [mergedCatalog, admin], pendingMessage: "Loading…"});
  const saved = feedback("success", "Saved.", {resultText: "Total: 42"});
  adminSurface(hook, [banner, pagination], {ui: {feedback: saved}});
  const surface = await render(hook, "s1");

  const next = deepAll(surface, "button").find((button) => button.textContent.includes("Next"));
  assert.ok(next, "the Next button renders");
  next.click();
  await tick();

  const [call] = sent(hook);
  const {functionCallId, callFunction} = call.callAgentFunction;
  assert.deepEqual(callFunction, {
    "@call": "ashAction",
    catalogId: ASH_A2UI_CATALOG_ID,
    args: {
      name: "query",
      sourceComponentId: "pagination",
      context: {query: QUERY, pageDelta: 1, component: "tasks"},
    },
  });
  assert.deepEqual(feedbackOf(hook, "s1"), saved, "a page turn writes no pending state");

  // The agent leaves the feedback alone for a quiet action.
  hook.processMessages([{version: "1.0", agentFunctionResponse: {functionCallId, value: {}}}]);
  await settle();
  assert.deepEqual(hook.responses[0].response, {value: {}});
  assert.deepEqual(feedbackOf(hook, "s1"), saved, "the last outcome and its result stay");
  const statusBanner = deep(surface, "ash-admin-status-banner");
  assert.equal(statusBanner.hasAttribute("hidden"), false, "the banner never hid");
});

test("a page chip sends its distance as pageDelta", async () => {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  adminSurface(hook, [pagination]);
  const surface = await render(hook, "s1");

  deepAll(surface, "button")
    .find((button) => button.getAttribute("aria-label") === "Page 3")
    .click();
  await tick();

  assert.equal(sent(hook)[0].callAgentFunction.callFunction.args.context.pageDelta, 2);
});

test("a row action resolves its row-relative bindings and settles on the outcome", async () => {
  const hook = mountHook({catalogs: [mergedCatalog, admin], actionTimeoutMs: 0});
  const grid = {
    id: "grid",
    component: "dataGrid",
    columns: [{label: "Title", path: "title"}],
    rows: {"@path": "/rows"},
    rowId: "id",
    rowActions: [
      {
        label: "Close",
        action: "invoke",
        context: {action: "close", recordId: {"@path": "id"}, query: {"@path": "/query"}},
      },
    ],
  };
  adminSurface(hook, [grid], {
    rows: [
      {id: "r1", title: "One"},
      {id: "r2", title: "Two"},
    ],
  });
  const surface = await render(hook, "s1");

  const closes = deepAll(surface, "[data-a2ui-action='close'] button");
  assert.ok(closes.length >= 2, "a Close button per row");
  closes[1].click();
  await tick();

  const {functionCallId, callFunction} = sent(hook)[0].callAgentFunction;
  assert.deepEqual(callFunction.args, {
    name: "invoke",
    sourceComponentId: "grid",
    context: {action: "close", recordId: "r2", query: QUERY},
  });

  const gridElement = deep(surface, "ash-admin-data-grid");
  await settle();
  assert.ok(gridElement._amBusyRowAction, "busy while the call is pending");

  hook.processMessages(answer(functionCallId, "success", "Closed"));
  await settle();
  assert.equal(gridElement._amBusyRowAction, null, "settled by the outcome, not the pending write");
});

test("a row action stays busy past the watchdog until the server's outcome", async () => {
  const hook = mountHook({catalogs: [mergedCatalog, admin], actionTimeoutMs: 20});
  const grid = {
    id: "grid",
    component: "dataGrid",
    columns: [{label: "Title", path: "title"}],
    rows: {"@path": "/rows"},
    rowId: "id",
    rowActions: [
      {label: "Close", action: "invoke", context: {action: "close", recordId: {"@path": "id"}}},
    ],
  };
  adminSurface(hook, [grid], {
    rows: [{id: "r1", title: "One"}],
    ui: {feedback: feedback(), feedback_text: {pending: "Working…", slow: "Still working…"}},
  });
  const surface = await render(hook, "s1");

  deepAll(surface, "[data-a2ui-action='close'] button")[0].click();
  await tick();
  const {functionCallId} = sent(hook)[0].callAgentFunction;
  const gridElement = deep(surface, "ash-admin-data-grid");

  await new Promise((resolve) => setTimeout(resolve, 60));
  await settle();
  assert.deepEqual(feedbackOf(hook, "s1"), {
    ...feedback("pending", "Still working…"),
    code: "TIMEOUT",
    functionCallId,
  });
  assert.ok(gridElement._amBusyRowAction, "still busy: the server may still be running it");

  hook.processMessages([
    {
      version: "1.0",
      updateDataModel: {
        surfaceId: "s1",
        path: "/ui/feedback",
        value: feedback("success", "Closed", {functionCallId}),
      },
    },
  ]);
  await settle();
  assert.equal(gridElement._amBusyRowAction, null, "the late outcome settles it");
});

test("a filterPicker renders on an admin surface with its hint", async () => {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  adminSurface(
    hook,
    [
      {
        id: "query_filter_status",
        component: "filterPicker",
        label: "Status",
        variant: "mutuallyExclusive",
        value: {"@path": "/query/filters/status"},
        options: [
          {label: "All", value: ""},
          {label: "Open", value: "open"},
        ],
        hint: "Statuses update nightly.",
        counts: {"@path": "/query/facets/status"},
      },
    ],
    {query: {...QUERY, filters: {status: ""}, facets: {status: {open: 3}}}},
  );
  const surface = await render(hook, "s1");

  const picker = deep(surface, "ash-admin-filter-picker");
  assert.ok(picker, "the filter picker element renders");
  const text = (picker.shadowRoot ?? picker).textContent;
  assert.match(text, /Statuses update nightly/);
  assert.match(text, /Open/);
});

// The admin calendarView over a month window, its windowAction a query.
function calendarSurface(hook) {
  const calendar = {
    id: "cal",
    component: "calendarView",
    label: "Visits",
    granularity: "month",
    window: {"@path": "/query/visits/window"},
    windowAction: {name: "query", context: {query: {"@path": "/query"}, component: "visits"}},
  };
  const window = (anchor, label) => ({granularity: "month", anchor, selected: "", marks: [], label});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [{id: "root", component: "Column", children: ["cal"]}, calendar],
        dataModel: {
          query: {visits: {window: window("2026-11-01", "November 2026")}},
          ui: {feedback: feedback()},
        },
      },
    },
  ]);
  return window;
}

test("a calendar move stays in flight until its own window arrives", async () => {
  const hook = mountHook({catalogs: [mergedCatalog, admin], actionTimeoutMs: 0});
  const window = calendarSurface(hook);
  const surface = await render(hook, "s1");
  const calendar = deep(surface, "ash-admin-calendar-view");

  calendar.request({anchor: "2026-12-01"}, calendar.windowKey("2026-12-01", ""));
  await settle();
  assert.ok(calendar._pending, "the move is in flight");
  calendar.request({anchor: "2027-01-01"}, calendar.windowKey("2027-01-01", ""));
  await settle();
  assert.ok(calendar._pending, "the second move is in flight");

  const [first] = sent(hook).map((message) => message.callAgentFunction.functionCallId);
  hook.processMessages([
    {
      version: "1.0",
      updateDataModel: {
        surfaceId: "s1",
        path: "/query/visits/window",
        value: window("2026-12-01", "December 2026"),
      },
    },
    {version: "1.0", agentFunctionResponse: {functionCallId: first, value: {}}},
  ]);
  await settle();

  assert.ok(calendar._pending, "an earlier window does not settle the later move");
  assert.notEqual(calendar.calendarElement()?.getAttribute("month"), "2026-12-01");
});

// A basic-catalog prompt: a Modal whose Confirm sends `invoke`.
function promptSurface(hook) {
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: basicCatalog.id,
        components: [
          {id: "root", component: "Column", children: ["prompt"]},
          {id: "prompt", component: "Modal", trigger: "open", content: "confirm"},
          {
            id: "open",
            component: "Button",
            child: "open_label",
            action: {
              functionCall: {
                "@call": "ashAction",
                catalogId: ASH_A2UI_CATALOG_ID,
                args: {name: "prompt", sourceComponentId: "open", context: {action: "delegate"}},
              },
            },
          },
          {id: "open_label", component: "Text", text: "Delegate"},
          {
            id: "confirm",
            component: "Button",
            child: "confirm_label",
            action: {
              functionCall: {
                "@call": "ashAction",
                catalogId: ASH_A2UI_CATALOG_ID,
                args: {name: "invoke", sourceComponentId: "confirm", context: {action: "delegate"}},
              },
            },
          },
          {id: "confirm_label", component: "Text", text: "Confirm"},
        ],
        dataModel: {ui: {feedback: feedback()}},
      },
    },
  ]);
}

async function openPrompt(hook) {
  const surface = await render(hook, "s1");
  const modal = deep(surface, "ash-a2ui-modal");
  modal.querySelector(".a2ui-modal-trigger").click();
  await settle();
  assert.equal(modal.isOpen, true);
  hook.pushed.length = 0;
  return modal;
}

test("the prompt Modal closes on its invoke's success", async () => {
  const hook = mountHook({catalogs: [mergedCatalog], actionTimeoutMs: 0});
  promptSurface(hook);
  const modal = await openPrompt(hook);

  modal.querySelector(".a2ui-modal-content button:not(.a2ui-modal-close)").click();
  await settle();
  assert.equal(modal.isOpen, true, "the pending write does not close it");

  const {functionCallId} = sent(hook)[0].callAgentFunction;
  hook.processMessages(answer(functionCallId, "success", "Delegated"));
  await settle();
  assert.equal(modal.isOpen, false);
});

test("the prompt Modal shows the outcome of a failed invoke", async () => {
  const hook = mountHook({catalogs: [mergedCatalog], actionTimeoutMs: 0});
  promptSurface(hook);
  const modal = await openPrompt(hook);

  modal.querySelector(".a2ui-modal-content button:not(.a2ui-modal-close)").click();
  await settle();
  const {functionCallId} = sent(hook)[0].callAgentFunction;
  hook.processMessages(answer(functionCallId, "error", "Not allowed"));
  await settle();

  assert.equal(modal.isOpen, true);
  assert.equal(modal.querySelector(".ash-a2ui-prompt-error").textContent, "Not allowed");
});
