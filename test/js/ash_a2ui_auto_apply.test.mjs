// The merged catalog Button's `apply_on_change` watch, against
// @a2ui/web_core's real DataModel. An Apply button (the `query` action,
// `page: 1`) on a query whose state carries `autoApply`:
//   - is configured only when `autoApply` is present, and never for a pager
//     button (`pageDelta`);
//   - sends its action once, at once, when a filter or the preset changes;
//   - sends it once, `debounceMs` after the last keystroke, for search;
//   - does not send it again when the server writes the applied values
//     back, nor on a write replacing the whole data model;
//   - does nothing on a query without `autoApply`.

import test from "node:test";
import assert from "node:assert/strict";

import {ashCatalog} from "./catalogs.mjs";
import {webCore} from "./support.mjs";
import {ASH_A2UI_CATALOG_ID} from "../../priv/js/ash_a2ui_protocol.js";

const {DataModel} = webCore;
const {autoApplyConfig, watchAutoApply, unwatchAutoApply} = ashCatalog;
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

function queryState(extra = {}) {
  return {
    search: "",
    filters: {status: ""},
    preset: "",
    sort: null,
    page: 1,
    pageSize: 25,
    totalCount: 0,
    hasMore: false,
    ...extra,
  };
}

// A stand-in for the Button element: the seams the watch reads. Its action
// is the ashAction the encoder emits for an Apply button.
function button(dataModel, actionContext = {page: 1, query: {"@path": "/query"}}) {
  const functionCall = {
    "@call": "ashAction",
    catalogId: ASH_A2UI_CATALOG_ID,
    args: {name: "query", sourceComponentId: "apply", context: actionContext},
  };
  const element = {
    sent: 0,
    updates: 0,
    context: {
      componentModel: {properties: {action: {functionCall}}},
      dataContext: {surface: {dataModel}},
    },
    controller: {props: {action: () => element.sent++}},
    requestUpdate: () => element.updates++,
  };
  return element;
}

const AUTO = {debounceMs: 40};

test("configured only with autoApply, never for a pager button", async () => {
  const plain = new DataModel({query: queryState()});
  assert.equal(autoApplyConfig(button(plain)), null, "plain query");

  const auto = new DataModel({query: queryState({autoApply: AUTO})});
  assert.equal(autoApplyConfig(button(auto))?.debounceMs, 40, "autoApply query");

  const pager = button(auto, {pageDelta: 1, query: {"@path": "/query"}});
  assert.equal(autoApplyConfig(pager), null, "pager button");
});

test("a filter change applies at once, the server's write-back does not", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/query/filters/status", "open");
  await sleep(5);
  assert.equal(element.sent, 1, "sends after the pick");

  // The reply: the same values, a new page count.
  dataModel.set("/query", queryState({autoApply: AUTO, filters: {status: "open"}, totalCount: 3}));
  await sleep(5);
  assert.equal(element.sent, 1, "no send on the write-back");
  unwatchAutoApply(element);
});

test("the preset applies at once", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/query/preset", "archived");
  await sleep(5);
  assert.equal(element.sent, 1, "sends after the pick");
  unwatchAutoApply(element);
});

test("search applies once, after a pause in typing", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  for (const text of ["a", "ac", "acm", "acme"]) {
    dataModel.set("/query/search", text);
    await sleep(10);
  }
  assert.equal(element.sent, 0, "nothing while typing");
  await sleep(60);
  assert.equal(element.sent, 1, "one send after the pause");
  unwatchAutoApply(element);
});

test("a write replacing the whole data model does not apply", async () => {
  const dataModel = new DataModel({query: queryState({autoApply: AUTO})});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/", {query: queryState({autoApply: AUTO, filters: {status: "closed"}})});
  await sleep(5);
  assert.equal(element.sent, 0, "no send on a root write");

  dataModel.set("/query/filters/status", "open");
  await sleep(5);
  assert.equal(element.sent, 1, "a later pick still applies");
  unwatchAutoApply(element);
});

test("a query without autoApply never applies by itself", async () => {
  const dataModel = new DataModel({query: queryState()});
  const element = button(dataModel);
  watchAutoApply(element);

  dataModel.set("/query/filters/status", "open");
  dataModel.set("/query/search", "acme");
  await sleep(60);
  assert.equal(element.sent, 0, "no send");
  unwatchAutoApply(element);
});

test("a multi-table query path is watched on its own", async () => {
  const dataModel = new DataModel({
    query: {table: queryState({autoApply: AUTO}), other: queryState()},
  });
  const element = button(dataModel, {
    page: 1,
    component: "table",
    query: {"@path": "/query/table"},
  });
  watchAutoApply(element);

  dataModel.set("/query/other/filters/status", "open");
  await sleep(5);
  assert.equal(element.sent, 0, "the other table's pick is not this one's");

  dataModel.set("/query/table/filters/status", "open");
  await sleep(5);
  assert.equal(element.sent, 1, "its own pick applies");
  unwatchAutoApply(element);
});
