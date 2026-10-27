defmodule AshA2ui.Test.Submission do
  @moduledoc """
  Fixture resource for `primary_action`: each row's button opens the
  record, labelled and styled by the `next_step` calculation — "Review"
  (primary) for a submitted row, "Finish" (default) for a draft, the View
  default (borderless) for anything else.
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

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :state, :atom,
      public?: true,
      constraints: [one_of: [:draft, :submitted, :approved]],
      default: :draft
  end

  calculations do
    calculate :next_step,
              :atom,
              expr(
                if state == :submitted do
                  :review
                else
                  if state == :draft, do: :finish, else: :view
                end
              ),
              public?: true
  end

  actions do
    defaults [:read, create: :*, update: :*]
  end

  a2ui do
    surface_id "submissions"

    component :table do
      fields [:title, :state]
      read_action :read

      primary_action do
        label_from :next_step
        labels review: "Review", finish: "Finish"
        variants review: :primary, finish: :default
        variant :borderless
      end
    end

    component :form do
      fields [:title, :state]
      create_action :create
      update_action :update
    end
  end
end
