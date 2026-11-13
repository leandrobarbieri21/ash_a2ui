import test from "node:test";
import assert from "node:assert/strict";

// The hook module touches no browser global at import time.
import {AshA2ui, acceptsMessage, addressedSurfaceId} from "../../priv/js/ash_a2ui_hook.js";

// A hook with the routing fields mounted() reads from its container, and a
// processor that only records what it is fed.
function hookWith({surface = null, primary = false} = {}) {
  const hook = Object.create(AshA2ui);
  hook.scopedSurface = surface;
  hook.primary = primary;
  hook.fed = [];
  hook.processor = {processMessages: (messages) => hook.fed.push(...messages)};
  hook.deps = {catalogs: []};
  hook.v1Surfaces = new Set();
  hook.pendingActions = new Map();
  hook.surfaceIds = new Set();
  hook.skeletonEl = null;
  hook.panelVisible = false;
  hook.surfaceEl = {};
  hook.events = [];
  hook.el = {dispatchEvent: (event) => hook.events.push(event)};
  hook.calls = [];
  hook.functions = {openUrl: (args) => hook.calls.push(args)};
  return hook;
}

const v09 = (kind, surfaceId, extra = {}) => ({version: "v0.9.1", [kind]: {surfaceId, ...extra}});
const v10 = (kind, surfaceId, extra = {}) => ({version: "v1.0", [kind]: {surfaceId, ...extra}});

const callFunction = {
  version: "v1.0",
  functionCallId: "fc_1",
  callFunction: {call: "openUrl", args: {url: "https://example.com"}},
};

const actionResponse = (actionId) => ({version: "v1.0", actionId, actionResponse: {status: "ok"}});

// The page: two scoped containers ("orders" and "summary") and one unscoped.
function page() {
  const orders = hookWith({surface: "orders"});
  const summary = hookWith({surface: "summary"});
  const unscoped = hookWith();
  return {orders, summary, unscoped, hooks: [orders, summary, unscoped]};
}

test("addressedSurfaceId reads the surface id of both protocol versions", () => {
  for (const kind of ["createSurface", "updateComponents", "updateDataModel", "deleteSurface"]) {
    assert.equal(addressedSurfaceId(v09(kind, "a")), "a");
    assert.equal(addressedSurfaceId(v10(kind, "b")), "b");
  }
  assert.equal(addressedSurfaceId(callFunction), undefined);
  assert.equal(addressedSurfaceId(actionResponse("x")), undefined);
  assert.equal(addressedSurfaceId(null), undefined);
});

test("a message addressed to a scoped surface reaches only that surface's hook", () => {
  const {orders, summary, unscoped, hooks} = page();
  const message = v10("updateComponents", "summary", {components: []});

  assert.equal(acceptsMessage(message, summary, hooks), true);
  assert.equal(acceptsMessage(message, orders, hooks), false);
  assert.equal(acceptsMessage(message, unscoped, hooks), false);
});

test("a message for a surface no hook claims reaches only the unscoped hook", () => {
  const {orders, summary, unscoped, hooks} = page();
  const message = v09("createSurface", "other", {catalogId: "c"});

  assert.equal(acceptsMessage(message, unscoped, hooks), true);
  assert.equal(acceptsMessage(message, orders, hooks), false);
  assert.equal(acceptsMessage(message, summary, hooks), false);
});

test("an actionResponse reaches only the hook holding its actionId", () => {
  const {orders, summary, unscoped, hooks} = page();
  summary.pendingActions.set("act-1", {surfaceId: "summary"});

  assert.equal(acceptsMessage(actionResponse("act-1"), summary, hooks), true);
  assert.equal(acceptsMessage(actionResponse("act-1"), orders, hooks), false);
  assert.equal(acceptsMessage(actionResponse("act-1"), unscoped, hooks), false);
});

test("an actionResponse nobody holds goes to the primary hook", () => {
  const {orders, summary, unscoped, hooks} = page();

  assert.equal(acceptsMessage(actionResponse("gone"), unscoped, hooks), true);
  assert.equal(acceptsMessage(actionResponse("gone"), orders, hooks), false);
  assert.equal(acceptsMessage(actionResponse("gone"), summary, hooks), false);
});

test("a message naming no surface goes to the unscoped hook", () => {
  const {orders, summary, unscoped, hooks} = page();

  assert.equal(acceptsMessage(callFunction, unscoped, hooks), true);
  assert.equal(acceptsMessage(callFunction, orders, hooks), false);
  assert.equal(acceptsMessage(callFunction, summary, hooks), false);
});

