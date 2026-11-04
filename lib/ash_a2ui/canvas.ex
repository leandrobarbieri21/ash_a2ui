defmodule AshA2ui.Canvas do
  @moduledoc """
  The naked-objects foundation for the canvas phase: a canonical graph AST
  over the host's configured domains, opaque object references, actor/tenant
  scoped object resolution, and server-derived capabilities.

  This is the layer that lets a client ask *"what exists?"* and *"what can I
  do with this thing?"* without the server ever materializing the database as
  UI, and without any client-supplied string becoming an atom or module
  (`CANVAS-SEC-006`):

    * **Graph** — `build_graph/1` introspects the registry's domains purely
      through Ash metadata (`Ash.Domain.Info`, `Ash.Resource.Info`, policy
      and state-machine info) into an `%AshA2ui.Canvas.Graph{}`: application
      → domain → resource containment, named relationship edges between
      registered resources, and the behavioral layers (actions, policies,
      state machines) as addressable typed sub-entities in node metadata.
      Records are never graph nodes — the graph is the *structural* truth,
      versioned by a deterministic content hash.
    * **Objects** — `resolve/2` turns an opaque ref
      (`"application:app"`, `"domain:app"`, `"resource:app.thing"`,
      `"record:app.thing:pk"`) into an `%AshA2ui.Canvas.Object{}` carrying a
      label, provenance, server-derived capabilities and declared
      projections. Structural objects are pure introspection (zero record
      reads); record refs enter through an authorized read by primary key.
    * **Registry** — the host implements `AshA2ui.Canvas.Registry`
      (`domains/0`, optional `label/1`). What the registry does not list
      does not exist: unregistered modules are unreachable, and resolution
      failures return the bare `{:error, :unknown_object}` with no registry
      content in the error.

  Deliberately *not* here (Phase D non-goals): scenes, viewports, navigation
  intents, renderers, projections-as-surfaces, and record enumeration. The
  experience compiler wires into projections in later phases.
  """

  alias AshA2ui.Canvas.Graph
  alias AshA2ui.Canvas.ObjectResolver

  @doc """
  Resolves an opaque object reference into an `%AshA2ui.Canvas.Object{}`.

  `ref` is the client-facing string form (`"application:<app>"`,
  `"domain:<short>"`, `"resource:<domain>.<resource>"`,
  `"record:<domain>.<resource>:<encoded_pk>"`). Options:

    * `:registry` (required) — the host's `AshA2ui.Canvas.Registry`
      implementation. Module names come only from this registry's domain
      list, matched against the parsed ref path; nothing in `ref` is ever
      converted to an atom or module.
    * `:actor`, `:tenant` — the scene's actor and tenant. Structural
      objects are pure introspection and read nothing; record refs resolve
      through an authorized read under this actor/tenant.
    * `:authorize?` — whether the record read authorizes. Defaults to
      `true`, like every authorized path in this library.
    * `:gettext_fn`, `:gettext_backend`, `:locale`, `:metadata_domain` — the
      translator options of an A2UI surface (`AshA2ui.L10n`); they translate
      the object's and its capabilities' labels, never a record's label.

  Returns `{:ok, object}` or `{:error, :unknown_object}` for malformed,
  unknown, or unregistered refs (and for record reads that fail — a record
  the actor cannot read does not exist for them).
  """
  @spec resolve(String.t(), keyword()) ::
          {:ok, AshA2ui.Canvas.Object.t()} | {:error, :unknown_object}
  def resolve(ref, opts), do: ObjectResolver.resolve(ref, opts)

  @doc """
  Builds the canonical `%AshA2ui.Canvas.Graph{}` over `registry`'s domains.

  Pure Ash introspection: no records are read, no Mermaid or SVG is parsed
  or produced anywhere. The revision is a deterministic sha256 over the
  canonicalized semantic content — registration order and module definition
  order do not affect it.
  """
  @spec build_graph(module(), keyword()) :: Graph.t()
  def build_graph(registry, opts \\ []), do: Graph.Builder.build(registry, opts)
end
