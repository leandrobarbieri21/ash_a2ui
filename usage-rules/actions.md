# Actions: routing client envelopes into Ash

Every inbound A2UI `action` envelope must go through
`AshA2ui.ActionHandler.handle/3`. It validates the envelope, enforces the
DSL allowlist, invokes the Ash action with the actor, and maps errors onto
the reserved data-model paths. Calling Ash actions directly from transport
code skips all of that.

## `handle/3` contract

```elixir
AshA2ui.ActionHandler.handle(resource_or_ui_module, envelope,
  actor: current_user,
  tenant: tenant          # optional
  # authorize?: true      # the default — leave it on
)
# => {:ok, [updateDataModel, ...]} | {:error, [updateDataModel, ...]}
```

- The first argument is a resource using the `AshA2ui` extension or an
  `AshA2ui.Standalone` UI module — the same module you pass to
  `AshA2ui.Info.build_surface/2`.
- The envelope may be the full client->server message
  (`%{"version" => ..., "action" => %{"name" => ..., "context" => ...}}`)
  or a bare inner action map — both are accepted.
- Push the returned messages to the client **for both `{:ok, _}` and
  `{:error, _}`** — error messages carry the validation feedback the
  renderer must display.

## The core action names

The core envelope names are `"submit_form"`, `"invoke"`, `"prompt"`,
`"select_row"` and `"query"`. Feature-specific names exist only when the
surface declares the feature: the context actions (`ash_a2ui:contexts`),
the relationship-picker actions (`ash_a2ui:relationships`), `"edit_cell"`
(tables with an `editable` block — commits one field of one record through
the declared update action, with validation errors mirrored into the
failing row's `_error_<field>` key), `"report"` (`:report` components —
runs the declared generic action; `ash_a2ui:reports`), `"export"`
(components with an `export` block — answers with the `downloadFile`
callFunction; `ash_a2ui:reports`) and `"bulk_invoke"` / `"bulk_select"`
(tables with `bulk_actions` — see "Bulk actions" below). Don't invent new `action.name` values;
add a proper Ash action and expose it via `row_actions` instead.

- `"submit_form"` — context `%{"values" => %{...}, "recordId" => id | nil}`.
  No `recordId` runs the form's create action; with one, the update action.
  String-keyed values are cast against the target action's accepted
  attributes/arguments (no dynamic atom creation); unknown keys are silently
  dropped.
- `"invoke"` — context `%{"action" => name, "recordId" => id | nil}` (plus
  an additive `"component" => table_name` identifying the source table; the
  handler tolerates its absence). **The named action must be listed in the
  surface's `row_actions`** — that list is the server-side allowlist and the
  authorization surface for client-triggered actions. Anything not listed is
  rejected with a `/ui/status` error before Ash is ever called. Destroy,
  update and generic actions are supported; a generic action with a
  `:record_id` argument receives the context's `"recordId"`.

  **Update actions via `invoke` call the named action itself** with no
  params on the identified record — an argument-less "touch-style" update.
  Actions that need user input declare `prompt_fields` on their `action`
  entity: then (and only then) the invoke context's `"values"` map is
  filtered to the declared prompt fields, cast against the Ash action's
  arguments/accepts, and passed as params (`"values"` on prompt-less actions
  is ignored). Don't put an update action in `row_actions` expecting it to
  receive *form* values — it won't; form input belongs to `update_action`.

  If the action's entity declares `visible_when` conditions, the handler
  fetches the identified record and re-evaluates them on **every** invoke —
  a non-visible action is rejected via `/ui/status` no matter what the
  client rendered. Never rely on the rendering to hide a button; the
  handler enforcement is the guarantee.
- `"prompt"` — context `%{"action" => name, "recordId" => id}`. Sent by the
  trigger of a prompt Modal (an action with `prompt_fields`). No Ash write:
  the handler validates the allowlist + `visible_when`, pre-fills
  `/prompt/values/<action>` from the record, and clears `/errors`. The
  actual write is the subsequent `"invoke"` with `"values"`.
- `"select_row"` — context `%{"recordId" => id}`. Returns one
  `updateDataModel` populating `/form` with the record's values (edit-form
  population). The per-row Select button is emitted only on surfaces with
  a `:form` component — with nothing to populate it would be a dead
  control (row selection on formless master/detail surfaces is the
  `select_context` button instead).
- `"query"` — context `%{"query" => <the query state map>}` plus optional
  `"page"`/`"pageDelta"`. Requires the table to declare a `query` entity;
  every search/sort/filter/page value is validated against that allowlist
  and rejected via `/ui/status` when undeclared. Returns `updateDataModel`
  messages for `/records` and `/query`. On multi-table surfaces the context
  **requires** `"component" => table_name` and the messages target
  `/records/<name>` + `/query/<name>`. Full rules in `ash_a2ui:queries`.

## Reserved data-model paths

All follow-up messages are `updateDataModel` messages on these paths —
never invent ad-hoc paths or custom message types; renderers depend on
them:

- `/records` — the re-read table rows after a successful write (each row
  includes `"id"`). Multi-table surfaces scope refreshes per table at
  `/records/<component_name>`.
