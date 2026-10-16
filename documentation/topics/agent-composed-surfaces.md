# Agent-Composed Surfaces

`AshA2ui.Dynamic` lets a host build A2UI surfaces from a runtime,
JSON-serializable **surface spec** — typically emitted by an LLM as
structured tool output — with the same safety guarantees as the compile-time
`a2ui` DSL. It is the "agent designs the screen, AshA2ui keeps the data and
action contracts safe" feature.

## What a spec is (and is not)

A spec is a declarative mirror of the DSL vocabulary. It references
resources, attributes, and actions **by name**; the server resolves,
validates, and encodes everything. A spec is *never* raw A2UI JSON — the
composer chooses among the same knobs a DSL author has, nothing more.

```json
{
  "resource": "Feedback",
  "title": "Recent feedback",
  "components": [
    {
      "kind": "table",
      "fields": ["subject", "category", "done", "inserted_at"],
      "row_actions": ["toggle_done"],
      "query": "default"
    }
  ],
  "queries": [
    {
      "name": "default",
      "search_fields": ["subject"],
      "sortable": ["inserted_at"],
      "filters": ["category", "done"],
      "default_sort": [{"field": "inserted_at", "direction": "desc"}]
    }
  ],
  "fields": [
    {"name": "inserted_at", "label": "Received", "format": "date"}
  ]
}
```

The full vocabulary — components (`table` / `form` / `detail`), field
overrides, queries with presets and range filters, `row_layout` cards (with
`badge_text` and `badge_tones`), form `groups` and `nested_forms`,
sectioned tables (`sections`), `action` metadata (`refreshes`,
`prompt_fields`, `visible_when`, `via`), `contexts` with the tables'
`select_context` / `context_filter` / `require_context`, related tables and
reference links — mirrors the DSL entity for entity.

A master/detail surface, as a spec: a pickerless context selected from the
people table, and a related table over `Note` scoped by it, with a link
column:

```json
{
  "resource": "Person",
  "contexts": [{"name": "person", "resource": "Person", "picker": false}],
  "components": [
    {"kind": "table", "fields": ["name"], "select_context": "person"},
    {"kind": "table", "name": "their_notes", "resource": "Note",
     "fields": ["title", "status", "subject_id"],
     "context_filter": {"person_id": "person"}, "require_context": ["person"]}
  ],
  "fields": [
    {"name": "subject_id", "label": "Subject",
     "link": {"surface": "person", "path": ["subject_id"]}}
  ]
}
```

A related table's `resource` is an allowlisted name like a context's; its
fields, query, `context_filter` keys, `source` paths and links resolve
against that resource, and the related-table rules (read-only, no
`row_actions` or `sections`) are the DSL verifiers'. A field's `link` is a
to-one relationship name or `{"surface", "path"}`; `links` names a to-many
relationship; `link_label` a destination attribute.
`AshA2ui.Dynamic.spec_schema/1` returns a JSON Schema of the whole spec,
ready to hand to an LLM as a tool parameter schema.

## The validation pipeline

`AshA2ui.Dynamic.resolve(spec, allowlist: allowlist)` runs:

1. **Allowlist gate** — the spec's `resource` (and every context
   `resource`, related-table `resource` and `sections` source) must be in
   the host-configured allowlist. Nothing outside it is introspectable or
   renderable.
2. **Entity building** — every spec entry is built through
   `Spark.Dsl.Entity.build/5` with the extension's own entity definitions,
   so Spark's option schemas (types, `one_of` values, required options,
   defaults) apply to specs exactly as to DSL blocks. Identifier strings are
   format-checked (`^[a-zA-Z]\w*$`, ≤ 64 bytes) before becoming atoms, and
   list sizes are bounded.
3. **Field inference** — `AshA2ui.Transformers.InferFields`, unchanged:
   tables without `fields` get the public attributes, forms the create
   action's accepts.
4. **The compile-time verifiers, at runtime** — the resolved entities are
   wrapped in a synthetic standalone-style DSL state and run through the
   *same verifier modules* the DSL compiles with (components, layouts,
   contexts, fields, actions, queries, relationships, nested forms). Same
   checks, same messages: fields must be public and existent, form fields
   accepted by their actions, query allowlists sound, relationship paths
   walkable, `visible_when` values castable.

