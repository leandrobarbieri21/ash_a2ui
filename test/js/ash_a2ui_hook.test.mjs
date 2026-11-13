import test from "node:test";
import assert from "node:assert/strict";

import {ASH_A2UI_CATALOG_ID, feedback} from "../../priv/js/ash_a2ui_protocol.js";
import {click, feedbackOf, mountHook, sent, tick} from "./harness.mjs";
import {BASIC_CATALOG_ID} from "./support.mjs";

const ashAction = (name, context = {}) => ({
  functionCall: {
    "@call": "ashAction",
    catalogId: ASH_A2UI_CATALOG_ID,
    args: {name, sourceComponentId: "submit", context},
  },
});

// A form whose Submit is an ashAction and whose Help is an event action.
function bootstrap(hook) {
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: BASIC_CATALOG_ID,
        components: [
          {id: "root", component: "Column", children: ["name", "submit", "help"]},
          {id: "name", component: "TextField", label: "Name", value: {"@path": "/form/name"}},
          {
            id: "submit",
            component: "Button",
            child: "submit_label",
            action: ashAction("submit_form", {
              name: {"@path": "/form/name"},
              values: {name: {"@path": "/form/name"}},
            }),
          },
          {id: "submit_label", component: "Text", text: "Save"},
          {
            id: "help",
            component: "Button",
            child: "help_label",
            action: {event: {name: "help", context: {topic: "names"}}},
          },
          {id: "help_label", component: "Text", text: "Help"},
        ],
        dataModel: {form: {name: "Ada"}, ui: {feedback: feedback()}},
      },
    },
  ]);
}

const agentResponse = (functionCallId, body) => ({
  version: "1.0",
  agentFunctionResponse: {functionCallId, ...body},
});

const settled = (functionCallId, kind, message) => ({
  version: "1.0",
  updateDataModel: {
    surfaceId: "s1",
    path: "/ui/feedback",
    value: feedback(kind, message, {functionCallId}),
  },
});

test("an ashAction click sends callAgentFunction and writes pending feedback first", async () => {
  const hook = mountHook({pendingMessage: "Saving…"});
  bootstrap(hook);

  const done = click(hook, "s1", "submit");
  await tick();

  const [call] = sent(hook);
  assert.equal(call.version, "1.0");
  const {surfaceId, functionCallId, callFunction} = call.callAgentFunction;
  assert.equal(surfaceId, "s1");
  assert.equal(typeof functionCallId, "string");
  assert.deepEqual(callFunction, {
    "@call": "ashAction",
    catalogId: ASH_A2UI_CATALOG_ID,
    args: {
      name: "submit_form",
      sourceComponentId: "submit",
      context: {name: "Ada", values: {name: "Ada"}},
    },
  });

  assert.deepEqual(feedbackOf(hook, "s1"), feedback("pending", "Saving…", {functionCallId}));

  hook.processMessages([
    settled(functionCallId, "success", "Saved"),
    agentResponse(functionCallId, {value: {kind: "success"}}),
  ]);
  await done;

  assert.deepEqual(feedbackOf(hook, "s1"), feedback("success", "Saved", {functionCallId}));
  assert.deepEqual(hook.responses, [
    {functionCallId, surfaceId: "s1", response: {value: {kind: "success"}}},
  ]);
  assert.equal(sent(hook).length, 1, "nothing else goes out");
});

test("an agent error settles the call with the agent's code and message", async () => {
  const hook = mountHook();
  bootstrap(hook);

  const done = click(hook, "s1", "submit");
  await tick();
  const {functionCallId} = sent(hook)[0].callAgentFunction;

  hook.processMessages([
    settled(functionCallId, "error", "Not allowed"),
    agentResponse(functionCallId, {error: {code: "FORBIDDEN", message: "Not allowed"}}),
  ]);
  await done;

  assert.deepEqual(hook.responses[0].response, {
    error: {code: "FORBIDDEN", message: "Not allowed"},
  });
  assert.deepEqual(feedbackOf(hook, "s1"), feedback("error", "Not allowed", {functionCallId}));
});

