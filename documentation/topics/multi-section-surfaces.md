# Multi-Section Surfaces

Dashboards and review screens often need several independent tables on one
surface — "new items" and "done items", each with its own read action and
query, where approving a row refreshes only its own section. AshA2ui models
this with **named table components**, a **scoped data model**, and per-action
**`refreshes`** metadata.

## Declaring multiple tables

Give each `:table` component a distinguishing name as the second argument:

```elixir
defmodule MyApp.UI.ReviewUI do
  use AshA2ui.Standalone

  a2ui do
    for_resource MyApp.Review.Item
    surface_id "review"

    component :table, :new_items do
      fields [:name, :count]
      read_action :new_items
      row_actions [:approve, :destroy]
      query :new_q
    end

    component :table, :done_items do
      fields [:name, :state]
      read_action :done_items
    end

    query :new_q do
      search_fields [:name]
      sortable [:name, :count]
      page_size 25
    end

    action :approve do
      refreshes [:new_items]
    end
  end
end
```

Rules (compile-time verified by `AshA2ui.Verifiers.VerifyComponents`):

- `component :table` without a name keeps working — its implicit name is
  `:table`. A surface is **multi-table** exactly when it declares more than
  one `:table` component.
- Only `:table` components may carry a name; component names must be unique;
  at most one `:form` per surface (unchanged this wave).
- Each table has its own `fields`, `read_action`, `row_actions`, and
  (optionally) `query` — queries stay per-table, referenced by name.
- The rendered section heading is the humanized component name
  (`:new_items` → "New items"); a single-table surface keeps the resource
  name as its heading.

## The scoped data model (frozen contract)

Single-table surfaces are byte-for-byte unchanged. On a multi-table surface:

- `/records` is an object keyed by table component name —
  `/records/<component_name>` holds each table's record list (every declared
  table always has a key).
- `/query` is an object with one `/query/<component_name>` entry per
  query-attached table; tables without a query have no key.
- Refreshes target the scoped paths (`/records/new_items`,
  `/query/new_items`), never the whole object — except full data-model
  refreshes (`AshA2ui.Info.build_data_model/2`, PubSub pushes), which write
  the complete keyed objects at `/`.

See [Data Model Conventions](data-model-conventions.md) for the full
reserved-path table.

## Component ids (frozen contract)

Multi-table surfaces infix the table component name right after each id's
leading noun; single-table surfaces keep today's unsuffixed ids:

| Single-table id | Multi-table id |
|---|---|
| `table_heading` | `table_heading_<name>` |
| `records_list` / `record_row` | `records_list_<name>` / `record_row_<name>` |
| `table_cell_<field>` | `table_cell_<name>_<field>` |
| `row_action_<action>_button` | `row_action_<name>_<action>_button` |
| `view_button` / `edit_button` / `create_button` | `view_<name>_button` / `edit_<name>_button` / `create_<name>_button` |
| `row_context_button` | `row_context_<name>_button` |
| `empty_state` | `empty_state_<name>` |
| `query_controls`, `query_search_input`, `query_filter_<f>`, `query_apply_button`, `query_pagination`, `query_prev_button`, `query_next_button`, `query_page_text` | `query_<name>_controls`, `query_<name>_search_input`, `query_<name>_filter_<f>`, `query_<name>_apply_button`, `query_<name>_pagination`, `query_<name>_prev_button`, `query_<name>_next_button`, `query_<name>_page_text` |

Root children order: the task panel (`form_slot`, when there is a form) and
the status text first, then the context pickers, then per table in
declaration order — heading, query controls (if any), create button (if
any), records list, empty state, pagination (if any) — and the
action-result panel last.

## Action contexts carry `"component"`

- Row-action buttons and the View/Edit row controls additively include
  `"component": "<component_name>"` in their `invoke`/`view_record`/
  `start_edit` contexts (the handler tolerates its absence).
- The `query` action **requires** `"component"` on multi-table surfaces (the
  emitted controls always send it); its context `"query"` value is that
  table's state map, and the response targets `/records/<name>` +
  `/query/<name>`.
- The carried query state on `invoke`/`submit_form` contexts binds the whole
  `/query` object (`{"path": "/query"}`), i.e. an object keyed by table
  name on multi-table surfaces — success refreshes parse each table's entry
  and fall back to that query's defaults when missing or invalid.

## `refreshes`: scoping success refreshes

By default every successful `submit_form`/`invoke` re-reads and rewrites
**every** table (today's behavior). An `action` entity narrows it:

```elixir
action :approve do
  refreshes [:new_items]
end
```

- `refreshes` lists table component names; each must exist (compile-time
  verified), and the `action` name must be reachable from some component's
  `row_actions` or the form's create/update actions.
- On success of that action, only the named tables' `/records/<name>` (and
  `/query/<name>`) messages are emitted. `/form`, `/errors`, and `/ui/*`
  follow-ups are unaffected.
