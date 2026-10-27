defmodule AshA2ui.Dynamic do
  @moduledoc """
  Agent-composed surfaces: build and serve A2UI surfaces from a runtime,
  JSON-serializable **surface spec** — typically emitted by an LLM as
  structured tool output — with the same validation rigor as the compile-time
  `a2ui` DSL.

  A spec is *not* raw A2UI. It is a declarative mirror of the DSL vocabulary
  (components, fields, queries, presets, groups, row layouts, nested forms,
  actions, contexts, related tables, reference links, calendar tables) that
  references
  resources, attributes and actions **by name**; the server resolves,
  validates, and encodes everything. The spec composer never controls the
  wire payload, only the same knobs a DSL author has.

  ## Pipeline

      spec (JSON map)
        │  AshA2ui.Dynamic.resolve(spec, allowlist: [...])
        ├─ resource looked up in the host-configured allowlist
        ├─ entities built through Spark's own entity schemas
        │    (AshA2ui.Dynamic.Parser — same option types/defaults as the DSL)
        ├─ field inference (AshA2ui.Transformers.InferFields)
        ├─ THE compile-time verifiers, run at runtime over a synthetic
        │    standalone-style DSL state (VerifyComponents/Layouts/Contexts/
        │    Fields/Actions/Queries/Calendar/Relationships/NestedForms — the
        │    same modules, the same messages)
        └─ {:ok, %AshA2ui.Dynamic.Surface{}} | {:error, [%Dynamic.Error{}]}

  The returned surface then flows through the exact machinery declared
  surfaces use:

    * `build_surface/2` → `AshA2ui.Info.build_surface/2` → the versioned
      encoder (authorized reads, query allowlists, context scoping),
    * `handle_action/3` → `AshA2ui.ActionHandler.handle/3` (row-action
      allowlist, `visible_when` enforcement, actor-based authorization with
      `authorize?: true` by default).

  ## The allowlist

  Dynamic surfaces may only render resources the host explicitly offers:

      allowlist = AshA2ui.Dynamic.allowlist([MyApp.Feedback, MyApp.User])

  `allowlist/1` names each resource by its short module name
  (`"Feedback"`); pass a `%{"name" => Module}` map to control naming. The
  allowlist gates the surface's own resource, every `context` resource,
  every related table's `resource` and every `sections` source.
  Relationship traversal (selects, `source` columns, search paths) is
  bounded the same way it is for declared surfaces: only the resource's own
  public relationships are walkable, and every read is authorized against
  the actor.

  `extension_resources/1` collects every resource of an OTP app's Ash
  domains that carries the `AshA2ui` extension — a convenient default
  allowlist ("what already has a declared surface may also be composed").

  ## Serving surfaces safely (the host contract)

  `resolve/2` is stateless; making the round trip tamper-proof is a
  **storage discipline** (see `AshA2ui.Dynamic.Surface`):

    1. resolve once, server-side; keep the `%Surface{}` in server state
       (LiveView assign, ETS, cache) keyed by `surface.surface_id`,
    2. serve client `action` envelopes with `handle_action/3` on the
       **server-held** struct — never rebuild a surface from anything the
       client echoes back,
    3. drop the struct when the surface is dismissed.

  Specs never contain secrets and validation is deterministic, so storing
  and re-resolving the raw spec (e.g. after a LiveView reconnect) is also
  sound — the important invariant is that the *server* is the only source
  of the spec.

  ## LLM integration

  `spec_schema/1` returns a JSON Schema for the spec, ready to hand to an
  LLM as a tool parameter schema. `describe_resources/1` returns a compact
  JSON-able description of each allowlisted resource (fields, actions,
  relationships) for the tool description or system prompt — an LLM cannot
  compose against fields it cannot see. Validation errors are structured
  and reuse the compile-time verifier messages (which enumerate what *is*
  available), so a tool loop can feed them back for self-correction:

      case AshA2ui.Dynamic.resolve(spec, allowlist: allowlist) do
        {:ok, surface} -> render(surface)
        {:error, errors} -> {:error, AshA2ui.Dynamic.Error.messages(errors)}
      end
  """

  alias AshA2ui.Dynamic.Diff
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Parser
  alias AshA2ui.Dynamic.Promoter
  alias AshA2ui.Dynamic.Serializer
  alias AshA2ui.Dynamic.Surface
  alias AshA2ui.Transformers.InferFields
  alias Spark.Dsl.Extension

  @resolve_opts [:allowlist, :surface_id, :spec_version, :via_allowlist]

  # The cell cap of a composed board; see max_composed_cells/0.
  @max_composed_cells 12

  @doc """
  Resolves and validates a surface `spec` (a JSON-decoded, string-keyed map)
  into an `AshA2ui.Dynamic.Surface`.

  ## Options

    * `:allowlist` (required) — the resources the spec may render, as
      returned by `allowlist/1` (or any `%{"name" => Module}` map).
    * `:surface_id` — the A2UI surface id. Defaults to a generated
      `"dyn_<resource>_<hex>"` id, unique per resolve, so a newly composed
      surface always replaces a previous one client-side.
    * `:spec_version` — the A2UI protocol version the surface speaks:
      `"0.9.1"` (the default) or `"1.0"`. Host configuration (matched to the
      renderer's capability), not part of the LLM-facing spec. A v1.0
      dynamic surface bootstraps as a *single* inline `createSurface`
      message — exactly what agent-panel transports want (see the A2UI 1.0
      topic).
    * `:via_allowlist` — the modules a spec's `via`-delegated row actions
      may dispatch to (default: none — a spec carrying `via` is rejected
      unless the host passes this). Via delegates run host code, so — unlike
      declared surfaces, where the delegate is reviewed source — the set of
      callable modules is host configuration, with the same discipline as
      `:allowlist`. The parser still independently validates that each
      delegate's module is loaded and exports the function at the applied
      arity.

  Returns `{:ok, surface}` or `{:error, [%AshA2ui.Dynamic.Error{}]}`.
  """
  @spec resolve(map, keyword) :: {:ok, Surface.t()} | {:error, [Error.t()]}
  def resolve(spec, opts) do
    Keyword.validate!(opts, @resolve_opts)
    allowlist = Keyword.fetch!(opts, :allowlist)
    spec_version = Keyword.get(opts, :spec_version, "0.9.1")
    via_allowlist = Keyword.get(opts, :via_allowlist, [])

    unless spec_version in ["0.9.1", "1.0"] do
      raise ArgumentError,
            "spec_version must be \"0.9.1\" or \"1.0\", got: #{inspect(spec_version)}"
    end

    with {:ok, resource} <- spec_resource(spec, allowlist),
         {:ok, title} <- spec_title(spec),
         {:ok, entities} <- Parser.parse(Map.drop(spec, ["resource", "title"]), allowlist),
         :ok <- validate_via_allowlist(entities, via_allowlist),
         :ok <- require_component(entities),
         surface_id =
           Keyword.get_lazy(opts, :surface_id, fn -> generate_surface_id(resource) end),
         {:ok, dsl_state} <-
           infer_fields(synthetic_dsl_state(resource, surface_id, spec_version, entities)),
         :ok <- run_verifiers(dsl_state),
         :ok <- validate_composed_sections(dsl_state, resource) do
      {:ok,
       %Surface{
         surface_id: surface_id,
         resource: resource,
         title: title,
         spec: spec,
         dsl_state: dsl_state
       }}
    end
  end

  @doc """
  Builds the surface's A2UI message list through
  `AshA2ui.Info.build_surface/2`: the v0.9.1 `createSurface` →
  `updateComponents` → `updateDataModel` triple, or (for surfaces resolved
  with `spec_version: "1.0"`) a single inline `createSurface` message.

  Takes the same options (`:actor`, `:tenant`, `:authorize?`, `:domain`,
  `:query_state`, `:context_state`); reads are authorized by default.
  """
  @spec build_surface(Surface.t(), keyword) :: [map]
  def build_surface(%Surface{} = surface, opts \\ []) do
    AshA2ui.Info.build_surface(surface.dsl_state, opts)
  end

  @doc """
  Builds a data-only refresh (`updateDataModel`) through
  `AshA2ui.Info.build_data_model/2`. Same options as `build_surface/2`.
  """
  @spec build_data_model(Surface.t(), keyword) :: map
  def build_data_model(%Surface{} = surface, opts \\ []) do
    AshA2ui.Info.build_data_model(surface.dsl_state, opts)
  end

  @doc """
  Handles a client `action` envelope for a **server-held** surface through
  `AshA2ui.ActionHandler.handle/3` — the row-action allowlist, query
  allowlists, `visible_when` enforcement, and actor-based authorization
  apply exactly as on declared surfaces.

  Takes the same options as `AshA2ui.ActionHandler.handle/3` (`:actor`,
  `:tenant`, `:authorize?`).
  """
  @spec handle_action(Surface.t(), map, keyword) :: {:ok, [map]} | {:error, [map]}
  def handle_action(%Surface{} = surface, action_message, opts \\ []) do
    AshA2ui.ActionHandler.handle(surface.dsl_state, action_message, opts)
  end

  # --- the spec-as-artifact lifecycle ---------------------------------------------

  @doc """
  Serializes a spec (or a resolved surface's spec) to its **canonical**
  versioned JSON form: object keys sorted at every level, array order
  preserved, wrapped in a `{"spec": ..., "spec_format": #{Serializer.spec_format()}}`
  envelope (see `AshA2ui.Dynamic.Serializer`).

  Canonical serialization is deterministic — semantically identical specs
  serialize byte-identically — which makes stored specs diffable,
  fingerprintable, and stable under version control.
  """
  @spec serialize(map | Surface.t()) :: String.t()
  def serialize(%Surface{spec: spec}), do: Serializer.serialize(spec)
  def serialize(spec) when is_map(spec), do: Serializer.serialize(spec)

  @doc """
  A stable content fingerprint (`"sha256:<hex>"` of the canonical
  serialization) of a spec or resolved surface — the identity stored specs
  and promoted modules are traced by. Input key order never matters.
  """
  @spec fingerprint(map | Surface.t()) :: String.t()
  def fingerprint(%Surface{spec: spec}), do: Serializer.fingerprint(spec)
  def fingerprint(spec) when is_map(spec), do: Serializer.fingerprint(spec)

  @doc """
  Loads a serialized spec (as produced by `serialize/1`) back into a served
  surface, **re-validating it against the current resource state** through
  `resolve/2` (same options).

  A stored spec is a claim about resources that may have changed since it
  was saved. Deserialization therefore never trusts it: fields, actions, or
  resources removed in the meantime surface as the same structured
  `AshA2ui.Dynamic.Error` list a freshly composed spec would produce —
  drift becomes reviewable errors, not a crash. Malformed payloads and
  unknown `spec_format` versions are reported the same way.
  """
  @spec deserialize(String.t(), keyword) :: {:ok, Surface.t()} | {:error, [Error.t()]}
  def deserialize(serialized, opts) when is_binary(serialized) do
    with {:ok, spec} <- Serializer.deserialize(serialized) do
      resolve(spec, opts)
    end
  end

  @doc """
  The human-reviewable change summary between two specs — what a ratifying
  human reads. Accepts spec maps, serialized specs, and `%Surface{}` structs
  interchangeably.

  The diff is computed at the spec vocabulary level (components, queries and
  their presets, fields, actions, contexts, matched by name; option changes
  with old and new values), never as a raw JSON diff. See
  `AshA2ui.Dynamic.Diff` for the change structure and
  `AshA2ui.Dynamic.Diff.summary/1` for the rendered lines.
  """
  @spec diff(map | String.t() | Surface.t(), map | String.t() | Surface.t()) :: Diff.t()
  def diff(old, new) do
    Diff.compute(to_spec!(old), to_spec!(new))
  end

  @doc """
  Promotes a validated spec into the source of a checked-in standalone UI
  module — a formatted, compile-ready `use AshA2ui.Standalone` module with
  the equivalent `a2ui do ... end` block and a provenance comment carrying
  the spec's `fingerprint/1`.

  The spec is validated through `resolve/2` first; promotion of an invalid
  (or drifted) spec returns its errors. Resolving the generated module
  produces a surface equivalent to resolving the spec directly.

  ## Options

    * `:module` (required) — the module name to generate.
    * `:allowlist` (required) — as `resolve/2`; also maps the spec's
      resource names back to modules in the generated source.
    * `:surface_id` — the surface id declared in the generated block.
      Defaults to the underscored last segment of `:module` (a promoted
      surface should have a stable id, not a per-resolve `dyn_` one).
    * `:spec_version` — as `resolve/2`; declared in the generated block
      when not the default.
    * `:via_allowlist` — as `resolve/2`; required for specs whose actions
      declare `via`, since promotion re-resolves the spec first.
  """
  @spec to_dsl_source(map | Surface.t(), keyword) :: {:ok, String.t()} | {:error, [Error.t()]}
  def to_dsl_source(spec_or_surface, opts) do
    Keyword.validate!(opts, [:module, :allowlist, :surface_id, :spec_version, :via_allowlist])
    module = Keyword.fetch!(opts, :module)
    allowlist = Keyword.fetch!(opts, :allowlist)
    spec = to_spec!(spec_or_surface)

    resolve_opts =
      opts
      |> Keyword.take([:allowlist, :spec_version, :via_allowlist])
      |> Keyword.put(:surface_id, "promotion_check")

    with {:ok, surface} <- resolve(spec, resolve_opts) do
      {:ok,
       Promoter.generate(
         spec,
         module,
         surface.resource,
         allowlist,
         Keyword.take(opts, [:surface_id, :spec_version])
       )}
    end
  end

  defp to_spec!(%Surface{spec: spec}), do: spec
  defp to_spec!(spec) when is_map(spec), do: spec

  defp to_spec!(serialized) when is_binary(serialized) do
    case Serializer.deserialize(serialized) do
      {:ok, spec} ->
        spec

      {:error, errors} ->
        raise ArgumentError,
              "not a serialized surface spec: #{Enum.join(Error.messages(errors), "; ")}"
    end
  end

  # --- allowlist ----------------------------------------------------------------

  @doc """
  Normalizes an allowlist: a list of Ash resource modules (named by their
  short module name) or a `%{"name" => Module}` map (names must match the
  spec name format). Raises on non-resources and name collisions —
  the allowlist is host configuration, not client input.
  """
  @spec allowlist([module] | %{String.t() => module}) :: %{String.t() => module}
  def allowlist(resources) when is_list(resources) do
    resources
    |> Map.new(fn resource -> {short_name(resource), resource} end)
    |> tap(fn named ->
      if map_size(named) != length(Enum.uniq(resources)) do
        raise ArgumentError,
              "resource short names collide in #{inspect(resources)} — " <>
                "pass a %{\"name\" => Module} map to disambiguate"
      end
    end)
    |> allowlist()
  end

  def allowlist(named) when is_map(named) do
    Enum.each(named, fn {name, resource} ->
      unless is_binary(name) and name =~ ~r/^[a-zA-Z][a-zA-Z0-9_]*$/ do
        raise ArgumentError, "allowlist name #{inspect(name)} must match ^[a-zA-Z]\\w*$"
      end

      unless Ash.Resource.Info.resource?(resource) do
        raise ArgumentError, "#{inspect(resource)} is not an Ash resource"
      end
    end)

    named
  end

  @doc """
  Every resource of `otp_app`'s configured Ash domains that carries the
  `AshA2ui` extension — a convenient default allowlist: what already has a
  declared surface may also be composed dynamically.
  """
  @spec extension_resources(atom) :: [module]
  def extension_resources(otp_app) do
    otp_app
    |> Application.get_env(:ash_domains, [])
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.filter(&(AshA2ui in Spark.extensions(&1)))
    |> Enum.uniq()
  end

  # --- LLM-facing descriptions -----------------------------------------------------

  @doc """
  A compact, JSON-able description of every allowlisted resource — the
  vocabulary an LLM needs to compose valid specs: public attributes
  (name/type/enum values), public calculations and aggregates, actions
  (type, accepts, arguments), and public relationships. Embed it in the
  tool description or system prompt alongside `spec_schema/1`.
  """
  @spec describe_resources(%{String.t() => module}) :: [map]
  def describe_resources(allowlist) do
    allowlist
    |> Enum.sort_by(fn {name, _resource} -> name end)
    |> Enum.map(fn {name, resource} -> describe_resource(name, resource) end)
  end

  defp describe_resource(name, resource) do
    %{
      "resource" => name,
      "attributes" => Enum.map(Ash.Resource.Info.public_attributes(resource), &describe_field/1),
      "calculations" =>
        Enum.map(Ash.Resource.Info.public_calculations(resource), &describe_field/1),
      "aggregates" =>
        Enum.map(Ash.Resource.Info.public_aggregates(resource), &%{"name" => to_string(&1.name)}),
      "actions" => Enum.map(Ash.Resource.Info.actions(resource), &describe_action/1),
      "relationships" =>
        for relationship <- Ash.Resource.Info.public_relationships(resource) do
          %{
            "name" => to_string(relationship.name),
            "type" => to_string(relationship.type),
            "destination" => short_name(relationship.destination)
          }
        end
    }
  end

  defp describe_field(%{name: name, type: type} = field) do
    base = %{"name" => to_string(name), "type" => type_name(type)}

    case enum_values(field) do
      nil -> base
      values -> Map.put(base, "one_of", Enum.map(values, &to_string/1))
    end
  end

  defp describe_field(%{name: name}), do: %{"name" => to_string(name)}

  defp describe_action(action) do
    base = %{"name" => to_string(action.name), "type" => to_string(action.type)}

    base
    |> put_names("accepts", List.wrap(Map.get(action, :accept)))
    |> put_names("arguments", Enum.map(Map.get(action, :arguments, []), & &1.name))
  end

  defp put_names(map, _key, []), do: map
  defp put_names(map, key, names), do: Map.put(map, key, Enum.map(names, &to_string/1))

  defp enum_values(%{type: Ash.Type.Atom, constraints: constraints}) do
    constraints[:one_of]
  end

  defp enum_values(%{type: type}) do
    if AshA2ui.TypeMapper.enum_type?(Ash.Type.get_type(type)) do
      Ash.Type.get_type(type).values()
    end
  end

  defp type_name(type) do
    type |> Ash.Type.get_type() |> Module.split() |> List.last() |> Macro.underscore()
  rescue
    _not_a_module -> inspect(type)
  end

  # --- spec schema ------------------------------------------------------------------

  @doc """
  The JSON Schema (draft-07-compatible object schema) of the surface spec,
  ready to use as an LLM tool parameter schema. `allowlist` constrains the
  `resource` (and context `resource`) enums to the host's allowlisted names.
  """
  @spec spec_schema(%{String.t() => module}) :: map
  def spec_schema(allowlist) do
    resource_names = allowlist |> Map.keys() |> Enum.sort()
    name = %{"type" => "string", "pattern" => "^[a-zA-Z][a-zA-Z0-9_]*$", "maxLength" => 64}
    name_list = %{"type" => "array", "items" => name, "maxItems" => 64}

    %{
      "type" => "object",
      "description" =>
        "A declarative A2UI surface spec: components over ONE resource, referencing " <>
          "its attributes and actions by name. The server validates every reference " <>
          "and builds the actual UI payload.",
      "properties" => %{
        "resource" => %{
          "type" => "string",
          "enum" => resource_names,
          "description" => "The resource this surface renders."
        },
        "title" => %{
          "type" => "string",
          "maxLength" => 120,
          "description" => "Human-readable panel title."
        },
        "components" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 64,
          "items" => component_schema(name, name_list, resource_names),
          "description" =>
            "The surface's components: usually one table (plus optionally one form). " <>
              "Multiple tables/details need distinguishing names."
        },
        "queries" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => query_schema(name, name_list),
          "description" =>
            "Named search/sort/filter/pagination allowlists referenced by tables via " <>
              "their \"query\". Only declared fields become searchable/sortable/filterable."
        },
        "fields" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => field_schema(name, name_list),
          "description" => "Optional per-field presentation overrides, shared across components."
        },
        "actions" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => action_schema(name, name_list),
          "description" =>
            "Optional per-action metadata for row actions or the form's actions: refresh " <>
              "targets, argument prompts, per-row visibility conditions."
        },
        "contexts" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => context_schema(name, name_list, resource_names),
          "description" =>
            "Named record selections (\"pick a user\") that scope tables " <>
              "(context_filter) and detail components. Advanced; omit unless needed."
        }
      },
      "required" => ["resource", "components"],
      "additionalProperties" => false
    }
  end

  defp component_schema(name, name_list, resource_names) do
    %{
      "type" => "object",
      "properties" => %{
        "kind" => %{
          "type" => "string",
          "enum" => ["table", "form", "detail"],
          "description" =>
            "table renders records of a read action; form renders a create/update form; " <>
              "detail renders a context's selected record."
        },
        "name" => Map.put(name, "description", "Distinguishing name (multi-table/detail only)."),
        "fields" =>
          Map.put(
            name_list,
            "description",
            "Fields shown, in order. Omit to infer (public attributes for tables, the " <>
              "create action's accepts for forms). Form fields must be accepted by the " <>
              "form's actions."
          ),
        "read_action" =>
          Map.put(name, "description", "Read action for tables (default: primary read)."),
        "create_action" => Map.put(name, "description", "Create action the form submits."),
        "update_action" => Map.put(name, "description", "Update action the form submits."),
        "row_actions" =>
          Map.put(
            name_list,
            "description",
            "Actions rendered as per-row buttons (update/destroy/generic actions of the resource)."
          ),
        "query" => Map.put(name, "description", "Name of a declared query (tables only)."),
        "resource" => %{
          "type" => "string",
          "enum" => resource_names,
          "description" =>
            "Related table (tables only): the resource this table reads when it is not " <>
              "the surface's, scoped by a context via context_filter/require_context " <>
              "(e.g. a selected user's orders). Its fields, query, context_filter keys, " <>
              "source paths and links refer to this resource. Read-only: no row_actions " <>
              "or sections."
        },
        "context_filter" => %{
          "type" => "object",
          "additionalProperties" => name,
          "description" =>
            "Table scoping: attribute name -> context name; the context's selected " <>
              "record id filters the table."
        },
        "require_context" =>
          Map.put(
            name_list,
            "description",
            "Contexts that must be selected before the table reads."
          ),
        "select_context" =>
          Map.put(
            name,
            "description",
            "Context a table row's Select button selects into (master/detail)."
          ),
        "context" =>
          Map.put(
            name,
            "description",
            "The context a detail component renders (required on detail)."
          ),
        "display" => %{
          "type" => "string",
          "enum" => ["list", "board", "calendar"],
          "description" =>
            "Tables only: \"calendar\" shows the records on a month, week or day " <>
              "grid placed by date_field; it needs date_field and a query (the query " <>
              "reads only the visible window). \"board\" shows source-less sections " <>
              "as lanes side by side (optionally split into swimlanes); it needs " <>
              "sections without a source and a row_layout. Default \"list\"."
        },
        "date_field" =>
          Map.put(
            name,
            "description",
            "Calendar tables: the date or datetime attribute that places each record."
          ),
        "end_date_field" =>
          Map.put(
            name,
            "description",
            "Calendar tables (optional): a date or datetime attribute holding each " <>
              "record's end; records overlapping the window are shown."
          ),
        "granularity" => %{
          "type" => "string",
          "enum" => Enum.map(AshA2ui.Calendar.granularities(), &Atom.to_string/1),
          "description" => "Calendar tables: the visible window (default \"month\")."
        },
        "granularities" => %{
          "type" => "array",
          "items" => %{
            "type" => "string",
            "enum" => Enum.map(AshA2ui.Calendar.granularities(), &Atom.to_string/1)
          },
          "description" =>
            "Calendar tables: the window sizes the user may switch between " <>
              "(default: only granularity)."
        },
        "row_layout" => %{
          "type" => "object",
          "description" => "Card-style table rows: a title header plus a labeled metadata grid.",
          "properties" => %{
            "title" => Map.put(name, "description", "Field rendered as the card heading."),
            "badge" => Map.put(name, "description", "Field rendered as a status badge."),
            "badge_text" => %{
              "type" => "object",
              "additionalProperties" => %{"type" => "string"},
              "description" => "Display text per badge value, e.g. {\"true\": \"Active\"}."
            },
            "badge_tones" => %{
              "type" => "object",
              "additionalProperties" => %{
                "type" => "string",
                "enum" => Enum.map(AshA2ui.RowLayout.tones(), &Atom.to_string/1)
              },
              "description" => "Semantic tone per badge value, e.g. {\"true\": \"success\"}."
            },
            "meta" =>
              Map.put(
                name_list,
                "description",
                "Fields in the metadata grid (defaults to the rest)."
              ),
            "columns" => %{"type" => "integer", "minimum" => 1, "maximum" => 6}
          },
          "required" => ["title"],
          "additionalProperties" => false
        },
        "columns" => %{
          "type" => "array",
          "maxItems" => 64,
          "description" =>
            "Tables only: how the data grid draws a field's cell beyond its value. " <>
              "The fields a column reads from must be table fields; they are drawn " <>
              "inside it, not as columns of their own.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => Map.put(name, "description", "The table field this column draws."),
              "subtitle" =>
                Map.put(name, "description", "Field drawn as a second line under the value."),
              "icon" =>
                Map.put(name, "description", "Field whose value picks an icon before the value."),
              "icon_names" => %{
                "type" => "object",
                "additionalProperties" => %{
                  "type" => "string",
                  "enum" => Enum.map(AshA2ui.Column.icons(), &Atom.to_string/1)
                },
                "description" => "Icon per icon value, e.g. {\"high\": \"alert\"}."
              },
              "icon_tones" => %{
                "type" => "object",
                "additionalProperties" => %{
                  "type" => "string",
                  "enum" => Enum.map(AshA2ui.RowLayout.tones(), &Atom.to_string/1)
                },
                "description" => "Tone per icon value, e.g. {\"high\": \"danger\"}."
              },
              "icon_labels" => %{
                "type" => "object",
                "additionalProperties" => %{"type" => "string"},
                "description" => "Accessible label per icon value (default: the humanized value)."
              },
              "more" =>
                Map.put(
                  name,
                  "description",
                  "Field counting the cell's values; 2 or more adds a \"+N more\" tag."
                ),
              "detail" =>
                Map.put(
                  name,
                  "description",
                  "Field whose value picks a detail line under the value."
                ),
              "detail_date" =>
                Map.put(
                  name,
                  "description",
                  "Date field put in place of {date} in the detail text."
                ),
              "detail_text" => %{
                "type" => "object",
                "additionalProperties" => %{"type" => "string"},
                "description" =>
                  "Detail text per detail value, e.g. {\"overdue\": \"Overdue since {date}\"}."
              },
              "detail_icon_names" => %{
                "type" => "object",
                "additionalProperties" => %{
                  "type" => "string",
                  "enum" => Enum.map(AshA2ui.Column.icons(), &Atom.to_string/1)
                },
                "description" => "Icon before the detail line per detail value."
              },
              "detail_icon_tones" => %{
                "type" => "object",
                "additionalProperties" => %{
                  "type" => "string",
                  "enum" => Enum.map(AshA2ui.RowLayout.tones(), &Atom.to_string/1)
                },
                "description" => "Tone of that icon per detail value."
              }
            },
            "required" => ["name"],
            "additionalProperties" => false
          }
        },
        "groups" => %{
          "type" => "array",
          "maxItems" => 64,
          "description" => "Labeled N-column sections of form fields (forms only).",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => name,
              "label" => %{"type" => "string"},
              "columns" => %{"type" => "integer", "minimum" => 1, "maximum" => 6},
              "fields" => name_list
            },
            "required" => ["name", "fields"],
            "additionalProperties" => false
          }
        },
        "nested_forms" => %{
          "type" => "array",
          "maxItems" => 64,
          "description" =>
            "Nested relationship sub-forms (forms only), named by the action argument a " <>
              "manage_relationship change consumes on the form's create/update actions. " <>
              "The interaction mode (pick existing vs. create inline) is inferred from that change.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" =>
                Map.put(
                  name,
                  "description",
                  "The action argument this nested form edits (managed by manage_relationship)."
                ),
              "label" => %{"type" => "string", "maxLength" => 120},
              "fields" =>
                Map.put(
                  name_list,
                  "description",
                  "Destination attributes rendered as sub-form inputs (create-inline mode)."
                ),
              "option_label" =>
                Map.put(
                  name,
                  "description",
                  "Destination attribute shown as the pick-existing option label."
                ),
              "option_value" =>
                Map.put(name, "description", "Destination attribute submitted as the value."),
              "option_sort" =>
                Map.put(name, "description", "Destination attribute options are sorted by."),
              "option_limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500},
              "option_search" =>
                Map.put(
                  name_list,
                  "description",
                  "Destination string attributes searched; makes the pick-existing select searchable."
                )
            },
            "required" => ["name"],
            "additionalProperties" => false
          }
        },
        "sections" => %{
          "type" => "object",
          "description" =>
            "Dynamic table sets (tables only): this table becomes a template expanded at " <>
              "render time into one concrete table per section, each scoped by scope_by == " <>
              "the section's value. With a source, one section per record of the source " <>
              "resource (allowlisted; its read is authorized). Without a source, one " <>
              "section per enumerated value of scope_by (an Ash.Type.Enum or one_of " <>
              "attribute) — a board's lanes, optionally split by swimlanes_by into rows. " <>
              "A composed board may expand to at most #{@max_composed_cells} cells (lanes x " <>
              "swimlanes). Board totals count only the listed swimlanes: records whose " <>
              "swimlane attribute is nil appear in no row, so map nil to a value of its own " <>
              "with a calculation and swimlane by that.",
          "properties" => %{
            "source" => %{
              "type" => "string",
              "enum" => resource_names,
              "description" => "The resource whose records enumerate the sections."
            },
            "scope_by" =>
              Map.put(
                name,
                "description",
                "Public attribute of this table's resource each section's reads filter on " <>
                  "(scope_by == <section value>)."
              ),
            "label" =>
              Map.put(
                name,
                "description",
                "Source attribute shown as each section's table heading."
              ),
            "value" =>
              Map.put(
                name,
                "description",
                "Source attribute providing each section's scope value and runtime name " <>
                  "(defaults to the source's primary key)."
              ),
            "read_action" =>
              Map.put(name, "description", "Source read action enumerating the sections."),
            "sort" =>
              Map.put(
                name,
                "description",
                "Source attribute the sections are ordered by (ascending)."
              ),
            "values" => %{
              "type" => "array",
              "items" => %{"type" => "string", "maxLength" => 64},
              "minItems" => 1,
              "maxItems" => 64,
              "description" =>
                "Source-less only: the scope_by values that become lanes, in order " <>
                  "(default: all of them)."
            },
            "labels" => %{
              "type" => "object",
              "additionalProperties" => %{"type" => "string", "maxLength" => 60},
              "description" =>
                "Source-less only: plain-text lane headings per value, e.g. " <>
                  "{\"open\": \"To do\"} (no markup characters)."
            },
            "swimlanes_by" =>
              Map.put(
                name,
                "description",
                "Boards only: a second enumerated attribute splitting the board into rows."
              ),
            "swimlane_values" => %{
              "type" => "array",
              "items" => %{"type" => "string", "maxLength" => 64},
              "minItems" => 1,
              "maxItems" => 64,
              "description" => "The swimlanes_by values that become rows, in order."
            },
            "swimlane_labels" => %{
              "type" => "object",
              "additionalProperties" => %{"type" => "string", "maxLength" => 60},
              "description" => "Plain-text row headings per swimlane value."
            },
            "swimlane_tones" => %{
              "type" => "object",
              "additionalProperties" => %{
                "type" => "string",
                "enum" => Enum.map(AshA2ui.RowLayout.tones(), &Atom.to_string/1)
              },
              "description" => "A tone per swimlane value (row background)."
            },
            "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500}
          },
          "required" => ["scope_by"],
          "additionalProperties" => false
        }
      },
      "required" => ["kind"],
      "additionalProperties" => false
    }
  end

  defp query_schema(name, name_list) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => name,
        "search_fields" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => %{"anyOf" => [name, name_list]},
          "description" =>
            "String attributes searched case-insensitively; entries are names or " <>
              "relationship paths like [\"author\", \"email\"]."
        },
        "sortable" => Map.put(name_list, "description", "Attributes the client may sort by."),
        "filters" =>
          Map.put(name_list, "description", "Attributes the client may equality-filter on."),
        "hidden_filters" =>
          Map.put(
            name_list,
            "description",
            "Entries of filters that get no picker: the page sets them itself, and " <>
              "they still apply."
          ),
        "range_filters" =>
          Map.put(
            name_list,
            "description",
            "Date/numeric attributes the client may range-filter on."
          ),
        "default_sort" => %{
          "type" => "array",
          "maxItems" => 8,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "field" => name,
              "direction" => %{"type" => "string", "enum" => ["asc", "desc"]}
            },
            "required" => ["field"],
            "additionalProperties" => false
          }
        },
        "presets" => %{
          "type" => "array",
          "maxItems" => 64,
          "description" => "Named server-side composite filters selected by name.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => name,
              "filter" => %{
                "type" => "object",
                "description" =>
                  "Attribute -> value conditions ANDed together (null means is-nil, " <>
                    "an array means membership)."
              },
              "read_action" => name,
              "calendar_anchor" => %{
                "type" => "integer",
                "minimum" => -366,
                "maximum" => 366,
                "description" =>
                  "Calendar tables only: switching to this preset moves the window to " <>
                    "today plus this many days and clears the picked day."
              }
            },
            "required" => ["name"],
            "additionalProperties" => false
          }
        },
        "default_preset" => name,
        "preset_picker" => %{
          "type" => "boolean",
          "description" =>
            "false when the page selects the preset itself: the presets apply, the " <>
              "picker is not emitted. Defaults to true."
        },
        "apply_on_change" => %{
          "type" => "boolean",
          "description" =>
            "true to apply the query as its controls change (search after a pause), " <>
              "without an Apply click. Defaults to false."
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
        "max_page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      },
      "required" => ["name"],
      "additionalProperties" => false
    }
  end

  defp field_schema(name, name_list) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => name,
        "label" => %{"type" => "string", "maxLength" => 120},
        "widget" => %{
          "type" => "string",
          "enum" => ["text_field", "check_box", "choice_picker", "date_time_input"]
        },
        "format" => %{"type" => "string", "enum" => ["date"]},
        "order" => %{"type" => "integer", "minimum" => 0, "maximum" => 1000},
        "hidden" => %{"type" => "boolean"},
        "source" =>
          Map.put(
            name_list,
            "description",
            "Relationship path a table column reads through, e.g. [\"user\", \"email\"]. Table-only."
          ),
        "relationship" =>
          Map.put(
            name,
            "description",
            "belongs_to relationship this form field selects a record for."
          ),
        "option_label" => name,
        "option_value" => name,
        "option_sort" => name,
        "option_limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500},
        "option_search" =>
          Map.put(
            name_list,
            "description",
            "Destination string attributes searched; makes a relationship select searchable."
          ),
        "link" => %{
          "anyOf" => [
            Map.put(
              name,
              "description",
              "A public to-one relationship (belongs_to/has_one): the cell links to the " <>
                "related record's surface."
            ),
            %{
              "type" => "object",
              "description" =>
                "A bare-id reference: the surface key that shows the record and the " <>
                  ~s(attribute path holding its id, e.g. {"surface": "user", "path": ) <>
                  ~s(["subject_id"]}.),
              "properties" => %{
                "surface" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
                "path" => Map.put(name_list, "minItems", 1)
              },
              "required" => ["surface", "path"],
              "additionalProperties" => false
            }
          ],
          "description" =>
            "Render this table/detail field as a reference link. Table/detail only."
        },
        "links" =>
          Map.put(
            name,
            "description",
            "A public to-many relationship (has_many/many_to_many) rendered as a list of " <>
              "reference links. Table/detail only."
          ),
        "link_label" =>
          Map.put(
            name,
            "description",
            "Destination attribute labelling each link (relationship links only)."
          )
      },
      "required" => ["name"],
      "additionalProperties" => false
    }
  end

  defp action_schema(name, name_list) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => Map.put(name, "description", "The Ash action this metadata applies to."),
        "label" => %{
          "type" => "string",
          "maxLength" => 120,
          "description" =>
            "Button text for the action (row, bulk and prompt buttons); defaults to the " <>
              "humanized action name."
        },
        "refreshes" =>
          Map.put(
            name_list,
            "description",
            "Table components refreshed after success (default: all)."
          ),
        "prompt_fields" =>
          Map.put(
            name_list,
            "description",
            "Action arguments/accepts collected in a modal prompt before invoking (row actions only)."
          ),
        "prompt_title" => %{"type" => "string", "maxLength" => 120},
        "visible_when" => %{
          "type" => "object",
          "description" =>
            "Per-record conditions gating the row action (attribute -> value; null means " <>
              "is-nil, an array means membership)."
        },
        "via" => %{
          "type" => "object",
          "description" =>
            "Host-delegated dispatch for a row action: instead of running the Ash action, " <>
              "the handler calls the host's function with a dispatch context (record, actor, " <>
              "action, surface id, context selections) prepended to \"args\". The module must " <>
              "exist in the host runtime and be listed in the resolve's :via_allowlist; row " <>
              "actions only, mutually exclusive with prompt_fields.",
          "properties" => %{
            "mfa" => %{
              "type" => "string",
              "pattern" => "^[A-Z][A-Za-z0-9_.]*\\.[a-zA-Z_][a-zA-Z0-9_?!]*/[0-9]+$",
              "description" =>
                "The delegate as \"Module.function/arity\". Arity is the delegate's full " <>
                  "arity: the dispatch context is prepended to \"args\", so arity = 1 + " <>
                  "length(args)."
            },
            "args" => %{
              "type" => "array",
              "maxItems" => 16,
              "description" => "Extra arguments appended after the dispatch context."
            }
          },
          "required" => ["mfa"],
          "additionalProperties" => false
        }
      },
      "required" => ["name"],
      "additionalProperties" => false
    }
  end

  defp context_schema(name, name_list, resource_names) do
    %{
      "type" => "object",
      "properties" => %{
        "name" => name,
        "resource" => %{"type" => "string", "enum" => resource_names},
        "label" => %{"type" => "string", "maxLength" => 120},
        "option_label" => name,
        "option_value" => name,
        "option_sort" => name,
        "option_limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 500},
        "option_search" => name_list,
        "depends_on" => name,
        "depends_on_path" => name_list,
        "auto_select_single" => %{"type" => "boolean"},
        "picker" => %{"type" => "boolean"}
      },
      "required" => ["name", "resource"],
      "additionalProperties" => false
    }
  end

  # --- internals ----------------------------------------------------------------------

  defp spec_resource(spec, allowlist) when is_map(spec) do
    case Map.fetch(spec, "resource") do
      {:ok, name} when is_binary(name) ->
        case Map.fetch(allowlist, name) do
          {:ok, resource} ->
            {:ok, resource}

          :error ->
            {:error,
             [
               Error.new(
                 "resource",
                 "resource #{inspect(name)} is not available to dynamic surfaces — " <>
                   "use one of: #{Enum.join(Enum.sort(Map.keys(allowlist)), ", ")}"
               )
             ]}
        end

      _missing_or_not_binary ->
        {:error, [Error.new("resource", ~s(the spec must name a "resource" string))]}
    end
  end

  defp spec_resource(_spec, _allowlist),
    do: {:error, [Error.new("", "the surface spec must be a JSON object")]}

  defp spec_title(spec) do
    case Map.get(spec, "title") do
      nil -> {:ok, nil}
      title when is_binary(title) -> {:ok, title}
      _other -> {:error, [Error.new("title", "title must be a string")]}
    end
  end

  defp require_component(entities) do
    if Enum.any?(entities, &is_struct(&1, AshA2ui.Component)) do
      :ok
    else
      {:error, [Error.new("components", "the spec must declare at least one component")]}
    end
  end

  # The RCE guard for spec-carried `via` delegations: a via MFA runs host
  # code at action time, so the callable modules are host configuration —
  # the same trust boundary as the resource allowlist. (The parser has
  # already validated the delegate exists; this decides whether the host
  # permits calling it.)
  defp validate_via_allowlist(entities, via_allowlist) do
    entities
    |> Enum.filter(&is_struct(&1, AshA2ui.Action))
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%AshA2ui.Action{via: nil}, _index} ->
        []

      {%AshA2ui.Action{via: {module, _function, _args}}, index} ->
        if module in via_allowlist do
          []
        else
          [
            Error.new(
              "actions[#{index}].via",
              "module #{inspect(module)} is not in the resolve's :via_allowlist — " <>
                "via delegates run host code, so the callable modules are host configuration"
            )
          ]
        end
    end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # The synthetic standalone-style DSL state the shared transformers,
  # verifiers, ResolvedView, Info, and ActionHandler all consume — the same
  # map shape Spark hands them at compile time, minus a real module.
  defp synthetic_dsl_state(resource, surface_id, spec_version, entities) do
    %{
      [:a2ui] => %{
        entities: entities,
        opts: [for_resource: resource, surface_id: surface_id, spec_version: spec_version]
      },
      :persist => %{module: __MODULE__, extensions: []}
    }
  end

  defp infer_fields(dsl_state) do
    case InferFields.transform(dsl_state) do
      {:ok, dsl_state} -> {:ok, dsl_state}
      {:error, error} -> {:error, [Error.new("", error_text(error))]}
    end
  end

  # The compile-time verifiers, unchanged, in the extension's declared
  # order. Every verifier runs (an LLM correcting several mistakes at once
  # converges faster than one-error-at-a-time).
  defp run_verifiers(dsl_state) do
    AshA2ui.verifiers()
    |> Enum.flat_map(fn verifier ->
      case verifier.verify(dsl_state) do
        :ok -> []
        {:error, %Spark.Error.DslError{} = error} -> [Error.from_dsl_error(error)]
        {:error, error} -> [Error.new("", error_text(error))]
      end
    end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  The most tables a composed (source-less) sections block may expand to:
  #{@max_composed_cells} lanes × swimlanes. Every cell is a page read plus a
  count on every render and refresh, so a composed spec gets a hard cap
  even where a declared board may set a higher `limit`.
  """
  @spec max_composed_cells() :: pos_integer
  def max_composed_cells, do: @max_composed_cells

  # Composed surfaces on top of the shared verifiers (which have already
  # passed): a source-less sections block expands to at most
  # @max_composed_cells tables, counted by the same AshA2ui.Board.cell_count/2
  # as the declared limit. (The parser has already refused a board with a
  # `source`.)
  defp validate_composed_sections(dsl_state, resource) do
    dsl_state
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
    |> Enum.with_index()
    |> Enum.flat_map(fn {component, index} ->
      composed_sections_errors(component, resource, "components[#{index}].sections")
    end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp composed_sections_errors(%{sections: nil}, _resource, _path), do: []

  defp composed_sections_errors(
         %{sections: %{source: nil} = sections} = component,
         resource,
         path
       ) do
    table_resource = component.resource || resource

    case AshA2ui.Board.cell_count(table_resource, sections) do
      {:ok, cells} when cells > @max_composed_cells ->
        [
          Error.new(
            path,
            "this board expands to #{cells} cells (lanes x swimlanes); a composed board may " <>
              "have at most #{@max_composed_cells}, since every cell is a page read and a " <>
              "count on every render — narrow values or swimlane_values"
          )
        ]

      _within_cap_or_not_enumerable ->
        []
    end
  end

  defp composed_sections_errors(_component, _resource, _path), do: []

  defp error_text(error) when is_binary(error), do: error
  defp error_text(error) when is_exception(error), do: Exception.message(error)
  defp error_text(error), do: inspect(error)

  defp generate_surface_id(resource) do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    "dyn_#{Macro.underscore(short_name(resource))}_#{suffix}"
  end

  defp short_name(resource) do
    resource |> Module.split() |> List.last()
  end
end
