# Actions and Authorization

Everything a client can *see* or *do* through an AshA2ui surface goes through
ordinary Ash actions with your actor and `authorize?: true`. There is no
side channel: if a policy forbids it, the surface can't do it either.

## Reading: the `render_a2ui` generic action

Compiling a resource with the `AshA2ui` extension adds a generic action
`render_a2ui` (returning `{:array, :map}` — the surface message list) to the
resource — opt out with `add_render_action? false` in the `a2ui` section if
you don't want it. It wraps
`AshA2ui.Info.build_surface/2`, which means surface rendering:

- shows up in code interfaces like any other action,
- participates in tracing/observability,
- and, most importantly, runs **through the policy pipeline**.

`build_surface/2` and `build_data_model/2` accept `actor:` and `tenant:` and
load records via the component's `read_action` with `authorize?: true`.
Defaults, spelled out:

| Option | Default | Meaning |
|---|---|---|
| `actor:` | `nil` | No actor — policies evaluate against a nil actor |
| `tenant:` | `nil` | No tenant |
| `authorize?` | always `true` | Never bypassed by AshA2ui |

If your resource has no policies, `authorize?: true` is a no-op — **an
AshA2ui surface on a policy-less resource is not access-controlled** beyond
whatever authentication your transport applies (router pipelines,
`live_session` mounts). Don't mistake the correct default posture for
enforcement you haven't written.

## Writing: the `action` envelope

Clients send a single envelope message; `AshA2ui.ActionHandler.handle/3`
consumes it:

```elixir
AshA2ui.ActionHandler.handle(MyApp.UI.TicketUI, envelope, actor: current_user)
# => {:ok, messages} | {:error, messages}
```

The v0 `action.name` vocabulary:

