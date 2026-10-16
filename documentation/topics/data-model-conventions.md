# Data Model Conventions

A2UI components don't carry data — they carry **bindings**: JSON Pointer
paths into a per-surface data model that the server updates with
`updateDataModel` messages. The protocol doesn't prescribe how that data
model is laid out, so AshA2ui reserves a small, stable set of paths and
promises to keep them consistent across every surface it emits. Renderers,
custom hooks, and tests can rely on them.

## The reserved paths

| Path | Contains | Written when |
|---|---|---|
| `/records` | The list of records backing the table component (multi-table surfaces: an object keyed by table component name — see below) | Initial render; every refresh (action follow-ups, PubSub) |
| `/records/<component_name>` | One table's record list on a **multi-table** surface | Initial render; every refresh that targets that table |
| `/form` | The form component's current field values (nested-form arguments: arrays of row maps) — the task panel's edit buffer | Initial render; `start_create` (fresh); `start_edit` (the record's values); `cancel_record_task` and after submit (reset); `nested_add`/`nested_remove` |
| `/errors/<field>` | Human-readable validation error text for `<field>` | A submitted action fails validation |
| `/errors/<argument>/<index>/<field>` | Validation error text for one field of one nested-form row (index into the submitted array) | A submit with nested rows fails validation |
| `/options/<name>` | The option list of a relationship-backed form select **or** a pick_existing nested form (keyed by field / argument name) | Initial render; full data-model refreshes; every `option_search` |
| `/select/<name>` | Client-side state of searchable selects (`{"search", "label"}`) and pick_existing pickers (`{"search", "picked"}`) | Initial render (only on surfaces using them); `option_select`; `start_edit`; after submit |
| `/ui/feedback` | The typed outcome of the last action: `{"kind", "message"}`, kind `"success"` / `"warning"` / `"error"` (`null` when cleared) — the flash-equivalent | After every handled action (success, rejection, validation failure, refusal); cleared by task open/cancel |
| `/ui/intent` | The task the surface is in: `"browse"`, `"create"`, `"view"` or `"edit"` | Initial render (`"browse"`); every task-panel action; a successful `submit_form` (back to `"browse"`) |
| `/ui/panel` | The task panel: `visible`, `mode`, `title`, `primary_label`, `record_id`, the `submit_visible` / `form_visible` / `view_visible` sentinels, and `record` (the read-only display values of a `view_record`) | Same as `/ui/intent`; `wizard_next`/`wizard_back` rewrite `primary_label` and `submit_visible` |
| `/_empty_visible` / `/_empty_message` | A table's empty-state sentinel (`[]` while records exist) and its text (multi-table: `/_empty_visible_<table>`, `/_empty_message_<table>`) | Initial render; every records rewrite |
| `/ui/action_result` | The raw map returned by a map-returning generic action | An `invoke`d generic action returns a plain map (cleared by every subsequent successful action) |
| `/ui/action_result_text` | The human-readable rendering of `/ui/action_result` | Same as `/ui/action_result` |
| `/query` | The current search/filter/preset/sort/pagination state of a query-enabled table (multi-table surfaces: an object keyed by table component name) | Initial render; after every `query` action; alongside query-aware success refreshes |
| `/query/<component_name>` | One table's query state on a **multi-table** surface | Same as `/query`, per table |
| `/_lane_total_<lane>` | A board lane's total as a string (`"3"`, `"5+"`) — only on surfaces with `display :board` tables | Initial render; action refreshes and `query` actions on that lane. A `scope: :records` push leaves it untouched |
| `/prompt/values/<action>` | The input values of a prompt-enabled row action's Modal (only on surfaces with `prompt_fields` actions) | Initial render (empty); pre-filled on `prompt`; cleared after a successful prompt `invoke` |
| `/context/<name>` | One surface context's selection state (`{"search", "value", "label"}`) — only on surfaces with `context` entities | Initial render; every `context_select`/`context_clear` (the whole `/context` map is rewritten) |
| `/options/<context>` | A picker context's option list (same `{"label","value"}` shape; shares the `/options` namespace) | Initial render; `context_search`; cascades that re-derive a dependent context's options |
| `/detail/<context>` | The selected record of a context rendered by `:detail` components (`{}` while unselected) | Initial render; every selection change of that context |
| `/report/<name>` | One `:report` component's state: `{"params" => %{<param> => ""}, "rows" => []}` — only on surfaces with `:report` components | Initial render (empty params, no rows); every `report` action rewrites `/report/<name>/rows` |
| `/ui/wizard` | A stepped form's wizard state: `index`, `steps` (`[{"name","label","state"}]`), the `<step>_visible` sentinels and the `nav` sentinels — only on surfaces whose form declares `step`s | Initial render (step 0); `wizard_next`/`wizard_back`; a failed `submit_form` (jumps to the owning step); reset to step 0 by task open/cancel and a successful `submit_form` |
| `/export/<name>/columns` | The column-selection booleans of a `column_select` export (`%{<column> => true}`, all checked initially) — only on surfaces with column-selectable `export` blocks | Initial render; toggled client-side by the checkboxes (never rewritten by the server) |
| `/bulk/<table>/result` | The last bulk run's outcome on a table with `bulk_actions`: `{"ok", "failed", "refused", "skipped", "errors"}` (`errors`: `[{"id", "message"}]`) — only on surfaces with bulk actions | Initial render (all zero); every `bulk_invoke` that passes the allowlist and selection checks |

Everything under these paths uses camelCase string keys, matching the rest of
the wire format.

## `/records` — table data

The table component's `List` binds to `/records`; each record is a map of the
surface's fields (values already run through any `format` hints from `field`
options). A data-only refresh — from `AshA2ui.Info.build_data_model/2` or the
LiveView transport's PubSub subscription — is one message:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/records",
    "value": [
      { "id": "…", "subject": "Printer on fire", "status": "open" }
    ]
  }
}
```

Because `updateDataModel` replaces the value at `path`, refreshes are
whole-region: the list is replaced, not diffed. On multi-table surfaces the
region is one table (`/records/<component_name>`), and `action` entities with
`refreshes` metadata narrow which regions a successful action rewrites — see
below and [Multi-Section Surfaces](multi-section-surfaces.md).

## Multi-table surfaces: `/records/<name>` and `/query/<name>`

A surface is **multi-table** exactly when it declares more than one `:table`
component (named via `component :table, :some_name` — see
[Multi-Section Surfaces](multi-section-surfaces.md)). The frozen rules:

- **Single-table surfaces are unchanged.** `/records` is the record list,
  `/query` is the (single) query-state map, and all component ids keep their
  unsuffixed names. Nothing about this wave affects existing surfaces.
- On a **multi-table** surface, `/records` is an **object keyed by table
  component name**: `/records/<component_name>` holds that table's record
  list. Every declared table always has a key (missing data renders as `[]`).
- `/query` is likewise an object with one `/query/<component_name>` entry
  **per query-attached table**; tables without a `query` have no key. Each
  entry has the same shape as the single-table `/query` (below).
- Refresh messages target the scoped paths — `/records/<name>` and
  `/query/<name>` — never the whole `/records` object (except full
  data-model refreshes at `/`, which write the complete keyed objects).
- Row-action `invoke` contexts additively carry
  `"component": "<component_name>"` identifying the source table (the
  handler tolerates its absence). `query` action contexts **require** it on
  multi-table surfaces.

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "review",
    "path": "/records/new_items",
    "value": [ { "id": "…", "name": "Fresh", "count": 3 } ]
  }
}
```

