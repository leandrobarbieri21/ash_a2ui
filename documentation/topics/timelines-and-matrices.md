# Timelines and Matrices

Two more ways to show a `:table`, beside a list, a board and a calendar:

- `display :timeline` reads the records in time order and leads each row
  with its moment;
- `display :matrix` lays the records out as a grid: one row per value of
  one attribute, one column per value of another, a third in each cell.

Neither adds a component kind or a catalog component. Both render a
basic-catalog composition under every catalog, so a client that advertises
only the basic catalog renders them in full. That is the fallback: there is
no richer admin component to fall back from.

## Timelines

```elixir
query :history do
  page_size 50
end

component :table, :history do
  fields [:summary, :outcome, :seen_at]
  display :timeline
  date_field :seen_at
  query :history
end
```

- **Order.** With no declared `default_sort` and no requested sort, the
  table's query reads in `date_field` order, oldest first. A declared or
  requested sort still wins. A table without a `query` shows its records in
  the order the host passes them.
- **The moment.** Every row carries `_timeline_at` (the ISO 8601 value) and
  `_timeline_when` (the date, or the date and minute in
  `config :ash_a2ui, :calendar_time_zone`, as calendars write it). Both are
  `""` when the record has no value, so a missing moment never reads as a
  date. Each basic row starts with a `caption` Text bound to
  `_timeline_when`.
- Everything a list does still works: queries, filters, presets, row
  actions, bulk actions, pagination, the empty state.
- Under the admin catalog a timeline stays the basic list rather than a
  `dataGrid`, whose columns would drop the leading moment.

Rules, checked at compile time and over composed surfaces: `:table` only;
a `date_field` that is a public `:date` or datetime attribute; no
`sections` block; `end_date_field`, `granularity` and `granularities`
stay calendar-only.

## Matrices

```elixir
query :results do
  page_size 200
  default_sort rank: :asc
end

component :table, :results do
  display :matrix
  row_field :case_name
  column_field :candidate
  cell_field :outcome
  query :results
end
```

The rows and columns vary with the data, so the server builds the grid and
serves it at the reserved root path `/_matrix_<table>`:

```json
{
  "columns": [{"text": "Case name"}, {"text": "v1"}, {"text": "v2"}],
  "rows": [
    {"cells": [
      {"text": "dosage check", "recorded": true},
      {"text": "Improved", "recorded": true},
      {"text": "Not recorded", "recorded": false}
    ]}
  ]
}
```

- **Rows** are the `row_field` values in the order the table reads them, so
  its sort applies. The first column heading is the `row_field` label and
  the first cell of each row is its value.
- **Columns** are the declared values of an enumerated `column_field`
  (`one_of` atoms, `Ash.Type.Enum`), in declaration order, kept even when
  no record has them. Any other `column_field` gives its values in read
  order.
- **Cells** hold the `cell_field` display text of the first record read at
  that row and column. A cell with no record, or whose record has no
  `cell_field` value, is `"recorded": false` with the text "Not recorded".
  A missing result is never shown as a value, nor as an empty string that
  reads like one. Renderers that style cells should key on `recorded`, not
  on the text.
- Rows always carry the three fields, whatever `fields` lists.
- The composition is a `Column` holding a header `Row` templated over
  `columns` and a `List` of `Row`s templated over `rows`, each templated
  over its `cells`. No record rows are templated.
- The grid is built from the page the table reads: filters, search and
  presets narrow it, and a page that splits a row's records shows that row
  partly. Give a matrix a page size that holds its grid.
- The initial data model and every records refresh after an action or a
  `"query"` action rewrite `/_matrix_<table>` beside the records. A
  records-only push (`encode_data_model(view, records, scope: :records)`)
  replaces `/records` alone, as it does for board totals.

Rules, checked at compile time and over composed surfaces: `:table` only;
`row_field`, `column_field` and `cell_field` all set, distinct, public
attributes of the table's resource, and among its `fields` when it declares
them; no `sections`, `row_layout`, `row_actions`, `bulk_actions` or
`editable`; and the three options only with `display :matrix`.

## Composed surfaces

An `AshA2ui.Dynamic` spec takes `"display": "timeline"` with `date_field`,
or `"display": "matrix"` with `row_field`, `column_field` and `cell_field`.
The same rules apply, and a declared timeline or matrix exports to a spec
that resolves back.
