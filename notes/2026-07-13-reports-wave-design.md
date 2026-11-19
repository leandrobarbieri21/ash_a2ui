# Reports wave: dynamic table sets, report queries, CSV export, inline cell editing

Design record for the four features closing a host app's misspellings /
usage_stats NO-GOs (thesis roadmap items 3+4). Contracts below are FROZEN on
merge; the topic docs are the public statement, this note records rationale.

## 1. Dynamic table sets (`sections` on `:table` components)

**Problem:** misspellings renders one table section *per runtime bucket* —
A2UI named tables were statically declared.

**Design:** a singleton `sections` entity inside a `:table` component turns
it into a *template* expanded at render time into one concrete table per
record of a source resource:

```elixir
component :table, :per_bucket do
  fields [:word, :replacement]
  query :bucket_q
  sections do
    source MyApp.Bucket     # enumerated per render (authorized read)
    scope_by :bucket_id     # table-resource attr == section record's value
    label :name             # section heading (defaults like option_label)
    value :id               # section identity (defaults to source pk)
    sort :name              # section ordering (pk tiebreaker appended)
    limit 25                # hard cap on section count
  end
end
```

**Mechanics:** `AshA2ui.Sections.expand/2` runs after `ResolvedView.resolve`
in `Info.build_surface/2`, `Info.build_data_model/2`, and
`ActionHandler.handle/3`. It reads the source (actor-scoped, authorized),
and replaces the template table/component with one per section. Everything
downstream (encoder, QueryRunner, handler dispatch/refresh) operates on the
expanded view unchanged — dynamic table sets ARE multi-table surfaces with
runtime names.

**Frozen contract:**
- Runtime table name: `<template_key>_<sanitized section value>`
  (sanitize = replace `[^A-Za-z0-9_]` with `_`; UAX #31-safe since the
  template key leads). Section values are the stringified `value` attribute.
- Data model: `/records/<runtime_name>`, `/query/<runtime_name>` — the
  established multi-table convention with runtime names. A surface declaring
  any `sections` table **always** uses scoped paths (even if a render finds
  0 or 1 sections) — `ResolvedView.multi_table?/1` is true for it.
- Component ids: the standard multi-table infix scheme with the runtime
  name. Section headings render the section record's `label` (not the
  humanized component name).
- Section scoping: `scope_by == section value` is ANDed onto every read of
  that table (via the table scope, next to `context_filter` entries) — the
  client can never read outside its section.
- Action contexts carry the runtime name in `"component"`; the handler
  re-expands per request, so a component naming a vanished section is
  rejected ("Unknown table component"). `refreshes [:per_bucket]` targets
  all of the template's expanded tables.
- Structural refreshes: `build_data_model` (PubSub refresh) re-reads
  sections and rewrites the keyed `/records` object, but the *component
  tree* is only built on `build_surface` — new/removed sections appear in
  the data model immediately and get their headings/controls on the next
  mount. Documented limitation.
- Versions: works identically on 0.9.1 and 1.0 (schema-validated on both).

## 2. Report components (`component :report`)

**Problem:** usage_stats renders computed rows (per user × practice ×
date-range), not resource records — nothing to `Ash.read`.

**Design:** a new component kind backed by a declared **generic Ash
action** returning rows:

```elixir
component :report, :usage do
  action :usage_stats            # generic action on the resource, returns [map]
  params [:emails, :from, :to]   # action arguments rendered as inputs
  fields [:email, :practice_name, :note_count]  # column allowlist + order
end
```

**Frozen contract:**
- Reserved path `/report/<name>`: `{"params": {<arg>: "" ...}, "rows": []}`.
  Only present on surfaces declaring reports. Rows never live in `/records`
  (they are not resource records) and reports don't affect
  `multi_table?`.
- Client action `"report"`: context
  `{"component": "<name>", "params": {"path": "/report/<name>/params"}}`.
  The handler casts params against the generic action's arguments (same
  cast rules as prompt values — unknown keys dropped, single-element list
  unwrap), runs the action actor-scoped/authorized, and answers with
  `/report/<name>/rows` (rows filtered to the declared `fields`,
  JSON-safe-serialized) + `/report/<name>/params` (echo) + the standard
  status write. A non-list result (or list with non-map entries) is an
  ACTION_FAILED error. Validation errors land on `/errors/<param>`.
- Components: `report_<name>` Card > `report_<name>_body` Column: heading,
  one widget-mapped input per param (`report_<name>_param_<arg>` bound to
  `/report/<name>/params/<arg>`) + error Text, a Run button
  (`report_<name>_run_button`), a rows List (`report_<name>_rows`
  templated over `/report/<name>/rows`, `report_<name>_row` of labeled
  cells like table cells).
- `fields` is **required** on `:report` components (rows are opaque maps —
  nothing to infer from). Labels come from shared `field` entities.