## Board lanes: `/_lane_total_<lane>`

A `display :board` table (see
[Multi-Section Surfaces](multi-section-surfaces.md#boards-sections-over-an-attribute-s-values))
is a set of expanded tables, one per lane, so each lane follows the
multi-table rules above under its runtime name (`/records/board_open`,
`/query/board_open`). One reserved root key is added per lane:

- `/_lane_total_<lane>` — the lane's total as a **string**, bound by the
  lane heading: the lane query's `totalCount` when present, else the number
  of rows in the lane, suffixed `+` when the query reports more rows but no
  count. It sits at the root beside the `_empty_visible_<table>`
  sentinels. The initial render, action refreshes (`refreshes`) and
  `query` actions rewrite it beside the lane's records. A records-only
  push (`encode_data_model(view, records, scope: :records)`) replaces
  `/records` alone and leaves it as it was, like the `_empty_visible`
  sentinels; push a full data model when the totals must follow.

Surfaces without boards never carry the key.

## `refreshes` — per-action refresh regions

By default a successful `submit_form`/`invoke` refreshes **every** table.
An `action` DSL entity narrows that:

```elixir
action :approve do
  refreshes [:new_items]
end
```

After a successful `:approve`, only `/records/new_items` (and
`/query/new_items`, when a query is attached) is rewritten — other tables'
regions are left untouched on the client. The `/form`, `/errors` and `/ui/*`
follow-up semantics are never affected by `refreshes`.

## `/form` — form state

Form inputs bind to `/form/<field>`. Opening an edit task (the `start_edit`
action) loads that record's editable values into `/form`; `start_create` and
`cancel_record_task` reset it, and a successful create or update clears it
back to its initial shape. A view task (`view_record`) never writes `/form`:
it renders the record read-only from `/ui/panel/record`. Clients that keep local edit
state should treat a server write to `/form` as authoritative.

On surfaces without nested forms the initial (and post-success) `/form` is
`{}`, exactly as before. Surfaces with `nested_form` entities additionally
carry **one array of row maps per argument** — `/form/<argument>` is always
present (initially `[]`), so the row `List` templates and the add/remove
buttons' `"rows"` context bindings always have a value:

```json
{ "form": { "notes": [ { "_row": "…", "body": "…", "rating": 4 } ],
            "tags":  [ { "_row": "…", "id": "…", "label": "urgent" } ] } }
```

Row maps use the destination's field names as keys plus reserved
underscore-prefixed **client-state keys**, which `submit_form` strips before
the argument cast:

- `"_row"` — the server-stamped row identity (the record id for existing
  rows, a generated UUID for fresh create_inline rows); the target of
  `nested_remove` and the template key. Never an array index.
- `"_error_<field>"` — the row-scoped validation error mirror (below).

`start_edit` populates the arrays from the record's currently-related
records (loaded through the argument's relationship). Rows are mutated only
by the `"nested_add"` / `"nested_remove"` actions — the server replaces the
whole array in one `updateDataModel` — and by create_inline row inputs
binding template-relative field paths. See
[Relationship Rendering](relationships.md) for the full contract.

## `/errors/<field>` — validation errors

When `AshA2ui.ActionHandler` invokes an Ash action and gets validation errors
back (an `Ash.Error.Invalid` with field-attributed errors), it maps each
error's field to its reserved path and pushes the message text:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/errors/subject",
    "value": "has already been taken"
  }
}
```

Conventions:

- The value is display-ready text (multiple errors on one field are joined),
  not a structured error object.
- A subsequent successful submit **clears** the error paths (`/errors` is
  reset wholesale to `{}`).
- Errors that can't be attributed to a field (e.g. a policy denial) go to
  the `/ui/feedback` error instead.
- Errors on **nested-form rows** carry Ash's error path and land at
  `/errors/<argument>/<index>/<field>` — `<index>` is the row's position in
  the submitted array. The same text is additionally mirrored into the
  submitted row itself as an `"_error_<field>"` key (one
  `/form/<argument>` rewrite), because row templates can only bind
  template-relative paths. Treat the `/errors/...` paths as the programmatic
  contract and the mirrors as a rendering aid.

Renderers bind error `Text` components next to each input at
`/errors/<field>` and get inline validation for free — no error-specific
message types needed.

## `/ui/feedback` — the flash-equivalent

Stateless protocols have no "flash" concept, so AshA2ui reserves
`/ui/feedback` for the typed outcome of every action. The message is
display-ready text; the kind says what happened:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/ui/feedback",
    "value": { "kind": "success", "message": "Created successfully." }
  }
}
```

`AshA2ui.ActionHandler` writes it after every outcome-bearing action — a
success text on completion (submits, invokes, report runs, CSV exports),
`"warning"` when a bulk run partly succeeded or a selection was capped, and
`"error"` with
an explanation on rejected/unknown actions, a "not authorized" text on policy
denials (deliberately without detail), and a generic failure text when errors
can't be attributed to a field. Task open/cancel and context
select/clear clear it (`kind: null`, `message: ""`). Actions that only fetch
data for the client (`query`, `option_search`, `context_search`) leave it
untouched. The emitted surface binds its `status_text` Text to
`/ui/feedback/message` (right under the task panel, above the tables), and
the admin catalog's `statusBanner` binds both keys. On v1.0 surfaces the
same outcome is also the structured `/ui/response` object (see
[A2UI 1.0](a2ui-1-0.md)).

There is no `/ui/status`: it was removed with the pre-experience
composition. Consumers that read it move to `/ui/feedback/message`.

## `/ui/action_result` and `/ui/action_result_text` — generic action results

Row actions (`invoke`) may target **generic actions** — think "generate an
API secret" or "recompute stats". Three handler conventions apply (all are
AshA2ui conventions layered on the protocol, not part of the A2UI spec):

