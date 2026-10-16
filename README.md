<!--
Badges: the hex.pm / hexdocs badges are placeholders until the first
`mix hex.publish` (see SUBMISSION.md). The CI badge is live once the repo is
pushed to GitHub.
-->

![Elixir CI](https://github.com/lukegalea/ash_a2ui/actions/workflows/elixir.yml/badge.svg)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_a2ui.svg)](https://hex.pm/packages/ash_a2ui)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/ash_a2ui)

# AshA2ui

Declare a UI surface on an [Ash](https://ash-hq.org) resource and get a
standards-based, agent-ready UI over the wire — no templates, no components,
no hand-written JSON.

AshA2ui is an Ash extension that generates
[A2UI (Agent to UI)](https://github.com/a2ui-project/a2ui) protocol
payloads — **v0.9.1** (the default) or **v1.0 (RC)** per surface — directly
from your Ash resources. You describe *what* the surface
shows (a table, a form, per-row actions) in a small `a2ui` DSL block; AshA2ui
derives the rest from what your resource already knows — attributes, types,
actions, policies — and emits the A2UI message stream that any A2UI renderer
(such as [`@a2ui/lit`](https://www.npmjs.com/package/@a2ui/lit) or
[`@a2ui/react`](https://www.npmjs.com/package/@a2ui/react)) turns into a live
UI. Client interactions come back as A2UI `action` envelopes and are routed
into your Ash actions with full actor/authorization support.

To our knowledge AshA2ui is the **first framework with an executable A2UI
1.0 conformance suite**: the v1.0(-RC) schemas, basic catalog, and the
spec's own test cases are vendored at a pinned commit and run in CI, and
every v1.0 message the encoders and action handler emit is validated
against them — plus targeted tests for the semantic rules schemas can't
express. Opt in per surface with `spec_version "1.0"` and get v1.0's UX
upgrades — single-message surfaces, per-action `actionResponse` feedback,
`callFunction` — with v0.9.1 output staying byte-identical. See
[A2UI 1.0](documentation/topics/a2ui-1-0.md).

Why this exists: in the agent era, "the UI" is increasingly something a server
(or an agent) *describes* and a remote canvas renders — chat surfaces, agent
canvases, embedded panels, cross-platform clients. Ash resources already carry
the richest machine-readable description of your domain. AshA2ui closes the
gap between the two.

- **Protocol core depends only on `ash`.** The DSL → `ResolvedView` → encoder
  → `ActionHandler` pipeline is transport-agnostic plain functions.
- **Batteries-included LiveView transport.** When `phoenix_live_view` is
  present, `AshA2ui.LiveRenderer` gives you a complete LiveView that pushes
  A2UI messages to a shipped JS hook hosting `<a2ui-surface>`, routes actions
  back, and live-refreshes the data model from `Ash.Notifier.PubSub`.
- **Plain JSON endpoints work too.** A controller that returns
  `AshA2ui.Info.build_surface/2`'s message list is a complete alternative
  transport.
- **Compile-time verifiers.** Referencing a field or action that doesn't
  exist fails at compile time, not in production — strictness matters more
  when you're emitting a wire protocol.

> **Status:** under active development, not yet published to hex.pm. APIs may
> change until v0.1.0 is tagged.

## Installation

With [igniter](https://hexdocs.pm/igniter) (recommended):

```bash
mix igniter.install ash_a2ui
```

Or manually — add the dependency:

```elixir
def deps do
  [
    {:ash_a2ui, "~> 0.1"},
    # optional, for the LiveView transport:
    {:phoenix_live_view, "~> 1.0"}
  ]
end
```

then add `:ash_a2ui` to your `.formatter.exs` so `mix format` understands the
DSL:

```elixir
[
  import_deps: [:ash_a2ui],
  plugins: [Spark.Formatter]
]
```

### Agent usage rules

AshA2ui ships LLM usage rules (`usage-rules.md` plus the
`usage-rules/actions.md`, `usage-rules/ag-ui.md`, `usage-rules/contexts.md`,
`usage-rules/dynamic.md`, `usage-rules/layout.md`,
`usage-rules/liveview.md`, `usage-rules/queries.md`,
`usage-rules/relationships.md`, `usage-rules/reports.md`, and
`usage-rules/zero-jank.md` sub-rules)
compatible with
[`usage_rules`](https://hexdocs.pm/usage_rules). To sync them into your
project's AGENTS.md, add `{:usage_rules, "~> 1.1", only: [:dev]}` and
configure it in your `mix.exs` project config:

```elixir
def project do
  [
    # ...
    usage_rules: [
      file: "AGENTS.md",
      usage_rules: [:ash_a2ui]
    ]
  ]
end
```

then run:

```bash
mix usage_rules.sync
```

`:ash_a2ui` inlines the main rules and all sub-rules. Use
`"ash_a2ui:actions"` / `"ash_a2ui:liveview"` / `"ash_a2ui:queries"` /
`"ash_a2ui:relationships"` / `"ash_a2ui:layout"` to pull in a single
sub-rule, or `{:ash_a2ui, sub_rules: []}` for the main rules only.

## Quickstart

### Authoring mode 1: on the resource

```elixir
defmodule MyApp.Support.Ticket do
  use Ash.Resource,
    domain: MyApp.Support,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshA2ui]

  attributes do
    uuid_primary_key :id
    attribute :subject, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :closed]],
      default: :open

    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    surface_id "tickets"

    component :table do
      fields [:subject, :status, :inserted_at]
      read_action :read
      row_actions [:update, :destroy]
    end

    component :form do
      fields [:subject, :status]
      create_action :create
      update_action :update
    end

    field :inserted_at do
      label "Created"
      format :date
    end
  end
end
```

### Authoring mode 2: a standalone UI module

Keep UI metadata out of shared domain resources (or define multiple surfaces
for one resource) with `AshA2ui.Standalone`:

```elixir
defmodule MyApp.UI.TicketUI do
  use AshA2ui.Standalone

  a2ui do
    for_resource MyApp.Support.Ticket
    surface_id "tickets"

    component :table do
      fields [:subject, :status]
      row_actions [:update]
    end
  end
end
```

Standalone modules are accepted anywhere a resource is:
`AshA2ui.Info.build_surface(MyApp.UI.TicketUI, actor: user)`.

### Search, filtering, sorting, pagination

Tables get server-enforced querying through a named `query` allowlist — the
client references it by name and can only use what you declare (arbitrary
client sort/filter params are rejected before Ash is called):

```elixir
a2ui do
  query :default do
    search_fields [:subject, [:requester, :email]]  # attrs or relationship paths, ci-contains, OR'd
    sortable [:subject, :inserted_at]
    filters [:status]                 # equality filters (expression calcs allowed)
    default_sort inserted_at: :desc
    page_size 25
    max_page_size 100
    default_preset :active

    preset :active do                 # composite predicates, selected by NAME
      filter deleted_at: nil
    end

    preset :deleted do
      read_action :deleted            # escape hatch for richer predicates
    end
  end

  component :table do
    fields [:subject, :status, :inserted_at]
    query :default
  end
end
```

The encoder emits the search field, preset + filter pickers, and pagination
buttons; the `"query"` action validates every request against the allowlist
and answers with `/records` + `/query` data-model updates. Clients never
send predicates — presets travel as names only. See
[Queries and Pagination](documentation/topics/queries-and-pagination.md).

### Row actions with prompts and conditional visibility

Row actions can collect arguments through a Modal prompt and show/hide per
row from record state — enforced server-side on every invoke:

```elixir
a2ui do
  component :table do
    fields [:code, :status]
    row_actions [:approve, :decline]
    query :default
  end

  action :approve do
    visible_when status: :pending     # per-row; handler re-checks on invoke
  end

  action :decline do
    prompt_fields [:notes]            # must be args/accepts of :decline
    prompt_title "Decline referral"
    visible_when status: [:pending, :approved]
  end
end
```

`:decline` renders as a `Modal` whose Confirm sends `invoke` with a
`"values"` map (filtered to the declared prompt fields, cast against the
action's arguments); validation errors land on `/errors/notes` inside the
Modal. See
[Actions and Authorization](documentation/topics/actions-and-authorization.md).

### Multiple table sections with scoped refreshes

Name extra `:table` components to build multi-section surfaces (review
dashboards, split lists). Each table gets its own read action, fields, and
query; `action ... refreshes` limits which sections a row action's success
rewrites. Calculation and aggregate fields render like attributes:

```elixir
a2ui do
  for_resource MyApp.Review.Item
  surface_id "review"

  component :table, :new_items do
    fields [:name, :occurrence_count]    # occurrence_count: an aggregate
    read_action :new_items
    row_actions [:approve, :dismiss]
    query :new_q
  end

  component :table, :done_items do
    fields [:name, :state]
    read_action :done_items
  end

  query :new_q do
    search_fields [:name]
    sortable [:name, :occurrence_count]  # aggregates are sortable
  end

  action :approve do
    refreshes [:new_items]               # success rewrites only /records/new_items
  end
end
```

Multi-table surfaces scope the data model per table
(`/records/<component_name>`, `/query/<component_name>`); single-table
surfaces are unchanged. See
[Multi-Section Surfaces](documentation/topics/multi-section-surfaces.md).

### Relationships

`belongs_to` form fields render as selects automatically — a form field whose
name matches the relationship's `source_attribute` becomes a `ChoicePicker`
with options loaded from the destination (actor/tenant-scoped, policies
apply). Table columns can read through loaded relationships with `source`:

```elixir
relationships do
  belongs_to :author, MyApp.Blog.Author, public?: true
end

a2ui do
  component :table do
    fields [:title, :author_email]
  end

  component :form do
    fields [:title, :author_id]       # author_id -> ChoicePicker, no DSL needed
    create_action :create
    update_action :update
  end

  field :author_email do
    label "Author email"
    source [:author, :email]          # column read through the loaded relationship
  end
end
```

Option labels default to the first existing public attribute of
`[:name, :title, :label, :username, :email]` on the destination (else its
primary key); `option_label` / `option_value` / `option_sort` /
`option_limit` override the defaults, and `relationship` handles
action-argument fields. Everything is verified at compile time. See
[Relationship Rendering](documentation/topics/relationships.md).

For destinations with thousands of records, `option_search` makes the select
**searchable** (search input + live result list instead of a static picker),
and `nested_form` edits related records inside the form — pick-and-attach or
inline sub-form rows, inferred from the action's `manage_relationship`
options:

```elixir
a2ui do
  component :form do
    fields [:subject, :author_id]
    create_action :create
    update_action :update

    nested_form :notes do          # manage_relationship(:notes, type: :direct_control)
      fields [:body, :rating]      #   -> inline sub-form rows (create/update/destroy)
    end

    nested_form :tags do           # manage_relationship(:tags, type: :append_and_remove)
      option_search [:name]        #   -> searchable pick-and-attach with remove buttons
    end
  end

  field :author_id do
    option_search [:name, :email]  # searchable select over the Author destination
  end
end
```

### Layout: form groups and card-style rows

Forms group fields into labeled N-column sections, and tables can render
records as cards — a title/badge header over a labeled metadata grid —
instead of flat cell rows. Both are structure-only (Rows of equal-weight
Columns; the renderer owns styling) and byte-identical to the flat output
when undeclared:

```elixir
a2ui do
  component :table do
    fields [:name, :slug, :trial_days, :is_active]

    row_layout do
      title :name
      badge :is_active
      badge_text true: "Active", false: "Inactive"
      meta [:slug, :trial_days]      # defaults to fields minus title/badge
      columns 2
    end
  end

  component :form do
    fields [:name, :slug, :trial_days, :expires_at]
    create_action :create
    update_action :update

    group :details do
      columns 2
      fields [:name, :slug]
    end

    group :scheduling do
      label "Scheduling"
      columns 2
      fields [:trial_days, :expires_at]
    end
  end
end
```

Group membership and `title`/`badge`/`meta` references are verified at
compile time. See [Layout](documentation/topics/layout.md) for the emitted
component tree, the ordering contract, and the `_badge_<field>` convention.

### Building the surface

```elixir
messages = AshA2ui.Info.build_surface(MyApp.Support.Ticket, actor: current_user)
# => [
#   %{"version" => "v0.9.1", "createSurface" => %{"surfaceId" => "tickets", ...}},
#   %{"version" => "v0.9.1", "updateComponents" => %{...}},
#   %{"version" => "v0.9.1", "updateDataModel" => %{...}}
# ]
```

Records are loaded through the resource's read action with `authorize?: true`
and your `actor:`/`tenant:` — policies apply exactly as everywhere else in
Ash.

### The experience layer

Every surface composes through the experience layer (`AshA2ui.Experience`):
an h1 title, a record **task panel** (browse / create / view / edit) driven
by the `start_create` / `view_record` / `start_edit` / `cancel_record_task`
client actions, **View** / **Edit** row controls (View only on surfaces with
a form, Edit only with a declared `update_action`, neither on a related
table), a **Create <Resource>** button on create-capable surfaces, pagination
that hides when there is one page, data-driven empty states, and typed
feedback for every action outcome at `/ui/feedback` (`kind` + `message`).
View is read-only (`/ui/panel/record`); edit is the explicit transition onto
the form buffer. Every detail of the reserved `/ui/*` state, the sentinels
and the task modes is documented on the `AshA2ui.Experience` moduledoc.

> **Removed (breaking):** the `experience_version` setting, the
> pre-experience composition it pinned (the always-visible form with a
> "Save" button and a per-row "Select" button), the `select_row` action and
> the `/ui/status` path. Drop `config :ash_a2ui, :experience_version, ...`
> from your config, bind status text to `/ui/feedback/message` instead of
> `/ui/status`, and send `start_edit` (to load a record into the form) or
> `view_record` (to show it read-only) instead of `select_row`. See the
> CHANGELOG.

### Admin catalog

`config :ash_a2ui, :catalog, :admin_v1` selects the semantic admin catalog
(the default is `:basic`; `AshA2ui.Experience.admin?/0`): surfaces are
emitted as an `entityPage` of `dataGrid` (with `emptyState` / `pagination`
children and destructive-confirmed row actions), a `recordPanel`
(`fieldDisplay` for view mode, `formSection` + `actionBar` for
create/edit), and a `statusBanner` bound to `/ui/feedback` — declared in
`priv/a2ui/admin_v1/catalog.json`. Advanced-feature subtrees (sections,
reports, export, editable, nested forms, bulk actions, wizard steps,
boards) stay basic-composed, and query states carry plain boolean
pagination props alongside the pagination sentinels. The default `:basic`
catalog leaves the output unchanged. The Lit renderer registration ships
separately in `priv/js/ash_admin_catalog.js`
(`createAshAdminCatalog(deps)`), a plain ES module consumed by the host's
bundler.

## Transports

### LiveView (batteries included)

```elixir
defmodule MyAppWeb.TicketA2uiLive do
  use AshA2ui.LiveRenderer,
    ui: MyApp.UI.TicketUI,
    actor_fn: & &1.assigns.current_user
end
```

That's the whole LiveView. On mount it subscribes (when `:pubsub` is
configured), builds the surface as an async task — the page renders
immediately and the shipped JS hook's skeleton shows until the first tree
hydrates — and pushes the messages to the shipped JS hook
(`priv/js/ash_a2ui_hook.js`) hosting `<a2ui-surface>`; client `action`
envelopes arrive as the `"a2ui:action"` event and are routed through
`AshA2ui.ActionHandler`; and if the resource has
`Ash.Notifier.PubSub` configured, the LiveView subscribes on mount and pushes
`updateDataModel` refreshes when records change — live refresh across browser
tabs for free.

See the
[Getting Started tutorial](documentation/tutorials/getting-started-with-ash-a2ui.md)
for the router and JS wiring, and
[Rendering Clients](documentation/topics/rendering-clients.md) for the full
hook contract.

Making the surface match your app's design system is covered in
[Theming](documentation/topics/theming.md): the package ships a neutral
`--a2ui-*` CSS-variable theme (`priv/js/ash_a2ui_theme.css`), a merged
component catalog whose single-choice ChoicePicker is a native `<select>`
(`priv/js/ash_a2ui_catalog.js`), and hook support for wiring
`@a2ui/markdown-it` so headings render as headings.

### Plain JSON endpoint

Transport-agnosticism proof — a read-only surface is just a controller:

```elixir
defmodule MyAppWeb.A2uiController do
  use MyAppWeb, :controller

  def tickets(conn, _params) do
    messages =
      AshA2ui.Info.build_surface(MyApp.UI.TicketUI,
        actor: conn.assigns.current_user
      )

    json(conn, messages)
  end
end
```

Feed the response to any A2UI renderer. Mutations can be posted back as
`action` envelopes to a matching endpoint that calls
`AshA2ui.ActionHandler.handle/3`.

## Positioning: is this the right tool?

Honest comparison — each of these is the better choice in its own lane:

| | AshA2ui | [AshAdmin](https://hexdocs.pm/ash_admin) | [AshSDUI](https://github.com/FoundryStack/ash_sdui) | [Backpex](https://hexdocs.pm/backpex) |
|---|---|---|---|---|
| What it is | Ash resources → A2UI wire protocol | Drop-in admin UI for all your resources | Server-driven UI runtime inside LiveView | LiveView admin panel builder (Ecto) |
| Output | JSON messages for any A2UI renderer | Rendered LiveView pages | Rendered LiveView pages | Rendered LiveView pages |
| Client | `@a2ui/lit`, `@a2ui/react`, agent canvases, anything speaking A2UI | Browser only | Browser only | Browser only |
| Best when | UI must cross a wire: agent surfaces, embedded panels, non-Phoenix clients, multiple frontends | You want a full internal admin in minutes with zero per-resource config | You want dynamic layouts/recipes rendered server-side in LiveView | You want a polished, deeply customizable admin and are Ecto-first |
| Customization | DSL + roadmap `overrides:`; renderer owns look & feel | Resource-level config | Recipes, layout persistence, Storybook | Full HEEx control |

If you just need an internal admin panel in a Phoenix app, **use AshAdmin** —
it's less work. Reach for AshA2ui when the UI description itself needs to
travel: to an agent canvas, a non-LiveView client, or multiple render targets.
More on this boundary in
[What is AshA2ui?](documentation/topics/what-is-ash-a2ui.md)

## Coverage matrix

The rule: **not in this table = not fully demoed.** Each promoted capability
maps to a demo route (in the reference proof-of-concept app) and a named test
in this repo. POC route cells are filled in when the POC lands.

| Capability | Demo route | Test |
|---|---|---|
| Table render (`List` + `Row`/`Column` composition) | `/admin-tools/promotions-providers` (ScribbleVet backend) | `test/encoder_test.exs` |
| Form create/update | `/admin-tools/promotions-providers` (ScribbleVet backend) | `test/encoder_test.exs`, `test/action_handler_test.exs` |
| Row actions (`invoke` allowlist) | `/admin-tools/promotions-providers` (`generate_webhook_secret`) | `test/action_handler_test.exs` |
| Validation-error round trip (`/errors/<field>`) | `/admin-tools/promotions-providers` (duplicate name) | `test/action_handler_test.exs` |
| Actor-aware authorization | `/admin-tools/promotions-providers` (admin live_session actor) | `test/action_handler_test.exs` |
| Field inference from public attributes | n/a (compile time) | `test/transformer_test.exs` |
| Compile-time verifiers (bad fields/actions) | n/a (compile time) | `test/verifier_test.exs` |
| Schema validation of every payload (vendored v0.9.1 schemas) | validated in POC transport specs | `test/schema_helper_test.exs` + every encoder/e2e test |
| LiveView transport (mount, action round trip) | `/admin-tools/promotions-providers` | `test/live_renderer_test.exs` |
| PubSub live data refresh | `/admin-tools/promotions-providers` (second-session create) | `test/live_renderer_test.exs` |
| End-to-end: resource → surface → action → updated data model | `/admin-tools/promotions-providers` + `GET /admin-tools/a2ui/promotions-providers` (JSON) | `test/ash_a2ui_test.exs` |
| Form field groups (`group` N-column sections) | `/admin-tools/promotions-providers` (ScribbleVet backend) | `test/wave6_encoder_test.exs` |
| Card-style table rows (`row_layout` + `_badge_<field>`) | `/admin-tools/promotions-providers` (ScribbleVet backend) | `test/wave6_encoder_test.exs`, `test/wave6_action_handler_test.exs` |
| Agent-composed surfaces (spec → validate → serve, tamper cases, DSL parity) | `/admin-tools/agent` (ScribbleVet backend, `design_admin_surface` tool) | `test/dynamic_test.exs` |

## Roadmap

v0 deliberately supports exactly what a real CRUD admin page needs: table +
form components, row actions, field inference, type→widget mapping,
compile-time verifiers, actor-aware authorization, and PubSub live refresh via
the LiveView transport.

Shipped beyond the v0 core:

- ✅ **Named server-enforced `query` allowlists** — declarative
  search/sort/filter/pagination per table, referenced by name and validated
  server-side (see
  [Queries and Pagination](documentation/topics/queries-and-pagination.md)).
- ✅ **AG-UI transport** (`AshA2ui.AgUi`) — serve surfaces to AG-UI clients
  (CopilotKit et al.) from any HTTP host: framework-free event builders,
  SSE encoding, `RunAgentInput`/action decoding, and the `a2ui-surface`
  activity binding, with a per-call `spec_version:` override to pin the
  wire version to the consuming renderer (see
  [External Transports](documentation/topics/external-transports.md)).
- ✅ **`usage_rules` support** — the package ships `usage-rules.md` plus ten
  sub-rules (`actions`, `ag-ui`, `contexts`, `dynamic`, `layout`,
  `liveview`, `queries`, `relationships`, `reports`, `zero-jank`),
  syncable into a consumer's
  AGENTS.md via [`mix usage_rules.sync`](https://hexdocs.pm/usage_rules) (see
  [Agent usage rules](#agent-usage-rules)).
- ✅ **Relationship rendering** — `belongs_to` form selects inferred from
  `source_attribute` (option-label fallback chain
  `[:name, :title, :label, :username, :email]`, actor/tenant-scoped option
  reads, the `/options/<field>` convention) and `source` table columns read
  through loaded relationships (see
  [Relationship Rendering](documentation/topics/relationships.md) and the
  [Relationships](#relationships) example above).
- ✅ **Calculation & aggregate columns** — table fields may name public
  calculations and aggregates; they load and serialize like attributes, and
  aggregates/expression calculations are sortable in `query` allowlists (see
  the [multi-section example](#multiple-table-sections-with-scoped-refreshes)
  above).
- ✅ **Multiple named table components + `refreshes` metadata** — several
  independent table sections per surface with a scoped data model
  (`/records/<component_name>`, `/query/<component_name>`), and `action`
  entities that limit which sections a successful action refreshes (see
  [Multi-Section Surfaces](documentation/topics/multi-section-surfaces.md)).
- ✅ **Row-action prompts (`prompt_fields`)** — row actions that collect
  arguments through a basic-catalog `Modal` before invoking
  (`action :decline do prompt_fields [:notes] end`): the trigger pre-fills
  `/prompt/values/<action>` via the `prompt` action, and the Modal's Confirm
  sends `invoke` with a `"values"` map filtered + cast against the Ash
  action's arguments/accepts (see
  [Actions and Authorization](documentation/topics/actions-and-authorization.md)).
- ✅ **Relationship-path search** — `search_fields` entries may be paths to
  string attributes through public relationships
  (`search_fields [:code, [:referrer, :email]]`), matched with the same
  case-insensitive contains (see
  [Queries and Pagination](documentation/topics/queries-and-pagination.md)).
- ✅ **Calculation filters + named filter presets** — `filters` may name
  expression-backed public calculations, and `preset` entities declare
  server-side composite predicates the client selects **by name**
  (`preset :pending do filter status: :pending, deleted_at: nil end`, with a
  `read_action` escape hatch and `default_preset`; a `ChoicePicker` is
  emitted and `/query` gains `"preset"`) (see
  [Queries and Pagination](documentation/topics/queries-and-pagination.md)).
- ✅ **Conditional row-action visibility (`visible_when`)** — per-row
  show/hide from record state
  (`action :approve do visible_when status: :pending end`): server-computed
  `"_actions"`/`"_visible_<action>"` row data + a templated slot render it,
  and the handler re-evaluates the conditions on every invoke (see
  [Actions and Authorization](documentation/topics/actions-and-authorization.md)).
- ✅ **Multi-key calculation sorting** — `default_sort` (and client sorts)
  compose expression calculations with attributes
  (`default_sort status_priority: :asc, code: :asc`) with no extra
  machinery.
- ✅ **Searchable relationship selects (`option_search`)** — for option sets
  beyond `option_limit`: `field :author_id do option_search [:name, :email]
  end` swaps the static ChoicePicker for a search input + result list
  refreshed live through `/options/<field>` (the `"option_search"` /
  `"option_select"` client actions; server-validated selection with
  actor/tenant-scoped destination reads) (see
  [Relationship Rendering](documentation/topics/relationships.md)).
- ✅ **Layout: form groups + card-style table rows** — `group` entities
  render labeled N-column form sections (Card + heading + rows of
  equal-weight Columns) with a documented ordering contract, and the
  singleton `row_layout` entity renders records as cards (title + badge
  header with the row's actions, caption-labeled metadata grid, the
  computed `_badge_<field>` display-text row key); both compile-verified
  and byte-identical to the flat output when undeclared (see
  [Layout](documentation/topics/layout.md)).
- ✅ **Wizard steps** — `step` entities split a form into pages over the
  one form and the one Ash action: Back/Next with server-side validation of
  the reached steps (nothing persisted until the final submit), an optional
  read-only review step, and `/ui/wizard` state composed from basic
  components on v0.9.1 and v1.0. The step vocabulary is borrowed from
  PyroManiac (see [Wizard Steps](documentation/topics/wizard-steps.md)).
- ✅ **Nested relationship forms (`nested_form`)** — forms edit related
  records through `manage_relationship` action arguments, with the
  interaction mode **inferred** from the change's options via
  `Ash.Changeset.ManagedRelationshipHelpers`
  (`type: :append_and_remove` → pick-and-attach with remove buttons,
  `type: :direct_control` → inline sub-form rows):
  `nested_form :notes do fields [:body, :rating] end`. Rows live at
  `/form/<argument>` as an array of maps mutated through server-mediated
  `"nested_add"`/`"nested_remove"` actions; nested validation errors map to
  `/errors/<argument>/<index>/<field>` (see
  [Relationship Rendering](documentation/topics/relationships.md)).
- ✅ **Surface contexts + master/detail (`context` entities, `:detail`
  components)** — named, server-validated record selections that scope the
  rest of the surface: searchable pickers over any resource, **dependent
  option sources** (`depends_on` + `depends_on_path`, with cascade clearing
  and `auto_select_single`), context-scoped tables (`context_filter`,
  `require_context`), row-driven selection (`select_context`) feeding
  `:detail` components at `/detail/<context>`; driven by the
  `"context_search"`/`"context_select"`/`"context_clear"` client actions
  with every selection validated through an authorized read (see
  [Contexts and Details](documentation/topics/contexts-and-details.md)).
- ✅ **Client-driven range filters (`range_filters`)** — inclusive from/to
  bounds on public attributes (`range_filters [:inserted_at]`), cast
  server-side with a date→day-bounds convenience on datetime fields, bound
  at `/query/ranges/<field>/from|to` (see
  [Queries and Pagination](documentation/topics/queries-and-pagination.md)).
- ✅ **Agent-composed surfaces (`AshA2ui.Dynamic`)** — an LLM designs ad-hoc
  surfaces as a JSON spec (a declarative mirror of the DSL vocabulary, never
  raw A2UI) validated at runtime by the *same* verifier modules the DSL
  compiles with, against a host-configured resource allowlist; ships a JSON
  Schema for LLM tool parameters, resource descriptions for prompts, and
  structured self-correction errors (see
  [Agent-Composed Surfaces](documentation/topics/agent-composed-surfaces.md)).

- ✅ **A2UI v1.0 (RC) support** — per-surface `spec_version "1.0"` with a
  versioned encoder (`AshA2ui.Encoder.V1_0`): single inline `createSurface`,
  the `actionResponse` contract with the structured `/ui/response` path and
  stable error codes, `surfaceProperties`, `call_function/3`, Markdown
  headings, and a vendored executable conformance suite pinned to the RC
  commit (see [A2UI 1.0](documentation/topics/a2ui-1-0.md)).

Documented as roadmap (not built):

- **A2UI v1.0 final re-pin** — v1.0 is vendored at a pinned RC commit
  (`priv/a2ui/v1_0/NOTES.md`); when the spec leaves RC, re-vendor and rerun
  the conformance suite to surface any drift.
- **Upstream v1.0 renderer adoption** — no published `@a2ui/lit` /
  `@a2ui/web_core` release ships a v1.0 runtime yet; the shipped hook
  adapts v1.0 messages for the v0_9 renderer, and the adapter seam is
  removed once upstream ships a v1_0 entry point.
- **Richer client-driven `query` filters** — custom filter shapes beyond
  the shipped equality filters, range filters, and named presets, and
  multiple queries per table.
- **Nested-form extensions** — `many_to_many` join-resource fields (editing
  join-row attributes like a membership's role), recursive nesting, and
  in-picker pagination; the shipped v1 covers pick-and-attach and inline
  create/update/destroy.
- **Sorting on relationship-sourced columns** — `source` table columns are
  render-only; `query` sorting covers attributes, aggregates, and expression
  calculations, but not `source` paths.
- **`overrides:` option on `build_surface/2`** — per-request title/label/
  empty-state tweaks: the middle rung between the DSL and forking the encoder.
- **Context struct** (`actor`, `tenant`, `locale`, `audience`, `device`) with
  audience-conditional surfaces chosen in plain Elixir — simple gates in
  metadata, complex branching in ordinary functions, never a hidden rules
  engine.
- **A2A transport binding** — the a2ui.org A2A extension (A2UI messages as
  `DataPart`s with the `application/a2ui+json` MIME type); the binding is
  designed in [External Transports](documentation/topics/external-transports.md)
  and waits on an Elixir A2A server to embed in plus a concrete
  agent-to-agent consumer.
- **Raw WebSocket transport.**
- **Custom component catalogs** beyond the basic catalog.

## Documentation

- [Getting Started tutorial](documentation/tutorials/getting-started-with-ash-a2ui.md)
- [What is AshA2ui?](documentation/topics/what-is-ash-a2ui.md) — concept and
  the honest "when it pays off" boundary
- [A2UI 1.0](documentation/topics/a2ui-1-0.md) — the v1.0 wire contract,
  per-feature UX rationale, and the executable conformance suite
- [Rendering Clients](documentation/topics/rendering-clients.md) — transports,
  hook contract, `@a2ui/lit` / `@a2ui/react`
- [External Transports](documentation/topics/external-transports.md) — the
  AG-UI transport (`AshA2ui.AgUi`), the CopilotKit client wiring, and the
  designed A2A binding
- [Actions and Authorization](documentation/topics/actions-and-authorization.md)
- [Queries and Pagination](documentation/topics/queries-and-pagination.md)
- [Multi-Section Surfaces](documentation/topics/multi-section-surfaces.md)
- [Layout](documentation/topics/layout.md) — form field groups and
  card-style table rows
- [Wizard Steps](documentation/topics/wizard-steps.md) — stepped forms with
  server-side per-step validation and a review step
- [Contexts and Details](documentation/topics/contexts-and-details.md)
- [Agent-Composed Surfaces](documentation/topics/agent-composed-surfaces.md) —
  runtime specs, the allowlist, and the server-held surface contract
- [Data Model Conventions](documentation/topics/data-model-conventions.md)
- [DSL reference](documentation/dsls/DSL-AshA2ui.md)

## Contributing

Issues and PRs welcome at
[github.com/lukegalea/ash_a2ui](https://github.com/lukegalea/ash_a2ui).
Every payload-producing change must keep the schema-validation test suite
green (`mix test`) — the vendored A2UI JSON Schemas in `priv/a2ui/v0_9_1/`
and `priv/a2ui/v1_0/` are the executable spec.

Agents: read [AGENTS.md](AGENTS.md) before you change this repository. It links the agent constitution (`AGENT_PRINCIPLES.md`).
