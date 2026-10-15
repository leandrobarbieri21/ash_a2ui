# Layout

By default AshA2ui renders the simplest protocol-honest structure: each table
record is a `Card` over one flat `Row` of caption-labeled cells, and forms
are one vertical `Column` of labeled inputs. Two declarative layout entities
upgrade that structure without touching the wire contract: `group` (labeled
N-column form sections) and `row_layout` (card-style table rows with a
title/badge header and a metadata grid). Surfaces that declare neither emit
exactly the same payload as before — both features are purely additive.

The A2UI v0.9.1 basic catalog has no grid component; grids are expressed the
way the spec suggests — `Row`s of equal-`weight` `Column`s (the catalog's
`weight` property is flex-grow-like and only valid on direct children of a
`Row`/`Column`). AshA2ui chunks fields into rows of N and pads the last row
with empty spacer `Column`s so cells stay aligned. Renderers own all actual
styling; the encoder only ships structure and variants.

## Form groups

A `group` declares a labeled section of form fields laid out in an N-column
grid:

```elixir
component :form do
  fields [:name, :slug, :trial_days, :expires_at, :is_active]
  create_action :create
  update_action :update

  group :details do
    label "Details"
    columns 2
    fields [:name, :slug]
  end

  group :scheduling do
    columns 2
    fields [:trial_days, :expires_at]
  end
end
```

- `fields` (required) — the form fields the group renders, in the group's
  declaration order. Every entry must be one of the form component's
  (declared or inferred) fields, and no field may belong to more than one
  group — both verified at compile time.
- `label` — the section heading; defaults to the humanized group name.
- `columns` (default `1`) — grid columns. Fields are chunked into rows of
  this many equal-weight columns.

### What the encoder emits

Each group renders as a `Card` (`form_group_<name>`) whose child `Column`
(`form_group_<name>_body`) holds a heading `Text` (variant `h3`) above the
grid: one `Row` per chunk (`form_group_<name>_row_<i>`), each cell a
`weight: 1` `Column` (`form_group_<name>_cell_<field>`) containing the
field's **unchanged** input and error components (`form_input_<field>` /
`form_select_<field>` + `form_error_<field>`). Uneven last rows are padded
with empty `form_group_<name>_spacer_<i>_<j>` columns. Single-column groups
skip the grid wrappers and hold the input/error pairs directly.

Groups only re-arrange containers — inputs, error bindings, `/form` paths,
validation, and the submit contract are all identical to ungrouped forms.

### Ordering contract

The form's children follow the form's effective field order (after `order` /
`hidden` normalization):

- an **ungrouped** field renders its input/error pair in place,
- a **group** renders — whole, in the group's own field order — at the
  position of its first member in the form's field order; its later members
  are skipped where they would otherwise appear.

Nested forms and the submit button follow all fields, as before. Hidden
fields drop out of groups exactly as they drop out of the form.

## Wizard steps

A form can also be split into pages with `step` entities (Back/Next over the
one form, with server-side validation per step and an optional review
step). Steps are not mixed with groups on one form. See
[Wizard Steps](wizard-steps.md).

## Card-style table rows (`row_layout`)

A `row_layout` upgrades a table's records from flat cell rows to cards with
a title/badge header and a labeled metadata grid — the shape of a typical
admin "record card":

```elixir
component :table do
  fields [:name, :slug, :referral_type, :trial_days, :is_active]
  read_action :read
  row_actions [:generate_webhook_secret]

  row_layout do
    title :name
    badge :is_active
    badge_text true: "Active", false: "Inactive"
    meta [:slug, :referral_type, :trial_days]
    columns 3
  end
end
```

- `title` (required) — the field rendered as the card heading. Honors the
  field's `format`.
- `badge` — a field rendered as a status badge in the header. See "Badge
  text" below.
- `badge_text` — display text per badge value (keyword list, so it matches
  atom and boolean values). Unmatched values fall back to the humanized
  value.
- `meta` — the fields in the labeled metadata grid, in order. Defaults to
  the table's fields minus `title` and `badge`.
- `columns` (default `2`) — metadata grid columns.

`title`, `badge`, and every `meta` entry must be among the table's fields,
and no field may be referenced twice — verified at compile time.

### What the encoder emits

The `List` template still points at `record_row<suffix>` (multi-table
surfaces infix the table name as everywhere else), but the row becomes:

- `record_row` — a `Card` over `record_row_body` (a `Column`),
- `record_row_header` — a `Row` (`justify: spaceBetween`, `align: center`)
  of the title `Text` (variant `h4`, `weight: 1`) and `record_row_header_right`
  — a `Row` of the badge `Text` (variant `caption`, when declared), the
  row-action anchors, and the `row_select_button` (surfaces with a `:form`
  component only — formless surfaces omit it),
- `record_row_meta_row_<i>` — the metadata grid: each cell a `weight: 1`
  `Column` (`record_row_meta_cell_<field>`) of a caption `Text` with the
  field's label over a `Text` bound to the value (honoring `format`).

Row actions, prompts, `visible_when` slots, and the select button work
unchanged — only their placement moves into the card header.

### Badge text

Raw field values often make poor badges (`true`, `pending_review`). The
badge `Text` therefore binds a **computed row key** — `_badge_<field>` —
served alongside the record fields (like the `_actions` / `_visible_<action>`
visibility keys): the `badge_text` entry matching the value when declared,
else the humanized value (`:pending_review` → `"Pending review"`,
`true` → `"True"`), and `""` for `nil`. The raw field value stays untouched
in the row, so `select_row` form population and filters are unaffected.
Refreshes written by the action handler serialize the key identically.

## Protocol constraints worth knowing

- **No wrap, no real grid** — the basic catalog's `Row` cannot wrap, so
  "N columns" means server-side chunking. Pick `columns` for the narrowest
  client you target. Boards (`display :board`) therefore lay their lanes
  out in a horizontal `List`, not a `Row` (see
  [Multi-Section Surfaces](multi-section-surfaces.md)).
- **`weight` placement** — only legal on direct children of a `Row`/`Column`;
  the encoder confines it to grid cells and the header title.
- **Badges are `Text`** — the catalog has no chip/badge component; the
  `caption` variant plus the renderer's theme is the protocol-honest
  expression.
- **Icons are not emitted** — the catalog `Icon` supports only a fixed name
  enum (or raw SVG paths); mapping arbitrary domain fields to icons is a
  renderer/theming concern, not something the encoder can do generically.
