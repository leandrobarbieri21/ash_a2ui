/**
 * AshA2ui LiveView JS hook.
 *
 * Hosts an `<a2ui-surface>` element (from `@a2ui/lit`) inside the LiveView
 * container, feeds it the A2UI server->client messages pushed by
 * `AshA2ui.LiveRenderer` as the "a2ui:messages" event, and forwards the
 * renderer's client `action` payloads back to the server as the
 * "a2ui:action" LiveView event (wrapped in the A2UI client envelope of the
 * surface's protocol version).
 *
 * ## A2UI v1.0 support
 *
 * No published `@a2ui/lit` / `@a2ui/web_core` release ships a v1.0 runtime
 * (0.10.x exposes only v0_8/v0_9 entry points; the v1_0 directory carries
 * schemas alone) — so this hook is the v1.0-capable client layer on top of
 * the v0_9 renderer. Per-message (`message.version === "v1.0"`) it:
 *
 *   - **expands inline `createSurface`** (v1.0's single-message bootstrap
 *     carrying `components` + `dataModel`) into the v0.9 triple the
 *     renderer understands, mapping the v1.0 basic-catalog id onto a
 *     registered catalog and carrying `surfaceProperties` through as the
 *     surface theme metadata;
 *   - **generates the `actionResponse` handshake**: outgoing actions from a
 *     v1.0 surface carry a unique `actionId` + `wantResponse: true` in a
 *     v1.0 envelope, and — the UX point — the hook optimistically writes
 *     `{status: "pending", ...}` to the surface's reserved `/ui/response`
 *     path the moment the action fires, so bound status components show
 *     feedback at 0 RTT. The server's `actionResponse` (echoing the
 *     `actionId`) resolves the pending entry; a watchdog timeout writes a
 *     timeout error into `/ui/response` if no response ever arrives. Every
 *     response also dispatches a bubbling `"ash-a2ui:action-response"`
 *     CustomEvent on the container for host-level integration.
 *   - **executes `callFunction`** server->client calls against the
 *     host-registered function table (`configureAshA2ui({functions})`;
 *     `openUrl` and `downloadFile` ship as built-ins) and pushes the `functionResponse`
 *     back as the "a2ui:function_response" LiveView event when
 *     `wantResponse` is set.
 *
 * v0.9.1 surfaces are untouched: their messages pass straight through and
 * their actions keep the v0.9.1 envelope.
 *
 * ## Reference links: `openSurface`
 *
 * Activating a reference link (admin catalog DataGrid link cells and
 * FieldDisplay links, or any `{"functionCall": {"call": "openSurface"}}`)
 * raises the bubbling, composed `"ash-a2ui:open-surface"` DOM event with
 * `detail = {surface, recordId?, query?, href?, surfaceId}`. The hook
 * catches it for its own surface and pushes the `"a2ui:open_surface"`
 * LiveView event with `{surface, recordId, query}` — `AshA2ui.LiveRenderer`
 * navigates to the configured `open_surface_url` by default. A
 * server-sent v1.0 `callFunction` `openSurface` takes the same path. Hosts
 * that want to handle it client-side pass
 * `configureAshA2ui({openSurface: (args, {surfaceId, href}) => ...})`.
 *
 * ## Contract with the host bundle
 *
 * This file ships without dependencies — importing `@a2ui/lit` /
 * `@a2ui/web_core` is left to the host app bundle, which must:
 *
 *   1. Import `@a2ui/lit/v0_9` so the `<a2ui-surface>` custom element is
 *      registered (the import has that side effect).
 *   2. Hand the renderer classes to this hook before `LiveSocket` mounts it:
 *
 *          import {MessageProcessor} from "@a2ui/web_core/v0_9";
 *          import {basicCatalog} from "@a2ui/lit/v0_9";
 *          import {AshA2ui, configureAshA2ui} from "ash_a2ui/priv/js/ash_a2ui_hook.js";
 *
 *          configureAshA2ui({MessageProcessor, catalogs: [basicCatalog]});
 *          const liveSocket = new LiveSocket("/live", Socket, {hooks: {AshA2ui}});
 *
 * Optional extras shipped alongside this hook (see the Theming topic):
 *
 *   - `ash_a2ui_theme.css` — a neutral `--a2ui-*` CSS-variable theme for
 *     the basic catalog; import it into your app CSS and override tokens.
 *   - `ash_a2ui_catalog.js` — `createAshA2uiCatalog(deps)` builds a merged
 *     catalog (registered under the basic catalog id) whose ChoicePicker
 *     renders a native `<select>` for single-choice pickers and whose
 *     Column upgrades AshA2ui search-picker composites to a typeahead
 *     combobox (pass `ColumnApi` in the deps to enable).
 *   - `configureAshA2ui({..., markdown})` — wires a markdown renderer so
 *     Text headings render as headings instead of literal `##` markdown
 *     (see the configureAshA2ui docs below).
 *
 * Verified against @a2ui/lit / @a2ui/web_core 0.10.x sources
 * (https://github.com/a2ui-project/a2ui, renderers/web_core + renderers/lit,
 * v0_9 entry points):
 *
 *   - Message ingest is `new MessageProcessor(catalogs, actionHandler)` +
 *     `processor.processMessages(messages)` — NOT a method on the
 *     `<a2ui-surface>` element. The element only takes a `SurfaceModel` via
 *     its `surface` property, delivered through
 *     `processor.onSurfaceCreated(cb)`.
 *   - User actions are delivered to the `actionHandler` callback passed to
 *     the `MessageProcessor` constructor (an `A2uiClientAction` with `name`,
 *     `surfaceId`, `sourceComponentId`, `context`) — in v0.9 there is no
 *     public action DOM event on the surface element.
 *
 * Actions flow through exactly one path: the `actionHandler` callback passed
 * to the `MessageProcessor` constructor (an `A2uiClientAction` with `name`,
 * `surfaceId`, `sourceComponentId`, `context`). A v0.8-era DOM-event
 * fallback (`a2uiaction` listener) was removed: verified against
 * @a2ui/lit 0.10.x sources, the v0_9 renderer does not dispatch a public
 * action DOM event, so the listener could only ever double-push an action
 * when a renderer build fired both paths. Docs:
 * https://www.npmjs.com/package/@a2ui/lit and
 * https://a2ui.org/guides/client-setup/.
 *
 * ## Zero jank: bootstrap skeleton and panel reveal
 *
 * Between the LiveView mount and the first component tree there is nothing
 * to show, so `mounted()` immediately renders a lightweight skeleton
 * (heading bar + row bars) inside the hook container, styled only with the
 * `--a2ui-*` custom properties (hosts theme it with everything else). The
 * skeleton is removed the moment the first surface render lands — the
 * removal waits for the surface element's first update (Lit
 * `updateComplete`) so there is no blank frame between the two. On a
 * LiveView reconnect the hook remounts and the skeleton reappears until the
 * fresh bootstrap hydrates: a torn-down surface never shows stale content
 * dressed up as live data.
 *
 * When a record-task panel opens (`start_create` / `view_record` /
 * `start_edit` flip `/ui/panel/visible`), the hook scrolls the panel into
 * view and focuses its first field — client-side, zero roundtrip. The
 * admin catalog's `recordPanel` manages its own focus; the reveal stays out
 * of the way when focus has already moved inside the panel.
 *
 * v0 limitation: a single surface per hook — the last surface created by the
 * processor wins the `<a2ui-surface>` element.
 */

