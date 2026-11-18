defmodule AshA2ui.Test.FindingFieldsUI do
  @moduledoc """
  Standalone UI fixture for field actions (admin catalog 3.2): a finding's
  title and amount, each with a button that checks it, on its detail card.
  The title's is offered only while the title waits (`title_open`); the
  amount's always; the note has none.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Finding
    surface_id "finding_fields"

    context :finding do
      resource AshA2ui.Test.Finding
      option_label :title
      picker false
    end

    component :detail, :facts do
      context :finding
      fields [:title, :amount, :note]
    end

    field :title do
      field_action :check_field
      field_action_visible :title_open
    end

    field :amount do
      field_action :check_field
    end

    action :check_field do
      label "Mark as checked"
      icon "check"
      refreshes []
    end
  end
end
