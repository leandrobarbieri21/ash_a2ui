defmodule AshA2ui.Calendar.CalendarTimeZoneTest do
  @moduledoc """
  The calendar time zone (`config :ash_a2ui, :calendar_time_zone`): days
  are cut, marked and printed in that zone rather than in UTC, a
  daylight-saving day keeps its true length, and the zone may be given as
  an `{module, function, args}` read on every request.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Calendar
  alias AshA2ui.Test.Calendar.{Event, WeekUI}

  @red %{team: "red"}

  setup do
    previous = Application.fetch_env(:ash_a2ui, :calendar_time_zone)

    on_exit(fn ->
      case previous do
        {:ok, zone} -> Application.put_env(:ash_a2ui, :calendar_time_zone, zone)
        :error -> Application.delete_env(:ash_a2ui, :calendar_time_zone)
      end
    end)
  end

  def toronto, do: "America/Toronto"

  defp put_zone(zone), do: Application.put_env(:ash_a2ui, :calendar_time_zone, zone)

  defp envelope(context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "query",
        "surfaceId" => "calendar_week",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => Map.put(context, "component", "week")
      }
    }
  end

  defp query(context) do
    assert {:ok, messages} =
             ActionHandler.handle(WeekUI, envelope(context), actor: @red, authorize?: false)

    Enum.each(messages, &assert_valid_server_message/1)
    messages
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp records(messages), do: value_at(messages, "/records/week")
  defp window(messages), do: value_at(messages, "/query/week")["window"]

  defp event!(title, starts_at) do
    Ash.create!(Event, %{title: title, team: "red", starts_at: starts_at}, authorize?: false)
  end

  # The week of Monday 2026-10-12, carried back by the client.
  defp week_state(selected \\ ""),
    do: %{"pageSize" => 10, "window" => %{"anchor" => "2026-10-12", "selected" => selected}}

  test "days are cut, marked and printed in the calendar time zone" do
    # 21:30 on Friday the 16th in Toronto is 01:30 on Saturday the 17th UTC.
    event!("Late Friday", ~U[2026-10-17 01:30:00Z])
    # 23:00 on Sunday the 18th in Toronto is Monday the 19th UTC: still this week.
    event!("Sunday night", ~U[2026-10-19 03:00:00Z])
    # 23:30 on Sunday the 11th UTC is 19:30 in Toronto: last week, not this one.
    event!("Previous Sunday", ~U[2026-10-11 23:30:00Z])

    put_zone(toronto())

    week = query(%{"query" => week_state()})
    assert window(week)["from"] == "2026-10-12"
    assert Enum.map(window(week)["marks"], & &1["date"]) == ["2026-10-16", "2026-10-18"]

    rows = records(week)
    assert Enum.map(rows, & &1["title"]) == ["Late Friday", "Sunday night"]
    late = hd(rows)
    assert late["_calendar_start"] == "2026-10-16"
    assert late["_calendar_when"] == "2026-10-16 21:30"

    # Picking the 16th reads the Toronto day, which holds the late event.
    friday = query(%{"query" => week_state(), "date" => "2026-10-16"})
    assert Enum.map(records(friday), & &1["title"]) == ["Late Friday"]

    saturday = query(%{"query" => week_state(), "date" => "2026-10-17"})
    assert records(saturday) == []

    # The same reads in UTC (the default) put the events on their UTC days.
    Application.delete_env(:ash_a2ui, :calendar_time_zone)

    utc = query(%{"query" => week_state()})
    assert Enum.map(window(utc)["marks"], & &1["date"]) == ["2026-10-17"]
    assert Enum.map(records(utc), & &1["title"]) == ["Late Friday"]
    assert hd(records(utc))["_calendar_when"] == "2026-10-17 01:30"
  end

  test "the zone may be an {m, f, a} read on every request" do
    put_zone({__MODULE__, :toronto, []})
    assert Calendar.time_zone() == "America/Toronto"

    expected = "America/Toronto" |> DateTime.now!() |> DateTime.to_date()
    assert Calendar.today() == expected

    put_zone({__MODULE__, :toronto_atom, []})
    assert_raise ArgumentError, ~r/must return an IANA time zone name/, &Calendar.time_zone/0

    put_zone(:toronto)
    assert_raise ArgumentError, ~r/must be an IANA time zone name/, &Calendar.time_zone/0
  end

  def toronto_atom, do: :toronto

  test "a datetime end is exclusive: an event ending at midnight stays on its day" do
    put_zone(toronto())

    config = %{
      date_field: :starts_at,
      end_date_field: :ends_at,
      granularity: :week,
      start_kind: :datetime,
      end_kind: :datetime
    }

    # All day on Friday the 16th in Toronto: midnight to the next midnight.
    all_day =
      Ash.create!(
        Event,
        %{
          title: "All day",
          team: "red",
          starts_at: ~U[2026-10-16 04:00:00Z],
          ends_at: ~U[2026-10-17 04:00:00Z]
        },
        authorize?: false
      )

    # Zero length, at midnight on the 17th: it is on the 17th.
    instant =
      Ash.create!(
        Event,
        %{
          title: "Instant",
          team: "red",
          starts_at: ~U[2026-10-17 04:00:00Z],
          ends_at: ~U[2026-10-17 04:00:00Z]
        },
        authorize?: false
      )

    on_day = fn date ->
      Event
      |> Ash.Query.new()
      |> Calendar.filter(config, {date, date})
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.title)
      |> Enum.sort()
    end

    assert on_day.(~D[2026-10-16]) == ["All day"]
    assert on_day.(~D[2026-10-17]) == ["Instant"]

    window = Calendar.default_window(config, ~D[2026-10-14])

    assert Calendar.marks(config, [all_day, instant], window) == [
             %{"date" => "2026-10-16", "count" => 1, "label" => "2026-10-16 (1)"},
             %{"date" => "2026-10-17", "count" => 1, "label" => "2026-10-17 (1)"}
           ]

    table = %{calendar: config}
    assert Calendar.row_data(table, all_day)["_calendar_end"] == "2026-10-16"

    assert Calendar.row_data(table, all_day)["_calendar_when"] ==
             "2026-10-16 00:00 – 2026-10-17 00:00"

    assert Calendar.row_data(table, instant)["_calendar_end"] == "2026-10-17"
  end

  test "a daylight-saving day keeps its true length" do
    put_zone(toronto())

    # Toronto falls back on 2026-11-01: a 25-hour day.
    assert Calendar.day_bounds(~D[2026-11-01]) ==
             {~U[2026-11-01 04:00:00Z], ~U[2026-11-02 04:59:59.999999Z]}

    # ...and springs forward on 2026-03-08: a 23-hour day.
    assert Calendar.day_bounds(~D[2026-03-08]) ==
             {~U[2026-03-08 05:00:00Z], ~U[2026-03-09 03:59:59.999999Z]}

    # Santiago springs forward at midnight on 2026-09-06: the day starts at
    # 01:00 local, the first instant after the gap.
    put_zone("America/Santiago")

    assert Calendar.day_bounds(~D[2026-09-06]) ==
             {~U[2026-09-06 04:00:00Z], ~U[2026-09-07 02:59:59.999999Z]}

    Application.delete_env(:ash_a2ui, :calendar_time_zone)

    assert Calendar.day_bounds(~D[2026-11-01]) ==
             {~U[2026-11-01 00:00:00Z], ~U[2026-11-01 23:59:59.999999Z]}
  end
end