let hookDeps = null;

/**
 * Registers the renderer classes the hook needs. Call once from the host
 * bundle before the LiveSocket mounts any AshA2ui hook.
 *
 * `markdown` is optional but strongly recommended: without a markdown
 * renderer the basic catalog's Text component prints headings as literal
 * markdown (`## Title`) — an upstream design decision, see
 * https://github.com/google/A2UI/issues/1226. Pass the three pieces and
 * the hook wires them up with a Lit context provider on the hook element:
 *
 *     import {ContextProvider} from "@lit/context";
 *     import {Context} from "@a2ui/lit/v0_9";
 *     import {renderMarkdown} from "@a2ui/markdown-it";
 *
 *     configureAshA2ui({
 *       MessageProcessor,
 *       catalogs: [catalog],
 *       markdown: {ContextProvider, context: Context.markdown, render: renderMarkdown},
 *     });
 *
 * (`ContextProvider` attaches its `context-request` listeners directly to
 * the host element, so a plain hook container works as the provider host —
 * verified against @lit/context 1.x `context-provider.js`.)
 *
 * @param {{
 *   MessageProcessor: Function,
 *   catalogs: Array<object>,
 *   markdown?: {ContextProvider: Function, context: object, render: Function},
 *   functions?: Object<string, Function>,
 *   openSurface?: Function,
 *   pendingMessage?: string,
 *   actionTimeoutMs?: number,
 * }} deps
 *   `functions` — client-side functions the server may invoke via v1.0
 *   `callFunction` messages, keyed by name (`(args) => value | Promise`);
 *   merged over the built-in `openUrl` / `downloadFile`. `pendingMessage` — the optimistic
 *   `/ui/response` message shown while a v1.0 action is in flight (default
 *   "Working…"). `actionTimeoutMs` — v1.0 actionResponse watchdog (default
 *   10000; 0 disables). `openSurface` — `(args, {surfaceId, href}) => void`:
 *   handle reference-link navigation client-side instead of pushing the
 *   `"a2ui:open_surface"` LiveView event.
 */
