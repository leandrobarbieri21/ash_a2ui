// Drives the AshA2ui hook without a DOM: `start` creates the real processor,
// `this.el` is an EventTarget and `pushEvent` records what the hook sends.

import {AshA2ui, resolveDeps} from "../../priv/js/ash_a2ui_hook.js";
import {basicCatalog, webCore} from "./support.mjs";

export function mountHook(options = {}) {
  const hook = Object.create(AshA2ui);
  hook.el = new EventTarget();
  hook.surfaceEl = null;
  hook.skeletonEl = null;
  hook.pushed = [];
  hook.pushEvent = (event, payload) => hook.pushed.push({event, payload});
  hook.responses = [];
  hook.el.addEventListener("ash-a2ui:action-response", (event) =>
    hook.responses.push(event.detail),
  );

  hook.start(
    resolveDeps({
      MessageProcessor: webCore.MessageProcessor,
      Catalog: webCore.Catalog,
      catalogs: [basicCatalog],
      ...options,
    }),
  );

  return hook;
}

// The renderer-to-agent messages the hook has sent, in order.
export function sent(hook) {
  return hook.pushed.filter(({event}) => event === "a2ui:message").map(({payload}) => payload);
}

// Runs the action of component `id` the way a click does.
export async function click(hook, surfaceId, id, {path = "/", index} = {}) {
  const surface = hook.processor.getSurface(surfaceId);
  const component = surface.componentsModel.get(id);
  if (!component) throw new Error(`no component ${id} on ${surfaceId}`);
  const api =
    component.catalog?.components.get(component.type) ??
    surface.defaultCatalog.components.get(component.type);
  const context = new webCore.ComponentContext(surface, id, path, undefined, index);
  const binder = new webCore.GenericBinder(context, api.schema);
  const subscription = binder.subscribe(() => {});
  try {
    return await binder.snapshot.action();
  } finally {
    subscription?.unsubscribe?.();
    binder.dispose?.();
  }
}

export function feedbackOf(hook, surfaceId) {
  return hook.processor.getSurface(surfaceId).dataModel.get("/ui/feedback");
}

export const tick = () => new Promise((resolve) => setTimeout(resolve, 0));
