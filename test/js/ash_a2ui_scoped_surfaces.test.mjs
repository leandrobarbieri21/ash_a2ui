import test from "node:test";
import assert from "node:assert/strict";

// The hook module touches no browser global at import time.
import {AshA2ui, acceptsMessage, addressedSurfaceId} from "../../priv/js/ash_a2ui_hook.js";
import {ASH_A2UI_CATALOG_ID, feedback} from "../../priv/js/ash_a2ui_protocol.js";
import {click, feedbackOf, mountHook, sent, tick} from "./harness.mjs";
import {BASIC_CATALOG_ID} from "./support.mjs";

// A hook with only the routing fields acceptsMessage reads.
function routed({surface = null, primary = false, calls = []} = {}) {
  const hook = Object.create(AshA2ui);
  hook.scopedSurface = surface;
  hook.primary = primary;
  hook.pendingCalls = new Set(calls);
  return hook;
}

const addressed = (kind, surfaceId, extra = {}) => ({version: "1.0", [kind]: {surfaceId, ...extra}});

const rendererCall = (surfaceId) => ({
  version: "1.0",
  callRendererFunction: {
    ...(surfaceId === undefined ? {} : {surfaceId}),
    functionCallId: "d1",
    callFunction: {
      "@call": "downloadFile",
      catalogId: ASH_A2UI_CATALOG_ID,
      args: {filename: "tasks.csv", dataUrl: "data:text/csv;base64,YQ=="},
    },
  },
});

const agentResponse = (functionCallId, body = {value: {}}) => ({
  version: "1.0",
  agentFunctionResponse: {functionCallId, ...body},
});

// The page: two scoped containers ("orders" and "summary") and one unscoped.
function page() {
  const orders = routed({surface: "orders"});
  const summary = routed({surface: "summary"});
  const unscoped = routed();
  return {orders, summary, unscoped, hooks: [orders, summary, unscoped]};
}

test("addressedSurfaceId reads the surface id of every addressed message", () => {
  for (const kind of ["createSurface", "updateComponents", "updateDataModel", "deleteSurface"]) {
    assert.equal(addressedSurfaceId(addressed(kind, "a")), "a");
  }
  assert.equal(addressedSurfaceId(rendererCall("s1")), "s1");
  assert.equal(addressedSurfaceId(rendererCall()), undefined);
  assert.equal(addressedSurfaceId(agentResponse("c1")), undefined);
  assert.equal(addressedSurfaceId(null), undefined);
});

test("a message addressed to a scoped surface reaches only that surface's hook", () => {
  const {orders, summary, unscoped, hooks} = page();
  const message = addressed("updateComponents", "summary", {components: []});

  assert.equal(acceptsMessage(message, summary, hooks), true);
  assert.equal(acceptsMessage(message, orders, hooks), false);
  assert.equal(acceptsMessage(message, unscoped, hooks), false);
});

test("a message for a surface no hook claims reaches only the unscoped hook", () => {
  const {orders, summary, unscoped, hooks} = page();
  const message = addressed("createSurface", "other", {catalogId: BASIC_CATALOG_ID});

  assert.equal(acceptsMessage(message, unscoped, hooks), true);
  assert.equal(acceptsMessage(message, orders, hooks), false);
  assert.equal(acceptsMessage(message, summary, hooks), false);
});

test("an agentFunctionResponse reaches only the hook that sent its functionCallId", () => {
  const {orders, summary, unscoped, hooks} = page();
  summary.pendingCalls.add("call-1");

  assert.equal(acceptsMessage(agentResponse("call-1"), summary, hooks), true);
  assert.equal(acceptsMessage(agentResponse("call-1"), orders, hooks), false);
  assert.equal(acceptsMessage(agentResponse("call-1"), unscoped, hooks), false);
});

