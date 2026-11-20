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
 *     message;
 *   - `liveLinkOf`, which says where a click on a live link goes.
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
  "document_pane",
  "document_region",
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

// --- Prompt pre-fill --------------------------------------------------------
//
// A row action with `prompt_fields` opens its dialog at once and asks the
// agent for the pre-fill (`prompt`), which writes the whole
// /prompt/values/<action> map (and /prompt/select/<action>, the label state
// of its searchable and scoped selects) when it lands. A person can type
// into the dialog before then. The pre-fill must not replace what they
// typed: Confirm sends /prompt/values/<action>, so an overwritten field
// would send a value the person never entered (often a blank).
//
// The hook keeps the values the dialog showed when the `prompt` call went
// out. A field whose value differs from that when the pre-fill arrives was
// edited by the person: the pre-fill write keeps the person's value, and
// that field's select state, and fills only the fields left untouched.

/** Whether two data-model values (JSON shapes) are equal. */
function sameValue(a, b) {
  if (a === b) return true;
  if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const keys = Object.keys(a);
  if (keys.length !== Object.keys(b).length) return false;
  return keys.every((key) => Object.prototype.hasOwnProperty.call(b, key) && sameValue(a[key], b[key]));
}

function plainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * The fields of a prompt's values map the person changed: those whose
 * value in `current` differs from `before` (the map when the `prompt` call
 * went out). Returns the list of field names.
 */
export function editedPromptFields(before, current) {
  const was = plainObject(before) ? before : {};
  const now = plainObject(current) ? current : {};
  const fields = new Set([...Object.keys(was), ...Object.keys(now)]);
  return [...fields].filter((field) => !sameValue(was[field], now[field]));
}

function overlay(value, kept) {
  const out = plainObject(value) ? {...value} : {};
  for (const [field, keptValue] of Object.entries(kept)) {
    if (keptValue === undefined) delete out[field];
    else out[field] = keptValue;
  }
  return out;
}

/**
 * Admin catalog 3.9: where a surface holds a person's unsaved changes to its
 * editable cards (`{<card>: {recordId, values: {<field>: value}}}`), until a
 * save bar saves or discards them.
 */
export const EDITS_PATH = "/ui/edits";

/**
 * Rewrites the writes in `messages` that would replace a surface's unsaved
 * changes so they keep them: a write of the whole data model (`/`), of
 * `/ui`, or a surface created again over one the processor holds. Only the
 * server's own write of `/ui/edits` (a save, which clears them) replaces
 * them. `editsOf(surfaceId)` returns the surface's current changes, or
 * null/undefined/{} when it has none. Returns a new array; the messages
 * themselves are not modified.
 */
export function keepUnsavedEdits(messages, editsOf) {
  const kept = new Map();
  const editsFor = (surfaceId) => {
    if (!kept.has(surfaceId)) {
      const edits = editsOf(surfaceId);
      kept.set(surfaceId, edits && typeof edits === "object" && Object.keys(edits).length > 0 ? edits : null);
    }
    return kept.get(surfaceId);
  };
  const withEdits = (model, edits) => {
    const base = model && typeof model === "object" ? model : {};
    const ui = base.ui && typeof base.ui === "object" ? base.ui : {};
    return {...base, ui: {...ui, edits}};
  };

  return messages.map((message) => {
    const update = message && message.updateDataModel;
    if (update && (update.path === "/" || update.path === "" || update.path === undefined)) {
      const edits = editsFor(update.surfaceId);
      return edits ? {...message, updateDataModel: {...update, value: withEdits(update.value, edits)}} : message;
    }
    if (update && update.path === "/ui") {
      const edits = editsFor(update.surfaceId);
      const ui = update.value && typeof update.value === "object" ? update.value : {};
      return edits ? {...message, updateDataModel: {...update, value: {...ui, edits}}} : message;
    }
    const create = message && message.createSurface;
    if (create && create.dataModel) {
      const edits = editsFor(create.surfaceId);
      return edits ? {...message, createSurface: {...create, dataModel: withEdits(create.dataModel, edits)}} : message;
    }
    return message;
  });
}