export function configureAshA2ui(deps) {
  hookDeps = deps;
}

function resolveDeps() {
  // Fallback for host bundles that prefer a global over calling
  // configureAshA2ui (e.g. when the hook is bundled separately).
  const deps = hookDeps || globalThis.__ASH_A2UI_DEPS__;

  if (!deps || typeof deps.MessageProcessor !== "function") {
    throw new Error(
      "AshA2ui hook: missing @a2ui renderer classes. Call " +
        "configureAshA2ui({MessageProcessor, catalogs}) from your app bundle " +
        "(or set globalThis.__ASH_A2UI_DEPS__) before mounting the LiveSocket.",
    );
  }

  return {
    MessageProcessor: deps.MessageProcessor,
    catalogs: deps.catalogs || [],
    markdown: deps.markdown || null,
    functions: {...BUILTIN_FUNCTIONS, ...(deps.functions || {})},
    pendingMessage: deps.pendingMessage || "Working…",
    openSurface: typeof deps.openSurface === "function" ? deps.openSurface : null,
    actionTimeoutMs: deps.actionTimeoutMs === undefined ? 10000 : deps.actionTimeoutMs,
  };
}

const V1_VERSION = "v1.0";
const OPEN_SURFACE_EVENT = "ash-a2ui:open-surface";
const V1_BASIC_CATALOG_ID = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json";
const V0_BASIC_CATALOG_ID = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json";

const BUILTIN_FUNCTIONS = {
  openUrl: (args) => {
    if (args && typeof args.url === "string") window.open(args.url, "_blank", "noopener");
    return null;
  },
  // The frozen server-generated file-export contract (see AshA2ui.Export):
  // `dataUrl` (a data: URL — how AshA2ui delivers CSV exports) or `url`
  // (a signed download URL, for hosts that upload instead of inlining),
  // downloaded under `filename` via a transient anchor click.
  downloadFile: (args) => {
    const href = args && (typeof args.dataUrl === "string" ? args.dataUrl : args.url);
    if (typeof href !== "string") return null;
    const anchor = document.createElement("a");
    anchor.href = href;
    anchor.download = (args && args.filename) || "download";
    anchor.rel = "noopener";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    return null;
  },
};

function randomActionId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }
  return `a2ui-${Date.now()}-${Math.random().toString(36).slice(2)}`;
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

// The panel visibility sentinel is a zero-or-one list (`[]` hidden,
// `[...]` visible — AshA2ui.Experience.sentinel/1).
function panelVisibleSentinel(value) {
  return Array.isArray(value) && value.length > 0;
}

