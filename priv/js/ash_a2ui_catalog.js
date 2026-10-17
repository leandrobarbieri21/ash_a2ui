/**
 * AshA2ui merged component catalog for the `@a2ui/lit` renderer.
 *
 * The A2UI basic catalog is deliberately small, and two of its structures
 * are the wrong control for admin-style surfaces:
 *
 *   1. **ChoicePicker** renders every single-choice picker as a radio list
 *      (its only `displayStyle`s are `checkbox` and `chips` — there is no
 *      dropdown, through spec v1.0).
 *   2. **Search pickers** (AshA2ui's surface-context pickers and searchable
 *      relationship selects) are emitted as a basic-catalog composite —
 *      label + selected text + search TextField + Search Button + a flat
 *      option List — because the basic catalog has no combobox. Rendered
 *      literally, every option shows before the user searches and nothing
 *      overlays.
 *   3. **The stock anatomy is not neobrutalist** (CLIN-10): badges are
 *      11px grey italic captions, the primary Button hardcodes
 *      `border: none`, buttons have no size scale (they inherit the 16px
 *      page font), row actions and pagination render at full primary mass,
 *      and the status region is a naked bound Text. No token reaches
 *      those — see the CLIN-10 root-cause map.
 *
 * No amount of CSS-variable theming can fix either, because both are
 * structural. `createAshA2uiCatalog(deps)` builds a Catalog registered
 * under the SAME catalog id the AshA2ui encoder emits (the basic catalog
 * id) with catalog-level fixes:
 *
 *   - **ChoicePicker** → `<ash-a2ui-choicepicker>`: a native, token-themed
 *     `<select>` for `mutuallyExclusive` pickers (checkbox list for
 *     `multipleSelection`).
 *   - **Column** → `<ash-a2ui-column>` (only when `ColumnApi` is passed):
 *     renders exactly like the basic Column, EXCEPT when the component is
 *     an AshA2ui picker composite — detected through the extension's
 *     frozen id contract (`context_<name>_body`, `form_select_<field>`)
 *     plus structural verification against the live component tree. Then:
 *       - a **searchable** composite renders as a real typeahead combobox:
 *         debounced search-as-you-type driving the emitted
 *         `context_search` / `option_search` action, results in an
 *         anchored overlay with keyboard navigation, and the selection
 *         collapsed to a compact chip with a Clear affordance;
 *       - a **non-searchable** context picker renders its options as a
 *         horizontal chip group with the selection highlighted.
 *     Composites the detector cannot fully verify fall back to the plain
 *     column rendering, which is also what any stock basic-catalog
 *     renderer shows — the emitted tree stays 100% basic catalog
 *     (progressive enhancement, no custom component types on the wire).
 *   - **Text** → `<ash-a2ui-text>` and **Button** → `<ash-a2ui-button>`:
 *     the CLIN-10 neobrutalist anatomy overrides — see the
 *     "Neobrutalist anatomy overrides" section below the imports.
 *
 * ## Contract with the host bundle
 *
 * Like the hook, this file ships with **no bundled dependencies** (the
 * host bundle owns the single `lit` / `@a2ui` instance; NODE_PATH-based
 * resolution from inside `deps/` would not find them anyway). The host
 * passes the classes in:
 *
 *     import {html, css, nothing} from "lit";
 *     import {basicCatalog, A2uiLitElement, A2uiController} from "@a2ui/lit/v0_9";
 *     import {Catalog} from "@a2ui/web_core/v0_9";
 *     import {ChoicePickerApi, ColumnApi} from "@a2ui/web_core/v0_9/basic_catalog";
 *     import {createAshA2uiCatalog} from "../../deps/ash_a2ui/priv/js/ash_a2ui_catalog.js";
 *
 *     const catalog = createAshA2uiCatalog({
 *       Catalog,
 *       basicCatalog,
 *       ChoicePickerApi,
 *       ColumnApi, // optional: omit to keep the stock Column (no combobox)
 *       A2uiLitElement,
 *       A2uiController,
 *       lit: {html, css, nothing},
 *     });
 *     configureAshA2ui({MessageProcessor, catalogs: [catalog]});
 *
 * The anatomy overrides subclass the upstream Text and Button elements.
 * No published `@a2ui/web_core` or `@a2ui/lit` entry point exports those
 * classes, so they are resolved at RUNTIME from the custom-element
 * registry: `customElements.get(basicCatalog.components.get("Text").tagName)`.
 * Importing `@a2ui/lit/v0_9` (which is where the host gets `basicCatalog`)
 * registers them, so they are always present by the time the factory
 * runs. Subclassing keeps markdown rendering, controller wiring, action
 * dispatch and `renderNode` semantics correct BY CONSTRUCTION — the
 * overrides layer styles and id-keyed anatomy on top, and anything they do
 * not match renders exactly upstream. If an upstream element is not
 * registered, that override is skipped with a console warning and the
 * stock element renders.
 *
 * Verified against @a2ui/lit 0.10.1 / @a2ui/web_core 0.10.4 (the
 * reference-link tier and the banner teardown also against @a2ui/lit +
 * @a2ui/web_core 0.11.0, where the basic components render into light DOM
 * and web_core's A2uiLitElement scopes `static styles` to the tag):
 * `new Catalog(id, components, functions, themeSchema)` takes
 * `{...ComponentApi, tagName}` entries; the renderer resolves
 * `createSurface.catalogId` by exact string match and renders each
 * component type via `catalog.components.get(type).tagName`. Custom
 * elements reach the surface state through `this.context`
 * (`componentModel.id`, `dataContext.surface.{dataModel,componentsModel,
 * dispatchAction}`) — the same seams the basic catalog uses.
 */

const CHOICEPICKER_TAG = "ash-a2ui-choicepicker";
const COLUMN_TAG = "ash-a2ui-column";
const TEXT_TAG = "ash-a2ui-text";
const BUTTON_TAG = "ash-a2ui-button";

/**
 * Builds the merged catalog. See the module docs for the `deps` contract.
 *
 * @returns {object} a `@a2ui/web_core` Catalog registered under the basic
 *   catalog's id, with ChoicePicker (and, when `ColumnApi` is given,
 *   Column) replaced.
 */
export function createAshA2uiCatalog(deps) {
  const {Catalog, basicCatalog, ChoicePickerApi, ColumnApi, A2uiLitElement, A2uiController, lit} =
    deps;

  if (
    !Catalog ||
    !basicCatalog ||
    !ChoicePickerApi ||
    !A2uiLitElement ||
    !A2uiController ||
    !lit
  ) {
    throw new Error(
      "createAshA2uiCatalog: missing deps. Pass {Catalog, basicCatalog, " +
        "ChoicePickerApi, A2uiLitElement, A2uiController, lit: {html, css, nothing}} " +
        "(plus ColumnApi for the search-picker combobox).",
    );
  }

  defineChoicePickerElement(deps);
  if (ColumnApi) defineColumnElement(deps);
  defineAnatomyElements(deps);

  const overrides = new Map([["ChoicePicker", {...ChoicePickerApi, tagName: CHOICEPICKER_TAG}]]);
  if (ColumnApi) overrides.set("Column", {...ColumnApi, tagName: COLUMN_TAG});
  // The CLIN-10 anatomy overrides spread the basic catalog's own API
  // entries (the components map holds them) and swap only the tag.
  for (const [type, tag] of [
    ["Text", TEXT_TAG],
    ["Button", BUTTON_TAG],
  ]) {
    const api = basicCatalog.components.get(type);
    if (api && customElements.get(tag)) overrides.set(type, {...api, tagName: tag});
  }

  const components = [...basicCatalog.components.values()].map(
    (component) => overrides.get(component.name) || component,
  );

  return new Catalog(
    basicCatalog.id,
    components,
    [...basicCatalog.functions.values()],
    basicCatalog.themeSchema,
  );
}

// --- shared helpers ---------------------------------------------------------

// Resolves an A2UI data binding leaf ({"path": ...}) against the surface
// data model; relative paths resolve under basePath (the option row's
// template scope). Non-binding values pass through, matching the
// GenericBinder's action-context resolution semantics.
function resolveEventContext(value, dataModel, basePath) {
  if (value === null || typeof value !== "object") return value;
  if (typeof value.path === "string" && Object.keys(value).length === 1) {
    const abs = value.path.startsWith("/")
      ? value.path
      : `${basePath.replace(/\/$/, "")}/${value.path}`;
    return dataModel.get(abs);
  }
  if (Array.isArray(value)) return value.map((v) => resolveEventContext(v, dataModel, basePath));
  const out = {};
  for (const [k, v] of Object.entries(value)) out[k] = resolveEventContext(v, dataModel, basePath);
  return out;
}

