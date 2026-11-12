defmodule AshA2ui.Test.CardVisitsUI do
  @moduledoc """
  Standalone UI fixture for card rows (catalog 1.16): an owner's visits as
  cards, each headed by its title and a badge already in words, its details
  as labeled pairs, and its clinic under a "Show clinic" disclosure.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "card_visits"

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :table, :visits do
      resource AshA2ui.Test.Appointment
      display :cards
      fields [:title, :seen_by, :details, :clinic_id]
      context_filter owner_id: :owner
      require_context [:owner]

      row_layout do
        title :title
        badge :seen_by
        meta [:details]
        expand [:clinic_id]
        expand_label("Show clinic")
      end
    end

    field :details, do: pairs(true)
  end
end
