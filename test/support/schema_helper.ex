defmodule AshA2ui.Test.SchemaHelper do
  @moduledoc """
  Validates A2UI 1.0 payloads against the spec schemas vendored in
  `priv/a2ui/v1_0` (see its NOTES.md for the pin and the file map).

  Validation is JSON Schema draft 2020-12 through JSV, the draft the spec
  declares, so `unevaluatedProperties` and the other 2020-12 keywords are
  enforced as the upstream reference runner (ajv, `--spec=draft2020`,
  `ajv-formats`) enforces them. String formats are asserted too.

  The API, every function on decoded JSON (string keys):

    * messages the agent sends: `assert_valid_agent_message/2`,
      `assert_valid_agent_messages/2` (a list, against
      `agent_to_renderer_list.json`), `validate_agent_message/2`;
    * messages the renderer sends: `assert_valid_renderer_message/2`,
      `validate_renderer_message/2`;
    * the catalogs a payload uses are `catalogs: [file, ...]`, paths relative
      to `priv/a2ui/v1_0` (default: the basic and ash_a2ui catalogs, what
      every ash_a2ui surface uses; an admin surface adds
      `admin_catalogs/0`);
    * catalogs: `assert_valid_catalog/1`, `validate_catalog/1` (structure
      against `catalog_definition.json`, plus the UAX #31 identifier and
      restricted-`$ref`-target rules the upstream runner checks in code);
    * anything else: `spec_schema/2` for a vendored schema file, `build_schema/2`
      for an ad-hoc schema map, `validate/2` against either, and
      `validate_catalog_component/3` for one component of a catalog.

  Every validator returns `:ok` or `{:error, errors}`, where `errors` is a
  list of `"<instance location>: <message>"` strings.
  """

  import ExUnit.Assertions

  alias AshA2ui.Test.SchemaHelper.Resolver

  # The schemas of common_types.json a catalog may `$ref`, per rule 3
  # ("Restricted `$ref` Targets") of the catalog schema rules in
  # docs/a2ui_protocol.md.
  @allowed_external_ref_targets ~w(ComponentId Child ChildList DynamicString DynamicNumber
                                   DynamicBoolean DynamicStringList DynamicValue
                                   AccessibilityAttributes CheckRule Checkable Action
                                   DataBinding FunctionCall)

  # Keys whose values are annotations or literal data, not subschemas.
  @non_schema_keys ~w(metadata examples const default enum description)

  # Protocol directives a catalog may declare as properties; their `@` is
  # outside the identifier grammar on purpose.
  @reserved_directives ~w(@path @call)

  # UAX #31 default identifiers (XID_Start / XID_Continue), with `_` allowed
  # first, as Python's str.isidentifier/0 accepts in the upstream runner.
  @identifier ~r/\A[\p{L}\p{Nl}_][\p{L}\p{Nl}\p{Mn}\p{Mc}\p{Nd}\p{Pc}]*\z/u

  ## Messages
  #
  # Every message function takes `catalogs:`, the catalog file or list of
  # mixed catalog files the payload uses (see `spec_schema/2`).

  @doc "Asserts `message` is a valid agent-to-renderer message. Returns it."
  def assert_valid_agent_message(message, opts \\ []),
    do:
      assert_valid(
        validate_agent_message(message, opts),
        message,
        "agent-to-renderer message",
        opts
      )

  @doc "Asserts `messages` is a valid agent-to-renderer message list. Returns it."
  def assert_valid_agent_messages(messages, opts \\ []) when is_list(messages) do
    result = validate(spec_schema("agent_to_renderer_list.json", opts), messages)
    assert_valid(result, messages, "agent-to-renderer message list", opts)
  end

  @doc "Asserts `message` is a valid renderer-to-agent message. Returns it."
  def assert_valid_renderer_message(message, opts \\ []),
    do:
      assert_valid(
        validate_renderer_message(message, opts),
        message,
        "renderer-to-agent message"
      )

  @doc "Validates an agent-to-renderer message."
  def validate_agent_message(message, opts \\ []),
    do: validate(spec_schema("agent_to_renderer.json", opts), message)

  @doc "Validates a renderer-to-agent message."
  def validate_renderer_message(message, opts \\ []),
    do: validate(spec_schema("renderer_to_agent.json", opts), message)

  ## Catalogs

  @doc """
  The catalog files an admin-catalog (`catalog: :admin_v1`) surface uses:
  pass them as `catalogs:`.
  """
  def admin_catalogs,
    do: [
      "catalogs/basic/v1/catalog.json",
      "catalogs/ash_a2ui/catalog.json",
      "../admin_v1/catalog.json"
    ]

  @doc "Asserts `catalog` is a valid catalog definition. Returns it."
  def assert_valid_catalog(catalog),
    do: assert_valid(validate_catalog(catalog), catalog, "catalog")

  @doc """
  Validates a catalog the way the upstream runner does: its structure against
  `catalog_definition.json`, every entity and property name against UAX #31,
  and every `$ref` against the restricted target list.
  """
  def validate_catalog(catalog) do
    structural =
      case validate(spec_schema("catalog_definition.json"), catalog) do
        :ok -> []
        {:error, errors} -> errors
      end

    case structural ++ identifier_errors(catalog) ++ ref_target_errors(catalog) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Validates `component` against the schema of the component `name` in
  `catalog` (a decoded catalog map), with the catalog's `$defs` in scope and
  its relative refs (`common_types.json#/$defs/...`) resolved against the
  vendored spec.
  """
  def validate_catalog_component(catalog, name, component) do
    catalog
    |> Map.fetch!("components")
    |> Map.fetch!(name)
    |> Map.put("$defs", Map.get(catalog, "$defs", %{}))
    |> Map.put("$id", Resolver.base() <> "catalog_component_#{name}.json")
    |> build_schema()
    |> validate(component)
  end

  ## Schemas

  @doc """
  The built schema of a vendored file, named by its basename under
  `priv/a2ui/v1_0/json` (`"agent_to_renderer.json"`, ...) or as
  `"testing_catalog.json"`.

  `catalogs:` names the catalog file, or the list of mixed catalog files,
  that the `catalog.json` refs resolve to (relative to `priv/a2ui/v1_0`), as
  a conformance suite's `"catalog"` key does upstream. The default is the
  basic and ash_a2ui catalogs. A payload that mixes catalogs (`@catalogId`,
  `FunctionCall.catalogId`) validates against the list of every catalog it
  uses. Built schemas are cached.
  """
  def spec_schema(file, opts \\ []) do
    catalogs = Keyword.get(opts, :catalogs)
    key = {__MODULE__, file, catalogs}

    case :persistent_term.get(key, nil) do
      nil ->
        root = build_schema(%{"$ref" => Resolver.base() <> file}, catalogs: catalogs)
        :persistent_term.put(key, root)
        root

      root ->
        root
    end
  end

  @doc """
  Builds an ad-hoc schema map (draft 2020-12 unless it says otherwise). Refs
  to `https://a2ui.org/specification/v1_0/...` resolve to the vendored files.
  """
  def build_schema(raw, opts \\ []) do
    JSV.build!(raw,
      resolver: [{Resolver, catalogs: Keyword.get(opts, :catalogs)}, JSV.Resolver.Embedded],
      formats: true
    )
  end

  @doc "Validates `data` against a built schema."
  def validate(%JSV.Root{} = root, data) do
    case JSV.validate(data, root, cast: false) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, format_errors(error)}
    end
  end

  ## Internals

  defp assert_valid(result, value, what, opts \\ [])

  defp assert_valid(:ok, value, _what, _opts), do: value

  defp assert_valid({:error, errors}, value, what, opts) do
    errors =
      case component_diagnostics(value, opts) do
        [] -> errors
        diagnostics -> diagnostics
      end

    flunk("""
    Expected a valid A2UI 1.0 #{what}, got:

    #{Enum.map_join(errors, "\n", &("  " <> &1))}

    #{inspect(value, pretty: true, limit: :infinity)}
    """)
  end

  # JSV nests the errors of combinators (`oneOf`, `allOf`, `$ref`) in
  # sub-units; the leaves are the actionable ones.
  defp format_errors(error) do
    error
    |> JSV.normalize_error()
    |> Map.get(:details, [])
    |> Enum.flat_map(&leaf_errors/1)
    |> Enum.uniq()
  end

  defp leaf_errors(%{valid: true}), do: []

  defp leaf_errors(unit) do
    Enum.flat_map(Map.get(unit, :errors, []), fn
      %{details: [_ | _] = details} -> Enum.flat_map(details, &leaf_errors/1)
      error -> ["#{unit[:instanceLocation]}: #{error[:message]}"]
    end)
  end

  # A component that fails `anyComponent` is reported against every kind it
  # is not. Validating each component against its own kind alone (the
  # envelope keys plus the catalog's definition) names the real problem.
  defp component_diagnostics(message, opts) do
    files = Resolver.catalog_files(opts)

    for components <- message_components(message),
        {component, index} <- Enum.with_index(components),
        {:error, errors} <- [validate_component(component, files, opts)],
        error <- errors do
      "component #{index} (#{inspect(component["id"])}, #{inspect(component["component"])}) #{error}"
    end
  end

  defp message_components(messages) when is_list(messages),
    do: Enum.flat_map(messages, &message_components/1)

  defp message_components(%{"createSurface" => %{"components" => [_ | _] = components}}),
    do: [components]

  defp message_components(%{"updateComponents" => %{"components" => [_ | _] = components}}),
    do: [components]

  defp message_components(_message), do: []

  defp validate_component(%{"component" => kind} = component, files, opts) when is_binary(kind) do
    case Enum.find_index(files, &(&1 |> Resolver.read!() |> get_in(["components", kind]))) do
      nil ->
        {:error, ["#: no catalog in use declares #{inspect(kind)}"]}

      index ->
        uri = Resolver.base() <> Resolver.catalog_uri(files, index)

        %{
          "allOf" => [
            %{"$ref" => Resolver.base() <> "common_types.json#/$defs/ComponentCommon"},
            %{"$ref" => uri <> "#/components/" <> kind}
          ],
          "unevaluatedProperties" => false
        }
        |> build_schema(opts)
        |> validate(component)
    end
  end

  defp validate_component(_component, _files, _opts), do: {:error, ["#: no component kind"]}

  defp identifier_errors(catalog) do
    named = fn section, what, trim ->
      catalog
      |> Map.get(section, %{})
      |> Enum.reject(fn {name, _} -> name in ["anyComponent", "anyFunction"] end)
      |> Enum.flat_map(fn {name, definition} ->
        check_identifier(trim.(name), what) ++ property_name_errors(definition)
      end)
    end

    named.("components", "component name", & &1) ++
      named.("functions", "function name", &String.trim_leading(&1, "@")) ++
      named.("$defs", "$defs name", & &1)
  end

  defp property_name_errors(%{} = schema) do
    own =
      schema
      |> Map.get("properties", %{})
      |> property_entries()
      |> Enum.flat_map(fn {name, definition} ->
        name_errors =
          if name in @reserved_directives, do: [], else: check_identifier(name, "property name")

        name_errors ++ property_name_errors(definition)
      end)

    extensions =
      case schema do
        %{"metadata" => %{"extensions" => %{} = extensions}} ->
          Enum.flat_map(Map.keys(extensions), &check_identifier(&1, "extension identifier"))

        _ ->
          []
      end

    nested =
      schema
      |> Map.drop(["properties", "metadata", "examples", "description", "const", "default"])
      |> Map.values()
      |> Enum.flat_map(&property_name_errors/1)

    own ++ extensions ++ nested
  end

  defp property_name_errors(list) when is_list(list),
    do: Enum.flat_map(list, &property_name_errors/1)

  defp property_name_errors(_scalar), do: []

  defp property_entries(%{} = properties), do: Enum.to_list(properties)
  defp property_entries(_), do: []

  defp check_identifier(name, what) do
    if Regex.match?(@identifier, name), do: [], else: ["invalid #{what}: #{inspect(name)}"]
  end

  defp ref_target_errors(catalog) do
    sections = Map.new(~w(components functions $defs), &{&1, Map.get(catalog, &1, %{})})

    sections
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
    |> Enum.flat_map(&collect_refs/1)
    |> Enum.flat_map(&check_ref(&1, sections))
  end

  defp collect_refs(%{} = schema) do
    own = if is_binary(schema["$ref"]), do: [schema["$ref"]], else: []

    properties =
      case schema["properties"] do
        %{} = properties -> Enum.flat_map(Map.values(properties), &collect_refs/1)
        _ -> []
      end

    nested =
      schema
      |> Map.drop(["properties" | @non_schema_keys])
      |> Map.values()
      |> Enum.flat_map(&collect_refs/1)

    own ++ properties ++ nested
  end

  defp collect_refs(list) when is_list(list), do: Enum.flat_map(list, &collect_refs/1)
  defp collect_refs(_scalar), do: []

  defp check_ref("#/$defs/" <> target = ref, _sections)
       when target in ["anyComponent", "anyFunction"],
       do: ["disallowed $ref target: #{inspect(ref)}"]

  defp check_ref("#/" <> local = ref, sections) do
    with [section, target] <- String.split(local, "/", parts: 2),
         %{} = entries <- Map.get(sections, section),
         true <- Map.has_key?(entries, target) do
      []
    else
      _ -> ["unknown local $ref target: #{inspect(ref)}"]
    end
  end

  defp check_ref("common_types.json#/$defs/" <> target = ref, _sections) do
    if target in @allowed_external_ref_targets,
      do: [],
      else: ["disallowed external $ref target: #{inspect(ref)}"]
  end

  defp check_ref(ref, _sections), do: ["disallowed $ref target: #{inspect(ref)}"]
end