test("a hook marked primary takes the messages naming no surface", () => {
  const orders = hookWith({surface: "orders", primary: true});
  const summary = hookWith({surface: "summary"});
  const unscoped = hookWith();
  const hooks = [orders, summary, unscoped];

  assert.equal(acceptsMessage(callFunction, orders, hooks), true);
  assert.equal(acceptsMessage(callFunction, summary, hooks), false);
  assert.equal(acceptsMessage(callFunction, unscoped, hooks), false);
});

test("with only scoped hooks and none primary, the first mounted takes unaddressed messages", () => {
  const orders = hookWith({surface: "orders"});
  const summary = hookWith({surface: "summary"});
  const hooks = [orders, summary];

  assert.equal(acceptsMessage(callFunction, orders, hooks), true);
  assert.equal(acceptsMessage(callFunction, summary, hooks), false);
});

test("with no scoped or primary hook, every hook takes every message", () => {
  const first = hookWith();
  const second = hookWith();
  const hooks = [first, second];
  first.pendingActions.set("act-1", {surfaceId: "s"});

  for (const message of [v09("createSurface", "s"), callFunction, actionResponse("act-1")]) {
    assert.equal(acceptsMessage(message, first, hooks), true);
    assert.equal(acceptsMessage(message, second, hooks), true);
  }
});

test("receiveMessages splits one push across the hooks on the page", async () => {
  const {orders, summary, unscoped, hooks} = page();
  orders.pendingActions.set("act-1", {surfaceId: "orders"});
  const push = [
    actionResponse("act-1"),
    v10("updateDataModel", "orders", {path: "/", value: {}}),
    v10("updateDataModel", "summary", {path: "/", value: {}}),
    v09("updateComponents", "other", {components: []}),
    callFunction,
  ];

  for (const hook of hooks) hook.receiveMessages(push, hooks);

  // Each processor got its own surface's messages. The holder's also got
  // the local /ui/response write settling the action, ahead of the push.
  assert.deepEqual(orders.fed.filter((message) => push.includes(message)), [push[1]]);
  assert.deepEqual(summary.fed, [push[2]]);
  assert.deepEqual(unscoped.fed, [push[3]]);

  // The actionResponse resolved on the hook that held it, and only there.
  assert.equal(orders.pendingActions.has("act-1"), false);
  assert.deepEqual(orders.events.map((event) => event.detail.actionId), ["act-1"]);
  assert.deepEqual([...summary.events, ...unscoped.events], []);

  // The callFunction ran once, on the unscoped hook.
  await Promise.resolve();
  assert.deepEqual(unscoped.calls, [{url: "https://example.com"}]);
  assert.deepEqual([...orders.calls, ...summary.calls], []);
});

test("a lone unscoped hook receives the push unchanged", () => {
  const hook = hookWith();
  const push = [v09("createSurface", "a", {catalogId: "c"}), v09("createSurface", "b", {catalogId: "c"})];

  hook.receiveMessages(push, [hook]);

  assert.deepEqual(hook.fed, push);
});

test("a scoped hook binds only its own surface to its element", () => {
  const hook = hookWith({surface: "summary"});

  hook.adoptSurface({id: "orders"});
  assert.equal(hook.surfaceEl.surface, undefined);

  const summary = {id: "summary"};
  hook.adoptSurface(summary);
  assert.equal(hook.surfaceEl.surface, summary);
});

test("an unscoped hook binds the last surface created", () => {
  const hook = hookWith();
  const second = {id: "b"};

  hook.adoptSurface({id: "a"});
  hook.adoptSurface(second);

  assert.equal(hook.surfaceEl.surface, second);
});

test("a held actionResponse reaches only its holder whichever hook sees the push first", () => {
  for (const order of [[0, 1, 2], [2, 1, 0], [1, 0, 2]]) {
    const {orders, summary, unscoped, hooks} = page();
    summary.pendingActions.set("act-1", {surfaceId: "summary"});
    const push = [actionResponse("act-1")];

    for (const index of order) hooks[index].receiveMessages(push, hooks);

    assert.deepEqual(summary.events.map((event) => event.detail.actionId), ["act-1"]);
    assert.deepEqual([...orders.events, ...unscoped.events], [], `order ${order}`);
  }
});
