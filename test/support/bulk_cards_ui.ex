defmodule AshA2ui.Test.BulkCardsUI do
  @moduledoc """
  Standalone UI fixture for bulk actions (A2UI-104) on a multi-table
  surface: `:inbox` renders `row_layout` cards with `bulk_actions
  [:reject]`; `:everything` has no bulk actions, so its rows and
  components must stay as they were.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BulkTask
    surface_id "bulk_cards"

    component :table, :inbox do
      fields [:title, :status, :score]
      bulk_actions [:reject]

      row_layout do
        title :title
        badge :status
        meta [:score]
      end
    end

    component :table, :everything do
      fields [:title]
    end
  end
end
