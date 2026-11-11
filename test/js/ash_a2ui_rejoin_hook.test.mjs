import test from "node:test";
import assert from "node:assert/strict";

// The hook module touches no browser global at import time.
import {AshA2ui, configureAshA2ui} from "../../priv/js/ash_a2ui_hook.js";

// A processor with the real one's contract for surfaces: creating a surface
// that is held raises, deleting disposes it and releases its listeners.
class FakeProcessor {
  constructor() {
    this.surfaces = new Map();
    this.model = {getSurface: (id) => this.surfaces.get(id)};
    this.disposed = [];
    this.fed = [];
  }

  processMessages(messages) {
    for (const message of messages) {
      this.fed.push(message);
      if (message.createSurface) {
        const {surfaceId} = message.createSurface;
        if (this.surfaces.has(surfaceId)) throw new Error(`Surface ${surfaceId} already exists.`);
        this.surfaces.set(surfaceId, {id: surfaceId});
      } else if (message.deleteSurface) {
        const surface = this.surfaces.get(message.deleteSurface.surfaceId);
        this.surfaces.delete(message.deleteSurface.surfaceId);
        if (surface) this.disposed.push(surface);
      }
    }
  }
}

function hookWith(processor) {
  const hook = Object.create(AshA2ui);
  hook.processor = processor;
  hook.deps = {catalogs: []};
  hook.v1Surfaces = new Set();
  hook.pendingActions = new Map();
  hook.surfaceIds = new Set();
  hook.skeletonEl = null;
  hook.panelVisible = false;
  return hook;
}

const bootstrap = [
  {version: "v0.9.1", createSurface: {surfaceId: "board", catalogId: "c"}},
  {version: "v0.9.1", updateComponents: {surfaceId: "board", components: [{id: "root"}]}},
];

test("bootstrapping the surface again on the same hook replaces it", () => {
  const processor = new FakeProcessor();
  const hook = hookWith(processor);

  hook.processMessages(bootstrap);
  const first = processor.surfaces.get("board");

  assert.doesNotThrow(() => hook.processMessages(bootstrap));
  assert.deepEqual(processor.disposed, [first]);
  assert.notEqual(processor.surfaces.get("board"), first);
  assert.equal(processor.surfaces.size, 1);
});

test("a v1.0 createSurface after a rejoin replaces the surface too", () => {
  const processor = new FakeProcessor();
  const hook = hookWith(processor);
  const v1 = [{version: "v1.0", createSurface: {surfaceId: "board", catalogId: "c", components: [{id: "root"}]}}];

  hook.processMessages(v1);
  assert.doesNotThrow(() => hook.processMessages(v1));
  assert.equal(processor.disposed.length, 1);
});
