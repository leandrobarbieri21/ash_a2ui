/**
 * AshA2ui LiveView JS hook.
 *
 * Hosts an `<a2ui-surface>` element (from `@a2ui/lit`) inside the LiveView
 * container and runs an A2UI 1.0 `MessageProcessor` (from `@a2ui/web_core`)
 * for it:
 *
 *   - the agent-to-renderer messages `AshA2ui.LiveRenderer` pushes as the
 *     "a2ui:messages" event go to `processor.processMessagesWithErrors`;
 *   - every renderer-to-agent message goes back, verbatim, as the single
 *     LiveView event "a2ui:message": a `callAgentFunction` (an
 *     `ashAction` call), a
 *     `rendererFunctionResponse` (the answer to a `callRendererFunction`)
 *     or an `error` (each message the processor could not apply).
 *
 * ## Action feedback: `ashAction`
 *
 * Every server-handled interaction is a function-call action against the
 * ash_a2ui catalog (`{"functionCall": {"@call": "ashAction", "catalogId":
 * ..., "args": {name, sourceComponentId, context}}}`). The hook registers
 * that catalog beside the host's catalogs, and its `ashAction`:
 *
 *   1. writes `{kind: "pending", message, functionCallId}` to the surface's
 *      `/ui/feedback` at once, so bound status components show feedback at
 *      0 RTT. The message is the surface's `/ui/feedback_text/pending` (in
 *      its own language), else `pendingMessage`. A quiet action
 *      (`QUIET_ACTIONS`: reads, searches, picker and panel steps) writes
 *      nothing here or in step 3, so a page turn or a search keystroke
 *      leaves the last outcome on screen;
 *   2. sends the call as `callAgentFunction` with that `functionCallId`;
 *   3. waits for the agent's `agentFunctionResponse`, which arrives last in
 *      the agent's batch, after the data-model writes (the settled
 *      `/ui/feedback` among them). If none arrives within `actionTimeoutMs`
 *      and `/ui/feedback` still belongs to this call, it writes the slow
 *      notice there: still `kind: "pending"`, `code: "TIMEOUT"`, the
 *      surface's `/ui/feedback_text/slow`. The agent may still be running
 *      the action, so busy controls stay busy until its outcome lands;
 *   4. dispatches the bubbling `"ash-a2ui:action-response"` CustomEvent on
 *      the container, `detail = {functionCallId, surfaceId, response}`,
 *      where `response` is `{value}` or `{error: {code, message}}`.
 *
 * A `query` or `report` call also sets the surface's reserved `/ui/loading`
 * flag (and `/ui/loading_visible`, see `AshA2ui.Loading`) while any such
 * call is unanswered, so an empty table or report reads as "rows on the
 * way" rather than "no rows".
 *
 * ## Renderer functions
 *
 * A `callRendererFunction` runs a catalog function the agent may call
 * (`allowedCallers` `agentOnly` or `rendererOrAgent`), and the processor
 * sends its `rendererFunctionResponse`. The ash_a2ui catalog's
 * `downloadFile` is one: the agent sends it after an export. A host that
 * needs more renderer functions declares them in a catalog of its own.
 *
 * ## Reference links: `openSurface`
 *
 * Activating a reference link (admin catalog DataGrid link cells and
 * FieldDisplay links, or the admin catalog's `openSurface` function) raises
 * the bubbling, composed `"ash-a2ui:open-surface"` DOM event with
 * `detail = {surface, recordId?, query?, href?, surfaceId}`. The hook
 * catches it for its own surface and pushes the `"a2ui:open_surface"`
 * LiveView event with `{surface, recordId, query}`; `AshA2ui.LiveRenderer`
 * navigates to the configured `open_surface_url` by default. Hosts that
 * want to handle it client-side pass
 * `configureAshA2ui({openSurface: (args, {surfaceId, href}) => ...})`.
 *
 * ## Contract with the host bundle
 *
 * This file ships without dependencies: importing `@a2ui/lit` /
 * `@a2ui/web_core` is left to the host app bundle, which must:
 *
 *   1. Import `@a2ui/lit`, which registers the `<a2ui-surface>` element.
 *   2. Hand the renderer classes to this hook before `LiveSocket` mounts it:
 *
 *          import "@a2ui/lit";
 *          import {Catalog, MessageProcessor} from "@a2ui/web_core";
 *          import {basicCatalog} from "@a2ui/web_core/catalogs/basic/v1";
 *          import {AshA2ui, configureAshA2ui} from "ash_a2ui/priv/js/ash_a2ui_hook.js";
 *
 *          configureAshA2ui({MessageProcessor, Catalog, catalogs: [basicCatalog]});
 *          const liveSocket = new LiveSocket("/live", Socket, {hooks: {AshA2ui}});
 *
 * Optional extras shipped alongside this hook (see the Theming topic):
 *
 *   - `ash_a2ui_theme.css`: a neutral `--a2ui-*` CSS-variable theme for
 *     the basic catalog; import it into your app CSS and override tokens.
 *   - `ash_a2ui_catalog.js`: `createAshA2uiCatalog(deps)` builds the basic
 *     catalog with AshA2ui's element overrides (see its docs).
 *   - `ash_admin_catalog.js`: `createAshAdminCatalog(deps)` builds the admin
 *     catalog.
 *   - `configureAshA2ui({..., markdown})`: wires a markdown renderer so
 *     Text headings render as headings instead of literal `##` markdown
 *     (see the configureAshA2ui docs below).
 *
 * Written against the runtime API of `@a2ui/lit` / `@a2ui/web_core` 0.15.0
 * (the version `mix js.test` pins): message ingest is
 * `new MessageProcessor(catalogs, actionHandler, {outboundListener})` plus
 * `processor.processMessagesWithErrors(messages)`; the `<a2ui-surface>`
 * element takes a `SurfaceModel` through its `surface` property, delivered
 * by `processor.onSurfaceCreated(cb)`; `processor.callAgentFunction(surfaceId,
 * call, {functionCallId, timeoutMs})` sends `callAgentFunction` through the
 * `outboundListener` and settles on the matching `agentFunctionResponse`.
 * 0.15.0 predates the spec's `@`-prefixed component envelope keys
 * (`@checks`, `@accessibility`, `@catalogId`): it refuses a surface whose
 * components carry them, which AshA2ui emits for form checks, accessible
 * labels and mixed catalogs. Rendering every AshA2ui surface needs the
 * first `@a2ui/web_core` release after 0.15.0.
 *
 * ## Zero jank: bootstrap skeleton and panel reveal
 *
 * Between the LiveView mount and the first component tree there is nothing
 * to show, so `mounted()` immediately renders a lightweight skeleton
 * (heading bar + row bars) inside the hook container, styled only with the
 * `--a2ui-*` custom properties (hosts theme it with everything else). The
 * skeleton is removed the moment the first surface render lands; the
 * removal waits for the surface element's first update (Lit
 * `updateComplete`) so there is no blank frame between the two. On a
 * LiveView reconnect the hook remounts and the skeleton reappears until the
 * fresh bootstrap hydrates: a torn-down surface never shows stale content
 * dressed up as live data.
 *
 * When a record-task panel opens (`start_create` / `view_record` /
 * `start_edit` flip `/ui/panel/visible`), the hook scrolls the panel into
 * view and focuses its first field, client-side, with no roundtrip. The
 * admin catalog's `recordPanel` manages its own focus; the reveal stays out
 * of the way when focus has already moved inside the panel.
 *
 * ## More than one surface on a page
 *
 * LiveView delivers every `push_event` to every hook on the page (nested
 * LiveViews included), so each hook decides which `"a2ui:messages"` it
 * takes (`acceptsMessage` below):
 *
 *   - a container with `data-a2ui-surface="<id>"` is scoped: it takes only
 *     messages addressed to that surface id (`createSurface`,
 *     `updateComponents`, `updateDataModel`, `deleteSurface`, and a
 *     `callRendererFunction` that names a `surfaceId`) and renders only
 *     that surface;
 *   - an unscoped container (no `data-a2ui-surface`) takes every addressed
 *     message except those for a surface a scoped hook on the page claims;
 *   - an `agentFunctionResponse` goes to the hook that sent the
 *     `callAgentFunction` with its `functionCallId`;
 *   - messages naming no surface (a `callRendererFunction` without a
 *     `surfaceId`, and an `agentFunctionResponse` no hook sent) go to the
 *     primary hook: the ones marked `data-a2ui-primary`, else the unscoped
 *     ones, else the first mounted.
 *
 * With no `data-a2ui-surface` and no `data-a2ui-primary` anywhere on the
 * page every hook takes every message, as before. An unscoped hook still
 * binds the last surface its processor creates to its `<a2ui-surface>`.
 *
 * The pure half of this work lives in `ash_a2ui_protocol.js` (tested with
 * `node --test`, `mix js.test`); this file runs the side effects around it.
 */