test("an agentFunctionResponse no hook sent goes to the primary hook", () => {
  const {orders, summary, unscoped, hooks} = page();

  assert.equal(acceptsMessage(agentResponse("gone"), unscoped, hooks), true);
  assert.equal(acceptsMessage(agentResponse("gone"), orders, hooks), false);
  assert.equal(acceptsMessage(agentResponse("gone"), summary, hooks), false);
});

test("a renderer function call naming no surface goes to the unscoped hook", () => {
  const {orders, summary, unscoped, hooks} = page();

  assert.equal(acceptsMessage(rendererCall(), unscoped, hooks), true);
  assert.equal(acceptsMessage(rendererCall(), orders, hooks), false);
  assert.equal(acceptsMessage(rendererCall(), summary, hooks), false);
  assert.equal(acceptsMessage(rendererCall("orders"), orders, hooks), true);
  assert.equal(acceptsMessage(rendererCall("orders"), unscoped, hooks), false);
});

test("a hook marked primary takes the messages naming no surface", () => {
  const orders = routed({surface: "orders", primary: true});
  const summary = routed({surface: "summary"});
  const unscoped = routed();
  const hooks = [orders, summary, unscoped];

  assert.equal(acceptsMessage(rendererCall(), orders, hooks), true);
  assert.equal(acceptsMessage(rendererCall(), summary, hooks), false);
  assert.equal(acceptsMessage(rendererCall(), unscoped, hooks), false);
});

test("with only scoped hooks and none primary, the first mounted takes unaddressed messages", () => {
  const orders = routed({surface: "orders"});
  const summary = routed({surface: "summary"});
  const hooks = [orders, summary];

  assert.equal(acceptsMessage(rendererCall(), orders, hooks), true);
  assert.equal(acceptsMessage(rendererCall(), summary, hooks), false);
});

test("with no scoped or primary hook, every hook takes every message", () => {
  const first = routed({calls: ["call-1"]});
  const second = routed();
  const hooks = [first, second];

  for (const message of [addressed("createSurface", "s"), rendererCall(), agentResponse("call-1")]) {
    assert.equal(acceptsMessage(message, first, hooks), true);
    assert.equal(acceptsMessage(message, second, hooks), true);
  }
});

test("a scoped hook binds only its own surface to its element", () => {
  const hook = Object.create(AshA2ui);
  hook.scopedSurface = "summary";
  hook.surfaceIds = new Set();
  hook.surfaceEl = {};
  hook.skeletonEl = null;

  hook.adoptSurface({id: "orders"});
  assert.equal(hook.surfaceEl.surface, undefined);

  const summary = {id: "summary"};
  hook.adoptSurface(summary);
  assert.equal(hook.surfaceEl.surface, summary);
});

// --- two real hooks on one page ----------------------------------------------

// A surface whose Save button is an ashAction.
function surface(surfaceId) {
  return {
    version: "1.0",
    createSurface: {
      surfaceId,
      catalogId: BASIC_CATALOG_ID,
      components: [
        {id: "root", component: "Column", children: ["save"]},
        {
          id: "save",
          component: "Button",
          child: "save_label",
          action: {
            functionCall: {
              "@call": "ashAction",
              catalogId: ASH_A2UI_CATALOG_ID,
              args: {name: "submit_form", sourceComponentId: "save", context: {surface: surfaceId}},
            },
          },
        },
        {id: "save_label", component: "Text", text: "Save"},
      ],
      dataModel: {ui: {feedback: feedback()}},
    },
  };
}

const settled = (surfaceId, functionCallId, message) =>
  addressed("updateDataModel", surfaceId, {
    path: "/ui/feedback",
    value: feedback("success", message, {functionCallId}),
  });

// Two scoped containers and one push carrying both surfaces, as a LiveView
// page with two LiveRenderer surfaces delivers it to every hook.
function twoSurfaces() {
  const orders = mountHook({pendingMessage: "Saving…"});
  const summary = mountHook({pendingMessage: "Saving…"});
  orders.scopedSurface = "orders";
  summary.scopedSurface = "summary";
  const hooks = [orders, summary];

  const push = [surface("orders"), surface("summary")];
  for (const hook of hooks) hook.receiveMessages(push, hooks);

  return {orders, summary, hooks};
}

