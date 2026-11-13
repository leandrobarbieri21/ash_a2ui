defmodule AshA2ui.Test.DocumentVisitsUI do
  @moduledoc """
  Standalone UI fixture for document rows and table footers (catalog 1.15):
  an owner's visits as rows with their status as a leading code, each title a
  link that downloads, and the owner's name under the rows beside an "All
  visits" link.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "document_visits"

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :table, :visits do
      resource AshA2ui.Test.Appointment
      display :rows
      fields [:status, :title, :scheduled_for]
      context_filter owner_id: :owner
      require_context [:owner]
      footer_note :name
      footer_link href: "#all", label: "All visits"

      row_layout do
        leading :status
        title :title
        trailing [:scheduled_for]
      end
    end

    field :title do
      link_url :page_url
      download true
    end
  end
end
