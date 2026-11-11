/**
 * Pure message adaptation for the AshA2ui LiveView hook: the functions
 * that turn the server->client messages `AshA2ui.LiveRenderer` pushes
 * (the "a2ui:messages" event) into the messages the v0_9 renderer runtime
 * takes, plus the /ui/response values the hook's optimistic response path
 * writes — with no DOM or LiveView access. The hook (`ash_a2ui_hook.js`)
 * feeds pushed messages through `adaptMessage` and runs the returned side
 * effects itself, in message order. Tested with `node --test`
 * (`mix js.test`).
 *
 * See "A2UI v1.0 support" in ash_a2ui_hook.js for why v1.0 messages are
 * expanded/consumed for the v0_9 renderer.
 */

export const V1_VERSION = "v1.0";

const V1_BASIC_CATALOG_ID = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json";
const V0_BASIC_CATALOG_ID = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json";

/**
 * Maps one server->client message to the messages handed to the v0_9
 * renderer. v0.9.1 messages pass through untouched; a v1.0 `createSurface`
 * expands into the v0.9 triple, while `actionResponse` / `callFunction`
 * are consumed (the hook resolves the pending action and runs the
 * function against its registered table).
 *
 * Returns one result object per message:
 *
 *     {messages, createdSurfaceId?, actionResponse?, callFunction?, deletedSurfaceId?}
 *
 * where `messages` feed the renderer and the remaining fields tell the
 * hook which side effects to run for the message.
 */
export function adaptMessage(message, {catalogs} = {}) {
  if (!message || message.version !== V1_VERSION) return {messages: [message]};

  if (message.createSurface) return adaptV1CreateSurface(message.createSurface, catalogs);

  if (message.actionResponse) return {messages: [], actionResponse: message};

  if (message.callFunction) return {messages: [], callFunction: message};

  let deletedSurfaceId = null;
  if (message.deleteSurface && message.deleteSurface.surfaceId) {
    deletedSurfaceId = message.deleteSurface.surfaceId;
  }

  // updateComponents / updateDataModel / deleteSurface payloads are
  // shape-compatible with v0.9; the processor does not inspect `version`.
  return {messages: [message], deletedSurfaceId};
}

/**
 * Expands v1.0's inline createSurface (surface + components + dataModel
 * in one message) into the v0.9 triple the published renderer
 * understands, mapping the v1.0 basic-catalog id onto a registered
 * catalog and passing surfaceProperties through as the surface's theme
 * metadata slot. `catalogs` is the host-registered list
 * (`configureAshA2ui({catalogs})`).
 */
export function adaptV1CreateSurface(payload, catalogs) {
  const {surfaceId, catalogId, surfaceProperties, sendDataModel, components, dataModel} = payload;

  const registered = (catalogs || []).some((catalog) => catalog.id === catalogId);
  const mappedCatalogId =
    !registered && catalogId === V1_BASIC_CATALOG_ID ? V0_BASIC_CATALOG_ID : catalogId;

  const create = {surfaceId, catalogId: mappedCatalogId};
  if (surfaceProperties) create.theme = surfaceProperties;
  if (sendDataModel !== undefined) create.sendDataModel = sendDataModel;

  const messages = [{createSurface: create}];

  if (components && components.length > 0) {
    messages.push({updateComponents: {surfaceId, components}});
  }

  if (dataModel !== undefined) {
    messages.push({updateDataModel: {surfaceId, path: "/", value: dataModel}});
  }

  return {messages, createdSurfaceId: surfaceId};
}

// The panel visibility sentinel is a zero-or-one list (`[]` hidden,
// `[...]` visible — AshA2ui.Experience.sentinel/1).
function panelVisibleSentinel(value) {
  return Array.isArray(value) && value.length > 0;
}

/**
 * Extracts the panel state a server->client message carries, if any:
 * `/ui/panel` writes from the action handler, or the full data model under
 * "/" (bootstrap, data-only refreshes). Returns true | false | null
 * (message carries no panel state).
 */
export function panelStateOf(message) {
  if (!message || !message.updateDataModel) return null;
  const {path, value} = message.updateDataModel;

  if (path === "/ui/panel") {
    return panelVisibleSentinel(value && value.visible);
  }

  if (path === "/") {
    const panel = value && value.ui && value.ui.panel;
    return panel ? panelVisibleSentinel(panel.visible) : null;
  }

  return null;
}

/**
 * The /ui/response value that settles an in-flight v1.0 action with the
 * server's actionResponse payload: the error shape when the response
 * carries an error, the ok shape spreading the response's value
 * otherwise.
 */
export function settledUiResponse(response) {
  const payload = response || {};

  return payload.error
    ? {
        status: "error",
        code: payload.error.code || "",
        message: payload.error.message || "",
        result: {},
        resultText: "",
      }
    : {
        status: "ok",
        message: "",
        result: {},
        resultText: "",
        ...(payload.value || {}),
      };
}