/**
 * Rewrites the pre-fill writes in `messages` so they keep what the person
 * typed. `prompts` lists the open prompts awaiting their pre-fill, each
 * `{surfaceId, action, values, selects}`: `values` maps each edited field
 * to its current value, `selects` maps each edited field to its current
 * /prompt/select state (absent when it has none). Only a write of the
 * whole `/prompt/values/<action>` or `/prompt/select/<action>` map is
 * rewritten; every other message is passed through. Returns a new array;
 * the messages themselves are not modified.
 */
export function keepPromptEdits(messages, prompts) {
  const edited = prompts.filter((prompt) => Object.keys(prompt.values).length > 0);
  if (edited.length === 0) return messages;

  return messages.map((message) => {
    const update = message && message.updateDataModel;
    if (!update) return message;

    for (const prompt of edited) {
      if (update.surfaceId !== prompt.surfaceId) continue;
      const kept =
        update.path === `/prompt/values/${prompt.action}`
          ? prompt.values
          : update.path === `/prompt/select/${prompt.action}`
            ? prompt.selects
            : null;
      if (kept) return {...message, updateDataModel: {...update, value: overlay(update.value, kept)}};
    }

    return message;
  });
}

/**
 * The attribute a renderer puts on a link the surface declared live (admin
 * catalog 3.7: a breadcrumb step's `live`). Its value is the kind:
 * `"navigate"` (`push_navigate`, another LiveView) or `"patch"`
 * (`push_patch`, this LiveView's own address). The AshA2ui hook follows a
 * plain click on it inside the LiveView, from inside any shadow root of its
 * surface; LiveView's own `data-phx-link` handler cannot see that far, as it
 * reads the click's target, which a shadow root retargets to its host.
 * Without the hook the link is a normal link.
 */
export const LIVE_LINK_ATTRIBUTE = "data-a2ui-live";

/** The kinds a live link may name (`LIVE_LINK_ATTRIBUTE`'s values). */
export const LIVE_LINK_KINDS = Object.freeze(["navigate", "patch"]);

/**
 * Where a click on a live link goes inside the LiveView: `{kind, href}`
 * (`href` absolute), or null when the browser should follow the link
 * itself.
 *
 * `click` is the click event (or its `button`, modifier keys and
 * `defaultPrevented`), `path` its `composedPath()`, innermost first, and
 * `container` the hook's element: the search for the nearest element
 * carrying `LIVE_LINK_ATTRIBUTE` stops there. `location` is the page's
 * (`origin` and `href`). The link's address is its `href` property when it
 * has a string one (an anchor's, or a custom element's that resolves it),
 * else its `href` attribute.
 *
 * Null for a modified, middle or already handled click; for a link with a
 * `target` other than `_self` or a `download`; for an unknown kind, no
 * address, or an address on another origin.
 */
export function liveLinkOf(click, path, {container, location} = {}) {
  if (!click || click.defaultPrevented) return null;
  if (click.button > 0 || click.metaKey || click.ctrlKey || click.shiftKey || click.altKey) {
    return null;
  }
  if (!location || typeof location.origin !== "string") return null;

  for (const node of path || []) {
    if (node === container) return null;
    if (!node || typeof node.getAttribute !== "function") continue;
    const kind = node.getAttribute(LIVE_LINK_ATTRIBUTE);
    if (kind === null || kind === undefined) continue;
    if (!LIVE_LINK_KINDS.includes(kind)) return null;

    const target = node.getAttribute("target");
    if ((target && target !== "_self") || node.getAttribute("download") !== null) return null;

    const href = typeof node.href === "string" && node.href !== "" ? node.href : node.getAttribute("href");
    if (!href) return null;
    let url;
    try {
      url = new URL(href, location.href || location.origin);
    } catch {
      return null;
    }
    return url.origin === location.origin ? {kind, href: url.href} : null;
  }
  return null;
}
