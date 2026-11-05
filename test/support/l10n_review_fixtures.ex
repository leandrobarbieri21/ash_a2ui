defmodule AshA2ui.Test.StringBadgeUI do
  @moduledoc false
  # A row_layout whose badge is a plain string field: its values are record
  # data, never display metadata.
  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BoardTask
    surface_id "string_badge"

    component :table, :tasks do
      fields [:name, :priority]
      read_action :read

      row_layout do
        title :priority
        badge :name
      end
    end
  end
end
