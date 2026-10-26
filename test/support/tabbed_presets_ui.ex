defmodule AshA2ui.Test.TabbedPresetsUI do
  @moduledoc """
  Standalone UI fixture for `preset_picker false`: the page around the
  surface selects the preset itself (tabs linking to `?q[preset]=...`), so
  the query controls leave the picker out while the presets still apply.
  Same query as `AshA2ui.Test.BulkPresetsUI`, plus search so the controls
  card has something left in it.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BulkTask
    surface_id "tabbed_presets"

    query :default do
      search_fields [:title]
      sortable [:title]
      default_sort title: :asc
      page_size 5
      max_page_size 5
      default_preset :archived
      preset_picker false

      preset :archived do
        read_action :archived
      end

      preset :approved do
        filter status: :approved
      end
    end

    component :table do
      fields [:title, :status, :score]
      read_action :active
      query :default
    end
  end
end