- **`:record_id` pass-through** — if the generic action declares a
  `:record_id` argument, the `invoke` context's `"recordId"` is passed to it,
  so row-scoped generic actions know which record they were invoked on.
- **`/ui/action_result`** — when the action returns a plain map, the handler
  serializes it (JSON-safe values, string keys) and writes it to
  `/ui/action_result` alongside the usual success follow-ups. This is the
  raw result, for programmatic consumers:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/ui/action_result",
    "value": { "secret": "s3cr3t", "record_id": "…" }
  }
}
```

- **`/ui/action_result_text`** — the same result rendered as display-ready,
  selectable text: one `Humanized key: value` line per key, sorted by key
  (non-string values are JSON-encoded). The emitted surface always includes
  an `action_result_panel` (a `Column` wrapping a `Text` bound to this
  path), so a generic action returning `%{secret: "abc"}` produces visible,
  selectable `Secret: abc` text with no custom renderer work:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "tickets",
    "path": "/ui/action_result_text",
    "value": "Record id: …\nSecret: s3cr3t"
  }
}
```

Both paths are **cleared** (`{}` / `""`) at the start of every subsequent
successful action's follow-up batch, so a stale result never outlives the
action that produced it (a map-returning action clears and then sets them in
the same batch — apply messages in order). Non-map results (`:ok`, records)
emit no extra message beyond the clears.