- `/form` — cleared to `%{}` on success; populated by `select_row`.
- `/errors/<field>` — per-field validation error text; `/errors` is cleared
  to `%{}` on success.
- `/ui/status` — human-readable lifecycle feedback (success text, rejection
  reasons, "not authorized").
- `/ui/action_result` — the map result of a map-returning generic action
  (an AshA2ui handler convention, not part of the A2UI spec).
- `/query` — the authoritative query state on query-enabled surfaces,
  written after `query` actions and query-aware success refreshes
  (multi-table surfaces: `/query/<component_name>` per query-attached
  table).
- `/prompt/values/<action>` — a prompt Modal's input values: pre-filled by
  `prompt`, cleared to `%{}` after a successful prompt `invoke`.
- `/bulk/<table>/result` — the last bulk run's outcome (`ok`, `failed`,
  `refused`, `skipped`, `errors`); rows of bulk tables carry `_selected`.

On `Ash.Error.Forbidden` only a `/ui/status` "not authorized" message is
emitted — no field errors, to avoid leaking policy details.

## Scoping refreshes with `action` entities

By default every success refreshes **every** table. On multi-section
surfaces, declare which tables an action's success rewrites:

```elixir
action :approve do
  refreshes [:new_items]    # only /records/new_items (+ /query/new_items)
end
```

Use it when a row action logically belongs to one section — refreshing
unrelated tables wastes reads and can visibly reset their pagination. The
`/form`/`/errors`/`/ui/*` follow-ups are never affected. Refresh targets and
action reachability are compile-time verified. `refreshes` may be omitted
when the entity only carries `prompt_fields`/`visible_when` — omitted means
"refresh every table" (the default).

## Prompts and conditional visibility on `action` entities

```elixir
action :decline do
  prompt_fields [:notes]                    # args/accepts of :decline, compile-verified
  prompt_title "Decline referral"           # optional Modal heading
  visible_when status: [:pending, :approved]
end
```

- `prompt_fields` renders the row action as a Modal (trigger button +
  inputs + Confirm) and freezes the `prompt`/`invoke "values"` wire
  contract above. Keep prompts to the action's real arguments — the handler
  filters everything else out anyway.
- `visible_when` is simple ANDed equality on public attributes or
  expression calculations (`nil` = is_nil, list = membership) —
  deliberately not a rules engine. Rendering hides the button per row
  (server-computed `"_actions"` / `"_visible_<action>"` row keys + a
  templated slot); the handler enforcement is mandatory and independent.
  Real authorization still belongs in Ash policies — `visible_when` is UX
  scoping inside the `row_actions` allowlist.

## Bulk actions

```elixir
component :table do
  row_actions [:approve]
  bulk_actions [:approve, :archive]   # update/destroy/generic, compile-verified
end
```

- `"bulk_invoke"` — context `%{"action" => name, "component" => table,
  "records" => <the carried rows>}` plus the usual `"query"`/`"contexts"`.
  The action must be in the surface's `bulk_actions` (and the table's own
  list) or it is refused before anything is read. Only the `"id"` of rows
  whose `"_selected"` is `true` is used; an empty selection is an error
  and more than one page (the query's `max_page_size`) is refused.
- The ids are **re-read** through the table's read under its active query
  preset (from the carried `"query"`, else `default_preset`: a
  `read_action` preset swaps the read, a `filter` preset ANDs on) with its
  context and section scope, as the actor. Ids the read does not return
  (forged, hidden by policy, out of scope or preset) count as `refused` and
  never reach the action. Each remaining record is checked against
  `visible_when` (`skipped` when it fails) and then runs through the same
  dispatch as `invoke`, one call per record, without a shared transaction.
- A **generic** bulk action must declare `argument :record_id` (compile-time
  verified): each call gets the record's id there.
- The handler writes `/bulk/<table>/result` and a status line, sends
  typed v2 feedback (`"warning"` on partial success, `"error"` when
  nothing was written) and refreshes the targets once. Nothing is
  refreshed when nothing was written.
- `"bulk_select"` — context `%{"component", "selected" => true | false}`:
  the server re-reads the page and rewrites its rows with `_selected` set
  (Select page / Clear). Carried rows are never echoed back. On a table
  without a query, Select page marks at most the bulk cap's worth of rows.
- No `prompt_fields` on bulk actions, no bulk actions on related tables or
  `display :board` tables,
  and bulk actions are not exposed as AG-UI tools. Full contract in the
  bulk-actions topic.

## Rules

- Keep `row_actions` and `bulk_actions` minimal — they are allowlists, not
  documentation. Never mirror every action on the resource.
- Always pass `actor:` (and `tenant:` where relevant); `authorize?` defaults
  to `true` and should stay on.
- On a resource with **no policies**, `authorize?: true` is a no-op —
  transport-level authentication is the only gate. Say so in review rather
  than assuming enforcement.
- Values are serialized JSON-safe on the way out (dates/datetimes to
  ISO 8601, decimals to strings, atoms to strings) — don't re-serialize.
