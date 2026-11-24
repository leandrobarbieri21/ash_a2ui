/**
 * Ash admin catalog v3 — semantic Lit components for the `@a2ui/lit`
 * renderer.
 *
 * `createAshAdminCatalog(deps)` builds a `@a2ui/web_core` Catalog
 * registered under the admin catalog id
 * (`https://github.com/lukegalea/ash_a2ui/catalogs/admin/v3`) so a surface whose
 * `createSurface.catalogId` matches resolves these components. The
 * renderer resolves a surface's catalog by exact id and renders every
 * component type with its catalog entry's element. The admin catalog is a
 * sibling the host registers beside the basic catalog:
 *
 *     import {A2uiLitElement, A2uiController} from "@a2ui/lit";
 *     import {html, css, nothing} from "lit";
 *     import {createAshAdminCatalog} from "../../deps/ash_a2ui/priv/js/ash_admin_catalog.js";
 *
 *     const adminCatalog = createAshAdminCatalog({
 *       basicCatalog, // the basic catalog, or createAshA2uiCatalog's
 *       A2uiLitElement,
 *       A2uiController,
 *       lit: {html, css, nothing},
 *     });
 *     configureAshA2ui({MessageProcessor, Catalog, catalogs: [basicCatalog, adminCatalog]});
 *
 * The catalog declares the semantic components:
 *
 *   entityPage, dataGrid, emptyState, pagination, recordPanel, fieldDisplay,
 *   formSection, actionBar, statusBanner, confirmDialog, calendarView,
 *   liveDiagram, filterPicker, documentPane, documentViewer
 *
 * and the basic kinds it renders itself (ADMIN_BASIC_KINDS): TextField,
 * CheckBox, ChoicePicker and DateTimeInput (the a11y-hardened inputs below)
 * and Modal (the prompt Modal). On an admin surface those five carry no
 * `@catalogId`, so they resolve here; every other basic kind carries the
 * basic catalog's id as `@catalogId` and renders from the basic catalog
 * the host registers under that id. (camelCase names and the five basic
 * kinds are the wire contract, pinned by `priv/a2ui/admin_v1/catalog.json`.)
 *
 * The JS catalog also carries the rest of `deps.basicCatalog` (pass the
 * stock `basicCatalog` or the merged `createAshA2uiCatalog` result to
 * inherit its upgrades), so a renderer that ignores `@catalogId` still
 * draws them. The wire never relies on it.
 *
 * ## Events
 *
 * Every admin action is server-handled and goes out as the ash_a2ui
 * catalog's `ashAction` function call (see `ash_a2ui_hook.js`), with its
 * context's `{"@path": ...}` bindings resolved at click time:
 *
 *   - row actions / ConfirmDialog confirm → the flat entry the encoder
 *     emits (`{label, action: <name>, context: {...}}`), with row-relative
 *     `{"@path": "id"}` bindings resolved against the clicked row's base
 *     path;
 *   - ActionBar primary → the `action` prop (the `submit_form` ashAction),
 *     run through the GenericBinder's own action resolution exactly like a
 *     basic Button; a reconstructed `{values: /form, recordId: /form/id[,
 *     query][, contexts]}` fallback covers an emission without one;
 *   - Pagination prev/next, sortable headers, the empty state's clear and
 *     the calendar window → the bare `{name, context}` events the encoder
 *     emits (the catalog's actionEvent), sent with what the component adds
 *     (pageDelta, a sort, a page size, a window).
 *
 * ## Zero jank: instant action acknowledgement
 *
 * Dispatching components acknowledge clicks at 0 RTT: the ActionBar primary
 * button and every DataGrid row-action button render disabled + spinner the
 * moment they dispatch, and settle when the surface's data model next
 * reports an outcome write at `/ui/feedback`, which every AshA2ui action
 * these components dispatch writes: submits, invokes, task open/cancel,
 * context select/clear and every rejection. Any settled write counts,
 * including one that leaves the value as it was: View and Cancel write the
 * already-clear feedback, and waiting for a changed message left the View
 * button spinning. The hook's pending write and a write replacing the
 * whole data model (a PubSub refresh) are not outcomes and do not settle.
 * No styling round trip and no `phx-*-loading`: these components own their
 * shadow DOM, and host CSS cannot reach inside it.
 *
 * ## A11y-hardened basic inputs
 *
 * This catalog REPLACES TextField, CheckBox, ChoicePicker and DateTimeInput
 * (for components resolved in the admin catalog only, which on an admin
 * surface is every one of them: they carry no `@catalogId`; the basic
 * catalog registered under its own id is untouched) with equivalent
 * components that associate a real `<label>`, read the AshA2ui form-error state
 * (`/errors/<field>`, derived from each input's `/form/<field>` value
 * binding), and render the error adjacent to the control with the aria
 * wiring. FormSection pairs the encoder's sibling `form_error_<field>`
 * Texts with their inputs so messages are never double-rendered (see that
 * component below).
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
 * Same discipline as `ash_a2ui_catalog.js`: the host passes the single
 * `lit` / `@a2ui/lit` instance in. Written against @a2ui/lit +
 * @a2ui/web_core 0.15.0 / lit 3.x; an admin surface mixes catalogs through
 * `@catalogId`, which that release refuses (see the hook's note), so it
 * renders on the first web_core release after 0.15.0.
 *
 * ## Schema provenance
 *
 * `@a2ui/web_core`'s GenericBinder classifies binding-capable props by
 * introspecting zod 3 internals. The component schemas are therefore
 * composed from web_core's own exported builders (`DynamicStringSchema`,
 * `DynamicValueSchema`, `ActionSchema`, `ChildListSchema`, ... imported
 * from `@a2ui/web_core/v1_0`, the SAME module instance the binder uses),
 * and static props take their primitives from web_core's exported schemas
 * too, so the whole tree is binder-visible whatever zod the host bundles.
 * The envelope keys (`@accessibility`, `@checks`) are the renderer's, not
 * the components'.
 */

import {
  createAdminStyles,
  getByPath,
  formatDisplayValue,
  applyWeight,
  childRefs,
  badgeTone,
  cellIcon,
  moreCount,
  detailText,
  linkEntries,
  listItems,
  pageWindow,
} from "./ash_admin_tokens.js";

// The prompt-closing Modal override, shared with the merged basic catalog
// (the board and basic-table prompts render the basic composition's Modal
// here too), and the action-outcome subscription both catalogs settle on.
// The file defines its element only when asked.
import {
  actionSpec,
  bindingPath,
  dispatchActionSpec,
  resolveEventContext,
  promptModalComponent,
  retagged,
  subscribeActionOutcomes,
  unsubscribeActionOutcomes,
} from "./ash_a2ui_catalog.js";

// The ash_a2ui catalog's id: the admin envelopes are sent as its ashAction.
import {ASH_A2UI_CATALOG_ID, EDITS_PATH, PREVIEW_PATH, LIVE_LINK_ATTRIBUTE, LIVE_LINK_KINDS} from "./ash_a2ui_protocol.js";

/**
 * The attribute a drawn link carries when the surface declared it live
 * (3.7: a breadcrumb step's `live`), its value `navigate` or `patch`. A
 * host's `renderHeader` override puts it on the element whose `href` holds
 * the address (`crumb.live` in the header model); the AshA2ui hook follows
 * a plain click on it inside the LiveView.
 */
export {LIVE_LINK_ATTRIBUTE};

// The NB layer's calendar grid (`nb-calendar`), used by calendarView. The
// file has no imports of its own and defines its elements only when asked.
import {defineNbComponents} from "./nb_components.js";

// Keeps a live diagram's edge labels and marker badges clear of each other
// and of the nodes (pure geometry, unit-tested without a browser).
import {placeMarkerGroups, separate} from "./ash_a2ui_diagram_layout.js";

// 3.4: the document pane and viewer (pdf.js loaded through deps.loadPdf).
import {defineDocumentElements, REGION_ATTRIBUTE} from "./ash_admin_document.js";

/**
 * The attribute a drawn value carries when it cites regions of a document
 * pane (3.8), its value the regions' addresses separated by spaces (see
 * `regionAddresses`). A host swap that draws its own field or table row
 * puts it on that element; the pane links the value and its regions both
 * ways while the document is shown.
 */
export {REGION_ATTRIBUTE};

// 3.1: the review a review field binds, {state, stateLabel, page?,
// pageLabel?, href?, quote?}; anything without a known state is none.
const REVIEW_STATES = ["pending", "reviewed", "missing"];

function reviewEntry(value) {
  if (!value || typeof value !== "object" || !REVIEW_STATES.includes(value.state)) return null;
  return value;
}

/**
 * 3.8: the REGION_ATTRIBUTE value for the reviews a value carries (a
 * field's `review`, or a table row's reviews): their `href`s, separated by
 * spaces, each once; "" when none has one.
 */
export function regionAddresses(reviews) {
  const hrefs = [];
  for (const review of Array.isArray(reviews) ? reviews : [reviews]) {
    const href = reviewEntry(review)?.href;
    if (typeof href === "string" && href !== "" && !hrefs.includes(href)) hrefs.push(href);
  }
  return hrefs.join(" ");
}

/**
 * 3.8: a dataGrid row's reviews, in column order: each column's `review`
 * and its subtitle's `reviewPath` (catalog 3.3), read from `row`. Pass them
 * to `regionAddresses` for the row's REGION_ATTRIBUTE.
 */
export function rowReviews(row, columns) {
  const reviews = [];
  for (const column of Array.isArray(columns) ? columns : []) {
    if (typeof column?.review?.path === "string") reviews.push(getByPath(row, column.review.path));
    if (typeof column?.subtitle?.reviewPath === "string") reviews.push(getByPath(row, column.subtitle.reviewPath));
    // 3.10: each item of a pairs column carries its own review.
    for (const item of pairItems(row, column)) reviews.push(item.review);
  }
  return reviews.map(reviewEntry).filter(Boolean);
}

/**
 * 3.10: a pairs column's items on `row`, read through its `items` binding:
 * each `{term, value, key?, review?, action?}`. Empty when the column binds
 * none (a 1.16 payload: draw the raw value) or the row has none.
 */
export function pairItems(row, column) {
  const path = column?.items?.path;
  if (typeof path !== "string") return [];
  const items = getByPath(row, path);
  return Array.isArray(items) ? items.filter((item) => item && typeof item === "object") : [];
}

/**
 * 3.10: whether a pairs column's `pairAction` is offered for `item`: the
 * column has one, and the item says so (`action: true`) with a key to send.
 * Hiding is a rendering concern only: the server re-checks every call.
 */
export function pairActionOffered(column, item) {
  const entry = column?.pairAction;
  return Boolean(
    entry &&
      typeof entry === "object" &&
      typeof entry.action === "string" &&
      item?.action === true &&
      typeof item.key === "string" &&
      item.key !== "",
  );
}

/**
 * 3.10: the action spec a pairs column's `pairAction` sends for `item`: the
 * entry's, with the item's key added to its context as `item`.
 */
export function pairActionEntry(column, item) {
  const entry = column.pairAction;
  return {...entry, context: {...(entry.context || {}), item: item.key}};
}

// --- 3.11: editing a record in place, saved by a save bar --------------------
//
// A fieldDisplay's `edit` opens its value as an input; a changed value is a
// draft at /ui/edits/<card>/values/<field> (with the card's record id at
// /ui/edits/<card>/recordId) until the saveBar sends them all as
// save_changes, or discards them. These pure helpers are the whole of that
// state, shared by the stock elements and a host's swaps.

/** Where a surface holds its unsaved changes (`/ui/edits`). */
export {EDITS_PATH, PREVIEW_PATH};

/** Where a refused save writes each edited field's message. */
export const EDIT_ERRORS_PATH = "/ui/edit_errors";

const EDIT_INPUTS = ["text", "integer", "number", "date", "choice"];

/** A fieldDisplay's `edit`, its `input` defaulted to text, or null. */
export function editEntry(edit) {
  if (!edit || typeof edit !== "object") return null;
  if (typeof edit.component !== "string" || typeof edit.field !== "string") return null;
  return {...edit, input: EDIT_INPUTS.includes(edit.input) ? edit.input : "text"};
}

/** Whether a field has an unsaved change: its bound `editDraft` is set. */
export function hasDraft(draft) {
  return draft !== undefined && draft !== null;
}

/** The text an input holds for a value: "" for none. */
export function editText(value) {
  return value === null || value === undefined ? "" : String(value);
}

/**
 * Keeps or drops a field's change in `dataModel`. `value` is what the input
 * holds, `stored` the value it started from (`editValue`): a value back at
 * it drops the field's draft (and the card's entry once it holds none);
 * anything else is the draft, as text, with the card's `recordId`. Either
 * way the field's message from a refused save goes.
 *
 * Each map is written whole (`/ui/edits`, `/ui/edit_errors`), never a path
 * inside it: a binding of the whole map (the saveBar's `edits`) sees only
 * the writes of its own path and its descendants' bindings.
 */
export function writeDraft(dataModel, edit, {recordId, value, stored}) {
  const edits = jsonCopy(dataModel.get(EDITS_PATH));
  const card = edits[edit.component] && typeof edits[edit.component] === "object" ? edits[edit.component] : {};
  const values = card.values && typeof card.values === "object" ? {...card.values} : {};

  if (editText(value) === editText(stored)) delete values[edit.field];
  else values[edit.field] = editText(value);

  if (Object.keys(values).length === 0) delete edits[edit.component];
  else edits[edit.component] = {...card, recordId, values};
  dataModel.set(EDITS_PATH, edits);

  const errors = jsonCopy(dataModel.get(EDIT_ERRORS_PATH));
  if (errors[edit.component] && Object.hasOwn(errors[edit.component], edit.field)) {
    delete errors[edit.component][edit.field];
    dataModel.set(EDIT_ERRORS_PATH, errors);
  }
}

// A plain copy of a JSON map; {} for anything else.
function jsonCopy(value) {
  return value && typeof value === "object" ? JSON.parse(JSON.stringify(value)) : {};
}

/**
 * Drops every unsaved change, every refused save's message and every value
 * worked out from the changes (3.15).
 */
export function discardEdits(dataModel) {
  dataModel.set(EDITS_PATH, {});
  dataModel.set(EDIT_ERRORS_PATH, {});
  dataModel.set(PREVIEW_PATH, {});
}

// --- 3.15: values recalculated from the unsaved changes ---------------------
//
// A recalculated fieldDisplay binds `preview` (/ui/preview/<context>/<field>):
// the server's own result for the field with the unsaved changes applied,
// `{value, steps?}`. The saveBar sends its `preview` envelope whenever
// /ui/edits changes, and the server writes /ui/preview whole. The browser
// never works a value out: it draws what the server sent.

/** A fieldDisplay's bound `preview`, or null while there is none. */
export function previewEntry(preview) {
  return preview && typeof preview === "object" && !Array.isArray(preview) ? preview : null;
}

/**
 * A fieldDisplay's props as it draws them: with a preview, its `value` (and
 * a steps field's `steps`) are the preview's. The stock element and a
 * host's swap both draw from it.
 */
export function previewedProps(props) {
  const preview = previewEntry(props?.preview);
  if (!preview) return props;
  const shown = {...props, value: preview.value ?? null};
  if (props.steps !== undefined || preview.steps !== undefined) shown.steps = preview.steps ?? [];
  return shown;
}

/** The preview_changes envelope a saveBar sends, or null when it has none. */
export function previewSpec(props) {
  const preview = props?.preview;
  if (!preview || typeof preview.action !== "string") return null;
  return {name: preview.action, context: {...(preview.context || {})}, catalogId: ASH_A2UI_CATALOG_ID};
}

/** The key a saveBar compares to tell its unsaved changes changed. */
export function editsKey(edits) {
  return JSON.stringify(edits && typeof edits === "object" ? edits : {});
}

/** How many fields hold an unsaved change in `edits` (`/ui/edits`). */
export function editCount(edits) {
  if (!edits || typeof edits !== "object") return 0;
  let count = 0;
  for (const card of Object.values(edits)) {
    const values = card && typeof card === "object" ? card.values : null;
    if (values && typeof values === "object") count += Object.keys(values).length;
  }
  return count;
}

const WAITING_STATES = ["pending", "missing"];

/**
 * 3.16: the table rows (and pairs items) still waiting on a saveBar's
 * record, as the server counts them (`_review_rows.waiting`); 0 without.
 */
export function rowsWaiting(record) {
  const count = record?._review_rows?.waiting;
  return Number.isInteger(count) && count > 0 ? count : 0;
}

/**
 * How many of a saveBar's fields under review still wait: their review on
 * the bar's `record` is pending or missing, unless `editReviews` and the
 * field has an unsaved change (saving it reviews it); plus (3.16) the
 * table rows still waiting on the record (`rowsWaiting`).
 */
export function waitingReviews(props) {
  return reviewCounts(props).waiting;
}

/**
 * How a saveBar's fields under review stand (3.17): `waiting` as
 * `waitingReviews` counts them; `reviewed`, the fields a person reviewed:
 * their review on the bar's `record` is reviewed, or, with `editReviews`, a
 * waiting one has an unsaved change (saving it reviews it), plus the table
 * rows reviewed (`_review_rows.reviewed`); and `open`, whether the review
 * is still open: a field's review on the record is still pending or
 * missing, whatever the unsaved changes, or a table row still waits.
 */
export function reviewCounts(props) {
  const record = props?.record && typeof props.record === "object" ? props.record : {};
  const edits = props?.edits && typeof props.edits === "object" ? props.edits : {};
  const rows = record._review_rows && typeof record._review_rows === "object" ? record._review_rows : {};
  let waiting = rowsWaiting(record);
  let reviewed = Number.isInteger(rows.reviewed) && rows.reviewed > 0 ? rows.reviewed : 0;
  let open = waiting > 0;
  for (const entry of Array.isArray(props?.reviews) ? props.reviews : []) {
    const state = reviewEntry(record[`_review_${entry?.field}`])?.state;
    if (state === "reviewed") {
      reviewed += 1;
      continue;
    }
    if (!WAITING_STATES.includes(state)) continue;
    open = true;
    const values = edits[entry.component]?.values;
    if (props.editReviews === true && values && Object.hasOwn(values, entry.field)) reviewed += 1;
    else waiting += 1;
  }
  return {waiting, reviewed, open};
}