## `/options/<name>` — relationship select and picker options

When a form field is backed by a `belongs_to` relationship (inferred from the
field name matching the relationship's `source_attribute`, or declared with
the `relationship` field option — see
[Relationship Rendering](relationships.md)), the surface loads the
destination's records and exposes them as an option list. Pick_existing
nested forms get the same treatment, keyed by the **argument** name:

```json
{
  "version": "v0.9.1",
  "updateDataModel": {
    "surfaceId": "posts",
    "path": "/options/author_id",
    "value": [
      { "label": "Ada Lovelace", "value": "018f…" },
      { "label": "Alan Turing", "value": "018f…" }
    ]
  }
}
```

Conventions:

- The value is always a list of `{"label": string, "value": string}` objects
  — `value` is the stringified `option_value` attribute (a UUID by default),
  `label` the stringified `option_label` attribute (falling back to the
  value when the label attribute is nil).
- The list is written on the initial render and on full data-model refreshes
  (`build_data_model/2`, PubSub pushes). Success follow-ups do **not**
  refresh options — but the `"option_search"` client action rewrites exactly
  one `/options/<name>` list on demand (searchable selects and searchable
  pick_existing pickers only; see
  [Relationship Rendering](relationships.md)).
- Because the v0.9.1 basic-catalog `ChoicePicker` only accepts a literal
  inline options array (each option's `value` is a plain string — no data
  binding), the emitted picker carries the same list **inline** in
  `updateComponents`; `/options/<field>` is the stable, programmatic mirror
  of what was rendered. Renderers with dynamic-options support can bind to
  it directly.
- Selected values travel back through `/form/<field>` as strings (see
  `AshA2ui.ActionHandler` for the cast rules).