- Reports run on demand only (initial rows `[]`); params persist in the
  data model between runs (accumulation = the action unions across runs'
  inputs if it wants — the host app models the three usage_stats loaders as
  arguments of one action).
- Versions: both 0.9.1 and 1.0.

## 3. CSV export (`export` on `:table` and `:report` components) — 1.0-only

**Problem:** per-section CSV downloads (misspellings) and column-selectable
CSV output (usage_stats); v0.9.1 had no server→client delivery affordance.

**Design:** the v1.0 `callFunction` RPC is exactly the download affordance:

```elixir
component :report, :usage do
  ...
  export do
    columns [:email, :note_count]  # selectable set; defaults to the fields
    filename "usage_stats.csv"     # defaults to <surface>_<component>.csv
    limit 10_000                   # row cap (tables read unpaginated)
  end
end
```

**Frozen contract:**
- **1.0-only.** `export` on a `spec_version "0.9.1"` surface is a compile
  error (there is no spec-honest delivery path in 0.9.1; the fallback story
  is "upgrade the surface").
- Reserved path `/export/<name>/columns`: the selected column names
  (strings), initialized to all declared columns. Only present on surfaces
  declaring exports.
- Components: `export_<name>_columns` (a `multipleSelection` ChoicePicker,
  emitted only when >1 column is declared) + `export_<name>_button`
  dispatching the `"export"` client action with context
  `{"component": "<name>", "columns": {"path": "/export/<name>/columns"}}`
  plus the standard `"query"`/`"contexts"` bindings on table exports and
  `"params": {"path": "/report/<name>/params"}` on report exports.
- Handler `"export"`: validates the component declares an export and the
  requested columns against the declared allowlist (empty/invalid → all
  declared). Table exports re-run the current query state **unpaginated**
  (clamped to `limit`, section/context scopes applied); report exports
  re-run the report action with the carried params. CSV is RFC 4180
  (quoted where needed, CRLF), header row = column labels.
- Delivery: the reply appends a `callFunction` message invoking the client
  function **`downloadFile`** with frozen args
  `{"filename": string, "mimeType": string, "dataUrl": string}` (a
  `data:text/csv;base64,...` URL). The contract also admits `"url"`
  (a signed one-time URL) instead of `"dataUrl"` for hosts generating
  server-side files; AshA2ui itself always emits `dataUrl`. The shipped
  hook registers `downloadFile` as a built-in (anchor-click download).
  `downloadFile` is an AshA2ui client-function extension: hosts running a
  strict v1.0 catalog validator must declare it in their catalog.
- The export response's `/ui/response` says "Exported N rows." and the
  v1.0 actionResponse carries it (the click gets pending→settled feedback
  like any action).

## 4. Inline cell editing (`editable` on `:table` components)

**Problem:** misspellings edits `replacement` in-row; forms are the only
write path A2UI surfaces had.

**Design:**

```elixir
component :table, :new_items do
  fields [:word, :replacement]
  editable [:replacement]
  update_action :update      # the commit action (defaults to primary update)
end
```

**Frozen contract:**
- Editable cells render the field's widget-mapped input (TextField /
  CheckBox / ChoicePicker) bound to the **template-relative** field path,
  a Save button (`table_cell<sfx>_<field>_save_button`) and an error Text
  bound to the row-relative `_error_<field>` key. Renderers keep local
  edits in the row's data-model copy; the Save button commits.
- Client action `"edit_cell"`: context `{"component": "<table>",
  "recordId": {"path": "id"}, "field": "<field>",
  "value": {"path": "<field>"}}` plus the standard query/contexts
  bindings. The handler validates the field against the table's `editable`
  allowlist, casts the value against the update action, and runs
  `Ash.update` on the identified record (actor-scoped, authorized).
- Success: the table refreshes (respecting the carried query state — the
  canonical row value replaces the local edit) + the standard status
  write; on a 1.0 surface the **actionResponse** drives pending→settled
  per-commit feedback (the hook's optimistic `/ui/response` write settles
  from the response; per-cell visual state is available to hosts via the
  `ash-a2ui:action-response` DOM event carrying the actionId — the basic
  catalog itself has no per-component pending affordance, stated honestly).
- Validation failure: `/errors/<field>` (programmatic contract) **plus**
  one `/records/<table>` rewrite mirroring the error into the target row
  as `_error_<field>` and preserving the submitted raw value in the field
  key — template-relative error rendering, same mechanism as nested-form
  row errors.
- `editable` fields must be subset of the table's `fields`, public writable
  attributes accepted by the commit action; tables with a `row_layout`
  reject `editable` (compile error — the card meta grid has no input
  affordance this wave). Works on 0.9.1 (status-only feedback) and 1.0.

## New client action names

`"report"`, `"export"`, `"edit_cell"` join the reserved action vocabulary.

## New reserved data-model paths

`/report/<name>/params`, `/report/<name>/rows`, `/export/<name>/columns`,
plus `_error_<field>` row mirrors on `/records` rows after a failed
`edit_cell`.
