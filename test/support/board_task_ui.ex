defmodule AshA2ui.Test.BoardTaskUI do
  @moduledoc """
  Fixture board (v0.9.1): `:board` is a `display :board` table whose lanes
  are three of `status`'s enumerated values, in a custom order with one
  overridden heading. Cards move through the `:claim` / `:complete`
  transition row actions, which refresh the template key (every lane).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BoardTask
    surface_id "board_tasks"

    query :lane_q do
      filters [:status]
      sortable [:name]
      default_sort name: :asc
      page_size 2
    end

    component :table, :board do
      fields [:name, :priority, :status]
      display :board
      row_actions [:claim, :complete]
      query :lane_q

      row_layout do
        title :name
        badge :priority
      end

      sections do
        scope_by :status
        values [:open, :claimed, :completed]
        labels open: "To do"
      end
    end

    action :claim do
      visible_when status: :open
      refreshes [:board]
    end

    action :complete do
      visible_when status: :claimed
      refreshes [:board]
    end
  end
end

defmodule AshA2ui.Test.BoardTaskV1UI do
  @moduledoc """
  The `AshA2ui.Test.BoardTaskUI` board with `spec_version "1.0"` and no
  query (lane totals from the row count, no pagination).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BoardTask
    surface_id "board_tasks_v1"
    spec_version "1.0"

    component :table, :board do
      fields [:name, :priority, :status]
      display :board
      row_actions [:claim]

      row_layout do
        title :name
        badge :priority
      end

      sections do
        scope_by :status
        values [:open, :claimed]
      end
    end

    action :claim do
      visible_when status: :open
      refreshes [:board]
    end
  end
end

defmodule AshA2ui.Test.StatusSectionsUI do
  @moduledoc """
  Fixture for source-less sections rendered as a list (`display` left at
  `:list`): every enumerated value of the `one_of`-constrained `status`, in
  declaration order.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BoardTask
    surface_id "status_sections"

    component :table, :by_status do
      fields [:name, :status]

      sections do
        scope_by :status
      end
    end
  end
end

defmodule AshA2ui.Test.SeveritySectionsUI do
  @moduledoc """
  Fixture for source-less sections over an `Ash.Type.Enum` attribute
  (`AshA2ui.Test.Severity`): every enum value, in declaration order.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BoardTask
    surface_id "severity_sections"

    component :table, :by_severity do
      fields [:name, :severity]

      sections do
        scope_by :severity
      end
    end
  end
end

defmodule AshA2ui.Test.SwimlaneBoardUI do
  @moduledoc """
  Fixture swimlaned board (v0.9.1): the `AshA2ui.Test.BoardTaskUI` lanes
  (three of `status`'s values) split into swimlanes by `severity` (an
  `Ash.Type.Enum`), two of its values in a custom order with one overridden
  heading and a tone each. The lane query filters on both axes, for the
  scope-widening checks.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BoardTask
    surface_id "swimlane_tasks"

    query :cell_q do
      filters [:status, :severity]
      sortable [:name]
      default_sort name: :asc
      page_size 2
    end

    component :table, :board do
      fields [:name, :priority, :status, :severity]
      display :board
      row_actions [:claim, :complete]
      query :cell_q

      row_layout do
        title :name
        badge :priority
      end

      sections do
        scope_by :status
        values [:open, :claimed, :completed]
        labels open: "To do"
        swimlanes_by :severity
        swimlane_values [:very_high, :low]
        swimlane_labels very_high: "Critical"
        swimlane_tones very_high: :danger, low: :success
      end
    end

    action :claim do
      visible_when status: :open
      refreshes [:board]
    end

    action :complete do
      visible_when status: :claimed
      refreshes [:board]
    end
  end
end

defmodule AshA2ui.Test.SwimlaneBoardV1UI do
  @moduledoc """
  A swimlaned board with `spec_version "1.0"` and no query (cell totals from
  the row count, no pagination); every `severity` is a swimlane, `medium`
  without a tone (neutral).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BoardTask
    surface_id "swimlane_tasks_v1"
    spec_version "1.0"

    component :table, :board do
      fields [:name, :status, :severity]
      display :board
      row_actions [:claim]

      row_layout do
        title :name
      end

      sections do
        scope_by :status
        values [:open, :claimed]
        swimlanes_by :severity
        swimlane_tones low: :info, very_high: :warning
      end
    end

    action :claim do
      visible_when status: :open
      refreshes [:board]
    end
  end
end
