defmodule AshA2ui.Test.CaptionedTask do
  @moduledoc """
  Fixture resource for catalog 1.11: a task list whose status pill explains
  itself (`badge_help`), whose title cell has a third line built from a date
  (`caption` + `caption_text`), whose due date sorts newest first
  (`sort_first`), and whose headers return to the default order on a third
  click (`sort_reset`).
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
    attribute :assignee_name, :string, public?: true

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :done]],
      default: :open

    attribute :created_on, :date, public?: true
    attribute :due_on, :date, public?: true
  end

  actions do
    defaults [:read, create: :*]
  end

  a2ui do
    surface_id "captioned_tasks"

    query :default do
      sortable [:title, :due_on]
      default_sort title: :asc
      sort_reset(true)
    end

    component :table do
      fields [:title, :status, :due_on, :assignee_name, :created_on]
      read_action :read
      query :default

      row_layout do
        title :title
        badge :status
        badge_tones open: :info, done: :success
        badge_help(open: "Still to do", done: "Finished and checked")
      end

      column :title do
        subtitle :assignee_name
        caption(:created_on)
        caption_text("Created {date}")
      end

      column :due_on do
        sort_first(:desc)
      end
    end
  end
end
