defmodule AshA2ui.Test.VisitReviewUI do
  @moduledoc """
  Standalone UI fixture for review fields (admin catalog 3.1): a visit's
  title and status, each with how it was filled in, on its detail card.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Appointment
    surface_id "visit_review"

    context :appointment do
      resource AshA2ui.Test.Appointment
      option_label :title
      picker false
    end

    component :detail, :review do
      context :appointment
      fields [:title, :status, :scheduled_for]
    end

    field :title do
      review(:title_review)
    end

    field :status do
      review(:status_review)
    end
  end
end
