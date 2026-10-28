defmodule AshA2ui.Verifiers.VerifyQueries do
  @moduledoc """
  Verifies at compile time that every `query` entity is a sound allowlist:

    * `search_fields` entries must be public string-typed attributes (they
      are matched with a case-insensitive contains) — or relationship paths
      to one (`[:author, :email]`: every step but the last a public
      relationship, the last a public string attribute of the final
      destination),
    * `filters` entries must be public attributes or public
      expression-backed calculations of the resolved resource
      (relationship-sourced `source` columns get a dedicated error,
      module-based calculations and aggregates a tailored rejection),
    * `sortable` and `default_sort` entries must be public attributes, or
      public calculations/aggregates that Ash can sort generically
      (`Ash.Resource.Info.sortable?/3`: expression-backed calculations and
      non-`:first`-over-unsortable aggregates) — non-sortable
      calculations/aggregates get a tailored error,
    * `preset` entities must have unique names and declare exactly one of
      `filter` / `read_action`; `filter` keys must be public attributes or
      public expression calculations with castable values, and `read_action`
      must name a `:read` action of the resource,
    * `default_preset` must name a declared preset,
    * `hidden_filters` must name entries of `filters` (or `path_filters`),
    * `path_filters` entries must be a relationship path to a public
      attribute, or a single public attribute, aggregate or expression
      calculation, under a name no `filters` entry takes,
    * `multi_select_filters`, `filter_labels`, `filter_hints` and a
      `facet_counts` list must name filters of the query,
    * `filter_groups` must group declared choices of a `filters` field, a
      leaf in at most one group, no group value also a leaf (and
      `group_labels` must label declared groups),
    * `page_size_options` must each be at most `max_page_size`,
    * `no_results_state` and preset `empty_state`s need the query's own
      `empty_state`,
    * `page_size` must not exceed `max_page_size`,
    * query names must be unique, and
    * a component's `query` option must reference a declared query.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped when no resource can be resolved (standalone
  UI module without `for_resource`) — `AshA2ui.Info.resource!/1` reports that
  at runtime.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @string_types [Ash.Type.String, Ash.Type.CiString]

  @impl true
  def verify(dsl_state) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      target ->
        module = Verifier.get_persisted(dsl_state, :module)
        queries = queries(dsl_state)
        source_fields = source_field_names(dsl_state)

        with :ok <- verify_unique_names(queries, module),
             :ok <-
               verify_queries(queries, query_targets(dsl_state, target), source_fields, module) do
          with :ok <- verify_references(dsl_state, queries, module) do
            verify_column_sorts(dsl_state, queries, module)
          end
        end
    end
  end

  defp source_field_names(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Field) and not is_nil(&1.source)))
    |> MapSet.new(& &1.name)
  end

  defp verify_unique_names(queries, module) do
    queries
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :query, name],
           message: "duplicate query name #{inspect(name)}: query names must be unique"
         )}
    end
  end

  # A query is checked against every resource whose table uses it: the
  # surface's, or a related table's (`resource`). An unused query is checked
  # against the surface resource.
  defp query_targets(dsl_state, target) do
    targets =
      dsl_state
      |> Verifier.get_entities([:a2ui])
      |> Enum.filter(&(is_struct(&1, AshA2ui.Component) and &1.name == :table and &1.query))
      |> Enum.reduce(%{}, fn component, acc ->
        resource = AshA2ui.Component.resource(component, target)
        Map.update(acc, component.query, [resource], &Enum.uniq([resource | &1]))
      end)

    &Map.get(targets, &1, [target])
  end

  defp verify_queries(queries, targets_of, source_fields, module) do
    pairs = for query <- queries, target <- targets_of.(query.name), do: {query, target}

    Enum.reduce_while(pairs, :ok, fn {query, target}, :ok ->
      ctx = %{
        target: target,
        attributes: public_attributes(target),
        source_fields: source_fields,
        module: module
      }

      case verify_query(query, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_query(query, ctx) do
    with :ok <- verify_allowlists(query, ctx),
         :ok <- verify_search_fields(query, ctx),
         :ok <- verify_path_filters(query, ctx),
         :ok <- verify_hidden_filters(query, ctx.module),
         :ok <- verify_filter_order(query, ctx.module),
         :ok <- verify_filter_name_options(query, ctx.module),
         :ok <- verify_filter_groups(query, ctx),
         :ok <- verify_page_size_options(query, ctx.module),
         :ok <- verify_empty_states(query, ctx.module),
         :ok <- verify_presets(query, ctx) do
      verify_page_sizes(query, ctx.module)
    end
  end

  defp verify_allowlists(query, ctx) do
    [
      sortable: query.sortable,
      filters: query.filters,
      range_filters: query.range_filters,
      default_sort: Keyword.keys(query.default_sort)
    ]
    |> Enum.reduce_while(:ok, fn {option, names}, :ok ->
      case verify_fields(query, option, names, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_fields(query, option, names, ctx) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case verify_field(query, option, name, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # Sort options accept attributes and generically-sortable public
  # calculations/aggregates; `filters` accepts attributes and
  # expression-backed public calculations (equality on the calc value).
  # Everything else gets a tailored rejection.
  defp verify_field(query, option, name, ctx) do
    kind = field_kind(name, ctx)
    sort_option? = option in [:sortable, :default_sort]

    case kind do
      :attribute ->
        :ok

      kind when kind in [:calculation, :aggregate] and sort_option? ->
        verify_sortable(query, option, name, kind, ctx)

      :calculation when option == :filters ->
        verify_filterable_calculation(query, option, name, ctx)

      kind when kind in [:calculation, :aggregate] ->
        {:error,
         allowlist_error(
           query,
           option,
           ctx.module,
           "query #{inspect(query.name)} lists #{inspect(name)} in #{option}, but " <>
             "#{inspect(name)} is #{with_article(kind)} — aggregates may only appear in " <>
             "`sortable`/`default_sort`, and calculations additionally in `filters` " <>
             "(when expression-backed), never in `#{option}`"
         )}

      :source ->
        {:error,
         allowlist_error(
           query,
           option,
           ctx.module,
           "query #{inspect(query.name)} lists #{inspect(name)} in #{option}, but " <>
             "#{inspect(name)} is a relationship-sourced column and is not sortable " <>
             "or filterable — only plain public attributes may appear in query allowlists"
         )}

      :unknown ->
        {:error,
         allowlist_error(query, option, ctx.module, """
         query #{inspect(query.name)} references unknown field #{inspect(name)} in #{option}.

         Every field in a query allowlist must be a public attribute (or, for sortable/\
         default_sort, a sortable public calculation or aggregate; for filters, an \
         expression-backed public calculation) of the resource. \
         Available attributes: #{inspect(Map.keys(ctx.attributes))}
         """)}
    end
  end

  # `filters` equality on a calculation requires a data-layer expression —
  # the same requirement generic sorting has, so `sortable?/3` doubles as
  # the expression-backed check.
  defp verify_filterable_calculation(query, option, name, ctx) do
    if Info.sortable?(ctx.target, name, include_private?: false) do
      :ok
    else
      {:error,
       allowlist_error(
         query,
         option,
         ctx.module,
         "query #{inspect(query.name)} lists #{inspect(name)} in #{option}, but the " <>
           "calculation #{inspect(name)} is not filterable: only expression-backed " <>
           "calculations (`calculate ..., expr(...)`) can be filtered generically — " <>
           "module-based calculations have no data-layer expression"
       )}
    end
  end

  defp verify_sortable(query, option, name, kind, ctx) do
    if Info.sortable?(ctx.target, name, include_private?: false) do
      :ok
    else
      detail =
        case kind do
          :calculation ->
            "only expression-backed calculations (`calculate ..., expr(...)`) can be " <>
              "sorted generically — module-based calculations have no data-layer expression"

          :aggregate ->
            "this aggregate kind/field cannot be sorted generically " <>
              "(e.g. a `:first` aggregate over an unsortable field)"
        end

      {:error,
       allowlist_error(
         query,
         option,
         ctx.module,
         "query #{inspect(query.name)} lists #{inspect(name)} in #{option}, but the " <>
           "#{kind} #{inspect(name)} is not sortable: #{detail}"
       )}
    end
  end

  defp with_article(:aggregate), do: "an aggregate"
  defp with_article(kind), do: "a #{kind}"

  defp field_kind(name, ctx) do
    cond do
      Map.has_key?(ctx.attributes, name) -> :attribute
      not is_nil(Info.public_calculation(ctx.target, name)) -> :calculation
      not is_nil(Info.public_aggregate(ctx.target, name)) -> :aggregate
      MapSet.member?(ctx.source_fields, name) -> :source
      true -> :unknown
    end
  end

  defp allowlist_error(query, option, module, message) do
    DslError.exception(
      module: module,
      path: [:a2ui, :query, query.name, option],
      message: message
    )
  end

  # A search_fields entry is a public string attribute, or a relationship
  # path to one — every step but the last a public relationship, the last a
  # public string attribute of the final destination (same rules as `source`
  # columns, see AshA2ui.Verifiers.VerifyRelationships).
  defp verify_search_fields(query, ctx) do
    Enum.reduce_while(query.search_fields, :ok, fn entry, :ok ->
      case verify_search_field(query, entry, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_search_field(query, name, ctx) when is_atom(name) do
    case field_kind(name, ctx) do
      :attribute ->
        verify_search_type(query, name, ctx.attributes[name], ctx.module)

      kind when kind in [:aggregate, :calculation] ->
        verify_search_computed(query, name, kind, ctx)

      _other ->
        {:error,
         allowlist_error(query, :search_fields, ctx.module, """
         query #{inspect(query.name)} references unknown field #{inspect(name)} in search_fields.

         Every search_fields entry must be a public string-typed attribute (or a \
         string-typed public aggregate or expression calculation), or a \
         relationship path to one (e.g. `[:author, :email]`). \
         Available attributes: #{inspect(Map.keys(ctx.attributes))}
         """)}
    end
  end

  defp verify_search_field(query, path, ctx) when is_list(path) and length(path) >= 2 do
    {relationship_steps, [terminal]} = Enum.split(path, -1)

    case walk_relationships(relationship_steps, ctx.target) do
      {:error, step} ->
        {:error,
         search_path_error(
           query,
           path,
           ctx.module,
           "step #{inspect(step)} is not a public relationship"
         )}

      {:ok, destination} ->
        case Info.attribute(destination, terminal) do
          %{public?: true} = attribute ->
            verify_search_type(query, path, attribute, ctx.module)

          _private_or_missing ->
            {:error,
             search_path_error(
               query,
               path,
               ctx.module,
               "terminal step #{inspect(terminal)} is not a public attribute of " <>
                 inspect(destination)
             )}
        end
    end
  end

  defp verify_search_field(query, path, ctx) do
    {:error, search_path_error(query, path, ctx.module, "a path must have at least two steps")}
  end

  # A computed search field (`search_fields [:vendor_name]`, a `first`
  # aggregate) is searched in the data layer like an attribute, so it must
  # be expressible there (`sortable?/3`: expression calculations, and
  # aggregates other than a `first` over an unsortable field) and resolve to
  # a string.
  defp verify_search_computed(query, name, kind, ctx) do
    cond do
      not Info.sortable?(ctx.target, name, include_private?: false) ->
        {:error,
         allowlist_error(
           query,
           :search_fields,
           ctx.module,
           "query #{inspect(query.name)} search_fields entry #{inspect(name)} is " <>
             "#{with_article(kind)} the data layer cannot filter on (only expression " <>
             "calculations and data-layer aggregates can be searched)"
         )}

      computed_type(ctx.target, name) in @string_types ->
        :ok

      true ->
        {:error,
         allowlist_error(
           query,
           :search_fields,
           ctx.module,
           "query #{inspect(query.name)} search_fields entry #{inspect(name)} must " <>
             "resolve to a string (search uses a case-insensitive contains)"
         )}
    end
  end

  # The Ash type a field resolves to: an attribute's or calculation's own
  # type, an aggregate's field type (`first`/`min`/`max`/`list` keep it).
  @doc false
  def computed_type(target, name) do
    case Info.field(target, name) do
      %Ash.Resource.Aggregate{} = aggregate ->
        aggregate_field_type(target, aggregate)

      %{type: type} ->
        Ash.Type.get_type(type)

      nil ->
        nil
    end
  end

  defp aggregate_field_type(target, %{kind: kind, field: field, relationship_path: path})
       when kind in [:first, :min, :max, :list] and not is_nil(field) do
    case Info.related(target, path) do
      nil -> nil
      related -> computed_type(related, field)
    end
  end

  defp aggregate_field_type(_target, %{kind: kind}) when kind in [:count, :sum],
    do: Ash.Type.Integer

  defp aggregate_field_type(_target, _aggregate), do: nil

  defp walk_relationships(steps, target) do
    Enum.reduce_while(steps, {:ok, target}, fn step, {:ok, current} ->
      case Info.relationship(current, step) do
        %{public?: true, destination: destination} -> {:cont, {:ok, destination}}
        _private_or_missing -> {:halt, {:error, step}}
      end
    end)
  end

  defp verify_search_type(query, entry, %{type: type}, module) do
    if Ash.Type.get_type(type) in @string_types do
      :ok
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :query, query.name, :search_fields],
         message:
           "query #{inspect(query.name)} search_fields entry #{inspect(entry)} must " <>
             "be a string-typed attribute (search uses a case-insensitive contains)"
       )}
    end
  end

  defp search_path_error(query, path, module, detail) do
    DslError.exception(
      module: module,
      path: [:a2ui, :query, query.name, :search_fields],
      message:
        "query #{inspect(query.name)} search_fields path #{inspect(path)} is invalid: " <>
          "#{detail}. Every step but the last must be a public relationship, and the " <>
          "last a public string attribute of the final destination."
    )
  end

  defp verify_hidden_filters(query, module) do
    case query.hidden_filters -- AshA2ui.Query.filter_names(query) do
      [] ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :query, query.name, :hidden_filters],
           message:
             "query #{inspect(query.name)} hidden_filters #{inspect(unknown)} " <>
               "are not in its filters (declared: " <>
               "#{inspect(AshA2ui.Query.filter_names(query))})"
         )}
    end
  end

  defp verify_filter_order(query, module) do
    case query.filter_order -- AshA2ui.Query.filter_names(query) do
      [] ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :query, query.name, :filter_order],
           message:
             "query #{inspect(query.name)} filter_order #{inspect(unknown)} " <>
               "are not in its filters (declared: " <>
               "#{inspect(AshA2ui.Query.filter_names(query))})"
         )}
    end
  end

  # --- path filters -----------------------------------------------------------

  defp verify_path_filters(query, ctx) do
    query.path_filters
    |> Enum.reduce_while(:ok, fn {name, target}, :ok ->
      case verify_path_filter(query, name, target, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_path_filter(query, name, target, ctx) do
    cond do
      name in query.filters ->
        {:error, path_filter_error(query, ctx.module, "#{inspect(name)} is already in filters")}

      Enum.count(query.path_filters, &(elem(&1, 0) == name)) > 1 ->
        {:error, path_filter_error(query, ctx.module, "#{inspect(name)} is declared twice")}

      true ->
        verify_path_filter_target(query, name, target, ctx)
    end
  end

  defp verify_path_filter_target(query, name, field, ctx) when is_atom(field) do
    filterable? =
      case field_kind(field, ctx) do
        :attribute ->
          true

        kind when kind in [:aggregate, :calculation] ->
          Info.sortable?(ctx.target, field, include_private?: false)

        _other ->
          false
      end

    if filterable? do
      :ok
    else
      {:error,
       path_filter_error(
         query,
         ctx.module,
         "#{inspect(name)}: #{inspect(field)} must be a public attribute, a data-layer " <>
           "aggregate or an expression calculation of the resource"
       )}
    end
  end

  defp verify_path_filter_target(query, name, [_, _ | _] = path, ctx) do
    {steps, [terminal]} = Enum.split(path, -1)

    case walk_relationships(steps, ctx.target) do
      {:error, step} ->
        {:error,
         path_filter_error(
           query,
           ctx.module,
           "#{inspect(name)}: step #{inspect(step)} of #{inspect(path)} is not a public relationship"
         )}

      {:ok, destination} ->
        case Info.attribute(destination, terminal) do
          %{public?: true} ->
            :ok

          _private_or_missing ->
            {:error,
             path_filter_error(
               query,
               ctx.module,
               "#{inspect(name)}: #{inspect(terminal)} is not a public attribute of " <>
                 inspect(destination)
             )}
        end
    end
  end

  defp verify_path_filter_target(query, name, other, ctx) do
    {:error,
     path_filter_error(
       query,
       ctx.module,
       "#{inspect(name)}: expected a field or a relationship path of at least two steps " <>
         "ending in an attribute, got: #{inspect(other)}"
     )}
  end

  defp path_filter_error(query, module, detail) do
    DslError.exception(
      module: module,
      path: [:a2ui, :query, query.name, :path_filters],
      message: "query #{inspect(query.name)} path_filters #{detail}"
    )
  end

  # multi_select_filters, a facet_counts list and the keys of filter_labels
  # and filter_hints all name filters of the query.
  defp verify_filter_name_options(query, module) do
    names = AshA2ui.Query.filter_names(query)

    [
      multi_select_filters: query.multi_select_filters,
      facet_counts: (is_list(query.facet_counts) && query.facet_counts) || [],
      filter_labels: Keyword.keys(query.filter_labels),
      filter_hints: Keyword.keys(query.filter_hints)
    ]
    |> Enum.find_value(:ok, fn {option, listed} ->
      case Enum.uniq(listed) -- names do
        [] ->
          nil

        unknown ->
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :query, query.name, option],
             message:
               "query #{inspect(query.name)} #{option} #{inspect(unknown)} are not " <>
                 "filters of the query (declared: #{inspect(names)})"
           )}
      end
    end)
    |> case do
      :ok -> verify_filter_texts(query, module)
      error -> error
    end
  end

  defp verify_filter_texts(query, module) do
    [filter_labels: query.filter_labels, filter_hints: query.filter_hints]
    |> Enum.find_value(:ok, fn {option, entries} ->
      case Enum.reject(entries, fn {_name, text} -> is_binary(text) end) do
        [] ->
          nil

        [{name, text} | _] ->
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :query, query.name, option],
             message:
               "query #{inspect(query.name)} #{option} for #{inspect(name)} must be a " <>
                 "string, got: #{inspect(text)}"
           )}
      end
    end)
  end

  # --- filter groups ------------------------------------------------------------

  defp verify_filter_groups(query, ctx) do
    with :ok <- verify_groups(query, ctx) do
      verify_group_labels(query, ctx.module)
    end
  end

  defp verify_groups(query, ctx) do
    Enum.find_value(query.filter_groups, :ok, fn {field, groups} ->
      case verify_field_groups(query, field, groups, ctx) do
        :ok -> nil
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp verify_field_groups(query, field, groups, ctx) do
    choices =
      ctx.target |> AshA2ui.TypeMapper.choices(field) |> Enum.map(&to_string(elem(&1, 0)))

    error = &group_error(query, field, ctx.module, &1)

    cond do
      field not in query.filters ->
        {:error, error.("#{inspect(field)} is not in the query's filters")}

      choices == [] ->
        {:error, error.("#{inspect(field)} declares no choices (one_of or an Ash.Type.Enum)")}

      not (Keyword.keyword?(groups) and Enum.all?(groups, fn {_g, leaves} -> is_list(leaves) end)) ->
        {:error, error.("expected `group: [leaf, ...]` entries, got: #{inspect(groups)}")}

      true ->
        verify_group_leaves(groups, choices, error)
    end
  end

  defp verify_group_leaves(groups, choices, error) do
    leaves = Enum.flat_map(groups, fn {_group, leaves} -> Enum.map(leaves, &to_string/1) end)
    group_values = Enum.map(groups, fn {group, _leaves} -> to_string(group) end)

    cond do
      (unknown = Enum.uniq(leaves) -- choices) != [] ->
        {:error, error.("leaves #{inspect(unknown)} are not choices of the field")}

      (dupes = leaves -- Enum.uniq(leaves)) != [] ->
        {:error, error.("leaves #{inspect(Enum.uniq(dupes))} are in more than one group")}

      (clash = Enum.filter(group_values, &(&1 in leaves))) != [] ->
        {:error,
         error.(
           "group values #{inspect(clash)} are also leaf values: a group needs a value of " <>
             "its own"
         )}

      Enum.any?(groups, fn {_group, leaves} -> leaves == [] end) ->
        {:error, error.("every group needs at least one leaf")}

      true ->
        :ok
    end
  end

  defp verify_group_labels(query, module) do
    Enum.find_value(query.group_labels, :ok, fn {field, labels} ->
      groups = Keyword.keys(Keyword.get(query.filter_groups, field, []))

      cond do
        not Keyword.keyword?(labels) ->
          {:error, group_error(query, field, module, "group_labels must be `group: \"Label\"`")}

        (unknown = Keyword.keys(labels) -- groups) != [] ->
          {:error,
           group_error(
             query,
             field,
             module,
             "group_labels #{inspect(unknown)} are not groups of the field " <>
               "(declared: #{inspect(groups)})"
           )}

        true ->
          nil
      end
    end)
  end

  defp group_error(query, field, module, detail) do
    DslError.exception(
      module: module,
      path: [:a2ui, :query, query.name, :filter_groups],
      message: "query #{inspect(query.name)} filter_groups for #{inspect(field)}: #{detail}"
    )
  end

  defp verify_page_size_options(query, module) do
    case Enum.filter(query.page_size_options, &(&1 > query.max_page_size)) do
      [] ->
        :ok

      too_big ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :query, query.name, :page_size_options],
           message:
             "query #{inspect(query.name)} page_size_options #{inspect(too_big)} exceed " <>
               "max_page_size #{query.max_page_size}"
         )}
    end
  end

  # no_results_state and a preset's empty_state are variants of the query's
  # empty_state, which the runner falls back to.
  defp verify_empty_states(%{empty_state: nil} = query, module) do
    with_variant =
      cond do
        query.no_results_state -> "no_results_state"
        Enum.any?(query.presets, & &1.empty_state) -> "a preset empty_state"
        true -> nil
      end

    if with_variant do
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :query, query.name, :empty_state],
         message:
           "query #{inspect(query.name)} declares #{with_variant} without its own " <>
             "empty_state (the state shown when nothing else applies)"
       )}
    else
      :ok
    end
  end

  defp verify_empty_states(_query, _module), do: :ok

  # --- presets ----------------------------------------------------------------

  defp verify_presets(query, ctx) do
    with :ok <- verify_unique_preset_names(query, ctx.module),
         :ok <- verify_preset_definitions(query, ctx) do
      verify_default_preset(query, ctx.module)
    end
  end

  defp verify_unique_preset_names(query, module) do
    query.presets
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         preset_error(query, name, module, "duplicate preset name: preset names must be unique")}
    end
  end

  defp verify_preset_definitions(query, ctx) do
    Enum.reduce_while(query.presets, :ok, fn preset, :ok ->
      case verify_preset(query, preset, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_preset(query, preset, ctx) do
    case {preset.filter, preset.read_action} do
      {nil, nil} ->
        {:error,
         preset_error(query, preset.name, ctx.module, "declare either filter or read_action")}

      {filter, nil} when is_list(filter) ->
        verify_preset_filter(query, preset, filter, ctx)

      {nil, read_action} ->
        verify_preset_read_action(query, preset, read_action, ctx)

      {_filter, _read_action} ->
        {:error,
         preset_error(
           query,
           preset.name,
           ctx.module,
           "filter and read_action are mutually exclusive — declare exactly one"
         )}
    end
  end

  defp verify_preset_filter(query, preset, filter, ctx) do
    Enum.reduce_while(filter, :ok, fn {key, value}, :ok ->
      case verify_preset_condition(query, preset, key, value, ctx) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # Preset filter keys follow the `filters` allowlist rules: public
  # attributes or expression-backed public calculations. Values must cast to
  # the field's type (nil means is_nil; a list means membership, each member
  # cast).
  defp verify_preset_condition(query, preset, key, value, ctx) do
    kind = field_kind(key, ctx)

    filterable? =
      case kind do
        :attribute -> true
        :calculation -> Info.sortable?(ctx.target, key, include_private?: false)
        _other -> false
      end

    cond do
      not filterable? ->
        {:error,
         preset_error(
           query,
           preset.name,
           ctx.module,
           "filter key #{inspect(key)} must be a public attribute or an expression-backed " <>
             "public calculation of the resource"
         )}

      not castable_condition?(ctx.target, key, value) ->
        {:error,
         preset_error(
           query,
           preset.name,
           ctx.module,
           "filter value #{inspect(value)} for #{inspect(key)} does not cast to the " <>
             "field's type"
         )}

      true ->
        :ok
    end
  end

  defp castable_condition?(_target, _key, nil), do: true

  defp castable_condition?(target, key, values) when is_list(values) do
    Enum.all?(values, &castable_condition?(target, key, &1))
  end

  defp castable_condition?(target, key, value) do
    case Info.attribute(target, key) || Info.calculation(target, key) do
      %{type: type, constraints: constraints} ->
        with {:ok, cast} <- Ash.Type.cast_input(type, value, constraints),
             {:ok, _cast} <- Ash.Type.apply_constraints(type, cast, constraints) do
          true
        else
          _error -> false
        end

      nil ->
        false
    end
  end

  defp verify_preset_read_action(query, preset, read_action, ctx) do
    case Info.action(ctx.target, read_action) do
      %{type: :read} ->
        :ok

      %{type: actual} ->
        {:error,
         preset_error(
           query,
           preset.name,
           ctx.module,
           "read_action #{inspect(read_action)} must be of type :read, but it is a " <>
             "#{inspect(actual)} action"
         )}

      nil ->
        {:error,
         preset_error(
           query,
           preset.name,
           ctx.module,
           "read_action #{inspect(read_action)} does not exist on the resource"
         )}
    end
  end

  defp verify_default_preset(%{default_preset: nil}, _module), do: :ok

  defp verify_default_preset(query, module) do
    if Enum.any?(query.presets, &(&1.name == query.default_preset)) do
      :ok
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :query, query.name, :default_preset],
         message:
           "query #{inspect(query.name)} default_preset #{inspect(query.default_preset)} " <>
             "does not name a declared preset " <>
             "(declared: #{inspect(Enum.map(query.presets, & &1.name))})"
       )}
    end
  end

  defp preset_error(query, preset_name, module, message) do
    DslError.exception(
      module: module,
      path: [:a2ui, :query, query.name, :preset, preset_name],
      message: "preset #{inspect(preset_name)} of query #{inspect(query.name)}: #{message}"
    )
  end

  defp verify_page_sizes(%{page_size: page_size, max_page_size: max} = query, module)
       when page_size > max do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :query, query.name, :page_size],
       message: "query #{inspect(query.name)} page_size #{page_size} exceeds max_page_size #{max}"
     )}
  end

  defp verify_page_sizes(_query, _module), do: :ok

  defp verify_references(dsl_state, queries, module) do
    declared = MapSet.new(queries, & &1.name)

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Component) and not is_nil(&1.query)))
    |> Enum.reduce_while(:ok, fn component, :ok ->
      if MapSet.member?(declared, component.query) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:a2ui, :component, component.name, :query],
            message: """
            component #{inspect(component.name)} references undeclared query #{inspect(component.query)}.

            Declare it with a `query #{inspect(component.query)} do ... end` entity in the a2ui section. \
            Declared queries: #{inspect(MapSet.to_list(declared))}
            """
          )}}
      end
    end)
  end

  # A column's `sort_by` names the field its header sorts by: it must be in
  # the sortable allowlist of the table's query.
  defp verify_column_sorts(dsl_state, queries, module) do
    by_name = Map.new(queries, &{&1.name, &1})

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
    |> Enum.flat_map(fn component ->
      for column <- component.columns, column.sort_by, do: {component, column}
    end)
    |> Enum.find_value(:ok, fn {component, column} ->
      query = component.query && by_name[component.query]

      if query && column.sort_by in query.sortable do
        nil
      else
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, AshA2ui.Component.key(component), :column, column.name],
           message:
             "column #{inspect(column.name)} sort_by #{inspect(column.sort_by)} must be in " <>
               "the sortable list of the table's query" <>
               ((query && " (sortable: #{inspect(query.sortable)})") || " (the table has none)")
         )}
      end
    end)
  end

  defp queries(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Query))
  end

  defp public_attributes(target) do
    target |> Info.public_attributes() |> Map.new(&{&1.name, &1})
  end

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and Info.resource?(resource), do: resource
    end
  end
end