- An empty `refreshes []` means "refresh no table" — useful for actions whose
  results only surface via `/ui/action_result`.

## PubSub live refresh

`AshA2ui.Info.build_data_model/2` (and therefore the LiveView transport's
PubSub refresh) always covers **all** tables — it re-reads every table with
its query defaults and writes the complete keyed `records`/`query` objects.

## Dynamic table sets: `sections`

Sometimes the sections themselves are data — one table per category, per
bucket, per team, where the set of sections is only known at render time. A
`sections` block turns a `:table` component into a **template** expanded at
runtime into one concrete table per record of a `source` resource:

```elixir
component :table, :per_bucket do
  fields [:word, :replacement]
  read_action :bucketed
  query :bucket_q

  sections do
    source MyApp.Dictionary.Bucket   # enumerates the sections
    scope_by :bucket_id              # the table's rows are filtered by this
    label :name                      # each section's heading
  end
end
```

At render (and action-handling) time the source is read — actor-scoped and
authorized like any other read — and each returned record becomes one table:

- **Runtime names**: `<template_key>_<sanitized value>` (every
  non-alphanumeric run of the section's `value` — default: the source's
  primary key — becomes `_`). All the multi-table contracts above apply
  under those names: `/records/<runtime name>`, `/query/<runtime name>`,
  `"component"` in emitted action contexts, component-id infixes.
- A surface with a sectioned table is **always multi-table** (even when the
  source yields zero or one section at runtime), so path shapes never change
  between renders.
- Each section's reads AND `scope_by == <section value>` onto the declared
  `read_action` — search/filters/pagination stay per-section.
- Headings show the section record's `label` attribute (not the humanized
  component name).
- `refreshes` may target the template key (`refreshes [:per_bucket]`) — it
  fans out to every runtime table of the set.
- Options: `value` (section value/name attribute; required when the source's
  primary key is composite), `read_action`, `sort` (defaults to the label),
  `limit` (max sections, default 50). `sections` cannot combine with
  `select_context` (compile-time verified by
  `AshA2ui.Verifiers.VerifySections`).

## Boards: sections over an attribute's values

A board is a sectioned table whose sections come from the **values of an
attribute** instead of the records of a source resource, rendered as lanes
side by side. It adds no component kind: it is a `sections` block without a
`source`, plus `display :board` on the table. Expansion, per-lane reads and
pagination, and template-key refresh fan-out are the same as above.

```elixir
component :table, :board do
  display :board
  row_actions [:claim, :complete]
  query :lane_q                         # optional: per-lane pagination

  row_layout do
    title :name
    badge :priority
  end

  sections do
    scope_by :status                      # lanes = enumerated values of :status
    values [:open, :claimed, :completed]  # optional: subset + order
    labels open: "To do"                  # optional: per-lane heading overrides
  end
end

action :claim do
  visible_when status: :open
  refreshes [:board]                      # template key -> every lane
end

action :complete do
  visible_when status: :claimed
  refreshes [:board]
end
```

**Lanes.** Without `source`, the sections are the enumerated values of
`scope_by`: an `Ash.Type.Enum`'s values, or the `one_of` constraint of an
attribute (or calculation), in declaration order. No read is issued to
enumerate them. `values` picks a subset and an order; `labels` overrides
headings, which otherwise are the enum's label or the humanized value. Each
lane is an ordinary expanded table: runtime name `<template_key>_<value>`
(`board_open`), records at `/records/board_open`, query state at
`/query/board_open`, reads ANDed with `status == :open`. A lane with no
records is kept and shows its empty state.

**Rendering.** `display :board` emits one root child, `board_<template_key>`:
a `Column` holding an h2 heading, the create affordance (when the
surface has a create action) and `board_<template_key>_lanes`, a `Row` of
lane `Column`s, each at layout `weight` 1: the lanes share the board's width
equally instead of each sizing to its widest card. The AshA2ui merged
catalog (`priv/js/ash_a2ui_catalog.js`) scrolls the lanes horizontally
inside the board once they reach their minimum width
(`--a2ui-board-lane-min-width`, default 18rem; `--a2ui-board-lane-max-width`
caps them), so a board with many lanes never widens the page. Each lane
`Column` (`lane_<lane>`) holds:

- `lane_<lane>_header`: a `Row` of the lane heading (`table_heading_<lane>`,
  h3) and the lane total (`lane_<lane>_total`, bound to the reserved
  `/_lane_total_<lane>` string),
- `query_<lane>_controls`, only when the lane's query declares search,
  presets, filters or ranges,
