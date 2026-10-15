defmodule AshA2ui.Test.BulkTasksUI do
  @moduledoc """
  Standalone UI fixture for bulk actions (A2UI-104): a single flat-row table
  scoped by the `:project` context, with a query capping pages at 5 rows,
  row actions `[:approve, :flag]` and bulk actions
  `[:approve, :reject, :destroy]`. `:approve` is gated by
  `visible_when status: :open`.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BulkTask
    surface_id "bulk_tasks"

    context :project do
      resource AshA2ui.Test.BulkProject
      option_label :name
    end

    query :default do
      search_fields [:title]
      sortable [:title]
      default_sort title: :asc
      page_size 5
      max_page_size 5
    end

    component :table do
      fields [:title, :status, :score]
      query :default
      context_filter project_id: :project
      row_actions [:approve, :flag]
      bulk_actions [:approve, :reject, :destroy]
    end

    action :approve do
      visible_when status: :open
      refreshes [:table]
    end
  end
end
