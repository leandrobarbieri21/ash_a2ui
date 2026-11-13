import test from "node:test";
import assert from "node:assert/strict";

import {
  ASH_A2UI_CATALOG,
  ASH_A2UI_CATALOG_ID,
  ashActionCall,
  createAshFunctionCatalog,
  feedback,
  panelStateOf,
  pendingFeedback,
  quietAction,
  replaceExistingSurfaces,
  rpcError,
  slowFeedback,
} from "../../priv/js/ash_a2ui_protocol.js";
import {readJson, webCore} from "./support.mjs";

test("the embedded catalog document is the shipped catalog.json", () => {
  assert.deepEqual(ASH_A2UI_CATALOG, readJson("priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json"));
  assert.equal(ASH_A2UI_CATALOG.catalogId, ASH_A2UI_CATALOG_ID);
});

test("createAshFunctionCatalog binds both functions with the document's callers", () => {
  const catalog = createAshFunctionCatalog(webCore.Catalog, {
    ashAction: () => "acted",
    downloadFile: () => undefined,
  });

  assert.equal(catalog.id, ASH_A2UI_CATALOG_ID);
  assert.equal(catalog.protocolVersion, "1.0");
  assert.deepEqual([...catalog.components.keys()], []);

  const ashAction = catalog.functions.get("ashAction");
  assert.equal(ashAction.requiresUserActivation, true);
  assert.equal(ashAction.allowedCallers, undefined);
  assert.equal(ashAction.execute(), "acted");

  assert.equal(catalog.functions.get("downloadFile").allowedCallers, "agentOnly");
});

test("createAshFunctionCatalog refuses a missing implementation", () => {
  assert.throws(
    () => createAshFunctionCatalog(webCore.Catalog, {ashAction: () => null}),
    /no implementation for downloadFile/,
  );
});

test("feedback maps are always whole", () => {
  assert.deepEqual(feedback(), {
    kind: "",
    message: "",
    code: "",
    functionCallId: "",
    result: {},
    resultText: "",
  });
  assert.deepEqual(pendingFeedback("Working…", "f1"), {
    ...feedback("pending", "Working…"),
    functionCallId: "f1",
  });
  assert.deepEqual(slowFeedback("Still working…", "f1"), {
    ...feedback("pending", "Still working…"),
    code: "TIMEOUT",
    functionCallId: "f1",
  });
});

test("quietAction names the actions that report no outcome of their own", () => {
  for (const name of ["query", "option_search", "context_search", "prompt", "wizard_next"]) {
    assert.equal(quietAction({name}), true, name);
  }
  for (const name of ["submit_form", "invoke", "edit_cell", "start_edit", "context_select"]) {
    assert.equal(quietAction({name}), false, name);
  }
  assert.equal(quietAction(undefined), false);
});

test("ashActionCall names the ash_a2ui catalog", () => {
  assert.deepEqual(ashActionCall({name: "submit_form"}), {
    "@call": "ashAction",
    catalogId: ASH_A2UI_CATALOG_ID,
    args: {name: "submit_form"},
  });
});

test("rpcError prefers the agent's own error over web_core's prefixed message", () => {
  const rejected = new webCore.A2uiRpcError("Not allowed", "FORBIDDEN", "f1", {
    code: "FORBIDDEN",
    message: "Not allowed",
  });
  assert.deepEqual(rpcError(rejected), {code: "FORBIDDEN", message: "Not allowed"});

  const timeout = new webCore.A2uiRpcError("timed out", "TIMEOUT", "f1");
  assert.deepEqual(rpcError(timeout), {code: "TIMEOUT", message: "[TIMEOUT] timed out"});

  assert.deepEqual(rpcError("boom"), {code: "UNKNOWN_ERROR", message: "boom"});
});

const create = (surfaceId) => ({version: "1.0", createSurface: {surfaceId, catalogId: "c"}});

test("replaceExistingSurfaces passes a new surface through", () => {
  const batch = [create("s1")];
  assert.deepEqual(
    replaceExistingSurfaces(batch, () => false),
    batch,
  );
});

test("replaceExistingSurfaces deletes a held surface before creating it again", () => {
  const batch = [create("s1")];
  assert.deepEqual(
    replaceExistingSurfaces(batch, (id) => id === "s1"),
    [{version: "1.0", deleteSurface: {surfaceId: "s1"}}, ...batch],
  );
});

test("replaceExistingSurfaces tracks creates and deletes within the batch", () => {
  assert.equal(replaceExistingSurfaces([create("s1"), create("s1")], () => false).length, 3);

  const batch = [{version: "1.0", deleteSurface: {surfaceId: "s1"}}, create("s1")];
  assert.deepEqual(
    replaceExistingSurfaces(batch, () => true),
    batch,
  );
});

test("replaceExistingSurfaces leaves its input alone", () => {
  const batch = [create("s1")];
  const copy = structuredClone(batch);
  replaceExistingSurfaces(batch, () => true);
  assert.deepEqual(batch, copy);
});

test("panelStateOf reads the bootstrap data model", () => {
  const surface = (visible) => ({
    version: "1.0",
    createSurface: {surfaceId: "s1", dataModel: {ui: {panel: {visible}}}},
  });
  assert.equal(panelStateOf(surface([1])), true);
  assert.equal(panelStateOf(surface([])), false);
  assert.equal(panelStateOf({createSurface: {surfaceId: "s1"}}), null);
});

test("panelStateOf reads a /ui/panel write and a whole-model write", () => {
  const write = (path, value) => ({updateDataModel: {surfaceId: "s1", path, value}});
  assert.equal(panelStateOf(write("/ui/panel", {visible: [1]})), true);
  assert.equal(panelStateOf(write("/ui/panel", {visible: []})), false);
  assert.equal(panelStateOf(write(undefined, {ui: {panel: {visible: [1]}}})), true);
  assert.equal(panelStateOf(write("/", {ui: {panel: {visible: []}}})), false);
  assert.equal(panelStateOf(write("/name", "Ada")), null);
  assert.equal(panelStateOf(null), null);
});