import {
  FEEDBACK_PATH,
  FEEDBACK_TEXT_PATH,
  PROTOCOL_VERSION,
  ashActionCall,
  createAshFunctionCatalog,
  panelStateOf,
  pendingFeedback,
  quietAction,
  replaceExistingSurfaces,
  rpcError,
  slowFeedback,
} from "./ash_a2ui_protocol.js";

// The ash_a2ui actions that fetch the data a surface shows: the hook marks
// the surface loading (AshA2ui.Loading) from the call until the agent
// answers it.
const FETCH_ACTIONS = new Set(["query", "report"]);

let hookDeps = null;

/**
 * Registers the renderer classes the hook needs. Call once from the host
 * bundle before the LiveSocket mounts any AshA2ui hook.
 *
 * `markdown` is optional but strongly recommended: without a markdown
 * renderer the basic catalog's Text component prints headings as literal
 * markdown (`## Title`). Pass the three pieces and the hook wires them up
 * with a Lit context provider on the hook element:
 *
 *     import {ContextProvider} from "@lit/context";
 *     import {Context} from "@a2ui/web_core/catalogs/basic/v1";
 *     import {renderMarkdown} from "@a2ui/markdown-it";
 *
 *     configureAshA2ui({
 *       MessageProcessor,
 *       Catalog,
 *       catalogs: [catalog],
 *       markdown: {ContextProvider, context: Context.markdown, render: renderMarkdown},
 *     });
 *
 * (`ContextProvider` attaches its `context-request` listeners directly to
 * the host element, so a plain hook container works as the provider host.)
 *
 * @param {{
 *   MessageProcessor: Function,
 *   Catalog: Function,
 *   catalogs: Array<object>,
 *   markdown?: {ContextProvider: Function, context: object, render: Function},
 *   openSurface?: Function,
 *   pendingMessage?: string,
 *   slowMessage?: string,
 *   actionTimeoutMs?: number,
 * }} deps
 *   `Catalog`: the `@a2ui/web_core` class the hook builds the ash_a2ui
 *   function catalog with. `pendingMessage` and `slowMessage`: the
 *   optimistic `/ui/feedback` messages for a surface whose data model has no
 *   `/ui/feedback_text` (an AshA2ui surface carries them in its own
 *   language): shown while an `ashAction` call is in flight, and once it
 *   has gone unanswered past `actionTimeoutMs`. `actionTimeoutMs`: how long
 *   an `ashAction` call waits for its `agentFunctionResponse` before the
 *   slow notice shows (default 10000; 0 waits without one).
 *   `openSurface`: `(args, {surfaceId, href}) => void`, to handle
 *   reference-link navigation client-side instead of pushing the
 *   `"a2ui:open_surface"` LiveView event.
 */
