defmodule AshA2ui.Sections do
  @moduledoc """
  Target struct for the `sections` DSL entity (dynamic table sets) and the
  runtime expansion turning one sectioned `:table` template into one concrete
  table per section record.

  A `:table` component declaring a `sections` block is a **template**: at
  render (and action-handling) time, the section `source` resource is read
  (actor-scoped, authorized like any other read) and the template is replaced
  by one concrete table per returned record — each scoped by
  `scope_by == <section record's value attribute>` and headed by the section
  record's `label` attribute.

  Runtime table names follow `<template_key>_<sanitized value>` (every
  non-alphanumeric character of the section value becomes `_`), and each
  expanded table keeps the established multi-table data-model contract:
  records at `/records/<runtime name>`, query state at
  `/query/<runtime name>`, `"query"` actions targeting the runtime name via
  the `"component"` context key. A surface with a sectioned table is always
  a multi-table surface (even when the source yields zero or one section),
  so the scoped paths — and the `"component"` context keys baked into
  emitted controls — never change shape between renders.

  A `sections` block without a `source` enumerates its sections from the
  values of `scope_by` instead (an `Ash.Type.Enum`'s values or a `one_of`
  constraint, narrowed and ordered by `values`, headed per `labels`): no
  read is issued, and the runtime names, scoped paths and per-section
  filters are exactly those of a source-backed set. A `:table` with
  `display :board` renders such a set as side-by-side lanes (see
  `AshA2ui.Board`); with `swimlanes_by` it expands into one cell per
  (swimlane, lane), `<template_key>_<lane>__<swimlane>`, scoped by both
  attributes.

  `refreshes` metadata may target the template key (`refreshes
  [:per_bucket]`): after expansion it covers every runtime table of the set.

  Expansion happens after `AshA2ui.ResolvedView.resolve/2` and before
  encoding/dispatch — `AshA2ui.Info.build_surface/2`,
  `AshA2ui.Info.build_data_model/2` and `AshA2ui.ActionHandler.handle/3` all
  call `expand/2`, so encoders and the handler only ever see concrete
  tables.
  """

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ResolvedView

  defstruct [
    :source,
    :scope_by,
    :label,
    :value,
    :read_action,
    :sort,
    :values,
    :swimlanes_by,
    :swimlane_values,
    labels: [],
    swimlane_labels: [],
    swimlane_tones: [],
    limit: 50,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          source: module | nil,
          scope_by: atom,
          label: atom | nil,
          value: atom | nil,
          read_action: atom | nil,
          sort: atom | nil,
          values: [atom | String.t()] | nil,
          labels: keyword,
          swimlanes_by: atom | nil,
          swimlane_values: [atom | String.t()] | nil,
          swimlane_labels: keyword,
          swimlane_tones: keyword(atom),
          limit: pos_integer
        }

  @doc """
  Expands every sectioned table of the resolved view into concrete per-section
  tables by reading the section `source` (with the given `:actor` /
  `:tenant` / `:authorize?` / `:domain` options). Views without sectioned
  tables are returned unchanged.

  Returns `{:error, error}` when a source read fails (e.g. a policy
  forbids it) — callers map it onto the usual error messages.
  """
  @spec expand(ResolvedView.t(), keyword) :: {:ok, ResolvedView.t()} | {:error, term}
  def expand(%ResolvedView{} = view, opts \\ []) do
    if Enum.any?(view.tables, &Map.get(&1, :sections)) do
      do_expand(view, opts)
    else
      {:ok, view}
    end
  end

  @doc """
  Same as `expand/2`, raising the Ash error class on a failed source read.
  """
  @spec expand!(ResolvedView.t(), keyword) :: ResolvedView.t()
  def expand!(view, opts \\ []) do
    case expand(view, opts) do
      {:ok, expanded} -> expanded
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  @doc """
  The runtime name of one expanded table: the template key plus the section
  value, with every non-alphanumeric run collapsed to `_`
  (`section_name(:per_bucket, "a3f4-9") == "per_bucket_a3f4_9"`).
  """
  @spec section_name(atom | String.t(), term) :: String.t()
  def section_name(template_key, value) do
    "#{template_key}_#{sanitize(value)}"
  end

  @doc """
  A section value in runtime-name form: its string form with every
  non-alphanumeric run collapsed to `_` (`sanitize("a3f4-9") == "a3f4_9"`).
  """
  @spec sanitize(term) :: String.t()
  def sanitize(value), do: String.replace(section_string(value), ~r/[^a-zA-Z0-9]+/, "_")

  defp do_expand(view, opts) do
    view.tables
    |> Enum.reduce_while({:ok, []}, fn table, {:ok, acc} ->
      case table_replacement(table, opts) do
        {:ok, replacement} -> {:cont, {:ok, acc ++ [replacement]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, replacements} -> {:ok, rebuild_view(view, replacements)}
      {:error, error} -> {:error, error}
    end
  end

  # One `{template_component, concrete_tables}` replacement pair per table:
  # sectionless tables map onto themselves, sectioned templates onto their
  # per-section expansion (failing over the source read's error).
  defp table_replacement(table, opts) do
    case Map.get(table, :sections) do
      nil ->
        {:ok, {table.component, [table]}}

      config ->
        case read_sections(config, opts) do
          {:ok, section_records} ->
            {:ok, {table.component, expand_table(table, config, section_records)}}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  # One concrete table per section record — on a swimlaned board, one per
  # (swimlane, lane) cell, swimlane-major, scoped by both filters: runtime
  # name, scoped data-model paths, a copied component (its `as` carries the runtime name so encoder
  # component ids stay unique), and the `section` scope the reads AND on
  # (see AshA2ui.ContextRunner.table_scope/3).
  # `limit` caps the cells (each one a page read and a count): whole
  # swimlane rows past it are dropped, as trailing lanes are on a lane-only
  # board. The verifier rejects such a limit where it can resolve the
  # resource, so this only guards boards it could not check.
  defp expand_table(table, %{swimlanes: %{}} = config, lanes) do
    swimlanes =
      config.resource
      |> AshA2ui.Board.swimlanes(config.swimlanes)
      |> Enum.take(div(config.limit, max(length(lanes), 1)))

    for swimlane <- swimlanes, lane <- lanes do
      name = AshA2ui.Board.cell_name(table.name, lane.value, swimlane.value)
      label = section_string(lane.label)

      table
      |> Map.delete(:sections)
      |> Map.merge(%{
        name: name,
        component: %{table.component | as: name},
        records_path: "/records/#{name}",
        query_path: table.query && "/query/#{name}",
        export: section_export(table, "#{label} #{swimlane.label}"),
        section: %{
          value: lane.value,
          label: label,
          filter: {config.scope_by, lane.value},
          template: table.name,
          lane: section_name(table.name, lane.value),
          swimlane: %{
            value: swimlane.value,
            label: swimlane.label,
            tone: swimlane.tone,
            name: AshA2ui.Board.swimlane_name(table.name, swimlane.value),
            filter: {config.swimlanes.scope_by, swimlane.value}
          }
        }
      })
    end
  end

  defp expand_table(table, config, section_records) do
    Enum.map(section_records, fn record ->
      value = Map.get(record, config.value)
      name = section_name(table.name, value)
      label = section_string(Map.get(record, config.label))

      table
      |> Map.delete(:sections)
      |> Map.merge(%{
        name: name,
        component: %{table.component | as: name},
        records_path: "/records/#{name}",
        query_path: table.query && "/query/#{name}",
        export: section_export(table, label),
        section: %{
          value: value,
          label: label,
          filter: {config.scope_by, value},
          template: table.name
        }
      })
    end)
  end

  # Each expanded table's export downloads its own section: the template's
  # declared filename gains a sanitized section-label suffix (or, when
  # defaulted, becomes "<label>.csv").
  defp section_export(%{export: nil}, _label), do: nil

  defp section_export(%{export: export, name: template_key}, label) do
    slug =
      label
      |> String.replace(~r/[^a-zA-Z0-9]+/, "_")
      |> String.trim("_")

    filename =
      if export.filename == "#{template_key}.csv" do
        "#{slug}.csv"
      else
        String.replace_suffix(export.filename, ".csv", "") <> "_#{slug}.csv"
      end

    %{export | filename: filename}
  end

  # Rebuilds the view around the expanded table set: `components` swaps each
  # template component for its per-section copies (preserving root order),
  # and `refreshes` targets naming a template key fan out to the runtime
  # names (nil — refresh everything — stays nil).
  defp rebuild_view(view, replacements) do
    tables = Enum.flat_map(replacements, fn {_component, tables} -> tables end)
    by_component = Map.new(replacements)

    components =
      Enum.flat_map(view.components, fn component ->
        case Map.get(by_component, component) do
          nil -> [component]
          expanded -> Enum.map(expanded, & &1.component)
        end
      end)

    expanded_names =
      for {component, expanded} <- replacements,
          component.name == :table,
          into: %{},
          do: {AshA2ui.Component.key(component), Enum.map(expanded, & &1.name)}

    refreshes =
      Map.new(view.refreshes, fn
        {action, nil} ->
          {action, nil}

        {action, targets} ->
          {action, Enum.flat_map(targets, &(Map.get(expanded_names, &1) || [&1]))}
      end)

    %{view | tables: tables, components: components, refreshes: refreshes}
  end

  # Source-less sections (boards): the lanes are the enumerated values of
  # `scope_by`, synthesized as `%{value, label}` records — no read.
  defp read_sections(%{source: nil} = config, _opts) do
    {:ok, config.resource |> AshA2ui.Board.lanes(config) |> Enum.take(config.limit)}
  end

  defp read_sections(config, opts) do
    domain =
      ResourceInfo.domain(config.source) || opts[:domain] ||
        raise(ArgumentError, "no domain configured for #{inspect(config.source)}")

    # The opts go to `for_read/4` so the source action's preparations see
    # the actor and tenant (they run when the query is built).
    config.source
    |> Ash.Query.for_read(
      config.read_action,
      %{},
      [
        domain: domain,
        actor: opts[:actor],
        tenant: opts[:tenant],
        authorize?: Keyword.get(opts, :authorize?, true)
      ] ++ AshA2ui.AsOf.read_opt(opts)
    )
    |> Ash.Query.sort([{config.sort, :asc}])
    |> Ash.Query.limit(config.limit)
    |> Ash.read()
  end

  defp section_string(%Date{} = date), do: Date.to_iso8601(date)
  defp section_string(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp section_string(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp section_string(nil), do: ""
  defp section_string(value), do: to_string(value)
end
