defmodule AshA2ui.Test.VisitProgressUI do
  @moduledoc """
  Standalone UI fixture for step fields (catalog 1.17): a visit's progress
  (booked, checked in, seen, billed) drawn as a numbered stepper on its
  detail card.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Appointment
    surface_id "visit_progress"

    context :appointment do
      resource AshA2ui.Test.Appointment
      option_label :title
      picker false
    end

    component :detail, :progress do
      context :appointment
      fields [:title, :progress]
    end

    field :progress do
      steps true
      empty_text "No steps yet"
    end
  end
end
