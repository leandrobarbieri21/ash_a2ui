// The four P0 contract fixtures (test/fixtures/v1_0_contract), fed through
// the hook and a real processor: every message applies with no error, and
// every Button's ashAction reaches the agent as a `callAgentFunction`.
//
// The fixtures are spec HEAD, whose component envelope keys are
// `@`-prefixed. @a2ui/web_core 0.15.0 rejects those keys and drops the
// surface (Gate R in the 1.0 programme), so against it these tests are
// skipped with that reason; run them against a build that accepts them
// with A2UI_WEB_CORE_DIR=<web_core package dir> mix js.test.

import test from "node:test";
import assert from "node:assert/strict";

import {ASH_A2UI_CATALOG_ID} from "../../priv/js/ash_a2ui_protocol.js";
import {click, mountHook, sent, tick} from "./harness.mjs";
import {acceptsEnvelopeKeys, readJson, webCoreVersion} from "./support.mjs";

const skip = acceptsEnvelopeKeys()
  ? false
  : `@a2ui/web_core ${webCoreVersion} rejects the @-prefixed component envelope keys of spec HEAD`;

function buttonsOf(message) {
  const body = message.createSurface || message.updateComponents;
  return (body && body.components ? body.components : []).filter((c) => c.component === "Button");
}

for (const name of ["table", "form", "board", "wizard"]) {
  test(`the ${name} fixture applies and its buttons reach the agent`, {skip}, async () => {
    const messages = readJson(`test/fixtures/v1_0_contract/${name}.json`);
    const hook = mountHook({actionTimeoutMs: 0});

    for (const message of messages) {
      const surfaceId = Object.values(message).find((body) => body && body.surfaceId)?.surfaceId;
      hook.processMessages([message]);
      assert.deepEqual(sent(hook), [], `${name}: ${Object.keys(message).join(",")} applies`);

      if (!hook.processor.getSurface(surfaceId)) continue;
      const surface = hook.processor.getSurface(surfaceId);

      for (const button of buttonsOf(message)) {
        if (!surface.componentsModel.get(button.id)) continue;
        hook.pushed.length = 0;
        void click(hook, surfaceId, button.id);
        await tick();

        const [out] = sent(hook);
        assert.equal(
          out?.callAgentFunction?.callFunction?.["@call"],
          "ashAction",
          `${name}: ${button.id} calls ashAction`,
        );
        assert.equal(out.callAgentFunction.callFunction.catalogId, ASH_A2UI_CATALOG_ID);
        assert.equal(out.callAgentFunction.surfaceId, surfaceId);
        assert.equal(out.callAgentFunction.callFunction.args.sourceComponentId, button.id);
        const {functionCallId} = out.callAgentFunction;
        hook.processMessages([{version: "1.0", agentFunctionResponse: {functionCallId, value: {}}}]);
        hook.pushed.length = 0;
      }
    }
  });
}