The result is `{:ok, %AshA2ui.Dynamic.Surface{}}` or
`{:error, [%AshA2ui.Dynamic.Error{}]}` — structured `path` + `message`
errors that reuse the verifier texts (which enumerate what *is* available),
so an LLM tool loop can feed them back and self-correct:

```elixir
case AshA2ui.Dynamic.resolve(spec, allowlist: allowlist) do
  {:ok, surface} -> {:ok, surface}
  {:error, errors} -> {:error, AshA2ui.Dynamic.Error.messages(errors)}
end
```

Every verifier runs (rather than halting at the first failure), so a
composer correcting several mistakes converges in fewer round trips.

## The allowlist

```elixir
allowlist = AshA2ui.Dynamic.allowlist([MyApp.Feedback, MyApp.Accounts.User])

# or: everything that already has a declared surface
allowlist =
  :my_app
  |> AshA2ui.Dynamic.extension_resources()
  |> AshA2ui.Dynamic.allowlist()
```

Resources are named by their short module name (pass a `%{"name" => Module}`
map to control naming). Relationship traversal (form selects, `source`
columns, search paths) is bounded exactly as on declared surfaces: only the
resource's own public relationships are walkable, and every read —
including option loads and picked-value lookups — is an authorized Ash read.

`AshA2ui.Dynamic.describe_resources(allowlist)` returns a compact JSON-able
description of each resource (public attributes with types and enum values,
actions with accepts/arguments, public relationships) — embed it in the tool
description or system prompt, because an LLM cannot compose against fields
it cannot see.

## Serving a surface (the host contract)

`resolve/2` is stateless. What makes the action round trip tamper-proof is a
storage discipline the host must follow:

1. **Resolve once, server-side.** Keep the returned `%Surface{}` in server
   state — a LiveView assign, ETS, a cache — keyed by `surface.surface_id`.
2. **Serve actions from the server-held struct.** Route client `action`
   envelopes to `AshA2ui.Dynamic.handle_action(surface, envelope, actor: actor)`
   using the stored surface looked up by the envelope's surface id. Never
   rebuild a surface from anything the client echoes back — the client's
   `surfaceId` selects *which* stored surface handles the envelope, and
   everything else about the envelope is validated the same way declared
   surfaces validate it (`row_actions` allowlist, query allowlists,
   `visible_when` enforcement, authorized reads).
3. **Drop the struct when the surface is dismissed.**

A LiveView host in full:

```elixir
def handle_info({:agent_designed_surface, spec}, socket) do
  case AshA2ui.Dynamic.resolve(spec, allowlist: @allowlist) do
    {:ok, surface} ->
      messages =
        AshA2ui.Dynamic.build_surface(surface, actor: socket.assigns.current_user)

      {:noreply,
       socket
       |> assign(:dynamic_surface, surface)
       |> push_event("a2ui:messages", %{messages: messages})}

    {:error, errors} ->
      # feed AshA2ui.Dynamic.Error.messages(errors) back to the agent loop
      {:noreply, socket}
  end
end

def handle_event("a2ui:action", envelope, socket) do
  surface = socket.assigns.dynamic_surface

  messages =
    case AshA2ui.Dynamic.handle_action(surface, envelope,
           actor: socket.assigns.current_user
         ) do
      {:ok, messages} -> messages
      {:error, messages} -> messages
    end

  {:noreply, push_event(socket, "a2ui:messages", %{messages: messages})}
end
```

Because specs contain no secrets and validation is deterministic, storing
the raw spec and re-resolving it (e.g. after a LiveView reconnect, with the
same `:surface_id`) is also sound. The invariant that matters: **the server
is the only source of the spec.**

`build_surface/2`, `build_data_model/2`, and `handle_action/3` take the same
options as their `AshA2ui.Info` / `AshA2ui.ActionHandler` counterparts —
`:actor`, `:tenant`, `:authorize?` (default `true`), `:query_state`,
`:context_state` — and authorization is actor-based exactly as on declared
surfaces.

