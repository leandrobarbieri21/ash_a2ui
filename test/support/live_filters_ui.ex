defmodule AshA2ui.Test.LiveFiltersUI do
  @moduledoc """
  Standalone UI fixture for `apply_on_change`: search and a filter apply as
  they change, without an Apply click. Same resource as
  `AshA2ui.Test.BulkPresetsUI`.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BulkTask
    surface_id "live_filters"

    query :default do
      search_fields [:title]
      sortable [:title]
      filters [:status]
      default_sort title: :asc
      page_size 5
      max_page_size 5
      apply_on_change true
    end

    component :table do
      fields [:title, :status, :score]
      read_action :active
      query :default
    end
  end
end