export function configureAshA2ui(deps) {
  hookDeps = deps;
}

/**
 * The deps the hook runs with: `deps`, or what `configureAshA2ui` (or the
 * `globalThis.__ASH_A2UI_DEPS__` fallback) registered, with defaults filled
 * in.
 */
export function resolveDeps(deps = hookDeps || globalThis.__ASH_A2UI_DEPS__) {
  if (!deps || typeof deps.MessageProcessor !== "function" || typeof deps.Catalog !== "function") {
    throw new Error(
      "AshA2ui hook: missing @a2ui renderer classes. Call " +
        "configureAshA2ui({MessageProcessor, Catalog, catalogs}) from your app bundle " +
        "(or set globalThis.__ASH_A2UI_DEPS__) before mounting the LiveSocket.",
    );
  }

  return {
    MessageProcessor: deps.MessageProcessor,
    Catalog: deps.Catalog,
    catalogs: deps.catalogs || [],
    markdown: deps.markdown || null,
    pendingMessage: deps.pendingMessage || "Working…",
    slowMessage: deps.slowMessage || "This is taking longer than usual. Still working…",
    openSurface: typeof deps.openSurface === "function" ? deps.openSurface : null,
    actionTimeoutMs: deps.actionTimeoutMs === undefined ? 10000 : deps.actionTimeoutMs,
  };
}

const OPEN_SURFACE_EVENT = "ash-a2ui:open-surface";
const ACTION_RESPONSE_EVENT = "ash-a2ui:action-response";