// --- ChoicePicker override ---------------------------------------------------

// Defines <ash-a2ui-choicepicker> once (idempotent across LiveView
// remounts and hot reloads). Written without decorators so the file stays
// plain JS with injected dependencies.
function defineChoicePickerElement({A2uiLitElement, A2uiController, ChoicePickerApi, lit}) {
  if (customElements.get(CHOICEPICKER_TAG)) return;

  const {html, css, nothing} = lit;

  class AshA2uiChoicePickerElement extends A2uiLitElement {
    /**
     * Styling knobs (all optional, themed by the same tokens as the rest
     * of the basic catalog):
     *
     * - `--a2ui-color-input` / `--a2ui-color-on-input`: select colors.
     * - `--a2ui-textfield-border`: select border (shared with TextField).
     * - `--a2ui-choicepicker-select-border-radius`: select corner radius.
     * - `--a2ui-choicepicker-select-padding`: select padding.
     * - `--a2ui-choicepicker-label-*`, `--a2ui-choicepicker-gap`: as in
     *   the basic catalog's ChoicePicker.
     */
    static styles = css`
      :host {
        display: flex;
        flex-direction: column;
        gap: var(--a2ui-choicepicker-gap, var(--a2ui-spacing-xs, 0.25rem));
      }
      label {
        color: var(--a2ui-choicepicker-label-color, inherit);
        font-size: var(
          --a2ui-choicepicker-label-font-size,
          var(--a2ui-label-font-size, var(--a2ui-font-size-s))
        );
        font-weight: var(
          --a2ui-choicepicker-label-font-weight,
          var(--a2ui-label-font-weight, bold)
        );
      }
      select {
        background-color: var(--a2ui-color-input, #fff);
        color: var(--a2ui-color-on-input, #333);
        border: var(--a2ui-textfield-border, var(--a2ui-border, 1px solid #ccc));
        border-radius: var(
          --a2ui-choicepicker-select-border-radius,
          var(--a2ui-border-radius, 0.25rem)
        );
        padding: var(
          --a2ui-choicepicker-select-padding,
          var(--a2ui-spacing-s, 0.25rem) var(--a2ui-spacing-m, 0.5rem)
        );
        font-family: inherit;
        font-size: inherit;
        max-width: 100%;
      }
      select:focus {
        outline: none;
        border-color: var(
          --a2ui-textfield-color-border-focus,
          var(--a2ui-color-primary, #17e)
        );
      }
      .options {
        display: flex;
        flex-direction: column;
        gap: var(--a2ui-choicepicker-gap, var(--a2ui-spacing-xs, 0.25rem));
      }
      .option-label {
        font-weight: normal;
        font-size: inherit;
      }
    `;

    createController() {
      return new A2uiController(this, ChoicePickerApi);
    }

    render() {
      const props = this.controller?.props;
      if (!props) return nothing;

      // The A2UI schema types ChoicePicker value as a string list, but a
      // server data-model refresh can echo a scalar back into the binding
      // (e.g. AshA2ui's /query/filters/<name>); accept both.
      const raw = props.value;
      const selected = Array.isArray(raw) ? raw : raw == null ? [] : [String(raw)];
      const options = props.options || [];

      const body =
        props.variant === "multipleSelection"
          ? this.renderCheckboxes(props, options, selected)
          : this.renderSelect(props, options, selected);

      return html`
        ${props.label ? html`<label>${props.label}</label>` : nothing} ${body}
      `;
    }

    renderSelect(props, options, selected) {
      const {html, nothing} = lit;
      let current = selected.length > 0 ? selected[0] : undefined;
      // An unset binding on a picker that offers an empty-valued option
      // (AshA2ui's "All" filter/preset option) means "all" — show that
      // option rather than a placeholder.
      if (current === undefined && options.some((opt) => opt.value === "")) {
        current = "";
      }
      const hasMatch = options.some((opt) => opt.value === current);

      return html`
        <select
          aria-label=${props.label || "Choose an option"}
          @change=${(e) => props.setValue && props.setValue([e.target.value])}
        >
          ${hasMatch
            ? nothing
            : html`<option value="" disabled selected hidden>Select…</option>`}
          ${options.map(
            (opt) =>
              html`<option value=${opt.value} ?selected=${opt.value === current}>
                ${opt.label}
              </option>`,
          )}
        </select>
      `;
    }

    renderCheckboxes(props, options, selected) {
      const {html} = lit;

      const toggle = (value) => {
        if (!props.setValue) return;
        if (selected.includes(value)) {
          props.setValue(selected.filter((v) => v !== value));
        } else {
          props.setValue([...selected, value]);
        }
      };

      return html`
        <div class="options">
          ${options.map(
            (opt) => html`
              <label class="option-label">
                <input
                  type="checkbox"
                  .checked=${selected.includes(opt.value)}
                  @change=${() => toggle(opt.value)}
                />
                ${opt.label}
              </label>
            `,
          )}
        </div>
      `;
    }

    // The basic catalog's shared base class applies the layout `weight`
    // prop as flex; replicate that here since the base class isn't part of
    // @a2ui/lit's public exports.
    willUpdate(changedProperties) {
      super.willUpdate(changedProperties);
      const props = this.controller?.props;
      if (props && props.weight !== undefined) {
        this.style.flex = String(props.weight);
      } else {
        this.style.removeProperty("flex");
      }
    }
  }

  customElements.define(CHOICEPICKER_TAG, AshA2uiChoicePickerElement);
}

// --- Neobrutalist anatomy overrides (CLIN-10) -------------------------------
//
// The stock basic-catalog anatomy cannot be reached with tokens (the
// root-cause map's findings #1/#2/#7/#8): badges are 11px grey italic
// captions, the primary Button hardcodes `border: none`, buttons inherit
// the 16px page font with no size scale, and row actions + pagination
// render at full primary mass. The overrides below subclass the upstream
// Lit elements — markdown rendering, the controller, action dispatch and
// renderNode are inherited, not reimplemented — and layer two things on
// top: a neobrutalist stylesheet (appended AFTER the upstream styles, so
// equal-specificity rules win by order) and id-keyed anatomy from the
// encoder's frozen id vocabulary. The wire stays 100% stock basic catalog;
// an id the rules do not know renders exactly upstream.
//
// Id keys (all long-standing encoder conventions, none new wire):
//   `*_badge`           row-layout badge Texts → the badge anatomy
//   `status_text`       the feedback region → the tone-aware banner
//   `table_heading*`    section/lane headings → h2 with the section chip
//   `stage_*_heading`   a swimlaned board's stage headings → the same chip
//   `surface_title`     the surface's h1 → the display tier
//   Texts inside a `swimlane_*` row and outside any Card or Button (the
//   swimlane heading and total, the cell totals, empty-state and
//   pagination texts) → the swimlane band's ink
//   `row_action_*_button`, `*_prev_button`, `*_next_button`, and a
//   calendar's `calendar*_today_button` / `_all_button` / `_day_button`
//                      → the quiet utility tier (sm, shadowless)
//   `<value id>_link`   a borderless Button whose child is `<value id>`
//                      (link_buttons: true) → the reference-link tier
//
// Tokens: everything reads `--a2ui-*` with the neobrutalism.dev literals
// as fallbacks (2px black borders, 4px/4px/0 hard shadow, 5px radius,
// black ink on every fill) — the tier defaults ship in
// ash_a2ui_theme.css, and a host that already bridges `--a2ui-*` (as
// clinic-demo does) needs zero new tokens.

// The badge tone map: label text → tone class. The vocabulary matches the
// clinic's lane/status language (the app's own badge_fill/1); anything
// unmatched is the neutral white chip — "filled = needs attention, white
// = metadata" per the digest.
const BADGE_TONES = [
  [/emergen/, "emergency"],
  [/urgent|^high$/, "urgent"],
  [/^soon$|^medium$/, "soon"],
  [/routine|^low$/, "routine"],
  [/^active$/, "routine"],
  [/visit|checked.?in/, "visit"],
  [/discharged|completed/, "discharged"],
  [/scheduled|booked/, "booked"],
  // The compliance vocabulary (AshCompliance's bundle labels surface in
  // row badges): compliant is the green "clear" read, noncompliant the
  // red "blocked" one — the one place red means go/no-go rather than
  // triage. Written broadly (compl- stems) to catch "Noncompliant",
  // "Non-compliant", and "Compliant" alike.
  [/non.?compliant/, "noncompliant"],
  [/^compliant$/, "compliant"],
];