test("an unanswered call stays pending under a slow notice, until the late outcome", async () => {
  const hook = mountHook({actionTimeoutMs: 10, slowMessage: "Still at it…"});
  bootstrap(hook);

  await click(hook, "s1", "submit");
  const {functionCallId} = sent(hook)[0].callAgentFunction;

  assert.equal(hook.responses[0].response.error.code, "TIMEOUT");
  assert.deepEqual(feedbackOf(hook, "s1"), {
    ...feedback("pending", "Still at it…"),
    code: "TIMEOUT",
    functionCallId,
  });

  hook.processMessages([settled(functionCallId, "success", "Saved")]);
  assert.deepEqual(feedbackOf(hook, "s1"), feedback("success", "Saved", {functionCallId}));
});

test("the pending and slow messages are the surface's own words", async () => {
  const hook = mountHook({actionTimeoutMs: 10, pendingMessage: "Working…"});
  bootstrap(hook);
  hook.processMessages([
    {
      version: "1.0",
      updateDataModel: {
        surfaceId: "s1",
        path: "/ui/feedback_text",
        value: {pending: "En cours…", slow: "Toujours en cours…"},
      },
    },
  ]);

  const done = click(hook, "s1", "submit");
  await tick();
  assert.equal(feedbackOf(hook, "s1").message, "En cours…");

  await done;
  assert.equal(feedbackOf(hook, "s1").message, "Toujours en cours…");
});

test("a quiet action leaves the last outcome and its result on screen", async () => {
  const hook = mountHook({actionTimeoutMs: 10});
  bootstrap(hook);
  const saved = feedback("success", "Saved", {resultText: "Total: 42"});
  hook.processMessages([
    {version: "1.0", updateDataModel: {surfaceId: "s1", path: "/ui/feedback", value: saved}},
  ]);

  const surface = hook.processor.getSurface("s1");
  const answered = hook.runAshAction(
    {name: "query", sourceComponentId: "pager", context: {page: 2}},
    {surface},
  );
  await tick();
  assert.deepEqual(feedbackOf(hook, "s1"), saved, "no pending state for a page turn");

  await answered;
  assert.equal(hook.responses[0].response.error.code, "TIMEOUT");
  assert.deepEqual(feedbackOf(hook, "s1"), saved, "no slow notice either");
});

test("query calls set /ui/loading until the last one is answered", async () => {
  const hook = mountHook({actionTimeoutMs: 0});
  bootstrap(hook);
  const surface = hook.processor.getSurface("s1");
  const loading = () => [surface.dataModel.get("/ui/loading"), surface.dataModel.get("/ui/loading_visible")];
  const query = (page) =>
    hook.runAshAction({name: "query", sourceComponentId: "pager", context: {page}}, {surface});

  const first = query(2);
  await tick();
  const second = query(3);
  await tick();
  assert.deepEqual(loading(), [true, [{id: "on"}]]);

  const [one, two] = sent(hook).map((message) => message.callAgentFunction.functionCallId);
  hook.processMessages([agentResponse(one, {value: {}})]);
  await first;
  assert.deepEqual(loading(), [true, [{id: "on"}]], "the later fetch is still on its way");

  hook.processMessages([agentResponse(two, {value: {}})]);
  await second;
  assert.deepEqual(loading(), [false, []]);
});

test("a write call leaves /ui/loading alone", async () => {
  const hook = mountHook({actionTimeoutMs: 10});
  bootstrap(hook);
  await click(hook, "s1", "submit");
  assert.equal(hook.processor.getSurface("s1").dataModel.get("/ui/loading"), undefined);
});

test("a timeout leaves feedback a later call owns", async () => {
  const hook = mountHook({actionTimeoutMs: 30});
  bootstrap(hook);

  const first = click(hook, "s1", "submit");
  await tick();
  const second = click(hook, "s1", "submit");
  await tick();
  const [
    ,
    {
      callAgentFunction: {functionCallId: secondId},
    },
  ] = sent(hook);

  await first;
  assert.equal(feedbackOf(hook, "s1").functionCallId, secondId);
  assert.equal(feedbackOf(hook, "s1").kind, "pending");

  hook.processMessages([
    settled(secondId, "success", "Saved"),
    agentResponse(secondId, {value: {}}),
  ]);
  await second;
  assert.equal(feedbackOf(hook, "s1").kind, "success");
});

test("actionTimeoutMs 0 waits for the agent", async () => {
  const hook = mountHook({actionTimeoutMs: 0});
  bootstrap(hook);

  const done = click(hook, "s1", "submit");
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(feedbackOf(hook, "s1").kind, "pending");

  const {functionCallId} = sent(hook)[0].callAgentFunction;
  hook.processMessages([agentResponse(functionCallId, {value: {}})]);
  await done;
  assert.deepEqual(hook.responses[0].response, {value: {}});
});

