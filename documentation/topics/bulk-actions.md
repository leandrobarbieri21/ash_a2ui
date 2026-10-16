# Bulk Actions

A table can run an action over a selection of its rows: approve five
referrals at once, archive a page of stale tickets. You declare which actions
are allowed in bulk with `bulk_actions`. Each row gets a checkbox, the table
gets a toolbar, and the server runs the action once per selected record,
exactly as if the user had clicked each row's button.

Prior art: this feature follows
[PyroManiac](https://github.com/frankdugan3/pyro_maniac), an Ash UI DSL
that offers bulk actions over a row selection. Like ash_a2ui, its DSL
compiles into an introspection layer and leaves rendering to a separate
library. We borrowed the idea, not the code. The design record is
`notes/2026-10-15-pyro-maniac-borrowings.md`, section 1.

## Declaring bulk actions

```elixir
component :table do
  fields [:name, :status]
  query :default
  row_actions [:approve, :reject]
  bulk_actions [:approve, :reject]
end

action :approve do
  refreshes [:table]
  visible_when status: :open
end
```

`bulk_actions` is a list of update, destroy or generic actions on the
table's resource. A bulk action does not have to be a row action too, but it
usually is. The action's `action` entity applies per record:

- `visible_when` is checked on each selected record. Records that fail it
  are skipped, not written.
- `via` delegates each record to the host function, one call per record.
- `refreshes` picks the tables refreshed once the run ends.

Compile-time rules (`AshA2ui.Verifiers.VerifyBulkActions`):

- Only `:table` components may declare `bulk_actions`.
- Every entry names an existing update, destroy or generic action. Read and
  create actions are refused.
- A generic bulk action must declare a `:record_id` argument. Each call
  receives the id of the record it runs for; without the argument every
  call would run with the same empty input and never learn which record it
  is for.
- A bulk action may not declare `prompt_fields`. One shared prompt for many
  records is not supported.
- A related table (`resource` set to another resource) may not declare
  `bulk_actions`, for the same reason it may not declare `row_actions`.
- The resource must have a single primary key, because the selection is a
  list of row ids.
- A `display :board` table may not declare `bulk_actions`. Board lanes
  render without the selection toolbar.

## What renders

Everything is composed from the basic catalog, so it works on v0.9.1 and
v1.0 and with any basic-catalog renderer:

- Each row template gets a `CheckBox` bound to the row-relative path
  `_selected`. On flat rows it is the first child of the row's cell Row
  (`record_row<sfx>_selected`); on `row_layout` cards it leads the card
  header.
- Above the list, a toolbar Row (`bulk<sfx>_toolbar`) holds one Button per
  bulk action (`bulk<sfx>_action_<action>_button`, labelled with the
  humanized action name), then **Select page** (`bulk<sfx>_select_page_button`)
  and **Clear** (`bulk<sfx>_clear_button`). The `_action_` segment keeps an
  action named `:clear` or `:select_page` from colliding with the fixed
  controls.

`<sfx>` is the multi-table suffix (`""` on a single-table surface,
`"_<table>"` otherwise), as everywhere else.

The checkbox state lives inside the row object. An A2UI List template
cannot bind an absolute per-row path, and dynamic List children have no
keys, so the selection travels with the row it belongs to.

Under `catalog: :admin_v1` a table with bulk actions stays basic-composed,
like tables with sections, exports or inline editing (see the admin catalog
contract note). A selectable `DataGrid` is not part of this release.

## Data model

| Path | Contains |
|---|---|
| row key `_selected` | `false` on every row the server writes (initial render, refreshes); the CheckBox toggles it on the client |
| `/bulk/<table>/result` | The last outcome: `{"ok", "failed", "refused", "skipped", "errors"}`, where `errors` is a list of `{"id", "message"}` |

Rows of tables without bulk actions carry no `_selected` key, and surfaces
without bulk actions carry no `/bulk` state.

## The `bulk_invoke` action

The action Buttons send:

```json
{
  "name": "bulk_invoke",
  "context": {
    "action": "approve",
    "component": "table",
    "records": {"path": "/records"},
    "query": {"path": "/query"},
    "contexts": {"path": "/context"}
  }
}
```

`"query"` and `"contexts"` are present when the surface has a query or
contexts, as on every write action. The handler then:

1. Checks the action against the union of the tables' `bulk_actions`, and
   against the target table's own list. Anything else is refused before
   any record is read.
2. Takes the `"id"` of every carried row whose `"_selected"` is `true`.
   Nothing else in the carried rows is read. An empty selection is an
   error. A selection larger than one page is refused: the cap is the
   table query's `max_page_size`, otherwise the read action's pagination
   `default_limit`, otherwise 100.
3. Re-reads those ids through the read the table performs under its
   active query preset, with the table's context and section scope, as the
   actor. The preset comes from the carried `"query"` state, parsed as a
   refresh parses it (a missing or invalid state means the query's
   `default_preset`). A `read_action` preset re-reads through that action,
   so bulk buttons work on a "deleted" view; a `filter` preset ANDs its
   conditions on. Search, filters and paging are not re-applied: they
   narrow what the user looks at, the preset decides which read the rows
   come from. Ids the read does not return are counted as `refused` and
   never reach an action. That covers a forged id, an id the actor's
   policies hide, an id outside the selected context, lane or preset, and
   an id that does not cast to the primary key's type.
4. Checks each re-read record against the action's `visible_when`, with the
   same predicate a single-row `invoke` uses. Failures count as `skipped`.
5. Runs each remaining record through the same dispatch as a single-row
   `invoke` (`via`, destroy, update or generic), one call per record. A
   generic action receives the record's id as its `:record_id` argument.
   Records do not share a transaction, so one failure does not roll back
   the others. Policies, changes, hooks and notifications behave exactly
   as they do for a single click.
6. Writes `/bulk/<table>/result` and a status line such as
   `"Approve: 4 of 5 selected records done; 1 refused."`. When at least one
   record was written it also sends the usual success follow-ups and
   refreshes the target tables once (rows come back with `_selected`
   false). When none was, it returns an error status and refreshes
   nothing.

The typed `/ui/feedback` kind is `"success"` when every
selected record was written, `"warning"` on partial success and `"error"`
when nothing was written. On v1.0 surfaces the `actionResponse` value
carries the result map under `"result"`.

## The `bulk_select` action

**Select page** and **Clear** send `bulk_select` with
`{"component", "selected": true | false, "records": {"path": ...}}` plus the
same `"query"`/`"contexts"` bindings. The server re-reads the table exactly
as a refresh would (current query state, context scope, as the actor) and
rewrites its rows with `_selected` set. It never echoes the carried rows
back, so a forged row cannot appear in the table.

A table with a query shows at most one page, so Select page marks every
row. A table without a query reads all its rows at once; there Select page
marks only the first rows up to the bulk cap (step 2 above) and says so in
the status line ("Selected the first 100 of 140 records: ..."), so the
selection it leaves is one a bulk run accepts.

## Limits

- One page at a time. Selecting across pages, or "everything matching this
  filter", is not supported.
- No prompt for bulk actions.
- Bulk actions are not added to the AG-UI tool surface. Letting one agent
  call fan out to many writes is a separate decision.
- Declared surfaces only: the dynamic surface spec has no `bulk_actions`
  vocabulary, so `AshA2ui.Dynamic` imports report it as a rejection.
