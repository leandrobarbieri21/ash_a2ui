import test from "node:test";
import assert from "node:assert/strict";

import {replaceExistingSurfaces} from "../../priv/js/ash_a2ui_messages.js";

const create = (surfaceId, version = "v0.9.1") => ({version, createSurface: {surfaceId, catalogId: "c"}});
const update = (surfaceId) => ({version: "v0.9.1", updateComponents: {surfaceId, components: [{id: "root"}]}});

test("a createSurface for a new surface passes through untouched", () => {
  const batch = [create("s1"), update("s1")];
  assert.deepEqual(replaceExistingSurfaces(batch, () => false), batch);
});

test("a createSurface for a surface already held is preceded by its deleteSurface", () => {
  const batch = [create("s1"), update("s1")];
  const out = replaceExistingSurfaces(batch, (id) => id === "s1");

  assert.deepEqual(out, [{version: "v0.9.1", deleteSurface: {surfaceId: "s1"}}, ...batch]);
});

test("only the surface that exists is replaced", () => {
  const out = replaceExistingSurfaces([create("a"), create("b")], (id) => id === "b");
  assert.deepEqual(
    out.map((m) => Object.keys(m).find((k) => k !== "version") + ":" + (m.createSurface || m.deleteSurface).surfaceId),
    ["createSurface:a", "deleteSurface:b", "createSurface:b"],
  );
});

test("a second createSurface in one batch replaces the first", () => {
  const out = replaceExistingSurfaces([create("s1"), create("s1")], () => false);
  assert.equal(out.length, 3);
  assert.ok(out[1].deleteSurface);
});

test("a deleteSurface earlier in the batch clears the id", () => {
  const batch = [{version: "v0.9.1", deleteSurface: {surfaceId: "s1"}}, create("s1")];
  assert.deepEqual(replaceExistingSurfaces(batch, () => true), batch);
});

test("messages without a version are replaced without one", () => {
  const out = replaceExistingSurfaces([{createSurface: {surfaceId: "s1", catalogId: "c"}}], () => true);
  assert.deepEqual(out[0], {deleteSurface: {surfaceId: "s1"}});
});

test("the input array and messages are not modified", () => {
  const batch = [create("s1")];
  const copy = JSON.parse(JSON.stringify(batch));
  replaceExistingSurfaces(batch, () => true);
  assert.deepEqual(batch, copy);
});
