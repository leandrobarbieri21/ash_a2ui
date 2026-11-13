defmodule AshA2ui.Test.HeadedVisitsUI do
  @moduledoc """
  Standalone UI fixture for table card headers (catalog 1.18): an owner's
  visits in two tables under one "Visits" section, the first with its own
  card heading and a caption, the second drawn as rows with a heading only,
  and a third table, labeled but with no heading, outside the section.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "headed_visits"
    component_order :declared

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :table, :visits do
      section "Visits"
      heading "Visit history"
      description "Each visit for this owner. Details come from the latest."
      resource AshA2ui.Test.Appointment
      fields [:title, :status]
      context_filter owner_id: :owner
      require_context [:owner]
    end

    component :table, :schedule do
      section "Visits"
      heading "Schedule"
      display :rows
      resource AshA2ui.Test.Appointment
      fields [:title, :scheduled_for]
      context_filter owner_id: :owner
      require_context [:owner]

      row_layout do
        title :title
        trailing [:scheduled_for]
      end
    end

    component :table, :all_visits do
      label "All visits"
      resource AshA2ui.Test.Appointment
      fields [:title]
      context_filter owner_id: :owner
      require_context [:owner]
    end
  end
end
