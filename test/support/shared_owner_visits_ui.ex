defmodule AshA2ui.Test.SharedOwnerVisitsUI do
  @moduledoc """
  Standalone UI fixture for `context_record`: an owner's details and two
  tables of their visits. `:visits` reads with the selected owner (and its
  `:greeting`) in its query context; `:plain_visits` does not.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Owner
    surface_id "shared_owner_visits"
    component_order :declared

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      picker false
    end

    component :detail, :details do
      context :owner
      fields [:name]
    end

    component :table, :visits do
      resource AshA2ui.Test.Appointment
      fields [:title, :owner_greeting]
      context_filter owner_id: :owner
      require_context [:owner]
      context_record owner: [:greeting]
    end

    component :table, :plain_visits do
      resource AshA2ui.Test.Appointment
      fields [:title, :owner_greeting]
      context_filter owner_id: :owner
      require_context [:owner]
    end
  end
end
