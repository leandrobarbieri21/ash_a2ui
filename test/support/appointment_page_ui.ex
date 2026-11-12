defmodule AshA2ui.Test.AppointmentPageUI do
  @moduledoc """
  Standalone UI fixture for a record page's detail rows: the appointment's
  status drawn as a badge (declared text, tones and help), its date with an
  `empty_text` on one card and left out while empty (`hide_empty`) on the
  other.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Appointment
    surface_id "appointment_page"

    context :appointment do
      resource AshA2ui.Test.Appointment
      option_label :title
      picker false
    end

    component :detail, :summary do
      context :appointment
      fields [:title, :status, :scheduled_for]
    end

    component :detail, :schedule do
      context :appointment
      fields [:scheduled_for]
      hide_empty [:scheduled_for]
    end

    field :status do
      badge_text scheduled: "Booked"
      badge_tones scheduled: :info, completed: :success
      badge_help completed: "Seen and signed off"
    end

    field :scheduled_for do
      empty_text "Not booked yet"
    end
  end
end
