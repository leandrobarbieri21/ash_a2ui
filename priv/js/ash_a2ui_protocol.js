/**
 * The pure half of the AshA2ui LiveView hook: the A2UI 1.0 contract between
 * the hook and `AshA2ui.LiveRenderer`, with no DOM or LiveView access. The
 * hook (`ash_a2ui_hook.js`) runs the side effects around it. Tested with
 * `node --test` (`mix js.test`).
 *
 *   - the ash_a2ui function catalog (`ASH_A2UI_CATALOG`, the document in
 *     `priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json`) and
 *     `createAshFunctionCatalog`, which binds its functions to code;
 *   - the `/ui/feedback` map: idle, pending and slow, and the quiet actions
 *     that write none;
 *   - `replaceExistingSurfaces`, which lets a re-joined LiveView bootstrap a
 *     surface the processor still holds;
 *   - `panelStateOf`, which reads the record-task panel's visibility from a
 *     message.
 */

/** The protocol version on every message, in both directions. */
export const PROTOCOL_VERSION = "1.0";

/** The id of the ash_a2ui catalog (`AshA2ui.Encoder.ash_catalog_id/0`). */
export const ASH_A2UI_CATALOG_ID = "https://github.com/lukegalea/ash_a2ui/catalogs/ash_a2ui/v1";

/** The data-model path of the one feedback map every surface carries. */
export const FEEDBACK_PATH = "/ui/feedback";

/**
 * Where a surface keeps the words the renderer writes into the feedback map
 * itself, in the surface's language: `pending` and `slow`
 * (`AshA2ui.Experience.initial_ui_state/1`).
 */
export const FEEDBACK_TEXT_PATH = "/ui/feedback_text";

/**
 * The ash_a2ui actions that report no outcome of their own: reads,
 * searches, picker and panel steps (`AshA2ui.ActionHandler.quiet_actions/0`,
 * kept equal by the Elixir tests). An `ashAction` call to one writes no
 * pending feedback, and the agent leaves `/ui/feedback` alone unless the
 * action fails, so a page turn or a search keystroke never replaces the
 * last outcome.
 */
export const QUIET_ACTIONS = Object.freeze([
  "query",
  "option_search",
  "context_search",
  "option_select",
  "nested_add",
  "nested_remove",
  "bulk_select",
  "prompt",
  "wizard_next",
  "wizard_back",
  "open_surface",
]);

/** Whether `ashAction` args name a quiet action (see `QUIET_ACTIONS`). */
export function quietAction(args) {
  return Boolean(args) && QUIET_ACTIONS.includes(args.name);
}

/**
 * The ash_a2ui catalog document, kept equal to
 * `priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json` by the node tests. It
 * declares `ashAction` (renderer to agent: every server-handled
 * interaction) and `downloadFile` (agent to renderer: an export).
 */
export const ASH_A2UI_CATALOG = {
  $schema: "https://json-schema.org/draft/2020-12/schema",
  $id: "https://github.com/lukegalea/ash_a2ui/catalogs/ash_a2ui/v1",
  protocolVersion: "1.0",
  title: "AshA2ui Function Catalog",
  description: "The functions an AshA2ui agent and renderer share beside the basic catalog: ashAction, which a renderer calls on the agent for every server-handled interaction, and downloadFile, which the agent calls on the renderer to deliver an export. It declares no components. The shipped LiveView hook (priv/js/ash_a2ui_hook.js) registers the implementations.",
  catalogId: "https://github.com/lukegalea/ash_a2ui/catalogs/ash_a2ui/v1",
  components: {},
  functions: {
    ashAction: {
      type: "object",
      description: "Runs a named ash_a2ui action on the agent. The renderer sends it as callAgentFunction; the agent answers with agentFunctionResponse after its data-model updates.",
      returnType: "object",
      requiresUserActivation: true,
      properties: {
        "@call": {
          const: "ashAction"
        },
        args: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "The action's name (submit_form, query, invoke, ...)."
            },
            sourceComponentId: {
              type: "string",
              description: "The id of the component the interaction came from."
            },
            context: {
              type: "object",
              description: "The action's inputs. Bindings resolve against the data model before the call is sent.",
              additionalProperties: {
                $ref: "common_types.json#/$defs/DynamicValue"
              }
            }
          },
          required: [
            "name"
          ],
          unevaluatedProperties: false
        }
      },
      required: [
        "@call",
        "args"
      ]
    },
    downloadFile: {
      type: "object",
      description: "Downloads a file the agent generated: exactly one of dataUrl (an inline data: URL, how AshA2ui delivers CSV exports) or url (a signed download URL, for hosts that upload instead of inlining), saved under filename. The agent sends it as callRendererFunction after an export. This function has no return value.",
      returnType: "void",
      allowedCallers: "agentOnly",
      properties: {
        "@call": {
          const: "downloadFile"
        },
        args: {
          type: "object",
          properties: {
            filename: {
              type: "string",
              description: "The name the downloaded file is saved under."
            },
            mimeType: {
              type: "string",
              description: "The file's MIME type (informational; the URL's own type wins where applicable)."
            },
            dataUrl: {
              type: "string",
              pattern: "^data:",
              description: "The file content as a data: URL."
            },
            url: {
              type: "string",
              format: "uri",
              description: "A (signed) URL the file is downloaded from."
            }
          },
          required: [
            "filename"
          ],
          oneOf: [
            {
              required: [
                "dataUrl"
              ]
            },
            {
              required: [
                "url"
              ]
            }
          ],
          unevaluatedProperties: false
        }
      },
      required: [
        "@call",
        "args"
      ]
    }
  },
  $defs: {
    anyComponent: {
      not: {}
    },
    anyFunction: {
      oneOf: [
        {
          $ref: "#/functions/ashAction"
        },
        {
          $ref: "#/functions/downloadFile"
        }
      ]
    }
  }
};

