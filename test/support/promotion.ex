defmodule AshA2ui.Test.Promotion do
  @moduledoc """
  Fixture resource for Wave 6 layout features: its surface declares a
  `row_layout` (card-style table rows: title + badge + metadata grid) and
  form `group` sections (labeled N-column field grids), modeled on a host
  app's promotions admin screen.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :slug, :string, public?: true
    attribute :trial_days, :integer, public?: true
    attribute :expires_at, :utc_datetime, public?: true
    attribute :is_active, :boolean, public?: true, default: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    surface_id "promotions"

    component :table do
      fields [:name, :slug, :trial_days, :expires_at, :is_active]
      read_action :read
      row_actions [:destroy]

      row_layout do
        title :name
        badge :is_active
        badge_text true: "Active", false: "Inactive"
        meta [:slug, :trial_days, :expires_at]
        columns 3
      end
    end

    component :form do
      fields [:name, :slug, :trial_days, :expires_at, :is_active]
      create_action :create
      update_action :update

      group :details do
        label "Details"
        columns 2
        fields [:name, :slug]
      end

      group :scheduling do
        columns 2
        fields [:trial_days, :expires_at]
      end
    end

    field :expires_at do
      label "Expires"
      format :date
    end
  end
end
