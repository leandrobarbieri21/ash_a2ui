/**
 * Ash admin catalog v1 — semantic Lit components for the `@a2ui/lit`
 * renderer.
 *
 * `createAshAdminCatalog(deps)` builds a `@a2ui/web_core` Catalog
 * registered under the admin catalog id
 * (`https://ash-a2ui.dev/catalogs/admin/v1`) so a surface whose
 * `createSurface.catalogId` matches resolves these components. Registration
 * under a custom catalog id is first-class in the renderer:
 * `MessageProcessor.processCreateSurfaceMessage` resolves
 * `catalogs.find(c => c.id === catalogId)` by exact match (see
 * web_core `processing/message-processor.js`), and the renderer looks every
 * component type up via `catalog.components.get(type).tagName` (see @a2ui/lit
 * `surface/render-a2ui-node.js`). No merging into the basic catalog is
 * involved — the admin catalog is a sibling the host registers alongside it:
 *
 *     import {z} from "zod";
 *     import {Catalog} from "@a2ui/web_core/v0_9";
 *     import {basicCatalog, A2uiLitElement, A2uiController} from "@a2ui/lit/v0_9";
 *     import {html, css, nothing} from "lit";
 *     import {createAshAdminCatalog} from "../../deps/ash_a2ui/priv/js/ash_admin_catalog.js";
 *
 *     const adminCatalog = createAshAdminCatalog({
 *       Catalog, basicCatalog, A2uiLitElement, A2uiController,
 *       lit: {html, css, nothing},
 *       // `z` is OPTIONAL since issue #5: binding-capable props are built
 *       // from @a2ui/web_core's own exported schema builders (web_core's
 *       // zod 3), so the host zod is no longer consumed. If you still pass
 *       // `z`, it must be the same zod MAJOR as @a2ui/web_core (zod 3) —
 *       // a foreign major throws immediately.
 *       z,
 *     });
 *     configureAshA2ui({MessageProcessor, catalogs: [basicCatalog, adminCatalog]});
 *
 * The catalog EXTENDS the basic catalog (contract: "admin adds semantic
 * components; it does not remove primitives"): every component of
 * `deps.basicCatalog` is carried over — pass the stock `basicCatalog` or the
 * merged `createAshA2uiCatalog` result to inherit its upgrades — plus the
 * ten semantic components:
 *
 *   entityPage, dataGrid, emptyState, pagination, recordPanel, fieldDisplay,
 *   formSection, actionBar, statusBanner, confirmDialog
 *
 * (camelCase names are the wire contract, pinned by A2UI-101B/AC-1 and
 * `priv/a2ui/admin_v1/catalog.json`.)
 *
 * ## Events
 *
 * Every dispatched action reuses the existing envelopes byte-for-byte:
 *
 *   - row actions / ConfirmDialog confirm → the flat envelope the encoder
 *     emits (`{label, action: <name>, context: {...}}`), with
 *     `{"path": "id"}`-style leaves resolved against the clicked row's base
 *     path — the same resolution the basic catalog's templated buttons
 *     perform;
 *   - ActionBar primary → the `action` envelope prop (emitted as the frozen
 *     `submit_form` event), dispatched through the GenericBinder's own
 *     action resolution exactly like a basic Button; a reconstructed
 *     `{values: /form, recordId: /form/id[, query][, contexts]}` fallback
 *     covers envelope-less emissions;
 *   - Pagination prev/next → the `previousAction`/`nextAction` bare event
 *     objects the encoder emits (`{"name": "query", "context": {...}}`),
 *     resolved and dispatched with pageDelta ∓1/±1; a derivation fallback
 *     covers envelope-less emissions.
 *
 * ## Zero jank: instant action acknowledgement
 *
 * Dispatching components acknowledge clicks at 0 RTT: the ActionBar primary
 * button and every DataGrid row-action button render disabled + spinner the
 * moment they dispatch, and settle when the surface's data model next
 * reports an outcome write (`/ui/feedback` or `/ui/response` — at least
 * one is written by every AshA2ui action these components dispatch:
 * submits, invokes, task open/cancel, context select/clear and every
 * rejection, on both wire versions). Any path write settles, including one
 * that leaves the value as it was: View and Cancel write the already-clear
 * feedback, and waiting for a changed message left the View button
 * spinning (clinic-demo). A write replacing the whole data model (a PubSub
 * refresh) is not an outcome and does not settle. No styling round
 * trip and no `phx-*-loading`: these components own their shadow DOM, and
 * host CSS cannot reach inside it.
 *
 * ## A11y-hardened basic inputs
 *
 * The core basic-catalog inputs render adjacent validation errors but do not
 * wire `aria-invalid`/`aria-describedby` (verified against @a2ui/lit 0.10.x
 * `TextField.js`/`CheckBox.js`). To satisfy the renderer quality contract,
 * this catalog REPLACES TextField, CheckBox, ChoicePicker and DateTimeInput
 * (inside admin surfaces only — the basic catalog registered under its own id
 * is untouched) with equivalent components that associate a real `<label>`,
 * read the AshA2ui form-error state (`/errors/<field>`, derived from each
 * input's `/form/<field>` value binding), and render the error adjacent to
 * the control with the aria wiring. FormSection pairs the encoder's sibling
 * `form_error_<field>` Texts with their inputs so messages are never
 * double-rendered (see that component below).
 *
 * ## Design tokens
 *
 * See `ash_admin_tokens.js` — the public `--ash-admin-*` surface with
 * `--a2ui-*` fallbacks and restrained literal defaults. No CSS framework
 * dependencies; light-mode first, dark-mode coherent whenever the host
 * themes the `--a2ui-*` layer (e.g. via `ash_a2ui_theme.css`).
 *
 * ## Contract with the host bundle
 *
 * Same discipline as `ash_a2ui_catalog.js`: no bundled dependencies, the
 * host passes the single `lit` / `@a2ui` instance in. Verified against
 * @a2ui/lit 0.10.1 / @a2ui/web_core 0.11.0 / lit 3.x.
 *
 * ## Schema provenance (issue #5)
 *
 * `@a2ui/web_core`'s GenericBinder classifies binding-capable props by
 * introspecting **zod 3 internals** (`_def.typeName`, `_def.shape()` — see
 * its `scrapeSchemaBehavior`). This file used to build its ten component
 * schemas with the host's `z`; under a host zod 4 every node scraped as
 * STATIC, so reserved-path bindings rendered `[object Object]` and grids
 * stayed empty. The schemas are therefore now composed from web_core's own
 * exported builders (`DynamicStringSchema`, `DynamicValueSchema`,
 * `ActionSchema`, `ChildListSchema`, ... — imported from
 * `@a2ui/web_core/v0_9`, the SAME module instance the binder uses):
 * binder-visible under any host zod. Static (non-binding) props derive
 * their primitives from web_core's exported schemas via public zod-3
 * accessors, so the host's `z` is no longer consumed at all — passing it
 * is optional, and when it IS passed its major is checked loudly (see the
 * guard in `createAshAdminCatalog`).
 */

import {
  createAdminStyles,
  resolveEventContext,
  getByPath,
  formatDisplayValue,
  applyWeight,
  childRefs,
  badgeTone,
  linkEntries,
  listItems,
  pageWindow,
} from "./ash_admin_tokens.js";

// The prompt-closing Modal override, shared with the merged basic catalog
// (the board and basic-table prompts render the basic composition's Modal
// here too), and the action-outcome subscription both catalogs settle on.
// The file defines its element only when asked.
import {
  promptModalComponent,
  subscribeActionOutcomes,
  unsubscribeActionOutcomes,
} from "./ash_a2ui_catalog.js";

// The NB layer's calendar grid (`nb-calendar`), used by calendarView. The
// file has no imports of its own and defines its elements only when asked.
import {defineNbComponents} from "./nb_components.js";

// Schema builders from web_core's OWN zod (3.x) — the instance the
// GenericBinder introspects. Importing the module directly (rather than
// receiving builders through `deps`) guarantees instance identity: the
// host bundle resolves the same specifier the renderer uses, so there is
// no dual-zod hazard regardless of which zod the host itself bundles.
import {
  ActionSchema,
  AnyComponentSchema,
  CheckableSchema,
  ChildListSchema,
  ComponentIdSchema,
  CreateSurfaceMessageSchema,
  DataBindingSchema,
  DynamicBooleanSchema,
  DynamicNumberSchema,
  DynamicStringSchema,
  DynamicValueSchema,
  FunctionCallSchema,
} from "@a2ui/web_core/v0_9";

/** The admin catalog id a surface must declare to resolve here. */
const ADMIN_CATALOG_ID = "https://ash-a2ui.dev/catalogs/admin/v1";

/** The admin catalog contract version (additive within the v1 id). */
export const ADMIN_CATALOG_VERSION = "1.7.0";

/**
 * The DOM event a reference-link activation raises when the host passed no
 * `openSurface` callback: bubbling + composed (it crosses every shadow root
 * up to `window`), `detail` = `{surface, recordId?, query?, href?,
 * surfaceId}`. The shipped LiveView hook (`ash_a2ui_hook.js`) listens for
 * it and pushes the `"a2ui:open_surface"` LiveView event, whose default
 * `AshA2ui.LiveRenderer` handling navigates to the configured
 * `open_surface_url`.
 */
export const OPEN_SURFACE_EVENT = "ash-a2ui:open-surface";

/**
 * Hands an `openSurface` request to the host: the `deps.openSurface`
 * callback (`(args, {surfaceId, href}) => void`) when given, otherwise the
 * OPEN_SURFACE_EVENT dispatched from `source` (an element inside the
 * surface) or, without one, from `window`.
 */
function requestOpenSurface(deps, args, {surfaceId, source, href} = {}) {
  if (!args || typeof args.surface !== "string" || args.surface === "") return;
  if (deps && typeof deps.openSurface === "function") {
    deps.openSurface(args, {surfaceId, href});
    return;
  }
  const target = source || globalThis;
  if (!target || typeof target.dispatchEvent !== "function") return;
  target.dispatchEvent(
    new CustomEvent(OPEN_SURFACE_EVENT, {
      bubbles: true,
      composed: true,
      detail: {...args, surfaceId, href},
    }),
  );
}

/** The openSurface args of a link object. */
function openSurfaceArgs(link) {
  const args = {surface: String(link.surface)};
  if (link.recordId !== null && link.recordId !== undefined && link.recordId !== "") {
    args.recordId = String(link.recordId);
  }
  if (link.query && typeof link.query === "object") args.query = link.query;
  return args;
}

/** Wire kinds (camelCase — pinned by the A2UI-101B contract) → tag names. */
const TAGS = {
  entityPage: "ash-admin-entity-page",
  dataGrid: "ash-admin-data-grid",
  emptyState: "ash-admin-empty-state",
  pagination: "ash-admin-pagination",
  recordPanel: "ash-admin-record-panel",
  fieldDisplay: "ash-admin-field-display",
  formSection: "ash-admin-form-section",
  actionBar: "ash-admin-action-bar",
  statusBanner: "ash-admin-status-banner",
  confirmDialog: "ash-admin-confirm-dialog",
  calendarView: "ash-admin-calendar-view",
  liveDiagram: "ash-admin-live-diagram",
};

/** Basic input kinds this catalog replaces with a11y-hardened elements. */
const INPUT_OVERRIDE_KINDS = ["TextField", "CheckBox", "ChoicePicker", "DateTimeInput"];
const INPUT_OVERRIDE_TAGS = {
  TextField: "ash-admin-textfield",
  CheckBox: "ash-admin-checkbox",
  ChoicePicker: "ash-admin-choicepicker",
  DateTimeInput: "ash-admin-datetimeinput",
};

// Responsive breakpoint: the DataGrid renders a real table at ≥ 48rem and a
// card list below it (CSS container query on the grid host).
const GRID_TABLE_MIN = "48rem";
void GRID_TABLE_MIN;

/**
 * Builds the admin catalog. See the module docs for the `deps` contract:
 * `{Catalog, basicCatalog, A2uiLitElement, A2uiController, z,
 * lit: {html, css, nothing}}`, plus the optional `loadMermaid` (a function
 * returning a promise of the mermaid engine, called the first time a
 * `liveDiagram` draws; see priv/js/ash_a2ui_mermaid.js) and
 * `openSurface`.
 *
 * @returns {object} a `@a2ui/web_core` Catalog registered under the admin
 *   catalog id, extending `deps.basicCatalog`.
 */
export function createAshAdminCatalog(deps) {
  const {Catalog, basicCatalog, A2uiLitElement, A2uiController, lit, z} = deps || {};

  // Loud guard (issue #5 defense): a foreign-zod `z` was the root cause of
  // reserved-path bindings rendering "[object Object]" — the GenericBinder
  // scrapes zod-3 internals, and under a different major every binding prop
  // scrapes STATIC. Binding schemas are now built from web_core's own
  // builders and `z` is optional, but any residual host-z usage must be
  // same-major or the catalog refuses to build with a message naming the
  // fix. (`z.string()._def?.typeName` is "ZodString" on zod 3; on zod 4
  // there is no typeName, so the optional chain short-circuits to undefined.)
  if (z && z.string()._def?.typeName !== "ZodString") {
    throw new Error(
      "createAshAdminCatalog: `z` must be the same zod major as @a2ui/web_core " +
        "(zod 3); binding schemas are now built from web_core's own builders — " +
        "upgrade or stop passing z for binding props",
    );
  }

  if (
    !Catalog ||
    !basicCatalog ||
    !A2uiLitElement ||
    !A2uiController ||
    !lit ||
    !lit.html ||
    !lit.css ||
    !lit.nothing
  ) {
    throw new Error(
      "createAshAdminCatalog: missing deps. Pass {Catalog, basicCatalog, " +
        "A2uiLitElement, A2uiController, lit: {html, css, nothing}} — Catalog is " +
        "the @a2ui/web_core Catalog class. `z` is optional (binding schemas are " +
        "built from @a2ui/web_core's own builders); if passed it must be zod 3.",
    );
  }

  const schemas = buildSchemas();
  const adminApis = Object.fromEntries(
    Object.keys(TAGS).map((kind) => [kind, {name: kind, schema: schemas[kind], tagName: TAGS[kind]}]),
  );

  defineAdminElements(deps, {adminApis});

  // The admin catalog extends the basic catalog: carry every basic component
  // (or the host's merged/overridden version of it), swapping the four input
  // kinds for the a11y-hardened elements and the Modal for the one closing
  // a prompt on a success outcome (boards and basic-composed prompts — see
  // "Prompt Modal" in ash_a2ui_catalog.js), then add the semantic kinds.
  const modal = promptModalComponent(basicCatalog);
  const components = [...basicCatalog.components.values()].map((component) => {
    if (INPUT_OVERRIDE_KINDS.includes(component.name)) {
      return {...component, tagName: INPUT_OVERRIDE_TAGS[component.name]};
    }
    if (component.name === "Modal" && modal) return modal;
    return component;
  });

  // The catalog's own client function: openSurface (reference-link
  // navigation — see OPEN_SURFACE_EVENT). Usable from any functionCall
  // action as {"call": "openSurface", "args": {surface, recordId, query}}.
  const openSurfaceFunction = {
    name: "openSurface",
    returnType: "void",
    schema: schemas.openSurfaceArgs,
    execute: (args, context) => {
      requestOpenSurface(deps, openSurfaceArgs(args || {}), {surfaceId: context?.surface?.id});
      return undefined;
    },
  };

  return new Catalog(
    ADMIN_CATALOG_ID,
    [...components, ...Object.values(adminApis)],
    [
      ...[...basicCatalog.functions.values()].filter((fn) => fn.name !== "openSurface"),
      openSurfaceFunction,
    ],
    basicCatalog.themeSchema,
  );
}

// ---------------------------------------------------------------------------
// Wire schemas
// ---------------------------------------------------------------------------

/**
 * Builds the zod schemas for the ten admin kinds.
 *
 * Every BEHAVIOR-BEARING (binding-capable) prop is composed from
 * `@a2ui/web_core`'s own exported builders — `DynamicStringSchema`,
 * `DynamicNumberSchema`, `DynamicBooleanSchema`, `DynamicValueSchema`,
 * `ChildListSchema`, `ActionSchema` — which are built on web_core's zod 3
 * and stamped with the `REF:common_types.json#/$defs/...` descriptions the
 * GenericBinder's `scrapeSchemaBehavior` keys on first. (The hand-built
 * host-z unions this file used before classified only via the binder's
 * zod-3 union-shape fallback, so they silently degraded to STATIC under a
 * host zod 4 — the issue #5 root cause.) Static props (plain strings,
 * numbers, booleans, enums, records) derive their primitives from
 * web_core's exported schemas too, via public zod-3 accessors, so the
 * whole schema tree is binder-visible regardless of the host zod.
 *
 * Exported for host-side verification (the binder classification repro).
 *
 * Schemas are deliberately NOT `.strict()` and tolerate `nil` wherever the
 * contract allows it, so the Elixir encoder can add props without breaking
 * component validation.
 */