## `/select/<name>` — searchable-select and picker state

Present **only** on surfaces with searchable selects (`option_search`) or
pick_existing nested forms — pre-Wave-5 surfaces carry no `"select"` key.
One entry per name:

- searchable selects: `{"search": "", "label": ""}` — `search` is the
  search input's binding, `label` the display text of the current selection
  (written by `"option_select"` and by `start_edit`).
- pick_existing pickers: `{"search": "", "picked": []}` — `picked` is the
  (non-searchable) ChoicePicker's value binding, read by the add button's
  context.

The whole `/select` map is rewritten on row selection (labels filled from
the loaded record) and reset after a successful submit. Four client actions
accompany these paths — `"option_search"`, `"option_select"`,
`"nested_add"`, `"nested_remove"`; their contexts and semantics are frozen
in [Relationship Rendering](relationships.md).

## `/query` — search/filter/sort/pagination state

When a table component declares a `query` (see
[Queries and Pagination](queries-and-pagination.md)), the surface carries the
current query state at `/query` (multi-table surfaces: at
`/query/<component_name>` per query-attached table). The exact shape (frozen
contract):

```json
{
  "search": "",
  "filters": { "status": "", "category": "" },
  "ranges": { "inserted_at": { "from": "", "to": "" } },
  "preset": "pending",
  "sort": { "field": "inserted_at", "dir": "desc" },
  "page": 1,
  "pageSize": 25,
  "totalCount": 42,
  "hasMore": true
}
```

Conventions:

- `filters` always contains **every declared filter name**; an empty string
  means "inactive", so client bindings at `/query/filters/<name>` are stable.
- `ranges` is present **only when the query declares `range_filters`**: one
  `{"from": "", "to": ""}` entry per declared field (both `""` = inactive;
  bounds are inclusive and validated server-side — see
  [Queries and Pagination](queries-and-pagination.md)). Client bindings at
  `/query/ranges/<field>/from|to` are stable.
- `preset` is present **only when the query declares presets** (see
  [Queries and Pagination](queries-and-pagination.md)): the selected
  preset's name, or `""` when none is active. The client only ever sends a
  preset *name* — never predicates.
- `sort` is `{"field": ..., "dir": "asc" | "desc"}` or `null` when unsorted.
- `totalCount` is an integer, or `null` when the data layer cannot count.
- `hasMore` says whether a next page exists.
- The server writes `/query` on the initial render, after every `query`
  action, and alongside query-aware success refreshes — client edits to
  `/query/search` and `/query/filters/...` (via the emitted controls) are
  local until a `query` action sends them back.

The `query` client action's context is `{"query": <the /query map>}` plus an
optional literal `"page"` override or relative `"pageDelta"`; everything in
it is validated against the DSL-declared allowlist and rejected with an
`/ui/feedback` error when not declared.

## `/prompt/values/<action>` — row-action prompt state

When a row action declares `prompt_fields` (see
[Actions and Authorization](actions-and-authorization.md)), its Modal inputs
bind to `/prompt/values/<action>/<field>` — absolute paths, because the
basic catalog's action contexts cannot nest objects and the prompt state is
shared across rows (only one Modal is open at a time). Conventions:

- The initial data model carries `"prompt"` (only on surfaces with
  prompt-enabled actions): one values map per prompt action, every declared
  field present as `""`.
- Clicking the trigger sends the `"prompt"` action; the server rewrites
  `/prompt/values/<action>` with the record's current values (public
  attributes; `""` for pure arguments) and clears `/errors`.
- The Modal's Confirm sends `"invoke"` with
  `"values": {"path": "/prompt/values/<action>"}`; a success clears the
  action's values map back to `{}`, a validation failure writes
  `/errors/<field>` (rendered inside the Modal).

## `/context/<name>` and `/detail/<context>` — surface contexts

Present **only** on surfaces declaring `context` entities (see
[Contexts and Details](contexts-and-details.md)). `/context` carries one
`{"search": "", "value": "", "label": ""}` entry per declared context —
`search` is the picker's search-input binding, `value`/`label` the current
selection (`""` = unselected). The server rewrites the **whole `/context`
map** on every selection change (`context_select` / `context_clear`),
including cascade effects on dependent contexts.

