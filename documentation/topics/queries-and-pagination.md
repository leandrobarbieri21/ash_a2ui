# Queries and Pagination

Real tables need search, filtering, sorting, and pagination — but a wire
protocol must never accept arbitrary client query parameters. AshA2ui's
answer is the `query` DSL entity: a **named, declarative allowlist the
server enforces**. The client only ever references the query by name (via
the table component) and submits state; every requested search, sort,
filter, and page value is validated against the declaration and anything
not declared is rejected before Ash is called.

## Declaring a query

```elixir
a2ui do
  query :default do
    search_fields [:subject, [:author, :email]]  # string attrs or paths, ci-contains, OR'd
    sortable [:subject, :inserted_at]     # the only sortable fields
    filters [:status]                     # equality filters on these fields
    default_sort inserted_at: :desc
    page_size 25                          # default page size
    max_page_size 100                     # hard clamp for client requests
  end

  component :table do
    fields [:subject, :status, :inserted_at]
    query :default
  end
end
```

All referenced fields must be **public attributes** (and `search_fields`
must be string-typed) — verified at compile time, like every other DSL
reference — with these extensions:

- `search_fields` entries may be **relationship paths** to a string
  attribute (`[:author, :email]`): every step but the last must be a public
  relationship, the last a public string attribute of the final destination
  (the same rules as `source` columns). The search condition references the
  terminal attribute through the path — Ash data layers apply `exists`
  semantics to to-many paths, so a match on *any* related record includes
  the row.
- `sortable` (and `default_sort`) may also name **public aggregates and
  expression-based calculations**, because Ash can push those into a
  generic sort. Module-based (non-expression) calculations are not
  generically sortable and are rejected with a tailored compile error.
- `filters` may also name **expression-based public calculations** —
  equality on the calculation's value, cast against the calculation's
  type/constraints. Module-based calculations have no data-layer expression
  and are rejected at compile time (mirroring the sorting rule); aggregates
  are not filterable.

Relationship-sourced `source` columns (see
[Relationship Rendering](relationships.md)) are render-only and rejected in
query allowlists. A table without a `query` behaves exactly as before: all
records, no query controls.

Multi-key sorts mixing calculations and attributes compose naturally:
`default_sort status_priority: :asc, code: :asc` (with `status_priority` an
expression calculation) orders by the calc first, then the attribute — no
extra machinery needed.

## Named filter presets

Composite predicates — "pending" meaning several conditions at once — do not
fit equality filters, and the allowlist principle forbids letting clients
send predicates. **Presets** solve this: the server declares named composite
filters, and the client selects one **by name**.

```elixir
query :default do
  filters [:status]
  default_preset :active

  preset :active do
    filter deleted_at: nil                      # is_nil
  end

  preset :pending do
    filter status: :pending, deleted_at: nil    # conditions ANDed
  end

  preset :closed do
    filter status: [:approved, :declined]       # list = membership
  end

  preset :deleted do
    read_action :deleted                        # escape hatch (see below)
  end
end
```

A `filter` preset is a keyword list ANDed onto the base query: `nil` means
`is_nil`, a list means membership (`in`), anything else is equality. Keys
follow the `filters` rules (public attributes or expression calculations;
values verified castable at compile time). Predicates the keyword form
can't express — `not is_nil(...)`, ranges, ORs — use the `read_action`
escape hatch: the preset reads through a dedicated read action (with its own
`filter expr(...)`) instead of the table's `read_action`. Search, filters,
sort and pagination all compose on top of either kind.

On the wire, the `/query` state map gains a `"preset"` key (only when the
query declares presets) and the encoder emits a `ChoicePicker`
(`query_preset_picker`, bound to `/query/preset`) whose options are the
preset names. `default_preset` names the preset applied when the client
selects none — a missing or empty `"preset"` falls back to it, and the
picker omits the `"All"`/`""` (no preset) option, making the declared set
closed: the unscoped base read is unreachable from the client. Without a
`default_preset`, `""` means "no preset" and an `"All"` option is emitted
first. Unknown preset names are rejected before Ash is called, like every
other allowlist violation. Presets are UX scoping, not a security boundary —
authorization stays in Ash policies.

## Client-driven range filters

Presets cover *fixed* composite predicates; **`range_filters`** covers the
one client-driven predicate shape that equality filters can't: bounding a
field between two client-supplied values ("visits since July 1st").

```elixir
query :default do
  range_filters [:scheduled_for]   # public attributes only
end
```

- The `/query` state gains a `"ranges"` key (only on queries declaring
  `range_filters`): one `{"from": "", "to": ""}` entry per declared field.
  Both `""` means inactive; a non-empty bound is ANDed onto the read as an
  **inclusive** `>=` / `<=` condition.
- Bounds travel as strings and are cast to the attribute's type before any
  read — a value that doesn't cast is rejected with an `/ui/feedback` error, exactly
  like an uncastable filter value. Fields not in `range_filters` are
  rejected too.
- **Date convenience on datetime fields:** a plain `YYYY-MM-DD` bound on a
  datetime-typed attribute expands to the day's edge — `from` becomes
  `00:00:00Z`, `to` becomes `23:59:59.999999Z` — so "from 2026-07-01 to
  2026-07-01" covers the whole day. The state echoes the client's raw
  strings back, not the expanded values.
- The encoder emits two `TextField`s per declared field
  (`query_range_<field>_from` / `query_range_<field>_to`, bound to
  `/query/ranges/<field>/from|to`), applied by the same **Apply** button.
