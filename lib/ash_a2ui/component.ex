defmodule AshA2ui.Component do
  @moduledoc """
  Target struct for the `component` DSL entity.

  FROZEN CONTRACT — parallel tracks code against these fields; do not change
  outside an integration commit.
  """

  defstruct [
    :name,
    :as,
    :fields,
    :resource,
    :read_action,
    :create_action,
    :update_action,
    :action,
    :params,
    :query,
    :row_layout,
    :sections,
    :editable,
    :export,
    :primary_action,
    :select_context,
    :context,
    :date_field,
    :end_date_field,
    :granularity,
    :granularities,
    context_filter: [],
    require_context: [],
    row_actions: [],
    columns: [],
    bulk_actions: [],
    display: :list,
    column_order: :layout,
    nested_forms: [],
    groups: [],
    steps: [],
    __spark_metadata__: nil
  ]

  # `as` is an atom in the DSL; the per-section component copies
  # `AshA2ui.Sections.expand/2` produces carry their runtime string name.
  @type t :: %__MODULE__{
          name: :table | :form | :detail | :report,
          as: atom | String.t() | nil,
          fields: [atom] | nil,
          resource: module | nil,
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          action: atom | nil,
          params: [atom] | nil,
          query: atom | nil,
          row_layout: AshA2ui.RowLayout.t() | nil,
          columns: [AshA2ui.Column.t()],
          sections: AshA2ui.Sections.t() | nil,
          editable: AshA2ui.Editable.t() | nil,
          export: AshA2ui.Export.t() | nil,
          primary_action: AshA2ui.PrimaryAction.t() | nil,
          select_context: atom | nil,
          context: atom | nil,
          context_filter: [{atom, atom}],
          require_context: [atom],
          row_actions: [atom],
          bulk_actions: [atom],
          display: :list | :board | :calendar,
          column_order: :layout | :fields,
          date_field: atom | nil,
          end_date_field: atom | nil,
          granularity: :day | :week | :month | nil,
          granularities: [:day | :week | :month] | nil,
          nested_forms: [AshA2ui.NestedForm.t()],
          groups: [AshA2ui.Group.t()],
          steps: [AshA2ui.Step.t()]
        }

  @doc """
  The distinguishing key of the component: its `as` name when given
  (`component :table, :new_items`), otherwise its kind
  (`:table` / `:form` / `:detail`).

  Component keys are unique per surface (verified at compile time) and are
  the `<component_name>` segment of multi-table data-model paths
  (`/records/<component_name>`, `/query/<component_name>`). On the
  per-section component copies `AshA2ui.Sections.expand/2` produces, the
  key is the runtime string name.
  """
  @spec key(t()) :: atom | String.t()
  def key(%__MODULE__{as: nil, name: name}), do: name
  def key(%__MODULE__{as: as}), do: as

  @doc """
  The resource a component reads: a related `:table`'s own `resource`, else
  `surface_resource` (the surface's `for_resource` / the resource itself).
  """
  @spec resource(t(), module | nil) :: module | nil
  def resource(%__MODULE__{name: :table, resource: resource}, _surface_resource)
      when not is_nil(resource),
      do: resource

  def resource(%__MODULE__{}, surface_resource), do: surface_resource

  @doc "Whether this is a related table (a `:table` over another resource)."
  @spec related?(t(), module | nil) :: boolean
  def related?(%__MODULE__{name: :table, resource: resource}, surface_resource)
      when not is_nil(resource),
      do: resource != surface_resource

  def related?(%__MODULE__{}, _surface_resource), do: false
end