function badgeTone(label) {
  const text = String(label ?? "").toLowerCase();
  for (const [pattern, tone] of BADGE_TONES) if (pattern.test(text)) return tone;
  return "neutral";
}

// The section-chip palette: headings cycle deterministically — the tone is
// a hash of the heading text, so the same section keeps its color across
// renders and pages.
const SECTION_TONES = ["main", "violet", "cyan", "green", "orange", "pink"];

function sectionTone(label) {
  const text = String(label ?? "");
  let hash = 0;
  for (let index = 0; index < text.length; index++) hash = (hash * 31 + text.charCodeAt(index)) >>> 0;
  return SECTION_TONES[hash % SECTION_TONES.length];
}

function componentIdOf(element) {
  try {
    return element.context?.componentModel?.id ?? "";
  } catch {
    return "";
  }
}

// The upstream element class for a basic-catalog component type, taken from
// the custom-element registry under the tag the basic catalog renders it
// with. Returns undefined when the type or its element is not registered.
function upstreamElementClass(basicCatalog, type) {
  const tagName = basicCatalog?.components?.get(type)?.tagName;
  return tagName ? customElements.get(tagName) : undefined;
}

function defineAnatomyElements({lit, basicCatalog}) {
  if (!lit) return;
  const {html, nothing} = lit;

  const A2uiBasicTextElement = upstreamElementClass(basicCatalog, "Text");
  const A2uiBasicButtonElement = upstreamElementClass(basicCatalog, "Button");
  if (!A2uiBasicTextElement || !A2uiBasicButtonElement) {
    console.warn(
      "createAshA2uiCatalog: the upstream Text/Button elements are not registered " +
        "(import @a2ui/lit/v0_9 first); the anatomy overrides are skipped.",
    );
    return;
  }

  class AshA2uiTextElement extends A2uiBasicTextElement {
    static styles = [
      super.styles,
      lit.css`
        /* The tier correction: captions are small BLACK metadata, not
         * grey italics — the style has no grey text tier. */
        .a2ui-text.caption,
        .a2ui-text.caption em {
          font-style: normal;
          font-weight: var(--a2ui-label-font-weight, 500);
          color: var(--a2ui-text-caption-color, var(--a2ui-color-on-surface, inherit));
        }

        /* The badge anatomy (digest §4): 2px black border, shared radius,
         * text-xs floor, saturated fill with BLACK ink. Prominence is the
         * fill + border — never size, never grey. */
        .a2ui-badge {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 0.25rem;
          box-sizing: border-box;
          border: var(--a2ui-badge-border, 2px solid var(--a2ui-color-border, #141414));
          border-radius: var(--a2ui-badge-border-radius, 5px);
          padding: var(--a2ui-badge-padding, 0.125rem 0.625rem);
          font-size: var(--a2ui-badge-font-size, 0.75rem);
          font-weight: var(--a2ui-badge-font-weight, 500);
          color: var(--a2ui-badge-color, var(--a2ui-color-on-surface, #141414));
          white-space: nowrap;
          width: fit-content;
          overflow: hidden;
        }
        .a2ui-badge em {
          font-style: normal;
        }
        .nb-tone-emergency {
          background: var(--a2ui-badge-emergency-fill, #ff5c64);
        }
        .nb-tone-urgent {
          background: var(--a2ui-badge-urgent-fill, #ffa94d);
        }
        .nb-tone-soon {
          background: var(--a2ui-badge-soon-fill, #ffd83d);
        }
        .nb-tone-routine {
          background: var(--a2ui-badge-routine-fill, #4fd07a);
        }
        .nb-tone-visit {
          background: var(--a2ui-badge-visit-fill, #b78aff);
        }
        .nb-tone-discharged {
          background: var(--a2ui-badge-discharged-fill, #38c8e8);
        }
        .nb-tone-booked {
          background: var(--a2ui-badge-booked-fill, var(--a2ui-color-primary, #3b82f6));
        }
        .nb-tone-neutral {
          background: var(--a2ui-badge-neutral-fill, var(--a2ui-color-surface, #ffffff));
        }
        /* Compliance pair: green/red with BLACK ink (the black-on-color
         * rule) — tokens mirror the routine/emergency hues so a host
         * bridging the palette gets both families coherently. */
        .nb-tone-compliant {
          background: var(--a2ui-badge-compliant-fill, var(--a2ui-badge-routine-fill, #4fd07a));
        }
        .nb-tone-noncompliant {
          background: var(--a2ui-badge-noncompliant-fill, var(--a2ui-badge-emergency-fill, #ff5c64));
        }

        /* The feedback banner (digest §5 Alert): bordered, filled by
         * tone, hard shadow; destructive is the one sanctioned inversion
         * — black card, white ink. Empty message + no tone renders
         * nothing (the region is authoritative, not decorative). */
        .a2ui-banner {
          display: block;
          box-sizing: border-box;
          width: 100%;
          border: var(--a2ui-banner-border, 2px solid var(--a2ui-color-border, #141414));
          border-radius: var(--a2ui-banner-border-radius, 5px);
          padding: var(--a2ui-banner-padding, 0.5rem 0.875rem);
          font-size: var(--a2ui-font-size-m, 0.875rem);
          font-weight: var(--a2ui-button-font-weight, 500);
          box-shadow: var(--a2ui-banner-box-shadow, 4px 4px 0 0 var(--a2ui-color-border, #141414));
          background: var(--a2ui-color-surface, #ffffff);
          color: var(--a2ui-color-on-surface, #141414);
          margin: var(--a2ui-banner-margin, 0 0 0.5rem 0);
        }
        .nb-banner-error {
          background: var(--a2ui-banner-error-fill, #141414);
          color: var(--a2ui-banner-error-color, #ffffff);
        }
        .nb-banner-warning {
          background: var(--a2ui-banner-warning-fill, #ffd83d);
          color: #141414;
        }
        .nb-banner-success {
          background: var(--a2ui-banner-success-fill, #4fd07a);
          color: #141414;
        }

        /* Section headings (digest: identity via color chips): a tilted
         * saturated square before the h2 text, deterministic per label.
         * ::before — the heading's DOM (and its aria) stays upstream's. */
        .a2ui-text.nb-section {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
        }
        .a2ui-text.nb-section::before {
          content: "";
          display: inline-block;
          width: 0.875rem;
          height: 0.875rem;
          flex: none;
          border: 2px solid var(--a2ui-color-border, #141414);
          border-radius: 3px;
          transform: rotate(-8deg);
        }
        .nb-section-tone-main::before {
          background: var(--a2ui-badge-booked-fill, var(--a2ui-color-primary, #3b82f6));
        }
        .nb-section-tone-violet::before {
          background: var(--a2ui-badge-visit-fill, #b78aff);
        }
        .nb-section-tone-cyan::before {
          background: var(--a2ui-badge-discharged-fill, #38c8e8);
        }
        .nb-section-tone-green::before {
          background: var(--a2ui-badge-routine-fill, #4fd07a);
        }
        .nb-section-tone-orange::before {
          background: var(--a2ui-badge-urgent-fill, #ffa94d);
        }
        .nb-section-tone-pink::before {
          background: var(--a2ui-badge-pink-fill, #ff9ec9);
        }

        /* The surface title: the display tier — one step above the h2
         * sections, heading weight, the surface's one display statement. */
        .a2ui-text.nb-title {
          display: block;
          font-size: var(--a2ui-font-size-2xl, 1.5rem);
        }
        .a2ui-text.nb-title h1 {
          font-size: inherit;
          line-height: var(--a2ui-line-height-headings, 1.2);
          letter-spacing: -0.01em;
        }
      `,
    ];

    connectedCallback() {
      super.connectedCallback();
      this.__bannerUnsubscribes = null;
    }

    disconnectedCallback() {
      super.disconnectedCallback();
      this.teardownBannerSubscriptions();
    }

    // `DataModel.subscribe` returns a subscription object ({value,
    // unsubscribe()}), not a function — the same in @a2ui/web_core 0.10.x
    // and 0.11.x. Calling the object threw "unsubscribe is not a function"
    // whenever the banner left the DOM (a link navigation, a LiveView patch).
    teardownBannerSubscriptions() {
      for (const subscription of this.__bannerUnsubscribes || []) subscription.unsubscribe();
      this.__bannerUnsubscribes = null;
    }

    // The status banner re-renders when the feedback KIND flips — the
    // tone is data (only the client sees it), so the banner subscribes to
    // its own source of truth. Same pattern as the picker's data
    // subscriptions.
    willUpdate(changedProperties) {
      super.willUpdate(changedProperties);
      const id = componentIdOf(this);
      if (id === "status_text" && !this.__bannerUnsubscribes) {
        try {
          const {dataModel} = this.context.dataContext.surface;
          this.__bannerUnsubscribes = [
            dataModel.subscribe("/ui/feedback/kind", () => this.requestUpdate()),
          ];
        } catch {
          // No surface yet — the next context change retries.
        }
      }
    }

    readFeedbackKind() {
      try {
        return String(this.context.dataContext.surface.dataModel.get("/ui/feedback/kind") ?? "");
      } catch {
        return "";
      }
    }

    render() {
      const props = this.controller?.props;
      if (!props) return nothing;
      const id = componentIdOf(this);

      if (id.endsWith("_badge")) {
        const text = typeof props.text === "string" ? props.text : String(props.text ?? "");
        const flexStyle = typeof props.weight === "number" ? `flex: ${props.weight};` : nothing;
        return html`<span
          class="a2ui-badge nb-tone-${badgeTone(text)}"
          style=${flexStyle}
          title=${text}
        >${text}</span>`;
      }

      if (id === "status_text") {
        const message = typeof props.text === "string" ? props.text : String(props.text ?? "");
        const kind = this.readFeedbackKind();
        if (message.trim() === "" && kind === "") return nothing;
        const tone =
          kind === "error" ? "error" : kind === "warning" ? "warning" : kind === "success" ? "success" : "info";
        return html`<span
          class="a2ui-banner nb-banner-${tone}"
          role=${tone === "error" ? "alert" : "status"}
          aria-live="polite"
        >${message}</span>`;
      }

      return super.render();
    }

    // Headings and the title keep upstream's DOM; the anatomy classes (and
    // their ::before chips) ride along without touching structure or aria.
    updated(changedProperties) {
      super.updated(changedProperties);
      const id = componentIdOf(this);
      // Texts on a swimlane's band take its ink (--a2ui-swimlane-ink, set
      // by the swimlane Column from its tone) through the two properties
      // upstream's Text colour reads — on the host, so it holds whether the
      // renderer colours the host (0.10.x) or an inner span (0.11.x).
      if (onSwimlaneBand(this)) {
        this.style.setProperty("--_a2ui-text-color", "var(--a2ui-swimlane-ink)");
        this.style.setProperty("--a2ui-text-caption-color", "var(--a2ui-swimlane-ink)");
        this.dataset.swimlaneInk = "";
      } else if (this.dataset.swimlaneInk !== undefined) {
        this.style.removeProperty("--_a2ui-text-color");
        this.style.removeProperty("--a2ui-text-caption-color");
        delete this.dataset.swimlaneInk;
      }
      const span = this.renderRoot.querySelector(".a2ui-text");
      if (!span) return;
      if (id.startsWith("table_heading") || /^stage_.+_heading$/.test(id)) {
        span.classList.add("nb-section");
        const variant = this.controller?.props?.variant || "body";
        if (variant === "h2" || variant === "h3") {
          const text = String(this.controller?.props?.text ?? "");
          span.classList.add(`nb-section-tone-${sectionTone(text)}`);
        }
      } else if (id === "surface_title") {
        span.classList.add("nb-title");
      }
    }
  }

  class AshA2uiButtonElement extends A2uiBasicButtonElement {
    static styles = [
      super.styles,
      lit.css`
        /* The neobrutalist button system (digest §3), layered after the
         * upstream styles so equal specificity resolves to these. */
        .a2ui-button {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          box-sizing: border-box;
          min-height: var(--a2ui-button-height, 2.5rem);
          font-size: var(--a2ui-button-font-size, 0.875rem);
          font-weight: var(--a2ui-button-font-weight, 500);
          line-height: 1.25;
          border: var(
            --a2ui-button-border,
            var(--a2ui-border-width, 2px) solid var(--a2ui-color-border, #141414)
          );
          border-radius: var(--a2ui-button-border-radius, 5px);
          box-shadow: var(--a2ui-button-box-shadow, 4px 4px 0 0 var(--a2ui-color-border, #141414));
          padding: var(--a2ui-button-padding, 0.375rem 1rem);
          margin: var(--a2ui-button-margin, 0 0.25rem 0.25rem 0);
          color: var(--a2ui-color-on-surface, inherit);
          background: var(--a2ui-button-background, var(--a2ui-color-surface, #ffffff));
          transition:
            transform 120ms var(--nb-ease-emphasized, cubic-bezier(0.2, 0, 0, 1)),
            box-shadow 120ms var(--nb-ease-emphasized, cubic-bezier(0.2, 0, 0, 1)),
            background-color 120ms ease;
        }

        /* The press, per the digest: hover/active collapse the button
         * INTO its own shadow — translate +4px/+4px and the shadow goes
         * none. No fill shift, no scale. */
        .a2ui-button:hover:not(:disabled) {
          transform: translate(4px, 4px);
          box-shadow: var(--a2ui-button-box-shadow-none, none);
          background: var(--a2ui-button-background, var(--a2ui-color-surface, #ffffff));
        }
        .a2ui-button:active:not(:disabled) {
          transform: translate(4px, 4px);
          box-shadow: none;
        }

        /* Focus: the hard 2px black ring with its white gap. */
        .a2ui-button:focus-visible {
          outline: 2px solid var(--a2ui-color-border, #141414);
          outline-offset: 2px;
        }

        /* Primary: the accent fill with BLACK ink — and the 2px border
         * RESTORED over upstream's hardcoded border:none rule (the
         * root-cause map's finding #7). */
        .a2ui-button.primary {
          border: var(
            --a2ui-button-border,
            var(--a2ui-border-width, 2px) solid var(--a2ui-color-border, #141414)
          );
          background: var(--a2ui-color-primary, #3b82f6);
          color: var(--a2ui-color-on-primary, #141414);
          box-shadow: var(--a2ui-button-box-shadow, 4px 4px 0 0 var(--a2ui-color-border, #141414));
        }
        .a2ui-button.primary:hover:not(:disabled) {
          background: var(--a2ui-color-primary, #3b82f6);
          transform: translate(4px, 4px);
          box-shadow: none;
        }

        /* Borderless stays the quiet link tier. */
        .a2ui-button.borderless {
          border: none;
          box-shadow: none;
          color: var(--a2ui-color-primary, inherit);
          text-underline-offset: 2px;
        }
        .a2ui-button.borderless:hover:not(:disabled) {
          transform: none;
          text-decoration: underline;
        }

        /* Reference links ("<value id>_link" borderless Buttons wrapping a
         * value Text, emitted with link_buttons: true; these rules follow
         * the borderless ones so they win at equal specificity) read as links, not
         * buttons: the surrounding text's font, an underline, no button
         * box. The text keeps the ink colour and the primary colour marks
         * the underline: hosts commonly use primary as a fill, and as text
         * it can fall below 4.5:1 on a light surface. The Text child takes
         * its colour from --_a2ui-text-color (upstream's button-to-text
         * channel), so it is set here too. */
        :host([data-a2ui-link]) {
          margin: 0;
          max-width: 100%;
        }
        .a2ui-button.nb-link {
          display: inline-block;
          vertical-align: baseline;
          min-height: 0;
          padding: 0;
          margin: 0;
          border: none;
          border-radius: 2px;
          box-shadow: none;
          background: none;
          font: inherit;
          line-height: inherit;
          letter-spacing: inherit;
          text-align: inherit;
          white-space: normal;
          cursor: pointer;
          color: var(--a2ui-link-color, var(--a2ui-color-on-surface, #141414));
          --_a2ui-text-color: var(--a2ui-link-color, var(--a2ui-color-on-surface, #141414));
          --_a2ui-text-margin: 0;
          text-decoration-line: var(--a2ui-link-decoration, underline);
          text-decoration-color: var(--a2ui-link-decoration-color, var(--a2ui-color-primary, currentColor));
          text-decoration-thickness: var(--a2ui-link-decoration-thickness, 1px);
          text-underline-offset: var(--a2ui-link-underline-offset, 2px);
          transition: color 120ms ease, text-decoration-thickness 120ms ease;
        }
        .a2ui-button.nb-link:hover:not(:disabled),
        .a2ui-button.nb-link:active:not(:disabled) {
          transform: none;
          box-shadow: none;
          background: none;
          color: var(--a2ui-link-hover-color, var(--a2ui-link-color, var(--a2ui-color-on-surface, #141414)));
          --_a2ui-text-color: var(
            --a2ui-link-hover-color,
            var(--a2ui-link-color, var(--a2ui-color-on-surface, #141414))
          );
          text-decoration-line: var(--a2ui-link-hover-decoration, underline);
          text-decoration-thickness: var(--a2ui-link-hover-decoration-thickness, 2px);
        }
        .a2ui-button.nb-link:focus-visible {
          outline: var(--a2ui-focus-ring-width, 2px) solid
            var(--a2ui-focus-ring-color, var(--a2ui-color-border, #141414));
          outline-offset: 2px;
        }


        /* The quiet utility tier: row actions and pagination — sm, white,
         * shadowless. Utility chrome beside the one loud primary; hover is
         * a tint, never the press (the press belongs to the buttons that
         * carry shadows). */
        .a2ui-button.nb-quiet {
          min-height: var(--a2ui-button-height-sm, 2.25rem);
          padding: var(--a2ui-button-padding-sm, 0.375rem 0.75rem);
          font-size: var(--a2ui-button-font-size-sm, 0.8125rem);
          box-shadow: none;
        }
        .a2ui-button.nb-quiet:hover:not(:disabled) {
          transform: none;
          box-shadow: none;
          background: var(--a2ui-button-quiet-hover, var(--a2ui-color-background, #d6ebfc));
        }
        .a2ui-button.nb-quiet:active:not(:disabled) {
          transform: none;
          box-shadow: none;
        }
        .a2ui-button.nb-quiet.primary {
          background: var(--a2ui-color-primary, #3b82f6);
          color: var(--a2ui-color-on-primary, #141414);
        }
        .a2ui-button.nb-quiet.primary:hover:not(:disabled) {
          background: var(--a2ui-color-primary, #3b82f6);
        }

        .a2ui-button:disabled {
          opacity: 0.5;
        }

        /* The reduced-motion kill-switch. The scoping shim rewrites these
         * selectors per instance and multiple instances' sheets reorder
         * within the host scope, so equal-specificity ordering is not a
         * reliable win — the media block carries the sanctioned
         * !important (the same kill-switch nb_motion.css applies). State
         * changes still land; only the travel drops. */
        @media (prefers-reduced-motion: reduce) {
          .a2ui-button,
          .a2ui-button:hover:not(:disabled),
          .a2ui-button:active:not(:disabled) {
            transition: none !important;
            transform: none !important;
          }
        }
      `,
    ];

    render() {
      // Upstream's render verbatim (click dispatch, disabled semantics,
      // variant classes), plus the id-keyed quiet tier class.
      const props = this.controller?.props;
      if (!props) return nothing;

      const isDisabled = props.isValid === false;
      const variant = props.variant ?? "default";
      const link = this.isReferenceLink(variant);
      this.toggleAttribute("data-a2ui-link", link);
      const classes = {
        "a2ui-button": true,
        [variant]: true,
        ["a2ui-button-" + variant]: true,
        "nb-quiet": this.isQuietUtility(),
        "nb-link": link,
      };

      return html`
        <button
          type="button"
          class=${classMapFallback(classes)}
          @click=${() => {
            if (isDisabled) return;
            props.action?.();
          }}          ?disabled=${isDisabled}
        >
          ${props.child ? html`${this.renderNode(props.child)}` : nothing}
        </button>
      `;
    }

    // A reference link: the encoder's `<value id>_link` borderless Button
    // whose child is the value Text `<value id>`.
    isReferenceLink(variant) {
      if (variant !== "borderless") return false;
      const id = componentIdOf(this);
      const child = this.controller?.props?.child;
      return id.endsWith("_link") && childRefId(child) === id.slice(0, -"_link".length);
    }

    // The utility tier, keyed on the encoder's frozen button ids: row
    // actions (invoke/prompt/confirm) and the query pager. The page's one
    // loud CTA stays the Create/Submit primary — these are the doors, not
    // the destination.
    isQuietUtility() {
      const id = componentIdOf(this);
      return (
        /(^|_)row_action_.*_button$/.test(id) ||
        id.endsWith("_prev_button") ||
        id.endsWith("_next_button") ||
        /^calendar(_.+)?_(today|all|day)_button$/.test(id)
      );
    }
  }

  if (!customElements.get(TEXT_TAG)) customElements.define(TEXT_TAG, AshA2uiTextElement);
  if (!customElements.get(BUTTON_TAG)) customElements.define(BUTTON_TAG, AshA2uiButtonElement);
}