- Only plain public attributes may appear in `range_filters` (compile-time
  verified); calculations/aggregates and relationship-sourced columns are
  rejected.

## What gets emitted

When the table declares a query, the encoder adds to the component tree:

- a search `TextField` bound to `/query/search` (omitted when there are no
  `search_fields`),
- a preset `ChoicePicker` bound to `/query/preset` (only when the query
  declares presets — see above),
- one `ChoicePicker` per filter bound to `/query/filters/<name>` with an
  `"All"` (empty value) option first — options come from the attribute's (or
  calculation's) `one_of` constraints or the attribute's `Ash.Type.Enum`
  module's `values/0` (or True/False for booleans),
- a from/to `TextField` pair per `range_filters` field bound to
  `/query/ranges/<field>/from|to` (see above),
- an **Apply** button and **Previous/Next** pagination buttons.

All of them dispatch the `"query"` client action. The wire contract:

```json
{
  "action": {
    "name": "query",
    "context": {
      "query": { "search": "...", "filters": {...}, "sort": {...}, "page": 2, "pageSize": 25 },
      "page": 1,
      "pageDelta": 1
    }
  }
}
```

- `"query"` is the current `/query` data-model map (the controls bind it via
  `{"path": "/query"}`).
- `"page"` is an optional literal override — the Apply button sends
  `"page": 1` so a new search/filter starts from the first page.
- `"pageDelta"` is an optional relative change — the Previous/Next buttons
  send `-1` / `1`. Precedence: literal `page` wins, then `page + pageDelta`,
  always clamped to ≥ 1.

The server answers with two `updateDataModel` messages: `/records` (the
page) and `/query` (the authoritative state — see
[Data Model Conventions](data-model-conventions.md) for the exact shape).

### Per-table queries on multi-table surfaces

Queries stay **per-table**: each named table component may reference its own
`query` entity. On a multi-table surface (see
[Multi-Section Surfaces](multi-section-surfaces.md)) the emitted controls
bind to that table's scoped state at `/query/<component_name>`, the `query`
action context **requires** `"component": "<component_name>"` (the controls
always send it; a missing or unknown component is rejected with an `/ui/feedback` error,
as is targeting a table with no query), and the response messages go to
`/records/<component_name>` + `/query/<component_name>`. Single-table
surfaces keep the plain `/query` paths and need no `"component"`.

## Enforcement (the allowlist)

`AshA2ui.QueryRunner` validates the context before anything touches Ash:

- a sort field not in `sortable` → rejected,
- a filter name not in `filters` → rejected,
- a filter value that doesn't cast to the field's type/constraints →
  rejected,
- a range on a field not in `range_filters`, or a bound that doesn't cast →
  rejected,
- a preset name not declared as a `preset` → rejected,
- a search on a query with no `search_fields` → rejected,
- requested `pageSize` is clamped to `1..max_page_size`, `page` to ≥ 1.

Rejections return `{:error, [message]}` with a human-readable explanation as
an `/ui/feedback` error — the same convention as every other handler error — and **no
read is executed**. Unknown extra keys inside the submitted `"query"` map
(such as the echoed `totalCount`/`hasMore`) are ignored.

Search builds a case-insensitive `contains` expression OR'd across the
declared `search_fields`; filters are equality (`in` when a list of values
is submitted, e.g. from a `multipleSelection` ChoicePicker); sort falls back
to `default_sort` when the client requests none.

## Pagination mechanism

Pagination uses plain `Ash.Query.limit/2` + `Ash.Query.offset/2` with
`limit = page_size + 1`: the extra row only signals `hasMore` and is dropped
from the results. This deliberately works on **any** data layer without
requiring the read action to enable Ash's `pagination` — resources need no
changes. `totalCount` is computed with `Ash.count/2` on the filtered,
unpaginated query and degrades to `null` on data layers without count
support. The primary key is appended as a sort tiebreaker so pages are
stable under equal sort values.

## Writes respect the active query

On query-enabled surfaces the emitted `submit_form` and row-action `invoke`
contexts also carry `"query": {"path": "/query"}` (on multi-table surfaces
that binds the whole per-table state object). After a successful write,
the refresh re-runs the *current* query (same search/filters/sort/page) and
includes a fresh `/query` message — the user stays on their page with their
filters intact. A missing or invalid carried query state falls back to the
query's declared defaults; the write itself never fails over refresh state.

PubSub-driven refreshes preserve the query too: `AshA2ui.LiveRenderer`
tracks the last `/query` state it pushed to the client and passes it to
`AshA2ui.Info.build_data_model/2` as `:query_state` (validated against the
allowlist like any client input; invalid state falls back to the declared
defaults). A live refresh therefore re-runs the user's current
search/filters/sort/page instead of resetting the surface. Callers driving
`build_data_model/2` directly get the default (page 1, default sort) unless
they pass `:query_state` themselves.

## Limitations (v0)

- Filters are equality-only (`filters [:status]` = "status equals the
  submitted value"); client-driven bounds go through `range_filters`
  (above). Other custom client-driven predicates are deliberately not
  supported — declare a named preset (or a preset `read_action`) for
  composite server-side predicates instead.
- One query per table (multi-table surfaces may attach one query to each
  table); queries are per-surface, not shared.
- No sort UI is emitted (sort arrives via the `"query"` action, e.g. from an
  agent or custom client); the allowlist still applies.
