defmodule AshA2ui.Test.SortOnlyUI do
  @moduledoc """
  Standalone UI fixture for a query with nothing to pick: sort and page
  size only. Its table gets no query controls card (it would hold only
  Apply); pagination stays.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BulkTask
    surface_id "sort_only"

    query :default do
      sortable [:title]
      default_sort title: :asc
      page_size 5
      max_page_size 5
    end

    component :table do
      fields [:title, :status, :score]
      read_action :active
      query :default
    end
  end
end