function randomCallId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }
  return `a2ui-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

// The ash_a2ui catalog's downloadFile (agent only): `dataUrl` (a data: URL,
// how AshA2ui delivers CSV exports) or `url` (a signed download URL, for
// hosts that upload instead of inlining), downloaded under `filename` via a
// transient anchor click. See AshA2ui.Export.
function downloadFile(args) {
  const href = args && (typeof args.dataUrl === "string" ? args.dataUrl : args.url);
  if (typeof href !== "string" || typeof document === "undefined") return undefined;
  const anchor = document.createElement("a");
  anchor.href = href;
  anchor.download = (args && args.filename) || "download";
  anchor.rel = "noopener";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  return undefined;
}

// --- zero-jank: bootstrap skeleton -------------------------------------------

// Rendered inside the hook container the moment the hook attaches (the gap
// between LiveView mount and the first component tree otherwise shows a
// blank rectangle). Colors, radii, spacing, and shadows come only from the
// `--a2ui-*` custom properties, so hosts theme the skeleton along with the
// surfaces; the fallbacks keep it legible before any theme loads.
const SKELETON_MARKUP = `
<style>
  .ash-a2ui-skeleton {
    box-sizing: border-box;
    max-width: 42rem;
    padding: var(--a2ui-card-padding, 1rem);
    background: var(--a2ui-color-surface, transparent);
    border: 1px solid var(--a2ui-color-border, transparent);
    border-radius: var(--a2ui-card-border-radius, 0.75rem);
    box-shadow: var(--a2ui-card-box-shadow, none);
    display: flex;
    flex-direction: column;
    gap: var(--a2ui-list-gap, 0.75rem);
  }
  .ash-a2ui-skeleton__bar {
    height: 0.875rem;
    border-radius: var(--a2ui-border-radius, 0.5rem);
    background-color: var(--a2ui-color-secondary, rgba(148, 163, 184, 0.25));
    background-image: linear-gradient(
      90deg,
      transparent 0%,
      color-mix(in srgb, var(--a2ui-color-surface, #ffffff) 65%, transparent) 50%,
      transparent 100%
    );
    background-size: 200% 100%;
    background-repeat: no-repeat;
    animation: ash-a2ui-skeleton-shimmer 1.4s ease-in-out infinite;
  }
  .ash-a2ui-skeleton__bar--heading {
    height: 1.375rem;
    width: 38%;
    background-color: var(--a2ui-color-secondary, rgba(148, 163, 184, 0.4));
  }
  .ash-a2ui-skeleton__bar--short {
    width: 62%;
  }
  @keyframes ash-a2ui-skeleton-shimmer {
    from { background-position: 200% 0; }
    to { background-position: -200% 0; }
  }
  @media (prefers-reduced-motion: reduce) {
    .ash-a2ui-skeleton__bar { animation: none; }
  }
</style>
<div class="ash-a2ui-skeleton" role="status" aria-busy="true" aria-label="Loading surface">
  <div class="ash-a2ui-skeleton__bar ash-a2ui-skeleton__bar--heading"></div>
  <div class="ash-a2ui-skeleton__bar"></div>
  <div class="ash-a2ui-skeleton__bar ash-a2ui-skeleton__bar--short"></div>
  <div class="ash-a2ui-skeleton__bar"></div>
  <div class="ash-a2ui-skeleton__bar ash-a2ui-skeleton__bar--short"></div>
</div>
`;

// --- zero-jank: shadow-piercing DOM helpers ----------------------------------

// querySelector stops at shadow boundaries; the surface tree is a stack of
// them, so the panel reveal walks every shadowRoot recursively.
function queryDeep(root, selector) {
  const search = (node) => {
    if (!node || typeof node.querySelector !== "function") return null;
    try {
      const direct = node.querySelector(selector);
      if (direct) return direct;
    } catch {
      return null;
    }
    const scopes = [...(node.children || [])];
    if (node.shadowRoot) scopes.push(node.shadowRoot);
    for (const scope of scopes) {
      const hit = search(scope);
      if (hit) return hit;
    }
    return null;
  };
  return search(root);
}

function laidOut(element) {
  try {
    return element.getBoundingClientRect().height > 0;
  } catch {
    return false;
  }
}

function firstFieldDeep(root) {
  const field =
    queryDeep(
      root,
      "input:not([type=hidden]):not([disabled]), select:not([disabled]), textarea:not([disabled])",
    ) ||
    queryDeep(root, "button:not([disabled]), a[href], [tabindex]:not([tabindex='-1'])");
  return field;
}

// Whether the composed active element (through nested shadow roots) is
// already inside `panel` — the signal that another component (the admin
// recordPanel) owns focus for this reveal.
function activeInside(panel) {
  let active = document.activeElement;
  while (active) {
    if (containsAcrossRoots(panel, active)) return true;
    const next = active.shadowRoot && active.shadowRoot.activeElement;
    if (!next || next === active) return false;
    active = next;
  }
  return false;
}

function containsAcrossRoots(ancestor, node) {
  let current = node;
  while (current) {
    if (current === ancestor) return true;
    if (current.host) {
      current = current.host;
      continue;
    }
    current = current.parentNode;
  }
  return false;
}

// --- zero-jank: record-task panel state --------------------------------------

const PANEL_IDS = ["record_panel", "form_slot", "form"];

// --- more than one surface: message routing ----------------------------------

// Every mounted AshA2ui hook on the page. LiveView sends a push_event to all
// of them, so each one checks its peers before taking a message.
const mountedHooks = new Set();

// Each push's messages -> the hooks that take each message, routed once per
// push (see receiveMessages).
const pushRoutes = new WeakMap();

const ADDRESSED_KINDS = [
  "createSurface",
  "updateComponents",
  "updateDataModel",
  "deleteSurface",
  "callRendererFunction",
];

/**
 * The surface id an agent-to-renderer message is addressed to
 * (`message.<kind>.surfaceId`), or `undefined` for one that names no
 * surface: an `agentFunctionResponse`, or a `callRendererFunction` without
 * a `surfaceId`.
 */
export function addressedSurfaceId(message) {
  if (!message) return undefined;
  for (const kind of ADDRESSED_KINDS) {
    const payload = message[kind];
    if (payload && payload.surfaceId !== undefined) return payload.surfaceId;
  }
  return undefined;
}

// The functionCallId an agentFunctionResponse answers, else undefined.
function respondedCallId(message) {
  const response = message && message.agentFunctionResponse;
  return response && response.functionCallId !== undefined ? response.functionCallId : undefined;
}

function isPrimary(hook, hooks) {
  if (hooks.some((peer) => peer.primary)) return Boolean(hook.primary);
  if (hooks.some((peer) => !peer.scopedSurface)) return !hook.scopedSurface;
  return hooks[0] === hook;
}

/**
 * Whether `hook` takes `message`, given every hook mounted on the page
 * (`hooks`, `hook` among them, in mount order). Reads only each hook's
 * `scopedSurface` (its `data-a2ui-surface`, or null), `primary` (its
 * `data-a2ui-primary`) and `pendingCalls` (the `functionCallId`s of the
 * `callAgentFunction`s it sent and has not had answered).
 *
 *   - Addressed to a surface: a scoped hook takes it when the id is its own;
 *     an unscoped hook takes it unless a scoped hook claims that id.
 *   - `agentFunctionResponse`: the hook that sent its `functionCallId` takes
 *     it; when none did, it is unaddressed.
 *   - Unaddressed: the primary hook takes it — those marked primary, else
 *     the unscoped ones, else the first mounted.
 *
 * With no scoped and no primary hook on the page, every hook takes every
 * message (the single-surface behaviour).
 */
export function acceptsMessage(message, hook, hooks) {
  if (!hooks.some((peer) => peer.scopedSurface || peer.primary)) return true;

  const surfaceId = addressedSurfaceId(message);

  if (surfaceId !== undefined) {
    if (hook.scopedSurface) return surfaceId === hook.scopedSurface;
    return !hooks.some((peer) => peer.scopedSurface === surfaceId);
  }

  const callId = respondedCallId(message);
  if (callId !== undefined) {
    const holder = hooks.find((peer) => peer.pendingCalls && peer.pendingCalls.has(callId));
    if (holder) return holder === hook;
  }

  return isPrimary(hook, hooks);
}

export const AshA2ui = {
  mounted() {
    const deps = resolveDeps();

    // More than one surface on a page: which surface this container renders
    // (null renders whatever its processor creates) and whether it takes
    // the messages that name no surface. See acceptsMessage.
    this.scopedSurface = this.el.dataset.a2uiSurface || null;
    this.primary = this.el.dataset.a2uiPrimary !== undefined;

    // Zero-jank state: the bootstrap skeleton, and whether the record-task
    // panel is currently open (reveal fires on the hidden -> visible flip
    // only; background refreshes must not yank scroll/focus).
    this.skeletonEl = null;
    this.renderSkeleton();

    // Provide the markdown renderer to Text components (which consume the
    // `Context.markdown` Lit context) from the hook container, an ancestor
    // of every rendered component. The renderer contract is
    // `(value, options) => Promise<string>`; wrap sync renderers so both
    // shapes work.
    const {markdown} = deps;
    if (markdown && markdown.ContextProvider && markdown.context && markdown.render) {
      this.markdownProvider = new markdown.ContextProvider(this.el, {
        context: markdown.context,
        initialValue: (value, options) => Promise.resolve(markdown.render(value, options)),
      });
    }

    this.surfaceEl = document.createElement("a2ui-surface");
    this.el.appendChild(this.surfaceEl);

    // Reference links: element-raised requests bubble (composed) through
    // this container; catalog-function requests are raised on window with
    // the surface id, and are accepted only for surfaces this hook renders.
    this.onOpenSurface = (event) => {
      const detail = event.detail || {};
      const ours = event.composedPath().includes(this.el) || this.surfaceIds.has(detail.surfaceId);
      if (!ours || event.__ashA2uiHandled) return;
      event.__ashA2uiHandled = true;
      this.openSurface(detail);
    };
    window.addEventListener(OPEN_SURFACE_EVENT, this.onOpenSurface);

    this.start(deps);

    mountedHooks.add(this);
    this.handleEvent("a2ui:messages", ({messages}) => {
      this.receiveMessages(messages || []);
    });
  },

  destroyed() {
    mountedHooks.delete(this);
    if (this.onOpenSurface) window.removeEventListener(OPEN_SURFACE_EVENT, this.onOpenSurface);

    if (this.surfaceSubscription && typeof this.surfaceSubscription.unsubscribe === "function") {
      this.surfaceSubscription.unsubscribe();
    }
    if (this.errorSubscription && typeof this.errorSubscription.unsubscribe === "function") {
      this.errorSubscription.unsubscribe();
    }

    // Rejects the in-flight ashAction calls (CANCELLED) and disposes the
    // surfaces.
    if (this.processor && typeof this.processor.dispose === "function") this.processor.dispose();

    if (this.skeletonEl && this.skeletonEl.parentNode) {
      this.skeletonEl.parentNode.removeChild(this.skeletonEl);
    }
    this.skeletonEl = null;

    if (this.surfaceEl && this.surfaceEl.parentNode) {
      this.surfaceEl.parentNode.removeChild(this.surfaceEl);
    }

    this.processor = null;
    this.surfaceEl = null;
    // The ContextProvider's listeners are attached to this.el, which the
    // LiveView is discarding; dropping the reference is enough.
    this.markdownProvider = null;
  },

  /**
   * Creates the processor: the host's catalogs plus the ash_a2ui function
   * catalog bound to this hook. Needs no DOM beyond `this.el` (an
   * EventTarget) and `this.pushEvent`.
   */
  start(deps) {
    this.deps = deps;
    this.surfaceIds = new Set();
    this.panelVisible = false;
    // The functionCallIds of the ashAction calls this hook sent and has not
    // had answered: their agentFunctionResponse is routed here.
    this.pendingCalls = new Set();

    const ashCatalog = createAshFunctionCatalog(deps.Catalog, {
      ashAction: (args, context) => this.runAshAction(args, context),
      downloadFile,
    });

    // Every server-handled control is an ashAction call. An event action
    // (none of the encoder's surfaces has one) is not sent: the agent
    // refuses them.
    this.processor = new deps.MessageProcessor(
      [...deps.catalogs, ashCatalog],
      (action) =>
        console.warn("AshA2ui hook: event actions are not sent; use ashAction", action && action.name),
      {outboundListener: (message) => this.send(message)},
    );

    // The surface element renders a SurfaceModel; hand it the model as soon
    // as the processor creates it.
    this.surfaceSubscription = this.processor.onSurfaceCreated((surface) => this.adoptSurface(surface));

    // Errors raised while a surface runs (a binding that fails, a function
    // a surface cannot resolve) go to the console. The errors of messages
    // the processor could not apply are sent to the agent instead.
    this.applying = false;
    if (this.processor.model && this.processor.model.onError) {
      this.errorSubscription = this.processor.model.onError.subscribe((error) => {
        if (!this.applying) console.warn("AshA2ui hook: renderer error", error);
      });
    }
  },

  /**
   * Binds a surface the processor created to this container's
   * `<a2ui-surface>` element. A scoped container binds only its own
   * surface; an unscoped one binds the last created.
   */
  adoptSurface(surface) {
    if (this.scopedSurface && !(surface && surface.id === this.scopedSurface)) return;
    if (surface && surface.id) this.surfaceIds.add(surface.id);
    if (this.surfaceEl) this.surfaceEl.surface = surface;
    this.dismissSkeleton();
  },

  /**
   * Takes the messages of one `"a2ui:messages"` push that are this hook's
   * (see acceptsMessage) and processes them. `hooks` defaults to every
   * AshA2ui hook mounted on the page.
   *
   * Every hook receives the same push object in turn, and processing it
   * changes the state routing reads (an answered call leaves
   * `pendingCalls`). So the first hook to see a push routes all of it, and
   * the others read that route.
   */
  receiveMessages(messages, hooks = [...mountedHooks]) {
    let route = pushRoutes.get(messages);
    if (!route) {
      const peers = hooks.includes(this) ? hooks : [...hooks, this];
      route = messages.map((message) => peers.filter((hook) => acceptsMessage(message, hook, peers)));
      pushRoutes.set(messages, route);
    }
    this.processMessages(messages.filter((_message, index) => route[index].includes(this)));
  },

  /** Pushes one renderer-to-agent message to the LiveView. */
  send(message) {
    this.pushEvent("a2ui:message", message);
  },

  /**
   * Feeds pushed agent-to-renderer messages into the processor and sends
   * the agent an `error` message for each message it could not apply.
   */
  processMessages(messages) {
    if (!this.processor) return;

    const batch = replaceExistingSurfaces(messages, (id) => this.surfaceExists(id));
    for (const error of this.apply(batch)) this.send(error);

    // An answered call no longer routes its (late or repeated) responses here.
    for (const message of batch) {
      const callId = respondedCallId(message);
      if (callId !== undefined && this.pendingCalls) this.pendingCalls.delete(callId);
    }

    // Belt and braces for the skeleton: onSurfaceCreated dismisses it.
    if (this.skeletonEl && batch.some((message) => message && message.createSurface)) {
      this.dismissSkeleton();
    }

    // Zero-jank panel reveal: only on the hidden -> visible flip, so
    // background data refreshes never yank scroll or focus.
    for (const message of batch) {
      const visible = panelStateOf(message);
      if (visible === null) continue;
      const wasVisible = this.panelVisible;
      this.panelVisible = visible;
      if (visible && !wasVisible) this.schedulePanelReveal();
    }
  },

  /** Applies messages, returning the `error` message of each it could not. */
  apply(messages) {
    this.applying = true;
    try {
      return this.processor.processMessagesWithErrors(messages);
    } finally {
      this.applying = false;
    }
  },

  /**
   * The ash_a2ui catalog's `ashAction`: see "Action feedback" above.
   * Resolves to the agent's value, or to undefined when the call failed.
   */
  async runAshAction(args, context) {
    const surfaceId = context && context.surface && context.surface.id;
    const functionCallId = randomCallId();
    const quiet = quietAction(args);
    const fetches = Boolean(args) && FETCH_ACTIONS.has(args.name);

    if (fetches) this.trackFetch(surfaceId, functionCallId, true);
    if (!quiet) {
      this.writeFeedback(
        surfaceId,
        pendingFeedback(this.feedbackText(surfaceId, "pending"), functionCallId),
      );
    }

    this.pendingCalls.add(functionCallId);

    let response;
    try {
      const value = await this.processor.callAgentFunction(surfaceId, ashActionCall(args), {
        functionCallId,
        timeoutMs: this.deps.actionTimeoutMs,
      });
      response = {value};
    } catch (error) {
      response = {error: rpcError(error)};
      // Any other failure was answered by the agent, whose batch already
      // wrote /ui/feedback. A later action owning the feedback keeps it,
      // and a quiet call never owns it.
      if (response.error.code === "TIMEOUT" && this.feedbackCallId(surfaceId) === functionCallId) {
        this.writeFeedback(
          surfaceId,
          slowFeedback(this.feedbackText(surfaceId, "slow"), functionCallId),
        );
      }
    }

    if (fetches) this.trackFetch(surfaceId, functionCallId, false);

    if (this.el && typeof this.el.dispatchEvent === "function") {
      this.el.dispatchEvent(
        new CustomEvent(ACTION_RESPONSE_EVENT, {
          bubbles: true,
          detail: {functionCallId, surfaceId, response},
        }),
      );
    }

    return response.value;
  },

  /**
   * Counts the surface's data fetches in flight and writes the reserved
   * `/ui/loading` flag (and its `/ui/loading_visible` zero-or-one list, see
   * `AshA2ui.Loading`) when the first starts and the last is answered or
   * times out, so an earlier answer never hides a later fetch's loading row.
   */
  trackFetch(surfaceId, functionCallId, started) {
    if (!this.fetching) this.fetching = new Map();
    const calls = this.fetching.get(surfaceId) || new Set();
    const before = calls.size;
    if (started) calls.add(functionCallId);
    else calls.delete(functionCallId);
    this.fetching.set(surfaceId, calls);
    if ((before === 0) !== (calls.size === 0)) this.writeLoading(surfaceId, calls.size > 0);
  },

  /** Writes the reserved `/ui/loading` flag and `/ui/loading_visible` list. */
  writeLoading(surfaceId, loading) {
    if (!this.processor || !this.surfaceExists(surfaceId)) return;
    this.apply([
      {version: PROTOCOL_VERSION, updateDataModel: {surfaceId, path: "/ui/loading", value: loading}},
      {
        version: PROTOCOL_VERSION,
        updateDataModel: {surfaceId, path: "/ui/loading_visible", value: loading ? [{id: "on"}] : []},
      },
    ]);
  },

  /**
   * Writes the surface's `/ui/feedback` map locally, through the
   * renderer's own data model: the 0-RTT pending and timeout states.
   */
  writeFeedback(surfaceId, value) {
    if (!this.processor || !this.surfaceExists(surfaceId)) return;
    this.apply([{version: PROTOCOL_VERSION, updateDataModel: {surfaceId, path: FEEDBACK_PATH, value}}]);
  },

  /**
   * The surface's own words for a feedback state the hook writes (`pending`
   * or `slow`, under `/ui/feedback_text`), else the configured default.
   */
  feedbackText(surfaceId, key) {
    const surface = this.processor && this.processor.getSurface(surfaceId);
    const text = surface ? surface.dataModel.get(`${FEEDBACK_TEXT_PATH}/${key}`) : undefined;
    if (typeof text === "string" && text !== "") return text;
    return key === "slow" ? this.deps.slowMessage : this.deps.pendingMessage;
  },

  /** The `functionCallId` the surface's `/ui/feedback` belongs to. */
  feedbackCallId(surfaceId) {
    const surface = this.processor && this.processor.getSurface(surfaceId);
    return surface ? surface.dataModel.get(`${FEEDBACK_PATH}/functionCallId`) : undefined;
  },

  /**
   * Removes the bootstrap skeleton once the first component tree is on
   * screen: wait for the surface element's first update (Lit
   * `updateComplete`) so no blank frame appears between skeleton and tree,
   * falling back to the next frame for renderers without that API.
   */
  dismissSkeleton() {
    const skeleton = this.skeletonEl;
    if (!skeleton) return;
    this.skeletonEl = null;

    const remove = () => {
      if (skeleton.parentNode) skeleton.parentNode.removeChild(skeleton);
    };

    const host = this.surfaceEl;
    if (host && host.updateComplete && typeof host.updateComplete.then === "function") {
      host.updateComplete.then(remove, remove);
    } else {
      requestAnimationFrame(remove);
    }
  },

  /** Renders the bootstrap skeleton (see "Zero jank" in the header). */
  renderSkeleton() {
    if (this.skeletonEl) return;
    const skeleton = document.createElement("div");
    skeleton.setAttribute("data-ash-a2ui-skeleton", "");
    skeleton.innerHTML = SKELETON_MARKUP;
    this.el.appendChild(skeleton);
    this.skeletonEl = skeleton;
  },

  /**
   * Scrolls the freshly opened record-task panel into view and focuses its
   * first field, client-side. Waits for the surface's pending render plus a
   * frame so the panel's DOM exists and has layout.
   */
  schedulePanelReveal() {
    if (typeof requestAnimationFrame !== "function") return;
    const run = () => this.revealPanel();
    const host = this.surfaceEl;
    if (host && host.updateComplete && typeof host.updateComplete.then === "function") {
      host.updateComplete.then(() => requestAnimationFrame(run), run);
    } else {
      requestAnimationFrame(() => requestAnimationFrame(run));
    }
  },

  revealPanel() {
    const host = this.surfaceEl;
    if (!host) return;

    const panel = PANEL_IDS.map((id) => queryDeep(host, `#${id}`)).find(
      (element) => element && laidOut(element),
    );
    if (!panel) return;

    try {
      panel.scrollIntoView({block: "start", behavior: "instant"});
    } catch {
      panel.scrollIntoView();
    }

    // The admin recordPanel moves focus itself (heading on open, restore on
    // close); stay out of the way when focus already lives in the panel.
    if (activeInside(panel)) return;

    const field = firstFieldDeep(panel);
    if (field) {
      try {
        field.focus({preventScroll: false});
      } catch {
        field.focus();
      }
    }
  },

  /**
   * Whether the processor still holds a surface. After a LiveView re-join
   * the server bootstraps the surface again on this same hook instance; the
   * old surface must then be replaced, not created twice.
   */
  surfaceExists(surfaceId) {
    return Boolean(this.processor && this.processor.getSurface(surfaceId));
  },

  /**
   * Opens another surface on a record (reference links): the host's
   * `openSurface` callback when configured, else the `"a2ui:open_surface"`
   * LiveView event with `{surface, recordId, query}` (the server builds the
   * navigation target itself; a client-supplied href is never trusted).
   */
  openSurface(detail) {
    const surface = detail && detail.surface;
    if (typeof surface !== "string" || surface === "") return;
    const args = {surface};
    if (detail.recordId !== undefined && detail.recordId !== null && detail.recordId !== "") {
      args.recordId = String(detail.recordId);
    }
    if (detail.query && typeof detail.query === "object") args.query = detail.query;

    if (this.deps.openSurface) {
      this.deps.openSurface(args, {surfaceId: detail.surfaceId, href: detail.href});
      return;
    }
    this.pushEvent("a2ui:open_surface", args);
  },
};

export default AshA2ui;
