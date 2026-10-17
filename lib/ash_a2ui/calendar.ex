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
        "label" => "2026-10",           # the window, as text
        "scopeLabel" => "2026-10-17",   # the picked day, else the window label
        "marks" => [%{"date" => "2026-10-17", "count" => 2, "label" => "2026-10-17 (2)"}]
      }

  `from`, `to`, the labels and `marks` are written by the server and
  ignored when the client sends the state back. Only `anchor` and
  `selected` are read, and only as ISO 8601 dates: the client never sends a
  range or a predicate.

  A month window runs from the first to the last day of the month, a week
  window from Monday to Sunday, a day window is one day. Without a carried
  anchor the window holds today (`Date.utc_today/0`).

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

  ## Matching records

  Without an `end_date_field` a record is in the window when its
  `date_field` falls inside it. With one, a record matches when it overlaps
  the window: it starts on or before the window's last day and ends on or
  after its first day (a `nil` end counts as the start day). Datetime fields
  are compared in UTC: a window day runs from 00:00:00 to 23:59:59.999999
  UTC.

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
  text, in UTC).
  """

  import Ash.Expr

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo

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

  @typedoc "A validated window: its first day, the picked day and its range."
  @type window :: %{
          granularity: :day | :week | :month,
          anchor: Date.t(),
          selected: Date.t() | nil,
          from: Date.t(),
          to: Date.t()
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

  @doc "Whether a resolved table is a calendar."
  @spec calendar?(map) :: boolean
  def calendar?(table), do: not is_nil(Map.get(table, :calendar))

  # --- windows ----------------------------------------------------------------

  @doc "The window holding `date` (today by default) with no picked day."
  @spec default_window(config, Date.t()) :: window
  def default_window(config, date \\ Date.utc_today()) do
    build_window(config.granularity, date, nil)
  end

  @doc """
  Parses the window of a `"query"` action against `config`: the carried
  state's `"window"` (`anchor`, `selected`) and the context's `"anchor"`,
  `"windowDelta"` and `"date"` keys (see the moduledoc). Returns
  `{:ok, window, changed?}` — `changed?` when the window or the picked day
  differ from the carried state — or `{:error, reason}`.
  """
  @spec parse_window(config, map, map) :: {:ok, window, boolean} | {:error, String.t()}
  def parse_window(config, state, context) do
    carried = window_state_map(state)
    granularity = config.granularity

    with {:ok, carried_anchor} <- carried_date(carried, "anchor"),
         {:ok, carried_selected} <- carried_date(carried, "selected"),
         {:ok, moved} <- requested_anchor(context, granularity, carried_anchor),
         {:ok, picked} <- requested_date(context) do
      base = build_window(granularity, carried_anchor || Date.utc_today(), carried_selected)
      window = apply_request(granularity, base, moved, picked)

      changed? =
        window.anchor != base.anchor or window.selected != carried_selected

      {:ok, window, changed?}
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
  defp request_anchor("today"), do: {:ok, Date.utc_today()}
  defp request_anchor(anchor) when is_binary(anchor), do: iso_date(anchor, "anchor")

  defp request_anchor(_other),
    do: {:error, ~s(Malformed query action: "anchor" must be an ISO date.)}

  defp requested_delta(context, granularity, carried_anchor) do
    case Map.get(context, "windowDelta") do
      nil ->
        {:ok, nil}

      delta when is_integer(delta) and abs(delta) <= @max_window_delta ->
        anchor = carried_anchor || Date.utc_today()
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

    %{granularity: granularity, anchor: from, selected: selected, from: from, to: to}
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
    start = config.date_field
    from_bound = bound(config.start_kind, from, :from)
    to_bound = bound(config.start_kind, to, :to)

    Ash.Query.filter(query, ^ref(start) >= ^from_bound and ^ref(start) <= ^to_bound)
  end

  def filter(query, config, {from, to}) do
    start = config.date_field
    finish = config.end_date_field

    start_to = bound(config.start_kind, to, :to)
    start_from = bound(config.start_kind, from, :from)
    end_from = bound(config.end_kind, from, :from)

    Ash.Query.filter(
      query,
      ^ref(start) <= ^start_to and
        (^ref(finish) >= ^end_from or (is_nil(^ref(finish)) and ^ref(start) >= ^start_from))
    )
  end

  defp bound(:date, date, _side), do: date
  defp bound(:datetime, date, :from), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp bound(:datetime, date, :to), do: DateTime.new!(date, ~T[23:59:59.999999], "Etc/UTC")
  defp bound(:naive, date, :from), do: NaiveDateTime.new!(date, ~T[00:00:00])
  defp bound(:naive, date, :to), do: NaiveDateTime.new!(date, ~T[23:59:59.999999])

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
    records
    |> Enum.flat_map(fn record ->
      {first, last} = span(config, record)
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
  defp span(config, record) do
    first = record |> Map.get(config.date_field) |> to_date()

    last =
      case config.end_date_field && record |> Map.get(config.end_date_field) |> to_date() do
        %Date{} = last when not is_nil(first) -> latest(last, first)
        _none -> first
      end

    {first, last}
  end

  defp to_date(%Date{} = date), do: date

  defp to_date(%DateTime{} = datetime),
    do: datetime |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()

  defp to_date(%NaiveDateTime{} = naive), do: NaiveDateTime.to_date(naive)
  defp to_date(_other), do: nil

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
    {first, last} = span(config, record)

    %{
      "_calendar_start" => (first && Date.to_iso8601(first)) || "",
      "_calendar_end" => (last && Date.to_iso8601(last)) || "",
      "_calendar_when" => when_text(config, record)
    }
  end

  def row_data(_table, _record), do: %{}

  defp when_text(config, record) do
    start = Map.get(record, config.date_field)
    finish = config.end_date_field && Map.get(record, config.end_date_field)

    case {point_text(start), point_text(finish)} do
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

  defp point_text(%Date{} = date), do: Date.to_iso8601(date)

  defp point_text(%DateTime{} = datetime) do
    datetime |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive() |> point_text()
  end

  defp point_text(%NaiveDateTime{} = naive) do
    date = naive |> NaiveDateTime.to_date() |> Date.to_iso8601()
    time = naive |> NaiveDateTime.to_time() |> Time.to_iso8601() |> binary_part(0, 5)
    "#{date} #{time}"
  end

  defp point_text(_other), do: ""
end
