defmodule AshA2ui.Test.ColumnTask do
  @moduledoc """
  Fixture resource for `column` entities: a task list whose title cell
  shows the assignee under it and a priority icon before it, whose tag cell
  shows the first tag and "+N more" from a count, and whose status pill
  (the `row_layout` badge) has a detail line with a date under it.
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

    attribute :priority, :atom,
      public?: true,
      constraints: [one_of: [:high, :normal, :low]]

    attribute :first_tag, :string, public?: true
    attribute :tag_count, :integer, public?: true, default: 0

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :done]],
      default: :open

    attribute :status_detail, :atom,
      public?: true,
      constraints: [one_of: [:due_soon, :overdue, :none]]

    attribute :due_on, :date, public?: true
  end

  actions do
    defaults [:read, create: :*]
  end

  a2ui do
    surface_id "column_tasks"

    component :table do
      fields [
        :title,
        :first_tag,
        :status,
        :assignee_name,
        :priority,
        :tag_count,
        :status_detail,
        :due_on
      ]

      read_action :read

      row_layout do
        title :title
        badge :status
        badge_tones open: :info, done: :success
      end

      column :title do
        subtitle :assignee_name
        icon :priority
        icon_names high: :alert, low: :check
        icon_tones high: :danger, low: :success
        icon_labels high: "High priority"
      end

      column :first_tag do
        more :tag_count
      end

      column :status do
        detail :status_detail
        detail_date :due_on
        detail_text due_soon: "Due {date}", overdue: "Overdue since {date}"
        detail_icon_names due_soon: :clock, overdue: :alert
        detail_icon_tones overdue: :danger
      end
    end
  end
end
