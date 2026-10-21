defmodule AshA2ui.Calendar.CalendarGranularityTest do
  @moduledoc """
  Switching a calendar's window size (`granularities`): the client names a
  size the calendar offers and the server keeps the user's place (the
  picked day, else today, else the old window's first day); any other size
  is rejected before a read; the basic composition offers one Button per
  size and the admin `calendarView` carries the list; composed surfaces
  carry it both ways; and the DSL rules hold.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Calendar
  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Calendar.{Event, MonthUI, SwitchUI}

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  @config %{
    date_field: :starts_on,
    end_date_field: nil,
    granularity: :month,
    granularities: [:month, :week, :day],
    start_kind: :date,
    end_kind: nil
  }

  test "switching keeps the picked day, else today, else the window's start" do
    picked = %{"window" => %{"anchor" => "2030-01-01", "selected" => "2030-01-15"}}

    assert {:ok, week, true} = Calendar.parse_window(@config, picked, %{"granularity" => "week"})
    # 2030-01-15 is a Tuesday: its week starts on Monday the 14th.
    assert {week.granularity, week.anchor, week.selected} ==
             {:week, ~D[2030-01-14], ~D[2030-01-15]}

    assert Calendar.state(week, [])["granularity"] == "week"

    # A day window holds the picked day and has no pick of its own.
    assert {:ok, day, true} = Calendar.parse_window(@config, picked, %{"granularity" => "day"})
    assert {day.anchor, day.selected} == {~D[2030-01-15], nil}

    # The carried size is the one the window keeps.
    carried = %{"window" => %{"anchor" => "2030-01-14", "granularity" => "week"}}
    assert {:ok, still, false} = Calendar.parse_window(@config, carried, %{})
    assert {still.granularity, still.anchor} == {:week, ~D[2030-01-14]}

    # Without a pick: today when the old window holds it...
    today = Calendar.today()
    this_month = %{"window" => %{"anchor" => Date.to_iso8601(Date.beginning_of_month(today))}}

    assert {:ok, week, true} =
             Calendar.parse_window(@config, this_month, %{"granularity" => "week"})

    assert week.from == Date.add(today, 1 - Date.day_of_week(today))

    # ...else the old window's first day (March 2030 starts on a Friday).
    march = %{"window" => %{"anchor" => "2030-03-01"}}
    assert {:ok, week, true} = Calendar.parse_window(@config, march, %{"granularity" => "week"})
    assert week.anchor == ~D[2030-02-25]

    # A size the calendar does not offer is refused; so is a carried one
    # (which falls back to the size it opens on).
    month_only = Map.put(@config, :granularities, [:month])

    assert {:error, message} =
             Calendar.parse_window(month_only, picked, %{"granularity" => "week"})

    assert message =~ ~s(granularity "week" is not one of)

    assert {:ok, window, _changed?} =
             Calendar.parse_window(month_only, carried, %{})

    assert window.granularity == :month
  end

  defp envelope(context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "query",
        "surfaceId" => "calendar_switch",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => Map.put(context, "component", "schedule")
      }
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  test "the query action reads the window of the size the client switches to" do
    for {title, date} <- [
          {"Mon", ~D[2030-01-14]},
          {"Sun", ~D[2030-01-20]},
          {"Later", ~D[2030-01-28]}
        ] do
      Ash.create!(Event, %{title: title, starts_on: date}, authorize?: false)
    end

    state = %{"pageSize" => 10, "window" => %{"anchor" => "2030-01-01", "selected" => ""}}

    assert {:ok, month} =
             ActionHandler.handle(SwitchUI, envelope(%{"query" => state}), authorize?: false)

    assert Enum.map(value_at(month, "/records"), & &1["title"]) == ["Mon", "Sun", "Later"]

    picked = put_in(state, ["window", "selected"], "2030-01-16")

    assert {:ok, week} =
             ActionHandler.handle(
               SwitchUI,
               envelope(%{"query" => picked, "granularity" => "week", "date" => ""}),
               authorize?: false
             )

    Enum.each(week, &assert_valid_server_message/1)
    window = value_at(week, "/query")["window"]

    assert {window["granularity"], window["from"], window["to"]} ==
             {"week", "2030-01-14", "2030-01-20"}

    assert Enum.map(value_at(week, "/records"), & &1["title"]) == ["Mon", "Sun"]
    assert Enum.map(window["marks"], & &1["date"]) == ["2030-01-14", "2030-01-20"]

    # Next now moves by weeks: two on is the week of the 28th.
    carried = Map.put(state, "window", window)

    assert {:ok, later} =
             ActionHandler.handle(
               SwitchUI,
               envelope(%{"query" => carried, "windowDelta" => 2}),
               authorize?: false
             )

    assert value_at(later, "/query")["window"]["from"] == "2030-01-28"
    assert Enum.map(value_at(later, "/records"), & &1["title"]) == ["Later"]

    assert {:error, refused} =
             ActionHandler.handle(
               SwitchUI,
               envelope(%{"query" => state, "granularity" => "year"}),
               authorize?: false
             )

    assert value_at(refused, "/records") == nil
    assert value_at(refused, "/ui/feedback")["message"] =~ "Malformed query action"
  end

  defp components_by_id(messages) do
    for message <- messages,
        component <- components_of(message),
        into: %{},
        do: {component["id"], component}
  end

  defp components_of(%{"updateComponents" => %{"components" => components}}), do: components
  defp components_of(%{"createSurface" => %{"components" => components}}), do: components
  defp components_of(_message), do: []

  test "the basic composition offers a Button per size; the admin view lists them" do
    by_id = SwitchUI |> AshA2ui.Info.build_surface(authorize?: false) |> components_by_id()

    assert Enum.take(by_id["calendar_nav"]["children"], -3) ==
             ~w(calendar_month_button calendar_week_button calendar_day_button)

    assert by_id["calendar_week_button"]["action"]["event"]["context"]["granularity"] == "week"
    assert by_id["calendar_week_text"]["text"] == "Week"

    # A calendar without a switch has no size Buttons.
    plain = MonthUI |> AshA2ui.Info.build_surface(authorize?: false) |> components_by_id()
    assert Map.has_key?(plain, "calendar_nav")
    refute Map.has_key?(plain, "calendar_month_button")

    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    admin = SwitchUI |> AshA2ui.Info.build_surface(authorize?: false) |> components_by_id()
    view = admin["calendar"]

    assert view["component"] == "calendarView"
    assert view["granularity"] == "month"
    assert view["granularities"] == ["month", "week", "day"]

    catalog = "priv/a2ui/admin_v1/catalog.json" |> File.read!() |> Jason.decode!()

    schema =
      catalog["components"]["calendarView"]
      |> Map.put("$defs", catalog["$defs"] || %{})
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, view) == :ok
  end

  test "composed surfaces carry granularities both ways" do
    allowlist = Dynamic.allowlist([Event])

    {:ok, spec, _rejections} = Importer.import(SwitchUI)
    [table] = spec["components"]
    assert table["granularities"] == ["month", "week", "day"]

    assert {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)
    [resolved] = ResolvedView.resolve(surface.dsl_state).tables
    assert resolved.calendar.granularities == [:month, :week, :day]
    assert resolved.calendar.granularity == :month

    bad = put_in(spec, ["components", Access.at(0), "granularities"], ["year"])
    assert {:error, _errors} = Dynamic.resolve(bad, allowlist: allowlist)

    # Promoted to DSL source, the switch survives.
    assert {:ok, source} =
             Dynamic.to_dsl_source(spec,
               module: AshA2ui.Calendar.PromotedSwitchUI,
               allowlist: allowlist
             )

    assert source =~ "granularities [:month, :week, :day]"
    [{module, _binary}] = Code.compile_string(source)
    assert hd(ResolvedView.resolve(module).tables).calendar == resolved.calendar
  end

  test "granularity must be one of granularities" do
    component = %AshA2ui.Component{
      name: :table,
      display: :calendar,
      date_field: :starts_on,
      query: :schedule,
      granularity: :day,
      granularities: [:month, :week]
    }

    assert {:error, :granularities, message} = Calendar.validate(component, Event)
    assert message =~ "must include the granularity"

    assert {:error, :granularities, _message} =
             Calendar.validate(%{component | granularity: nil, granularities: []}, Event)

    assert :ok = Calendar.validate(%{component | granularity: nil}, Event)
    assert Calendar.resolve(%{component | granularity: nil}, Event).granularity == :month

    assert {:error, :granularities, _message} =
             Calendar.validate(
               %{component | display: :list, date_field: nil, granularity: nil},
               Event
             )
  end
end
