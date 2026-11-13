defmodule AshA2ui.Test.KitchenSinkV1UI do
  @moduledoc """
  A second surface over `AshA2ui.Test.KitchenSink`: the same table + form
  over the same resource under its own surface id, spanning the full
  field-type matrix (string, boolean, integer, decimal, date,
  utc_datetime, enum, timestamps with a `formatDate` function cell).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.KitchenSink
    surface_id "kitchen_sink_v1"

    component :table do
      fields [:name, :active, :count, :price, :birthday, :scheduled_at, :status, :inserted_at]
      read_action :read
      row_actions [:update, :destroy]
    end

    component :form do
      fields [:name, :active, :count, :price, :birthday, :scheduled_at, :status]
      create_action :create
      update_action :update
    end

    field :name do
      label "Name"
      widget :text_field
      order 1
    end

    field :inserted_at do
      label "Created"
      format :date
      order 99
    end

    field :updated_at do
      hidden true
    end
  end
end