// Extracts the panel state a server->client message carries, if any:
// `/ui/panel` writes from the action handler, or the full data model under
// "/" (bootstrap, data-only refreshes). Returns true | false | null
// (message carries no panel state).
function panelStateOf(message) {
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

const PANEL_IDS = ["record_panel", "form_slot", "form"];

export const AshA2ui = {
  mounted() {
    const deps = resolveDeps();
    const {MessageProcessor, catalogs, markdown} = deps;
    this.deps = deps;

    // v1.0 state: which surfaces speak v1.0, and the in-flight
    // actionId -> {surfaceId, timer} entries awaiting an actionResponse.
    this.v1Surfaces = new Set();
    this.pendingActions = new Map();

    // Zero-jank state: the bootstrap skeleton, and whether the record-task
    // panel is currently open (reveal fires on the hidden -> visible flip
    // only — background refreshes must not yank scroll/focus).
    this.skeletonEl = null;
    this.panelVisible = false;
    this.renderSkeleton();

    // Provide the markdown renderer to Text components (which consume the
    // `Context.markdown` Lit context) from the hook container, an ancestor
    // of every rendered component. The renderer contract is
    // `(value, options) => Promise<string>`; wrap sync renderers so both
    // shapes work.
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
    // the surface id — accept those only for surfaces this hook renders.
    this.surfaceIds = new Set();
    this.onOpenSurface = (event) => {
      const detail = event.detail || {};
      const ours = event.composedPath().includes(this.el) || this.surfaceIds.has(detail.surfaceId);
      if (!ours || event.__ashA2uiHandled) return;
      event.__ashA2uiHandled = true;
      this.openSurface(detail);
    };
    window.addEventListener(OPEN_SURFACE_EVENT, this.onOpenSurface);
    // The server-sent v1.0 callFunction "openSurface" takes the same route
    // unless the host registered its own function under that name.
    this.functions = {
      openSurface: (args) => {
        this.openSurface(args || {});
        return null;
      },
      ...deps.functions,
    };

    this.processor = new MessageProcessor(catalogs, (action) => {
      this.forwardAction(action);
    });

    // The surface element renders a SurfaceModel; hand it the model as soon
    // as the processor creates it (single-surface v0 semantics).
    if (typeof this.processor.onSurfaceCreated === "function") {
      this.surfaceSubscription = this.processor.onSurfaceCreated((surface) => {
        if (surface && surface.id) this.surfaceIds.add(surface.id);
        this.surfaceEl.surface = surface;
        this.dismissSkeleton();
      });
    }

    this.handleEvent("a2ui:messages", ({messages}) => {
      this.processMessages(messages || []);
    });
  },

  destroyed() {
    if (this.onOpenSurface) window.removeEventListener(OPEN_SURFACE_EVENT, this.onOpenSurface);

    for (const pending of this.pendingActions.values()) {
      if (pending.timer) clearTimeout(pending.timer);
    }
    this.pendingActions.clear();

    if (this.surfaceSubscription && typeof this.surfaceSubscription.unsubscribe === "function") {
      this.surfaceSubscription.unsubscribe();
    }

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
    // LiveView is discarding — dropping the reference is enough.
    this.markdownProvider = null;
  },

  /**
   * Feeds pushed server->client messages into the renderer, adapting v1.0
   * messages for the v0_9 MessageProcessor (see "A2UI v1.0 support" above).
   */
  processMessages(messages) {
    if (!this.processor) return;

    const adapted = [];
    for (const message of messages) {
      adapted.push(...this.adaptMessage(message));
    }

    this.feedProcessor(adapted);

    // Belt and braces for the skeleton: onSurfaceCreated dismisses it, but
    // a processor without that hook still boots a surface through a
    // createSurface message here.
    if (this.skeletonEl && adapted.some((message) => message && message.createSurface)) {
      this.dismissSkeleton();
    }

    // Zero-jank panel reveal: only on the hidden -> visible flip, so
    // background data refreshes never yank scroll or focus.
    for (const message of adapted) {
      const visible = panelStateOf(message);
      if (visible === null) continue;
      const wasVisible = this.panelVisible;
      this.panelVisible = visible;
      if (visible && !wasVisible) this.schedulePanelReveal();
    }
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
   * first field — client-side, zero roundtrip. Waits for the surface's
   * pending render plus a frame so the panel's DOM exists and has layout.
   */
  schedulePanelReveal() {
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
    // close) — stay out of the way when focus already lives in the panel.
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

  feedProcessor(messages) {
    if (messages.length === 0) return;

    if (typeof this.processor.processMessages === "function") {
      this.processor.processMessages(messages);
    } else if (typeof this.processor.processMessage === "function") {
      // Defensive: older/newer builds may only expose the singular API.
      for (const message of messages) {
        this.processor.processMessage(message);
      }
    } else {
      console.error("AshA2ui hook: MessageProcessor has no processMessages/processMessage API");
    }
  },

  /**
   * Maps one server->client message to the list of messages handed to the
   * v0_9 renderer. v0.9.1 messages pass through untouched; v1.0 messages
   * are expanded/consumed per the header comment.
   */
  adaptMessage(message) {
    if (!message || message.version !== V1_VERSION) return [message];

    if (message.createSurface) return this.adaptV1CreateSurface(message.createSurface);

    if (message.actionResponse) {
      this.resolveActionResponse(message);
      return [];
    }

    if (message.callFunction) {
      this.executeFunctionCall(message);
      return [];
    }

    if (message.deleteSurface && message.deleteSurface.surfaceId) {
      this.v1Surfaces.delete(message.deleteSurface.surfaceId);
    }

    // updateComponents / updateDataModel / deleteSurface payloads are
    // shape-compatible with v0.9; the processor does not inspect `version`.
    return [message];
  },

  /**
   * Expands v1.0's inline createSurface (surface + components + dataModel
   * in one message) into the v0.9 triple the published renderer
   * understands, mapping the v1.0 basic-catalog id onto a registered
   * catalog and passing surfaceProperties through as the surface's theme
   * metadata slot.
   */
  adaptV1CreateSurface(payload) {
    const {surfaceId, catalogId, surfaceProperties, sendDataModel, components, dataModel} = payload;

    this.v1Surfaces.add(surfaceId);

    const registered = (this.deps.catalogs || []).some((catalog) => catalog.id === catalogId);
    const mappedCatalogId =
      !registered && catalogId === V1_BASIC_CATALOG_ID ? V0_BASIC_CATALOG_ID : catalogId;

    const create = {surfaceId, catalogId: mappedCatalogId};
    if (surfaceProperties) create.theme = surfaceProperties;
    if (sendDataModel !== undefined) create.sendDataModel = sendDataModel;

    const expanded = [{createSurface: create}];

    if (components && components.length > 0) {
      expanded.push({updateComponents: {surfaceId, components}});
    }

    if (dataModel !== undefined) {
      expanded.push({updateDataModel: {surfaceId, path: "/", value: dataModel}});
    }

    return expanded;
  },

  /**
   * Resolves a server actionResponse: clears the pending entry (and its
   * watchdog), settles the optimistic /ui/response pending state with the
   * response itself, and re-dispatches the response as a bubbling DOM event
   * so host code can react per action.
   */
  resolveActionResponse(message) {
    const pending = this.pendingActions.get(message.actionId);

    if (pending) {
      if (pending.timer) clearTimeout(pending.timer);
      this.pendingActions.delete(message.actionId);

      // Settle the optimistic pending write with the response payload so
      // "Working…" never outlives its action. The actionResponse is the
      // FIRST message of the server's reply batch, so a server /ui/response
      // write in the same batch (e.g. an invoke result) lands after this
      // and wins — this is only the floor.
      const response = message.actionResponse || {};
      const settled = response.error
        ? {
            status: "error",
            code: response.error.code || "",
            message: response.error.message || "",
            result: {},
            resultText: "",
          }
        : {
            status: "ok",
            message: "",
            result: {},
            resultText: "",
            ...(response.value || {}),
          };

      this.writeUiResponse(pending.surfaceId, settled);
    }

    this.el.dispatchEvent(
      new CustomEvent("ash-a2ui:action-response", {
        bubbles: true,
        detail: {
          actionId: message.actionId,
          surfaceId: pending ? pending.surfaceId : undefined,
          response: message.actionResponse,
        },
      }),
    );
  },

  /**
   * Executes a v1.0 server->client callFunction against the registered
   * function table and, when `wantResponse` is set, pushes the
   * functionResponse (or error) back as the "a2ui:function_response"
   * LiveView event.
   */
  executeFunctionCall(message) {
    const {functionCallId, wantResponse, callFunction} = message;
    const name = callFunction && callFunction.call;
    const fn = (this.functions || this.deps.functions)[name];

    const reply = (payload) => {
      if (wantResponse) this.pushEvent("a2ui:function_response", payload);
    };

    if (typeof fn !== "function") {
      console.warn(`AshA2ui hook: no client function registered for callFunction "${name}"`);
      reply({
        version: V1_VERSION,
        error: {code: "UNSUPPORTED_FUNCTION", message: `Unknown function: ${name}`, functionCallId},
      });
      return;
    }

    Promise.resolve()
      .then(() => fn(callFunction.args || {}))
      .then((value) =>
        reply({
          version: V1_VERSION,
          functionResponse: {functionCallId, call: name, value: value === undefined ? null : value},
        }),
      )
      .catch((error) =>
        reply({
          version: V1_VERSION,
          error: {code: "FUNCTION_FAILED", message: String(error), functionCallId},
        }),
      );
  },

  /**
   * Opens another surface on a record (reference links): the host's
   * `openSurface` callback when configured, else the `"a2ui:open_surface"`
   * LiveView event with `{surface, recordId, query}` (the server builds the
   * navigation target itself — a client-supplied href is never trusted).
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

  /**
   * Writes the surface's reserved /ui/response object locally (through the
   * renderer's own data model) — the 0-RTT pending/timeout feedback path.
   */
  writeUiResponse(surfaceId, value) {
    this.feedProcessor([
      {updateDataModel: {surfaceId, path: "/ui/response", value}},
    ]);
  },

  /**
   * Wraps a renderer action (the A2uiClientAction delivered to the
   * MessageProcessor's action handler) in the A2UI client->server envelope
   * of the surface's protocol version and pushes it to the LiveView.
   *
   * For v1.0 surfaces the action carries a generated `actionId` +
   * `wantResponse: true`, an optimistic `{status: "pending"}` is written to
   * `/ui/response` (instant feedback on the bound status components), and a
   * watchdog turns a never-answered action into a visible timeout error.
   */
  forwardAction(action) {
    if (!action || !action.name) return;

    const inner = {
      name: action.name,
      surfaceId: action.surfaceId,
      sourceComponentId: action.sourceComponentId,
      timestamp: action.timestamp || new Date().toISOString(),
      context: action.context || {},
    };

    if (!this.v1Surfaces.has(action.surfaceId)) {
      this.pushEvent("a2ui:action", {version: "v0.9.1", action: inner});
      return;
    }

    const actionId = randomActionId();
    inner.actionId = actionId;
    inner.wantResponse = true;

    let timer = null;
    if (this.deps.actionTimeoutMs > 0) {
      timer = setTimeout(() => {
        if (!this.pendingActions.has(actionId)) return;
        this.pendingActions.delete(actionId);
        this.writeUiResponse(action.surfaceId, {
          status: "error",
          code: "TIMEOUT",
          message: "The server did not respond in time. Please try again.",
          result: {},
          resultText: "",
        });
      }, this.deps.actionTimeoutMs);
    }

    this.pendingActions.set(actionId, {surfaceId: action.surfaceId, timer});

    this.writeUiResponse(action.surfaceId, {
      status: "pending",
      message: this.deps.pendingMessage,
      result: {},
      resultText: "",
    });

    this.pushEvent("a2ui:action", {version: V1_VERSION, action: inner});
  },
};

export default AshA2ui;
