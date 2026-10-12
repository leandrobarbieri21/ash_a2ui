# Admin catalog v1 — component contract

> **Status: contract for A2UI-101B.** Written before implementation. Both the
> Elixir encoder lane and the Lit renderer lane implement against this file;
> changes here require changing both. Criterion ids live in
> `.sdlc/acceptance/A2UI-101B.yaml`.

## Identity & configuration

- Catalog id: `https://ash-a2ui.dev/catalogs/admin/v1`
- Selection: `config :ash_a2ui, :catalog, :basic | :admin_v1` (default `:basic`).
  App-wide only for this iteration — no per-surface DSL option yet (negotiation
  arrives with the host integration).
- The admin catalog **extends the basic catalog**: basic components (inputs,
  buttons, pickers) remain available inside admin surfaces. Admin adds semantic
  components; it does not remove primitives.

### Precedence rules (deterministic, tested)

| `experience_version` | `:catalog` | Effective emission |
|---|---|---|
| 1 (default) | `:basic` | basic v1 — byte-identical to before A2UI-101 |
| 1 | `:admin_v1` | **basic v1** (admin requires v2; config is ignored, not an error) |
| 2 | `:basic` | basic v2 — byte-identical to A2UI-101 output |
| 2 | `:admin_v1` | admin v1 (this catalog) |

### Feature fallback

The admin encoder upgrades the **core table + form + pagination + status**
subtree to semantic components. Surfaces using advanced features — `sections`,
`reports`, `export`, `editable`, `nested_form` — emit those parts with
**basic v2 composition** (byte-equal to `:basic` output for those subtrees).
The whole surface never regresses below v2; only the unsupported subtree stays
basic-composed. Context pickers and query controls (search/filters/apply)
always remain basic components inside `EntityPage`.

## Components

Property values are literals or data-model path bindings using the same
`{"path": ...}` template-ref mechanism the basic encoders already emit.

### 1. `EntityPage` — page shell
- Props: `title` (string|binding), `description` (string|binding, optional)
- Children: page body (pickers, query controls, DataGrid, RecordPanel, StatusBanner)
- Events: none

