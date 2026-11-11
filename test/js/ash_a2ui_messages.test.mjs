import test from "node:test";
import assert from "node:assert/strict";

import {
  V1_VERSION,
  adaptMessage,
  adaptV1CreateSurface,
  panelStateOf,
  settledUiResponse,
} from "../../priv/js/ash_a2ui_messages.js";

const V1_BASIC = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json";
const V0_BASIC = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json";

test("v0.9.1 messages pass through untouched", () => {
  const message = {
    version: "v0.9.1",
    createSurface: {surfaceId: "s1", catalogId: V0_BASIC},
  };
  const result = adaptMessage(message, {catalogs: []});

  assert.deepEqual(result, {messages: [message]});
  assert.equal(result.messages[0], message);
});

test("messages without a version pass through untouched", () => {
  const message = {updateDataModel: {surfaceId: "s1", path: "/x", value: 1}};

  assert.deepEqual(adaptMessage(message), {messages: [message]});
});

test("adaptMessage(null) passes the message through", () => {
  assert.deepEqual(adaptMessage(null), {messages: [null]});
});

test("a v1.0 createSurface expands into the v0.9 triple", () => {
  const result = adaptMessage(
    {
      version: V1_VERSION,
      createSurface: {
        surfaceId: "s1",
        catalogId: V1_BASIC,
        surfaceProperties: {"--a2ui-color-primary": "red"},
        components: [{id: "c1"}],
        dataModel: {name: "Ada"},
      },
    },
    {catalogs: [{id: V0_BASIC}]},
  );

  assert.equal(result.createdSurfaceId, "s1");
  assert.deepEqual(result.messages, [
    {createSurface: {surfaceId: "s1", catalogId: V0_BASIC, theme: {"--a2ui-color-primary": "red"}}},
    {updateComponents: {surfaceId: "s1", components: [{id: "c1"}]}},
    {updateDataModel: {surfaceId: "s1", path: "/", value: {name: "Ada"}}},
  ]);
});

test("an unregistered v1.0 basic-catalog id maps onto the v0.9 catalog id", () => {
  const {messages} = adaptV1CreateSurface(
    {surfaceId: "s1", catalogId: V1_BASIC},
    [{id: "https://example.com/catalog.json"}],
  );

  assert.deepEqual(messages, [{createSurface: {surfaceId: "s1", catalogId: V0_BASIC}}]);
});

test("a registered v1.0 basic-catalog id is kept", () => {
  const {messages} = adaptV1CreateSurface(
    {surfaceId: "s1", catalogId: V1_BASIC},
    [{id: V1_BASIC}],
  );

  assert.deepEqual(messages, [{createSurface: {surfaceId: "s1", catalogId: V1_BASIC}}]);
});

test("an unregistered non-basic catalog id is kept", () => {
  const {messages} = adaptV1CreateSurface(
    {surfaceId: "s1", catalogId: "https://example.com/catalog.json"},
    [],
  );

  assert.deepEqual(messages, [
    {createSurface: {surfaceId: "s1", catalogId: "https://example.com/catalog.json"}},
  ]);
});

test("createSurface omits absent components, dataModel and sendDataModel", () => {
  const {messages} = adaptV1CreateSurface({surfaceId: "s1", catalogId: V0_BASIC}, []);

  assert.deepEqual(messages, [{createSurface: {surfaceId: "s1", catalogId: V0_BASIC}}]);
  assert.deepEqual(
    adaptV1CreateSurface(
      {surfaceId: "s1", catalogId: V0_BASIC, components: []},
      [],
    ).messages,
    [{createSurface: {surfaceId: "s1", catalogId: V0_BASIC}}],
  );
});

test("sendDataModel passes through as createSurface.sendDataModel", () => {
  const {messages} = adaptV1CreateSurface(
    {surfaceId: "s1", catalogId: V0_BASIC, sendDataModel: true},
    [],
  );

  assert.deepEqual(messages, [
    {createSurface: {surfaceId: "s1", catalogId: V0_BASIC, sendDataModel: true}},
  ]);
});

