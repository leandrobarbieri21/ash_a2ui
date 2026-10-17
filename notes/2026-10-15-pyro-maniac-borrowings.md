# Bulk actions, boards, wizard steps

Design record for three features whose vocabulary comes from PyroManiac
(<https://github.com/frankdugan3/pyro_maniac>, MIT, read at `main` @ `f390d17`,
2026-09-20). PyroManiac is an Ash UI DSL whose page DSL compiles into
`PyroManiac.Info` and leaves rendering to a separate library — the same split
as our DSL → `ResolvedView` → encoder → `ActionHandler`. We borrow the ideas
(kanban views, form steps, bulk actions over a selection), not the code. Each
feature is one work item and one PR; acceptance criteria are in
`.sdlc/acceptance/A2UI-104.yaml` (bulk), `A2UI-105.yaml` (boards) and
`A2UI-106.yaml` (steps). Contracts below are frozen when this note merges.

## Constraint: the A2UI catalog will not grow to meet us

The basic catalog (v0.9.1 and the v1.0 candidate) has no stepper, table,
board or calendar, and multi-select exists only as `ChoicePicker` over a
literal option list. Upstream closed the requests on 2026-09-21 — Stepper
(a2ui-project/a2ui#2672), rich/multi-select ChoicePicker (#2673), Table
(#2674) — with "create one of your own as part of a custom catalog". Open
#1745 (P1) notes that dynamic `List` children have no keys.

Consequences:

- Every feature here composes from basic components, so it works on both
  spec versions and with the basic catalog.
- Anything richer (drag-and-drop lanes, a stepper widget) goes into our own
  `admin_v1` catalog in a later item, never into a fork of the basic one.
- Per-row state lives **inside the row object** (a reserved key bound with a
  row-relative path). A List template cannot bind an absolute per-row path,
  and without keys the client cannot be trusted to keep row identity across
  rewrites.

## 1. Bulk actions (A2UI-104)

```elixir
component :table do
  row_actions [:approve, :reject]
  bulk_actions [:approve, :reject]
end

action :approve do
  refreshes [:table]
  visible_when status: :open
end
```

**DSL.** `bulk_actions` (list of atoms, default `[]`) on `:table`
components. Each name is an Ash action on the table's resource of type
`:update`, `:destroy` or `:action` (generic). Bulk actions reuse the `action`
entity: label, `refreshes`, `visible_when` and `via` all apply per record.

**Verifier rules.**

- Each `bulk_actions` entry names an existing update/destroy/generic action.
- A bulk action may not declare `prompt_fields` (one shared prompt for many
  records is a later item).
- Related tables (`resource` set) may not declare `bulk_actions`, as they may
  not declare `row_actions`.
- `bulk_actions` is not allowed on a table whose rows have no single primary
  key.

**Data model.**

- Every serialized row of a table with bulk actions carries
  `"_selected": false`. The encoder's `serialize_record` and the handler's
  `rows/3` must both add it, as they must stay byte-equal.
- `/bulk/<table>/result` holds the last outcome:
  `{"ok": n, "failed": n, "refused": n, "skipped": n, "errors": [...]}`.

**Rendering (basic composition).**

- A CheckBox bound to the row-relative path `_selected` in each row template
  (card header for `row_layout` cards, first cell otherwise).
- Above the list, a toolbar Row: one Button per bulk action, plus "Select
  page" and "Clear". The action Buttons send `bulk_invoke` with
  `{"action": name, "component": table, "records": {"path": records_path}}`
  and the usual carried `"query"`/`"contexts"` bindings. Select/Clear send
  `bulk_select` with `{"component", "selected": true|false, "records":
  {"path": records_path}}`, and the server rewrites the page's rows.
- The admin catalog keeps this subtree basic-composed, following the
  established feature-fallback rule (see `2026-09-07-admin-catalog-contract.md`).
  A selectable `DataGrid` is a later item.

**Handler: `bulk_invoke`.**

1. The action must be in the union of the tables' `bulk_actions`. Anything
   else is refused, the same as `invoke`'s allowlist.
2. Ids are the `id`s of the carried rows whose `_selected` is `true`.
   Nothing else in the carried rows is read. The list is capped at the
   table's page size (`max_page_size`, or the read's default limit).
   An empty selection is an error status, not a no-op success.
3. **Authorized re-read:** the table's read action with the table's
   context/section scope and `id in ^ids`, as the actor. Ids the read does
   not return are counted as `refused` and never touched. A forged id,
   another tenant's id or a row outside the current lane all land here.
4. Each re-read record is checked against the action's `visible_when`, using
   the same predicate as single-row enforcement. Failures count as `skipped`.
5. Each remaining record runs through the same dispatch as a single-row
   `invoke` (`via`, destroy, update or generic), one call per record. They do
   not share a transaction, so one failure does not roll back the others.
   This keeps policies, changes, hooks, notifications and `via` delegates
   identical to clicking each row. Selections are page-bounded, so the extra
   round trips are bounded too.
6. The handler writes `/bulk/<table>/result` and typed `/ui/feedback`
   ("Approved 4 of 5; 1 refused"), which is `warning` on partial success
   and `error` when nothing succeeded. Then it refreshes targets once, as `invoke` does.
   Nothing is refreshed when every record failed.

**Not exposed to agents.** Bulk actions are not added to the AG-UI tool
surface. One agent call fanning out to many writes is a separate decision.

## 2. Boards (A2UI-105)

A board is a sectioned table whose sections come from the values of an
attribute instead of the records of a source resource. It rides on
`sections`: no new component kind, so expansion, per-lane reads and
pagination, and refresh fan-out are reused unchanged.

```elixir
component :table, :board do
  display :board
  row_actions [:claim, :complete]
  row_layout do
    title :name
    badge :priority
  end
  sections do
    scope_by :status                      # lanes = enumerated values of :status
    values [:open, :claimed, :completed]  # optional: subset + order
    labels open: "To do"                  # optional: per-lane heading overrides
    limit 4
  end
end

action :claim do
  visible_when status: :open
  refreshes [:board]                      # template key → every lane
end
```

**DSL.**

- `sections.source` becomes optional. Without `source`, the lanes are the
  enumerated values of `scope_by`: an `Ash.Type.Enum`'s values, or an
  `:atom`/`:string` attribute's `one_of` constraint, in declaration order.
- `values` (list) picks a subset and an order. `labels` (keyword) overrides
  headings, which otherwise are the humanized value.
- `label`, `value` and `sort` remain source-only.
- `display :list | :board` (default `:list`) is a new `:table` option.

**Verifier rules.**

- Without `source`, `scope_by` must have enumerable values.
- `values` must be a subset of them.
- `labels` keys must be in `values` (or in the full value set).
- `label`/`value`/`sort` are invalid without `source`.
- `display :board` requires `sections` and a `row_layout`.

**Expansion.** `Sections.read_sections/2` gains a no-source clause that
synthesizes `%{value, label}` section records without a read. Runtime names
follow the frozen `<template_key>_<sanitized value>` contract. Each lane's
reads are scoped by `{scope_by, value}` through the existing `section.filter`.
An empty lane renders its empty state; the lane itself is never dropped.

**Rendering.**

- `display :board` lanes render side by side: a horizontal List/Row of lane
  Columns. Each Column has a heading with the lane label and its total, the
  lane's card list, and the lane's pagination.
- `display :list` keeps today's stacked rendering.
- The admin catalog falls back to basic composition for sectioned tables, as
  it does today.

**Moves.** A card moves when a transition action runs: row actions gated by
`visible_when` on the lane attribute, refreshing the template key. There is
no drag-and-drop in this item. It needs pointer events the basic catalog does
not have, so it belongs to an `admin_v1` `board` component later. That
component's drop event will still be an `invoke` of a declared transition,
validated server-side exactly like a button.

**Deliberately not borrowed.**

- PyroManiac's fractional-index ordering within a lane: a `priority` string
  with a Postgres rank function and a unique index. Our core depends only on
  `ash`.
- WIP limits, and swimlanes on a second axis (swimlanes reversed on
  2026-10-17, see the amendment below).
- PyroManiac's generated `move_action`. Our transitions are the resource's
  own actions, which keeps state-machine rules where they live.

**Amendment, 2026-10-17: swimlanes are in (A2UI-105B).** The list above
put "swimlanes on a second axis" out of scope. The clinic-demo owner has now
asked for one: the triage board should stay a horizontal kanban of stages,
split vertically by triage severity, each severity on its own coloured band.
Why adding them now is sound:

- *It needs no new machinery.* Lanes turned out to be ordinary expanded
  tables with one more filter. A swimlane cell is the same table with a
  second filter ANDed on, so expansion, per-cell reads and pagination, the
  scope guarantee against client filters, and template-key refresh fan-out
  are all reused. The runtime-name contract extends instead of changing:
  `<key>_<lane>` becomes `<key>_<lane>__<swimlane>` (a sanitized value
  never contains `__`; the verifier rejects the values with leading or
  trailing punctuation that could still make two cells meet), and a board
  without `swimlanes_by` encodes byte-for-byte as before (golden-tested).
- *The alternative is worse.* Without it, a host stacks one board per
  severity, which repeats the stage headers, does not align the stages, and
  needs one refresh target per board.
- *Colour stays out of the wire.* The basic catalog still has no colour
  props, so the tone travels as data (`/_swimlane_tone_<key>__<swimlane>`)
  in the `badge_tones` vocabulary, and the merged catalog paints it from
  theme tokens with AA contrast. Stock basic renderers show the same rows
  without colour, as they show badges without tones.

WIP limits and rank ordering within a lane stay out, for the reasons above.
The design is in the Boards section of
`documentation/topics/multi-section-surfaces.md`; the criteria are in
`.sdlc/acceptance/A2UI-105B.yaml`.

## 3. Wizard steps (A2UI-106)

```elixir
component :form do
  create_action :create

  step :who do
    label "Who"
    fields [:name, :email]
  end

  step :what do
    fields [:role, :team_id]
  end

  step :confirm do
    review? true
  end
end
```

**DSL.**

- `step` entities (`name`, `label`, `description`, `fields`, `review?`) on
  `:form` components, in order.
- A `review?` step has no fields and renders a read-only summary of `/form`.

**Verifier rules.**

- Every form field is in exactly one step.
- Step names are unique.
- `review?` is allowed only on the last step and only without `fields`.
- `step` and `group` are not mixed on one form (groups inside steps is a
  later item).
- A form with steps has at least two of them.

**Data model.**

- `/ui/wizard/index` (integer).
- `/ui/wizard/steps`: `[{"name", "label", "state": "done"|"current"|"todo"}]`
  for the progress header.
- `/ui/wizard/<step>_visible`: zero-or-one lists, the same trick as the
  `/ui/panel/*_visible` flags.
- `/form` is carried across steps unchanged. It is the one form.

**Handler.**

- `wizard_next` carries `/form` and the index. It builds the full changeset
  (`for_create`/`for_update` over the cast `/form` values) and keeps only the
  errors whose field belongs to the current or an earlier step.
  - If any remain, they go to `/errors/*` and the index stays.
  - Otherwise, the index advances and `/errors` clears.
  - Nothing is written to the data layer.
- `wizard_back` decrements without validating.
- The last step's primary button is the existing `submit_form`. If submit
  fails, the index jumps to the earliest step owning an erroring field. An
  error on no field stays on the last step with the status line.
- `start_create`, `cancel_record_task` and a successful submit reset the
  index to 0.

**Task panel.** `panel_state` labels the primary button "Next" before the
last step, then the existing "Create X" / "Save changes"; the panel's submit
gate opens on the last step. (Experience v1, under which the submit sat
behind its own wizard sentinel, was removed on 2026-10-16.)

**Scope note.** Linear, server-validated steps over one Ash action are
supported. Branching flows, uploads and steps that wait on background work
(polling a job) still belong in a LiveView; `what-is-ash-a2ui.md` says so.

## Navigation: noted, not built

PyroManiac's `nav` DSL compiles a tree, a flat item list and a
`route_manifest` of `[{path, module}]`. It filters items by
`Ash.can?(..., run_queries?: false)` against each page's primary read. That
is a fair description of what host applications already do with their own
surface registries. Navigation stays a host concern; ash_a2ui does not grow
a nav DSL.

## PyroManiac details we did not copy

At `f390d17`, three things in PyroManiac's docs disagree with its code:

- The kanban `priority` field is documented as an integer, but the
  transformer requires `:string`.
- The kanban read action is documented to accept `lane_value`, but no such
  argument is added.
- `combobox_*` options are documented as `autocomplete_*`.

None of these affects us. They are recorded so nobody "fixes" our design
toward the docs.