/** A counted text: `one` for one when given, else `other`, `%{count}` replaced. */
export function countText(other, one, count) {
  const text = count === 1 && typeof one === "string" && one !== "" ? one : other;
  return typeof text === "string" ? text.replaceAll("%{count}", String(count)) : "";
}

/** Whether a saveBar's confirm offers its second choice on the bar's record. */
export function thenOffered(props) {
  const confirm = props?.confirm;
  if (!confirm || confirm.then !== true) return false;
  if (typeof confirm.thenVisible !== "string" || confirm.thenVisible === "") return true;
  return props.record?.[confirm.thenVisible] === true;
}

/**
 * Whether a saveBar shows while its fields under review wait, before
 * anything changed (3.14): its `showWhileWaiting` is true, or names a field
 * of the bar's record that is true.
 */
export function showsWhileWaiting(props) {
  const show = props?.showWhileWaiting;
  if (show === true) return true;
  if (typeof show !== "string" || show === "") return false;
  return props?.record?.[show] === true;
}

/**
 * What a saveBar draws, from its props: `shown` (a change waits, or, with
 * `showWhileWaiting`, fields under review wait), the change and waiting
 * counts, its message (`messageWaiting` while fields wait), its status tag
 * ("" when none waits), its reviewed tag (3.17: `statusReviewed`, "" unless
 * the review is open and a field is reviewed) and whether it offers Discard
 * (only while a change waits). The stock bar and a host's swap both draw
 * from it.
 */
export function saveBarState(props) {
  const edits = editCount(props?.edits);
  const {waiting, reviewed, open} = reviewCounts(props);
  const reviewedShown = open && reviewed > 0 && typeof props?.statusReviewed === "string";
  const shown = edits > 0 || (waiting > 0 && showsWhileWaiting(props));
  const message = waiting > 0 && props?.messageWaiting ? props.messageWaiting : props?.message;
  return {
    shown,
    edits,
    waiting,
    reviewed,
    message: typeof message === "string" ? message : "",
    status: waiting > 0 ? countText(props?.status, props?.statusOne, waiting) : "",
    statusReviewed: reviewedShown ? countText(props.statusReviewed, props.statusReviewedOne, reviewed) : "",
    discard: edits > 0,
  };
}

/**
 * What a saveBar's Save does: "confirm" (open the dialog: fields still
 * wait), "then" (save and run the confirm's then action: nothing waits, it
 * is offered and `thenWhenClear`), "save", or "none" (no change and no
 * dialog to open: nothing to send).
 */
export function saveDecision(props) {
  const confirm = props?.confirm;
  const hasConfirm = Boolean(confirm) && typeof confirm === "object";
  if (hasConfirm && waitingReviews(props) > 0) return "confirm";
  const decision = hasConfirm && confirm.thenWhenClear === true && thenOffered(props) ? "then" : "save";
  return decision === "save" && !choiceSends(props, "save") ? "none" : decision;
}

/**
 * Whether choosing `choice` sends anything: "then" always does (the then
 * action runs, with the changes if any); "save" only while a change waits.
 * A save with nothing changed writes nothing, so it sends nothing.
 */
export function choiceSends(props, choice) {
  return choice === "then" || editCount(props?.edits) > 0;
}

/**
 * The words of a saveBar's dialog for the fields still waiting: title,
 * message, and the buttons (`thenLabel` only while it is offered).
 */
export function confirmTexts(props) {
  const confirm = props?.confirm || {};
  const count = waitingReviews(props);
  return {
    count,
    title: countText(confirm.title, confirm.titleOne, count),
    message: countText(confirm.message, confirm.messageOne, count),
    cancelLabel: confirm.cancelLabel || "",
    saveLabel: confirm.saveLabel || "",
    thenLabel: thenOffered(props) ? confirm.thenLabel || "" : "",
  };
}

/** The save_changes envelope a saveBar sends for `choice` ("save" or "then"). */
export function saveSpec(props, choice) {
  const action = props?.action;
  if (!action || typeof action.action !== "string") return null;
  return {
    name: action.action,
    context: {...(action.context || {}), choice},
    catalogId: ASH_A2UI_CATALOG_ID,
  };
}

// Schema builders from web_core's OWN zod (3.x), the instance the
// GenericBinder introspects. Importing the module directly (rather than
// receiving builders through `deps`) guarantees instance identity: the
// host bundle resolves the same specifier the renderer uses, so there is
// no dual-zod hazard regardless of which zod the host itself bundles.
import {
  ActionSchema,
  ChildListSchema,
  ComponentIdSchema,
  CreateSurfaceMessageSchema,
  DynamicBooleanSchema,
  DynamicNumberSchema,
  DynamicStringSchema,
  DynamicValueSchema,
  TextApi,
  WeightSchema,
} from "@a2ui/web_core/v1_0";

/** The admin catalog id a surface must declare to resolve here. */
const ADMIN_CATALOG_ID = "https://github.com/lukegalea/ash_a2ui/catalogs/admin/v3";

/** The admin catalog contract version (minor versions are additive). */
export const ADMIN_CATALOG_VERSION = "3.17.0";

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

/**
 * The stock reference-link activation, for a host element that draws a
 * `_links` entry itself (a catalog swap drawing its own link element): call
 * it from the link's click handler. A plain primary click on a link to a
 * record (one with a `surface`) is handed to the host as an openSurface
 * request (`deps.openSurface` when given, else OPEN_SURFACE_EVENT raised from
 * `source`, which the shipped hook turns into the `"a2ui:open_surface"`
 * LiveView event), and the browser's own navigation and the click's bubbling
 * are stopped. A modified or middle click, and a plain link (`link_url`, no
 * `surface`), keep the browser's own behaviour, so the server-built `href`
 * still opens in a new tab. Returns whether the link was opened in place.
 *
 * @param {MouseEvent} event the click
 * @param {object} link one entry of `linkEntries(row._links[field])`
 * @param {{source?: Element, surfaceId?: string, deps?: object}} [options]
 *   `source`: the element raising the event (inside the surface);
 *   `surfaceId`: the surface it belongs to; `deps`: the catalog's deps, for
 *   their `openSurface` callback
 * @returns {boolean}
 */
export function activateLink(event, link, {source, surfaceId, deps} = {}) {
  if (!link || typeof link.surface !== "string" || link.surface === "") return false;
  if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
    return false;
  }
  event.preventDefault();
  event.stopPropagation();
  requestOpenSurface(deps, openSurfaceArgs(link), {surfaceId, source, href: link.href});
  return true;
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
  alertBanner: "ash-admin-alert-banner",
  confirmDialog: "ash-admin-confirm-dialog",
  calendarView: "ash-admin-calendar-view",
  liveDiagram: "ash-admin-live-diagram",
  filterPicker: "ash-admin-filter-picker",
  documentPane: "ash-admin-document-pane",
  documentViewer: "ash-admin-document-viewer",
  saveBar: "ash-admin-save-bar",
};

/** Basic input kinds this catalog replaces with a11y-hardened elements. */
const INPUT_OVERRIDE_KINDS = ["TextField", "CheckBox", "ChoicePicker", "DateTimeInput"];

/**
 * The basic kinds this catalog renders itself: the a11y-hardened inputs and
 * the prompt Modal. The admin catalog document declares exactly these basic
 * kinds, and on an admin surface they carry no `@catalogId`
 * (`AshA2ui.Experience.admin_basic_kinds/0`).
 */
export const ADMIN_BASIC_KINDS = [...INPUT_OVERRIDE_KINDS, "Modal"];
const INPUT_OVERRIDE_TAGS = {
  TextField: "ash-admin-textfield",
  CheckBox: "ash-admin-checkbox",
  ChoicePicker: "ash-admin-choicepicker",
  DateTimeInput: "ash-admin-datetimeinput",
};

/**
 * The element that has focus inside `element`, whichever DOM it renders
 * into, or null when focus is elsewhere.
 *
 * An element with its own shadow root (the @a2ui/lit 0.15.0 A2uiLitElement,
 * or a plain custom element such as nb-calendar) keeps its focus in that
 * root's `activeElement`. One rendered into light DOM (A2uiLitElement whose
 * `createRenderRoot()` returns `this`, the upstream default after 0.15.0)
 * has no shadow root: its focus is the `activeElement` of the root it sits
 * in, the document or an enclosing shadow root, when that element is
 * inside it.
 */
function focusedIn(element) {
  if (!element) return null;
  const renderRoot = element.renderRoot;
  const own = renderRoot && renderRoot !== element ? renderRoot : element.shadowRoot;
  if (own) return own.activeElement ?? null;
  const active = element.getRootNode?.()?.activeElement ?? null;
  return active && active !== element && element.contains(active) ? active : null;
}

/**
 * The element that has focus in the root `element` sits in (its neighbours'
 * root, not its own): the control that opened a dialog, say. Falls back to
 * `document.activeElement`.
 */
function focusedAround(element) {
  return element?.getRootNode?.()?.activeElement ?? document.activeElement ?? null;
}

// Responsive breakpoint: the DataGrid renders a real table at ≥ 48rem and a
// card list below it (CSS container query on the grid host).
const GRID_TABLE_MIN = "48rem";
void GRID_TABLE_MIN;

/**
 * Builds the admin catalog. See the module docs for the `deps` contract:
 * `{basicCatalog, A2uiLitElement, A2uiController, lit: {html, css,
 * nothing}}`, plus the optional `loadMermaid` (a function
 * returning a promise of the mermaid engine, called the first time a
 * `liveDiagram` draws; see priv/js/ash_a2ui_mermaid.js), `loadPdf` (a
 * function returning a promise of the pdf.js engine, called the first time
 * a `documentViewer` opens a document; see priv/js/ash_a2ui_pdf.js) and
 * `openSurface`, and `renderActionButton(opts)`: every button the catalog
 * draws for an action (row actions, the form's primary button, dialog
 * Cancel/Confirm, pager, calendar tools) is passed to it, and a host that
 * returns a Lit template draws the button with its own design system;
 * returning undefined keeps the stock `<button class="am-btn">`. The
 * options are documented on `stockActionButton` in this module.
 *
 * @returns {object} a `@a2ui/web_core` Catalog registered under the admin
 *   catalog id, extending `deps.basicCatalog`.
 */
