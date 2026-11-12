defmodule AshA2ui.Test.LinkedVisitsUI do
  @moduledoc """
  Standalone UI fixture for plain links (`link_url`): each visit's title
  links to the visit's own page, in the table and on its detail card.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Appointment
    surface_id "linked_visits"

    context :visit do
      resource AshA2ui.Test.Appointment
      option_label :title
      picker false
    end

    component :table do
      fields [:title, :status]
      select_context :visit
    end

    component :detail, :visit_card do
      context :visit
      fields [:title]
    end

    field :title do
      link_url(:page_url)
    end
  end
end
