# AshA2ui layout rules

Rules for the `group` and `row_layout` layout entities and for boards
(`display :board`). See the Layout and Multi-Section Surfaces topics for the
full contracts.

## Form groups

- Group form fields into labeled sections with `group` entities inside
  `component :form`:

  ```elixir
  group :scheduling do
    label "Scheduling"     # defaults to the humanized group name
    columns 2              # defaults to 1
    fields [:trial_days, :expires_at]
  end
  ```

- Every grouped field must be one of the form's fields and may belong to at
  most one group (compile-verified). Groups re-arrange containers only —
  inputs, `/form` bindings, `/errors/<field>`, and submit semantics are
  identical to ungrouped forms.
- Ordering contract: ungrouped fields render in place; a group renders whole
  at the position of its first member in the form's field order. Order the
  form's `fields` list (or `field ... order`) accordingly — don't expect
  groups to render in group-declaration order.
- Don't reach for `columns 3+` casually: the basic catalog cannot wrap, so
  wide grids stay wide on narrow clients.

## Card-style table rows

- Give a table the record-card shape (title + status badge header, labeled
  metadata grid) with the singleton `row_layout` entity:

  ```elixir
  row_layout do
    title :name
    badge :is_active
    badge_text true: "Active", false: "Inactive"
    meta [:slug, :trial_days]   # defaults to fields minus title/badge
    columns 2
  end
  ```

- `title`/`badge`/`meta` must reference the table's fields, each at most
  once (compile-verified). Row actions, prompts, `visible_when`, and the
  select button are unchanged — they move into the card header.
- The badge binds the computed `_badge_<field>` row key (display text), not
  the raw value: declare `badge_text` for boolean/enum values you want to
  read well; unmatched values humanize. The raw field value stays in the
  row for `select_row` and filters.
- Without a `row_layout`, rows stay flat cell Rows — both layouts are
  byte-identical to the pre-layout encoder when undeclared, so adding one
  never breaks existing renderers.

## Boards

- A board is a sectioned `:table` whose sections are the values of an
  attribute, laid out as lanes side by side. Declare it with `display :board`,
  a `row_layout` (lanes render cards) and a `sections` block **without** a
  `source`:

  ```elixir
  component :table, :board do
    display :board
    row_actions [:claim, :complete]

    row_layout do
      title :name
      badge :priority
    end

    sections do
      scope_by :status                      # Ash.Type.Enum or one_of
      values [:open, :claimed, :completed]  # optional subset + order
      labels open: "To do"                  # optional heading overrides
    end
  end

  action :claim do
    visible_when status: :open
    refreshes [:board]                      # template key = every lane
  end
  ```

- `scope_by` must have enumerable values (an `Ash.Type.Enum` type or a
  `one_of` constraint); `values` entries and `labels` keys must be among
  them; `label`/`value`/`sort`/`read_action` need a `source` and
  `values`/`labels` its absence; no value twice in `values`, no two values
  that sanitize to the same lane name (`:"in-progress"` / `:in_progress`)
  (all compile-verified).
- On a board, `limit` caps the number of **lanes**, not cards per lane, and
  may not be below the lane count. Set a lane's page size with the lane
  query's `page_size`.
- Moving a card = running a transition: a row action on the resource,
  gated by `visible_when` on the lane attribute, that refreshes the
  template key. There is no drag-and-drop; don't generate a generic
  "set status" action to fake one — the resource's own actions keep the
  state-machine rules.
- Each lane is an expanded table (`/records/<lane>`, `/query/<lane>`,
  `scope_by == value` ANDed onto every read, so a client filter cannot pull
  in another lane's records). Its heading total is the reserved
  `/_lane_total_<lane>` string, rewritten by action refreshes and `query`
  actions but not by a `scope: :records` push. Empty lanes stay on the
  board.
- Attach a `query` for per-lane pagination; lanes show query controls only
  when the query declares search, presets, filters or ranges.
- `display :list` (the default) keeps the stacked rendering, so source-less
  sections work without a board too.

## Avoid

- ❌ Expecting a real grid/wrap — "columns" is server-side chunking into
  Rows of equal-weight Columns.
- ❌ Styling through the DSL — spacing, colors, and card chrome belong to
  the renderer/theme, not the payload.
- ❌ Duplicating a field across `title`/`badge`/`meta` or across groups.
- ❌ Hardcoding one `:table` per status value — use a source-less `sections`
  block, so the lanes follow the attribute's declared values.