export function buildSchemas() {
  // --- static primitives on web_core's own zod ------------------------------
  // Derived once from web_core's exported schemas via public zod-3
  // accessors (`.shape`, `.unwrap()`, static `.create()`), so static props
  // need no host `z`. Each primitive classifies STATIC in the binder (plain
  // ZodString/Number/Boolean/Any/Record — `ComponentIdSchema` is a plain
  // ZodString whose `component-id` child-ref stamp only matters inside
  // ChildList classification, which these positions never reach).
  const EmptyObject = DataBindingSchema.pick({});
  const Str = ComponentIdSchema;
  const Num = AnyComponentSchema.shape.weight.unwrap();
  const Bool = CreateSurfaceMessageSchema.shape.createSurface.shape.sendDataModel.unwrap();
  const Any = CreateSurfaceMessageSchema.shape.createSurface.shape.theme.unwrap();
  const RecordAny = FunctionCallSchema.shape.args;
  const ArrayOf = (element) => CheckableSchema.shape.checks.unwrap().constructor.create(element);
  const EnumOf = (values) => CreateSurfaceMessageSchema.shape.version.constructor.create(values);

  const formatEnum = () => EnumOf(["text", "datetime", "boolean", "number"]).optional();

  // Bare event objects exactly as `admin_page_action/3` emits them:
  // {"name": "query", "context": {...}} with absolute path refs.
  // Deliberately NOT a union with an event-shaped option — that would trip
  // the GenericBinder's ACTION detection and silently mis-dispatch these
  // values (dispatchAction drops payloads without an `event`).
  const bareEvent = () => EmptyObject.extend({name: Str, context: RecordAny.optional()});

  return {
    entityPage: EmptyObject.extend({
      title: DynamicStringSchema,
      description: DynamicStringSchema.nullable().optional(),
      children: ChildListSchema.optional(),
      // 1.6: false when the host page already owns the heading.
      headerVisible: Bool.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    dataGrid: EmptyObject.extend({
      // `format` per column is optional (not pinned by the contract): when
      // the encoder provides it, cells format like FieldDisplay.
      columns: ArrayOf(
        EmptyObject.extend({
          label: Str,
          path: Str,
          format: formatEnum(),
          // 1.1 presentation hints — static values, read per row by the
          // grid itself (link/badge paths are row-relative).
          align: EnumOf(["start", "center", "end"]).optional(),
          mono: Bool.optional(),
          badge: RecordAny.optional(),
          link: RecordAny.optional(),
          // 1.7: the header is a sort control (the field is in the query's
          // sortable allowlist), driven by the grid's `sort`.
          sortable: Bool.optional(),
        }),
      ),
      // Row arrays / a "/rows" binding / a function call — DynamicValue's
      // union covers the literal array, the {path} binding and the
      // {call} envelope, so the whole prop classifies DYNAMIC like the
      // hand-built union did.
      rows: DynamicValueSchema.optional(),
      rowId: Str.optional(),
      label: DynamicStringSchema.nullable().optional(),
      // Flat envelope shape the admin encoder emits (`admin_row_actions/2`):
      // `action` is the client action NAME string ("view_record",
      // "start_edit", "invoke") and `context` carries literal +
      // row-relative {"path": "id"} refs. Deliberately static values — the
      // DataGrid resolves the context against each clicked row's base path
      // itself, which the binder's component-scoped ACTION resolution
      // cannot do.
      rowActions: ArrayOf(
        EmptyObject.extend({
          label: DynamicStringSchema,
          action: Str,
          context: RecordAny.optional(),
          destructive: Bool.optional(),
          // 1.2: the row-relative per-row visibility of a visible_when
          // action (`_visible_<action>`: a non-empty list = offered), and
          // the prompt a prompt_fields action collects first —
          // {content, title, confirmLabel, open}. Static, like the rest of
          // the entry: the grid resolves them against the clicked row.
          visiblePath: Str.optional(),
          prompt: RecordAny.optional(),
        }),
      ).optional(),
      // 1.1: the row's primary action envelope (same flat shape as a
      // rowActions entry), dispatched on whole-row activation.
      rowClick: EmptyObject.extend({
        label: DynamicStringSchema,
        action: Str,
        context: RecordAny.optional(),
      }).optional(),
      // 1.7: {path, action} — the current sort's binding ({field, dir} or
      // null) and the query envelope a sortable header dispatches. Static,
      // like rowActions: the grid reads the path and resolves the envelope
      // itself at click time.
      sort: RecordAny.optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    emptyState: EmptyObject.extend({
      message: DynamicStringSchema.nullable().optional(),
      child: Str.optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    pagination: EmptyObject.extend({
      page: DynamicNumberSchema.nullable().optional(),
      pageSize: DynamicNumberSchema.nullable().optional(),
      total: DynamicNumberSchema.nullable().optional(),
      hasNext: DynamicBooleanSchema.nullable().optional(),
      visible: DynamicBooleanSchema.nullable().optional(),
      previousVisible: DynamicBooleanSchema.nullable().optional(),
      nextVisible: DynamicBooleanSchema.nullable().optional(),
      rangeText: DynamicStringSchema.nullable().optional(),
      label: DynamicStringSchema.nullable().optional(),
      prevAction: bareEvent().optional(),
      // The encoder emits `previousAction` (the contract name); `prevAction`
      // stays accepted for older emissions.
      previousAction: bareEvent().optional(),
      nextAction: bareEvent().optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    recordPanel: EmptyObject.extend({
      mode: DynamicStringSchema.nullable().optional(),
      title: DynamicStringSchema.nullable().optional(),
      recordId: DynamicValueSchema.nullable().optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    fieldDisplay: EmptyObject.extend({
      label: DynamicStringSchema,
      value: DynamicValueSchema.nullable().optional(),
      format: formatEnum(),
      // 1.1: the field's reference link(s), bound like the value.
      link: DynamicValueSchema.nullable().optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    formSection: EmptyObject.extend({
      title: DynamicStringSchema.nullable().optional(),
      columns: Num.int().min(1).max(6).optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    actionBar: EmptyObject.extend({
      primaryLabel: DynamicStringSchema.nullable().optional(),
      busy: DynamicBooleanSchema.nullable().optional(),
      destructive: Bool.optional(),
      // Emitted as {"event": submit_event} — the frozen submit_form
      // envelope, binder-resolved into a callable (ActionSchema classifies
      // ACTION via its REF description and its {event} union option).
      action: ActionSchema.optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    statusBanner: EmptyObject.extend({
      kind: DynamicStringSchema.nullable().optional(),
      message: DynamicStringSchema.nullable().optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    // 1.3: the calendar over a display :calendar table. `window` binds the
    // table's /query/<table>/window state (an object, so DynamicValue);
    // `windowAction` is the bare query event the calendar dispatches with
    // `anchor` or `date` added (like pagination's page envelopes).
    calendarView: EmptyObject.extend({
      label: DynamicStringSchema.nullable().optional(),
      granularity: Str.optional(),
      granularities: Any.optional(),
      window: DynamicValueSchema.optional(),
      windowAction: bareEvent().optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    // 1.4: a live diagram. `source` is the static mermaid text; `markers`
    // (keyed by node id) and `nodes` (the fallback list) bind the
    // /diagram/<name> state, `error` its unavailable message.
    liveDiagram: EmptyObject.extend({
      label: DynamicStringSchema.nullable().optional(),
      description: DynamicStringSchema.nullable().optional(),
      source: Str.optional(),
      markers: DynamicValueSchema.optional(),
      nodes: DynamicValueSchema.optional(),
      error: DynamicStringSchema.nullable().optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    // Args of the catalog's openSurface client function.
    openSurfaceArgs: EmptyObject.extend({
      surface: Str,
      recordId: Any.optional(),
      query: Any.optional(),
    }),

    confirmDialog: EmptyObject.extend({
      title: DynamicStringSchema.nullable().optional(),
      body: DynamicStringSchema.nullable().optional(),
      confirmLabel: DynamicStringSchema.nullable().optional(),
      destructive: Bool.optional(),
      action: ActionSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),
  };
}

// ---------------------------------------------------------------------------
// Shared element helpers
// ---------------------------------------------------------------------------

function str(value) {
  return value === null || value === undefined ? "" : String(value);
}

/** The cell alignment class of a DataGrid column (`align` hint). */
function alignClass(column) {
  if (column?.align === "end") return "align-end";
  if (column?.align === "center") return "align-center";
  return "";
}

/** Merges check-driven validation errors with the /errors state. */
function fieldErrors(props, selfError) {
  const errors = [];
  if (selfError) errors.push(selfError);
  if (Array.isArray(props?.validationErrors)) {
    for (const message of props.validationErrors) {
      if (message && !errors.includes(message)) errors.push(String(message));
    }
  }
  return errors;
}

/**
 * Normalizes a row-action entry into a raw `{event: {name, context}}`
 * envelope ready for resolveEventContext + dispatchAction. Prefers the flat
 * shape the admin encoder emits (`{label, action: <name>, context}`); a
 * legacy nested `{label, action: {event: ...}}` is tolerated defensively.
 */
function rowActionEnvelope(entry) {
  if (!entry || typeof entry !== "object") return null;
  if (typeof entry.action === "string") {
    return {event: {name: entry.action, context: entry.context || {}}};
  }
  const nested = entry.action;
  if (nested && typeof nested === "object" && nested.event && typeof nested.event.name === "string") {
    return nested;
  }
  return null;
}

/**
 * Whether a row action is offered on `row`: entries without a `visiblePath`
 * always are; otherwise the row's value there must be a non-empty list (the
 * server-computed `_visible_<action>` slot) or `true`. Hiding is a
 * rendering concern only — the server re-checks every invoke.
 */
function rowActionVisible(action, row) {
  const path = action?.visiblePath;
  if (typeof path !== "string" || path === "") return true;
  const value = getByPath(row, path);
  if (value === undefined) return true;
  if (Array.isArray(value)) return value.length > 0;
  return value === true;
}

/**
 * The AshA2ui form-error subscription shared by the a11y-hardened inputs:
 * derives `/errors/<field>` from the input's `/form/<field>` value binding
 * and keeps `el._amErrText` current. Purely additive to the controller's own
 * prop subscriptions.
 */
function syncFieldError(el) {
  const context = el.context;
  const raw = context?.componentModel?.properties;
  const valuePath = raw?.value?.path;
  const match = typeof valuePath === "string" ? /^\/form\/(.+)$/.exec(valuePath) : null;
  const errorPath = match ? `/errors/${match[1]}` : null;

  if (errorPath === el._amErrPath) return;

  if (el._amErrUnsub) {
    el._amErrUnsub.unsubscribe();
    el._amErrUnsub = null;
  }
  el._amErrPath = errorPath;
  el._amErrText = "";

  if (errorPath && context?.dataContext) {
    const dataModel = context.dataContext.surface.dataModel;
    el._amErrUnsub = dataModel.subscribe(errorPath, (value) => {
      el._amErrText = errorText(value);
      el.requestUpdate();
    });
    el._amErrText = errorText(dataModel.get(errorPath));
  }
}

function teardownFieldError(el) {
  if (el._amErrUnsub) {
    el._amErrUnsub.unsubscribe();
    el._amErrUnsub = null;
  }
  el._amErrPath = null;
  el._amErrText = "";
}

function errorText(value) {
  if (value === null || value === undefined || value === "") return "";
  if (Array.isArray(value)) {
    return value.filter((item) => item !== null && item !== undefined && item !== "").join(" · ");
  }
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

/**
 * Reconstructs the frozen submit_form context (see the basic emission's
 * `submit_button/2` / `submit_event/1`): `/form` values + `/form/id`
 * recordId, plus the `/query` and `/context` bindings whenever the surface's
 * data model carries them.
 */
function buildSubmitFormContext(surface) {
  const context = {
    values: {path: "/form"},
    recordId: {path: "/form/id"},
  };
  const dataModel = surface.dataModel;
  if (dataModel.get("/query") !== null && dataModel.get("/query") !== undefined) {
    context.query = {path: "/query"};
  }
  if (dataModel.get("/context") !== null && dataModel.get("/context") !== undefined) {
    context.contexts = {path: "/context"};
  }
  return context;
}

// ---------------------------------------------------------------------------
// Element definitions
// ---------------------------------------------------------------------------

/**
 * Defines every admin custom element (idempotent across LiveView remounts
 * and hot reloads). All classes are created inside the factory so they close
 * over the host's single Lit instance and the freshly-built APIs.
 */
function defineAdminElements(deps, {adminApis}) {
  const {basicCatalog, A2uiLitElement, A2uiController, lit} = deps;
  const {html, css, nothing} = lit;
  const {shared, buttons, content} = createAdminStyles(css);

  // --- shared read-only content: links, values -------------------------------

  /** Renders reference link(s) (see linkEntries): one link inline, several
   * as a wrapping list. */
  function renderLinks(element, links) {
    const rendered = links.map((link) => renderLink(element, link));
    return rendered.length === 1 ? rendered[0] : html`<span class="am-links">${rendered}</span>`;
  }

  /**
   * One reference link. With a server-provided `href` it is a real anchor
   * (modifier/middle clicks keep the browser's open-in-new-tab behavior);
   * a plain activation is handed to the host as an openSurface request
   * (requestOpenSurface) instead of a full page load. Without an href it is
   * a link-styled button.
   */
  function renderLink(element, link) {
    const label = str(link.label) || str(link.recordId);
    const activate = (event) => {
      if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      requestOpenSurface(deps, openSurfaceArgs(link), {
        surfaceId: element.context?.dataContext?.surface?.id,
        source: element,
        href: link.href,
      });
    };

    if (typeof link.href === "string" && link.href !== "") {
      return html`<a class="am-link" href=${link.href} data-surface=${link.surface} @click=${activate}
        >${label}</a
      >`;
    }
    return html`<button type="button" class="am-link" data-surface=${link.surface} @click=${activate}>
      ${label}
    </button>`;
  }

  /**
   * Read-only value: text-formatted values that are lists (arrays, or
   * bulleted multi-line text) render as a list, other multi-line text keeps
   * its line breaks; everything else is the formatted display string.
   */
  function renderValue(value, format) {
    if (!format || format === "text") {
      const items = listItems(value);
      if (items) return html`<ul class="am-list">${items.map((item) => html`<li>${item}</li>`)}</ul>`;
      if (typeof value === "string" && value.includes("\n")) {
        return html`<span class="am-multiline">${value}</span>`;
      }
    }
    return formatDisplayValue(value, format);
  }

  // --- zero jank: instant action acknowledgement -----------------------------
  //
  // Components that dispatch action envelopes acknowledge the click at 0 RTT
  // (disabled + spinner), then settle when the surface's data model next
  // reports an outcome. Every AshA2ui action these components dispatch
  // (submits, invokes, task open/cancel, context select/clear, and every
  // rejection) writes at least one of /ui/feedback (both wire versions) or
  // /ui/response (v1.0 wire), so subscribing to both settles on the first
  // outcome. Both are subscribed as OBJECT paths through
  // subscribeActionOutcomes (see "Action outcomes" in ash_a2ui_catalog.js),
  // so the settle fires on every outcome path write, also one that leaves
  // the value unchanged. view_record and cancel_record_task write the
  // already-clear feedback; a primitive leaf like /ui/feedback/message
  // only fires when its value changes, which left View spinning after
  // View + Cancel. A whole-model refresh (a PubSub push or URL-state change
  // writing "/") is not an outcome and does not settle. No styling round
  // trip, no phx-*-loading — these components own their shadow DOM.
  const SETTLE_PATHS = ["/ui/feedback", "/ui/response"];

  function markActionBusy(component) {
    if (component._amSettleUnsubscribes) return;
    const surface = component.surface;
    if (!surface || !surface.dataModel || typeof surface.dataModel.subscribe !== "function") {
      return;
    }
    component._amSettleUnsubscribes = subscribeActionOutcomes(surface.dataModel, SETTLE_PATHS, () =>
      settleActionBusy(component),
    );
  }

  function settleActionBusy(component) {
    dropActionBusySubscriptions(component);
    if (typeof component.onActionSettled === "function") component.onActionSettled();
    component.requestUpdate();
  }

  function dropActionBusySubscriptions(component) {
    if (!component._amSettleUnsubscribes) return;
    unsubscribeActionOutcomes(component._amSettleUnsubscribes);
    component._amSettleUnsubscribes = null;
  }

  // Shared styles for the a11y-hardened inputs. Declared BEFORE the define
  // calls: class static field initializers evaluate eagerly, so anything
  // their `static styles` arrays reference must already be initialized.
  const inputBaseStyles = css`
    :host {
      display: block;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--am-space-2xs);
      min-width: 0;
    }
    .field-label {
      font-size: var(--am-font-size-s);
      font-weight: var(--am-font-weight-medium);
      color: var(--am-text);
      width: fit-content;
    }
    .control {
      font: inherit;
      font-size: var(--am-font-size-m);
      color: var(--am-text);
      background: var(--am-surface);
      border: 1px solid var(--am-border-strong);
      border-radius: var(--am-radius-m);
      padding: var(--am-space-xs) var(--am-space-s);
      min-height: 2.25rem;
      width: 100%;
    }
    .control:hover:not([disabled]) {
      border-color: var(--am-text-faint);
    }
    .control:focus {
      outline: none;
      border-color: var(--am-primary);
      box-shadow: 0 0 0 3px color-mix(in srgb, var(--am-primary) 15%, transparent);
    }
    .control[aria-invalid="true"] {
      border-color: var(--am-error);
    }
    textarea.control {
      min-height: 4.5rem;
      resize: vertical;
    }
    .error {
      color: var(--am-error);
      font-size: var(--am-font-size-s);
      font-weight: var(--am-font-weight-medium);
    }
    .choices {
      display: flex;
      flex-direction: column;
      gap: var(--am-space-xs);
      margin: 0;
      padding: 0;
      border: none;
      min-inline-size: 0;
    }
    .choices-legend {
      font-size: var(--am-font-size-s);
      font-weight: var(--am-font-weight-medium);
      color: var(--am-text);
      padding: 0;
    }
    .choice {
      display: flex;
      align-items: center;
      gap: var(--am-space-xs);
      font-size: var(--am-font-size-m);
      font-weight: var(--am-font-weight-regular);
    }
    .choice input {
      width: 1rem;
      height: 1rem;
      accent-color: var(--am-primary);
    }
  `;

  defineEntityPage();
  defineDataGrid();
  defineEmptyState();
  definePagination();
  defineRecordPanel();
  defineFieldDisplay();
  defineFormSection();
  defineActionBar();
  defineStatusBanner();
  defineConfirmDialog();
  defineCalendarView();
  defineLiveDiagram();
  defineTextField();
  defineCheckBox();
  defineChoicePicker();
  defineDateTimeInput();

  /** Resolves the basic-catalog Api for an overridden input kind. */
  function basicInputApi(name) {
    // The catalog entry for this kind was swapped in createAshAdminCatalog
    // to {name, schema, tagName}; the element binds to the same schema, so
    // validation + binding behavior are identical to the basic input.
    const entry = basicCatalog.components.get(name);
    if (!entry) {
      throw new Error(`createAshAdminCatalog: basicCatalog has no ${name} component to extend.`);
    }
    return {name: entry.name, schema: entry.schema, tagName: INPUT_OVERRIDE_TAGS[name]};
  }

  // --- EntityPage: page shell ---------------------------------------------

  function defineEntityPage() {
    const tag = TAGS.entityPage;
    if (customElements.get(tag)) return;

    class AshAdminEntityPage extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .page-header {
            margin: 0 0 var(--am-space-xl);
          }
          .page-title {
            margin: 0;
            font-size: var(--am-font-size-xl);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
            letter-spacing: -0.01em;
          }
          .page-description {
            margin: var(--am-space-2xs) 0 0;
            color: var(--am-text-muted);
            font-size: var(--am-font-size-m);
            max-width: 60ch;
          }
          .page-body {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-xl);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.entityPage);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        return html`
          ${props.headerVisible === false
            ? nothing
            : html`<header class="page-header">
                <h1 class="page-title">${str(props.title)}</h1>
                ${props.description
                  ? html`<p class="page-description">${str(props.description)}</p>`
                  : nothing}
              </header>`}
          <div class="page-body">
            ${childRefs(props.children).map((ref) => html`${this.renderNode(ref)}`)}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminEntityPage);
  }

  // --- DataGrid: table / card collection -----------------------------------

  function defineDataGrid() {
    const tag = TAGS.dataGrid;
    if (customElements.get(tag)) return;

    class AshAdminDataGrid extends A2uiLitElement {
      constructor() {
        super();
        // Destructive row action awaiting confirmation:
        // {envelope, basePath, label}
        this.pendingConfirm = null;
        this._confirmEl = null;
        // Zero jank: the row action whose envelope is in flight —
        // {row, label} — disabled + spinner from click to outcome write.
        this._amBusyRowAction = null;
        this._amSettleUnsubscribes = null;
        // The open prompt dialog of a prompt_fields row action:
        // {entry, rowIdentity, busy, error, restoreFocus, focused}.
        this._amPrompt = null;
      }

      static styles = [
        shared,
        buttons,
        content,
        css`
          :host {
            display: block;
            container-type: inline-size;
            /* 1.1 grid tokens (see ash_admin_tokens.js) — no hardcoded
             * lines or header styling: every value is themeable. */
            --am-grid-max-height: var(--ash-admin-grid-max-height, none);
            --am-grid-radius: var(--ash-admin-grid-radius, var(--am-radius-m));
            --am-grid-shadow: var(--ash-admin-grid-shadow, var(--am-shadow-1));
            --am-grid-header-bg: var(--ash-admin-grid-header-background, var(--am-surface-sunken));
            --am-grid-header-text: var(--ash-admin-grid-header-text, var(--am-text));
            --am-grid-header-size: var(--ash-admin-grid-header-font-size, var(--am-font-size-s));
            --am-grid-header-weight: var(
              --ash-admin-grid-header-font-weight,
              var(--am-font-weight-bold)
            );
            --am-grid-header-transform: var(--ash-admin-grid-header-transform, none);
            --am-grid-header-tracking: var(--ash-admin-grid-header-tracking, normal);
            --am-grid-row-active: var(
              --ash-admin-grid-row-active,
              color-mix(in srgb, var(--am-hover-tint) 70%, var(--am-primary))
            );
          }
          /* Scroll frame: the table scrolls inside it (both axes) and the
           * header sticks — opaque, so rows never show through it. */
          .grid-frame {
            max-height: var(--am-grid-max-height);
            overflow: auto;
            border: var(--am-border-width) solid var(--am-border);
            border-radius: var(--am-grid-radius);
            background: var(--am-surface);
            box-shadow: var(--am-grid-shadow);
          }
          .grid-table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: var(--am-font-size-m);
            background: var(--am-surface);
          }
          .grid-table thead th {
            position: sticky;
            top: 0;
            z-index: 1;
            text-align: left;
            font-size: var(--am-grid-header-size);
            font-weight: var(--am-grid-header-weight);
            letter-spacing: var(--am-grid-header-tracking);
            text-transform: var(--am-grid-header-transform);
            color: var(--am-grid-header-text);
            background: var(--am-grid-header-bg);
            padding: var(--am-space-s) var(--am-space-m);
            border-bottom: var(--am-border-width) solid var(--am-border-strong);
            white-space: nowrap;
          }
          .grid-table thead th .sort-button {
            all: unset;
            display: inline-flex;
            align-items: center;
            gap: var(--am-space-xs);
            cursor: pointer;
            font: inherit;
            letter-spacing: inherit;
            text-transform: inherit;
            color: inherit;
          }
          .grid-table thead th .sort-button:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          .grid-table thead th .sort-mark {
            opacity: 0.5;
          }
          .grid-table thead th[aria-sort="ascending"] .sort-mark,
          .grid-table thead th[aria-sort="descending"] .sort-mark {
            opacity: 1;
          }
          .grid-table tbody tr:hover {
            background: var(--am-hover-tint);
          }
          .grid-table tbody tr.is-clickable {
            cursor: pointer;
          }
          .grid-table tbody tr.is-clickable:active {
            background: var(--am-grid-row-active);
          }
          .grid-table tbody tr.is-clickable:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: -2px;
          }
          .grid-table td,
          .grid-table th[scope="row"] {
            padding: var(--am-space-s) var(--am-space-m);
            border-bottom: var(--am-border-width) solid var(--am-border);
            text-align: left;
            vertical-align: top;
          }
          .grid-table th[scope="row"] {
            font-weight: var(--am-font-weight-medium);
            white-space: nowrap;
          }
          .grid-table tbody tr:last-child td,
          .grid-table tbody tr:last-child th {
            border-bottom: none;
          }
          .grid-table .align-end {
            text-align: right;
            font-variant-numeric: tabular-nums;
          }
          .grid-table .align-center {
            text-align: center;
          }
          .cell-actions {
            text-align: right;
          }
          /* Row actions wrap inside their cell instead of pushing the
           * table past its frame. */
          .row-actions {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--am-space-2xs);
          }
          /* Prompt dialog (prompt_fields row actions). */
          .prompt-overlay {
            position: fixed;
            inset: 0;
            z-index: 80;
            display: grid;
            place-items: center;
            padding: var(--am-space-l);
            background: rgb(15 23 42 / 0.45);
          }
          .prompt-dialog {
            width: min(32rem, 100%);
            max-height: calc(100vh - 2 * var(--am-space-l));
            overflow: auto;
            background: var(--am-surface);
            color: var(--am-text);
            border: 1px solid var(--am-border);
            border-radius: var(--am-radius-l);
            box-shadow: var(--am-shadow-3);
            padding: var(--am-space-xl);
          }
          .prompt-focus-guard {
            position: absolute;
            width: 1px;
            height: 1px;
            overflow: hidden;
            clip-path: inset(50%);
            outline: none;
          }
          .prompt-title {
            margin: 0 0 var(--am-space-m);
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
          }
          .prompt-title:focus {
            outline: none;
          }
          .prompt-title:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          .prompt-error {
            margin: 0 0 var(--am-space-m);
            color: var(--am-error);
            font-size: var(--am-font-size-s);
            font-weight: var(--am-font-weight-medium);
          }
          .prompt-actions {
            display: flex;
            justify-content: flex-end;
            gap: var(--am-space-s);
            margin-top: var(--am-space-l);
          }
          .grid-cards {
            display: none;
            list-style: none;
            margin: 0;
            padding: 0;
            gap: var(--am-space-m);
          }
          .card {
            background: var(--am-surface);
            border: var(--am-border-width) solid var(--am-border);
            border-radius: var(--am-radius-m);
            padding: var(--am-space-m) var(--am-space-l);
            box-shadow: var(--am-shadow-1);
          }
          .card.is-clickable {
            cursor: pointer;
          }
          .card-fields {
            margin: 0;
            display: grid;
            gap: var(--am-space-xs) var(--am-space-l);
            grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr));
          }
          .card-field dt {
            font-size: var(--am-grid-header-size);
            font-weight: var(--am-grid-header-weight);
            letter-spacing: var(--am-grid-header-tracking);
            text-transform: var(--am-grid-header-transform);
            color: var(--am-text-muted);
          }
          .card-field dd {
            margin: 0;
            min-width: 0;
            overflow-wrap: anywhere;
          }
          .card-actions {
            display: flex;
            justify-content: flex-end;
            gap: var(--am-space-2xs);
            margin-top: var(--am-space-m);
          }
          .grid-empty {
            display: grid;
            place-items: center;
            min-height: 12rem;
          }
          .no-records {
            margin: 0;
            color: var(--am-text-muted);
          }
          .grid-pagination {
            display: flex;
            justify-content: center;
            margin-top: var(--am-space-m);
          }
          /* Real table at ≥ 48rem, card list below. Browsers without
           * container queries degrade to the table. */
          @container (max-width: 47.99rem) {
            .grid-frame {
              display: none;
            }
            .grid-cards {
              display: grid;
              grid-template-columns: 1fr;
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.dataGrid);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        this.syncConfirmDialog();
        if (this._amPrompt && !this._amPrompt.focused) {
          // Prompt opened: move focus into the dialog.
          this._amPrompt.focused = true;
          this.renderRoot?.querySelector("[data-prompt-heading]")?.focus();
        }
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        dropActionBusySubscriptions(this);
        if (this._confirmEl && this._confirmEl.parentNode) {
          this._confirmEl.parentNode.removeChild(this._confirmEl);
        }
      }

      onActionSettled() {
        this._amBusyRowAction = null;
        const prompt = this._amPrompt;
        if (!prompt || !prompt.busy) return;
        // The outcome batch is processed synchronously; read it once the
        // whole batch has landed (the /ui/response write of a v1.0 reply
        // precedes its /ui/feedback mirror).
        Promise.resolve().then(() => {
          if (this._amPrompt !== prompt) return;
          prompt.busy = false;
          const dataModel = this.surface?.dataModel;
          const kind = dataModel?.get("/ui/feedback/kind");
          if (kind === "success") {
            this.closePrompt();
          } else {
            prompt.error = str(dataModel?.get("/ui/feedback/message"));
            this.requestUpdate();
          }
        });
      }

      get surface() {
        return this.context?.dataContext?.surface;
      }

      /** Raw rows binding path — anchors each row action's relative refs. */
      get rowsBasePath() {
        const raw = this.context?.componentModel?.properties?.rows;
        return raw && typeof raw.path === "string" ? raw.path : null;
      }

      childType(ref) {
        try {
          return this.surface?.componentsModel?.get(ref.id)?.type ?? null;
        } catch {
          return null;
        }
      }

      /** Ids of the grid children that are prompt contents (rendered only
       * inside their prompt dialog). */
      promptContentIds() {
        const rowActions = this.controller?.props?.rowActions;
        const ids = new Set();
        for (const action of Array.isArray(rowActions) ? rowActions : []) {
          if (typeof action?.prompt?.content === "string") ids.add(action.prompt.content);
        }
        return ids;
      }

      partitionChildren() {
        const props = this.controller?.props;
        const promptIds = this.promptContentIds();
        const empty = [];
        const pagination = [];
        const prompts = [];
        const rest = [];
        for (const ref of childRefs(props?.children)) {
          const type = this.childType(ref);
          if (promptIds.has(ref.id)) prompts.push(ref);
          else if (type === "emptyState") empty.push(ref);
          else if (type === "pagination") pagination.push(ref);
          else rest.push(ref);
        }
        return {empty, pagination, prompts, rest};
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const columns = Array.isArray(props.columns) ? props.columns : [];
        const rows = Array.isArray(props.rows) ? props.rows : [];
        const rowActions = Array.isArray(props.rowActions) ? props.rowActions : [];
        const label = str(props.label);
        const {empty, pagination, prompts, rest} = this.partitionChildren();

        return html`
          <div class="grid-root">
            ${rows.length === 0
              ? html`
                  <div class="grid-empty">
                    ${empty.length > 0
                      ? empty.map((ref) => html`${this.renderNode(ref)}`)
                      : html`<p class="no-records">
                          ${label ? `${label}: no records` : "No records"}
                        </p>`}
                  </div>
                `
              : html`
                  ${this.renderTable(columns, rows, rowActions, label)}
                  ${this.renderCards(columns, rows, rowActions, label)}
                `}
            ${pagination.length > 0
              ? html`<div class="grid-pagination">
                  ${pagination.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`
              : nothing}
            ${rest.map((ref) => html`${this.renderNode(ref)}`)}
            ${this._amPrompt ? this.renderPrompt(prompts) : nothing}
          </div>
        `;
        // The ConfirmDialog is mounted imperatively in updated() — dynamic
        // tag names cannot appear in Lit templates without unsafeStatic,
        // which is not part of this factory's deps contract.
      }

      renderTable(columns, rows, rowActions, label) {
        const hasActions = rowActions.length > 0;
        return html`
          <div class="grid-frame" part="frame">
            <table class="grid-table" aria-label=${label || "Records"}>
              <thead>
                <tr>
                  ${columns.map((column) => this.renderHeader(column))}
                  ${hasActions
                    ? html`<th scope="col"><span class="sr-only">Actions</span></th>`
                    : nothing}
                </tr>
              </thead>
              <tbody>
                ${rows.map(
                  (row, index) => this.renderTableRow(row, index, columns, rowActions, hasActions),
                )}
              </tbody>
            </table>
          </div>
        `;
      }

      /** The column's current sort direction ("asc" | "desc") or null. */
      sortDirection(column) {
        const path = this.controller?.props?.sort?.path;
        const current = path ? this.surface?.dataModel?.get(path) : null;
        return current && current.field === column.path ? current.dir : null;
      }

      /**
       * A header cell: plain text, or (1.7) for a sortable column a button
       * with the label and a sort mark, the th carrying aria-sort.
       */
      renderHeader(column) {
        const label = str(column.label);
        if (!column.sortable || !this.controller?.props?.sort) {
          return html`<th scope="col" class=${alignClass(column)}>${label}</th>`;
        }
        const dir = this.sortDirection(column);
        const ariaSort = dir === "asc" ? "ascending" : dir === "desc" ? "descending" : "none";
        const mark = dir === "asc" ? "\u2191" : dir === "desc" ? "\u2193" : "\u2195";
        return html`<th scope="col" class=${alignClass(column)} aria-sort=${ariaSort}>
          <button
            type="button"
            class="sort-button"
            data-sort=${ariaSort}
            @click=${() => this.sortBy(column)}
          >
            <span>${label}</span><span class="sort-mark" aria-hidden="true">${mark}</span>
          </button>
        </th>`;
      }

      /**
       * Dispatches the grid's sort envelope with the clicked column's sort:
       * ascending first, then toggling. The query state is resolved as for
       * Apply and the new sort replaces its `sort`; the server's refresh
       * rewrites the bound sort, which re-marks the header.
       */
      sortBy(column) {
        const sort = this.controller?.props?.sort;
        const surface = this.surface;
        if (!sort?.action || !surface || !this.context?.componentModel) return;
        const dir = this.sortDirection(column) === "asc" ? "desc" : "asc";
        const resolved = resolveEventContext(
          {event: {name: sort.action.name, context: sort.action.context || {}}},
          surface.dataModel,
          "/",
        );
        const context = resolved.event.context;
        context.query = {...(context.query || {}), sort: {field: column.path, dir}};
        surface.dispatchAction(resolved, this.context.componentModel.id);
      }

      renderTableRow(row, index, columns, rowActions, hasActions) {
        const rowId = this.rowIdentity(row, index);
        const clickable = this.rowClickable();
        return html`
          <tr
            id="row-${rowId}"
            class=${clickable ? "is-clickable" : ""}
            tabindex=${clickable ? "0" : nothing}
            @click=${clickable ? (event) => this.onRowClick(event, index) : nothing}
            @keydown=${clickable ? (event) => this.onRowKey(event, index) : nothing}
          >
            ${columns.map((column, columnIndex) => {
              const cell = this.renderCell(row, column);
              return columnIndex === 0
                ? html`<th scope="row" class=${alignClass(column)}>${cell}</th>`
                : html`<td class=${alignClass(column)}>${cell}</td>`;
            })}
            ${hasActions
              ? html`<td class="cell-actions">${this.renderRowActions(row, index, rowActions)}</td>`
              : nothing}
          </tr>
        `;
      }

      renderCards(columns, rows, rowActions, label) {
        return html`
          <ul class="grid-cards" aria-label=${label || "Records"}>
            ${rows.map((row, index) => this.renderCard(row, index, columns, rowActions))}
          </ul>
        `;
      }

      renderCard(row, index, columns, rowActions) {
        const hasActions = rowActions.length > 0;
        const clickable = this.rowClickable();
        return html`
          <li
            class="card ${clickable ? "is-clickable" : ""}"
            @click=${clickable ? (event) => this.onRowClick(event, index) : nothing}
          >
            <dl class="card-fields">
              ${columns.map(
                (column) => html`
                  <div class="card-field">
                    <dt>${str(column.label)}</dt>
                    <dd>${this.renderCell(row, column)}</dd>
                  </div>
                `,
              )}
            </dl>
            ${hasActions
              ? html`<div class="card-actions">${this.renderRowActions(row, index, rowActions)}</div>`
              : nothing}
          </li>
        `;
      }

      /**
       * One cell: the column's link(s) when the row carries them (pruned
       * per actor server-side — absent means plain value), a toned status
       * pill for badge columns, identifiers in mono, lists as lists, and
       * everything else through the format rules.
       */
      renderCell(row, column) {
        if (column.link && typeof column.link.path === "string") {
          const links = linkEntries(getByPath(row, column.link.path));
          if (links.length > 0) return renderLinks(this, links);
        }

        if (column.badge && typeof column.badge.path === "string") {
          const text = getByPath(row, column.badge.path);
          if (text === null || text === undefined || text === "") return "—";
          const tone =
            typeof column.badge.tonePath === "string"
              ? badgeTone(getByPath(row, column.badge.tonePath))
              : "neutral";
          return html`<span class="am-badge" data-tone=${tone}>${str(text)}</span>`;
        }

        const raw = getByPath(row, column.path);
        if (!column.format) {
          const items = listItems(raw);
          if (items) return items.join(", ");
        }
        const value = this.cellValue(row, column);
        return column.mono === true && value !== "—"
          ? html`<span class="am-mono">${value}</span>`
          : value;
      }

      rowClickable() {
        const rowClick = this.controller?.props?.rowClick;
        return !!(rowClick && typeof rowClick.action === "string");
      }

      /** Whole-row activation dispatches the row's primary action — unless
       * the click landed on something interactive of its own (a row
       * button, a link) or finished a text selection. */
      onRowClick(event, index) {
        const rowClick = this.controller?.props?.rowClick;
        if (!rowClick) return;
        for (const node of event.composedPath()) {
          if (node === event.currentTarget) break;
          if (node.tagName && /^(A|BUTTON|INPUT|SELECT|TEXTAREA|LABEL)$/.test(node.tagName)) return;
        }
        const selection = globalThis.getSelection ? globalThis.getSelection() : null;
        if (selection && String(selection).trim() !== "") return;
        this.onRowAction(rowClick, index);
      }

      onRowKey(event, index) {
        if (event.key !== "Enter" || event.target !== event.currentTarget) return;
        event.preventDefault();
        this.onRowAction(this.controller?.props?.rowClick, index);
      }

      renderRowActions(row, index, rowActions) {
        const rowIdentity = this.rowIdentity(row, index);
        const offered = rowActions.filter((action) => rowActionVisible(action, row));
        return html`<div class="row-actions">${offered.map((action) => {
          const label = str(action?.label);
          const destructive = action?.destructive === true;
          const busy =
            this._amBusyRowAction !== null &&
            this._amBusyRowAction.row === rowIdentity &&
            this._amBusyRowAction.label === label;
          return html`
            <button
              type="button"
              class="am-btn am-btn-quiet am-btn-sm ${destructive ? "am-btn-danger" : ""}"
              ?disabled=${busy}
              aria-busy=${busy ? "true" : "false"}
              @click=${() => this.onRowAction(action, index)}
            >
              ${busy ? html`<span class="am-spinner" aria-hidden="true"></span>` : nothing}
              ${label}
            </button>
          `;
        })}</div>`;
      }

      // --- prompt dialog (prompt_fields row actions) -----------------------

      /** Opens the prompt of `action` for row `index`: the dialog shows the
       * prompt's content child and the server pre-fills its values
       * (`prompt`). Nothing is invoked until Confirm. */
      openPrompt(action, index) {
        const rows = this.controller?.props?.rows || [];
        this._amPrompt = {
          entry: action,
          rowIdentity: this.rowIdentity(rows[index], index),
          busy: false,
          error: "",
          restoreFocus: this.shadowRoot?.activeElement || document.activeElement,
          focused: false,
        };
        const open = rowActionEnvelope(action.prompt.open);
        if (open) this.dispatchRowAction(open, this.rowBasePath(index));
        this.requestUpdate();
      }

      closePrompt() {
        const prompt = this._amPrompt;
        this._amPrompt = null;
        this.requestUpdate();
        if (prompt?.restoreFocus?.isConnected) prompt.restoreFocus.focus();
      }

      /** Confirm: the entry's own invoke envelope (its `values` bind the
       * prompt state), resolved against the prompt's row — found again by
       * identity, since a refresh may have moved it. */
      confirmPrompt() {
        const prompt = this._amPrompt;
        if (!prompt || prompt.busy) return;
        const rows = this.controller?.props?.rows || [];
        const index = rows.findIndex(
          (row, rowIndex) => this.rowIdentity(row, rowIndex) === prompt.rowIdentity,
        );
        if (index === -1) {
          prompt.error = "This record is no longer listed.";
          this.requestUpdate();
          return;
        }
        const envelope = rowActionEnvelope(prompt.entry);
        if (!envelope) return;
        prompt.busy = true;
        prompt.error = "";
        this.markRowActionBusyByIdentity(prompt.entry, prompt.rowIdentity);
        this.dispatchRowAction(envelope, this.rowBasePath(index));
      }

      onPromptKey(event) {
        if (event.key === "Escape") {
          event.preventDefault();
          this.closePrompt();
          return;
        }
        if (event.key === "Tab") {
          // Focus trap over the dialog's own buttons (the inputs live in
          // nested shadow roots and take focus in between): Tab from the
          // last button wraps to the heading, Shift+Tab from the heading to
          // the last button. Shift+Tab from the first input lands on the
          // start guard, which does the same (onPromptGuardFocus).
          const last = this.lastPromptButton();
          if (!last) return;
          const active = this.shadowRoot?.activeElement;
          const heading = this.renderRoot.querySelector("[data-prompt-heading]");
          if (!event.shiftKey && active === last) {
            event.preventDefault();
            heading?.focus();
          } else if (event.shiftKey && active === heading) {
            event.preventDefault();
            last.focus();
          }
        }
      }

      lastPromptButton() {
        const buttons = [...this.renderRoot.querySelectorAll(".prompt-dialog button")].filter(
          (element) => !element.hasAttribute("disabled"),
        );
        return buttons[buttons.length - 1] ?? null;
      }

      onPromptGuardFocus() {
        (this.lastPromptButton() ?? this.renderRoot.querySelector("[data-prompt-heading]"))?.focus();
      }

      renderPrompt(promptRefs) {
        const prompt = this._amPrompt;
        const spec = prompt.entry.prompt || {};
        const ref = promptRefs.find((candidate) => candidate.id === spec.content);
        const title = str(spec.title) || str(prompt.entry.label);
        return html`
          <div
            class="prompt-overlay"
            @keydown=${(event) => this.onPromptKey(event)}
            @pointerdown=${(event) => {
              if (event.target === event.currentTarget) this.closePrompt();
            }}
          >
            <div class="prompt-dialog" role="dialog" aria-modal="true" aria-labelledby="am-prompt-title">
              <span
                class="prompt-focus-guard"
                tabindex="0"
                data-prompt-focus-guard
                @focus=${() => this.onPromptGuardFocus()}
              ></span>
              <h2 class="prompt-title" id="am-prompt-title" tabindex="-1" data-prompt-heading>
                ${title}
              </h2>
              ${prompt.error
                ? html`<p class="prompt-error" role="alert">${prompt.error}</p>`
                : nothing}
              ${ref ? html`${this.renderNode(ref)}` : nothing}
              <div class="prompt-actions">
                <button type="button" class="am-btn" @click=${() => this.closePrompt()}>Cancel</button>
                <button
                  type="button"
                  class="am-btn am-btn-primary"
                  ?disabled=${prompt.busy}
                  aria-busy=${prompt.busy ? "true" : "false"}
                  @click=${() => this.confirmPrompt()}
                >
                  ${prompt.busy ? html`<span class="am-spinner" aria-hidden="true"></span>` : nothing}
                  ${str(spec.confirmLabel) || "Confirm"}
                </button>
              </div>
            </div>
          </div>
        `;
      }

      /** Formats a cell: explicit column format wins; ISO-datetime-looking
       * strings format for readability; everything else uses text rules. */
      cellValue(row, column) {
        const value = getByPath(row, column.path);
        if (column.format) return formatDisplayValue(value, column.format);
        if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)) {
          return formatDisplayValue(value, "datetime");
        }
        return formatDisplayValue(value);
      }

      rowIdentity(row, index) {
        const rowIdProp = this.controller?.props?.rowId || "id";
        const value = getByPath(row, rowIdProp);
        return value === null || value === undefined ? `i${index}` : String(value);
      }

      rowBasePath(index) {
        return this.rowsBasePath ? `${this.rowsBasePath}/${index}` : "/";
      }

      onRowAction(action, index) {
        if (!action) return;
        const envelope = rowActionEnvelope(action);
        if (!envelope) return;

        if (action.prompt && typeof action.prompt.content === "string") {
          this.openPrompt(action, index);
          return;
        }

        if (action.destructive === true) {
          // Destructive actions gate behind the ConfirmDialog; confirming
          // dispatches this exact envelope unchanged.
          this.pendingConfirm = {
            envelope,
            basePath: this.rowBasePath(index),
            label: str(action.label),
            rowIdentity: this.rowIdentity((this.controller?.props?.rows || [])[index], index),
          };
          this.requestUpdate();
          return;
        }

        this.markRowActionBusy(action, index);
        this.dispatchRowAction(envelope, this.rowBasePath(index));
      }

      /** Zero jank: the clicked button acknowledges at 0 RTT; the data
       * model's next outcome write (SETTLE_PATHS) re-enables it. */
      markRowActionBusy(action, index) {
        const rows = this.controller?.props?.rows || [];
        this.markRowActionBusyByIdentity(action, this.rowIdentity(rows[index], index));
      }

      markRowActionBusyByIdentity(action, rowIdentity) {
        this._amBusyRowAction = {row: rowIdentity, label: str(action?.label)};
        markActionBusy(this);
        this.requestUpdate();
      }

      dispatchRowAction(envelope, basePath) {
        const surface = this.surface;
        if (!surface || !this.context?.componentModel) return;
        const resolved = resolveEventContext(envelope, surface.dataModel, basePath);
        surface.dispatchAction(resolved, this.context.componentModel.id);
      }

      /**
       * Mounts/unmounts the ConfirmDialog element imperatively. Setting its
       * reactive properties (title/body/confirmLabel/open) drives its own
       * Lit update lifecycle, including the focus trap and focus restore.
       */
      syncConfirmDialog() {
        const pending = this.pendingConfirm;

        if (!pending) {
          if (this._confirmEl && this._confirmEl.open) this._confirmEl.open = false;
          if (this._confirmEl && this._confirmEl.parentNode) {
            this._confirmEl.parentNode.removeChild(this._confirmEl);
          }
          return;
        }

        if (!this._confirmEl) {
          this._confirmEl = document.createElement(TAGS.confirmDialog);
          this._confirmEl.addEventListener("confirm", () => {
            const current = this.pendingConfirm;
            this.pendingConfirm = null;
            this.requestUpdate();
            if (current) {
              this.markRowActionBusyByIdentity({label: current.label}, current.rowIdentity);
              this.dispatchRowAction(current.envelope, current.basePath);
            }
          });
          this._confirmEl.addEventListener("cancel", () => {
            this.pendingConfirm = null;
            this.requestUpdate();
          });
        }

        const dialog = this._confirmEl;
        dialog.title = `${pending.label} this record?`;
        dialog.body = "This action cannot be undone.";
        dialog.confirmLabel = pending.label || "Confirm";
        dialog.destructive = true;

        if (!dialog.parentNode) this.renderRoot.appendChild(dialog);
        // Open last: the dialog's updated() focuses its heading once mounted.
        if (!dialog.open) dialog.open = true;
      }
    }

    customElements.define(tag, AshAdminDataGrid);
  }

  // --- EmptyState: zero results --------------------------------------------

  function defineEmptyState() {
    const tag = TAGS.emptyState;
    if (customElements.get(tag)) return;

    class AshAdminEmptyState extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .empty {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: var(--am-space-m);
            padding: var(--am-space-2xl) var(--am-space-xl);
            text-align: center;
          }
          .empty-glyph {
            display: grid;
            place-items: center;
            width: 3rem;
            height: 3rem;
            border-radius: var(--am-radius-pill);
            background: var(--am-surface-sunken);
            border: 1px solid var(--am-border);
            color: var(--am-text-faint);
          }
          .empty-message {
            margin: 0;
            color: var(--am-text-muted);
            font-size: var(--am-font-size-m);
            max-width: 40ch;
          }
          .empty-action {
            display: flex;
            gap: var(--am-space-s);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.emptyState);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const action = props.child
          ? [this.renderNode(props.child)]
          : childRefs(props.children).map((ref) => this.renderNode(ref));

        return html`
          <div class="empty">
            <span class="empty-glyph" aria-hidden="true">
              <svg
                viewBox="0 0 24 24"
                width="20"
                height="20"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M4 7h16M4 12h16M4 17h10"></path>
              </svg>
            </span>
            <p class="empty-message">${str(props.message)}</p>
            ${action.length > 0 ? html`<div class="empty-action">${action}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminEmptyState);
  }

  // --- Pagination: conditional navigation -----------------------------------

  function definePagination() {
    const tag = TAGS.pagination;
    if (customElements.get(tag)) return;

    class AshAdminPagination extends A2uiLitElement {
      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: block;
          }
          .pager {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: var(--am-space-m);
            flex-wrap: wrap;
          }
          .pager-status {
            display: inline-flex;
            align-items: baseline;
            gap: var(--am-space-s);
            font-size: var(--am-font-size-m);
          }
          .pager-current {
            font-weight: var(--am-font-weight-semibold);
          }
          .pager-range {
            color: var(--am-text-muted);
            font-size: var(--am-font-size-s);
          }
          .pager-chevron {
            font-size: 1em;
            line-height: 1;
          }
          /* 1.1: windowed page chips (shown when the total is known). */
          .pager-pages {
            display: inline-flex;
            align-items: center;
            gap: var(--am-space-2xs);
            flex-wrap: wrap;
          }
          .pager-chip {
            min-width: 2rem;
            min-height: 2rem;
            padding: 0 var(--am-space-xs);
            font: inherit;
            font-size: var(--am-font-size-s);
            font-weight: var(--am-font-weight-medium);
            font-variant-numeric: tabular-nums;
            color: var(--am-text);
            background: var(--ash-admin-pager-chip-background, var(--am-surface));
            border: var(--am-border-width) solid var(--ash-admin-pager-chip-border, var(--am-border));
            border-radius: var(--ash-admin-pager-chip-radius, var(--am-radius-s));
            box-shadow: var(--ash-admin-pager-chip-shadow, none);
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
          }
          .pager-chip:hover {
            background: var(--am-hover-tint);
          }
          .pager-chip[aria-current="page"] {
            cursor: default;
            color: var(--am-on-primary);
            background: var(--am-primary);
            border-color: var(--ash-admin-pager-chip-border, var(--am-primary));
            font-weight: var(--am-font-weight-bold);
          }
          .pager-gap {
            color: var(--am-text-muted);
            padding: 0 var(--am-space-2xs);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.pagination);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;
        if (props.visible !== true) return nothing;

        const showPrevious = props.previousVisible === true;
        const showNext = props.nextVisible === true;
        const page =
          props.page === null || props.page === undefined || props.page === ""
            ? NaN
            : Number(props.page);
        const label = str(props.label) || "Results";
        const totalPages = this.totalPages(props);

        if (Number.isFinite(page) && totalPages > 1) {
          return this.renderWindowed(props, page, totalPages, label, showPrevious, showNext);
        }

        return html`
          <nav class="pager" aria-label=${label}>
            ${showPrevious
              ? html`
                  <button
                    type="button"
                    class="am-btn am-btn-quiet am-btn-sm"
                    @click=${() => this.turnPage(-1)}
                  >
                    <span class="pager-chevron" aria-hidden="true">‹</span>
                    Previous
                  </button>
                `
              : nothing}
            <span class="pager-status">
              ${Number.isFinite(page)
                ? html`<span class="pager-current" aria-current="page">Page ${page}</span>`
                : nothing}
              ${props.rangeText
                ? html`<span class="pager-range">${str(props.rangeText)}</span>`
                : nothing}
            </span>
            ${showNext
              ? html`
                  <button
                    type="button"
                    class="am-btn am-btn-quiet am-btn-sm"
                    @click=${() => this.turnPage(1)}
                  >
                    Next
                    <span class="pager-chevron" aria-hidden="true">›</span>
                  </button>
                `
              : nothing}
          </nav>
        `;
      }

      /** Total page count from the bound total/pageSize (NaN when the
       * data layer could not count — the pager then stays prev/next). */
      totalPages(props) {
        const total = Number(props.total);
        const size = Number(props.pageSize);
        if (props.total === null || props.total === undefined || props.total === "") return NaN;
        if (!Number.isFinite(total) || !Number.isFinite(size) || size <= 0) return NaN;
        return Math.max(1, Math.ceil(total / size));
      }

      renderWindowed(props, page, totalPages, label, showPrevious, showNext) {
        return html`
          <nav class="pager" aria-label=${label}>
            <button
              type="button"
              class="am-btn am-btn-quiet am-btn-sm"
              ?disabled=${!showPrevious || page <= 1}
              @click=${() => this.turnPage(-1)}
            >
              <span class="pager-chevron" aria-hidden="true">‹</span>
              Previous
            </button>
            <span class="pager-pages">
              ${pageWindow(page, totalPages).map((entry) =>
                entry === "…"
                  ? html`<span class="pager-gap" aria-hidden="true">…</span>`
                  : entry === page
                    ? html`<span class="pager-chip" aria-current="page">${entry}</span>`
                    : html`<button
                        type="button"
                        class="pager-chip"
                        aria-label="Page ${entry}"
                        @click=${() => this.turnPage(entry - page)}
                      >
                        ${entry}
                      </button>`,
              )}
            </span>
            <button
              type="button"
              class="am-btn am-btn-quiet am-btn-sm"
              ?disabled=${!showNext || page >= totalPages}
              @click=${() => this.turnPage(1)}
            >
              Next
              <span class="pager-chevron" aria-hidden="true">›</span>
            </button>
            ${props.rangeText
              ? html`<span class="pager-range">${str(props.rangeText)}</span>`
              : nothing}
          </nav>
        `;
      }

      /**
       * Dispatches the existing `query` envelope with the given pageDelta
       * (any integer: prev/next are ∓1, a page chip jumps by the distance).
       *
       * Priority: the `previousAction`/`nextAction` event object the admin
       * encoder emits (`{"name": "query", "context": {...}}`, byte-exact) —
       * its path refs are resolved at click time and dispatched; a legacy
       * callable or `{event: {...}}` envelope is tolerated; when neither is
       * present the envelope is reconstructed like the basic
       * `query_button/2` emission: the query path is derived from the `page`
       * binding, `component` is added for multi-table surfaces, and the
       * `contexts` binding rides along when the surface carries context
       * state.
       */
      turnPage(delta) {
        const props = this.controller?.props;
        if (!props) return;

        const envelope =
          delta < 0 ? props.previousAction || props.prevAction : props.nextAction;

        if (typeof envelope === "function") {
          // Legacy callables only know their own ±1 step.
          if (Math.abs(delta) === 1) envelope();
          return;
        }

        const context = this.context;
        const surface = context?.dataContext?.surface;
        if (!surface || !context.componentModel) return;

        if (envelope && typeof envelope.name === "string") {
          const resolved = resolveEventContext(
            {event: {name: envelope.name, context: {...(envelope.context || {}), pageDelta: delta}}},
            surface.dataModel,
            "/",
          );
          surface.dispatchAction(resolved, context.componentModel.id);
          return;
        }

        if (envelope && envelope.event && typeof envelope.event.name === "string") {
          const event = {
            ...envelope.event,
            context: {...(envelope.event.context || {}), pageDelta: delta},
          };
          const resolved = resolveEventContext({...envelope, event}, surface.dataModel, "/");
          surface.dispatchAction(resolved, context.componentModel.id);
          return;
        }

        const raw = context.componentModel.properties || {};
        const pagePath =
          typeof raw.page?.path === "string"
            ? raw.page.path
            : typeof raw.pageSize?.path === "string"
              ? raw.pageSize.path
              : null;

        let queryPath = "/query";
        if (pagePath && pagePath.endsWith("/page")) {
          queryPath = pagePath.slice(0, -"/page".length) || "/query";
        }

        const actionContext = {pageDelta: delta, query: {path: queryPath}};
        if (queryPath !== "/query") {
          const segments = queryPath.split("/");
          actionContext.component = segments[segments.length - 1];
        }
        const contexts = surface.dataModel.get("/context");
        if (contexts !== null && contexts !== undefined && typeof contexts === "object") {
          actionContext.contexts = {path: "/context"};
        }

        const resolved = resolveEventContext(
          {event: {name: "query", context: actionContext}},
          surface.dataModel,
          "/",
        );
        surface.dispatchAction(resolved, context.componentModel.id);
      }
    }

    customElements.define(tag, AshAdminPagination);
  }

  // --- RecordPanel: explicit task panel -------------------------------------

  function defineRecordPanel() {
    const tag = TAGS.recordPanel;
    if (customElements.get(tag)) return;

    const MODE_HEADINGS = {
      view: "View record",
      create: "Create record",
      edit: "Edit record",
    };

    class AshAdminRecordPanel extends A2uiLitElement {
      constructor() {
        super();
        this._amLastMode = null;
        this._amRestoreFocus = null;
      }

      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .panel {
            background: var(--am-surface-raised);
            border: 1px solid var(--am-border);
            border-radius: var(--am-radius-l);
            box-shadow: var(--am-shadow-2);
            padding: var(--am-space-xl);
            margin: var(--am-space-s) 0 var(--am-space-m);
            max-width: 56rem;
          }
          .panel-title {
            margin: 0 0 var(--am-space-l);
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
          }
          .panel-title:focus {
            outline: none;
          }
          .panel-title:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          .panel-fields {
            margin: 0;
            display: flex;
            flex-direction: column;
          }
          .panel-form {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-l);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.recordPanel);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);

        // Capture the pre-panel focus BEFORE the DOM gains the panel, so
        // closing restores the user to whatever invoked the task (the row's
        // View/Edit button, a Create button, …).
        const mode = this.resolvedMode();
        if (mode && !this._amLastMode && !this._amRestoreFocus) {
          this._amRestoreFocus = document.activeElement;
        }

        applyWeight(this, this.controller?.props);
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        const mode = this.resolvedMode();

        if (mode && !this._amLastMode) {
          // Panel opened: move focus into the panel.
          this.focusPanel();
        } else if (!mode && this._amLastMode) {
          // Panel closed (mode → nil = back to browse): restore focus.
          if (this._amRestoreFocus && this._amRestoreFocus.isConnected) {
            this._amRestoreFocus.focus();
          }
          this._amRestoreFocus = null;
        } else if (mode && mode !== this._amLastMode) {
          // Task switched (view ↔ edit): the content changed wholesale, so
          // bring focus back to the panel heading.
          this.focusPanel();
        }

        this._amLastMode = mode;
      }

      resolvedMode() {
        const mode = this.controller?.props?.mode;
        return mode === null || mode === undefined || mode === "" ? null : String(mode);
      }

      focusPanel() {
        const heading = this.renderRoot?.querySelector("[data-panel-heading]");
        if (heading) heading.focus();
      }

      childType(ref) {
        try {
          return this.context?.dataContext?.surface?.componentsModel?.get(ref.id)?.type ?? null;
        } catch {
          return null;
        }
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;
        const mode = this.resolvedMode();
        if (!mode) return nothing;

        const isView = mode === "view";
        const children = childRefs(props.children);
        // View mode: the field displays, then the action bar — whose
        // primary is hidden there (empty label) but whose Cancel closes
        // the panel, as the basic composition's footer does.
        const refs = children.filter((ref) => {
          const type = this.childType(ref);
          if (type === "fieldDisplay") return isView;
          return !isView;
        });
        const closeRefs = isView
          ? children.filter((ref) => this.childType(ref) === "actionBar")
          : [];

        const title = str(props.title);
        const headingText = title || MODE_HEADINGS[mode] || "";

        return html`
          <section
            class="panel"
            aria-label=${headingText || "Record panel"}
            data-record-id=${str(props.recordId ?? "")}
          >
            <h2 class="panel-title" tabindex="-1" data-panel-heading>
              ${headingText}
            </h2>
            ${isView
              ? html`<dl class="panel-fields">
                    ${refs.map((ref) => html`${this.renderNode(ref)}`)}
                  </dl>
                  ${closeRefs.map((ref) => html`${this.renderNode(ref)}`)}`
              : html`<div class="panel-form">
                  ${refs.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`}
          </section>
        `;
      }
    }

    customElements.define(tag, AshAdminRecordPanel);
  }

  // --- FieldDisplay: read-only value ----------------------------------------

  function defineFieldDisplay() {
    const tag = TAGS.fieldDisplay;
    if (customElements.get(tag)) return;

    class AshAdminFieldDisplay extends A2uiLitElement {
      static styles = [
        shared,
        content,
        css`
          :host {
            display: block;
            container-type: inline-size;
          }
          .field {
            display: grid;
            grid-template-columns: minmax(8rem, 33%) 1fr;
            gap: var(--am-space-2xs) var(--am-space-l);
            align-items: baseline;
            padding: var(--am-space-xs) 0;
            border-bottom: var(--am-border-width) solid var(--am-border);
          }
          :host(:last-child) .field,
          .field:last-child {
            border-bottom: none;
          }
          .field-label {
            font-size: var(--am-font-size-xs);
            font-weight: var(--am-font-weight-semibold);
            letter-spacing: var(--ash-admin-field-label-tracking, var(--am-tracking-wide));
            text-transform: var(--ash-admin-field-label-transform, uppercase);
            color: var(--ash-admin-field-label-text, var(--am-text-muted));
          }
          .field-value {
            margin: 0;
            font-size: var(--am-font-size-m);
            overflow-wrap: anywhere;
          }
          .field-value-boolean {
            display: inline-flex;
            align-items: center;
            gap: var(--am-space-2xs);
            font-weight: var(--am-font-weight-medium);
          }
          .field-value-boolean::before {
            content: "";
            width: 0.5rem;
            height: 0.5rem;
            border-radius: 50%;
            background: var(--am-text-faint);
          }
          .field-value-boolean.is-true::before {
            background: var(--am-success);
          }
          .field-value-boolean.is-false::before {
            background: var(--am-border-strong);
          }
          @container (max-width: 29.99rem) {
            .field {
              grid-template-columns: 1fr;
              gap: var(--am-space-2xs);
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.fieldDisplay);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const isBoolean = props.format === "boolean";
        const links = linkEntries(props.link);

        if (links.length > 0) {
          return html`
            <div class="field">
              <dt class="field-label">${str(props.label)}</dt>
              <dd class="field-value">${renderLinks(this, links)}</dd>
            </div>
          `;
        }

        if (isBoolean) {
          const value = formatDisplayValue(props.value, props.format);
          return html`
            <div class="field">
              <dt class="field-label">${str(props.label)}</dt>
              <dd
                class="field-value field-value-boolean ${value === "Yes" ? "is-true" : "is-false"}"
              >
                ${value}
              </dd>
            </div>
          `;
        }

        return html`
          <div class="field">
            <dt class="field-label">${str(props.label)}</dt>
            <dd class="field-value">${renderValue(props.value, props.format)}</dd>
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminFieldDisplay);
  }

  // --- FormSection: labeled field grouping ----------------------------------

  function defineFormSection() {
    const tag = TAGS.formSection;
    if (customElements.get(tag)) return;

    // Frozen AshA2ui encoder id conventions (see the v0_9_1 emission):
    // inputs are `form_input_<field>` with value bound to `/form/<field>`,
    // errors are `form_error_<field>` Texts bound to `/errors/<field>`, and
    // searchable relationship selects are `form_select_<field>` composites.
    const ERROR_ID_PREFIX = "form_error_";
    const SELECT_ID_PREFIX = "form_select_";
    const INPUT_KINDS = ["TextField", "CheckBox", "ChoicePicker", "DateTimeInput"];

    class AshAdminFormSection extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
            container-type: inline-size;
          }
          .fs {
            border: none;
            margin: 0;
            padding: 0;
          }
          .fs-title {
            margin: 0 0 var(--am-space-l);
            font-size: var(--am-font-size-m);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
          }
          .fs-grid {
            display: grid;
            gap: var(--am-space-l) var(--am-space-xl);
            grid-template-columns: repeat(var(--am-fs-cols, 1), minmax(0, 1fr));
          }
          .fs-cell {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-2xs);
            min-width: 0;
          }
          .fs-extra {
            margin-top: var(--am-space-l);
          }
          @container (max-width: 39.99rem) {
            .fs-grid {
              grid-template-columns: 1fr;
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.formSection);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        const props = this.controller?.props;
        const columns = Math.min(Math.max(Math.round(Number(props?.columns) || 1), 1), 6);
        this.style.setProperty("--am-fs-cols", String(columns));
        applyWeight(this, props);
      }

      childType(ref) {
        try {
          return this.context?.dataContext?.surface?.componentsModel?.get(ref.id)?.type ?? null;
        } catch {
          return null;
        }
      }

      childValuePath(ref) {
        try {
          const path = this.context?.dataContext?.surface?.componentsModel?.get(ref.id)?.properties
            ?.value?.path;
          return typeof path === "string" ? path : null;
        } catch {
          return null;
        }
      }

      /**
       * Pairs the encoder's sibling `form_error_<field>` Texts with their
       * inputs. The a11y-hardened inputs (TextField/CheckBox/ChoicePicker/
       * DateTimeInput overrides) already render + aria-wire `/errors/<field>`
       * themselves — their paired error Texts are dropped so the message is
       * never double-rendered. Error Texts that pair with a searchable-select
       * composite (`form_select_<field>`) render inside that field's cell
       * (true adjacency); anything unpaired renders in a trailing block.
       */
      partitionChildren() {
        const props = this.controller?.props;
        const refs = childRefs(props?.children);

        const errors = [];
        const fields = [];
        for (const ref of refs) {
          if (ref.id.startsWith(ERROR_ID_PREFIX) && this.childType(ref) === "Text") {
            errors.push(ref);
          } else {
            fields.push(ref);
          }
        }

        const attached = new Map(); // field ref id -> error ref
        const trailing = [];
        for (const errorRef of errors) {
          const field = errorRef.id.slice(ERROR_ID_PREFIX.length);

          const ownedByInput = fields.some(
            (ref) =>
              this.childValuePath(ref) === `/form/${field}` &&
              INPUT_KINDS.includes(this.childType(ref)),
          );
          if (ownedByInput) continue; // the input renders this error itself

          const selectRef = fields.find((ref) => ref.id === `${SELECT_ID_PREFIX}${field}`);
          if (selectRef) {
            attached.set(selectRef.id, errorRef);
            continue;
          }

          trailing.push(errorRef);
        }

        return {fields, attached, trailing};
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const {fields, attached, trailing} = this.partitionChildren();

        return html`
          <div class="fs">
            ${props.title ? html`<h3 class="fs-title">${str(props.title)}</h3>` : nothing}
            <div class="fs-grid">
              ${fields.map(
                (ref) => html`
                  <div class="fs-cell">
                    ${this.renderNode(ref)}
                    ${attached.has(ref.id)
                      ? html`${this.renderNode(attached.get(ref.id))}`
                      : nothing}
                  </div>
                `,
              )}
            </div>
            ${trailing.length > 0
              ? html`<div class="fs-extra">
                  ${trailing.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`
              : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminFormSection);
  }

  // --- ActionBar: action hierarchy -------------------------------------------

  function defineActionBar() {
    const tag = TAGS.actionBar;
    if (customElements.get(tag)) return;

    class AshAdminActionBar extends A2uiLitElement {
      constructor() {
        super();
        // Zero jank: set at submit time (0 RTT), cleared when the data
        // model reports the action's outcome (see SETTLE_PATHS above).
        this._amOptimisticBusy = false;
        this._amSettleUnsubscribes = null;
      }

      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: block;
          }
          .bar {
            display: flex;
            align-items: center;
            gap: var(--am-space-m);
            flex-wrap: wrap;
            margin-top: var(--am-space-l);
          }
          /* Quiet secondaries: custom properties pierce the basic Button's
           * shadow boundary, so its default chrome softens without touching
           * the basic catalog. */
          .bar-secondary {
            display: flex;
            align-items: center;
            gap: var(--am-space-s);
            flex-wrap: wrap;
            --a2ui-button-border: 1px solid transparent;
            --a2ui-button-background: transparent;
            --a2ui-button-padding: 0.375rem 0.75rem;
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.actionBar);
      }

      get surface() {
        return this.context?.dataContext?.surface;
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        dropActionBusySubscriptions(this);
      }

      onActionSettled() {
        this._amOptimisticBusy = false;
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const label = str(props.primaryLabel ?? "");
        const busy = this._amOptimisticBusy || props.busy === true;
        const destructive = props.destructive === true;
        const children = childRefs(props.children);

        return html`
          <div class="bar" role="group" aria-label="Record actions">
            ${label !== ""
              ? html`
                  <button
                    type="button"
                    class="am-btn ${destructive ? "am-btn-destructive" : "am-btn-primary"}"
                    ?disabled=${busy}
                    aria-busy=${busy ? "true" : "false"}
                    @click=${() => this.submit()}
                  >
                    ${busy ? html`<span class="am-spinner" aria-hidden="true"></span>` : nothing}
                    ${label}
                  </button>
                `
              : nothing}
            ${children.length > 0
              ? html`<div class="bar-secondary">
                  ${children.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`
              : nothing}
          </div>
        `;
      }

      /**
       * Dispatches the existing `submit_form` envelope: the `action`
       * envelope prop the encoder emits (GenericBinder-resolved into a
       * callable, byte-exact) wins; otherwise the frozen context is
       * reconstructed from the data model's shape (matching the basic
       * emission's `submit_button/2`).
       */
      submit() {
        const props = this.controller?.props;
        if (!props) return;

        if (typeof props.action === "function") {
          this._amOptimisticBusy = true;
          markActionBusy(this);
          this.requestUpdate();
          props.action();
          return;
        }

        const context = this.context;
        const surface = context?.dataContext?.surface;
        if (!surface || !context.componentModel) return;

        const resolved = resolveEventContext(
          {event: {name: "submit_form", context: buildSubmitFormContext(surface)}},
          surface.dataModel,
          "/",
        );

        // Zero jank: the click is acknowledged before the envelope leaves
        // the browser — disabled + spinner now, settled by the outcome
        // write (or the encoder-driven `busy` prop) later.
        this._amOptimisticBusy = true;
        markActionBusy(this);
        this.requestUpdate();

        surface.dispatchAction(resolved, context.componentModel.id);
      }
    }

    customElements.define(tag, AshAdminActionBar);
  }

  // --- StatusBanner: typed feedback ------------------------------------------

  function defineStatusBanner() {
    const tag = TAGS.statusBanner;
    if (customElements.get(tag)) return;

    const glyph = (paths) => html`<svg
      viewBox="0 0 20 20"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      ${paths.map((path) => html`<path d=${path}></path>`)}
    </svg>`;

    const GLYPHS = {
      success: glyph(["M4 10.5l4 4 8-9"]),
      error: glyph(["M10 4v8", "M10 15.5v.01"]),
      warning: glyph(["M10 4.5l6 10.5H4l6-10.5z", "M10 9v3", "M10 13.75v.01"]),
      info: glyph(["M10 9v5", "M10 6.25v.01"]),
    };

    class AshAdminStatusBanner extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .banner {
            display: flex;
            align-items: flex-start;
            gap: var(--am-space-s);
            padding: var(--am-space-s) var(--am-space-m);
            border-radius: var(--am-radius-m);
            border: 1px solid transparent;
            font-size: var(--am-font-size-m);
          }
          .banner-glyph {
            flex: none;
            margin-top: 0.125rem;
            display: inline-flex;
          }
          .banner-content {
            min-width: 0;
            overflow-wrap: anywhere;
          }
          .banner-success {
            color: var(--am-success);
            background: var(--am-success-subtle);
            border-color: color-mix(in srgb, var(--am-success) 25%, transparent);
          }
          .banner-error {
            color: var(--am-error);
            background: var(--am-error-subtle);
            border-color: color-mix(in srgb, var(--am-error) 25%, transparent);
          }
          .banner-warning {
            color: var(--am-warning);
            background: var(--am-warning-subtle);
            border-color: color-mix(in srgb, var(--am-warning) 25%, transparent);
          }
          .banner-info {
            color: var(--am-text-muted);
            background: var(--am-hover-tint);
            border-color: var(--am-border);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.statusBanner);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const kind = props.kind === null || props.kind === undefined ? "" : String(props.kind);
        if (!kind) return nothing;

        const tone = ["success", "error", "warning", "info"].includes(kind) ? kind : "info";
        // Typed feedback semantics: errors assert, everything else is polite.
        const role = tone === "error" ? "alert" : "status";

        return html`
          <div class="banner banner-${tone}" role=${role}>
            <span class="banner-glyph">${GLYPHS[tone]}</span>
            <div class="banner-content">${str(props.message)}</div>
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminStatusBanner);
  }

  // --- CalendarView: the window of a display :calendar table (1.3) ----------
  //
  // An `nb-calendar` grid (month, or one week for week and day calendars)
  // beside the table's own dataGrid child, which lists the window's records
  // or the picked day's. The server owns the data: moving the window or
  // picking a day dispatches `windowAction` (a `query` envelope) with
  // `anchor` / `date` added, and the window state it writes back
  // (anchor, selected, marks) repaints the grid.
  //
  // Zero jank, "the server follows the DOM": the grid moves and highlights
  // the moment the user acts, and the envelope carries the ABSOLUTE date the
  // grid now shows, never a delta. While requests are in flight, window
  // states from earlier requests do not move the grid back; the latest one
  // (which matches what is on screen) lands silently. A typed-feedback
  // write (an error) or a 10 s timeout clears the pending request.

  function defineCalendarView() {
    const tag = TAGS.calendarView;
    if (customElements.get(tag)) return;
    defineNbComponents();

    const PENDING_TIMEOUT_MS = 10000;

    const pad = (number) => String(number).padStart(2, "0");
    const isoOf = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    const parseIso = (text) => {
      const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text || "");
      if (!match) return null;
      const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
      date.setHours(12, 0, 0, 0);
      return date;
    };
    const addDays = (date, days) => {
      const next = new Date(date);
      next.setDate(next.getDate() + days);
      return next;
    };
    const mondayOf = (date) => addDays(date, -((date.getDay() + 6) % 7));

    class AshAdminCalendarView extends A2uiLitElement {
      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: block;
          }
          .cal-view {
            display: flex;
            flex-wrap: wrap;
            align-items: flex-start;
            gap: var(--am-space-l);
          }
          .cal-pane {
            flex: 0 1 22rem;
            min-width: min(100%, 18rem);
            display: flex;
            flex-direction: column;
            gap: var(--am-space-s);
          }
          .cal-tools {
            display: flex;
            align-items: center;
            gap: var(--am-space-xs);
            flex-wrap: wrap;
          }
          .cal-sizes {
            display: inline-flex;
            gap: var(--am-space-2xs, 2px);
          }
          .cal-sizes .am-btn[aria-pressed="true"] {
            font-weight: var(--am-font-weight-semibold);
            text-decoration: underline;
            text-underline-offset: 0.25em;
          }
          .cal-tools .cal-day {
            font-weight: var(--am-font-weight-semibold);
            margin-inline-end: auto;
          }
          .cal-list {
            flex: 1 1 24rem;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: var(--am-space-s);
            transition: opacity 120ms ease;
          }
          .cal-list[aria-busy="true"] {
            opacity: 0.6;
          }
          .cal-scope {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: var(--am-space-s);
            flex-wrap: wrap;
          }
          .cal-scope-title {
            margin: 0;
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-semibold);
          }
          nb-calendar {
            max-width: none;
          }
          @media (prefers-reduced-motion: reduce) {
            .cal-list {
              transition: none;
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.calendarView);
      }

      constructor() {
        super();
        this._pending = null;
        this._pendingTimer = null;
        this._feedbackSubscription = null;
        this.onCalendarEvent = (event) => this.handleCalendarEvent(event);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        this.clearPending();
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      // The window's own size (it can be switched), else the declared one.
      get granularity() {
        const value = str(this.windowState.granularity) || this.controller?.props?.granularity;
        return value === "day" || value === "week" ? value : "month";
      }

      get granularities() {
        const value = this.controller?.props?.granularities;
        return Array.isArray(value)
          ? value.filter((size) => size === "day" || size === "week" || size === "month")
          : [];
      }

      sizeLabel(size) {
        return size === "day" ? "Day" : size === "week" ? "Week" : "Month";
      }

      get windowState() {
        const value = this.controller?.props?.window;
        return value && typeof value === "object" ? value : {};
      }

      locale() {
        return this.closest("[lang]")?.getAttribute("lang") || document.documentElement.lang || undefined;
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const label = str(props.label) || "Calendar";
        const state = this.windowState;
        const day = this.granularity === "day";
        const selected = str(state.selected);

        return html`
          <section class="cal-view" aria-label=${label}>
            <div class="cal-pane">
              <div class="cal-tools">
                ${day
                  ? html`<span class="cal-day">${this.formatDay(str(state.anchor))}</span>`
                  : nothing}
                <button type="button" class="am-btn am-btn-quiet am-btn-sm" @click=${() => this.goToday()}>
                  Today
                </button>
                ${this.granularities.length > 1
                  ? html`<span class="cal-sizes" role="group" aria-label="Calendar view">
                      ${this.granularities.map(
                        (size) => html`<button
                          type="button"
                          class="am-btn am-btn-quiet am-btn-sm"
                          aria-pressed=${size === this.granularity ? "true" : "false"}
                          @click=${() => this.switchSize(size)}
                        >
                          ${this.sizeLabel(size)}
                        </button>`,
                      )}
                    </span>`
                  : nothing}
              </div>
              <nb-calendar
                part="calendar"
                view=${this.granularity === "month" ? "month" : "week"}
                @nb-select=${this.onCalendarEvent}
                @nb-month-change=${this.onCalendarEvent}
                @nb-week-change=${this.onCalendarEvent}
              ></nb-calendar>
            </div>
            <div class="cal-list" aria-busy=${this._pending ? "true" : "false"}>
              <div class="cal-scope">
                <h3 class="cal-scope-title">${this.scopeTitle(state)}</h3>
                ${!day && selected
                  ? html`<button
                      type="button"
                      class="am-btn am-btn-quiet am-btn-sm"
                      @click=${() => this.pickDay("")}
                    >
                      All days
                    </button>`
                  : nothing}
              </div>
              ${childRefs(props.children).map((ref) => html`${this.renderNode(ref)}`)}
            </div>
          </section>
        `;
      }

      updated(changedProperties) {
        super.updated?.(changedProperties);
        this.syncCalendar();
      }

      calendarElement() {
        return this.renderRoot?.querySelector("nb-calendar") || null;
      }

      // --- server → grid ---------------------------------------------------

      /** Writes the server's window state onto the grid, unless a newer
       * request of ours is still in flight (then only the marks move). */
      syncCalendar() {
        const element = this.calendarElement();
        if (!element) return;
        const state = this.windowState;
        const items = Array.isArray(state.marks)
          ? state.marks.map((mark) => `${str(mark.date)}*${Number(mark.count) || 1}`).join(" ")
          : "";

        const attrs = {items};
        const serverKey = this.windowKey(str(state.anchor), str(state.selected));

        if (this._pending && this._pending.key !== serverKey) {
          this.writeAttributes(element, attrs);
          return;
        }
        if (this._pending) this.clearPending();

        attrs.month = str(state.anchor);
        attrs.selected = this.granularity === "day" ? str(state.anchor) : str(state.selected);
        this.writeAttributes(element, attrs);
      }

      /** Sets only the attributes that differ (each write repaints the
       * grid), and keeps keyboard focus on the day that held it. */
      writeAttributes(element, attrs) {
        const focused = element.shadowRoot?.activeElement?.dataset?.date;
        let changed = false;
        for (const [name, value] of Object.entries(attrs)) {
          const current = element.getAttribute(name);
          if (value === "" || value === null || value === undefined) {
            if (current !== null) {
              element.removeAttribute(name);
              changed = true;
            }
          } else if (current !== value) {
            element.setAttribute(name, value);
            changed = true;
          }
        }
        if (changed && focused && typeof element.focusDateInMonth === "function") {
          element.focusDateInMonth(parseIso(focused));
        }
      }

      // --- grid → server ---------------------------------------------------

      handleCalendarEvent(event) {
        event.stopPropagation();
        const detail = event.detail || {};
        const state = this.windowState;

        if (event.type === "nb-select") {
          const date = str(detail.date);
          if (this.granularity === "day") {
            this.moveWindow(date, date);
          } else {
            this.pickDay(date === str(state.selected) ? "" : date);
          }
          return;
        }

        if (event.type === "nb-month-change") {
          this.moveWindow(`${str(detail.month)}-01`, null);
          return;
        }

        // nb-week-change: a week or day calendar moved a week. A day
        // calendar keeps its weekday.
        const monday = parseIso(str(detail.week));
        if (!monday) return;
        if (this.granularity === "day") {
          const anchor = parseIso(str(state.anchor)) || monday;
          const date = isoOf(addDays(monday, (anchor.getDay() + 6) % 7));
          this.moveWindow(date, date);
        } else {
          this.moveWindow(isoOf(monday), null);
        }
      }

      /** Asks the server for another window size. The server decides the
       * window it then shows (it keeps the picked day, or today), so no
       * pending key: its reply repaints the grid. */
      switchSize(size) {
        if (size === this.granularity) return;
        this.clearPending();
        this.request({granularity: size}, null);
      }

      goToday() {
        const today = isoOf(new Date());
        this.moveWindow(today, this.granularity === "day" ? today : null);
      }

      /** Shows the window holding `anchor` now, then asks the server for it. */
      moveWindow(anchor, dayPick) {
        const element = this.calendarElement();
        const state = this.windowState;
        const selected = this.granularity === "day" ? anchor : this.keptSelection(anchor, str(state.selected));
        if (element) this.writeAttributes(element, {month: anchor, selected});

        if (this.granularity === "day" && dayPick) {
          this.request({date: dayPick}, this.windowKey(anchor, ""));
        } else {
          this.request({anchor}, this.windowKey(anchor, selected));
        }
      }

      /** Picks a day (or clears the pick with ""), then asks the server. */
      pickDay(date) {
        const element = this.calendarElement();
        if (element) this.writeAttributes(element, {selected: date});
        this.request({date}, this.windowKey(str(this.windowState.anchor), date));
      }

      /** The picked day survives a move only when it is inside the new window. */
      keptSelection(anchor, selected) {
        if (!selected) return "";
        return this.windowKey(anchor, "") === this.windowKey(selected, "") ? selected : "";
      }

      /** A comparable key for "this window with this pick". */
      windowKey(anchor, selected) {
        const date = parseIso(anchor);
        let key = anchor;
        if (date && this.granularity === "month") key = anchor.slice(0, 7);
        if (date && this.granularity === "week") key = isoOf(mondayOf(date));
        return `${key}|${this.granularity === "day" ? "" : selected || ""}`;
      }

      request(extra, key) {
        const props = this.controller?.props;
        const context = this.context;
        const surface = context?.dataContext?.surface;
        const envelope = props?.windowAction;
        if (!surface || !context.componentModel || !envelope || typeof envelope.name !== "string") return;

        // A null key (a size switch) waits for no particular window.
        if (key === null) this.clearPending();
        else this.setPending(key, surface);
        const resolved = resolveEventContext(
          {event: {name: envelope.name, context: {...(envelope.context || {}), ...extra}}},
          surface.dataModel,
          "/",
        );
        surface.dispatchAction(resolved, context.componentModel.id);
      }

      setPending(key, surface) {
        this.clearPending();
        this._pending = {key};
        this._pendingTimer = setTimeout(() => {
          this.clearPending();
          this.requestUpdate();
        }, PENDING_TIMEOUT_MS);
        if (surface.dataModel && typeof surface.dataModel.subscribe === "function") {
          this._feedbackSubscription = surface.dataModel.subscribe("/ui/feedback/message", () => {
            this.clearPending();
            this.requestUpdate();
          });
        }
        this.requestUpdate();
      }

      clearPending() {
        this._pending = null;
        if (this._pendingTimer) clearTimeout(this._pendingTimer);
        this._pendingTimer = null;
        if (this._feedbackSubscription) {
          try {
            this._feedbackSubscription.unsubscribe();
          } catch {
            // The data model may already be gone (surface torn down).
          }
        }
        this._feedbackSubscription = null;
      }

      // --- labels ----------------------------------------------------------

      scopeTitle(state) {
        const selected = str(state.selected);
        if (selected) return this.formatDay(selected);
        const anchor = parseIso(str(state.anchor));
        if (!anchor) return str(state.label);
        const locale = this.locale();
        if (this.granularity === "month") {
          return new Intl.DateTimeFormat(locale, {month: "long", year: "numeric"}).format(anchor);
        }
        if (this.granularity === "week") {
          const format = new Intl.DateTimeFormat(locale, {month: "short", day: "numeric", year: "numeric"});
          const sunday = addDays(anchor, 6);
          return typeof format.formatRange === "function"
            ? format.formatRange(anchor, sunday)
            : `${format.format(anchor)} – ${format.format(sunday)}`;
        }
        return this.formatDay(str(state.anchor));
      }

      formatDay(iso) {
        const date = parseIso(iso);
        if (!date) return iso;
        return new Intl.DateTimeFormat(this.locale(), {dateStyle: "full"}).format(date);
      }
    }

    customElements.define(tag, AshAdminCalendarView);
  }

  // --- LiveDiagram: a mermaid diagram with live markers (1.4) --------------
  //
  // Draws the static mermaid `source` once and places the bound markers
  // (keyed by node id) on the nodes they name. Marker moves are plain
  // data-model writes: the diagram never re-renders for them, only the
  // marker layer does. Mermaid is loaded through `deps.loadMermaid` the
  // first time a diagram is drawn (see priv/js/ash_a2ui_mermaid.js), and
  // always renders with `securityLevel: "strict"`. Without a loader, or
  // when mermaid fails, the bound node list renders instead (the basic
  // composition's fallback).
  //
  // Status styling follows the BPMN viewer's marker vocabulary: waiting is
  // dashed and hollow, executing pulses, active is solid, failed is the
  // danger fill, done is muted. Tones color the fill and ink: the
  // `--a2ui-marker-<tone>-background` / `-color` pairs of
  // ash_a2ui_theme.css, overridable per tone as `--ash-admin-diagram-<tone>`
  // and `--ash-admin-diagram-<tone>-ink`.

  function defineLiveDiagram() {
    const tag = TAGS.liveDiagram;
    if (customElements.get(tag)) return;

    let enginePromise = null;
    let sequence = 0;

    const strictConfig = (mermaid) => {
      const current =
        typeof mermaid.mermaidAPI?.getConfig === "function" ? mermaid.mermaidAPI.getConfig() : {};
      if (current.securityLevel !== "strict" || current.startOnLoad !== false) {
        mermaid.initialize({...current, startOnLoad: false, securityLevel: "strict"});
      }
    };

    // The loader may resolve to ash_a2ui_mermaid.js's engine, to a raw
    // `mermaid` module (default export or namespace), or to nothing (an
    // IIFE entry that published window.AshA2uiMermaid).
    const toEngine = (loaded) => {
      const candidate = loaded?.default ?? loaded ?? globalThis.AshA2uiMermaid;
      const mermaid = candidate?.mermaid ?? candidate;
      if (!mermaid || typeof mermaid.render !== "function") return null;
      return {
        render: (id, source) => {
          if (typeof mermaid.initialize === "function") strictConfig(mermaid);
          return mermaid.render(id, source);
        },
      };
    };

    const loadEngine = () => {
      if (!enginePromise) {
        const loader = deps.loadMermaid;
        enginePromise =
          typeof loader === "function"
            ? Promise.resolve()
                .then(() => loader())
                .then(toEngine)
                .catch((error) => {
                  console.error("liveDiagram: could not load mermaid", error);
                  return null;
                })
            : Promise.resolve(toEngine(globalThis.AshA2uiMermaid));
      }
      return enginePromise;
    };

    // Mermaid (v10–12) wraps a node's id: "<render id>-flowchart-<node id>-<n>".
    // Direct id/data-id matches come first for other renderers.
    const findNode = (canvas, nodeId) => {
      const escaped = String(nodeId).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const pattern = new RegExp(`(^|-)${escaped}(-[0-9]+)?$`);
      return (
        canvas.querySelector(`[data-id="${CSS.escape(nodeId)}"]`) ||
        canvas.querySelector(`g.node[id="${CSS.escape(nodeId)}"]`) ||
        Array.from(canvas.querySelectorAll("g.node")).find((node) =>
          pattern.test(node.getAttribute("id") || ""),
        ) ||
        null
      );
    };

    const markerTitle = (marker) =>
      `${str(marker.label)} — ${str(marker.nodeLabel) || str(marker.nodeId)} (${str(marker.statusLabel) || str(marker.status)})`;

    class AshAdminLiveDiagram extends A2uiLitElement {
      static styles = [
        shared,
        content,
        css`
          :host {
            display: block;
            --am-diagram-info: var(--ash-admin-diagram-info, var(--a2ui-marker-info-background, #1e40af));
            --am-diagram-info-ink: var(--ash-admin-diagram-info-ink, var(--a2ui-marker-info-color, #ffffff));
            --am-diagram-success: var(--ash-admin-diagram-success, var(--a2ui-marker-success-background, #065f46));
            --am-diagram-success-ink: var(--ash-admin-diagram-success-ink, var(--a2ui-marker-success-color, #ffffff));
            --am-diagram-warning: var(--ash-admin-diagram-warning, var(--a2ui-marker-warning-background, #7c2d12));
            --am-diagram-warning-ink: var(--ash-admin-diagram-warning-ink, var(--a2ui-marker-warning-color, #ffffff));
            --am-diagram-danger: var(--ash-admin-diagram-danger, var(--a2ui-marker-danger-background, #991b1b));
            --am-diagram-danger-ink: var(--ash-admin-diagram-danger-ink, var(--a2ui-marker-danger-color, #ffffff));
            --am-diagram-accent: var(--ash-admin-diagram-accent, var(--a2ui-marker-accent-background, #5b21b6));
            --am-diagram-accent-ink: var(--ash-admin-diagram-accent-ink, var(--a2ui-marker-accent-color, #ffffff));
            --am-diagram-neutral: var(--ash-admin-diagram-neutral, var(--a2ui-marker-neutral-background, #374151));
            --am-diagram-neutral-ink: var(--ash-admin-diagram-neutral-ink, var(--a2ui-marker-neutral-color, #ffffff));
          }
          .diagram-head {
            margin: 0 0 var(--am-space-s);
          }
          .diagram-title {
            margin: 0;
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-semibold);
          }
          .diagram-description {
            margin: var(--am-space-2xs) 0 0;
            color: var(--am-text-muted);
          }
          .diagram-frame {
            position: relative;
            border: var(--am-border-width) solid var(--am-border);
            border-radius: var(--am-radius-m);
            background: var(--ash-admin-diagram-background, var(--am-surface));
            padding: var(--am-space-m);
            overflow: auto;
          }
          .diagram-canvas svg {
            display: block;
            margin: 0 auto;
            max-width: 100%;
            height: auto;
          }
          .diagram-canvas:empty {
            min-height: 6rem;
          }
          .diagram-markers {
            position: absolute;
            inset: 0;
            pointer-events: none;
          }
          .marker {
            position: absolute;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            box-sizing: border-box;
            width: 2rem;
            height: 2rem;
            margin: -1rem 0 0 -1rem;
            border: 2px solid var(--ash-admin-diagram-marker-border, var(--am-text));
            border-radius: 999px;
            background: var(--tone);
            color: var(--ink);
            font: inherit;
            font-size: 0.6875rem;
            font-weight: var(--am-font-weight-bold);
            line-height: 1;
            text-decoration: none;
            box-shadow: var(--ash-admin-diagram-marker-shadow, 2px 2px 0 0 var(--am-text));
            pointer-events: auto;
            cursor: default;
            transition:
              left 250ms ease,
              top 250ms ease,
              transform 120ms ease;
          }
          a.marker,
          button.marker {
            cursor: pointer;
            padding: 0;
          }
          a.marker:hover,
          button.marker:hover {
            transform: translate(-1px, -1px);
          }
          a.marker:focus-visible,
          button.marker:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          .marker[data-tone="info"] {
            --tone: var(--am-diagram-info);
            --ink: var(--am-diagram-info-ink);
          }
          .marker[data-tone="success"] {
            --tone: var(--am-diagram-success);
            --ink: var(--am-diagram-success-ink);
          }
          .marker[data-tone="warning"] {
            --tone: var(--am-diagram-warning);
            --ink: var(--am-diagram-warning-ink);
          }
          .marker[data-tone="danger"] {
            --tone: var(--am-diagram-danger);
            --ink: var(--am-diagram-danger-ink);
          }
          .marker[data-tone="accent"] {
            --tone: var(--am-diagram-accent);
            --ink: var(--am-diagram-accent-ink);
          }
          .marker[data-tone="neutral"] {
            --tone: var(--am-diagram-neutral);
            --ink: var(--am-diagram-neutral-ink);
          }
          .marker[data-status="waiting"] {
            border-style: dashed;
            border-color: var(--tone);
            background: var(--am-surface);
            color: var(--tone);
            box-shadow: none;
          }
          .marker[data-status="executing"] {
            animation: am-diagram-pulse 1.2s ease-in-out infinite;
          }
          .marker[data-status="failed"] {
            border-width: 3px;
          }
          .marker[data-status="done"] {
            opacity: 0.6;
            box-shadow: none;
          }
          @keyframes am-diagram-pulse {
            0%,
            100% {
              opacity: 1;
            }
            50% {
              opacity: 0.55;
            }
          }
          .diagram-status {
            color: var(--am-text-muted);
            font-size: var(--am-font-size-s);
            margin: var(--am-space-xs) 0 0;
          }
          .node-list {
            list-style: none;
            margin: 0;
            padding: 0;
            display: flex;
            flex-direction: column;
            gap: var(--am-space-s);
          }
          .node-label {
            font-weight: var(--am-font-weight-semibold);
          }
          .node-markers {
            display: flex;
            flex-wrap: wrap;
            gap: var(--am-space-xs);
            margin-top: var(--am-space-2xs);
          }
          .chip {
            display: inline-flex;
            align-items: center;
            gap: var(--am-space-xs);
            font-size: var(--am-font-size-s);
          }
          .chip .marker {
            position: static;
            margin: 0;
            width: 1.5rem;
            height: 1.5rem;
            font-size: 0.5625rem;
          }
          @media (prefers-reduced-motion: reduce) {
            .marker,
            .marker[data-status="executing"] {
              animation: none;
              transition: none;
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.liveDiagram);
      }

      constructor() {
        super();
        this._drawn = null; // the source the canvas holds
        this._drawing = null; // the source being drawn
        this._failed = null; // the source mermaid could not draw (or no engine)
        this._mode = "pending"; // pending | ready | fallback
        this._positions = {};
        this._resize = null;
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        this._resize?.disconnect();
        this._resize = null;
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      markerMap() {
        const value = this.controller?.props?.markers;
        return value && typeof value === "object" && !Array.isArray(value) ? value : {};
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const label = str(props.label) || "Diagram";
        const error = str(props.error);
        const fallback = this._mode === "fallback" || !str(props.source);

        return html`
          <section aria-label=${label}>
            <header class="diagram-head">
              <h2 class="diagram-title">${label}</h2>
              ${props.description
                ? html`<p class="diagram-description">${str(props.description)}</p>`
                : nothing}
            </header>
            ${error ? html`<p class="diagram-status" role="status">${error}</p>` : nothing}
            ${fallback
              ? this.renderNodeList(props)
              : html`
                  <div class="diagram-frame" part="frame">
                    <div class="diagram-canvas" part="canvas"></div>
                    <div class="diagram-markers">${this.renderMarkers()}</div>
                  </div>
                  ${this._mode === "pending"
                    ? html`<p class="diagram-status" role="status">Loading diagram…</p>`
                    : nothing}
                `}
          </section>
        `;
      }

      renderMarkers() {
        if (this._mode !== "ready") return nothing;
        const rendered = [];
        for (const [nodeId, markers] of Object.entries(this.markerMap())) {
          const point = this._positions[nodeId];
          if (!point || !Array.isArray(markers)) continue;
          // Badges along the node's top edge, from its right corner
          // leftwards, so the node's own label stays readable.
          markers.forEach((marker, index) => {
            const left = point.x - 4 - index * 28;
            rendered.push(this.renderMarker(marker, `left: ${left}px; top: ${point.y}px`));
          });
        }
        return rendered;
      }

      renderMarker(marker, style) {
        const title = markerTitle(marker);
        const tone = badgeTone(str(marker.tone));
        const status = str(marker.status);
        const link = marker.link && typeof marker.link === "object" ? marker.link : null;
        const text = str(marker.initials) || "?";

        if (link && str(link.surface)) {
          const activate = (event) => this.openLink(event, link);
          if (str(link.href)) {
            return html`<a class="marker" data-tone=${tone} data-status=${status} style=${style}
              href=${link.href} title=${title} aria-label=${title} @click=${activate}>${text}</a>`;
          }
          return html`<button type="button" class="marker" data-tone=${tone} data-status=${status}
            style=${style} title=${title} aria-label=${title} @click=${activate}>${text}</button>`;
        }
        return html`<span class="marker" data-tone=${tone} data-status=${status} style=${style}
          role="img" title=${title} aria-label=${title}>${text}</span>`;
      }

      openLink(event, link) {
        if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        event.stopPropagation();
        requestOpenSurface(deps, openSurfaceArgs(link), {
          surfaceId: this.context?.dataContext?.surface?.id,
          source: this,
          href: link.href,
        });
      }

      renderNodeList(props) {
        const nodes = Array.isArray(props.nodes) ? props.nodes : [];
        if (nodes.length === 0) return nothing;
        return html`<ul class="node-list">
          ${nodes.map(
            (node) => html`<li>
              <span class="node-label">${str(node.label) || str(node.id)}</span>
              <div class="node-markers">
                ${(Array.isArray(node.markers) ? node.markers : []).map(
                  (marker) => html`<span class="chip">${this.renderMarker(marker, "")}
                    <span>${str(marker.label)} (${str(marker.statusLabel) || str(marker.status)})</span></span>`,
                )}
              </div>
            </li>`,
          )}
        </ul>`;
      }

      updated(changedProperties) {
        super.updated?.(changedProperties);
        const source = str(this.controller?.props?.source);
        if (source && source !== this._drawn && source !== this._drawing && source !== this._failed) {
          this.draw(source);
        }
        else if (this._mode === "ready") this.measure();
      }

      async draw(source) {
        this._drawing = source;
        if (this._mode !== "pending") {
          this._mode = "pending";
          this.requestUpdate();
        }
        const engine = await loadEngine();
        if (this._drawing !== source) return;
        if (!engine) {
          this._drawing = null;
          this._failed = source;
          this._mode = "fallback";
          this.requestUpdate();
          return;
        }
        try {
          const {svg} = await engine.render(`ash-a2ui-diagram-${++sequence}`, source);
          if (this._drawing !== source) return;
          await this.updateComplete;
          const canvas = this.renderRoot.querySelector(".diagram-canvas");
          if (!canvas) return;
          canvas.innerHTML = svg;
          this._drawn = source;
          this._drawing = null;
          this._mode = "ready";
          this.observeResize(canvas);
          this.measure();
          this.requestUpdate();
        } catch (error) {
          console.error("liveDiagram: mermaid could not render the diagram", error);
          this._drawing = null;
          this._failed = source;
          this._mode = "fallback";
          this.requestUpdate();
        }
      }

      observeResize(canvas) {
        if (this._resize || typeof ResizeObserver !== "function") return;
        this._resize = new ResizeObserver(() => this.measure());
        this._resize.observe(canvas);
      }

      /** Node top-right corners relative to the frame, for every node
       * holding markers. */
      measure() {
        const frame = this.renderRoot.querySelector(".diagram-frame");
        const canvas = this.renderRoot.querySelector(".diagram-canvas");
        if (!frame || !canvas) return;
        const origin = frame.getBoundingClientRect();
        const positions = {};
        for (const nodeId of Object.keys(this.markerMap())) {
          const node = findNode(canvas, nodeId);
          if (!node) continue;
          const box = node.getBoundingClientRect();
          positions[nodeId] = {
            x: Math.round(box.right - origin.left + frame.scrollLeft),
            y: Math.round(box.top - origin.top + frame.scrollTop),
          };
        }
        if (JSON.stringify(positions) !== JSON.stringify(this._positions)) {
          this._positions = positions;
          this.requestUpdate();
        }
      }
    }

    customElements.define(tag, AshAdminLiveDiagram);
  }

  // --- ConfirmDialog: destructive confirmation -------------------------------

  function defineConfirmDialog() {
    const tag = TAGS.confirmDialog;
    if (customElements.get(tag)) return;

    class AshAdminConfirmDialog extends A2uiLitElement {
      static properties = {
        open: {type: Boolean},
        title: {type: String},
        body: {type: String},
        confirmLabel: {type: String},
        destructive: {type: Boolean},
      };

      constructor() {
        super();
        this.open = false;
        this.title = "";
        this.body = "";
        this.confirmLabel = "Confirm";
        this.destructive = true;
        this._amRestoreFocus = null;
      }

      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: contents;
          }
          .overlay {
            position: fixed;
            inset: 0;
            z-index: 80;
            display: grid;
            place-items: center;
            padding: var(--am-space-l);
            background: rgb(15 23 42 / 0.45);
          }
          .dialog {
            width: min(28rem, 100%);
            background: var(--am-surface);
            color: var(--am-text);
            border: 1px solid var(--am-border);
            border-radius: var(--am-radius-l);
            box-shadow: var(--am-shadow-3);
            padding: var(--am-space-xl);
          }
          .dialog-title {
            margin: 0 0 var(--am-space-s);
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
          }
          .dialog-title:focus {
            outline: none;
          }
          .dialog-title:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          .dialog-body {
            margin: 0 0 var(--am-space-xl);
            color: var(--am-text-muted);
            font-size: var(--am-font-size-m);
          }
          .dialog-actions {
            display: flex;
            justify-content: flex-end;
            gap: var(--am-space-s);
          }
        `,
      ];

      // Normally rendered by the DataGrid renderer (not the component tree),
      // so no controller binding is used. A standalone emission still
      // validates against the catalog schema and renders closed.
      createController() {
        return null;
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        if (!changedProperties.has("open")) return;

        if (this.open) {
          this._amRestoreFocus = document.activeElement;
          const heading = this.renderRoot?.querySelector("[data-dialog-heading]");
          if (heading) heading.focus();
        } else if (changedProperties.get("open") === true && this.isConnected) {
          this.restoreFocus();
        }
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        // The DataGrid removes this element on confirm/cancel — restoring
        // focus to the invoking row button is the closing act.
        if (this.open) this.restoreFocus();
      }

      restoreFocus() {
        if (this._amRestoreFocus && this._amRestoreFocus.isConnected) {
          this._amRestoreFocus.focus();
        }
        this._amRestoreFocus = null;
      }

      confirm() {
        this.dispatchEvent(new CustomEvent("confirm", {bubbles: false}));
      }

      cancel() {
        this.dispatchEvent(new CustomEvent("cancel", {bubbles: false}));
      }

      onKeydown(event) {
        if (event.key === "Escape") {
          event.preventDefault();
          this.cancel();
          return;
        }
        if (event.key === "Tab") {
          // Focus trap: cycle within the dialog while it is open.
          const focusables = [
            ...this.renderRoot.querySelectorAll(
              'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
            ),
          ].filter((element) => !element.hasAttribute("disabled"));
          if (focusables.length === 0) return;
          const first = focusables[0];
          const last = focusables[focusables.length - 1];
          if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
          } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
          }
        }
      }

      render() {
        if (!this.open) return nothing;

        return html`
          <div
            class="overlay"
            @keydown=${(event) => this.onKeydown(event)}
            @pointerdown=${(event) => {
              // Clicking the backdrop cancels; clicks inside the dialog do not.
              if (event.target === event.currentTarget) this.cancel();
            }}
          >
            <div
              class="dialog"
              role="dialog"
              aria-modal="true"
              aria-labelledby="am-dialog-title"
              aria-describedby="am-dialog-body"
            >
              <h2 class="dialog-title" id="am-dialog-title" tabindex="-1" data-dialog-heading>
                ${str(this.title)}
              </h2>
              ${this.body
                ? html`<p class="dialog-body" id="am-dialog-body">${str(this.body)}</p>`
                : nothing}
              <div class="dialog-actions">
                <button type="button" class="am-btn" @click=${() => this.cancel()}>Cancel</button>
                <button
                  type="button"
                  class="am-btn ${this.destructive ? "am-btn-destructive" : "am-btn-primary"}"
                  @click=${() => this.confirm()}
                >
                  ${str(this.confirmLabel) || "Confirm"}
                </button>
              </div>
            </div>
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminConfirmDialog);
  }

  // --- A11y-hardened basic inputs --------------------------------------------

  function defineTextField() {
    const tag = INPUT_OVERRIDE_TAGS.TextField;
    if (customElements.get(tag)) return;

    class AshAdminTextField extends A2uiLitElement {
      static styles = [shared, inputBaseStyles];

      createController() {
        return new A2uiController(this, basicInputApi("TextField"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const inputId = `${this.context?.componentModel?.id || "textfield"}-input`;
        const errorId = `${inputId}-error`;
        const errors = fieldErrors(props, this._amErrText);
        const invalid = errors.length > 0;

        let type = "text";
        if (props.variant === "number") type = "number";
        if (props.variant === "obscured") type = "password";

        return html`
          <div class="field">
            ${props.label
              ? html`<label class="field-label" for=${inputId}>${props.label}</label>`
              : nothing}
            ${props.variant === "longText"
              ? html`<textarea
                  id=${inputId}
                  class="control"
                  .value=${props.value ?? ""}
                  aria-invalid=${invalid ? "true" : "false"}
                  aria-describedby=${invalid ? errorId : ""}
                  @input=${(event) => props.setValue?.(event.target.value)}
                ></textarea>`
              : html`<input
                  id=${inputId}
                  class="control"
                  type=${type}
                  .value=${props.value ?? ""}
                  aria-invalid=${invalid ? "true" : "false"}
                  aria-describedby=${invalid ? errorId : ""}
                  @input=${(event) => props.setValue?.(event.target.value)}
                />`}
            ${invalid ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminTextField);
  }

  function defineCheckBox() {
    const tag = INPUT_OVERRIDE_TAGS.CheckBox;
    if (customElements.get(tag)) return;

    class AshAdminCheckBox extends A2uiLitElement {
      static styles = [shared, inputBaseStyles];

      createController() {
        return new A2uiController(this, basicInputApi("CheckBox"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const inputId = `${this.context?.componentModel?.id || "checkbox"}-input`;
        const errorId = `${inputId}-error`;
        const errors = fieldErrors(props, this._amErrText);
        const invalid = errors.length > 0;

        return html`
          <div class="field">
            <label class="choice" for=${inputId}>
              <input
                id=${inputId}
                type="checkbox"
                .checked=${props.value === true}
                aria-invalid=${invalid ? "true" : "false"}
                aria-describedby=${invalid ? errorId : ""}
                @change=${(event) => props.setValue?.(event.target.checked)}
              />
              ${props.label}
            </label>
            ${invalid ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminCheckBox);
  }

  function defineChoicePicker() {
    const tag = INPUT_OVERRIDE_TAGS.ChoicePicker;
    if (customElements.get(tag)) return;

    class AshAdminChoicePicker extends A2uiLitElement {
      static styles = [
        shared,
        inputBaseStyles,
        css`
          select.control {
            appearance: none;
            background-image: linear-gradient(45deg, transparent 50%, var(--am-text-muted) 50%),
              linear-gradient(135deg, var(--am-text-muted) 50%, transparent 50%);
            background-position:
              calc(100% - 1.15rem) calc(50% + 0.1rem),
              calc(100% - 0.8rem) calc(50% + 0.1rem);
            background-size:
              0.35rem 0.35rem,
              0.35rem 0.35rem;
            background-repeat: no-repeat;
            padding-right: var(--am-space-xl);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, basicInputApi("ChoicePicker"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        // The A2UI schema types ChoicePicker value as a string list, but a
        // server data-model refresh can echo a scalar back into the binding
        // (e.g. AshA2ui's /query/filters/<name>); accept both.
        const raw = props.value;
        const selected = Array.isArray(raw) ? raw : raw == null ? [] : [String(raw)];
        const options = Array.isArray(props.options) ? props.options : [];
        const baseId = this.context?.componentModel?.id || "choice";
        const errorId = `${baseId}-error`;
        const errors = fieldErrors(props, this._amErrText);

        return props.variant === "multipleSelection"
          ? this.renderCheckboxes(props, options, selected, baseId, errors)
          : this.renderSelect(props, options, selected, baseId, errors);
      }

      renderSelect(props, options, selected, baseId, errors) {
        const inputId = `${baseId}-input`;
        const invalid = errors.length > 0;

        // An unset binding on a picker that offers an empty-valued option
        // (AshA2ui's "All" filter/preset option) means "all" — show that
        // option rather than a placeholder.
        let current = selected.length > 0 ? selected[0] : undefined;
        if (current === undefined && options.some((option) => option.value === "")) {
          current = "";
        }
        const hasMatch = options.some((option) => option.value === current);

        return html`
          <div class="field">
            ${props.label
              ? html`<label class="field-label" for=${inputId}>${props.label}</label>`
              : nothing}
            <select
              id=${inputId}
              class="control"
              aria-invalid=${invalid ? "true" : "false"}
              aria-describedby=${invalid ? `${baseId}-error` : ""}
              @change=${(event) => props.setValue && props.setValue([event.target.value])}
            >
              ${hasMatch
                ? nothing
                : html`<option value="" disabled selected hidden>Select…</option>`}
              ${options.map(
                (option) => html`
                  <option value=${option.value} ?selected=${option.value === current}>
                    ${option.label}
                  </option>
                `,
              )}
            </select>
            ${invalid
              ? html`<div class="error" id=${`${baseId}-error`}>${errors[0]}</div>`
              : nothing}
          </div>
        `;
      }

      renderCheckboxes(props, options, selected, baseId, errors) {
        const errorId = `${baseId}-error`;
        const toggle = (value) => {
          if (!props.setValue) return;
          if (selected.includes(value)) {
            props.setValue(selected.filter((item) => item !== value));
          } else {
            props.setValue([...selected, value]);
          }
        };

        return html`
          <div class="field">
            <fieldset class="choices" aria-describedby=${errors.length ? errorId : ""}>
              ${props.label ? html`<legend class="choices-legend">${props.label}</legend>` : nothing}
              ${options.map((option, index) => {
                const optionId = `${baseId}-opt-${index}`;
                return html`
                  <label class="choice" for=${optionId}>
                    <input
                      id=${optionId}
                      type="checkbox"
                      .checked=${selected.includes(option.value)}
                      @change=${() => toggle(option.value)}
                    />
                    ${option.label}
                  </label>
                `;
              })}
            </fieldset>
            ${errors.length > 0 ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminChoicePicker);
  }

  function defineDateTimeInput() {
    const tag = INPUT_OVERRIDE_TAGS.DateTimeInput;
    if (customElements.get(tag)) return;

    // HTML5 date/time inputs reject timezone indicators and sub-minute
    // precision in .value; strip both without shifting the wall clock.
    const normalizeDateTimeValue = (value, type) => {
      if (!value) return "";
      const hasTime = value.includes("T");
      const split = value.split("T");
      const datePart = (hasTime ? split[0] : value).substring(0, 10) || "";
      const timePart = (hasTime ? split[1] : value).substring(0, 5) || "";
      if (type === "date") return datePart;
      if (type === "time") return timePart;
      if (type === "datetime-local") return datePart && timePart ? `${datePart}T${timePart}` : "";
      return "";
    };

    class AshAdminDateTimeInput extends A2uiLitElement {
      static styles = [shared, inputBaseStyles];

      createController() {
        return new A2uiController(this, basicInputApi("DateTimeInput"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const inputId = `${this.context?.componentModel?.id || "datetime"}-input`;
        const errorId = `${inputId}-error`;
        const errors = fieldErrors(props, this._amErrText);
        const invalid = errors.length > 0;

        // Mirrors the upstream control: date and/or time via the native
        // input types, ISO-string round-trip.
        const type =
          props.enableDate && props.enableTime
            ? "datetime-local"
            : props.enableDate
              ? "date"
              : "time";
        const value = normalizeDateTimeValue(props.value, type);

        return html`
          <div class="field">
            ${props.label
              ? html`<label class="field-label" for=${inputId}>${props.label}</label>`
              : nothing}
            <input
              id=${inputId}
              class="control"
              type=${type}
              .value=${value}
              aria-invalid=${invalid ? "true" : "false"}
              aria-describedby=${invalid ? errorId : ""}
              @input=${(event) => props.setValue?.(event.target.value)}
            />
            ${invalid ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminDateTimeInput);
  }
}

export default createAshAdminCatalog;
