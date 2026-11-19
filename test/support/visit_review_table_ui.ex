defmodule AshA2ui.Test.VisitReviewTableUI do
  @moduledoc """
  Standalone UI fixture for review fields in a table (admin catalog 3.3): an
  owner's visits as list rows, the title a row layout's expand field and the
  status the subtitle of the visit time's column, each with how it was
  filled in.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "visit_review_table"

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :table, :visits do
      resource AshA2ui.Test.Appointment
      display :rows
      fields [:seen_by, :scheduled_for, :status, :title]
      context_filter owner_id: :owner
      require_context [:owner]

      column :scheduled_for, do: subtitle(:status)

      row_layout do
        title :seen_by
        trailing [:scheduled_for]
        expand [:title]
      end
    end

    field :title do
      review :title_review
    end

    field :status do
      review :status_review
    end
  end
end
