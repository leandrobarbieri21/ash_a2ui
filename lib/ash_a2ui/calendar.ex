defmodule AshA2ui.Calendar do
  @moduledoc """
  Calendars: a `:table` rendered as a month, week or day grid
  (`display :calendar`).

  A calendar adds no component kind. It is a table whose `query` reads only
  the visible **window**: the table's read, preset, context scope, filters
  and search apply as on any table, and the window ANDs a date range onto
  them. Allowlisting, actor scoping and pagination therefore work exactly as
  they do for a list.

      component :table, :schedule do
        fields [:title, :status, :starts_at, :ends_at]
        display :calendar
        date_field :starts_at
        end_date_field :ends_at
        granularity :month
        query :schedule
      end

  ## The window

  The window lives in the table's query state at `/query/<table>/window`:

      %{
        "granularity" => "month",       # the declared granularity
        "anchor" => "2026-10-01",       # the window's first day
        "from" => "2026-10-01",         # first day in the window
        "to" => "2026-10-31",           # last day in the window
        "selected" => "2026-10-17",     # the picked day, "" when none
        "preset" => "",                 # the preset the window last followed
        "label" => "2026-10",           # the window, as text
        "scopeLabel" => "2026-10-17",   # the picked day, else the window label
        "marks" => [%{"date" => "2026-10-17", "count" => 2, "label" => "2026-10-17 (2)"}]
      }

  `from`, `to`, the labels and `marks` are written by the server and
  ignored when the client sends the state back. Only `anchor` and
  `selected` are read, as ISO 8601 dates, and `preset` (see "Presets"
  below): the client never sends a range or a predicate.

  A month window runs from the first to the last day of the month, a week
  window from Monday to Sunday, a day window is one day. Without a carried
  anchor the window holds today, in the calendar time zone.

  ## The time zone

  Days are cut in one time zone: `config :ash_a2ui, :calendar_time_zone`,
  an IANA name (`"America/Toronto"`) or an `{module, function, args}` that
  returns one, read on every request (so a zone set at boot from the
  environment applies). It defaults to `"Etc/UTC"`. A zone other than UTC
  needs a time zone database (`config :elixir, :time_zone_database`, e.g.
  `Tz.TimeZoneDatabase` or `Tzdata.TimeZoneDatabase`).

  The zone decides which day "today" is, where a window day starts and ends
  for datetime fields, which day a datetime record is marked on, and the
  times in `_calendar_when`. `:date` and `:naive_datetime` fields have no
  zone and are read as they are.

  ## Moving the window and picking a day

  Both are the standard `"query"` action. Besides the usual `"query"`
  binding, the context may carry:

    * `"anchor" => "2026-11-01"` — show the window holding that date
      (`"today"` is accepted). The admin catalog's calendar sends the date it
      is already showing, so the server follows what the user sees even when
      several clicks are in flight.
    * `"windowDelta" => -1 | 1` — move the window by whole units relative to
      the carried anchor (the basic composition's Previous/Next buttons).
    * `"date" => "2026-10-17"` — pick a day (`""` clears the pick). On a
      `:day` calendar picking a day moves the window to it.

  A picked day narrows the records read to that day; the marks still cover
  the whole window. Moving the window keeps the picked day only when it is
  still inside it. Either change resets the page to 1.

  ## Presets

  The query's presets apply to a calendar as to any table: the window ANDs
  onto the preset's read. A preset that declares `calendar_anchor` also
  moves the window. When the requested preset differs from the one the
  window last followed (`"preset"` in the window state, written by the
  server), the window moves to the one holding today plus `calendar_anchor`
  days and the picked day is cleared; an `"anchor"`, `"windowDelta"` or
  `"date"` in the same request still applies on top. Staying on the preset
  never moves the window again, so the user can navigate away from it. The
  first render follows the `default_preset` the same way.

  ## Matching records

  Without an `end_date_field` a record is in the window when its
  `date_field` falls inside it. With one, a record matches when it overlaps
  the window: it starts on or before the window's last day and ends on or
  after its first day (a `nil` end counts as the start day). A datetime end
  is exclusive, the instant the record is over: one ending at exactly
  midnight does not reach into the next day. For datetime
  fields a window day runs from local midnight to just before the next local
  midnight in the calendar time zone, so a day that a daylight-saving change
  shortens or lengthens keeps its true length.

  ## Marks

  `marks` lists the days of the window that hold at least one record, with
  their count. When the page already holds every record of the window (no
  picked day, page 1, no further page) the marks come from those rows;
  otherwise the server reads the window's start and end dates once more,
  through the same read and filters, capped at 1,000 rows.

  ## Rows

  Every row of a calendar table carries three reserved keys:
  `_calendar_start` and `_calendar_end` (ISO dates, the end never before
  the start) and `_calendar_when` (the record's date or date-time span as
  text, in the calendar time zone).
  """

  import Ash.Expr

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Verifier

  @marks_limit 1_000
  @max_window_delta 1_200

  @date_types [Ash.Type.Date]
  @datetime_types [Ash.Type.UtcDatetime, Ash.Type.UtcDatetimeUsec, Ash.Type.DateTime]
  @naive_types [Ash.Type.NaiveDatetime]

  @typedoc "The kind of a calendar date field: how it is bounded and read."
  @type kind :: :date | :datetime | :naive

  @typedoc "A resolved calendar config (the table's `:calendar` key)."
  @type config :: %{
          date_field: atom,
          end_date_field: atom | nil,
          granularity: :day | :week | :month,
          start_kind: kind,
          end_kind: kind | nil
        }

  @typedoc """
  A validated window: its first day, the picked day, its range, and the
  name of the preset it last followed (`""` for none).
  """
  @type window :: %{
          granularity: :day | :week | :month,
          anchor: Date.t(),
          selected: Date.t() | nil,
          from: Date.t(),
          to: Date.t(),
          preset: String.t()
        }

  @doc "The granularities a calendar accepts."
  @spec granularities() :: [:day | :week | :month]
  def granularities, do: [:day, :week, :month]

  @doc "The row cap of the marks read."
  @spec marks_limit() :: pos_integer
  def marks_limit, do: @marks_limit

  @doc """
  The kind of `field` on `resource` as a calendar date field: `:date`,
  `:datetime` (UTC datetimes) or `:naive`, or `nil` when it is not a public
  date or datetime attribute.
  """
  @spec field_kind(module | map, atom) :: kind | nil
  def field_kind(resource, field) do
    case ResourceInfo.attribute(resource, field) do
      %{public?: true, type: type} -> type |> Ash.Type.get_type() |> type_kind()
      _missing_or_private -> nil
    end
  end

  defp type_kind(type) when type in @date_types, do: :date
  defp type_kind(type) when type in @datetime_types, do: :datetime
  defp type_kind(type) when type in @naive_types, do: :naive
  defp type_kind(_type), do: nil

  @doc """
  The resolved calendar config of a `display :calendar` table component
  over `resource`, or `nil` for any other component.
  """
  @spec resolve(AshA2ui.Component.t(), module) :: config | nil
  def resolve(%{display: :calendar, date_field: date_field} = component, resource)
      when not is_nil(date_field) do
    %{
      date_field: date_field,
      end_date_field: component.end_date_field,
      granularity: component.granularity || :month,
      start_kind: field_kind(resource, date_field) || :date,
      end_kind:
        component.end_date_field && (field_kind(resource, component.end_date_field) || :date)
    }
  end

  def resolve(_component, _resource), do: nil

  @doc """
  The calendar rules of one component, shared by the compile-time verifier
  (`AshA2ui.Verifiers.VerifyCalendar`) and composed surfaces
  (`AshA2ui.Dynamic`, which runs the same verifier over the spec):

    * `display :calendar` only on `:table` components,
    * a `date_field` and a `query`,
    * `granularity` in `granularities/0`,
    * no `sections` and no `bulk_actions`,
    * `date_field` / `end_date_field` public `:date` or datetime attributes
      of `resource` (skipped when `resource` is `nil`, i.e. not resolvable
      yet), and not the same attribute,
    * `date_field`, `end_date_field` and `granularity` only with
      `display :calendar`.

  Returns `:ok` or `{:error, option, message}`, `option` being the
  offending component option.
  """
  @spec validate(AshA2ui.Component.t(), module | map | nil) :: :ok | {:error, atom, String.t()}
  def validate(%{display: :calendar} = component, resource) do
    with :ok <- validate_table(component),
         :ok <- validate_required(component),
         :ok <- validate_granularity(component),
         :ok <- validate_compatible(component) do
      validate_fields(component, resource)
    end
  end

  def validate(component, _resource) do
    case Enum.find([:date_field, :end_date_field, :granularity], &Map.get(component, &1)) do
      nil -> :ok
      option -> {:error, option, "#{option} is only supported with display :calendar"}
    end
  end

  defp validate_table(%{name: :table}), do: :ok

  defp validate_table(_component),
    do: {:error, :display, "display :calendar is only supported on :table components"}

  defp validate_required(%{date_field: nil}) do
    {:error, :display,
     "display :calendar needs a date_field: the date or datetime attribute that places " <>
       "each record on the calendar"}
  end

  defp validate_required(%{query: nil}) do
    {:error, :query,
     "display :calendar needs a query: the visible window is read through the table's " <>
       "query (its page size bounds the records shown per window)"}
  end

  defp validate_required(_component), do: :ok

  defp validate_granularity(%{granularity: granularity}) do
    if is_nil(granularity) or granularity in granularities(),
      do: :ok,
      else:
        {:error, :granularity,
         "granularity must be one of #{inspect(granularities())}, got: #{inspect(granularity)}"}
  end

  defp validate_compatible(%{sections: sections}) when not is_nil(sections),
    do: {:error, :sections, "a display :calendar table cannot declare a sections block"}

  defp validate_compatible(%{bulk_actions: [_ | _]}),
    do: {:error, :bulk_actions, "a display :calendar table cannot declare bulk_actions"}

  defp validate_compatible(_component), do: :ok

  defp validate_fields(_component, nil), do: :ok

  defp validate_fields(component, resource) do
    with :ok <- validate_date_field(component, resource, :date_field),
         :ok <- validate_date_field(component, resource, :end_date_field) do
      if component.end_date_field == component.date_field,
        do:
          {:error, :end_date_field,
           "end_date_field must differ from date_field (#{inspect(component.date_field)})"},
        else: :ok
    end
  end

  defp validate_date_field(component, resource, option) do
    field = Map.get(component, option)

    if is_nil(field) or field_kind(resource, field) do
      :ok
    else
      {:error, option,
       "#{option} #{inspect(field)} must be a public :date or datetime attribute " <>
         "(:utc_datetime, :utc_datetime_usec, :datetime, :naive_datetime) of " <>
         inspect(resource_name(resource)) <> date_fields_hint(resource)}
    end
  end

  # Lists what is available, so an agent composing a spec can self-correct.
  defp date_fields_hint(resource) do
    case resource
         |> ResourceInfo.public_attributes()
         |> Enum.filter(&field_kind(resource, &1.name)) do
      [] -> " — it has no date or datetime attributes"
      fields -> " — its date and datetime attributes: #{inspect(Enum.map(fields, & &1.name))}"
    end
  end

  defp resource_name(resource) when is_atom(resource), do: resource

  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)

  @doc "Whether a resolved table is a calendar."
  @spec calendar?(map) :: boolean
  def calendar?(table), do: not is_nil(Map.get(table, :calendar))

  # --- windows ----------------------------------------------------------------

  @doc """
  The window holding `date` with no picked day. Without a `date` it holds
  today, or today plus the `calendar_anchor` of `preset` (the active
  preset, `nil` for none), which the window then follows.
  """
  @spec default_window(config, Date.t() | nil, AshA2ui.Preset.t() | nil) :: window
  def default_window(config, date \\ nil, preset \\ nil) do
    date = date || preset_anchor(preset) || today()
    config.granularity |> build_window(date, nil) |> Map.put(:preset, preset_name(preset))
  end

  defp preset_name(nil), do: ""
  defp preset_name(%{name: name}), do: to_string(name)

  defp preset_anchor(%{calendar_anchor: days}) when is_integer(days), do: Date.add(today(), days)
  defp preset_anchor(_preset), do: nil

  # --- the time zone ----------------------------------------------------------

  @doc """
  The calendar time zone: `config :ash_a2ui, :calendar_time_zone` (an IANA
  name, or an `{module, function, args}` returning one), `"Etc/UTC"` when
  unset. See "The time zone" in the moduledoc.
  """
  @spec time_zone() :: String.t()
  def time_zone do
    case Application.get_env(:ash_a2ui, :calendar_time_zone, "Etc/UTC") do
      zone when is_binary(zone) ->
        zone

      {module, function, args} when is_atom(module) and is_atom(function) and is_list(args) ->
        case apply(module, function, args) do
          zone when is_binary(zone) ->
            zone

          other ->
            raise ArgumentError,
                  "config :ash_a2ui, :calendar_time_zone: #{inspect({module, function, args})} " <>
                    "must return an IANA time zone name, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError,
              "config :ash_a2ui, :calendar_time_zone must be an IANA time zone name or an " <>
                "{module, function, args} returning one, got: #{inspect(other)}"
    end
  end

  @doc "Today's date in the calendar time zone."
  @spec today() :: Date.t()
  def today do
    case time_zone() do
      "Etc/UTC" -> Date.utc_today()
      zone -> zone |> DateTime.now!() |> DateTime.to_date()
    end
  end

  @doc """
  The UTC instants `{first, last}` of `date` in the calendar time zone:
  local midnight (or, when a daylight-saving change skips midnight, the
  first instant after the gap) up to a microsecond before the next day
  starts. Window days for datetime fields are cut with these bounds.
  """
  @spec day_bounds(Date.t()) :: {DateTime.t(), DateTime.t()}
  def day_bounds(%Date{} = date) do
    zone = time_zone()
    {bound(:datetime, date, :from, zone), bound(:datetime, date, :to, zone)}
  end

  # The UTC instant a day starts at in `zone`: local midnight, or the first
  # instant after the gap when a daylight-saving change skips midnight.
  defp day_start(date, "Etc/UTC"), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp day_start(date, zone) do
    local =
      case DateTime.new(date, ~T[00:00:00], zone) do
        {:ok, datetime} -> datetime
        {:gap, _just_before, just_after} -> just_after
        {:ambiguous, first, _second} -> first
        {:error, reason} -> raise ArgumentError, "calendar time zone #{inspect(zone)}: #{reason}"
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end

  defp to_zone(%DateTime{} = datetime, zone), do: DateTime.shift_zone!(datetime, zone)

  @doc """
  Parses the window of a `"query"` action against `config`: the carried
  state's `"window"` (`anchor`, `selected`, `preset`) and the context's
  `"anchor"`, `"windowDelta"` and `"date"` keys (see the moduledoc).
  `preset` is the request's active preset (`nil` for none): switching to
  one that declares `calendar_anchor` moves the window first. Returns
  `{:ok, window, changed?}` — `changed?` when the window or the picked day
  differ from the carried state — or `{:error, reason}`.
  """
  @spec parse_window(config, map, map, AshA2ui.Preset.t() | nil) ::
          {:ok, window, boolean} | {:error, String.t()}
  def parse_window(config, state, context, preset \\ nil) do
    carried = window_state_map(state)
    granularity = config.granularity

    with {:ok, carried_anchor} <- carried_date(carried, "anchor"),
         {:ok, carried_selected} <- carried_date(carried, "selected"),
         {:ok, followed} <- followed_anchor(carried, preset),
         {:ok, moved} <- requested_anchor(context, granularity, followed || carried_anchor),
         {:ok, picked} <- requested_date(context) do
      carried_window = build_window(granularity, carried_anchor || today(), carried_selected)

      base =
        if followed,
          do: build_window(granularity, followed, nil),
          else: carried_window

      window =
        granularity
        |> apply_request(base, moved, picked)
        |> Map.put(:preset, preset_name(preset))

      changed? =
        window.anchor != carried_window.anchor or window.selected != carried_selected

      {:ok, window, changed?}
    end
  end

  # The day the window moves to when the request switches to a preset with a
  # `calendar_anchor`; nil when it stays on the preset the window followed.
  defp followed_anchor(carried, preset) do
    case Map.get(carried, "preset", "") do
      followed when is_binary(followed) ->
        if followed == preset_name(preset), do: {:ok, nil}, else: {:ok, preset_anchor(preset)}

      _other ->
        {:error, ~s(Malformed query action: window "preset" must be a string.)}
    end
  end

  defp window_state_map(state) when is_map(state) do
    case Map.get(state, "window") do
      window when is_map(window) -> window
      _missing -> %{}
    end
  end

  defp window_state_map(_state), do: %{}

  defp carried_date(carried, key) do
    case Map.get(carried, key) do
      empty when empty in [nil, ""] -> {:ok, nil}
      value when is_binary(value) -> iso_date(value, "window #{key}")
      _other -> {:error, ~s(Malformed query action: window "#{key}" must be an ISO date.)}
    end
  end

  # The absolute anchor wins over the relative delta.
  defp requested_anchor(context, granularity, carried_anchor) do
    case context |> Map.get("anchor") |> request_anchor() do
      {:ok, nil} -> requested_delta(context, granularity, carried_anchor)
      other -> other
    end
  end

  defp request_anchor(nil), do: {:ok, nil}
  defp request_anchor("today"), do: {:ok, today()}
  defp request_anchor(anchor) when is_binary(anchor), do: iso_date(anchor, "anchor")

  defp request_anchor(_other),
    do: {:error, ~s(Malformed query action: "anchor" must be an ISO date.)}

  defp requested_delta(context, granularity, carried_anchor) do
    case Map.get(context, "windowDelta") do
      nil ->
        {:ok, nil}

      delta when is_integer(delta) and abs(delta) <= @max_window_delta ->
        anchor = carried_anchor || today()
        {:ok, shift(granularity, window_start(granularity, anchor), delta)}

      _other ->
        {:error,
         ~s(Malformed query action: "windowDelta" must be an integer between ) <>
           "-#{@max_window_delta} and #{@max_window_delta}."}
    end
  end

  # `:none` when the context picks nothing, `nil` when it clears the pick.
  defp requested_date(context) do
    case Map.fetch(context, "date") do
      :error -> {:ok, :none}
      {:ok, empty} when empty in [nil, ""] -> {:ok, nil}
      {:ok, [value]} -> requested_date(%{"date" => value})
      {:ok, value} when is_binary(value) -> iso_date(value, "date")
      {:ok, _other} -> {:error, ~s(Malformed query action: "date" must be an ISO date.)}
    end
  end

  # A :day calendar has no picked day: picking one moves the window there.
  defp apply_request(:day, base, moved, picked) do
    anchor =
      case picked do
        %Date{} = date -> date
        _none_or_cleared -> moved || base.anchor
      end

    build_window(:day, anchor, nil)
  end

  defp apply_request(granularity, base, moved, picked) do
    anchor = moved || base.anchor

    selected =
      case picked do
        :none -> base.selected
        other -> other
      end

    build_window(granularity, anchor, selected)
  end

  # The window holding `date`; a picked day outside it is dropped.
  defp build_window(granularity, date, selected) do
    {from, to} = range(granularity, date)

    selected =
      if selected && Date.compare(selected, from) != :lt && Date.compare(selected, to) != :gt,
        do: selected,
        else: nil

    %{granularity: granularity, anchor: from, selected: selected, from: from, to: to, preset: ""}
  end

  defp iso_date(value, what) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, date}

      {:error, _reason} ->
        {:error, "Malformed query action: #{what} #{inspect(value)} is not an ISO date."}
    end
  end

  @doc "The first and last day of the `granularity` window holding `date`."
  @spec range(:day | :week | :month, Date.t()) :: {Date.t(), Date.t()}
  def range(:day, date), do: {date, date}

  def range(:week, date) do
    monday = Date.add(date, 1 - Date.day_of_week(date))
    {monday, Date.add(monday, 6)}
  end

  def range(:month, date) do
    first = Date.beginning_of_month(date)
    {first, Date.end_of_month(first)}
  end

  defp window_start(granularity, date), do: granularity |> range(date) |> elem(0)

  @doc "The first day of the window `delta` units away from the one starting at `anchor`."
  @spec shift(:day | :week | :month, Date.t(), integer) :: Date.t()
  def shift(:day, anchor, delta), do: Date.add(anchor, delta)
  def shift(:week, anchor, delta), do: Date.add(anchor, 7 * delta)

  def shift(:month, anchor, delta) do
    months = anchor.year * 12 + anchor.month - 1 + delta
    Date.new!(div(months, 12), rem(months, 12) + 1, 1)
  end

  @doc """
  The days the records read covers: the picked day when there is one, else
  the whole window.
  """
  @spec read_range(window) :: {Date.t(), Date.t()}
  def read_range(%{selected: %Date{} = day}), do: {day, day}
  def read_range(window), do: {window.from, window.to}

  # --- filtering --------------------------------------------------------------

  @doc """
  ANDs the window filter for the `{from, to}` day range onto `query` (see
  "Matching records" in the moduledoc).
  """
  @spec filter(Ash.Query.t(), config, {Date.t(), Date.t()}) :: Ash.Query.t()
  def filter(query, %{end_date_field: nil} = config, {from, to}) do
    zone = time_zone()
    start = config.date_field
    from_bound = bound(config.start_kind, from, :from, zone)
    to_bound = bound(config.start_kind, to, :to, zone)

    Ash.Query.filter(query, ^ref(start) >= ^from_bound and ^ref(start) <= ^to_bound)
  end

  def filter(query, config, {from, to}) do
    zone = time_zone()
    start = config.date_field
    finish = config.end_date_field

    start_to = bound(config.start_kind, to, :to, zone)
    start_from = bound(config.start_kind, from, :from, zone)
    end_from = bound(config.end_kind, from, :from, zone)

    # A record starting inside the window always matches (so does one with
    # a nil end). A date end is the record's last day; a datetime end is
    # the instant it is over, so one ending at the window's first instant
    # does not reach into it.
    if config.end_kind == :date do
      Ash.Query.filter(
        query,
        ^ref(start) <= ^start_to and (^ref(finish) >= ^end_from or ^ref(start) >= ^start_from)
      )
    else
      Ash.Query.filter(
        query,
        ^ref(start) <= ^start_to and (^ref(finish) > ^end_from or ^ref(start) >= ^start_from)
      )
    end
  end

  defp bound(:date, date, _side, _zone), do: date
  defp bound(:datetime, date, :from, zone), do: day_start(date, zone)

  # The last instant before the next day starts (a microsecond before it).
  defp bound(:datetime, date, :to, zone),
    do: date |> Date.add(1) |> day_start(zone) |> DateTime.add(-1, :microsecond)

  defp bound(:naive, date, :from, _zone), do: NaiveDateTime.new!(date, ~T[00:00:00])
  defp bound(:naive, date, :to, _zone), do: NaiveDateTime.new!(date, ~T[23:59:59.999999])

  @doc """
  Reads the marks of `window` through `filtered` (the table's read with its
  preset, scope, filters and search applied, before the window): the start
  and end dates of at most `marks_limit/0` matching records.
  """
  @spec read_marks(Ash.Query.t(), config, window) :: {:ok, [map]} | {:error, term}
  def read_marks(filtered, config, window) do
    fields = Enum.reject([config.date_field, config.end_date_field], &is_nil/1)

    filtered
    |> filter(config, {window.from, window.to})
    |> Ash.Query.select(fields)
    |> Ash.Query.sort([{config.date_field, :asc}])
    |> Ash.Query.limit(@marks_limit)
    |> Ash.read()
    |> case do
      {:ok, records} -> {:ok, marks(config, records, window)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The marks of `window` over `records`: one entry per day of the window
  that at least one record covers, in day order.
  """
  @spec marks(config, [struct], window) :: [map]
  def marks(config, records, window) do
    zone = time_zone()

    records
    |> Enum.flat_map(fn record ->
      {first, last} = span(config, record, zone)
      clipped_days(first, last, window)
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {day, _count} -> day end, Date)
    |> Enum.map(fn {day, count} ->
      iso = Date.to_iso8601(day)
      %{"date" => iso, "count" => count, "label" => "#{iso} (#{count})"}
    end)
  end

  defp clipped_days(nil, _last, _window), do: []

  defp clipped_days(first, last, window) do
    first = latest(first, window.from)
    last = earliest(last, window.to)

    if Date.compare(first, last) == :gt,
      do: [],
      else: first |> Date.range(last) |> Enum.to_list()
  end

  defp latest(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
  defp earliest(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)

  # A record's first and last day; the end is never before the start.
  defp span(config, record, zone) do
    start = Map.get(record, config.date_field)
    first = to_date(start, zone)
    finish = config.end_date_field && Map.get(record, config.end_date_field)

    last =
      case last_date(start, finish, zone) do
        %Date{} = last when not is_nil(first) -> latest(last, first)
        _none -> first
      end

    {first, last}
  end

  # A datetime end is exclusive: one at exactly midnight (after the start)
  # closes the day before, as an all-day event ending at the next midnight
  # does.
  defp last_date(start, %DateTime{} = finish, zone) do
    local = to_zone(finish, zone)
    date = DateTime.to_date(local)

    if midnight?(local) and after_start?(finish, start),
      do: Date.add(date, -1),
      else: date
  end

  defp last_date(start, %NaiveDateTime{} = finish, _zone) do
    date = NaiveDateTime.to_date(finish)

    if midnight?(finish) and after_start?(finish, start),
      do: Date.add(date, -1),
      else: date
  end

  defp last_date(_start, finish, zone), do: to_date(finish, zone)

  defp midnight?(%{hour: 0, minute: 0, second: 0, microsecond: {0, _precision}}), do: true
  defp midnight?(_datetime), do: false

  defp after_start?(%DateTime{} = finish, %DateTime{} = start),
    do: DateTime.compare(finish, start) == :gt

  defp after_start?(%NaiveDateTime{} = finish, %NaiveDateTime{} = start),
    do: NaiveDateTime.compare(finish, start) == :gt

  defp after_start?(_finish, _start), do: false

  defp to_date(%Date{} = date, _zone), do: date
  defp to_date(%DateTime{} = datetime, zone), do: datetime |> to_zone(zone) |> DateTime.to_date()
  defp to_date(%NaiveDateTime{} = naive, _zone), do: NaiveDateTime.to_date(naive)
  defp to_date(_other, _zone), do: nil

  # --- state ------------------------------------------------------------------

  @doc "The `/query/<table>/window` state of `window` with its `marks`."
  @spec state(window, [map]) :: map
  def state(window, marks) do
    label = label(window)
    selected = window.selected && Date.to_iso8601(window.selected)

    %{
      "granularity" => to_string(window.granularity),
      "anchor" => Date.to_iso8601(window.anchor),
      "from" => Date.to_iso8601(window.from),
      "to" => Date.to_iso8601(window.to),
      "selected" => selected || "",
      "preset" => Map.get(window, :preset, ""),
      "label" => label,
      "scopeLabel" => selected || label,
      "marks" => marks
    }
  end

  @doc "The window as text: `2026-10`, `2026-10-12 – 2026-10-18` or `2026-10-17`."
  @spec label(window) :: String.t()
  def label(%{granularity: :month, anchor: anchor}),
    do: anchor |> Date.to_iso8601() |> binary_part(0, 7)

  def label(%{granularity: :week, from: from, to: to}),
    do: "#{Date.to_iso8601(from)} – #{Date.to_iso8601(to)}"

  def label(%{granularity: :day, anchor: anchor}), do: Date.to_iso8601(anchor)

  # --- rows -------------------------------------------------------------------

  @doc """
  The reserved row keys of a calendar table's row (`%{}` for any other
  table): `_calendar_start`, `_calendar_end` and `_calendar_when`.
  """
  @spec row_data(map | nil, struct) :: map
  def row_data(%{calendar: %{} = config}, record) do
    zone = time_zone()
    {first, last} = span(config, record, zone)

    %{
      "_calendar_start" => (first && Date.to_iso8601(first)) || "",
      "_calendar_end" => (last && Date.to_iso8601(last)) || "",
      "_calendar_when" => when_text(config, record, zone)
    }
  end

  def row_data(_table, _record), do: %{}

  defp when_text(config, record, zone) do
    start = Map.get(record, config.date_field)
    finish = config.end_date_field && Map.get(record, config.end_date_field)

    case {point_text(start, zone), point_text(finish, zone)} do
      {"", _finish} -> ""
      {start_text, ""} -> start_text
      {same, same} -> same
      {start_text, finish_text} -> "#{start_text} – #{same_day_suffix(start_text, finish_text)}"
    end
  end

  # "2026-10-17 09:30 – 11:00" when both ends fall on one day.
  defp same_day_suffix(
         <<day::binary-size(10), " ", _::binary>>,
         <<day::binary-size(10), " ", time::binary>>
       ),
       do: time

  defp same_day_suffix(_start_text, finish_text), do: finish_text

  defp point_text(%Date{} = date, _zone), do: Date.to_iso8601(date)

  defp point_text(%DateTime{} = datetime, zone) do
    datetime |> to_zone(zone) |> DateTime.to_naive() |> point_text(zone)
  end

  defp point_text(%NaiveDateTime{} = naive, _zone) do
    date = naive |> NaiveDateTime.to_date() |> Date.to_iso8601()
    time = naive |> NaiveDateTime.to_time() |> Time.to_iso8601() |> binary_part(0, 5)
    "#{date} #{time}"
  end

  defp point_text(_other, _zone), do: ""
end