### 2. `DataGrid` — collection
- Props:
  - `columns`: array of `{label: string, path: string}` (one per visible field, derived from the surface's field set / row layout, in order)
  - `rows`: binding to the table's records list path
  - `rowId`: data path for row identity (`"id"`)
  - `label`: accessible collection name (e.g. `"Appointments"`)
  - `rowActions`: array of action envelopes reusing the existing button
    context shape — `{label, action, context: %{...path refs...}, destructive?: boolean}`.
    View is always present; Edit only when the view has an `update_action`;
    declared `row_actions` map to their existing `invoke` envelopes and are
    `destructive: true` when the action is a destroy.
- Children: at most one `EmptyState`, at most one `Pagination`
- Events: none of its own (row actions dispatch via their envelopes)

### 3. `EmptyState` — zero results
- Props: `message` (string|binding — the "No X records yet." text)
- Visibility is the DataGrid's concern: render only when the bound rows list
  is empty. No sentinel prop.
- Children: optional hint/action button
- Events: none

### 4. `Pagination` — conditional navigation
- Props (plain values/bindings — **no sentinel lists**):
  - `page`, `pageSize` (integers, bound to query state)
  - `total` (integer|nil, bound)
  - `hasNext` (boolean, bound)
  - `visible`, `previousVisible`, `nextVisible` (booleans, bound)
  - `rangeText` (string, bound — `"1–5 of 42"` / `"Showing 1–5"`)
  - `previousAction`, `nextAction` (action envelopes emitted by the encoder —
    the exact `query` envelopes with `pageDelta` -1/+1; the renderer dispatches
    them verbatim and derives a fallback from the `page` binding if absent)
- Events: carried by the envelope props above (unchanged handler contract)

### 5. `RecordPanel` — explicit task panel
- Props: `mode` (binding `/ui/panel/mode`), `title` (binding `/ui/panel/title`), `recordId` (binding)
- Children: view mode → `FieldDisplay` per field; create/edit → `FormSection` + `ActionBar`
- Hidden while mode is nil (renderer concern; `/ui/panel/mode` nil = closed)
- Events: none of its own

### 6. `FieldDisplay` — read-only value
- Props: `label` (string), `value` (binding), `format` (optional: `"text" | "datetime" | "boolean" | "number"`)
- View semantics, never a disabled input
- Events: none

### 7. `FormSection` — labeled field grouping
- Props: `title` (string|binding, optional), `columns` (integer, default 1)
- Children: **basic-catalog input components** (`text_field`, `check_box`,
  `choice_picker`, `date_time_input`) with the exact per-field bindings and
  error associations the current form emission produces
- Events: none of its own

### 8. `ActionBar` — action hierarchy
- Props: `primaryLabel` (binding `/ui/panel/primary_label` — empty = hidden),
  `busy` (binding, reserved — false for now), `destructive` (boolean, default false),
  `action` (the primary's `submit_form` envelope emitted by the encoder; the
  renderer dispatches it verbatim and reconstructs the frozen context as
  fallback)
- Children: secondary buttons (Cancel → existing `cancel_record_task` envelope)
- Events: carried by the `action` envelope prop

### 9. `StatusBanner` — typed feedback
- Props: `kind` (binding `/ui/feedback/kind`), `message` (binding `/ui/feedback/message`)
- kind nil → renders nothing (renderer concern)
- A11y (renderer): success → `role="status"`, error → `role="alert"`

### 10. `ConfirmDialog` — destructive confirmation
- Props: `title`, `body`, `confirmLabel`, `destructive` (boolean, default true)
- Declared in the catalog vocabulary; **rendered by the DataGrid renderer**
  when a row action envelope carries `destructive: true` — confirming
  dispatches the original envelope unchanged. The server never sees a new
  action name from this component.
- Events: confirm/cancel handled client-side before dispatch

## Data model additions (admin only)

Alongside the v2 sentinels (which remain for basic compat), each `/query`
state under admin gains plain booleans `paginationVisible`, `previousVisible`,
`nextVisible` derived from `AshA2ui.Experience.pagination_state/2`. Everything
else reuses the A2UI-101 `/ui` state verbatim.

## Encoder mapping (v2 + admin_v1)

`build_surface` root becomes `EntityPage {title: resource label}` with children:
1. context pickers (basic components, unchanged order)
2. query controls (basic: search/filters/apply, unchanged)
3. one `DataGrid` per table — columns from the visible field set;
   `rowActions` per the rules above; children `EmptyState` + `Pagination`
4. `RecordPanel` per the form-capable table (mode-bound children as above)
5. `StatusBanner`

The pagination row, form slot composition, select/view/edit button
primitives, and status_text of the basic-v2 emission are **replaced** by the
semantic components above — no dual emission.

## v1.0 upgrade path

`AshA2ui.Encoder.V1_0` rewrites basic component kinds and collapses the
`/ui` status trio. Custom kinds (`entityPage`, `dataGrid`, ...) and their
bindings pass through untouched. `/ui/response` collapse keeps the v2/AC-5
behavior from A2UI-101.

## JS registration expectations (renderer lane)

`priv/js/ash_admin_catalog.js` exports `createAshAdminCatalog(deps)`,
mirroring the `createAshA2ui_catalog` pattern (`priv/js/ash_a2ui_catalog.js`):
same-Lit-instance discipline, registration under the admin catalog id so a
surface declaring `catalogId: https://ash-a2ui.dev/catalogs/admin/v1`
resolves its components. Study `@a2ui/lit` in the host
(`~/vendorpm/ash_enterprise/assets/node_modules/@a2ui/lit/`, READ-ONLY) for
the registration surface. No new build tooling in this library — plain ES
modules consumed by the host's esbuild, exactly like the existing JS.

### Renderer decisions (as implemented)

- Custom catalog ids are first-class: the renderer resolves
  `catalogs.find(c => c.id === catalogId)` per surface, so the factory
  returns a full `Catalog` under the admin id (basic components included
  alongside the ten semantic kinds) and the host registers it as a sibling
  of the basic catalog.
- The core `@a2ui` inputs do not wire `aria-invalid`/`aria-describedby`, so
  the admin catalog ships a11y-hardened **overrides of the four basic input
  kinds** (TextField, CheckBox, ChoicePicker, DateTimeInput) — real
  `<label for>`, adjacent errors, aria wiring. Overrides apply only to
  admin-catalog surfaces.
- `ConfirmDialog` is mounted imperatively by the DataGrid for destructive
  row actions (dynamic tag names in Lit templates would require a dep
  outside the factory's contract); confirm dispatches the original row
  envelope unchanged.

### Renderer quality contract (non-negotiable)

- Design tokens as CSS custom properties (spacing scale, typography, color
  incl. success/warning/error/destructive, elevation, focus ring) with sane
  defaults; hosts theme by overriding. No daisyUI/tailwind dependency.
- DataGrid responsive: table ≥ breakpoint, cards below.
- Accessibility: persistent visible labels; required state via text +
  semantics; errors adjacent with `aria-describedby`; `aria-invalid` on
  invalid fields; `role="status"`/`role="alert"` banners; pagination labels
  the collection + `aria-current`; RecordPanel/ConfirmDialog move focus in
  and restore on close; icon-only buttons carry accessible names; view mode
  uses text semantics, never disabled inputs; `prefers-reduced-motion`
  respected (no animated travel).

## Addendum (2026-10-12): catalog 1.1 — additive

`priv/a2ui/admin_v1/catalog.json` gains `"version": "1.1.0"`; the catalog id
is unchanged (every addition is optional, renderers reading only the 1.0
props are unaffected).

- `dataGrid.columns[]` optional hints: `format` (`text|datetime|boolean|number`),
  `align` (`start|center|end`; numbers `end`), `mono` (identifier columns),
  `badge` (`{path: "_badge_<field>", tonePath?: "_badge_tone_<field>"}` — the
  row_layout badge as a toned pill; this restores `badge_text` under the
  admin catalog), `link` (`{path: "_links/<field>"}` — reference links).
- `dataGrid.rowClick` optional: the row's primary action envelope,
  byte-identical to its rowActions entry (`context_select` when the table
  declares `select_context`, else View). Activating the row outside its
  buttons/links dispatches it.
- `fieldDisplay.link` optional: binding to a field's reference link(s);
  text values that are lists (arrays / bulleted multi-line text) render as
  lists.
- `functions.openSurface` `{surface, recordId?, query?}`: reference-link
  navigation, handed to the host.
- Admin `:detail` components now render `fieldDisplay` children (was the
  basic Row/Text composition) so details get typed formatting and links.
- Pagination renders windowed page chips when `total`/`pageSize` are
  known, dispatching the existing `query` envelope with `pageDelta` = the
  distance to the target page.