export function createAshAdminCatalog(deps) {
  const {basicCatalog, A2uiLitElement, A2uiController, lit} = deps || {};

  if (
    !basicCatalog ||
    !A2uiLitElement ||
    !A2uiController ||
    !lit ||
    !lit.html ||
    !lit.css ||
    !lit.nothing
  ) {
    throw new Error(
      "createAshAdminCatalog: missing deps. Pass {basicCatalog, A2uiLitElement, " +
        "A2uiController, lit: {html, css, nothing}}.",
    );
  }

  const schemas = buildSchemas(basicCatalog);
  // filterPicker extends the basic ChoicePicker's schema, so it exists only
  // when the basic catalog has one to extend.
  const adminApis = Object.fromEntries(
    Object.keys(TAGS)
      .filter((kind) => schemas[kind])
      .map((kind) => [kind, {name: kind, schema: schemas[kind], tagName: TAGS[kind]}]),
  );

  defineAdminElements(deps, {adminApis, inputSchemas: schemas.inputs});

  // The admin catalog extends the basic catalog: carry every basic component
  // (or the host's merged/overridden version of it), swapping the four input
  // kinds for the a11y-hardened elements and the Modal for the one closing
  // a prompt on a success outcome (boards and basic-composed prompts — see
  // "Prompt Modal" in ash_a2ui_catalog.js), then add the semantic kinds.
  const modal = promptModalComponent(basicCatalog);
  const components = [...basicCatalog.components.values()].map((component) => {
    if (INPUT_OVERRIDE_KINDS.includes(component.name)) {
      // 1.10: ChoicePicker and TextField validate against their extended
      // schemas (the basic ones are strict and reject the added keys).
      const schema = schemas.inputs[component.name] || component.schema;
      return {...retagged(component, INPUT_OVERRIDE_TAGS[component.name]), schema};
    }
    if (component.name === "Modal" && modal) return modal;
    return component;
  });

  // The catalog's own client function: openSurface (reference-link
  // navigation — see OPEN_SURFACE_EVENT). Usable from any functionCall
  // action as {"@call": "openSurface", "args": {surface, recordId, query}};
  // like every navigation it runs only from a user gesture.
  const openSurfaceFunction = {
    name: "openSurface",
    returnType: "void",
    requiresUserActivation: true,
    schema: schemas.openSurfaceArgs,
    execute: (args, context) => {
      requestOpenSurface(deps, openSurfaceArgs(args || {}), {surfaceId: context?.surface?.id});
      return undefined;
    },
  };

  return basicCatalog.derive({
    catalogId: ADMIN_CATALOG_ID,
    components: [...components, ...Object.values(adminApis)],
    functions: [
      ...[...basicCatalog.functions.values()].filter((fn) => fn.name !== "openSurface"),
      openSurfaceFunction,
    ],
  });
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
export function buildSchemas(basicCatalog = null) {
  // --- static primitives on web_core's own zod ------------------------------
  // Taken from web_core's exported schemas through public zod-3 API
  // (`.unwrap()`, `.removeDefault()`, `.array()`, static `.create()`), so
  // static props need no host `z`. Each primitive classifies STATIC in the
  // binder (plain ZodString/Number/Boolean/Any/Record; `ComponentIdSchema`
  // is a plain ZodString whose `component-id` child-ref stamp only matters
  // inside ChildList classification, which these positions never reach).
  const createSurface = CreateSurfaceMessageSchema.shape.createSurface.shape;
  // An empty object with no description (a REF description, like
  // Checkable's, would classify every admin component as that def).
  const EmptyObject = CreateSurfaceMessageSchema.pick({}).strip();
  const Str = ComponentIdSchema;
  const Num = WeightSchema;
  const Bool = createSurface.sendDataModel.unwrap();
  const RecordAny = createSurface.dataModel.unwrap();
  const Any = RecordAny.valueSchema;
  const ArrayOf = (element) => element.array();
  const ZodEnum = TextApi.schema.shape.variant.unwrap().removeDefault().constructor;
  const EnumOf = (values) => ZodEnum.create(values);

  const formatEnum = () => EnumOf(["text", "datetime", "boolean", "number"]).optional();

  // The admin envelopes ({"name": "query", "context": {...}}, the
  // catalog's actionEvent), sent as an ashAction with the context's
  // {"@path"} bindings resolved at click time. Deliberately NOT an
  // ActionSchema: that would make the binder resolve it into a callable
  // with the component's own scope, and the components add to the context
  // (pageDelta, a sort, a calendar window) before sending.
  const bareEvent = () => EmptyObject.extend({name: Str, context: RecordAny.optional()});

  // 1.10: the basic ChoicePicker and TextField, extended with the keys the
  // admin emission adds (both basic schemas are strict). ChoicePicker:
  // `hint` (static), `counts` and `dynamicOptions` (bindings: a value→count
  // map and an option list from the query state) and options that may carry
  // `parent` / `group`. TextField: `placeholder`. Kept as the basic schema
  // when the host's catalog has none to extend.
  const inputs = {};
  const choice = basicCatalog?.components?.get?.("ChoicePicker")?.schema;
  if (choice && typeof choice.extend === "function") {
    inputs.ChoicePicker = choice.extend({
      options: ArrayOf(
        EmptyObject.extend({
          label: DynamicStringSchema,
          value: Str,
          parent: Str.optional(),
          group: Bool.optional(),
        }),
      ),
      hint: Str.optional(),
      counts: DynamicValueSchema.optional(),
      dynamicOptions: DynamicValueSchema.optional(),
    });
  }
  const text = basicCatalog?.components?.get?.("TextField")?.schema;
  if (text && typeof text.extend === "function") {
    inputs.TextField = text.extend({placeholder: Str.optional()});
  }

  return {
    inputs,
    // A query filter's picker: the extended ChoicePicker under its own name
    // (two catalogs declaring one name would make a mixed surface
    // ambiguous).
    filterPicker: inputs.ChoicePicker,
    entityPage: EmptyObject.extend({
      title: DynamicStringSchema,
      description: DynamicStringSchema.nullable().optional(),
      children: ChildListSchema.optional(),
      // 1.6: false when the host page already owns the heading.
      headerVisible: Bool.optional(),
      // 3.5: the declared page header, the lead components and their
      // gates, and the section nav (static: the element reads the paths
      // they name itself).
      header: RecordAny.optional(),
      lead: ChildListSchema.optional(),
      leadVisible: RecordAny.optional(),
      nav: RecordAny.optional(),
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
          // 1.8 cell hints (column entities): a second line, a leading
          // icon, a "+N more" tag and a detail line, all row-relative.
          subtitle: RecordAny.optional(),
          icon: RecordAny.optional(),
          more: RecordAny.optional(),
          // 3.3: the row's review of the column's field ({path}); the
          // subtitle's own review rides on subtitle.reviewPath.
          review: RecordAny.optional(),
          // 3.9: the column's field action (a rowActions-shaped entry) and
          // the row's offer of it ({path}, row-relative).
          action: RecordAny.optional(),
          actionVisible: RecordAny.optional(),
          // 3.12: the row's masked-field reason ({path}, row-relative); a
          // non-empty one draws the cell as plain text (the masked word).
          masked: RecordAny.optional(),
          detail: RecordAny.optional(),
          // 1.10: header help ({title, body}) and the field a header
          // sorts by when it is not the column's own path.
          help: RecordAny.optional(),
          sortField: Str.optional(),
          // 1.10: a fixed width in px, and the plural noun of the "+N
          // more" list (more.valuesPath names the row's list of values).
          width: Num.optional(),
          moreNoun: Str.optional(),
          // 1.11: a third line ({path, text?}) and the direction a
          // header's first click sorts in when it is not ascending.
          caption: RecordAny.optional(),
          sortFirst: EnumOf(["desc"]).optional(),
          // 1.12: where a list-rows renderer draws the column (a row
          // layout's trailing or expand fields).
          // 1.14: group / groupSubtitle head a run of rows sharing the value;
          // 1.15: leading is a short code before the row's title.
          placement: EnumOf(["trailing", "expand", "group", "groupSubtitle", "leading"]).optional(),
          // 1.16: the value is a list of {term, value} pairs.
          pairs: Bool.optional(),
          // 3.10: the row's normalized pairs ({path}, row-relative), each
          // with its own review, key and offer, and the button per item.
          items: RecordAny.optional(),
          pairAction: RecordAny.optional(),
          // 1.14: the field's empty_text, for a list-rows renderer.
          emptyText: Str.optional(),
        }),
      ),
      // 1.12: "rows" asks for list rows instead of a grid (display :rows).
      // 1.16: "cards", one card per row.
      layout: EnumOf(["rows", "cards"]).optional(),
      // 1.16: the words on the disclosure opening the expand columns.
      expandLabel: Str.optional(),
      // 1.18: the header of the table's own card and the caption under it,
      // present only when declared (label stays the accessible name).
      heading: Str.optional(),
      description: Str.optional(),
      // 1.14: the icon name for a list-rows renderer's group headers.
      groupIcon: Str.optional(),
      // 1.15: the line under the rows (a binding) and the link beside it.
      footerNote: DynamicValueSchema.optional(),
      footerLink: RecordAny.optional(),
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
          // 3.13: the ConfirmDialog's heading and body for a destructive
          // entry, translated by the server; a body only for a destroy.
          confirmTitle: Str.optional(),
          confirmBody: Str.optional(),
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
        // 1.9: the row click drawn as one button per row (`inline`), its
        // label and Button variant read from the row (`_primary_label`,
        // `_primary_variant`). Static, like the rest of the envelope.
        labelPath: Str.optional(),
        variantPath: Str.optional(),
        inline: Bool.optional(),
        // 1.10: the inline button column's fixed width in px.
        width: Num.optional(),
      }).optional(),
      // 1.7: {path, action} — the current sort's binding ({field, dir} or
      // null) and the query envelope a sortable header dispatches. Static,
      // like rowActions: the grid reads the path and resolves the envelope
      // itself at click time.
      sort: RecordAny.optional(),
      children: ChildListSchema.optional(),
      weight: Num.optional(),
    }),

    emptyState: EmptyObject.extend({
      message: DynamicStringSchema.nullable().optional(),
      // 1.10: a declared empty state — title and icon (inbox | search |
      // archive) bound like the message, and the clear action
      // ({label, action}: the query envelope sent after the client clears
      // search and filters) shown while clearVisible.
      title: DynamicStringSchema.nullable().optional(),
      icon: DynamicStringSchema.nullable().optional(),
      clearAction: RecordAny.optional(),
      clearVisible: DynamicBooleanSchema.nullable().optional(),
      child: Str.optional(),
      children: ChildListSchema.optional(),
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
      previousAction: bareEvent().optional(),
      nextAction: bareEvent().optional(),
      // 1.10: the page sizes offered and the envelope sent (with the picked
      // pageSize, page 1) when one is picked.
      pageSizeOptions: ArrayOf(Num).optional(),
      pageSizeAction: bareEvent().optional(),
      weight: Num.optional(),
    }),

    recordPanel: EmptyObject.extend({
      mode: DynamicStringSchema.nullable().optional(),
      title: DynamicStringSchema.nullable().optional(),
      recordId: DynamicValueSchema.nullable().optional(),
      children: ChildListSchema.optional(),
      weight: Num.optional(),
    }),

    fieldDisplay: EmptyObject.extend({
      label: DynamicStringSchema,
      value: DynamicValueSchema.nullable().optional(),
      format: formatEnum(),
      // 1.1: the field's reference link(s), bound like the value.
      link: DynamicValueSchema.nullable().optional(),
      // 1.12: a badge field's text, tone and tooltip; the empty placeholder;
      // whether an empty field draws at all.
      badge: DynamicStringSchema.nullable().optional(),
      badgeTone: DynamicStringSchema.nullable().optional(),
      badgeHelp: DynamicStringSchema.nullable().optional(),
      note: Str.optional(),
      emptyText: Str.optional(),
      hideWhenEmpty: Bool.optional(),
      // 1.17: a steps field's normalized steps, drawn as a numbered stepper.
      steps: DynamicValueSchema.nullable().optional(),
      // 3.1: how a review field's value was filled in: its state and citation.
      review: DynamicValueSchema.nullable().optional(),
      // 3.12: the masked-field reason; a non-empty one draws the value as
      // plain text (the masked word), ignoring format/link/badge/emptyText.
      masked: DynamicValueSchema.nullable().optional(),
      // 3.2: a field action's button (a rowActions-shaped entry) and
      // whether the record offers it.
      action: RecordAny.optional(),
      actionVisible: DynamicValueSchema.nullable().optional(),
      // 3.11: editing in place: the card, field and input (static), the
      // stored value, whether the record offers editing, the unsaved change
      // and a refused save's message (bindings).
      edit: RecordAny.optional(),
      editValue: DynamicValueSchema.nullable().optional(),
      editVisible: DynamicValueSchema.nullable().optional(),
      editDraft: DynamicValueSchema.nullable().optional(),
      editError: DynamicValueSchema.nullable().optional(),
      // 3.15: the field worked out again with the unsaved changes ({value, steps?}).
      preview: DynamicValueSchema.nullable().optional(),
      weight: Num.optional(),
    }),

    // 3.11: the bar that saves or discards the unsaved changes.
    saveBar: EmptyObject.extend({
      message: Str.optional(),
      messageWaiting: Str.optional(),
      status: Str.optional(),
      statusOne: Str.optional(),
      // 3.17: a tag counting the fields reviewed, beside status.
      statusReviewed: Str.optional(),
      statusReviewedOne: Str.optional(),
      saveLabel: Str,
      discardLabel: Str,
      edits: DynamicValueSchema.nullable().optional(),
      record: DynamicValueSchema.nullable().optional(),
      reviews: ArrayOf(RecordAny).optional(),
      editReviews: Bool.optional(),
      // 3.14: also shown while reviews wait: true, or the record's field gating it.
      showWhileWaiting: Any.optional(),
      // The save_changes envelope (static: the bar adds the choice and the
      // context's bindings resolve at click time).
      action: RecordAny.optional(),
      // 3.15: the preview_changes envelope, sent whenever the changes change
      // (static: the context's bindings resolve when it is sent).
      preview: RecordAny.optional(),
      confirm: RecordAny.optional(),
      domId: Str.optional(),
      weight: Num.optional(),
    }),

    formSection: EmptyObject.extend({
      title: DynamicStringSchema.nullable().optional(),
      columns: Num.int().min(1).max(6).optional(),
      children: ChildListSchema.optional(),
      weight: Num.optional(),
    }),

    actionBar: EmptyObject.extend({
      primaryLabel: DynamicStringSchema.nullable().optional(),
      busy: DynamicBooleanSchema.nullable().optional(),
      destructive: Bool.optional(),
      // Emitted as the submit_form ashAction call ({"functionCall": ...}),
      // binder-resolved into a callable (ActionSchema classifies ACTION via
      // its REF description).
      action: ActionSchema.optional(),
      children: ChildListSchema.optional(),
      weight: Num.optional(),
    }),

    // 3.5: a :detail drawn as an alert.
    alertBanner: EmptyObject.extend({
      variant: Str.optional(),
      layout: Str.optional(),
      title: DynamicStringSchema.nullable().optional(),
      message: DynamicStringSchema.nullable().optional(),
      linkHref: DynamicStringSchema.nullable().optional(),
      linkLabel: DynamicStringSchema.nullable().optional(),
      // 3.6: a review summary's count of fields still waiting.
      count: DynamicValueSchema.nullable().optional(),
      weight: Num.optional(),
    }),

    statusBanner: EmptyObject.extend({
      kind: DynamicStringSchema.nullable().optional(),
      message: DynamicStringSchema.nullable().optional(),
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
      weight: Num.optional(),
    }),

    // 3.4: a document pane: the surface's sections beside its document.
    // `document` and `shown` bind the record's document and the pane's
    // state; `toggleAction` is the bare document_pane event, sent with
    // `shown` added.
    documentPane: EmptyObject.extend({
      pane: Str.optional(),
      label: Str.optional(),
      description: Str.optional(),
      document: DynamicValueSchema.nullable().optional(),
      shown: DynamicBooleanSchema.nullable().optional(),
      selected: DynamicStringSchema.nullable().optional(),
      regionHref: Str.optional(),
      toggleAction: bareEvent().optional(),
      viewer: Str.optional(),
      children: ChildListSchema.optional(),
      weight: Num.optional(),
    }),

    // 3.4: a PDF drawn with pdf.js, its regions on the pages. `regionAction`
    // is the bare document_region event, sent with `regionId` added.
    documentViewer: EmptyObject.extend({
      src: DynamicStringSchema.nullable().optional(),
      fileName: DynamicStringSchema.nullable().optional(),
      regions: DynamicValueSchema.nullable().optional(),
      selected: DynamicStringSchema.nullable().optional(),
      regionAction: bareEvent().optional(),
      strings: RecordAny.optional(),
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

/** 1.10 empty-state icons (Feather-style paths, 24-unit viewBox). */
const EMPTY_ICONS = {
  inbox:
    "M22 12h-6l-2 3h-4l-2-3H2 M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z",
  search: "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z M21 21l-4.35-4.35",
  archive: "M21 8v13H3V8 M1 3h22v5H1z M10 12h4",
};

/** The field a column's header sorts by: its `sortField` (1.10), else its path. */
function sortField(column) {
  return typeof column?.sortField === "string" && column.sortField !== ""
    ? column.sortField
    : column?.path;
}

/**
 * A column help body (1.10) as paragraphs: blank lines separate them, and a
 * line `**Term** — text` is a definition `{term, text}`.
 */
function helpParagraphs(body) {
  const definition = (line) => line.match(/^\*\*(.+?)\*\*\s*[—–-]\s*(.*)$/);
  return String(body)
    .split(/\n\s*\n/)
    .flatMap((block) => {
      const lines = block.split("\n").map((line) => line.trim()).filter((line) => line !== "");
      if (lines.length === 0) return [];
      // A block of definitions is one entry per line; prose lines join.
      if (lines.every((line) => definition(line))) {
        return lines.map((line) => {
          const [, term, text] = definition(line);
          return {term, text};
        });
      }
      return [{text: lines.join(" ")}];
    });
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
 * The button tone of a primary action variant (the A2UI Button variants):
 * primary is the filled call to action, borderless reads as a link,
 * default (and anything unknown) is the outlined button.
 */
function primaryVariantTone(variant) {
  if (variant === "primary") return "primary";
  if (variant === "borderless") return "quiet";
  return "default";
}

/**
 * The action an admin envelope sends, as an `actionSpec`: a row action
 * entry (`{label, action: <name>, context}`) or a bare admin envelope
 * (`{name, context}`: pagination, sort, the empty-state clear, the
 * calendar window) is server-handled and goes out as the ash_a2ui
 * catalog's `ashAction`; a full `ashAction` Action (`{functionCall}`)
 * keeps its catalog id. Null for anything else, an event action included.
 */
function adminActionSpec(envelope) {
  if (!envelope || typeof envelope !== "object") return null;
  const name = typeof envelope.action === "string" ? envelope.action : envelope.name;
  if (typeof name === "string") {
    return {name, context: envelope.context || {}, catalogId: ASH_A2UI_CATALOG_ID};
  }
  return actionSpec(typeof envelope.action === "object" ? envelope.action : envelope);
}

/**
 * The name a row action entry's control carries in `data-a2ui-action`: the
 * declared row action's name (its envelope's `context.action`), else the
 * entry's own action (`view_record`, `start_edit`, `context_select`).
 */
function rowActionKey(action) {
  const named = action?.context?.action;
  if (typeof named === "string" && named !== "") return named;
  return typeof action?.action === "string" ? action.action : "";
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
  const valuePath = bindingPath(raw?.value);
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
    values: {"@path": "/form"},
    recordId: {"@path": "/form/id"},
  };
  const dataModel = surface.dataModel;
  if (dataModel.get("/query") !== null && dataModel.get("/query") !== undefined) {
    context.query = {"@path": "/query"};
  }
  if (dataModel.get("/context") !== null && dataModel.get("/context") !== undefined) {
    context.contexts = {"@path": "/context"};
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
function defineAdminElements(deps, {adminApis, inputSchemas = {}}) {
  const {basicCatalog, A2uiLitElement, A2uiController, lit} = deps;
  const {html, css, nothing} = lit;
  const {shared, buttons, content} = createAdminStyles(css);

  // --- action buttons ----------------------------------------------------------

  /**
   * The stock action button: a native `<button class="am-btn ...">`.
   *
   * `opts` is the whole contract of the `deps.renderActionButton` seam:
   *   label          string or Lit template, the button's content
   *   tone           "default" (outlined) | "primary" (filled) | "quiet" (link-like)
   *   destructive    boolean; a primary tone draws as the destructive fill,
   *                  a quiet one as danger text
   *   size           "md" (default) | "sm"
   *   busy           undefined when the button has no busy state; otherwise
   *                  true draws a spinner and disables the button, with
   *                  `aria-busy` reflecting it
   *   disabled       boolean
   *   pressed        undefined, or the `aria-pressed` state of a toggle
   *   primaryAction  boolean; marks a row's primary action (`data-primary-action`)
   *   icon           optional icon name (3.2, a field action's): a host may draw
   *                  the button as that icon, the label becoming its accessible
   *                  name and tooltip; the stock button draws the label
   *   onClick        (event) => void, called for an enabled button
   */
  function stockActionButton(opts) {
    const {label, tone = "default", destructive = false, size = "md", busy, disabled = false, pressed, primaryAction = false, onClick} = opts;
    const classes = ["am-btn"];
    if (tone === "primary") classes.push(destructive ? "am-btn-destructive" : "am-btn-primary");
    if (tone === "quiet") classes.push("am-btn-quiet");
    if (size === "sm") classes.push("am-btn-sm");
    if (tone === "quiet" && destructive) classes.push("am-btn-danger");
    return html`<button
      type="button"
      class=${classes.join(" ")}
      data-am-button
      ?data-primary-action=${primaryAction}
      ?disabled=${disabled || busy === true}
      aria-busy=${busy === undefined ? nothing : busy ? "true" : "false"}
      aria-pressed=${pressed === undefined ? nothing : pressed ? "true" : "false"}
      @click=${onClick}
    >
      ${busy === true ? html`<span class="am-spinner" aria-hidden="true"></span>` : nothing}
      ${label}
    </button>`;
  }

  /**
   * Every button the catalog draws for an action goes through here, so a
   * host can draw them with its own design system: `deps.renderActionButton(opts)`
   * receives the options documented on stockActionButton and returns a Lit
   * template, or undefined/null to leave that button to the stock drawing.
   * The element it draws must be the focusable control itself (or a host that
   * delegates focus), honour `disabled` and `aria-busy`, call `onClick(event)`
   * only while enabled, and carry the `data-am-button` attribute, which the
   * dialogs' focus traps look for.
   */
  function renderActionButton(opts) {
    if (typeof deps.renderActionButton === "function") {
      const drawn = deps.renderActionButton(opts);
      if (drawn !== undefined && drawn !== null) return drawn;
    }
    return stockActionButton(opts);
  }

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
    const label = str(link.label) || str(link.recordId) || str(link.href);

    // 1.13: a plain link (no surface) is a page or address: the browser follows it.
    // 1.15: one marked download fetches the file instead.
    if (!link.surface) {
      return link.download
        ? html`<a class="am-link" href=${link.href} download>${label}</a>`
        : html`<a class="am-link" href=${link.href}>${label}</a>`;
    }

    const activate = (event) =>
      activateLink(event, link, {
        surfaceId: element.context?.dataContext?.surface?.id,
        source: element,
        deps,
      });

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
  // rejection) writes /ui/feedback, subscribed as an OBJECT path through
  // subscribeActionOutcomes (see "Action outcomes" in ash_a2ui_catalog.js),
  // so the settle fires on every outcome write, also one that leaves the
  // value unchanged: view_record and cancel_record_task write the
  // already-clear feedback. The hook's pending write and a whole-model
  // refresh (a PubSub push or URL-state change writing "/") are not
  // outcomes and do not settle. No styling round trip, no phx-*-loading:
  // these components own their shadow DOM.
  function markActionBusy(component) {
    if (component._amSettleUnsubscribes) return;
    const surface = component.surface;
    if (!surface || !surface.dataModel || typeof surface.dataModel.subscribe !== "function") {
      return;
    }
    component._amSettleUnsubscribes = subscribeActionOutcomes(surface.dataModel, () =>
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
  defineAlertBanner();
  defineConfirmDialog();
  defineCalendarView();
  defineLiveDiagram();
  defineSaveBar();
  defineDocumentElements({
    A2uiLitElement,
    A2uiController,
    lit,
    apis: adminApis,
    tags: TAGS,
    styles: {shared, buttons},
    renderActionButton,
    dispatchActionSpec,
    bindingPath,
    applyWeight,
    childRefs,
    catalogId: ASH_A2UI_CATALOG_ID,
    loadPdf: deps.loadPdf,
  });
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
    const schema = inputSchemas[name] || entry.schema;
    return {name: entry.name, schema, tagName: INPUT_OVERRIDE_TAGS[name]};
  }

  // --- EntityPage: page shell ---------------------------------------------
  //
  // 3.5: a record page the surface draws whole. `header` is the page header
  // the surface declares (breadcrumb, title, tags, meta, buttons), read from
  // its record at `header.path` by field name; `lead` the components drawn
  // full width under it (each gated by `leadVisible` when listed there);
  // `nav` a sticky section nav beside the children. The element subscribes
  // to the record and to /page itself: they are paths in static props, so
  // the controller does not.
  //
  // A host drawing the page with its own design system subclasses this
  // element and overrides the drawing only: `renderHeader(model)` (the
  // resolved `headerModel()`), `renderNav(nav)` and `renderNavItem(item,
  // index)`; `onHeaderAction(action)` runs a button. The nav's behaviour finds its
  // entries by `data-a2ui-nav-item` (the entry's index) and marks the
  // chosen one with the `selected` attribute (and aria-current), so an
  // override keeps both. `navLine()` is the line a section stops on. A
  // breadcrumb step the surface declared live (3.7) has `crumb.live`
  // (navigate or patch) in the model: an override puts it on its link as
  // the `data-a2ui-live` attribute (LIVE_LINK_ATTRIBUTE), on the element
  // whose `href` holds the address, and the AshA2ui hook follows it.

  function defineEntityPage() {
    const tag = TAGS.entityPage;
    if (customElements.get(tag)) return;

    // A section's outline, while it is the one just chosen (3s).
    const OUTLINE_MS = 3000;
    // Input that ends a held highlight or a pending arrival: the person's own.
    const PERSON = ["wheel", "touchstart", "keydown", "mousedown"];

    class AshAdminEntityPage extends A2uiLitElement {
      static styles = [
        shared,
        buttons,
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
          .page-head {
            display: flex;
            flex-wrap: wrap;
            align-items: flex-start;
            justify-content: space-between;
            gap: var(--am-space-m);
            margin: 0 0 var(--am-space-xl);
          }
          .page-crumbs ol {
            display: flex;
            flex-wrap: wrap;
            gap: var(--am-space-2xs);
            margin: 0 0 var(--am-space-2xs);
            padding: 0;
            list-style: none;
            font-size: var(--am-font-size-s);
            color: var(--am-text-muted);
          }
          .page-crumbs li + li::before {
            content: "/";
            margin-inline-end: var(--am-space-2xs);
          }
          .page-meta {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--am-space-xs);
            margin-top: var(--am-space-xs);
            font-size: var(--am-font-size-s);
            color: var(--am-text-muted);
          }
          .page-meta [data-tone="warning"] {
            color: var(--am-warning);
          }
          .page-actions {
            display: flex;
            flex-wrap: wrap;
            gap: var(--am-space-xs);
          }
          .page-lead {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-xl);
            margin: 0 0 var(--am-space-xl);
          }
          .page-with-nav {
            display: grid;
            gap: var(--am-space-xl);
            align-items: start;
          }
          @media (min-width: 64rem) {
            .page-with-nav {
              grid-template-columns: 12.5rem minmax(0, 1fr);
            }
            .page-nav {
              position: sticky;
              top: var(--ash-admin-nav-top, var(--am-space-xl));
            }
          }
          .page-nav {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-2xs);
          }
          .page-nav a {
            padding: var(--am-space-2xs) var(--am-space-s);
            border-radius: var(--am-radius-s);
            color: var(--am-text-muted);
            text-decoration: none;
          }
          .page-nav a[selected] {
            color: var(--am-text);
            background: var(--am-hover-tint);
            font-weight: var(--am-font-weight-medium);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.entityPage);
      }

      get surface() {
        return this.context?.dataContext?.surface;
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        this.watchPaths(this.controller?.props);
      }

      updated(changedProperties) {
        super.updated?.(changedProperties);
        if (this.controller?.props?.nav && !this._amNavStarted) this.startNav();
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        this.unwatchPaths();
        this.stopNav();
      }

      // --- the record, the host page's values and the lead gates ----------

      /** The data-model paths this page reads by itself, from its props. */
      watchedPaths(props) {
        const paths = [];
        if (props?.header?.path) paths.push(props.header.path);
        if (props?.header) paths.push("/page");
        for (const path of Object.values(props?.leadVisible || {})) {
          if (typeof path === "string") paths.push(path);
        }
        for (const ref of childRefs(props?.children)) paths.push(...this.blankPaths(ref.id));
        return [...new Set(paths)];
      }

      watchPaths(props) {
        const dataModel = this.surface?.dataModel;
        const paths = this.watchedPaths(props);
        const key = paths.join("|");
        if (!dataModel || typeof dataModel.subscribe !== "function") return;
        if (this._amWatched?.key === key && this._amWatched.dataModel === dataModel) return;
        this.unwatchPaths();
        this._amWatched = {
          key,
          dataModel,
          subscriptions: paths.map((path) => dataModel.subscribe(path, () => this.requestUpdate())),
        };
      }

      unwatchPaths() {
        for (const subscription of this._amWatched?.subscriptions || []) {
          try {
            subscription.unsubscribe();
          } catch {
            // The data model may already be gone (surface torn down).
          }
        }
        this._amWatched = null;
      }

      read(path) {
        const dataModel = this.surface?.dataModel;
        return path && dataModel ? dataModel.get(path) : undefined;
      }

      // --- the header -------------------------------------------------------

      /**
       * The declared header with its values read from the record: what an
       * override draws. Items and links without a value are left out, and
       * buttons not offered.
       */
      headerModel() {
        const header = this.controller?.props?.header;
        if (!header || typeof header !== "object") return null;
        const record = this.read(header.path) || {};
        const page = this.read("/page") || {};
        const value = (field) => (field ? str(record[field]) : "");

        const item = (entry, kind) => ({
          kind,
          field: entry.field,
          text: value(entry.field),
          tone: entry.tone ? value(entry.tone) || null : null,
          icon: entry.iconField ? value(entry.iconField) || null : entry.icon || null,
          help: entry.helpField ? value(entry.helpField) || null : entry.help || null,
          helpLabel: entry.helpLabel || null,
        });

        const pageValue = (path) => {
          const key = typeof path === "string" ? path.replace(/^\/page\//, "") : "";
          return key ? str(page[key]) : "";
        };

        return {
          breadcrumbLabel: str(header.breadcrumbLabel),
          breadcrumb: [
            ...(header.breadcrumb || []).map((crumb) => ({
              label: str(crumb.label),
              href: pageValue(crumb.pagePath) || str(crumb.href) || null,
              live: LIVE_LINK_KINDS.includes(crumb.live) ? crumb.live : null,
            })),
            {label: value(header.title), href: null, current: true},
          ],
          title: value(header.title),
          tags: (header.tags || []).map((entry) => item(entry, "tag")).filter((entry) => entry.text !== ""),
          meta: (header.meta || []).map((entry) => item(entry, "meta")).filter((entry) => entry.text !== ""),
          actions: (header.actions || [])
            .map((action) => ({
              name: action.name,
              label: str(action.label),
              variant: action.variant || "secondary",
              title: action.title || null,
              href: action.href ? value(action.href) || null : null,
              entry: action.action || null,
              offered: action.visible ? record[action.visible] === true : true,
              busy: this._amBusyAction === action.name,
            }))
            .filter((action) => action.offered && (action.entry || action.href)),
        };
      }

      /** Runs a header button's action: its envelope, bindings resolved now. */
      onHeaderAction(action) {
        const spec = adminActionSpec(action?.entry);
        if (!spec || this._amBusyAction || !this.context?.componentModel) return;
        this._amBusyAction = action.name;
        markActionBusy(this);
        this.requestUpdate();
        dispatchActionSpec(this.context, spec);
      }

      onActionSettled() {
        this._amBusyAction = null;
      }

      /**
       * A breadcrumb step's link; a live step (3.7) carries data-a2ui-live,
       * which the AshA2ui hook follows inside the LiveView.
       */
      renderCrumbLink(crumb) {
        return html`<a class="am-link" href=${crumb.href} data-a2ui-live=${crumb.live || nothing}>${crumb.label}</a>`;
      }

      /** The stock header: breadcrumb, h1, the line under it, the buttons. */
      renderHeader(model) {
        const tone = (entry) => (entry.tone ? entry.tone : nothing);
        const tooltip = (entry) => entry.help || nothing;
        return html`<header class="page-head" data-a2ui-page-header>
          <div>
            <nav class="page-crumbs" aria-label=${model.breadcrumbLabel || nothing}>
              <ol>
                ${model.breadcrumb.map((crumb) =>
                  crumb.current
                    ? html`<li aria-current="page">${crumb.label}</li>`
                    : html`<li>${crumb.href ? this.renderCrumbLink(crumb) : crumb.label}</li>`,
                )}
              </ol>
            </nav>
            <h1 class="page-title">${model.title}</h1>
            ${model.tags.length + model.meta.length > 0
              ? html`<div class="page-meta">
                  ${model.tags.map(
                    (entry) =>
                      html`<span class="am-badge" data-tone=${tone(entry)} data-field=${entry.field} title=${tooltip(entry)}
                        >${entry.text}</span
                      >`,
                  )}
                  ${model.meta.map(
                    (entry) =>
                      html`<span data-tone=${tone(entry)} data-field=${entry.field} title=${tooltip(entry)}>${entry.text}</span>`,
                  )}
                </div>`
              : nothing}
          </div>
          ${model.actions.length > 0
            ? html`<div class="page-actions">
                ${model.actions.map((action) =>
                  action.href
                    ? html`<a
                        class=${action.variant === "primary" ? "am-btn am-btn-primary" : "am-btn"}
                        data-a2ui-action=${action.name}
                        href=${action.href}
                        title=${action.title || nothing}
                        >${action.label}</a
                      >`
                    : html`<span data-a2ui-action=${action.name}
                        >${renderActionButton({
                          label: action.label,
                          tone: action.variant === "secondary" ? "default" : action.variant,
                          busy: action.busy,
                          onClick: () => this.onHeaderAction(action),
                        })}</span
                      >`,
                )}
              </div>`
            : nothing}
        </header>`;
      }

      // --- lead and body ----------------------------------------------------

      leadShown(id) {
        const path = this.controller?.props?.leadVisible?.[id];
        return typeof path !== "string" || this.read(path) === true;
      }

      renderLead(props) {
        const lead = childRefs(props.lead).filter((ref) => this.leadShown(ref.id ?? ref));
        if (lead.length === 0) return nothing;
        return html`<div class="page-lead">${lead.map((ref) => html`${this.renderNode(ref)}`)}</div>`;
      }

      renderBody(props) {
        return html`<div class="page-body">
          ${this.shownChildren(props).map((ref) => html`${this.renderNode(ref)}`)}
        </div>`;
      }

      /**
       * The body children with something to show. A blank child (a Column
       * with no children, or whose Texts are all empty: the
       * `action_result_panel` until a generic action returns text) is not
       * drawn, so it holds no gap in the page's column; it is drawn as soon
       * as one of its Texts has words (watchedPaths re-renders the page). A
       * host that draws the body itself filters through this too.
       */
      shownChildren(props) {
        return childRefs(props?.children).filter((ref) => !this.blankChild(ref.id));
      }

      /** A component as the surface holds it, or null. */
      bodyComponent(id) {
        try {
          return this.surface?.componentsModel?.get(id) ?? null;
        } catch {
          return null;
        }
      }

      /**
       * Whether a component draws nothing: a Column of blank parts, or a
       * Text whose words (literal or bound) are empty. Anything else, and
       * anything the surface does not hold yet, draws.
       */
      blankChild(id, depth = 0) {
        const node = this.bodyComponent(id);
        if (!node || depth > 8) return false;
        if (node.type === "Text") {
          const text = node.properties?.text;
          const path = bindingPath(text);
          return str(typeof path === "string" ? this.read(path) : text).trim() === "";
        }
        if (node.type === "Column") {
          return childRefs(node.properties?.children).every((ref) => this.blankChild(ref.id, depth + 1));
        }
        return false;
      }

      /** The paths a blank-able body child's Texts are bound to. */
      blankPaths(id, depth = 0) {
        const node = this.bodyComponent(id);
        if (!node || depth > 8) return [];
        if (node.type === "Text") {
          const path = bindingPath(node.properties?.text);
          return typeof path === "string" ? [path] : [];
        }
        if (node.type === "Column") {
          return childRefs(node.properties?.children).flatMap((ref) => this.blankPaths(ref.id, depth + 1));
        }
        return [];
      }

      // --- the section nav --------------------------------------------------

      /** The stock nav: a link per section. */
      renderNav(nav) {
        return html`<nav class="page-nav" id=${nav.id || nothing} aria-label=${str(nav.label) || nothing} data-a2ui-nav>
          ${(nav.items || []).map((item, index) => this.renderNavItem(item, index))}
        </nav>`;
      }

      renderNavItem(item, index) {
        return html`<a
          href=${`#${item.anchor}`}
          id=${item.id || nothing}
          data-a2ui-nav-item=${index}
          data-section=${item.target}
          @click=${(event) => this.onNavClick(event, index)}
          >${str(item.label)}</a
        >`;
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const model = this.headerModel();
        const plain =
          props.headerVisible === false
            ? nothing
            : html`<header class="page-header">
                <h1 class="page-title">${str(props.title)}</h1>
                ${props.description
                  ? html`<p class="page-description">${str(props.description)}</p>`
                  : nothing}
              </header>`;

        return html`
          ${model ? this.renderHeader(model) : plain} ${this.renderLead(props)}
          ${props.nav
            ? html`<div class="page-with-nav">${this.renderNav(props.nav)} ${this.renderBody(props)}</div>`
            : this.renderBody(props)}
        `;
      }

      // --- the section nav's behaviour --------------------------------------

      get navEntries() {
        return [...(this.renderRoot?.querySelectorAll?.("[data-a2ui-nav-item]") || [])];
      }

      get navElement() {
        return this.renderRoot?.querySelector?.("[data-a2ui-nav]") || null;
      }

      navItem(index) {
        return this.controller?.props?.nav?.items?.[index];
      }

      startNav() {
        this._amNavStarted = true;
        this.reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)");
        // A link anywhere on the page to a section (inside a surface's
        // shadow DOM too): the browser's own jump cannot see into it. The
        // link is found on the click's composed path.
        this._amOnPageClick = (event) => {
          if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey) return;
          if (event.composedPath().some((el) => el?.hasAttribute?.("data-a2ui-nav-item"))) return;
          const link = event.composedPath().find((el) => el instanceof HTMLAnchorElement);
          const index = link ? this.byHash(link.getAttribute("href")) : -1;
          if (index < 0 || !this.section(index)) return;
          event.preventDefault();
          this.go(index);
        };
        // Back and forward between sections, and a same-document jump to a
        // section's hash: the surface may still be drawing it.
        this._amOnHash = () => {
          const index = this.byHash(location.hash);
          if (index >= 0) this.arrive(index);
        };
        this._amOnScroll = () => {
          if (this._amLocked || this._amFrame) return;
          this._amFrame = requestAnimationFrame(() => {
            this._amFrame = null;
            this.select(this.inView());
          });
        };
        document.addEventListener("click", this._amOnPageClick);
        window.addEventListener("hashchange", this._amOnHash);
        document.addEventListener("scroll", this._amOnScroll, {capture: true, passive: true});
        const hash = this.byHash(location.hash);
        // The first entry on arrival: the sections may still be drawing, so
        // the page can look short enough to be "at the bottom" before it is.
        this.select(hash >= 0 ? hash : 0);
        if (hash >= 0) this.arrive(hash);
      }

      stopNav() {
        if (!this._amNavStarted) return;
        this._amNavStarted = false;
        document.removeEventListener("click", this._amOnPageClick);
        window.removeEventListener("hashchange", this._amOnHash);
        document.removeEventListener("scroll", this._amOnScroll, {capture: true});
        cancelAnimationFrame(this._amFrame);
        this._amFrame = null;
        this.stopArrival();
        this.release();
        clearTimeout(this._amUnoutline);
      }

      onNavClick(event, index) {
        if (event.button !== 0 || event.metaKey || event.ctrlKey) return;
        if (!this.section(index)) return;
        event.preventDefault();
        this.go(index);
      }

      // Goes to a section once it is drawn. No deadline: a busy server can
      // take longer than any fixed wait. The person's own scroll, click or
      // key ends the wait, so the page never moves under someone reading.
      arrive(index) {
        this.stopArrival();
        this._amArrivalStop = () => this.stopArrival();
        for (const type of PERSON) {
          window.addEventListener(type, this._amArrivalStop, {capture: true, once: true});
        }
        // An arrival jumps: hold() pins the section from the next frame on,
        // and an instant scroll issued while a smooth one is running lands a
        // few pixels past the line in Chromium.
        const wait = () => {
          if (!this.section(index)) {
            this._amWaiting = setTimeout(wait, 100);
            return;
          }
          this.go(index, {instant: true});
          this.hold(index, Date.now() + OUTLINE_MS);
        };
        wait();
      }

      // The sections above keep drawing after the one arrived at exists,
      // which pushes it down the page: keep it on the line while it settles.
      hold(index, until) {
        const step = () => {
          const target = this.section(index);
          if (!target || Date.now() > until) {
            this.stopArrival();
            return;
          }
          const margin = this.clear(target);
          if (Math.abs(target.getBoundingClientRect().top - margin) > 1) {
            target.scrollIntoView({behavior: "auto", block: "start"});
          }
          this._amArrival = requestAnimationFrame(step);
        };
        this._amArrival = requestAnimationFrame(step);
      }

      stopArrival() {
        clearTimeout(this._amWaiting);
        cancelAnimationFrame(this._amArrival);
        if (!this._amArrivalStop) return;
        for (const type of PERSON) {
          window.removeEventListener(type, this._amArrivalStop, {capture: true});
        }
        this._amArrivalStop = null;
      }

      byHash(hash) {
        if (!hash || !hash.startsWith("#")) return -1;
        const items = this.controller?.props?.nav?.items || [];
        return items.findIndex((item) => `#${item.anchor}` === hash);
      }

      go(index, {instant = false} = {}) {
        const item = this.navItem(index);
        const target = this.section(index);
        if (!item || !target) return;
        this.select(index);
        // Hold the highlight on the chosen entry until the person scrolls,
        // clicks or types: a section near the end can stop short of the line.
        this.holdChoice();
        const items = this.controller?.props?.nav?.items || [];
        items.forEach((_item, i) => this.outline(this.section(i), false));
        this.outline(target, true);
        this.clear(target);
        const smooth = !instant && !this.reducedMotion?.matches;
        target.scrollIntoView({behavior: smooth ? "smooth" : "auto", block: "start"});
        clearTimeout(this._amUnoutline);
        this._amUnoutline = setTimeout(() => this.outline(target, false), OUTLINE_MS);
        const hash = `#${item.anchor}`;
        if (location.hash !== hash) history.replaceState(history.state, "", hash);
      }

      holdChoice() {
        this.release();
        this._amLocked = true;
        this._amUnlock = () => this.release();
        for (const type of PERSON) {
          window.addEventListener(type, this._amUnlock, {capture: true, once: true});
        }
      }

      release() {
        this._amLocked = false;
        if (!this._amUnlock) return;
        for (const type of PERSON) {
          window.removeEventListener(type, this._amUnlock, {capture: true});
        }
        this._amUnlock = null;
      }

      /**
       * The line a section stops on, in pixels from the top of the window:
       * where the nav sticks (its own `top`), so the section's heading is
       * level with the nav. A nav that does not stick (a narrow window)
       * stops sections at `--ash-admin-nav-line` (0 by default).
       */
      navLine() {
        const nav = this.navElement;
        const style = nav ? getComputedStyle(nav) : null;
        if (style && style.position === "sticky") return Math.round(parseFloat(style.top) || 0);
        return Math.round(parseFloat(getComputedStyle(this).getPropertyValue("--ash-admin-nav-line")) || 0);
      }

      // A section stops on the line, not behind a sticky bar: its scroll
      // margin, set on the section itself. Returns the margin.
      clear(section) {
        const margin = this.navLine();
        section.style.scrollMarginTop = `${margin}px`;
        return margin;
      }

      /** A section by its entry: its target id, looked up when needed. */
      section(index) {
        const item = this.navItem(index);
        return item ? this.findSection(item.target) : null;
      }

      /**
       * The element a nav entry scrolls to, by its target (a section's
       * component id): an element carrying that DOM id, else the element
       * drawing that component. A host whose section drawing sets the DOM id
       * may look it up by id alone.
       */
      findSection(target) {
        return findById(this.renderRoot, target);
      }

      outline(section, on) {
        if (!section) return;
        section.toggleAttribute("data-outlined", on);
        Object.assign(section.style, {
          outline: on ? "2px solid var(--ash-admin-nav-outline, var(--am-primary))" : "",
          outlineOffset: on ? "8px" : "",
          borderRadius: on ? "var(--am-radius-l)" : "",
        });
      }

      // The last section whose top has passed a third of the way down the
      // window, or the last one once the person has scrolled to the end.
      inView() {
        const items = this.controller?.props?.nav?.items || [];
        const line = window.innerHeight / 3;
        const page = document.scrollingElement;
        if (page && page.scrollTop > 0 && page.scrollTop + page.clientHeight >= page.scrollHeight - 1) {
          return items.length - 1;
        }
        let index = 0;
        items.forEach((_item, i) => {
          const section = this.section(i);
          if (section && section.getBoundingClientRect().top <= line) index = i;
        });
        return index;
      }

      select(index) {
        this.navEntries.forEach((entry) => {
          const on = Number(entry.getAttribute("data-a2ui-nav-item")) === index;
          entry.toggleAttribute("selected", on);
          if (on) entry.setAttribute("aria-current", "location");
          else entry.removeAttribute("aria-current");
        });
      }
    }

    customElements.define(tag, AshAdminEntityPage);
  }

  // A section under `root` by its component id, through every shadow root
  // below it (the surface's sections render inside their elements' own
  // shadow DOM): an element carrying that DOM id (a host drawing may set
  // it), else the element drawing that component.
  function findById(root, id) {
    if (!root || !id) return null;
    return findByDomId(root, id) || findByComponent(root, id);
  }

  function findByDomId(root, id) {
    const direct = root.getElementById?.(id) || root.querySelector?.(`[id="${id.replace(/"/g, '\\"')}"]`);
    if (direct) return direct;
    for (const el of root.querySelectorAll?.("*") || []) {
      const found = el.shadowRoot && findByDomId(el.shadowRoot, id);
      if (found) return found;
    }
    return null;
  }

  function findByComponent(root, id) {
    for (const el of root.querySelectorAll?.("*") || []) {
      if (el.context?.componentModel?.id === id) return el;
      const found = el.shadowRoot && findByComponent(el.shadowRoot, id);
      if (found) return found;
    }
    return null;
  }

  // --- AlertBanner: a :detail drawn as an alert (3.5) -----------------------

  function defineAlertBanner() {
    const tag = TAGS.alertBanner;
    if (customElements.get(tag)) return;

    class AshAdminAlertBanner extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .alert {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            justify-content: space-between;
            gap: var(--am-space-s);
            padding: var(--am-space-s) var(--am-space-m);
            border-radius: var(--am-radius-m);
            border: 1px solid var(--am-border);
            background: var(--am-hover-tint);
            font-size: var(--am-font-size-m);
          }
          .alert[data-variant="warning"] {
            background: var(--am-warning-subtle);
            border-color: color-mix(in srgb, var(--am-warning) 25%, transparent);
          }
          .alert[data-variant="danger"] {
            background: var(--am-error-subtle);
            border-color: color-mix(in srgb, var(--am-error) 25%, transparent);
          }
          .alert[data-variant="success"] {
            background: var(--am-success-subtle);
            border-color: color-mix(in srgb, var(--am-success) 25%, transparent);
          }
          .alert-title {
            margin: 0;
            font-weight: var(--am-font-weight-semibold);
          }
          .alert-message {
            margin: 0;
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.alertBanner);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;
        const title = str(props.title);
        const message = str(props.message);
        if (title === "" && message === "") return nothing;
        const href = str(props.linkHref);
        const role = props.variant === "danger" || props.variant === "warning" ? "alert" : "status";
        const count = typeof props.count === "number" ? props.count : nothing;
        return html`<div class="alert" role=${role} data-variant=${props.variant || "info"} data-layout=${props.layout || "inline"} data-count=${count}>
          <div>
            ${title ? html`<p class="alert-title">${title}</p>` : nothing}
            ${message ? html`<p class="alert-message">${message}</p>` : nothing}
          </div>
          ${href ? html`<a class="am-link" href=${href}>${str(props.linkLabel) || href}</a>` : nothing}
        </div>`;
      }
    }

    customElements.define(tag, AshAdminAlertBanner);
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
          .cell-primary {
            text-align: right;
            white-space: nowrap;
          }
          /* Row actions wrap inside their cell instead of pushing the
           * table past its frame. */
          .row-actions {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--am-space-2xs);
          }
          /* The per-action wrapper carrying data-a2ui-action takes no box:
           * its button stays a flex item of .row-actions. */
          .row-action {
            display: contents;
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
          /* 1.18: a declared heading frames the grid as one card, the
           * header on top; the frame inside it drops its own edge. */
          .grid-card {
            border: var(--am-border-width) solid var(--am-border);
            border-radius: var(--am-grid-radius);
            background: var(--am-surface);
            box-shadow: var(--am-grid-shadow);
          }
          .grid-heading {
            display: grid;
            gap: var(--am-space-2xs);
            padding: var(--am-space-m) var(--am-space-l);
          }
          .grid-heading-title {
            margin: 0;
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-bold);
            color: var(--am-text);
          }
          .grid-heading-description {
            margin: 0;
            font-size: var(--am-font-size-s);
            color: var(--am-text-muted);
          }
          .grid-card .grid-frame,
          .grid-card .grid-empty {
            border: 0;
            border-top: var(--am-border-width) solid var(--am-border);
            border-radius: 0 0 var(--am-grid-radius) var(--am-grid-radius);
            box-shadow: none;
          }
          .grid-card .grid-cards {
            padding: 0 var(--am-space-l) var(--am-space-l);
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
        this.watchSort(this.controller?.props);
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        // Selection attributes (see AshA2ui.Manifest): the grid carries its
        // component id; its rows `data-a2ui-row-id` and its row action
        // controls `data-a2ui-action` (renderTableRow, renderCard,
        // renderRowActions).
        const componentId = this.context?.componentModel?.id;
        if (componentId) this.setAttribute("data-a2ui-id", componentId);
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
        this.unwatchSort();
        if (this._confirmEl && this._confirmEl.parentNode) {
          this._confirmEl.parentNode.removeChild(this._confirmEl);
        }
      }

      /**
       * The header marks its sort from the data model at `sort.path`, a path
       * in a static prop rather than a bound one, so the controller does not
       * subscribe to it. The data model notifies only the subscribers of a
       * path that changed: when the server's sort reply leaves the bound rows
       * as they were (one row, or rows already in that order), nothing else
       * renders the grid again and the old marks stay. The grid subscribes
       * to the sort path itself.
       */
      watchSort(props) {
        const path = typeof props?.sort?.path === "string" ? props.sort.path : null;
        const dataModel = this.surface?.dataModel;
        if (!path || !dataModel || typeof dataModel.subscribe !== "function") {
          this.unwatchSort();
          return;
        }
        if (this._amSort?.path === path && this._amSort.dataModel === dataModel) return;
        this.unwatchSort();
        this._amSort = {
          path,
          dataModel,
          subscription: dataModel.subscribe(path, () => this.requestUpdate()),
        };
      }

      unwatchSort() {
        try {
          this._amSort?.subscription?.unsubscribe();
        } catch {
          // The data model may already be gone (surface torn down).
        }
        this._amSort = null;
      }

      onActionSettled() {
        this._amBusyRowAction = null;
        const prompt = this._amPrompt;
        if (!prompt || !prompt.busy) return;
        // The outcome batch is processed synchronously; read it once the
        // whole batch has landed.
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
        return bindingPath(this.context?.componentModel?.properties?.rows);
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

        const body =
          rows.length === 0
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
              `;

        return html`
          <div class="grid-root">
            ${this.renderCardHeader(props, body)}
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

      /**
       * 1.18: a declared heading and caption make the grid one card: the
       * header on top, then the rows (table or card list) or the empty
       * state. Without them the body draws as before.
       */
      renderCardHeader(props, body) {
        const heading = str(props.heading);
        const description = str(props.description);
        if (!heading && !description) return body;
        return html`
          <section class="grid-card" part="card">
            <header class="grid-heading" part="heading">
              ${heading ? html`<h3 class="grid-heading-title">${heading}</h3>` : nothing}
              ${description
                ? html`<p class="grid-heading-description">${description}</p>`
                : nothing}
            </header>
            ${body}
          </section>
        `;
      }

      renderTable(columns, rows, rowActions, label) {
        const hasActions = rowActions.length > 0;
        const primary = this.inlinePrimary();
        return html`
          <div class="grid-frame" part="frame">
            <table class="grid-table" aria-label=${label || "Records"}>
              <thead>
                <tr>
                  ${columns.map((column) => this.renderHeader(column))}
                  ${primary
                    ? html`<th scope="col"><span class="sr-only">${str(primary.label)}</span></th>`
                    : nothing}
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

      /**
       * 1.10 column help: an info mark after the header label opening the
       * column's help (title, paragraphs, `**Term** — text` definitions) in
       * a disclosure.
       */
      renderColumnHelp(column) {
        const help = column?.help;
        if (!help || typeof help.body !== "string" || help.body === "") return nothing;
        const title = str(help.title);
        const label = title ? `About ${title}` : `About ${str(column.label)}`;
        return html`<details class="am-col-help" @click=${(event) => event.stopPropagation()}>
          <summary class="am-help-mark" aria-label=${label}>ⓘ</summary>
          <div class="am-col-help-body" role="note">
            ${title ? html`<strong class="am-col-help-title">${title}</strong>` : nothing}
            ${helpParagraphs(help.body).map((paragraph) =>
              paragraph.term
                ? html`<p><strong>${paragraph.term}</strong> — ${paragraph.text}</p>`
                : html`<p>${paragraph.text}</p>`,
            )}
          </div>
        </details>`;
      }

      /** The column's current sort direction ("asc" | "desc") or null. */
      sortDirection(column) {
        const path = this.controller?.props?.sort?.path;
        const current = path ? this.surface?.dataModel?.get(path) : null;
        return current && current.field === sortField(column) ? current.dir : null;
      }

      /**
       * A header cell: plain text, or (1.7) for a sortable column a button
       * with the label and a sort mark, the th carrying aria-sort.
       */
      renderHeader(column) {
        const label = str(column.label);
        const help = this.renderColumnHelp(column);
        // 1.10: a fixed column width.
        const width = Number.isInteger(column.width) ? `width: ${column.width}px` : nothing;
        if (!column.sortable || !this.controller?.props?.sort) {
          return html`<th scope="col" class=${alignClass(column)} style=${width}>${label}${help}</th>`;
        }
        const dir = this.sortDirection(column);
        const ariaSort = dir === "asc" ? "ascending" : dir === "desc" ? "descending" : "none";
        const mark = dir === "asc" ? "\u2191" : dir === "desc" ? "\u2193" : "\u2195";
        return html`<th scope="col" class=${alignClass(column)} aria-sort=${ariaSort} style=${width}>
          <button
            type="button"
            class="sort-button"
            data-sort=${ariaSort}
            @click=${() => this.sortBy(column)}
          >
            <span>${label}</span><span class="sort-mark" aria-hidden="true">${mark}</span>
          </button>${help}
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
        // 1.11: a column's first direction (sortFirst), and with the
        // sort's reset a third click back to the default order (null).
        const first = column.sortFirst === "desc" ? "desc" : "asc";
        const current = this.sortDirection(column);
        const other = first === "asc" ? "desc" : "asc";
        const dir = !current ? first : current === first ? other : sort.reset === true ? null : first;
        const spec = adminActionSpec(sort.action);
        if (!spec) return;
        dispatchActionSpec(this.context, spec, {
          update: (context) => ({
            ...context,
            query: {...(context.query || {}), sort: dir ? {field: sortField(column), dir} : null},
          }),
        });
      }

      renderTableRow(row, index, columns, rowActions, hasActions) {
        const rowId = this.rowIdentity(row, index);
        const clickable = this.rowClickable();
        return html`
          <tr
            id="row-${rowId}"
            data-a2ui-row-id=${rowId}
            data-a2ui-region=${regionAddresses(rowReviews(row, columns)) || nothing}
            class=${clickable ? "is-clickable" : ""}
            tabindex=${clickable ? "0" : nothing}
            @click=${clickable ? (event) => this.onRowClick(event, index) : nothing}
            @keydown=${clickable ? (event) => this.onRowKey(event, index) : nothing}
          >
            ${columns.map((column, columnIndex) => {
              const cell = this.renderCell(row, column);
              return columnIndex === 0
                ? html`<th scope="row" class=${alignClass(column)} data-a2ui-column=${column.path || nothing}>${cell}</th>`
                : html`<td class=${alignClass(column)} data-a2ui-column=${column.path || nothing}>${cell}</td>`;
            })}
            ${this.inlinePrimary()
              ? html`<td class="cell-primary">${this.renderPrimaryAction(row, index)}</td>`
              : nothing}
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
            data-a2ui-row-id=${this.rowIdentity(row, index)}
            data-a2ui-region=${regionAddresses(rowReviews(row, columns)) || nothing}
            @click=${clickable ? (event) => this.onRowClick(event, index) : nothing}
          >
            <dl class="card-fields">
              ${columns.map(
                (column) => html`
                  <div class="card-field">
                    <dt>${str(column.label)}</dt>
                    <dd data-a2ui-column=${column.path || nothing}>${this.renderCell(row, column)}</dd>
                  </div>
                `,
              )}
            </dl>
            ${hasActions || this.inlinePrimary()
              ? html`<div class="card-actions">
                  ${this.inlinePrimary() ? this.renderPrimaryAction(row, index) : nothing}
                  ${hasActions ? this.renderRowActions(row, index, rowActions) : nothing}
                </div>`
              : nothing}
          </li>
        `;
      }

      /**
       * 3.9: whether a column's field action is offered on `row`: the
       * column has one, and the row offers it (its `actionVisible` path is
       * true; an unbound one always offers it). Hiding is a rendering
       * concern only: the server re-checks every call.
       */
      cellActionOffered(row, column) {
        const entry = column?.action;
        if (!entry || typeof entry !== "object" || typeof entry.action !== "string") return false;
        const path = column.actionVisible?.path;
        return typeof path !== "string" || getByPath(row, path) === true;
      }

      /**
       * 3.9: a column's field action, a quiet button on the value's line
       * after its review, sent like a row action (the entry's bindings
       * resolved against the row) and busy until the outcome. A click never
       * reaches the row's own click.
       */
      renderCellAction(row, column) {
        if (!this.cellActionOffered(row, column)) return nothing;
        const entry = column.action;
        const rows = this.controller?.props?.rows || [];
        const index = rows.indexOf(row);
        const rowIdentity = this.rowIdentity(row, index);
        const label = str(entry.label);
        const busy =
          this._amBusyRowAction !== null &&
          this._amBusyRowAction.row === rowIdentity &&
          this._amBusyRowAction.label === label;
        return html`<span class="am-cell-action" data-a2ui-action="field_action">${renderActionButton({
          label,
          icon: typeof entry.icon === "string" && entry.icon !== "" ? entry.icon : undefined,
          tone: "quiet",
          size: "sm",
          busy,
          onClick: (event) => {
            event?.stopPropagation?.();
            this.onCellAction(entry, index);
          },
        })}</span>`;
      }

      /** 3.9: sends a row's field action, the row's bindings resolved now. */
      onCellAction(entry, index) {
        const spec = adminActionSpec(entry);
        if (!spec || index < 0 || this._amBusyRowAction) return;
        this.markRowActionBusy(entry, index);
        this.dispatchRowAction(spec, this.rowBasePath(index));
      }

      /**
       * 3.10: a pairs column bound to its row's items: one labeled line per
       * item, its value followed by its own review and, while the item
       * offers it, the column's pairAction as a quiet button.
       */
      renderPairs(row, column) {
        const items = pairItems(row, column);
        if (items.length === 0) return "—";
        return html`<dl class="am-pairs">
          ${items.map((item) => {
            const review = reviewEntry(item.review);
            return html`<div class="am-pair" data-a2ui-region=${regionAddresses(review) || nothing}>
              <dt>${str(item.term)}</dt>
              <dd>
                <span class="am-cell-value" data-review=${review ? review.state : nothing}>${str(item.value)}</span>
                ${renderCellReview(review)} ${this.renderPairAction(row, column, item)}
              </dd>
            </div>`;
          })}
        </dl>`;
      }

      /**
       * 3.10: a pairs column's action for one item, busy until the outcome,
       * sent like a row action with the item's key in its context. A click
       * never reaches the row's own click.
       */
      renderPairAction(row, column, item) {
        if (!pairActionOffered(column, item)) return nothing;
        const entry = column.pairAction;
        const rows = this.controller?.props?.rows || [];
        const index = rows.indexOf(row);
        const label = str(entry.label);
        const identity = `${this.rowIdentity(row, index)}#${item.key}`;
        const busy =
          this._amBusyRowAction !== null &&
          this._amBusyRowAction?.row === identity &&
          this._amBusyRowAction?.label === label;
        return html`<span class="am-cell-action" data-a2ui-action="field_action" data-a2ui-item=${item.key}
          >${renderActionButton({
            label,
            icon: typeof entry.icon === "string" && entry.icon !== "" ? entry.icon : undefined,
            tone: "quiet",
            size: "sm",
            busy,
            onClick: (event) => {
              event?.stopPropagation?.();
              this.onPairAction(column, item, index);
            },
          })}</span
        >`;
      }

      /** 3.10: sends a pairs column's action for one item. */
      onPairAction(column, item, index) {
        if (!pairActionOffered(column, item) || index < 0 || this._amBusyRowAction) return;
        const entry = pairActionEntry(column, item);
        const spec = adminActionSpec(entry);
        if (!spec) return;
        const rows = this.controller?.props?.rows || [];
        this.markRowActionBusyByIdentity(entry, `${this.rowIdentity(rows[index], index)}#${item.key}`);
        this.dispatchRowAction(spec, this.rowBasePath(index));
      }

      /**
       * One cell: its value (below), framed by the column's 1.8 hints when
       * it declares any — a leading icon and a "+N more" tag on the value's
       * line, a second line and a detail line under it.
       */
      renderCell(row, column) {
        const value = this.renderCellValue(row, column);
        if (
          !column.subtitle &&
          !column.icon &&
          !column.more &&
          !column.detail &&
          !column.caption &&
          !column.review &&
          !column.action
        )
          return value;

        const at = (binding) =>
          binding && typeof binding.path === "string" ? getByPath(row, binding.path) : undefined;
        // 3.3: the row's review of the column's field, and of its subtitle's.
        const review = reviewEntry(at(column.review));
        const subtitleReview =
          typeof column.subtitle?.reviewPath === "string"
            ? reviewEntry(getByPath(row, column.subtitle.reviewPath))
            : null;
        const icon = cellIcon(at(column.icon));
        const label = column.icon ? str(getByPath(row, column.icon.labelPath)) : "";
        const tone = column.icon?.tonePath ? badgeTone(getByPath(row, column.icon.tonePath)) : "neutral";
        const more = moreCount(at(column.more));
        // 1.10: all the values behind the tag, listed in its title.
        const moreValues =
          typeof column.more?.valuesPath === "string" ? getByPath(row, column.more.valuesPath) : null;
        // The tag's text and the list's caption arrive translated and
        // pluralized per row (textPath, captionPath); the English forms are
        // for a payload from before them.
        const rowText = (path) => (typeof path === "string" ? str(getByPath(row, path)) : "");
        const moreText = rowText(column.more?.textPath) || `+${more} more`;
        const moreCaption =
          rowText(column.more?.captionPath) ||
          (Array.isArray(moreValues) ? `${moreValues.length} ${str(column.moreNoun) || "values"}` : "");
        const moreTitle = Array.isArray(moreValues) ? `${moreCaption}: ${moreValues.join(", ")}` : "";
        const moreLabel = rowText(column.more?.labelPath);
        const subtitle = at(column.subtitle);
        const detail = column.detail
          ? detailText(at(column.detail), column.detail.datePath ? getByPath(row, column.detail.datePath) : null)
          : "";
        const detailIcon =
          detail && typeof column.detail.iconPath === "string"
            ? cellIcon(getByPath(row, column.detail.iconPath))
            : null;
        const detailTone =
          typeof column.detail?.iconTonePath === "string"
            ? badgeTone(getByPath(row, column.detail.iconTonePath))
            : "neutral";
        // 1.11: the third line, its words filled with the caption value.
        const captionValue = at(column.caption);
        const caption =
          captionValue === null || captionValue === undefined || captionValue === ""
            ? ""
            : typeof column.caption.text === "string" && column.caption.text !== ""
              ? detailText(column.caption.text.replaceAll("{value}", str(captionValue)), captionValue)
              : str(captionValue);
        // 1.10: a detail line's explanation, an info mark with a tooltip.
        const detailHelp =
          detail && typeof column.detail.helpPath === "string"
            ? str(getByPath(row, column.detail.helpPath))
            : "";

        return html`<span class="am-cell">
          <span class="am-cell-line">
            ${icon
              ? html`<svg
                  class="am-cell-icon"
                  data-tone=${tone}
                  viewBox="0 0 20 20"
                  width="16"
                  height="16"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.75"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  role=${label ? "img" : nothing}
                  aria-label=${label || nothing}
                  aria-hidden=${label ? nothing : "true"}
                >
                  <path d=${icon.join(" ")}></path>
                </svg>`
              : nothing}
            <span class="am-cell-value" data-review=${review ? review.state : nothing}>${value}</span>
            ${renderCellReview(review)} ${this.renderCellAction(row, column)}
            ${more > 0
              ? html`<span
                  class="am-badge"
                  data-tone="neutral"
                  title=${moreTitle || nothing}
                  aria-label=${moreLabel || nothing}
                  >${moreText}</span
                >`
              : nothing}
          </span>
          ${subtitle === null || subtitle === undefined || subtitle === ""
            ? nothing
            : subtitleReview
              ? html`<span class="am-cell-sub"
                  ><span class="am-cell-value" data-review=${subtitleReview.state}>${str(subtitle)}</span
                  >${renderCellReview(subtitleReview)}</span
                >`
              : html`<span class="am-cell-sub">${str(subtitle)}</span>`}
          ${caption ? html`<span class="am-cell-caption">${caption}</span>` : nothing}
          ${detail
            ? html`<span class="am-cell-detail">${detailIcon
                ? html`<svg
                    class="am-cell-icon"
                    data-tone=${detailTone}
                    viewBox="0 0 20 20"
                    width="14"
                    height="14"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.75"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path d=${detailIcon.join(" ")}></path>
                  </svg>`
                : nothing}<span>${detail}</span>${detailHelp
                ? html`<span
                    class="am-help-mark"
                    role="img"
                    tabindex="0"
                    title=${detailHelp}
                    aria-label=${detailHelp}
                    >ⓘ</span
                  >`
                : nothing}</span>`
            : nothing}
        </span>`;
      }

      /**
       * A cell's value: the column's link(s) when the row carries them (pruned
       * per actor server-side — absent means plain value), a toned status
       * pill for badge columns, identifiers in mono, lists as lists, and
       * everything else through the format rules.
       */
      renderCellValue(row, column) {
        // 3.10: a pairs column bound to its row's items.
        if (column.pairs === true && typeof column.items?.path === "string") return this.renderPairs(row, column);
        // 3.12: a masked cell draws the value (the masked word) as plain
        // text: format, link, badge and emptyText are ignored, the element
        // is marked data-a2ui-masked, and the reason is its title and
        // accessible description.
        if (column.masked && typeof column.masked.path === "string") {
          const maskedReason = str(getByPath(row, column.masked.path));
          if (maskedReason) {
            return html`<span
              data-a2ui-masked
              title=${maskedReason}
              aria-description=${maskedReason}>${str(getByPath(row, column.path))}</span
            >`;
          }
        }
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
          // 1.11: the pill's one-line explanation, as its tooltip.
          const help = typeof column.badge.helpPath === "string" ? str(getByPath(row, column.badge.helpPath)) : "";
          return help
            ? html`<span class="am-badge" data-tone=${tone} title=${help} aria-description=${help}
                >${str(text)}</span
              >`
            : html`<span class="am-badge" data-tone=${tone}>${str(text)}</span>`;
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

      /** The row click when it is also drawn as a button per row (1.9
       * `inline`), else null. */
      inlinePrimary() {
        const rowClick = this.controller?.props?.rowClick;
        return rowClick && rowClick.inline === true && typeof rowClick.action === "string"
          ? rowClick
          : null;
      }

      /** The row's primary action button: the row click's envelope, its
       * label and variant from the row (labelPath / variantPath), the row
       * click's own label and the default variant when absent. A click
       * here never reaches the row's own click handler (it is a button). */
      renderPrimaryAction(row, index) {
        const rowClick = this.inlinePrimary();
        const rowLabel =
          typeof rowClick.labelPath === "string" ? getByPath(row, rowClick.labelPath) : null;
        const label = str(
          rowLabel === null || rowLabel === undefined || rowLabel === "" ? rowClick.label : rowLabel,
        );
        const variant =
          typeof rowClick.variantPath === "string"
            ? primaryVariantTone(getByPath(row, rowClick.variantPath))
            : primaryVariantTone(null);
        const action = {...rowClick, label};
        const busy =
          this._amBusyRowAction !== null &&
          this._amBusyRowAction.row === this.rowIdentity(row, index) &&
          this._amBusyRowAction.label === label;
        return renderActionButton({
          label,
          tone: variant,
          size: "sm",
          busy,
          primaryAction: true,
          onClick: (event) => {
            event.stopPropagation();
            this.onRowAction(action, index);
          },
        });
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
          // The wrapper (display: contents) names the action — a declared
          // row action's name, else the entry's own ("view_record", ...) —
          // whatever draws the button (renderActionButton's host seam).
          return html`<span class="row-action" data-a2ui-action=${rowActionKey(action)}>${renderActionButton({
            label,
            tone: "quiet",
            size: "sm",
            destructive,
            busy,
            onClick: () => this.onRowAction(action, index),
          })}</span>`;
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
          restoreFocus: focusedIn(this) || document.activeElement,
          focused: false,
        };
        const open = adminActionSpec(action.prompt.open);
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
        const envelope = adminActionSpec(prompt.entry);
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
          const active = focusedIn(this);
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
        const buttons = [...this.renderRoot.querySelectorAll(".prompt-dialog :is(button, [data-am-button])")].filter(
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
                ${renderActionButton({label: "Cancel", onClick: () => this.closePrompt()})}
                ${renderActionButton({
                  label: str(spec.confirmLabel) || "Confirm",
                  tone: "primary",
                  busy: prompt.busy,
                  onClick: () => this.confirmPrompt(),
                })}
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
        const envelope = adminActionSpec(action);
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
            title: str(action.confirmTitle),
            body: str(action.confirmBody),
            rowIdentity: this.rowIdentity((this.controller?.props?.rows || [])[index], index),
          };
          this.requestUpdate();
          return;
        }

        this.markRowActionBusy(action, index);
        this.dispatchRowAction(envelope, this.rowBasePath(index));
      }

      /** Zero jank: the clicked button acknowledges at 0 RTT; the data
       * model's next outcome write (subscribeActionOutcomes) re-enables it. */
      markRowActionBusy(action, index) {
        const rows = this.controller?.props?.rows || [];
        this.markRowActionBusyByIdentity(action, this.rowIdentity(rows[index], index));
      }

      markRowActionBusyByIdentity(action, rowIdentity) {
        this._amBusyRowAction = {row: rowIdentity, label: str(action?.label)};
        markActionBusy(this);
        this.requestUpdate();
      }

      dispatchRowAction(spec, basePath) {
        if (!this.surface || !this.context?.componentModel) return;
        dispatchActionSpec(this.context, spec, {basePath});
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
        // 3.13: the server sends the dialog's text, translated, and says
        // "cannot be undone" only for a destroy.
        dialog.title = pending.title || pending.label;
        dialog.body = pending.body;
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
        buttons,
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
          .empty-title {
            margin: 0;
            font-size: var(--am-font-size-l, 1.125rem);
            font-weight: var(--am-font-weight-semibold);
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
                <path d=${EMPTY_ICONS[str(props.icon)] || "M4 7h16M4 12h16M4 17h10"}></path>
              </svg>
            </span>
            ${props.title ? html`<h3 class="empty-title">${str(props.title)}</h3>` : nothing}
            <p class="empty-message">${str(props.message)}</p>
            ${action.length > 0 ? html`<div class="empty-action">${action}</div>` : nothing}
            ${this.renderClear(props)}
          </div>
        `;
      }

      /** 1.10: the clear action, while clearVisible. */
      renderClear(props) {
        const clear = props.clearAction;
        if (!clear || props.clearVisible !== true || !clear.action?.name) return nothing;
        return html`<div class="empty-action">
          ${renderActionButton({label: str(clear.label), tone: "primary", onClick: () => this.clear()})}
        </div>`;
      }

      /**
       * Clears search, filters and ranges in the query state the clear
       * action names, then sends it (page 1).
       */
      clear() {
        const clear = this.controller?.props?.clearAction;
        const context = this.context;
        const surface = context?.dataContext?.surface;
        if (!clear?.action || !surface || !context.componentModel) return;
        const spec = adminActionSpec(clear.action);
        if (!spec) return;
        const queryPath = bindingPath(spec.context.query);
        if (queryPath !== null) {
          const state = surface.dataModel.get(queryPath) || {};
          surface.dataModel.set(`${queryPath}/search`, "");
          for (const [name, value] of Object.entries(state.filters || {})) {
            surface.dataModel.set(`${queryPath}/filters/${name}`, Array.isArray(value) ? [] : "");
          }
          for (const name of Object.keys(state.ranges || {})) {
            surface.dataModel.set(`${queryPath}/ranges/${name}`, {from: "", to: ""});
          }
        }
        dispatchActionSpec(context, spec);
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
          /* 1.10: the rows-per-page select. */
          .pager-size {
            display: inline-flex;
            align-items: center;
            gap: var(--am-space-xs);
            font-size: var(--am-font-size-s);
            color: var(--am-text-muted);
          }
          .pager-size select {
            font: inherit;
            color: var(--am-text);
            background: var(--am-surface);
            border: var(--am-border-width) solid var(--am-border);
            border-radius: var(--am-radius-s);
            padding: var(--am-space-2xs) var(--am-space-xs);
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
        if (props.visible !== true) {
          // 1.10: with page sizes to pick, the size select stays while there
          // are more records than the smallest size shows.
          if (!this.pageSizeOffered(props)) return nothing;
          return html`<nav class="pager" aria-label=${str(props.label) || "Results"}>
            ${props.rangeText
              ? html`<span class="pager-range">${str(props.rangeText)}</span>`
              : nothing}
            ${this.renderPageSize(props)}
          </nav>`;
        }

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
              ? this.renderTurn(-1, true)
              : nothing}
            <span class="pager-status">
              ${Number.isFinite(page)
                ? html`<span class="pager-current" aria-current="page">Page ${page}</span>`
                : nothing}
              ${props.rangeText
                ? html`<span class="pager-range">${str(props.rangeText)}</span>`
                : nothing}
            </span>
            ${this.renderPageSize(props)}
            ${showNext
              ? this.renderTurn(1, true)
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

      /** The Previous (direction -1) or Next (1) button. */
      renderTurn(direction, enabled) {
        const previous = direction < 0;
        return renderActionButton({
          label: previous
            ? html`<span class="pager-chevron" aria-hidden="true">‹</span> Previous`
            : html`Next <span class="pager-chevron" aria-hidden="true">›</span>`,
          tone: "quiet",
          size: "sm",
          disabled: !enabled,
          onClick: () => this.turnPage(direction),
        });
      }

      renderWindowed(props, page, totalPages, label, showPrevious, showNext) {
        return html`
          <nav class="pager" aria-label=${label}>
            ${this.renderTurn(-1, showPrevious && page > 1)}
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
            ${this.renderTurn(1, showNext && page < totalPages)}
            ${props.rangeText
              ? html`<span class="pager-range">${str(props.rangeText)}</span>`
              : nothing}
            ${this.renderPageSize(props)}
          </nav>
        `;
      }

      /** The page sizes offered (1.10 `pageSizeOptions`), or []. */
      pageSizeOptions(props) {
        return Array.isArray(props.pageSizeOptions)
          ? props.pageSizeOptions.map(Number).filter((size) => Number.isInteger(size) && size > 0)
          : [];
      }

      /** Whether a size select is worth showing: more records than the
       * smallest size holds (or an unknown total past the first page). */
      pageSizeOffered(props) {
        const sizes = this.pageSizeOptions(props);
        if (sizes.length === 0 || !props.pageSizeAction) return false;
        const total = Number(props.total);
        if (props.total === null || props.total === undefined || !Number.isFinite(total)) {
          return props.hasNext === true;
        }
        return total > Math.min(...sizes);
      }

      renderPageSize(props) {
        const sizes = this.pageSizeOptions(props);
        if (sizes.length === 0 || !props.pageSizeAction) return nothing;
        const current = Number(props.pageSize);
        const id = `${this.context?.componentModel?.id || "pagination"}-size`;
        return html`<label class="pager-size" for=${id}>
          <span>Rows per page</span>
          <select
            id=${id}
            class="am-select"
            @change=${(event) => this.setPageSize(Number(event.target.value))}
          >
            ${sizes.map(
              (size) => html`<option value=${size} ?selected=${size === current}>${size}</option>`,
            )}
          </select>
        </label>`;
      }

      /** Sends the pageSizeAction envelope (page 1) with the picked size. */
      setPageSize(size) {
        const props = this.controller?.props;
        const envelope = props?.pageSizeAction;
        const context = this.context;
        const surface = context?.dataContext?.surface;
        if (!envelope || !surface || !context.componentModel || !Number.isInteger(size)) return;
        const spec = adminActionSpec(envelope);
        if (!spec) return;
        dispatchActionSpec(context, spec, {
          update: (resolved) => ({
            ...resolved,
            query: {...(resolved.query || {}), pageSize: size, page: 1},
          }),
        });
      }

      /**
       * Sends the `query` envelope with the given pageDelta (any integer:
       * prev/next are ∓1, a page chip jumps by the distance).
       *
       * The `previousAction`/`nextAction` the admin encoder emits
       * (`{"name": "query", "context": {...}}`) is sent as an ashAction,
       * its bindings resolved at click time. When neither is present the
       * envelope is reconstructed like the basic `query_button/2` emission:
       * the query path is derived from the `page` binding, `component` is
       * added for multi-table surfaces, and the `contexts` binding rides
       * along when the surface carries context state.
       */
      turnPage(delta) {
        const props = this.controller?.props;
        const context = this.context;
        const surface = context?.dataContext?.surface;
        if (!props || !surface || !context.componentModel) return;

        const withDelta = (resolved) => ({...resolved, pageDelta: delta});
        const spec = adminActionSpec(delta < 0 ? props.previousAction : props.nextAction);
        if (spec) {
          dispatchActionSpec(context, spec, {update: withDelta});
          return;
        }

        const raw = context.componentModel.properties || {};
        const pagePath = bindingPath(raw.page) ?? bindingPath(raw.pageSize);

        let queryPath = "/query";
        if (pagePath && pagePath.endsWith("/page")) {
          queryPath = pagePath.slice(0, -"/page".length) || "/query";
        }

        const actionContext = {query: {"@path": queryPath}};
        if (queryPath !== "/query") {
          const segments = queryPath.split("/");
          actionContext.component = segments[segments.length - 1];
        }
        const contexts = surface.dataModel.get("/context");
        if (contexts !== null && contexts !== undefined && typeof contexts === "object") {
          actionContext.contexts = {"@path": "/context"};
        }

        dispatchActionSpec(context, adminActionSpec({name: "query", context: actionContext}), {
          update: withDelta,
        });
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
          .field-note {
            font-weight: var(--am-font-weight-regular);
            text-transform: none;
            letter-spacing: normal;
          }
          .field-value-empty {
            color: var(--am-text-muted);
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
          /* 1.17: a steps field, an ordered list drawn as a stepper. Each
             step's number, label and state are text; the marker colour only
             repeats the state. */
          .field-steps {
            list-style: none;
            margin: 0;
            padding: 0;
            display: grid;
            gap: var(--am-space-xs);
          }
          .field-step {
            display: grid;
            grid-template-columns: auto 1fr;
            gap: 0 var(--am-space-xs);
            align-items: baseline;
          }
          .field-step-number {
            display: inline-grid;
            place-items: center;
            min-width: 1.5rem;
            height: 1.5rem;
            border-radius: 50%;
            font-size: var(--am-font-size-xs);
            font-weight: var(--am-font-weight-semibold);
            border: var(--am-border-width) solid var(--am-border-strong);
            color: var(--am-text-muted);
          }
          .field-step[data-state="complete"] .field-step-number {
            border-color: var(--am-success);
            color: var(--am-success);
          }
          .field-step[data-state="current"] .field-step-number {
            border-color: var(--am-primary);
            color: var(--am-primary);
          }
          .field-step[data-state="overdue"] .field-step-number {
            border-color: var(--am-error);
            color: var(--am-error);
          }
          .field-step-body {
            display: grid;
            gap: 0.125rem;
            min-width: 0;
          }
          .field-step-head {
            display: flex;
            flex-wrap: wrap;
            align-items: baseline;
            gap: var(--am-space-2xs);
          }
          .field-step-label {
            font-weight: var(--am-font-weight-medium);
          }
          .field-step[data-state="current"] .field-step-label {
            font-weight: var(--am-font-weight-semibold);
          }
          .field-step-text {
            font-size: var(--am-font-size-s);
          }
          .field-step-note {
            font-size: var(--am-font-size-xs);
            color: var(--am-text-muted);
          }
          /* 3.1: a review field. A pending value is highlighted; the state
             is written out (not only coloured) beside its page tag. */
          .field[data-review="pending"] .field-value {
            background: var(--ash-admin-field-pending-bg, var(--am-warning-subtle));
            border-radius: var(--am-radius-s);
            padding-inline: var(--am-space-2xs);
          }
          .field-review {
            grid-column: 2;
            margin: 0;
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--am-space-2xs);
            font-size: var(--am-font-size-xs);
          }
          .field-review-page {
            color: var(--am-text-muted);
          }

          /* 3.11: an editable value is a control that opens its input; a
             changed value is marked, its change written as text. */
          .field-edit {
            all: unset;
            box-sizing: border-box;
            display: inline-block;
            min-width: 4rem;
            min-height: 1.5em;
            padding-inline: var(--am-space-2xs);
            border-radius: var(--am-radius-s);
            border: var(--am-border-width) dashed var(--am-border);
            cursor: text;
            overflow-wrap: anywhere;
          }
          .field-edit:hover,
          .field-edit:focus-visible {
            border-color: var(--am-primary);
          }
          .field[data-changed] .field-edit {
            border-style: solid;
            border-color: var(--am-primary);
            font-weight: var(--am-font-weight-medium);
          }
          .field-edit-input {
            font: inherit;
            width: 100%;
            max-width: 24rem;
            box-sizing: border-box;
            padding: var(--am-space-2xs) var(--am-space-xs);
            border: var(--am-border-width) solid var(--am-border-strong);
            border-radius: var(--am-radius-s);
          }
          .field-edit-input[aria-invalid="true"] {
            border-color: var(--am-error);
          }
          .field-edit-error {
            grid-column: 2;
            margin: 0;
            font-size: var(--am-font-size-xs);
            color: var(--am-error);
          }
          /* 3.2: a field action's button, under the value. */
          .field-action {
            grid-column: 2;
            margin: 0;
          }
          @container (max-width: 29.99rem) {
            .field-review,
            .field-action {
              grid-column: 1;
            }
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

      /**
       * 3.2: whether the field's action is offered: there is one, and the
       * record offers it (`actionVisible` true; an unbound one always
       * offers it). Hiding is a rendering concern only: the server
       * re-checks every call.
       */
      fieldActionOffered(props) {
        const entry = props?.action;
        if (!entry || typeof entry !== "object" || typeof entry.action !== "string") return false;
        const bound = this.context?.componentModel?.properties?.actionVisible !== undefined;
        return !bound || props.actionVisible === true;
      }

      /** 3.2: sends the field's action (its rowActions-shaped entry, the
       * bindings resolved now) and holds the button busy until the outcome. */
      onFieldAction(entry) {
        const spec = adminActionSpec(entry);
        if (!spec || this._amFieldActionBusy || !this.context?.componentModel) return;
        this._amFieldActionBusy = true;
        markActionBusy(this);
        this.requestUpdate();
        dispatchActionSpec(this.context, spec);
      }

      onActionSettled() {
        this._amFieldActionBusy = false;
      }

      // --- 3.11: editing in place ------------------------------------------
      //
      // A swap draws its own input and calls these: `editOffered` decides
      // whether to draw one, `editing` whether it is open, `openEdit` opens
      // it (on a click or focus), `commitEdit(value)` keeps what it holds
      // (Enter, or leaving it), `cancelEdit` drops it (Escape). The draft
      // lives in the surface's data model (`writeDraft`), so the saveBar
      // sees it and a refresh keeps it.

      /** 3.11: whether the field is edited in place on this record. */
      editOffered(props) {
        if (!editEntry(props?.edit)) return false;
        const bound = this.context?.componentModel?.properties?.editVisible !== undefined;
        return !bound || props.editVisible === true;
      }

      /** 3.11: whether the field's input is open. */
      editing() {
        return Boolean(this._amEditing);
      }

      /** 3.11: the value the input starts from: the draft, else the stored value. */
      editStart(props) {
        return hasDraft(props?.editDraft) ? props.editDraft : props?.editValue;
      }

      /** 3.11: opens the input, focused once drawn. */
      openEdit() {
        if (this._amEditing) return;
        this._amEditing = true;
        this.requestUpdate();
        this.updateComplete.then(() => {
          const input = this.renderRoot?.querySelector?.("[data-a2ui-edit-input]");
          if (input && typeof input.focus === "function") input.focus();
        });
      }

      /** 3.11: keeps `value` as the field's change (none when it is the stored value). */
      commitEdit(value) {
        if (!this._amEditing) return;
        this._amEditing = false;
        const props = this.controller?.props;
        const edit = editEntry(props?.edit);
        const dataModel = this.context?.dataContext?.surface?.dataModel;
        if (edit && dataModel) {
          writeDraft(dataModel, edit, {
            recordId: resolveEventContext(edit.recordId, dataModel),
            value,
            stored: props.editValue,
          });
        }
        this.requestUpdate();
      }

      /** 3.11: closes the input and drops what it held. */
      cancelEdit() {
        if (!this._amEditing) return;
        this._amEditing = false;
        this.requestUpdate();
      }

      /** 3.11: Enter keeps the input's value, Escape drops it. */
      onEditKeydown(event) {
        if (event.key === "Enter") {
          event.preventDefault();
          this.commitEdit(event.target.value);
        } else if (event.key === "Escape") {
          event.preventDefault();
          event.stopPropagation();
          this.cancelEdit();
        }
      }

      /** 3.11: the stock input for the field's `edit`. */
      renderEditInput(props) {
        const edit = editEntry(props.edit);
        const value = editText(this.editStart(props));
        const label = str(props.label);
        const invalid = str(props.editError) !== "";
        const keydown = (event) => this.onEditKeydown(event);
        const blur = (event) => this.commitEdit(event.target.value);

        if (edit.input === "choice") {
          const options = Array.isArray(edit.options) ? edit.options : [];
          return html`<select class="field-edit-input" data-a2ui-edit-input aria-label=${label}
            aria-invalid=${invalid ? "true" : "false"} @keydown=${keydown} @blur=${blur}>
            <option value="" ?selected=${value === ""}></option>
            ${options.map((option) => html`<option value=${str(option.value)} ?selected=${str(option.value) === value}>${str(option.label)}</option>`)}
          </select>`;
        }

        const type = edit.input === "date" ? "date" : edit.input === "text" ? "text" : "number";
        return html`<input class="field-edit-input" data-a2ui-edit-input type=${type}
          step=${edit.input === "integer" ? "1" : edit.input === "number" ? "any" : nothing}
          .value=${value} aria-label=${label} aria-invalid=${invalid ? "true" : "false"}
          @keydown=${keydown} @blur=${blur} />`;
      }

      /** 3.11: an editable field: its input while open, else its value (the draft, marked as changed) as a control that opens it. */
      renderEditable(props) {
        const review = reviewEntry(props.review);
        const region = regionAddresses(review) || nothing;
        const draft = hasDraft(props.editDraft);
        const error = str(props.editError);
        const empty = props.value == null || props.value === "";
        const shown = draft
          ? editText(props.editDraft)
          : empty
            ? str(props.emptyText) || (review?.stateLabel ?? "")
            : renderValue(props.value, props.format);

        return html`
          <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region} ?data-changed=${draft}>
            <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
            <dd class="field-value">${this._amEditing
              ? this.renderEditInput(props)
              : html`<button type="button" class="field-edit" data-a2ui-edit=${editEntry(props.edit).field}
                  aria-label=${str(props.label)} @click=${() => this.openEdit()} @focus=${() => this.openEdit()}>${shown}</button>`}</dd>
            ${error ? html`<dd class="field-edit-error" role="alert">${error}</dd>` : nothing}
            ${renderReview(review)}${this.renderFieldAction(props)}
          </dl>
        `;
      }

      /** 3.2: the field action's button, while the record offers it. */
      renderFieldAction(props) {
        if (!this.fieldActionOffered(props)) return nothing;
        const entry = props.action;
        return html`<dd class="field-action" data-a2ui-action="field_action">${renderActionButton({
          label: str(entry.label),
          icon: typeof entry.icon === "string" && entry.icon !== "" ? entry.icon : undefined,
          tone: "quiet",
          size: "sm",
          busy: Boolean(this._amFieldActionBusy),
          onClick: () => this.onFieldAction(entry),
        })}</dd>`;
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        // 3.15: a recalculated field draws the server's result for the
        // unsaved changes while there is one.
        const props = previewedProps(this.controller?.props);
        if (!props) return nothing;

        // 3.12: a masked field draws its value (the masked word) as plain
        // text: format, link, badge, edit, emptyText and hideWhenEmpty are
        // ignored (a value the reader may not see is not edited in place),
        // the element is marked data-a2ui-masked, and the reason is its
        // title and accessible description.
        const maskedReason = str(props.masked || "");
        if (maskedReason) {
          this.hidden = false;
          const review = reviewEntry(props.review);
          const region = regionAddresses(review) || nothing;
          return html`
            <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region}>
              <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
              <dd
                class="field-value"
                data-a2ui-masked
                title=${maskedReason}
                aria-description=${maskedReason}
              >
                ${str(props.value)}
              </dd>
            ${renderReview(review)}${this.renderFieldAction(props)}
            </dl>
          `;
        }

        // 3.11: a field the record offers editing on draws its value as a
        // control that opens its input, and never hides.
        if (this.editOffered(props)) {
          this.hidden = false;
          return this.renderEditable(props);
        }

        const isBoolean = props.format === "boolean";
        const links = linkEntries(props.link);
        // 3.1: a review field's state and citation, or null.
        const review = reviewEntry(props.review);
        // 3.8: the regions the value cites, linked with it in a document pane.
        const region = regionAddresses(review) || nothing;

        // 1.17: a steps field is empty when it has no steps.
        const steps = props.steps === undefined ? null : stepEntries(props.steps);
        const empty = steps ? steps.length === 0 : props.value == null || props.value === "";

        // 1.12: an empty field the surface hides draws nothing.
        this.hidden = Boolean(props.hideWhenEmpty) && empty;
        if (this.hidden) return nothing;

        if (empty && props.emptyText) {
          return html`
            <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region}>
              <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
              <dd class="field-value field-value-empty">${str(props.emptyText)}</dd>
            ${renderReview(review)}${this.renderFieldAction(props)}
            </dl>
          `;
        }

        const badge = str(props.badge);
        if (badge) {
          const tone = props.badgeTone ? badgeTone(props.badgeTone) : "neutral";
          const help = str(props.badgeHelp);
          return html`
            <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region}>
              <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
              <dd class="field-value">
                <span class="am-badge" data-tone=${tone} title=${help || nothing}
                  aria-description=${help || nothing}>${badge}</span>
              </dd>
            ${renderReview(review)}${this.renderFieldAction(props)}
            </dl>
          `;
        }

        if (steps) {
          return html`
            <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region}>
              <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
              <dd class="field-value">${renderSteps(steps)}</dd>
            ${renderReview(review)}${this.renderFieldAction(props)}
            </dl>
          `;
        }

        if (links.length > 0) {
          return html`
            <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region}>
              <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
              <dd class="field-value">${renderLinks(this, links)}</dd>
            ${renderReview(review)}${this.renderFieldAction(props)}
            </dl>
          `;
        }

        if (isBoolean) {
          const value = formatDisplayValue(props.value, props.format);
          return html`
            <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region}>
              <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
              <dd
                class="field-value field-value-boolean ${value === "Yes" ? "is-true" : "is-false"}"
              >
                ${value}
              </dd>
            ${renderReview(review)}${this.renderFieldAction(props)}
            </dl>
          `;
        }

        return html`
          <dl class="field" data-review=${review ? review.state : nothing} data-a2ui-region=${region}>
            <dt class="field-label">${str(props.label)}${props.note ? html` <span class="field-note">${str(props.note)}</span>` : nothing}</dt>
            <dd class="field-value">${renderValue(props.value, props.format)}</dd>
          ${renderReview(review)}${this.renderFieldAction(props)}
            </dl>
        `;
      }
    }

    customElements.define(tag, AshAdminFieldDisplay);
  }


  // --- SaveBar: the unsaved changes, saved or discarded (3.11) ---------------
  //
  // Shown while /ui/edits holds a change, and with showWhileWaiting (3.14)
  // while fields under review wait (`saveBarState`). Save sends
  // save_changes (choice "save"), or first opens the confirm dialog while
  // fields under review still wait (`saveDecision`); a save with no change
  // sends nothing (`choiceSends`). A swap draws its own bar and dialog from
  // `saveBarState` and `confirmTexts` and calls `onSave`, `onDiscard`,
  // `choose(choice)` and `closeConfirm`; it reads `confirmOpen()` and
  // `busy()`.

  function defineSaveBar() {
    const tag = TAGS.saveBar;
    if (customElements.get(tag)) return;

    class AshAdminSaveBar extends A2uiLitElement {
      static styles = [
        shared,
        buttons,
        content,
        css`
          :host {
            display: block;
            position: sticky;
            bottom: 0;
            z-index: 30;
          }
          :host([hidden]) {
            display: none;
          }
          .bar {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--am-space-s);
            padding: var(--am-space-s) var(--am-space-m);
            border-top: var(--am-border-width) solid var(--am-border);
            background: var(--am-surface, #fff);
          }
          .bar-message {
            margin: 0;
            font-weight: var(--am-font-weight-semibold);
          }
          .bar-actions {
            margin-inline-start: auto;
            display: flex;
            flex-wrap: wrap;
            gap: var(--am-space-s);
          }
          dialog {
            border: none;
            border-radius: var(--am-radius-m);
            padding: var(--am-space-l);
            max-width: 34rem;
          }
          dialog h2 {
            margin: 0 0 var(--am-space-s);
            font-size: var(--am-font-size-l);
          }
          dialog p {
            margin: 0 0 var(--am-space-m);
          }
          .dialog-actions {
            display: flex;
            flex-wrap: wrap;
            gap: var(--am-space-s);
          }
          .dialog-actions .spacer {
            flex: 1;
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.saveBar);
      }

      // The surface the bar reads and writes (its busy state settles on its outcomes).
      get surface() {
        return this.context?.dataContext?.surface;
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      /** Whether the confirm dialog is open. */
      confirmOpen() {
        return Boolean(this._amConfirmOpen);
      }

      /** Whether a save is on its way. */
      busy() {
        return Boolean(this._amSaveBusy);
      }

      /** Discard: drops every change and every refused save's message. */
      onDiscard() {
        const dataModel = this.context?.dataContext?.surface?.dataModel;
        if (dataModel && !this._amSaveBusy) discardEdits(dataModel);
      }

      /** Save: sends at once, or opens the dialog while fields still wait. */
      onSave() {
        const props = this.controller?.props;
        if (!props || this._amSaveBusy) return;
        const decision = saveDecision(props);
        if (decision === "confirm") {
          this._amConfirmOpen = true;
          this.requestUpdate();
        } else if (decision !== "none") {
          this.choose(decision);
        }
      }

      /**
       * Sends save_changes with `choice` ("save" or "then"), closing the
       * dialog. A "save" with no change sends nothing: there is nothing to
       * write.
       */
      choose(choice) {
        const props = this.controller?.props;
        const spec = choiceSends(props, choice) ? saveSpec(props, choice) : null;
        this.closeConfirm();
        if (!spec || this._amSaveBusy || !this.context?.componentModel) return;
        this._amSaveBusy = true;
        markActionBusy(this);
        this.requestUpdate();
        dispatchActionSpec(this.context, spec);
      }

      /** Closes the dialog with nothing sent. */
      closeConfirm() {
        if (!this._amConfirmOpen) return;
        this._amConfirmOpen = false;
        this.requestUpdate();
      }

      onActionSettled() {
        this._amSaveBusy = false;
      }

      /**
       * 3.15: sends the bar's preview envelope (preview_changes, quiet) once
       * the unsaved changes differ from the ones last sent, emptied ones
       * too, so the server's last answer always matches the changes held.
       * A swap that overrides `updated` keeps this by calling super.
       */
      sendPreview() {
        const props = this.controller?.props;
        const spec = previewSpec(props);
        if (!spec || !this.context?.componentModel) return;
        const key = editsKey(props.edits);
        if (key === (this._amPreviewKey ?? editsKey({}))) return;
        this._amPreviewKey = key;
        dispatchActionSpec(this.context, spec);
      }

      updated(changed) {
        super.updated?.(changed);
        this.sendPreview();
        const dialog = this.renderRoot?.querySelector?.("dialog");
        if (!dialog) return;
        if (this._amConfirmOpen && !dialog.open && typeof dialog.showModal === "function") dialog.showModal();
        if (!this._amConfirmOpen && dialog.open && typeof dialog.close === "function") dialog.close();
      }

      renderConfirm(props) {
        if (!props.confirm || !this._amConfirmOpen) return nothing;
        const texts = confirmTexts(props);
        return html`<dialog aria-labelledby="save-confirm-title" @cancel=${(event) => {
          event.preventDefault();
          this.closeConfirm();
        }} @click=${(event) => {
          if (event.target === event.currentTarget) this.closeConfirm();
        }}>
          <h2 id="save-confirm-title">${texts.title}</h2>
          ${texts.message ? html`<p>${texts.message}</p>` : nothing}
          <div class="dialog-actions">
            ${renderActionButton({label: texts.cancelLabel, onClick: () => this.closeConfirm()})}
            <span class="spacer"></span>
            ${renderActionButton({label: texts.saveLabel, onClick: () => this.choose("save")})}
            ${texts.thenLabel
              ? renderActionButton({label: texts.thenLabel, tone: "primary", onClick: () => this.choose("then")})
              : nothing}
          </div>
        </dialog>`;
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;
        const state = saveBarState(props);
        this.hidden = !state.shown;
        if (this.hidden) return nothing;

        const {message, status, statusReviewed} = state;
        const busy = Boolean(this._amSaveBusy);

        return html`<div class="bar" id=${props.domId || nothing} data-edit-count=${state.edits} data-waiting=${state.waiting} data-reviewed=${state.reviewed}>
            ${message ? html`<p class="bar-message" aria-live="polite">${message}</p>` : nothing}
            ${status ? html`<span class="am-badge" data-tone="warning">${status}</span>` : nothing}
            ${statusReviewed ? html`<span class="am-badge" data-tone="success">${statusReviewed}</span>` : nothing}
            <div class="bar-actions">
              ${state.discard
                ? renderActionButton({label: str(props.discardLabel), tone: "quiet", disabled: busy, onClick: () => this.onDiscard()})
                : nothing}
              ${renderActionButton({label: str(props.saveLabel), tone: "primary", busy, onClick: () => this.onSave()})}
            </div>
          </div>
          ${this.renderConfirm(props)}`;
      }
    }

    customElements.define(tag, AshAdminSaveBar);
  }

  const REVIEW_TONES = { pending: "warning", reviewed: "success", missing: "neutral" };

  // The state in words as a badge, then the page tag: a link to the source
  // when there is an address, its quote as the tooltip.
  function renderReview(review) {
    if (!review) return nothing;
    return html`<dd class="field-review">${reviewParts(review, "field-review-page")}</dd>`;
  }

  // 3.3: a table cell's review (a dataGrid column's review or its
  // subtitle's reviewPath), drawn as the detail one on the value's line.
  function renderCellReview(review) {
    if (!review) return nothing;
    return html`<span class="am-cell-review">${reviewParts(review, "am-cell-review-page")}</span>`;
  }

  function reviewParts(review, pageClass) {
    const quote = str(review.quote);
    const page = str(review.pageLabel);
    const href = str(review.href);
    return html`
      <span class="am-badge" data-tone=${REVIEW_TONES[review.state]}>${str(review.stateLabel) || review.state}</span>
      ${page
        ? href
          ? html`<a class=${pageClass} href=${href} title=${quote || nothing}>${page}</a>`
          : html`<span class=${pageClass} title=${quote || nothing}>${page}</span>`
        : nothing}
    `;
  }

  // 1.17: the steps a steps field binds, each {number, label, text?, note?,
  // state, stateLabel}; anything that is not a step with a label is skipped.
  function stepEntries(value) {
    if (!Array.isArray(value)) return [];
    return value.filter((step) => step && typeof step === "object" && str(step.label));
  }

  const STEP_STATES = ["complete", "current", "upcoming", "overdue"];
  const STEP_TONES = {
    complete: "success",
    current: "info",
    upcoming: "neutral",
    overdue: "danger",
  };

  // An ordered list: the number, label and state are text (the state is not
  // only a colour: its words sit in a badge beside the label), the current
  // step is aria-current, and text and note follow on their own lines.
  function renderSteps(steps) {
    return html`
      <ol class="field-steps" role="list">
        ${steps.map((step, index) => {
          const state = STEP_STATES.includes(step.state) ? step.state : "upcoming";
          const number = step.number ?? index + 1;
          const stateLabel = str(step.stateLabel) || state;
          return html`
            <li
              class="field-step"
              data-state=${state}
              aria-current=${state === "current" ? "step" : nothing}
            >
              <span class="field-step-number">${number}</span>
              <span class="field-step-body">
                <span class="field-step-head">
                  <span class="field-step-label">${str(step.label)}</span>
                  <span class="am-badge" data-tone=${STEP_TONES[state]}>${stateLabel}</span>
                </span>
                ${str(step.text) ? html`<span class="field-step-text">${str(step.text)}</span>` : nothing}
                ${str(step.note) ? html`<span class="field-step-note">${str(step.note)}</span>` : nothing}
              </span>
            </li>
          `;
        })}
      </ol>
    `;
  }

  // --- FormSection: labeled field grouping ----------------------------------

  function defineFormSection() {
    const tag = TAGS.formSection;
    if (customElements.get(tag)) return;

    // Frozen AshA2ui encoder id conventions (see AshA2ui.Encoder):
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
          return bindingPath(
            this.context?.dataContext?.surface?.componentsModel?.get(ref.id)?.properties?.value,
          );
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
        // model reports the action's outcome (see markActionBusy above).
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
              ? renderActionButton({
                  label,
                  tone: "primary",
                  destructive,
                  busy,
                  onClick: () => this.submit(),
                })
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

        const spec = adminActionSpec({
          name: "submit_form",
          context: buildSubmitFormContext(surface),
        });

        // Zero jank: the click is acknowledged before the envelope leaves
        // the browser — disabled + spinner now, settled by the outcome
        // write (or the encoder-driven `busy` prop) later.
        this._amOptimisticBusy = true;
        markActionBusy(this);
        this.requestUpdate();

        dispatchActionSpec(context, spec);
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
          :host([hidden]) {
            display: none;
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
        const props = this.controller?.props;
        applyWeight(this, props);
        // 1.10: with no feedback to show the banner takes no layout space
        // (a page body's gap would otherwise open around an empty host).
        const kind = props?.kind === null || props?.kind === undefined ? "" : String(props.kind);
        this.toggleAttribute("hidden", kind === "");
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
                ${renderActionButton({label: "Today", tone: "quiet", size: "sm", onClick: () => this.goToday()})}
                ${this.granularities.length > 1
                  ? html`<span class="cal-sizes" role="group" aria-label="Calendar view">
                      ${this.granularities.map((size) =>
                        renderActionButton({
                          label: this.sizeLabel(size),
                          tone: "quiet",
                          size: "sm",
                          pressed: size === this.granularity,
                          onClick: () => this.switchSize(size),
                        }),
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
                  ? renderActionButton({label: "All days", tone: "quiet", size: "sm", onClick: () => this.pickDay("")})
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
        const focused = focusedIn(element)?.dataset?.date;
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
        const spec = adminActionSpec(envelope);
        if (!surface || !context.componentModel || !spec) return;

        // A null key (a size switch) waits for no particular window.
        if (key === null) this.clearPending();
        else this.setPending(key, surface);
        dispatchActionSpec(context, {...spec, context: {...spec.context, ...extra}});
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
    // The badge is 2rem square (see .marker); the layout works in pixels.
    const MARKER_SIZE = 32;

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
            padding-bottom: calc(var(--am-space-m) + 2.5rem);
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
          .marker[data-tone="pending"] {
            --tone: var(--ash-admin-diagram-pending, var(--am-pending));
            --ink: var(--ash-admin-diagram-pending-ink, #ffffff);
          }
          .marker[data-tone="gray"] {
            --tone: var(--ash-admin-diagram-gray, var(--am-gray));
            --ink: var(--ash-admin-diagram-gray-ink, #ffffff);
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
        this._slots = {};
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
          const slots = this._slots[nodeId];
          if (!slots || !Array.isArray(markers)) continue;
          // Badges in a group beside their node (see placeMarkerGroups), so a
          // state box is never covered, however many are marked on it.
          markers.forEach((marker, index) => {
            const slot = slots[index];
            if (slot) rendered.push(this.renderMarker(marker, `left: ${slot.x}px; top: ${slot.y}px`));
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

      /** Marker badges placed clear of every node, then the edge labels moved
       * clear of one another, of every node and of the badges. */
      measure() {
        const frame = this.renderRoot.querySelector(".diagram-frame");
        const canvas = this.renderRoot.querySelector(".diagram-canvas");
        const svg = canvas && canvas.querySelector("svg");
        if (!frame || !svg) return;
        const origin = frame.getBoundingClientRect();
        const relative = (box) => ({
          x: Math.round(box.left - origin.left + frame.scrollLeft),
          y: Math.round(box.top - origin.top + frame.scrollTop),
          width: Math.round(box.width),
          height: Math.round(box.height),
        });
        const nodes = Array.from(svg.querySelectorAll("g.node")).map((node) => relative(node.getBoundingClientRect()));

        const groups = [];
        for (const [nodeId, markers] of Object.entries(this.markerMap())) {
          const node = findNode(canvas, nodeId);
          if (!node || !Array.isArray(markers) || markers.length === 0) continue;
          groups.push({id: nodeId, node: relative(node.getBoundingClientRect()), count: markers.length});
        }
        const slots = placeMarkerGroups(groups, nodes, {size: MARKER_SIZE});

        const badges = Object.values(slots)
          .flat()
          .map((slot) => ({
            x: slot.x - MARKER_SIZE / 2,
            y: slot.y - MARKER_SIZE / 2,
            width: MARKER_SIZE,
            height: MARKER_SIZE,
          }));
        this.arrangeLabels(canvas, relative, nodes, badges);

        if (JSON.stringify(slots) !== JSON.stringify(this._slots)) {
          this._slots = slots;
          this.requestUpdate();
        }
      }

      /** Moves each edge label the shortest distance that clears the other
       * labels, every node and the badges. Mermaid's own positions are kept
       * in `data-ash-origin` so a re-measure starts from them again. */
      arrangeLabels(canvas, relative, nodes, badges) {
        const svg = canvas.querySelector("svg");
        if (!svg) return;
        const elements = Array.from(svg.querySelectorAll("g.edgeLabel")).filter((element) =>
          (element.textContent || "").trim() !== "",
        );
        for (const element of elements) {
          const origin = element.dataset.ashOrigin ?? element.getAttribute("transform") ?? "";
          element.dataset.ashOrigin = origin;
          element.setAttribute("transform", origin);
        }
        if (elements.length === 0) return;

        const box = svg.getBoundingClientRect();
        const viewBox = svg.viewBox && svg.viewBox.baseVal;
        const scale = viewBox && viewBox.width > 0 && box.width > 0 ? box.width / viewBox.width : 1;

        const items = elements.map((element, index) => ({id: index, ...relative(element.getBoundingClientRect())}));
        const moves = separate(items, [...nodes, ...badges], {gap: 4, step: 4, radius: 200});

        elements.forEach((element, index) => {
          const {dx, dy} = moves[index];
          if (dx === 0 && dy === 0) return;
          const match = /translate\(\s*(-?[\d.]+)[ ,]+(-?[\d.]+)\s*\)/.exec(element.dataset.ashOrigin);
          const x = match ? Number(match[1]) : 0;
          const y = match ? Number(match[2]) : 0;
          element.setAttribute("transform", `translate(${x + dx / scale}, ${y + dy / scale})`);
        });
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

      // A2uiLitElement renders only once it has a controller, and this
      // dialog never gets one (no controller binding, no context: the
      // DataGrid mounts it by hand), so it rendered nothing at all. Render
      // through LitElement directly.
      update(changedProperties) {
        Object.getPrototypeOf(A2uiLitElement.prototype).update.call(this, changedProperties);
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        if (!changedProperties.has("open")) return;

        if (this.open) {
          // Read before the heading takes focus: the control that opened
          // the dialog, from the root the dialog sits in (in shadow DOM,
          // document.activeElement would be the outermost host).
          this._amRestoreFocus = focusedAround(this);
          const heading = this.renderRoot?.querySelector("[data-dialog-heading]");
          if (heading) heading.focus();
        } else if (changedProperties.get("open") === true && this.isConnected) {
          this.restoreFocus();
        }
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        // The DataGrid removes this element on confirm/cancel — restoring
        // focus to the invoking row button is the closing act. It sets
        // `open = false` just before, and removal comes before that update
        // runs, so the pending restore target is what says it was open.
        if (this.open || this._amRestoreFocus) this.restoreFocus();
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
          // Focus trap: cycle within the dialog while it is open, in light
          // or shadow DOM (focusedIn). Tab past the last control wraps to
          // the first and Shift+Tab before the first to the last; from the
          // heading (tabindex -1, not in the cycle) or from anywhere outside
          // the controls, focus is brought back inside.
          const focusables = [
            ...this.renderRoot.querySelectorAll(
              'button, [data-am-button], [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
            ),
          ].filter(
            (element, _index, all) =>
              !element.hasAttribute("disabled") &&
              // a design-system button host and its own <button> are one stop
              !all.some((other) => other !== element && other.contains(element)),
          );
          if (focusables.length === 0) return;
          const first = focusables[0];
          const last = focusables[focusables.length - 1];
          const active = focusedIn(this);
          const index = focusables.findIndex((element) => element === active || element.contains(active));
          if (event.shiftKey && index <= 0) {
            event.preventDefault();
            last.focus();
          } else if (!event.shiftKey && (index === -1 || index === focusables.length - 1)) {
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
                ${renderActionButton({label: "Cancel", onClick: () => this.cancel()})}
                ${renderActionButton({
                  label: str(this.confirmLabel) || "Confirm",
                  tone: "primary",
                  destructive: this.destructive,
                  onClick: () => this.confirm(),
                })}
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
                  placeholder=${props.placeholder ? str(props.placeholder) : nothing}
                  .value=${props.value ?? ""}
                  aria-invalid=${invalid ? "true" : "false"}
                  aria-describedby=${invalid ? errorId : ""}
                  @input=${(event) => props.setValue?.(event.target.value)}
                ></textarea>`
              : html`<input
                  id=${inputId}
                  class="control"
                  type=${type}
                  placeholder=${props.placeholder ? str(props.placeholder) : nothing}
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
          .hint {
            margin-top: var(--am-space-2xs);
            font-size: var(--am-font-size-xs);
            color: var(--am-text-muted);
          }
          .choice-leaf {
            padding-inline-start: var(--am-space-l);
          }
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
        // 1.10: a path filter's options arrive bound (`dynamicOptions`),
        // after any static ones.
        const options = [
          ...(Array.isArray(props.options) ? props.options : []),
          ...(Array.isArray(props.dynamicOptions) ? props.dynamicOptions : []),
        ];
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
              ${options
                .filter((option) => option.group !== true)
                .map(
                  (option) => html`
                    <option value=${option.value} ?selected=${option.value === current}>
                      ${option.label}${this.countText(props, option)}
                    </option>
                  `,
                )}
            </select>
            ${this.renderHint(props, baseId)}
            ${invalid
              ? html`<div class="error" id=${`${baseId}-error`}>${errors[0]}</div>`
              : nothing}
          </div>
        `;
      }

      /** " (n)" from the 1.10 `counts` map, for an option with a value. */
      countText(props, option) {
        const counts = props.counts;
        if (!counts || typeof counts !== "object" || option.value === "") return "";
        const count = counts[option.value];
        return typeof count === "number" ? ` (${count})` : "";
      }

      /** The 1.10 `hint`, under the options. */
      renderHint(props, baseId) {
        return props.hint
          ? html`<div class="hint" id=${`${baseId}-hint`}>${str(props.hint)}</div>`
          : nothing;
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
        // 1.10 groups: a group selects (or clears) all its leaves; only leaf
        // values are ever written.
        const leavesOf = (group) =>
          options.filter((option) => option.parent === group).map((option) => option.value);
        const toggleGroup = (group) => {
          if (!props.setValue) return;
          const leaves = leavesOf(group);
          const all = leaves.every((leaf) => selected.includes(leaf));
          props.setValue(
            all
              ? selected.filter((item) => !leaves.includes(item))
              : [...selected, ...leaves.filter((leaf) => !selected.includes(leaf))],
          );
        };

        return html`
          <div class="field">
            <fieldset
              class="choices"
              aria-describedby=${[errors.length ? errorId : "", props.hint ? `${baseId}-hint` : ""]
                .filter(Boolean)
                .join(" ")}
            >
              ${props.label ? html`<legend class="choices-legend">${props.label}</legend>` : nothing}
              ${options.map((option, index) => {
                const optionId = `${baseId}-opt-${index}`;
                if (option.group === true) {
                  const leaves = leavesOf(option.value);
                  const picked = leaves.filter((leaf) => selected.includes(leaf)).length;
                  return html`
                    <label class="choice choice-group" for=${optionId}>
                      <input
                        id=${optionId}
                        type="checkbox"
                        .checked=${leaves.length > 0 && picked === leaves.length}
                        .indeterminate=${picked > 0 && picked < leaves.length}
                        @change=${() => toggleGroup(option.value)}
                      />
                      ${option.label}${this.countText(props, option)}
                    </label>
                  `;
                }
                return html`
                  <label
                    class=${option.parent ? "choice choice-leaf" : "choice"}
                    for=${optionId}
                  >
                    <input
                      id=${optionId}
                      type="checkbox"
                      .checked=${selected.includes(option.value)}
                      @change=${() => toggle(option.value)}
                    />
                    ${option.label}${this.countText(props, option)}
                  </label>
                `;
              })}
            </fieldset>
            ${this.renderHint(props, baseId)}
            ${errors.length > 0 ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminChoicePicker);

    // The admin filterPicker draws exactly like the choicepicker, bound to
    // its own Api (the same extended schema under the filterPicker name).
    if (adminApis.filterPicker && !customElements.get(TAGS.filterPicker)) {
      class AshAdminFilterPicker extends AshAdminChoicePicker {
        createController() {
          return new A2uiController(this, adminApis.filterPicker);
        }
      }
      customElements.define(TAGS.filterPicker, AshAdminFilterPicker);
    }
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