| `action.name` | Meaning | Maps to |
|---|---|---|
| `"submit_form"` | The form component was submitted | The form's `create_action` or `update_action` (with `recordId` → update, without → create) |
| `"invoke"` | A row action button was clicked (or a prompt Modal confirmed) | The named action in `row_actions` |
| `"prompt"` | A prompt Modal's trigger was clicked | No Ash write — pre-fills `/prompt/values/<action>` for the Modal inputs |
| `"start_create"` | The Create button was clicked | No Ash write — opens the task panel in create mode over a fresh `/form` |
| `"view_record"` | A row's View control was clicked | An authorized read — the record shows read-only in the panel (`/ui/panel/record`); `/form` is untouched |
| `"start_edit"` | A row's Edit control was clicked | An authorized read plus an update-authorization pre-flight — `/form` is populated and the panel opens in edit mode |
| `"cancel_record_task"` | The panel's Cancel was clicked | No Ash write — back to browse, `/form` and `/errors` reset |
| `"query"` | Query controls were applied | The table's `query` allowlist (see [Queries and Pagination](queries-and-pagination.md)) |
| `"bulk_invoke"` | A bulk toolbar button was clicked over a row selection | The named action in the table's `bulk_actions`, once per re-read selected record (see [Bulk Actions](bulk-actions.md)) |
| `"bulk_select"` | Select page / Clear was clicked | No Ash write — the table's rows are re-read and rewritten with `_selected` set |
| `"wizard_next"` / `"wizard_back"` | A stepped form's Next / Back was clicked | No Ash write — Next validates the reached steps through the form's action changeset (see [Wizard Steps](wizard-steps.md)) |
| `"open_surface"` | A basic-catalog reference link was clicked | No Ash read or write — accepted only for a to-one link field whose resolved surface is the one sent; returns no messages, and the transport navigates (see [Relationships](relationships.md#rendering)) |

When the view declares no form/table action, the handler falls back to the
resource's **primary** create/update/read action — so minimal surfaces work
without spelling every action out.

Both result tuples carry valid server→client messages: on success, a data
refresh plus typed `/ui/feedback`; on failure, validation errors mapped onto
`/errors/<field>` paths and an `/ui/feedback` error (see
[Data Model Conventions](data-model-conventions.md)).

## The task panel

Every surface with a `:form` component composes a **record task panel**: a
small state machine over the form buffer, with its state in the data model at
`/ui/intent` and `/ui/panel/*` (see
[Data Model Conventions](data-model-conventions.md)).

| Mode | Entered by | What shows |
|---|---|---|
| browse | the initial render, `cancel_record_task`, a successful `submit_form` | the panel is closed |
| create | `start_create` (the "Create <Resource>" button; only with a create action) | the editable form over a fresh `/form`, the create submit and Cancel |
| view | `view_record` (a row's View control) | the record **read-only** from `/ui/panel/record`; no submit, Cancel only. `/form` is never written |
| edit | `start_edit` (a row's Edit control; only with a declared `update_action`) | the editable form over the record's values, "Save changes" and Cancel |

`view_record` and `start_edit` read the record through the surface's read
action with the actor, and `start_edit` also pre-flights the update
authorization with `Ash.can?`, so the edit panel never opens on a write the
server would refuse. A failed `submit_form` keeps the mode, the panel and the
submitted values, with the field errors at `/errors/<field>`. Every outcome is
written to the typed `/ui/feedback`, whose message the status line just under
the panel shows.

A **related table** (a `:table` with its own `resource`, scoped by a context)
lists another resource's records, so it is read-only: it gets neither the
View/Edit controls nor the create button. A table with `select_context` gets a
"Select <context>" row button that makes the row's record the context's
selection, which fills the `:detail` components and related tables bound to it
(see [Contexts and Details](contexts-and-details.md)).

## Row actions with argument prompts (`prompt_fields`)

A row action that needs user input — "decline with a note" — declares its
prompt fields on an `action` entity:

```elixir
component :table do
  row_actions [:approve, :decline]
end

action :decline do
  prompt_fields [:notes]                 # must be args/accepts of :decline
  prompt_title "Decline referral"        # optional; defaults to the humanized name
end
```

Every prompt field must be an **argument or accepted attribute** of the Ash
action (verified at compile time). The encoder then renders the action as a
basic-catalog `Modal` instead of a bare button:

- the row button becomes the Modal's `trigger` and dispatches the `"prompt"`
  action (`{"action": "decline", "recordId": {"path": "id"}, "component":
  "table"}`); the server answers by pre-filling
  `/prompt/values/decline` (each field's current record value when it is a
  public attribute, `""` otherwise) and clearing `/errors`,
- the Modal `content` is a Column with a title, one `TextField` per prompt
  field bound to `/prompt/values/decline/<field>`, a per-field error `Text`
  bound to `/errors/<field>`, and a **Confirm** button,
- Confirm dispatches a regular `"invoke"` whose context carries
  `"values": {"path": "/prompt/values/decline"}` alongside
  `"action"`/`"recordId"`.

Handler-side, the `invoke` context's `"values"` map is **filtered to the
declared `prompt_fields`** (nothing outside them ever reaches the
changeset), cast against the action's arguments/accepts, and passed as the
action params. Validation errors land on `/errors/<field>` as usual — they
render inside the open Modal. A success clears
`/prompt/values/<action>`. For actions *without* `prompt_fields`, `"values"`
is ignored entirely — the pre-Wave-4 empty-params behavior is unchanged.

Protocol notes: Modal open/close is client-side (the v0.9.1 basic catalog
has no server-controlled open state), so the server cannot force the Modal
shut — the frozen contract is only the `prompt` pre-fill and the `invoke`
`"values"` map. Prompt inputs bind **absolute** `/prompt/...` paths because
the catalog's `Action.context` values cannot nest objects; the shared state
is safe because only one Modal is open at a time.

## Conditional row actions (`visible_when`)

Per-row availability driven by record state:

```elixir
action :approve do
  visible_when status: :pending, deleted_at: nil
end
```

`visible_when` is a keyword list of conditions ANDed together — `nil` means
`is_nil`, a list means membership, anything else is equality — on **public
attributes or expression-backed public calculations** (values verified
castable at compile time). It is deliberately *not* a rules engine: anything
richer belongs in an Ash policy or a dedicated read action.

Two halves, with different guarantees:

- **Enforcement (mandatory):** on every `invoke` (and `prompt`) of a
  conditional action, the handler fetches the identified record (loading any
  condition calculations) and re-evaluates the conditions. A non-visible
  action is rejected with an `/ui/feedback` error before touching the write —
  regardless of what the client rendered.
- **Rendering (best-effort):** the v0.9.1 basic catalog has no `visible`
  property or template conditionals, so visibility is server-computed data:
  each row gains `"_actions"` (the visible action names) and a
  `"_visible_<action>"` list (`[{"id": <record id>}]` or `[]`), and the
  action renders inside a `List` slot templated over that row-relative path
  — renderers that support nested templates show zero or one button per
  row. Renderers that don't can still consult `"_actions"`; either way the
  handler enforcement above is the authority.

Note `visible_when` is a UX affordance layered *inside* the `row_actions`
allowlist — it narrows when an allowlisted action applies, and Ash policies
remain the real authorization boundary.

## `row_actions` is the allowlist

This is the load-bearing security property of the DSL:

```elixir
component :table do
  row_actions [:update, :archive]  # ← the ONLY actions "invoke" may call
end
```

`ActionHandler` rejects any `invoke` envelope naming an action outside the
declared `row_actions` — *before* touching Ash. (`submit_form` envelopes
carry no action name at all: the server always runs the view's declared
create/update action, so there is nothing for a client to redirect.)
A malicious client editing the envelope cannot reach `:destroy` if you didn't
declare it. Corollary: **declare `row_actions` explicitly and minimally**;
never expose an action through the surface just because it exists.

The declared actions are verified to exist (with compatible types) at compile
time, so the allowlist can't silently drift from the resource.

`bulk_actions` is a second allowlist with the same rule for `bulk_invoke`.
A bulk run never trusts the carried row ids: it re-reads them through the
table's read action and scope as the actor, and only the records that read
returns are passed to the action (see [Bulk Actions](bulk-actions.md)).

## Layering your authorization

Defense in depth, from outside in:

1. **Transport auth** — router pipelines / `live_session` `on_mount` decide
   who reaches the surface at all, and supply the actor
   (`actor_fn:` on `AshA2ui.LiveRenderer`, `conn.assigns` for JSON
   endpoints).
2. **The DSL allowlist** — `row_actions`, `bulk_actions` and the declared
   form actions bound what can be attempted.
3. **Ash policies** — decide whether *this* actor may perform the attempted
   action on *this* record, exactly as everywhere else in your app.

## Documented limitation: no field-level visibility

v0 field visibility is Ash's public/private attribute distinction plus the
static `hidden` field option — nothing actor-dependent. If two actors are
allowed to read the same records but should see *different fields*, AshA2ui
cannot express that yet: the surface's component tree and field list are the
same for every actor.

Workarounds today: define separate surfaces per audience in standalone UI
modules (`use AshA2ui.Standalone`, one module per audience) and choose which
to render in plain Elixir. First-class support arrives with the roadmap
context struct (`audience`-conditional surfaces) and field-visibility rules.
