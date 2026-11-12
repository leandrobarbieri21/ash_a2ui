defmodule AshA2ui.Test.OwnerOverviewUI do
  @moduledoc """
  Standalone UI fixture for record page sections: an "Overview" section of
  two detail cards (one labelled, one under the section's heading alone), a
  "Visits" section holding a related table, and a field note.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "owner_overview"
    component_order :declared

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :detail, :details do
      section "Overview"
      label "Details"
      context :owner
      fields [:name]
    end

    component :detail, :contact do
      section "Overview"
      context :owner
      fields [:email]
    end

    component :table, :visits do
      section "Visits"
      resource AshA2ui.Test.Appointment
      fields [:title]
      context_filter owner_id: :owner
      require_context [:owner]
    end

    field :email do
      note "From sign-up"
    end
  end
end
