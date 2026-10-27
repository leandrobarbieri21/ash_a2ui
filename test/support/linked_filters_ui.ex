defmodule AshA2ui.Test.LinkedFiltersUI do
  @moduledoc """
  Standalone UI fixture for `hidden_filters`: the page around the surface
  sets the `secret` filter itself (links to `?q[filters][secret]=true`), so
  the query controls draw no picker for it while it still applies. `status`
  keeps its picker.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BulkTask
    surface_id "linked_filters"

    query :default do
      sortable [:title]
      filters [:status, :secret]
      hidden_filters [:secret]
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
