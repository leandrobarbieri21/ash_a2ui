defmodule AshA2ui.Test.GroupedVisitsUI do
  @moduledoc """
  Standalone UI fixture for grouped list rows (catalog 1.14): an owner's
  visits under their clinic, the clinic's status line under it, in a
  "Visits" section whose note is the owner's name.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "grouped_visits"

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :table, :visits do
      section "Visits"
      section_note :name
      resource AshA2ui.Test.Appointment
      display :rows
      fields [:clinic_id, :status, :title, :scheduled_for]
      context_filter owner_id: :owner
      require_context [:owner]

      row_layout do
        group_by :clinic_id
        group_subtitle :status
        group_icon "home"
        title :title
        trailing [:scheduled_for]
      end
    end

    field :title, do: empty_text("Untitled")
  end
end
