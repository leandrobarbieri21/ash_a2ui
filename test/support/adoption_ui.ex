# Adoption fixtures that use DSL this branch adds (a relationship prompt
# over a searchable select, action labels, select_context on a board), kept
# apart from test/support/adoption.ex so that file also compiles against
# the pre-fix library.

defmodule AshA2ui.Test.Adoption.SearchJobsUI do
  @moduledoc "A relationship prompt over a searchable select (`option_search`)."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_search_jobs"

    component :table do
      fields [:title, :status]
      row_actions [:assign]
    end

    field :clerk_id do
      label "Clerk"
      option_search [:name]
    end

    action :assign do
      prompt_fields [:clerk_id]
    end
  end
end

defmodule AshA2ui.Test.Adoption.LabelledJobsUI do
  @moduledoc "Row, prompt and bulk buttons labelled through the action entity."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_labelled_jobs"

    component :table do
      fields [:title, :status]
      row_actions [:claim, :assign, :lock]
    end

    action :claim do
      label "Take it"
      visible_when status: :open
    end

    action :assign do
      label "Assign clerk"
      prompt_fields [:clerk_id]
    end
  end
end

defmodule AshA2ui.Test.Adoption.LabelledBulkJobsUI do
  @moduledoc "A bulk action labelled through the action entity."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_labelled_bulk_jobs"

    component :table do
      fields [:title, :status]
      bulk_actions [:claim]
    end

    action :claim do
      label "Take it"
    end
  end
end

defmodule AshA2ui.Test.Adoption.SelectBoardUI do
  @moduledoc """
  A board whose cards select into a pickerless context (`select_context`),
  filling a detail card — the master/detail a list table gets.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Adoption.Job
    surface_id "adoption_select_board"

    context :job do
      resource AshA2ui.Test.Adoption.Job
      option_label :title
      picker false
    end

    component :table, :board do
      fields [:title, :priority]
      display :board
      select_context :job
      row_actions [:claim]

      row_layout do
        title :title
        badge :priority
      end

      sections do
        scope_by :status
        values [:open, :claimed]
      end
    end

    component :detail, :job_card do
      context :job
      fields [:title, :status, :priority]
    end

    action :claim do
      visible_when status: :open
      refreshes [:board]
    end
  end
end