/**
 * Builds the ash_a2ui catalog with executable functions: the schemas come
 * from `ASH_A2UI_CATALOG` through `Catalog.fromJson`, the code from
 * `implementations` (`{ashAction, downloadFile}`, each
 * `(args, dataContext) => value`). `Catalog` is the `@a2ui/web_core` class.
 */
export function createAshFunctionCatalog(Catalog, implementations) {
  const schemas = Catalog.fromJson(ASH_A2UI_CATALOG);

  const functions = [...schemas.functions.values()].map((api) => {
    const execute = implementations[api.name];
    if (typeof execute !== "function") {
      throw new Error(`createAshFunctionCatalog: no implementation for ${api.name}`);
    }

    return {
      name: api.name,
      returnType: api.returnType,
      schema: api.schema,
      allowedCallers: api.allowedCallers,
      requiresUserActivation: api.requiresUserActivation,
      description: api.description,
      execute,
    };
  });

  return schemas.withEntries([], functions);
}

/**
 * The full `/ui/feedback` map. The server writes the whole map on every
 * settled action, so a stale pending entry can never survive a write.
 * `kind` is `""` (idle), `"pending"`, `"success"`, `"warning"` or
 * `"error"`; `extra` may set `code`, `functionCallId`, `result` and
 * `resultText`.
 */
export function feedback(kind = "", message = "", extra = {}) {
  return {kind, message, code: "", functionCallId: "", result: {}, resultText: "", ...extra};
}

/** The feedback written the moment an `ashAction` call goes out. */
export function pendingFeedback(message, functionCallId) {
  return feedback("pending", message, {functionCallId});
}

/**
 * The feedback written when an `ashAction` call has gone unanswered past the
 * watchdog. The agent may still be running the action, so the call stays
 * pending (`kind: "pending"`, `code: "TIMEOUT"`): busy controls stay busy
 * and nothing invites a second submit. The agent's late outcome replaces it.
 */
export function slowFeedback(message, functionCallId) {
  return feedback("pending", message, {code: "TIMEOUT", functionCallId});
}

/** The `ashAction` FunctionCall for the given args. */
export function ashActionCall(args) {
  return {"@call": "ashAction", catalogId: ASH_A2UI_CATALOG_ID, args};
}

/**
 * The `{code, message}` of a rejected agent function call. web_core rejects
 * with an `A2uiRpcError` whose `details` hold the agent's own error object;
 * its `message` carries a `[CODE]` prefix, so the details win.
 */
export function rpcError(error) {
  const details = error && error.details;
  if (details && typeof details === "object" && typeof details.code === "string") {
    return {code: details.code, message: String(details.message ?? "")};
  }

  return {
    code: (error && typeof error.code === "string" && error.code) || "UNKNOWN_ERROR",
    message: String((error && error.message) || error || ""),
  };
}

/**
 * Makes a message batch safe to feed a processor that already holds some
 * surfaces. A page that re-joins its LiveView (a dropped socket, a crashed
 * process) keeps this hook instance, and the server then bootstraps the
 * surface again: a `createSurface` for an id the processor still holds
 * would be rejected. Each such message is preceded by a `deleteSurface` for
 * the same id, so the old surface is disposed (its subscriptions released)
 * and the new one replaces it.
 *
 * `exists(surfaceId)` says whether the processor holds the surface now.
 * Ids created earlier in the same batch count as existing, and a
 * `deleteSurface` in the batch clears the id. Returns a new array; the
 * messages themselves are not modified.
 */
export function replaceExistingSurfaces(messages, exists) {
  const live = new Map();
  const isLive = (id) => (live.has(id) ? live.get(id) : Boolean(exists(id)));
  const out = [];

  for (const message of messages) {
    const created = message && message.createSurface;
    const deleted = message && message.deleteSurface;

    if (created && created.surfaceId !== undefined) {
      if (isLive(created.surfaceId)) {
        out.push({version: PROTOCOL_VERSION, deleteSurface: {surfaceId: created.surfaceId}});
      }
      live.set(created.surfaceId, true);
    } else if (deleted && deleted.surfaceId !== undefined) {
      live.set(deleted.surfaceId, false);
    }

    out.push(message);
  }

  return out;
}

// The panel visibility sentinel is a zero-or-one list (`[]` hidden,
// `[...]` visible; AshA2ui.Experience.sentinel/1).
function panelVisibleSentinel(value) {
  return Array.isArray(value) && value.length > 0;
}

function panelOfModel(model) {
  const panel = model && model.ui && model.ui.panel;
  return panel ? panelVisibleSentinel(panel.visible) : null;
}

/**
 * The record-task panel state a message carries, if any: the data model a
 * `createSurface` bootstraps, a `/ui/panel` write from the action handler,
 * or a write of the whole data model (an omitted path or `/`). Returns
 * true | false | null (the message carries no panel state).
 */
export function panelStateOf(message) {
  if (!message) return null;

  if (message.createSurface) return panelOfModel(message.createSurface.dataModel);

  if (!message.updateDataModel) return null;
  const {path, value} = message.updateDataModel;

  if (path === "/ui/panel") return panelVisibleSentinel(value && value.visible);
  if (path === undefined || path === "/" || path === "") return panelOfModel(value);

  return null;
}