test("an event action is not sent: the agent answers ashAction calls only", async () => {
  const hook = mountHook();
  bootstrap(hook);

  const warn = console.warn;
  const warnings = [];
  console.warn = (...args) => warnings.push(args);
  try {
    await click(hook, "s1", "help");
  } finally {
    console.warn = warn;
  }

  assert.deepEqual(sent(hook), []);
  assert.equal(warnings.length, 1);
  assert.match(String(warnings[0][0]), /event actions are not sent/);
  assert.deepEqual(feedbackOf(hook, "s1"), feedback());
});

test("the agent's downloadFile call is answered with a rendererFunctionResponse", async () => {
  const hook = mountHook();
  bootstrap(hook);

  hook.processMessages([
    {
      version: "1.0",
      callRendererFunction: {
        surfaceId: "s1",
        functionCallId: "d1",
        callFunction: {
          "@call": "downloadFile",
          catalogId: ASH_A2UI_CATALOG_ID,
          args: {filename: "tasks.csv", dataUrl: "data:text/csv;base64,YQ=="},
        },
      },
    },
  ]);
  await tick();

  const [response] = sent(hook);
  assert.equal(response.version, "1.0");
  assert.equal(response.rendererFunctionResponse.functionCallId, "d1");
  assert.equal(response.rendererFunctionResponse.error, undefined);
});

test("the agent may not call ashAction on the renderer", async () => {
  const hook = mountHook();
  bootstrap(hook);

  hook.processMessages([
    {
      version: "1.0",
      callRendererFunction: {
        surfaceId: "s1",
        functionCallId: "x1",
        callFunction: {
          "@call": "ashAction",
          catalogId: ASH_A2UI_CATALOG_ID,
          args: {name: "submit_form"},
        },
      },
    },
  ]);
  await tick();

  const [response] = sent(hook);
  assert.equal(response.rendererFunctionResponse.functionCallId, "x1");
  assert.equal(response.rendererFunctionResponse.error.code, "INVALID_FUNCTION_CALL");
});

test("a message the processor rejects is reported to the agent as an error", () => {
  const hook = mountHook();
  bootstrap(hook);

  hook.processMessages([
    {
      version: "1.0",
      updateComponents: {surfaceId: "s1", components: [{id: "submit_label", component: "Text"}]},
    },
    {version: "1.0", updateDataModel: {surfaceId: "elsewhere", path: "/a", value: 1}},
  ]);

  const [invalid, unknown] = sent(hook);
  assert.equal(invalid.version, "1.0");
  assert.equal(invalid.error.code, "VALIDATION_FAILED");
  assert.equal(invalid.error.surfaceId, "s1");
  assert.equal(invalid.error.path, "/components/0/text");
  assert.equal(unknown.error.surfaceId, "elsewhere");
  assert.equal(sent(hook).length, 2);
});

test("bootstrapping the surface again on the same hook replaces it", () => {
  const hook = mountHook();
  bootstrap(hook);
  const first = hook.processor.getSurface("s1");

  bootstrap(hook);

  assert.deepEqual(sent(hook), []);
  assert.notEqual(hook.processor.getSurface("s1"), first);
  assert.equal(hook.processor.getSurfaces().size, 1);
});

test("the panel reveal is scheduled on the hidden-to-visible flip only", () => {
  const hook = mountHook();
  let reveals = 0;
  hook.schedulePanelReveal = () => reveals++;

  const panel = (visible) => ({
    version: "1.0",
    updateDataModel: {surfaceId: "s1", path: "/ui/panel", value: {visible}},
  });
  bootstrap(hook);
  hook.processMessages([panel([1])]);
  hook.processMessages([panel([1])]);
  hook.processMessages([panel([])]);
  hook.processMessages([panel([1])]);

  assert.equal(reveals, 2);
});

test("destroying the hook cancels the in-flight call", async () => {
  const hook = mountHook({actionTimeoutMs: 0});
  bootstrap(hook);

  const done = click(hook, "s1", "submit");
  await tick();
  hook.processor.dispose();
  await done;

  assert.equal(hook.responses[0].response.error.code, "CANCELLED");
});