test("each scoped hook renders only its own surface from a shared push", () => {
  const {orders, summary} = twoSurfaces();

  assert.ok(orders.surfaceExists("orders"));
  assert.equal(orders.surfaceExists("summary"), false);
  assert.ok(summary.surfaceExists("summary"));
  assert.equal(summary.surfaceExists("orders"), false);
});

test("an ashAction on one surface is answered on that surface's hook only", async () => {
  const {orders, summary, hooks} = twoSurfaces();

  const done = click(summary, "summary", "save");
  await tick();

  const [call] = sent(summary);
  const {surfaceId, functionCallId, callFunction} = call.callAgentFunction;
  assert.equal(surfaceId, "summary");
  assert.deepEqual(callFunction.args.context, {surface: "summary"});
  assert.deepEqual(sent(orders), []);
  assert.deepEqual(feedbackOf(summary, "summary"), feedback("pending", "Saving…", {functionCallId}));
  assert.deepEqual(feedbackOf(orders, "orders"), feedback());

  // The agent's batch: the summary surface's settled feedback, a write to
  // the orders surface, and the response correlated by functionCallId.
  const push = [
    settled("summary", functionCallId, "Saved"),
    addressed("updateDataModel", "orders", {path: "/ui/note", value: "refreshed"}),
    agentResponse(functionCallId, {value: {kind: "success"}}),
  ];
  // The hook that did not send the call sees the push first.
  for (const hook of [orders, summary]) hook.receiveMessages(push, hooks);
  await done;

  assert.deepEqual(summary.responses, [
    {functionCallId, surfaceId: "summary", response: {value: {kind: "success"}}},
  ]);
  assert.deepEqual(orders.responses, []);
  assert.deepEqual(feedbackOf(summary, "summary"), feedback("success", "Saved", {functionCallId}));
  assert.equal(orders.processor.getSurface("orders").dataModel.get("/ui/note"), "refreshed");
  assert.equal(summary.pendingCalls.has(functionCallId), false);

  // Neither hook reported an unknown message back to the agent.
  assert.deepEqual(sent(orders), []);
  assert.equal(sent(summary).length, 1);
});

test("calls in flight on both surfaces settle on their own hooks", async () => {
  const {orders, summary, hooks} = twoSurfaces();

  const ordersDone = click(orders, "orders", "save");
  const summaryDone = click(summary, "summary", "save");
  await tick();

  const ordersCall = sent(orders)[0].callAgentFunction.functionCallId;
  const summaryCall = sent(summary)[0].callAgentFunction.functionCallId;

  const push = [
    settled("summary", summaryCall, "Summary saved"),
    agentResponse(summaryCall, {value: {kind: "success"}}),
    settled("orders", ordersCall, "Orders saved"),
    agentResponse(ordersCall, {error: {code: "FORBIDDEN", message: "No"}}),
  ];
  for (const hook of hooks) hook.receiveMessages(push, hooks);
  await Promise.all([ordersDone, summaryDone]);

  assert.deepEqual(
    summary.responses.map(({functionCallId, response}) => [functionCallId, response]),
    [[summaryCall, {value: {kind: "success"}}]],
  );
  assert.deepEqual(
    orders.responses.map(({functionCallId, response}) => [functionCallId, response]),
    [[ordersCall, {error: {code: "FORBIDDEN", message: "No"}}]],
  );
  assert.deepEqual(
    feedbackOf(orders, "orders"),
    feedback("success", "Orders saved", {functionCallId: ordersCall}),
  );
});

test("a lone unscoped hook receives the push unchanged", () => {
  const hook = mountHook();
  const push = [surface("a"), surface("b")];

  hook.receiveMessages(push, [hook]);

  assert.ok(hook.surfaceExists("a"));
  assert.ok(hook.surfaceExists("b"));
});
