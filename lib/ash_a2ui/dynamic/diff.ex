defmodule AshA2ui.Dynamic.Diff do
  @moduledoc """
  A human-reviewable change summary between two `AshA2ui.Dynamic` surface
  specs — what a ratifying human reads before approving a stored or updated
  agent-designed surface.

  The diff is computed at the **spec vocabulary level**, never as a raw JSON
  diff: entities (components, queries, fields, actions, contexts — and their
  nested presets, groups, nested forms, and row layouts) are matched by name,
  and each change names the entity, the option that changed, and the old and
  new values. Key order and other serialization noise never show up.

  Compute one through `AshA2ui.Dynamic.diff/2` (which accepts spec maps,
  serialized specs, and resolved surfaces interchangeably):

      diff = AshA2ui.Dynamic.diff(stored_spec, proposed_spec)

      AshA2ui.Dynamic.Diff.summary(diff)
      # => [
      #   ~s(surface: title changed from "Feedback" to "Recent feedback"),
      #   ~s(added query "default"),
      #   ~s(component "table": row_actions changed from [] to [:toggle_done])
      # ]

  Every `AshA2ui.Dynamic.Diff.Change` is Jason-encodable (like
  `AshA2ui.Dynamic.Error`), so hosts can render diffs in review UIs directly.
  """

  defmodule Change do
    @moduledoc """
    One reviewable change of a spec diff.

    * `kind` — `:added` / `:removed` (a named entity appeared or
      disappeared) or `:changed` (an option of a matched entity differs).
    * `entity` — the vocabulary level: `:surface`, `:component`, `:query`,
      `:preset`, `:field`, `:action`, `:context`, `:column`, `:group` or
      `:nested_form`.
    * `name` — the entity's own name (`nil` for surface-level changes).
    * `path` — the fully qualified human-readable location, e.g.
      `surface`, `component "table"`, `query "default" preset "drafts"`.
    * `option` — the changed option (`:changed` only), dotted for nested
      singletons (`"row_layout.badge"`).
    * `from` / `to` — the old and new value: option values for `:changed`,
      the whole entity spec (or `nil`) for `:added` / `:removed`.
    """

    @derive {Jason.Encoder, only: [:kind, :entity, :name, :path, :option, :from, :to]}
    defstruct [:kind, :entity, :name, :path, :option, :from, :to]

    @type t :: %__MODULE__{
            kind: :added | :removed | :changed,
            entity:
              :surface
              | :component
              | :query
              | :preset
              | :field
              | :action
              | :context
              | :column
              | :group
              | :nested_form,
            name: String.t() | nil,
            path: String.t(),
            option: String.t() | nil,
            from: term,
            to: term
          }
  end

  defstruct changes: []

  @type t :: %__MODULE__{changes: [Change.t()]}

  # {spec key, entity kind, naming} per named-entity section, in the spec's
  # canonical section order. Components are named by their distinguishing
  # name, falling back to their kind (mirroring AshA2ui.Component.key/1).
  @sections [
    {"contexts", :context, &__MODULE__.name_of/1},
    {"queries", :query, &__MODULE__.name_of/1},
    {"components", :component, &__MODULE__.component_key/1},
    {"fields", :field, &__MODULE__.name_of/1},
    {"actions", :action, &__MODULE__.name_of/1}
  ]

  @surface_options ~w(resource title)

  @doc false
  def name_of(entry), do: Map.get(entry, "name")

  @doc false
  def component_key(entry), do: Map.get(entry, "name") || Map.get(entry, "kind")

  @doc """
  Computes the diff between two spec maps (string-keyed, JSON-decoded shape).
  Prefer `AshA2ui.Dynamic.diff/2`, which also accepts serialized specs and
  resolved surfaces.
  """
  @spec compute(map, map) :: t()
  def compute(old_spec, new_spec) when is_map(old_spec) and is_map(new_spec) do
    old_spec = normalize(old_spec)
    new_spec = normalize(new_spec)

    surface_changes =
      Enum.flat_map(@surface_options, fn option ->
        option_changes(:surface, nil, "surface", option, old_spec[option], new_spec[option])
      end)

    section_changes =
      Enum.flat_map(@sections, fn {key, entity, namer} ->
        diff_entities(
          entity,
          &entity_path(entity, &1),
          Map.get(old_spec, key, []),
          Map.get(new_spec, key, []),
          namer,
          &entity_option_changes(entity, &1, &2, &3)
        )
      end)

    %__MODULE__{changes: surface_changes ++ section_changes}
  end

  @doc """
  Whether the diff contains no changes.
  """
  @spec empty?(t()) :: boolean
  def empty?(%__MODULE__{changes: changes}), do: changes == []

  @doc """
  One human-readable line per change — the review text. Mirrors
  `AshA2ui.Dynamic.Error.messages/1`.
  """
  @spec summary(t()) :: [String.t()]
  def summary(%__MODULE__{changes: changes}) do
    Enum.map(changes, fn
      %Change{kind: :added, path: path} ->
        "added #{path}"

      %Change{kind: :removed, path: path} ->
        "removed #{path}"

      %Change{kind: :changed, path: path, option: option, from: from, to: to} ->
        "#{path}: #{option} changed from #{render(from)} to #{render(to)}"
    end)
  end

  defp render(nil), do: "(unset)"
  defp render(value), do: inspect(value)

  # --- entity matching -----------------------------------------------------------

  defp entity_path(entity, name), do: ~s(#{entity} "#{name}")

  defp diff_entities(entity, path_fun, old_entries, new_entries, namer, option_differ) do
    old_by_name = index_by(old_entries, namer)
    new_by_name = index_by(new_entries, namer)

    names =
      Enum.uniq(Enum.map(old_entries, namer) ++ Enum.map(new_entries, namer))

    Enum.flat_map(names, fn name ->
      path = path_fun.(name)

      case {Map.fetch(old_by_name, name), Map.fetch(new_by_name, name)} do
        {{:ok, old_entry}, {:ok, new_entry}} ->
          option_differ.(path, old_entry, new_entry)

        {{:ok, old_entry}, :error} ->
          [%Change{kind: :removed, entity: entity, name: name, path: path, from: old_entry}]

        {:error, {:ok, new_entry}} ->
          [%Change{kind: :added, entity: entity, name: name, path: path, to: new_entry}]
      end
    end)
  end

  defp index_by(entries, namer), do: Map.new(entries, &{namer.(&1), &1})

  # --- per-entity option diffing ----------------------------------------------------

  # Queries nest presets, components nest groups and nested forms (named
  # sub-entities) plus a row_layout singleton (flattened into dotted
  # options); everything else is a flat option map.
  defp entity_option_changes(:query, path, old_entry, new_entry) do
    flat_changes(:query, path, old_entry, new_entry, ["presets"]) ++
      diff_entities(
        :preset,
        &~s(#{path} preset "#{&1}"),
        Map.get(old_entry, "presets", []),
        Map.get(new_entry, "presets", []),
        &name_of/1,
        fn preset_path, old_preset, new_preset ->
          flat_changes(:preset, preset_path, old_preset, new_preset, [])
        end
      )
  end

  defp entity_option_changes(:component, path, old_entry, new_entry) do
    name = component_key(new_entry)

    singleton_options = ["row_layout", "sections"]

    singleton_changes =
      for option <- singleton_options do
        option_map_changes(
          :component,
          name,
          path,
          option,
          Map.get(old_entry, option, %{}),
          Map.get(new_entry, option, %{})
        )
      end

    column_changes =
      diff_entities(
        :column,
        &~s(#{path} column "#{&1}"),
        Map.get(old_entry, "columns", []),
        Map.get(new_entry, "columns", []),
        &name_of/1,
        fn column_path, old_column, new_column ->
          flat_changes(:column, column_path, old_column, new_column, [])
        end
      )

    group_changes =
      diff_entities(
        :group,
        &~s(#{path} group "#{&1}"),
        Map.get(old_entry, "groups", []),
        Map.get(new_entry, "groups", []),
        &name_of/1,
        fn group_path, old_group, new_group ->
          flat_changes(:group, group_path, old_group, new_group, [])
        end
      )

    nested_form_changes =
      diff_entities(
        :nested_form,
        &~s(#{path} nested form "#{&1}"),
        Map.get(old_entry, "nested_forms", []),
        Map.get(new_entry, "nested_forms", []),
        &name_of/1,
        fn nested_path, old_nested, new_nested ->
          flat_changes(:nested_form, nested_path, old_nested, new_nested, [])
        end
      )

    flat_changes(:component, path, old_entry, new_entry, ["columns" | singleton_options]) ++
      List.flatten(singleton_changes) ++ column_changes ++ group_changes ++ nested_form_changes
  end

  defp entity_option_changes(entity, path, old_entry, new_entry) do
    flat_changes(entity, path, old_entry, new_entry, [])
  end

  defp flat_changes(entity, path, old_entry, new_entry, nested_keys) do
    name = name_for(entity, new_entry)

    old_entry
    |> option_keys(new_entry, nested_keys)
    |> Enum.flat_map(fn option ->
      option_changes(entity, name, path, option, old_entry[option], new_entry[option])
    end)
  end

  defp name_for(:component, entry), do: component_key(entry)
  defp name_for(:surface, _entry), do: nil
  defp name_for(_entity, entry), do: name_of(entry)

  # Sub-object options (row_layout) flatten into dotted option changes, so a
  # reviewer sees "row_layout.badge changed" rather than an opaque map blob.
  defp option_map_changes(entity, name, path, option, old_map, new_map)
       when is_map(old_map) and is_map(new_map) do
    old_map
    |> option_keys(new_map, [])
    |> Enum.flat_map(fn key ->
      option_changes(entity, name, path, "#{option}.#{key}", old_map[key], new_map[key])
    end)
  end

  defp option_keys(old_entry, new_entry, nested_keys) do
    (Map.keys(old_entry) ++ Map.keys(new_entry))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in nested_keys or &1 == "name" or &1 == "kind"))
    |> Enum.sort()
  end

  defp option_changes(_entity, _name, _path, _option, same, same), do: []

  defp option_changes(entity, name, path, option, old_value, new_value) do
    [
      %Change{
        kind: :changed,
        entity: entity,
        name: name,
        path: path,
        option: option,
        from: old_value,
        to: new_value
      }
    ]
  end

  # --- normalization ---------------------------------------------------------------

  # Comparison happens over plain string-keyed maps, so specs built in
  # Elixir (atom keys) and specs decoded from JSON diff identically.
  defp normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(other), do: other
end
