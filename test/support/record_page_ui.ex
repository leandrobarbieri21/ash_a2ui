defmodule AshA2ui.Test.RecordPageUI do
  @moduledoc """
  Standalone UI fixture for a record page: one owner selected into a
  pickerless context, its sections in declaration order
  (`component_order :declared`) and headed by their `label`s — a detail card,
  a related table, then a second detail card.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "record_page"
    component_order :declared

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :detail, :summary do
      label "At a glance"
      context :owner
      fields [:name]
    end

    component :table, :visits do
      label "Visits & follow-ups"
      resource AshA2ui.Test.Appointment
      fields [:title, :status]
      context_filter owner_id: :owner
      require_context [:owner]
    end

    component :detail, :contact do
      context :owner
      fields [:email]
    end
  end
end
