defmodule AshA2ui.Test.Calendar.Domain do
  @moduledoc """
  Domain for the calendar fixtures (`display :calendar`, AST-173). Kept
  apart from the frozen shared `AshA2ui.Test.Domain`.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.Calendar.Event
  end
end

defmodule AshA2ui.Test.Calendar.TeamScope do
  @moduledoc """
  Read preparation scoping events to the actor's `team`. Without an actor
  every event is read (the fixtures that do not test scoping pass none).
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, %{actor: %{team: team}}), do: Ash.Query.filter(query, team == ^team)
  def prepare(query, _opts, _context), do: query
end

defmodule AshA2ui.Test.Calendar.Event do
  @moduledoc """
  Fixture resource for calendars: `starts_on`/`ends_on` are dates (a
  multi-day event when `ends_on` is set), `starts_at`/`ends_at` UTC
  datetimes, `status` an atom with a `one_of` constraint, and `team` the
  attribute reads are scoped by (`AshA2ui.Test.Calendar.TeamScope`).
  `:confirm` is the row action, gated on `status: :booked`.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Calendar.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:booked, :confirmed, :cancelled]],
      default: :booked

    attribute :team, :string, public?: true, default: "red"
    attribute :starts_on, :date, public?: true
    attribute :ends_on, :date, public?: true
    attribute :starts_at, :utc_datetime, public?: true
    attribute :ends_at, :utc_datetime, public?: true
    attribute :notes, :string, public?: true
  end

  actions do
    defaults [:destroy, create: :*, update: :*]

    read :read do
      primary? true
      prepare AshA2ui.Test.Calendar.TeamScope
    end

    update :confirm do
      accept []
      change set_attribute(:status, :confirmed)
    end
  end
end

defmodule AshA2ui.Test.Calendar.MonthUI do
  @moduledoc """
  A month calendar over date fields (`starts_on` to `ends_on`) with a card
  row layout, a toned status badge, a status filter and the `:confirm` row
  action. Single table, v0.9.1.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Calendar.Event
    surface_id "calendar_month"

    query :schedule do
      filters [:status]
      page_size 10
    end

    component :table, :schedule do
      fields [:title, :status, :starts_on, :ends_on]
      display :calendar
      date_field :starts_on
      end_date_field :ends_on
      granularity :month
      query :schedule
      row_actions [:confirm]

      row_layout do
        title :title
        badge :status
        badge_tones booked: :info, confirmed: :success, cancelled: :danger
        meta [:starts_on, :ends_on]
      end
    end

    action :confirm do
      visible_when status: :booked
    end
  end
end

defmodule AshA2ui.Test.Calendar.WeekUI do
  @moduledoc """
  A week calendar over a UTC datetime (`starts_at`, no end field) beside a
  plain list table: a multi-table surface, flat rows, two-row pages.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Calendar.Event
    surface_id "calendar_week"

    query :week do
      page_size 2
    end

    component :table, :week do
      fields [:title, :starts_at]
      display :calendar
      date_field :starts_at
      granularity :week
      query :week
    end

    component :table, :all do
      fields [:title]
    end
  end
end

defmodule AshA2ui.Test.Calendar.DayUI do
  @moduledoc """
  A day calendar over `starts_at` to `ends_at`, `spec_version "1.0"`, with
  a CSV export (so the admin catalog keeps its basic composition).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Calendar.Event
    surface_id "calendar_day"
    spec_version "1.0"

    query :day do
      page_size 25
    end

    component :table do
      fields [:title, :starts_at, :ends_at]
      display :calendar
      date_field :starts_at
      end_date_field :ends_at
      granularity :day
      query :day

      export do
      end
    end
  end
end