- `records_list_<lane>` with the `row_layout` cards, row actions and
  visibility slots of the list composition,
- the empty state and the lane's pagination and export controls.

`display :list` (the default) keeps the stacked rendering above, unchanged.
The admin catalog renders boards with this basic composition, as it does
every sectioned table.

**Selecting a card.** A board takes `select_context` like a list table: every
card gets the per-row "Select <context>" button (`row_context_<lane>_button`),
dispatching `context_select` with the card's id, so the `:detail` components
and related tables bound to the context follow. Nothing in it depends on the
runtime lane name. Other sectioned tables (`display :list`) still do not
take `select_context`.

**Totals.** `/_lane_total_<lane>` is the lane query's `totalCount` when it
has one, else the lane's row count (`"5+"` when the query reports more rows
without a count). The initial render, action refreshes and `query` actions
rewrite it beside the lane's records. A records-only push
(`encode_data_model(view, records, scope: :records)`) replaces `/records`
alone and leaves the totals as they were; push a full data model when they
must follow.

**`limit` caps lanes.** Without a `source`, `limit` (default 50) is the
maximum number of lanes, as it is the maximum number of sections with one.
It is not a per-lane card limit: a lane's page size comes from its query
(`page_size`). A `limit` below the number of lanes is a compile error, so no
lane is dropped silently.

**Moves.** A card moves when a transition runs: a row action gated by
`visible_when` on the lane attribute that refreshes the template key. The
server runs the action like any row action, then re-reads every lane, so the
card leaves one lane and appears in the next. There is no drag-and-drop: it
needs pointer events the basic catalog does not have. A future custom
catalog component can add it, and its drop would still be an `invoke` of a
declared transition, validated server-side like a button.

**Scope cannot be widened.** A lane's `scope_by == value` filter is ANDed
onto every read, including `"query"` actions. A client filter on the lane
attribute that names another value returns nothing; it cannot pull records
from another lane. Only declared lanes are addressable components.

**Rules** (compile-time verified):

- Without `source`, `scope_by` must have enumerable values, every `values`
  entry and every `labels` key must be one of them, and `label`, `value`,
  `sort` and `read_action` are not allowed.
- No two lanes may share a runtime name: a value listed twice in `values`
  (`:open` and `"open"` count as the same value) and two values that
  sanitize alike (`:"in-progress"` and `:in_progress`, both
  `board_in_progress`) are rejected.
- Without `source`, `limit` may not be below the number of lanes.
- With `source`, `values` and `labels` are not allowed.
- `display :board` needs a `:table` with a `sections` block and a
  `row_layout`.

**Not included:** ordering within a lane by a stored rank, WIP limits,
swimlanes on a second axis, and a generated move action. Transitions are the
resource's own actions, so state-machine rules stay on the resource.

Prior art: the board vocabulary comes from PyroManiac
(<https://github.com/frankdugan3/pyro_maniac>), an Ash UI DSL with kanban
views. We borrowed the idea, not the code; the design record is
`notes/2026-10-15-pyro-maniac-borrowings.md`.

## Inline cell editing: `editable`

An `editable` block renders an allowlist of a table's fields as in-row
inputs committing **per cell** — no form roundtrip:

```elixir
component :table, :per_bucket do
  fields [:word, :replacement]

  editable do
    fields [:replacement]
    update_action :update_replacement   # defaults to the primary update
  end
end

action :update_replacement do
  refreshes [:per_bucket]
end
```

- Each editable cell is a TextField bound to the template-relative field
  path (edits stay client-side until committed), a Save button dispatching
  the **`"edit_cell"`** client action (context: `recordId`, `component`,
  `field`, and the field's current `value`), and an error Text bound to the
  row's reserved `_error_<field>` key.
- The server runs `update_action` on the identified record with just that
  field's value, cast like any client input. The edited field must be in
  the declared allowlist — like `row_actions`, that list is the
  authorization surface for client-triggered commits.
- On success the standard refresh conventions apply (the action's
  `refreshes` metadata included). On a validation error the standard
  `/errors/<field>` + status writes are joined by a **row-scoped mirror**:
  the table's records are rewritten with the failing row carrying the
  submitted value (for in-place correction) and the message at
  `_error_<field>`.
- On v1.0 surfaces the per-action `actionResponse` handshake gives each
  cell pending→settled feedback (the shipped hook holds the pending state
  per `actionId`).
- Not supported together with a `row_layout` (card rows render read-only
  meta values); every editable field must be a table field accepted by the
  update action (compile-time verified by
  `AshA2ui.Verifiers.VerifyEditable`).

Editable cells compose with dynamic table sets: on an expanded table the
Save buttons carry the runtime `component` name, and `refreshes` targeting
the template key covers the whole set.