test("a v1.0 actionResponse is consumed, not forwarded to the renderer", () => {
  const message = {version: V1_VERSION, actionId: "a1", actionResponse: {value: {ok: 1}}};
  const result = adaptMessage(message, {catalogs: []});

  assert.deepEqual(result.messages, []);
  assert.equal(result.actionResponse, message);
});

test("a v1.0 callFunction is consumed, not forwarded to the renderer", () => {
  const message = {
    version: V1_VERSION,
    functionCallId: "f1",
    callFunction: {call: "openUrl", args: {url: "https://example.com"}},
  };
  const result = adaptMessage(message, {catalogs: []});

  assert.deepEqual(result.messages, []);
  assert.equal(result.callFunction, message);
});

test("a v1.0 deleteSurface passes through and reports the deleted surface id", () => {
  const message = {version: V1_VERSION, deleteSurface: {surfaceId: "s1"}};
  const result = adaptMessage(message, {catalogs: []});

  assert.deepEqual(result, {messages: [message], deletedSurfaceId: "s1"});
});

test("a deleteSurface without a surface id passes through untracked", () => {
  const message = {version: V1_VERSION, deleteSurface: {}};

  assert.deepEqual(adaptMessage(message, {catalogs: []}), {
    messages: [message],
    deletedSurfaceId: null,
  });
});

test("v1.0 updateComponents and updateDataModel pass through shape-compatibly", () => {
  const components = {
    version: V1_VERSION,
    updateComponents: {surfaceId: "s1", components: [{id: "c1"}]},
  };
  const dataModel = {
    version: V1_VERSION,
    updateDataModel: {surfaceId: "s1", path: "/ui/panel", value: {visible: [1]}},
  };

  assert.deepEqual(adaptMessage(components, {catalogs: []}), {
    messages: [components],
    deletedSurfaceId: null,
  });
  assert.deepEqual(adaptMessage(dataModel, {catalogs: []}), {
    messages: [dataModel],
    deletedSurfaceId: null,
  });
});

test("panelStateOf reads the /ui/panel action-handler write", () => {
  assert.equal(
    panelStateOf({updateDataModel: {path: "/ui/panel", value: {visible: [1]}}}),
    true,
  );
  assert.equal(
    panelStateOf({updateDataModel: {path: "/ui/panel", value: {visible: []}}}),
    false,
  );
});

test("panelStateOf reads the panel from a full data model write", () => {
  assert.equal(
    panelStateOf({updateDataModel: {path: "/", value: {ui: {panel: {visible: [1]}}}}}),
    true,
  );
  assert.equal(
    panelStateOf({updateDataModel: {path: "/", value: {ui: {panel: {visible: []}}}}}),
    false,
  );
});

test("panelStateOf returns null when the message carries no panel state", () => {
  assert.equal(panelStateOf(null), null);
  assert.equal(panelStateOf({createSurface: {surfaceId: "s1"}}), null);
  assert.equal(panelStateOf({updateDataModel: {path: "/name", value: "Ada"}}), null);
  assert.equal(
    panelStateOf({updateDataModel: {path: "/", value: {ui: {other: {}}}}}),
    null,
  );
});

test("settledUiResponse maps an error actionResponse onto the error shape", () => {
  assert.deepEqual(settledUiResponse({error: {code: "X", message: "boom"}}), {
    status: "error",
    code: "X",
    message: "boom",
    result: {},
    resultText: "",
  });
});

test("settledUiResponse defaults missing error code and message", () => {
  assert.deepEqual(settledUiResponse({error: {}}), {
    status: "error",
    code: "",
    message: "",
    result: {},
    resultText: "",
  });
});

test("settledUiResponse spreads the response value onto the ok shape", () => {
  assert.deepEqual(settledUiResponse({value: {answer: 42, resultText: "done"}}), {
    status: "ok",
    message: "",
    result: {},
    resultText: "done",
    answer: 42,
  });
});

test("settledUiResponse of an empty or absent payload is the bare ok shape", () => {
  const ok = {status: "ok", message: "", result: {}, resultText: ""};

  assert.deepEqual(settledUiResponse({}), ok);
  assert.deepEqual(settledUiResponse(undefined), ok);
});
