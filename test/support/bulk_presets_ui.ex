defmodule AshA2ui.Test.BulkPresetsUI do
  @moduledoc """
  Standalone UI fixture for bulk actions (A2UI-104) under query presets:
  the table reads through `:active`, its query's default preset `:archived`
  swaps the read to `:archived`, and the `:approved` preset ANDs a filter.
  Bulk actions are `:reject` (update) and `:stamp` (generic, takes
  `:record_id`).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BulkTask
    surface_id "bulk_presets"

    query :default do
      sortable [:title]
      default_sort title: :asc
      page_size 5
      max_page_size 5
      default_preset :archived

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
      bulk_actions [:reject, :stamp]
    end
  end
end