`/detail/<context>` carries the serialized selected record for contexts
rendered by `:detail` components — the same JSON-safe map shape as a
`/records` row, `{}` while the context is unselected.

Every action context on a context-enabled surface additively carries
`"contexts": {"path": "/context"}`, so server reads (refreshes, `query`,
cascades) run under the client's current selections. Carried context values
are **scoping input, not authority**: the changed context's value always
round-trips through an authorized read, and scoped table reads run with the
surface's actor/tenant/authorize? as usual.

## `/ui/wizard` — wizard step state

Present **only** on surfaces whose form declares `step` entities (see
[Wizard Steps](wizard-steps.md)). It carries:

- `"index"` — the current step (0-based integer);
- `"steps"` — one `{"name", "label", "state"}` entry per step, `state`
  being `"done"`, `"current"` or `"todo"` (the progress header binds it);
- `"<step>_visible"` — one zero-or-one sentinel per step (`[{"id": "on"}]`
  on the current step, `[]` elsewhere); each step page is a `List`
  templated over it;
- `"nav"` — `"back_visible"` and `"next_visible"` sentinels for the
  navigation controls (the submit is gated by the panel's
  `/ui/panel/submit_visible`, which opens on the last step).

The server rewrites the whole `/ui/wizard` value on every move. `/form` is
carried across steps unchanged: the `wizard_next` / `wizard_back` contexts
carry `"index": {"path": "/ui/wizard/index"}` (and Next the
`/form` values), and the server re-checks both — keys outside the form's
fields are dropped and the index is clamped into the step range.

## Per-row visibility: `"_actions"` and `"_visible_<action>"`

Rows of a table whose `row_actions` include `visible_when`-conditional
actions carry two extra keys (server-computed; see
[Actions and Authorization](actions-and-authorization.md)):

- `"_actions"` — the names of the row actions visible for this record,
- `"_visible_<action>"` — `[{"id": <record id>}]` when visible, `[]` when
  hidden; the emitted per-action `List` slot templates over this
  row-relative path to render zero or one button.

Rows of tables without conditional actions are unchanged (no underscore
keys).

## Per-row selection: `"_selected"`

Rows of a table that declares `bulk_actions` carry `"_selected"`, bound by
the row's CheckBox (see [Bulk Actions](bulk-actions.md)). The server writes
`false` on every row it sends (initial render, refreshes, a successful
`bulk_invoke`), and `true` or `false` on a `bulk_select` rewrite (on a
table without a query, "Select page" marks at most the bulk cap). The client
toggles it in place; `bulk_invoke` reads only `"id"` and `"_selected"` from
the carried rows, and every id is re-read through an authorized, scoped read
before anything is written. Rows of tables without bulk actions carry no
`"_selected"` key.

## Per-row error mirrors: `"_error_<field>"`

When an inline cell edit (`editable` — see
[Reports, Exports, and Editable Tables](reports-and-exports.md)) fails
validation, the failing row of the refreshed `/records` write carries the
submitted value (so the user can correct it in place) and the error text at
its reserved `"_error_<field>"` key — the only template-relative place a
per-row error Text can bind. Rows of untouched records, and all rows after
a subsequent successful commit, carry no underscore error keys.

## Why conventions instead of message types

The A2UI protocol keeps its message vocabulary tiny on purpose — data and
lifecycle signals all travel as `updateDataModel`. Encoding lifecycle state
*into the data model at known paths* means any conforming renderer displays
it with plain bindings, nothing custom to implement. These reserved paths are
part of AshA2ui's public contract: additions may come (they'll be documented
here), but existing paths won't change meaning within a major version.

> #### Precise payload shapes {: .info}
>
> The exact grouping of these writes (single message vs. one per path, order
> relative to `/records` refreshes) is pinned down by the encoder/handler
> test suites rather than this document — the vendored v0.9.1 JSON Schemas
> in `priv/a2ui/v0_9_1/` validate every emitted message. Treat the *paths and
> meanings* above as frozen, and the message batching as an implementation
> detail.