## The spec-as-artifact lifecycle: propose → ratify → persist → promote

A validated spec is worth keeping. The lifecycle API treats specs as
first-class artifacts — serializable, diffable, and promotable — so an
organization's library of agent-designed surfaces can grow as a reviewed
asset instead of evaporating with the chat session:

1. **Propose.** The agent emits a spec; `resolve/2` validates it and the
   host serves it (everything above).
2. **Ratify.** A human reviews what the spec *is* — or, for an updated
   spec, what changed: `AshA2ui.Dynamic.diff(stored, proposed)` computes a
   change summary at the spec vocabulary level (components, queries and
   their presets, fields, actions, contexts, matched by name; option
   changes with old and new values — never a raw JSON diff).
   `AshA2ui.Dynamic.Diff.summary/1` renders it as review lines:

   ```elixir
   AshA2ui.Dynamic.diff(stored, proposed) |> AshA2ui.Dynamic.Diff.summary()
   # => [
   #   ~s(surface: title changed from "Feedback" to "Recent feedback"),
   #   ~s(added query "default"),
   #   ~s(component "table": row_actions changed from [] to ["toggle_done"])
   # ]
   ```

3. **Persist.** `AshA2ui.Dynamic.serialize/1` produces the canonical stored
   form: a versioned JSON envelope (`{"spec": ..., "spec_format": 1}`) with
   object keys sorted at every level, so semantically identical specs
   serialize byte-identically. `AshA2ui.Dynamic.fingerprint/1` derives the
   matching `"sha256:..."` content identity. Loading goes through
   `AshA2ui.Dynamic.deserialize(serialized, allowlist: allowlist)` — which
   **re-validates against the current resource state**. A spec saved six
   months ago is a claim about resources that may have changed; fields or
   actions removed in the meantime come back as the same structured
   `AshA2ui.Dynamic.Error` list a freshly composed spec would produce.
   Drift is a reviewable error, never a crash.
4. **Promote.** When a stored spec earns permanence,
   `AshA2ui.Dynamic.to_dsl_source/2` generates a checked-in standalone UI
   module — formatted, compile-ready, provenance-commented with the spec's
   fingerprint:

   ```elixir
   {:ok, source} =
     AshA2ui.Dynamic.to_dsl_source(spec,
       module: MyApp.UI.RecentFeedbackUI,
       allowlist: allowlist
     )

   File.write!("lib/my_app/ui/recent_feedback_ui.ex", source)
   ```

   Resolving the generated module produces a surface equivalent to
   resolving the spec directly (the test suite holds this as a round-trip
   property). Promotion changes *where* the declaration lives — reviewable
   code with compile-time verification instead of stored data — never what
   it renders. The spec's `title` is host-rendered chrome, not DSL
   vocabulary; it is carried into the generated module's `@moduledoc`.

## Capability edges (honest limits)

- The spec exposes **exactly the DSL vocabulary** — nothing the DSL cannot
  declare can be composed. No free-form layout, no custom components, no
  arbitrary filters beyond `query` allowlists and presets, at most one form
  per surface.
- `via`-delegated row actions are part of the spec (as
  `"Mod.fun/arity"` + args), but the callable modules are **host
  configuration**: `resolve/2` accepts a `:via_allowlist`, and a spec whose
  delegate module is not on it is rejected. The parser additionally
  validates — at resolve, never at call time — that the delegate's module
  is loaded and exports the function at the applied arity. Existence is not
  authorization: without an explicit `:via_allowlist`, no spec-carried
  `via` resolves.
- Widget/format hints are limited to the encoder's vocabulary
  (`text_field`, `check_box`, `choice_picker`, `date_time_input`; `date`).
- A dynamic surface is only as capable as the resource's actions and
  policies: a spec cannot invent actions, expose private fields, or bypass
  `authorize?: true`. On policy-less resources, dynamic surfaces (like
  declared ones) are *not* access control.
- Dynamic resolution reports errors at runtime, to the composer — a human
  authoring a surface should prefer the DSL and get compile-time
  diagnostics instead.
