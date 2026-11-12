defmodule AshA2ui.Test.OwnerVisitsUI do
  @moduledoc """
  Standalone UI fixture for a record page's related lines drawn as list rows
  (`display :rows`): each visit's title and status badge, its date trailing,
  and its clinic shown when the row is opened.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "owner_visits"

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :table, :visits do
      label "Visits"
      resource AshA2ui.Test.Appointment
      display :rows
      fields [:title, :status, :scheduled_for, :clinic_id]
      context_filter owner_id: :owner
      require_context [:owner]

      row_layout do
        title :title
        badge :status
        trailing [:scheduled_for]
        expand [:clinic_id]
      end
    end
  end
end