// classMap fallback: the deps contract passes `lit: {html, css, nothing}`
// (and the hosts' lit instance exports classMap, but the merged catalog
// only receives what it is handed). Tiny local copy — the shape is three
// booleans.
function classMapFallback(classes) {
  return Object.entries(classes)
    .filter(([, on]) => !!on)
    .map(([name]) => name)
    .join(" ");
}

// --- Column override (search-picker combobox / chip group) -------------------

const SEARCH_DEBOUNCE_MS = 250;

// AshA2ui's frozen picker-composite id contract (see the extension's
// Contexts and Details topic — ids are part of the wire contract):
//
//   context picker  : Card `context_<name>` > Column `context_<name>_body`
//                     holding `_label`, `_selected_row` (`_selected` +
//                     `_clear_button`), optional `_controls` (`_search_input`
//                     + `_search_button`), and `_options` (List over
//                     /options/<name> of `_option_button` > `_option_text`).
//   searchable select: Column `form_select_<field>` holding `_label`,
//                     `_selected`, `_controls`, `_options` (same shapes,
//                     no clear button).
//
// detectPicker inspects the live component tree and only enhances when
// every structural piece it needs is present and correctly shaped, so an
// encoder from a different version (or a hand-built surface reusing the id
// prefix) degrades to the plain column rendering.
//
// Returns the picker descriptor on success, `{mismatch: [reasons]}` when
// the id matches the frozen contract but a structural piece failed
// verification (the caller warns — a contract-id composite that silently
// degrades renders as the dead-end label + search-input composite and
// reads as a finished feature; that silence cost a full integration lap
// once), or null when the id is not a picker id at all (the common case).
function detectPicker(surface, id) {
  const contextMatch = /^context_(.+)_body$/.exec(id);
  const selectMatch = /^form_select_(.+)$/.exec(id);
  if (!contextMatch && !selectMatch) return null;

  const base = contextMatch ? `context_${contextMatch[1]}` : id;
  const get = (suffix) => surface.componentsModel.get(`${base}${suffix}`);

  const missing = [];
  const options = get("_options");
  const optionButton = get("_option_button");
  const selected = get("_selected");
  const label = get("_label");
  if (!options) missing.push("no _options component");
  if (!optionButton) missing.push("no _option_button component");
  if (!selected) missing.push("no _selected component");
  if (!label) missing.push("no _label component");
  if (missing.length === 0) {
    if (options.type !== "List") missing.push("_options is not a List");
    if (typeof options.properties?.children?.path !== "string")
      missing.push("_options has no templated children path");
    if (typeof optionButton.properties?.action?.event?.name !== "string")
      missing.push("_option_button has no action event");
    if (typeof selected.properties?.text?.path !== "string")
      missing.push("_selected has no bound text path");
    if (typeof label.properties?.text !== "string")
      missing.push("_label has no literal text");
  }
  if (missing.length > 0) return {mismatch: missing};

  const searchInput = get("_search_input");
  const searchButton = get("_search_button");
  const searchPath = searchInput?.properties?.value?.path;
  const searchEvent = searchButton?.properties?.action?.event;
  const searchable =
    typeof searchPath === "string" && typeof searchEvent?.name === "string";

  const clearEvent = get("_clear_button")?.properties?.action?.event;

  return {
    base,
    // The v1.0 encoder emits heading Texts as Markdown ("### User"); the
    // picker renders its label as plain inline text, so strip the marker.
    label: label.properties.text.replace(/^#{1,6}\s+/, ""),
    labelPath: selected.properties.text.path,
    // The picker's selected value lives next to its label in the reserved
    // state shape ({value, label, search}).
    valuePath: selected.properties.text.path.replace(/\/label$/, "/value"),
    optionsPath: options.properties.children.path,
    optionEvent: optionButton.properties.action.event,
    optionButtonId: `${base}_option_button`,
    searchable,
    searchPath: searchable ? searchPath : null,
    searchEvent: searchable ? searchEvent : null,
    searchButtonId: searchable ? `${base}_search_button` : null,
    clearEvent: clearEvent && typeof clearEvent.name === "string" ? clearEvent : null,
    clearButtonId: `${base}_clear_button`,
  };
}

// A child reference's component id: static children are plain id strings,
// template children `{id, basePath}` objects.
function childRefId(child) {
  return typeof child === "object" && child !== null ? child.id : String(child);
}

// --- Board swimlanes ----------------------------------------------------------
//
// A swimlaned board (`swimlanes_by`) splits into rows across its stage
// columns. The basic catalog has no colour props, so a swimlane's tone is
// data: `/_swimlane_tone_<swimlane>` holds one of the badge_tones vocabulary
// (neutral/info/success/warning/danger/accent), read here by the encoder's
// frozen `swimlane_<swimlane>` id. Each tone maps onto a pair of tokens,
// `--a2ui-swimlane-<tone>-background` and `--a2ui-swimlane-<tone>-color`
// (the ink of the headings and totals sitting on the band). The fallbacks
// below are the ash_a2ui_theme.css defaults: a 200-weight tint with
// 900-weight ink in light, the reverse in dark — every pair at least
// 6.9:1, above WCAG AA (4.5:1) for body text.
const SWIMLANE_TONE_FALLBACKS = {
  neutral: ["light-dark(#e2e8f0, #334155)", "light-dark(#0f172a, #f1f5f9)"],
  info: ["light-dark(#bfdbfe, #1e3a8a)", "light-dark(#1e3a8a, #dbeafe)"],
  success: ["light-dark(#bbf7d0, #14532d)", "light-dark(#14532d, #dcfce7)"],
  warning: ["light-dark(#fde68a, #713f12)", "light-dark(#713f12, #fef3c7)"],
  danger: ["light-dark(#fecaca, #7f1d1d)", "light-dark(#7f1d1d, #fee2e2)"],
  accent: ["light-dark(#ddd6fe, #4c1d95)", "light-dark(#4c1d95, #ede9fe)"],
};

function swimlaneTone(tone) {
  return Object.hasOwn(SWIMLANE_TONE_FALLBACKS, tone) ? tone : "neutral";
}

// Whether a Text sits directly on a swimlane's band: some ancestor (across
// shadow roots) is part of a `swimlane_<swimlane>` row, and no Card or
// Button lies in between (those paint their own surface). That covers the
// swimlane heading and total, each cell's total, empty-state text and
// pagination text, and nothing outside a swimlaned board. Matched by the
// encoder's frozen ids, so it holds before the band has painted.
function onSwimlaneBand(element) {
  let node = element;
  while (node) {
    node = node.parentElement ?? node.getRootNode?.()?.host ?? null;
    const model = node?.context?.componentModel;
    if (!model) continue;
    if (model.type === "Card" || model.type === "Button") return false;
    if (typeof model.id === "string" && model.id.startsWith("swimlane_")) return true;
  }
  return false;
}

// Defines <ash-a2ui-column> once (idempotent across LiveView remounts and
// hot reloads).
function defineColumnElement({A2uiLitElement, A2uiController, ColumnApi, lit}) {
  if (customElements.get(COLUMN_TAG)) return;

  const {html, css, nothing} = lit;

  const JUSTIFY_MAP = {
    start: "flex-start",
    center: "center",
    end: "flex-end",
    spaceBetween: "space-between",
    spaceAround: "space-around",
    spaceEvenly: "space-evenly",
    stretch: "stretch",
  };

  const ALIGN_MAP = {
    start: "flex-start",
    center: "center",
    end: "flex-end",
    stretch: "stretch",
  };

  class AshA2uiColumnElement extends A2uiLitElement {
    /**
     * Plain columns use the basic catalog's variable (`--a2ui-column-gap`).
     * Enhanced pickers add (all optional):
     *
     * - `--a2ui-combobox-max-height`: overlay max height (default 18rem).
     * - `--a2ui-combobox-z-index`: overlay stacking (default 30).
     * - `--a2ui-combobox-option-padding`: option row padding.
     * - `--a2ui-chip-background` / `--a2ui-chip-color`: chip at rest
     *   (default secondary tokens).
     * - `--a2ui-chip-selected-background` / `--a2ui-chip-selected-color`:
     *   selected chip (default primary tokens).
     * - `--a2ui-chip-border-radius`: chip rounding (default 999px pill).
     *
     * Shared input/surface/border/label tokens come from the same
     * `--a2ui-*` set as the rest of the catalog.
     *
     * Boards (`board_<template>`, whose `board_<template>_lanes` Row holds
     * the weighted lane Columns) scroll their lanes horizontally inside
     * the board instead of the page:
     *
     * - `--a2ui-board-lane-min-width`: the narrowest a lane gets before
     *   the lanes scroll (default 18rem).
     * - `--a2ui-board-lane-max-width`: the widest a lane gets (default
     *   none — lanes share the board's width).
     *
     * Swimlaned boards (`board_<template>_lanes` is a Column of the
     * `board_<template>_stages` Row and one `swimlane_<swimlane>` Column per
     * swimlane) scroll stages and swimlanes together, and paint each
     * swimlane from its tone (`/_swimlane_tone_<swimlane>`):
     *
     * - `--a2ui-swimlane-<tone>-background` / `--a2ui-swimlane-<tone>-color`:
     *   a tone's band and its ink (tones: neutral, info, success, warning,
     *   danger, accent; defaults in ash_a2ui_theme.css).
     * - `--a2ui-swimlane-padding`: the band's inner padding (default
     *   0.75rem); the stage header row is inset to match, so every cell
     *   stays under its stage.
     * - `--a2ui-swimlane-border-radius`: the band's corners (default
     *   `--a2ui-border-radius`).
     */
    static styles = css`
      :host {
        display: flex;
        flex-direction: column;
        gap: var(--a2ui-column-gap, var(--a2ui-spacing-m));
        min-width: 0;
      }
      .board-lanes {
        overflow-x: auto;
        min-width: 0;
        max-width: 100%;
        padding-bottom: var(--a2ui-spacing-s, 0.5rem);
      }
      .board-stages {
        padding-inline: calc(
          var(--a2ui-swimlane-padding, 0.75rem) + var(--a2ui-border-width, 2px)
        );
      }

      .picker {
        display: flex;
        flex-direction: column;
        gap: var(--a2ui-spacing-s, 0.5rem);
      }
      .picker-label {
        font-size: var(--a2ui-label-font-size, var(--a2ui-font-size-s));
        font-weight: var(--a2ui-label-font-weight, bold);
      }
      .combobox-anchor {
        position: relative;
        max-width: 28rem;
      }
      .combobox-input {
        width: 100%;
        box-sizing: border-box;
        background-color: var(--a2ui-color-input, #fff);
        color: var(--a2ui-color-on-input, #333);
        border: var(--a2ui-textfield-border, var(--a2ui-border, 1px solid #ccc));
        border-radius: var(--a2ui-textfield-border-radius, var(--a2ui-spacing-m));
        padding: var(--a2ui-textfield-padding, var(--a2ui-spacing-m));
        font-family: inherit;
        font-size: inherit;
      }
      .combobox-input:focus {
        outline: none;
        border-color: var(
          --a2ui-textfield-color-border-focus,
          var(--a2ui-color-primary, #17e)
        );
      }
      .combobox-popup {
        position: absolute;
        top: calc(100% + 0.25rem);
        left: 0;
        right: 0;
        z-index: var(--a2ui-combobox-z-index, 30);
        background: var(--a2ui-color-surface, #fff);
        color: var(--a2ui-color-on-surface, #333);
        border: var(--a2ui-border, 1px solid var(--a2ui-color-border, #ccc));
        border-radius: var(--a2ui-border-radius, 0.5rem);
        box-shadow: var(
          --a2ui-combobox-box-shadow,
          var(--a2ui-card-box-shadow, 0 4px 12px rgb(0 0 0 / 0.15))
        );
        max-height: var(--a2ui-combobox-max-height, 18rem);
        overflow-y: auto;
        margin: 0;
        padding: var(--a2ui-spacing-xs, 0.25rem);
        list-style: none;
      }
      .combobox-option {
        padding: var(
          --a2ui-combobox-option-padding,
          var(--a2ui-spacing-s, 0.375rem) var(--a2ui-spacing-m, 0.5rem)
        );
        border-radius: calc(var(--a2ui-border-radius, 0.5rem) - 0.125rem);
        cursor: pointer;
      }
      .combobox-option.active,
      .combobox-option:hover {
        background: var(--a2ui-color-secondary, #eee);
        color: var(--a2ui-color-on-secondary, inherit);
      }
      .combobox-hint {
        padding: var(--a2ui-spacing-s, 0.375rem) var(--a2ui-spacing-m, 0.5rem);
        opacity: 0.65;
        font-size: var(--a2ui-font-size-s, 0.875rem);
      }
      .chips {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--a2ui-spacing-s, 0.5rem);
      }
      .chip {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        background: var(--a2ui-chip-background, var(--a2ui-color-secondary, #eee));
        color: var(--a2ui-chip-color, var(--a2ui-color-on-secondary, inherit));
        border: var(--a2ui-border-width, 1px) solid transparent;
        border-radius: var(--a2ui-chip-border-radius, 999px);
        padding: 0.25rem 0.75rem;
        font: inherit;
        font-size: var(--a2ui-font-size-s, 0.875rem);
        cursor: pointer;
      }
      .chip:hover {
        border-color: var(--a2ui-color-border, #ccc);
      }
      .chip.selected {
        background: var(--a2ui-chip-selected-background, var(--a2ui-color-primary, #17e));
        color: var(--a2ui-chip-selected-color, var(--a2ui-color-on-primary, #fff));
      }
      .chip .chip-x {
        font-weight: bold;
        opacity: 0.75;
      }
      .chip-hint {
        opacity: 0.65;
        font-size: var(--a2ui-font-size-s, 0.875rem);
      }
    `;

    constructor() {
      super();
      this.picker = null;
      this.open = false;
      this.activeIndex = -1;
      this.debounceTimer = null;
      this.dataSubscriptions = [];
    }

    createController() {
      return new A2uiController(this, ColumnApi);
    }

    get surface() {
      return this.context?.dataContext?.surface;
    }

    willUpdate(changedProperties) {
      super.willUpdate(changedProperties);

      if (changedProperties.has("context") && this.context) {
        this.teardownPicker();
        try {
          const detected = detectPicker(this.surface, this.context.componentModel.id);
          if (detected && detected.mismatch) {
            // The id promised a picker composite but the tree did not
            // verify. Rendering continues as the plain composite — the
            // wire stays renderable — but the degradation is announced:
            // silently, it renders a dead-end label + search input that
            // reads as a finished feature (the trap behind the intake
            // picker misdiagnosis).
            console.warn(
              `ash_a2ui: ${this.context.componentModel.id} matches the picker id contract ` +
                `but did not verify (${detected.mismatch.join("; ")}); ` +
                `rendering the plain composite.`,
            );
            this.picker = null;
          } else {
            this.picker = detected;
          }
        } catch (error) {
          console.warn(
            `ash_a2ui: picker detection threw for ${this.context.componentModel?.id}: ${error}`,
          );
          this.picker = null;
        }
        if (this.picker) this.subscribePickerData();
      }

      const props = this.controller?.props;
      if (props && props.weight !== undefined) {
        this.style.flex = String(props.weight);
      } else {
        this.style.removeProperty("flex");
      }
    }

    updated(changedProperties) {
      super.updated(changedProperties);
      if (this.picker) return;
      const props = this.controller?.props;
      if (props) {
        this.style.justifyContent = JUSTIFY_MAP[props.justify ?? ""] ?? "flex-start";
        this.style.alignItems = ALIGN_MAP[props.align ?? ""] ?? "stretch";
      }
      // Board lanes keep a minimum (and optional maximum) width, so a board
      // with many lanes scrolls inside its frame instead of crushing them.
      // Set on the lane itself: depending on the renderer version the lanes
      // Row renders its children in light DOM or in its own shadow root.
      if (this.boardLane()) {
        this.style.minWidth = "var(--a2ui-board-lane-min-width, 18rem)";
        this.style.maxWidth = "var(--a2ui-board-lane-max-width, none)";
      } else if (this.swimlaneGrid()) {
        // The stages and swimlanes scroll together: the grid is as wide as
        // its widest row (the lanes at their minimum width), so a band's
        // background spans every cell instead of stopping at the frame.
        this.style.minWidth = "min-content";
        this.style.removeProperty("max-width");
      } else {
        this.style.removeProperty("min-width");
        this.style.removeProperty("max-width");
      }
      this.paintSwimlane();
    }

    // A board lane: the encoder's frozen `lane_<lane>` id with its
    // `lane_<lane>_header` child, inside a board's lanes Row — or a
    // swimlaned board's stage column (`stage_<lane>` with
    // `stage_<lane>_header`), which keeps the same width as the cells
    // under it.
    boardLane() {
      const id = this.context?.componentModel?.id;
      if (typeof id !== "string" || !/^(lane|stage)_.+/.test(id)) return false;
      const children = this.controller?.props?.children;
      return Array.isArray(children) && children.some((child) => childRefId(child) === `${id}_header`);
    }

    // A swimlaned board's lanes Column: `board_<template>_lanes` holding
    // its `board_<template>_stages` Row.
    swimlaneGrid() {
      return this.swimlaneStagesId() !== null;
    }

    swimlaneStagesId() {
      const id = this.context?.componentModel?.id;
      if (typeof id !== "string") return null;
      const match = /^(board_.+)_lanes$/.exec(id);
      if (!match) return null;
      const stagesId = `${match[1]}_stages`;
      const children = this.controller?.props?.children;
      return Array.isArray(children) && children.some((child) => childRefId(child) === stagesId)
        ? stagesId
        : null;
    }

    // A swimlane row: the encoder's frozen `swimlane_<swimlane>` id with its
    // `_header` and `_cells` children. Returns the swimlane's runtime name.
    swimlaneName() {
      const id = this.context?.componentModel?.id;
      if (typeof id !== "string" || !/^swimlane_.+/.test(id)) return null;
      const children = (this.controller?.props?.children ?? []).map(childRefId);
      if (!children.includes(`${id}_header`) || !children.includes(`${id}_cells`)) return null;
      return id.slice("swimlane_".length);
    }

    // Paints a swimlane row from its tone: the band background, a border in
    // the board's line colour, and `--a2ui-swimlane-ink` for the texts on
    // the band (the merged Text override reads it). The tone is data the
    // server writes once with the surface; the subscription re-paints when
    // it arrives after the components (v0.9.1 sends the data model last).
    paintSwimlane() {
      const name = this.swimlaneName();
      if (name === null) {
        if (this.dataset.swimlaneTone) {
          delete this.dataset.swimlaneTone;
          for (const property of [
            "background",
            "border",
            "border-radius",
            "padding",
            "--a2ui-swimlane-ink",
          ]) {
            this.style.removeProperty(property);
          }
        }
        return;
      }
      const path = `/_swimlane_tone_${name}`;
      let tone = "neutral";
      try {
        const {dataModel} = this.surface;
        if (!this.swimlaneSubscription) {
          this.swimlaneSubscription = dataModel.subscribe(path, () => this.requestUpdate());
        }
        tone = swimlaneTone(String(dataModel.get(path) ?? ""));
      } catch {
        // No surface yet: the next update paints.
      }
      const [background, ink] = SWIMLANE_TONE_FALLBACKS[tone];
      this.dataset.swimlaneTone = tone;
      this.style.background = `var(--a2ui-swimlane-${tone}-background, ${background})`;
      this.style.setProperty("--a2ui-swimlane-ink", `var(--a2ui-swimlane-${tone}-color, ${ink})`);
      this.style.color = "var(--a2ui-swimlane-ink)";
      this.style.border =
        "var(--a2ui-border-width, 2px) solid var(--a2ui-color-border, currentColor)";
      this.style.borderRadius =
        "var(--a2ui-swimlane-border-radius, var(--a2ui-border-radius, 5px))";
      this.style.padding = "var(--a2ui-swimlane-padding, 0.75rem)";
    }

    disconnectedCallback() {
      super.disconnectedCallback();
      this.teardownPicker();
      this.swimlaneSubscription?.unsubscribe();
      this.swimlaneSubscription = null;
    }

    teardownPicker() {
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer);
        this.debounceTimer = null;
      }
      for (const sub of this.dataSubscriptions) sub.unsubscribe();
      this.dataSubscriptions = [];
      this.picker = null;
      this.open = false;
      this.activeIndex = -1;
    }

    // The picker rendering reads live values straight from the data model;
    // these subscriptions only exist to re-render when the server rewrites
    // the selection, the options page, or the search text.
    subscribePickerData() {
      const {dataModel} = this.surface;
      const paths = [this.picker.labelPath, this.picker.optionsPath];
      if (this.picker.searchPath) paths.push(this.picker.searchPath);
      for (const path of paths) {
        this.dataSubscriptions.push(dataModel.subscribe(path, () => this.requestUpdate()));
      }
    }

    dispatch(event, sourceComponentId, basePath = "/") {
      const {dataModel} = this.surface;
      const context = resolveEventContext(event.context || {}, dataModel, basePath);
      this.surface.dispatchAction({event: {name: event.name, context}}, sourceComponentId);
    }

    readPickerState() {
      const {dataModel} = this.surface;
      const rawOptions = dataModel.get(this.picker.optionsPath);
      return {
        selectedLabel: String(dataModel.get(this.picker.labelPath) ?? ""),
        selectedValue: String(dataModel.get(this.picker.valuePath) ?? ""),
        search: this.picker.searchPath
          ? String(dataModel.get(this.picker.searchPath) ?? "")
          : "",
        options: Array.isArray(rawOptions) ? rawOptions : [],
      };
    }

    render() {
      const props = this.controller?.props;
      if (!props) return nothing;

      if (this.picker && this.surface) {
        const state = this.readPickerState();
        return this.picker.searchable
          ? this.renderCombobox(state)
          : this.renderChipGroup(state);
      }

      const children = Array.isArray(props.children) ? props.children : [];
      const lanesId = this.boardLanesId(children);
      const stagesId = this.swimlaneStagesId();
      return html`${children.map((child) => {
        const childId = childRefId(child);
        if (lanesId !== null && childId === lanesId) {
          return html`<div class="board-lanes" part="board-lanes">${this.renderNode(child)}</div>`;
        }
        if (stagesId !== null && childId === stagesId) {
          return html`<div class="board-stages" part="board-stages">${this.renderNode(child)}</div>`;
        }
        return html`${this.renderNode(child)}`;
      })}`;
    }

    // A board container (the encoder's frozen `board_<template>` id with its
    // `board_<template>_lanes` child — a Row of lanes, or on a swimlaned
    // board the Column of stages and swimlanes): the lanes child renders
    // inside a horizontal scroll frame. Anything else returns null (plain
    // column).
    boardLanesId(children) {
      const id = this.context?.componentModel?.id;
      if (typeof id !== "string" || !/^board_.+/.test(id)) return null;
      const lanesId = `${id}_lanes`;
      if (!children.some((child) => childRefId(child) === lanesId)) return null;
      try {
        const type = this.surface?.componentsModel?.get(lanesId)?.type;
        return type === "Row" || type === "Column" ? lanesId : null;
      } catch {
        return null;
      }
    }

    // --- typeahead combobox ---

    renderCombobox(state) {
      const listboxId = `${this.picker.base}_listbox`;

      // A selection with a clear action collapses to just the chip; without
      // one (searchable relationship selects have no clear button) the
      // input stays visible so a new search can replace the selection.
      const collapsed = state.selectedLabel && this.picker.clearEvent;

      const input = html`
        <div class="combobox-anchor">
          <input
            class="combobox-input"
            type="text"
            role="combobox"
            aria-expanded=${this.open ? "true" : "false"}
            aria-controls=${listboxId}
            aria-autocomplete="list"
            aria-activedescendant=${this.activeIndex >= 0
              ? `${listboxId}_opt_${this.activeIndex}`
              : ""}
            placeholder="Type to search…"
            autocomplete="off"
            .value=${state.search}
            @input=${(e) => this.onSearchInput(e.target.value)}
            @focus=${() => this.setOpen(true)}
            @blur=${() => this.setOpen(false)}
            @keydown=${(e) => this.onSearchKeydown(e, state)}
          />
          ${this.open ? this.renderPopup(state, listboxId) : nothing}
        </div>
      `;

      return html`
        <div class="picker">
          <span class="picker-label">${this.picker.label}</span>
          ${state.selectedLabel ? this.renderSelectionChip(state) : nothing}
          ${collapsed ? nothing : input}
        </div>
      `;
    }

    renderSelectionChip(state) {
      const clearable = !!this.picker.clearEvent;
      return html`
        <div class="chips">
          <button
            type="button"
            class="chip selected"
            title=${clearable ? "Clear selection" : "Current selection"}
            @click=${() => this.clearSelection()}
          >
            ${state.selectedLabel}
            ${clearable ? html`<span class="chip-x" aria-hidden="true">×</span>` : nothing}
          </button>
        </div>
      `;
    }

    // The popup never lists options before the user has typed: the server
    // pre-loads a default option page, but surfacing it unprompted is
    // exactly the flat-list UX this component replaces.
    renderPopup(state, listboxId) {
      // Keep focus in the input when the popup chrome (scrollbar, padding)
      // is clicked, so blur doesn't close the popup mid-interaction.
      const keepFocus = (e) => e.preventDefault();

      if (state.search.trim() === "") {
        return html`<ul id=${listboxId} role="listbox" class="combobox-popup" @mousedown=${keepFocus}>
          <li class="combobox-hint">Type to search…</li>
        </ul>`;
      }

      if (state.options.length === 0) {
        return html`<ul id=${listboxId} role="listbox" class="combobox-popup" @mousedown=${keepFocus}>
          <li class="combobox-hint">No matches</li>
        </ul>`;
      }

      return html`
        <ul id=${listboxId} role="listbox" class="combobox-popup" @mousedown=${keepFocus}>
          ${state.options.map(
            (option, index) => html`
              <li
                id="${listboxId}_opt_${index}"
                class="combobox-option ${index === this.activeIndex ? "active" : ""}"
                role="option"
                aria-selected=${index === this.activeIndex ? "true" : "false"}
                @mousedown=${(e) => {
                  e.preventDefault();
                  this.selectOption(index);
                }}
                @mousemove=${() => this.setActiveIndex(index)}
              >
                ${String(option?.label ?? "")}
              </li>
            `,
          )}
        </ul>
      `;
    }

    onSearchInput(value) {
      this.surface.dataModel.set(this.picker.searchPath, value);
      this.setOpen(true);
      this.setActiveIndex(-1);
      if (this.debounceTimer) clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this.debounceTimer = null;
        this.dispatchSearch();
      }, SEARCH_DEBOUNCE_MS);
      this.requestUpdate();
    }

    dispatchSearch() {
      this.dispatch(this.picker.searchEvent, this.picker.searchButtonId);
    }

    onSearchKeydown(event, state) {
      const optionCount = state.search.trim() === "" ? 0 : state.options.length;

      switch (event.key) {
        case "ArrowDown":
          event.preventDefault();
          this.setOpen(true);
          if (optionCount > 0) this.setActiveIndex((this.activeIndex + 1) % optionCount);
          break;
        case "ArrowUp":
          event.preventDefault();
          if (optionCount > 0) {
            this.setActiveIndex((this.activeIndex - 1 + optionCount) % optionCount);
          }
          break;
        case "Enter":
          event.preventDefault();
          if (this.debounceTimer) {
            // A pending debounce means the visible options are stale for
            // the typed text — flush the search instead of selecting.
            clearTimeout(this.debounceTimer);
            this.debounceTimer = null;
            this.dispatchSearch();
          } else if (this.open && this.activeIndex >= 0 && this.activeIndex < optionCount) {
            this.selectOption(this.activeIndex);
          }
          break;
        case "Escape":
          this.setOpen(false);
          break;
        default:
          break;
      }
    }

    selectOption(index) {
      this.dispatch(
        this.picker.optionEvent,
        this.picker.optionButtonId,
        `${this.picker.optionsPath}/${index}`,
      );
      this.setOpen(false);
      this.setActiveIndex(-1);
    }

    clearSelection() {
      if (!this.picker.clearEvent) return;
      this.dispatch(this.picker.clearEvent, this.picker.clearButtonId);
      this.setOpen(false);
      this.setActiveIndex(-1);
    }

    setOpen(open) {
      if (this.open !== open) {
        this.open = open;
        this.requestUpdate();
      }
    }

    setActiveIndex(index) {
      if (this.activeIndex !== index) {
        this.activeIndex = index;
        this.requestUpdate();
      }
    }

    // --- non-searchable context picker: chip group ---

    renderChipGroup(state) {
      let body;
      if (state.options.length === 0 && !state.selectedLabel) {
        body = html`<span class="chip-hint">No options yet — make a selection above.</span>`;
      } else {
        body = html`
          <div class="chips" role="group" aria-label=${this.picker.label}>
            ${state.options.map((option, index) => {
              const value = String(option?.value ?? "");
              const isSelected = value !== "" && value === state.selectedValue;
              return html`
                <button
                  type="button"
                  class="chip ${isSelected ? "selected" : ""}"
                  aria-pressed=${isSelected ? "true" : "false"}
                  @click=${() => (isSelected ? this.clearSelection() : this.selectOption(index))}
                >
                  ${String(option?.label ?? "")}
                  ${isSelected && this.picker.clearEvent
                    ? html`<span class="chip-x" aria-hidden="true">×</span>`
                    : nothing}
                </button>
              `;
            })}
          </div>
        `;
      }

      return html`
        <div class="picker">
          <span class="picker-label">${this.picker.label}</span>
          ${body}
        </div>
      `;
    }
  }

  customElements.define(COLUMN_TAG, AshA2uiColumnElement);
}

export default createAshA2uiCatalog;
