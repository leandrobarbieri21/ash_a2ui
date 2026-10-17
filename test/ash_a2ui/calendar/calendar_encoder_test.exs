defmodule AshA2ui.Calendar.CalendarEncoderTest do
  @moduledoc """
  Calendar payloads (AST-173): the basic agenda composition on v0.9.1 and
  v1.0 (schema-validated, built from basic-catalog components only, so a
  stock renderer shows it), the window state and row keys, and the admin
  catalog's `calendarView` wrapping the table's `dataGrid`.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Test.Calendar.{DayUI, Event, MonthUI, WeekUI}

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  defp event!(attrs) do
    Ash.create!(Event, Map.merge(%{title: "event"}, attrs), authorize?: false)
  end

  defp seed_october do
    event!(%{title: "Spans in", starts_on: ~D[2026-09-29], ends_on: ~D[2026-10-01]})
    event!(%{title: "Kickoff", starts_on: ~D[2026-10-03]})

    event!(%{
      title: "Offsite",
      starts_on: ~D[2026-10-16],
      ends_on: ~D[2026-10-18],
      status: :confirmed
    })

    event!(%{title: "November", starts_on: ~D[2026-11-02]})
    event!(%{title: "September", starts_on: ~D[2026-09-10]})
  end

  defp components_by_id(components), do: Map.new(components, &{&1["id"], &1})

  defp v0_9_1_parts(ui, opts) do
    messages = AshA2ui.Info.build_surface(ui, [authorize?: false] ++ opts)
    Enum.each(messages, &assert_valid_server_message/1)

    components =
      messages |> Enum.find_value(& &1["updateComponents"]) |> Map.fetch!("components")

    value =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    {components_by_id(components), value}
  end

  defp october, do: [query_state: %{"window" => %{"anchor" => "2026-10-20"}}]

  @tag ac: "AST-173/AC-3"
  test "encodes the basic agenda for both versions" do
    seed_october()

    # --- v0.9.1 ---
    {components, value} = v0_9_1_parts(MonthUI, october())

    # The window state: the month holding the carried anchor.
    window = value["query"]["window"]

    assert Map.take(window, ~w(granularity anchor from to selected label scopeLabel)) == %{
             "granularity" => "month",
             "anchor" => "2026-10-01",
             "from" => "2026-10-01",
             "to" => "2026-10-31",
             "selected" => "",
             "label" => "2026-10",
             "scopeLabel" => "2026-10"
           }

    # Only records overlapping October, in date order (a September event
    # ending on October 1 overlaps it).
    assert Enum.map(value["records"], & &1["title"]) == ["Spans in", "Kickoff", "Offsite"]

    # Marks: every October day a record covers, clipped to the window.
    assert window["marks"] == [
             %{"date" => "2026-10-01", "count" => 1, "label" => "2026-10-01 (1)"},
             %{"date" => "2026-10-03", "count" => 1, "label" => "2026-10-03 (1)"},
             %{"date" => "2026-10-16", "count" => 1, "label" => "2026-10-16 (1)"},
             %{"date" => "2026-10-17", "count" => 1, "label" => "2026-10-17 (1)"},
             %{"date" => "2026-10-18", "count" => 1, "label" => "2026-10-18 (1)"}
           ]

    # Row keys.
    offsite = Enum.find(value["records"], &(&1["title"] == "Offsite"))
    assert offsite["_calendar_start"] == "2026-10-16"
    assert offsite["_calendar_end"] == "2026-10-18"
    assert offsite["_calendar_when"] == "2026-10-16 – 2026-10-18"

    kickoff = Enum.find(value["records"], &(&1["title"] == "Kickoff"))
    assert kickoff["_calendar_end"] == "2026-10-03"
    assert kickoff["_calendar_when"] == "2026-10-03"

    # The composition: the window controls sit above the table's own list.
    assert components["root"]["children"] == [
             "status_text",
             "table_heading",
             "query_controls",
             "calendar",
             "records_list",
             "empty_state",
             "query_pagination",
             "action_result_panel"
           ]

    assert components["calendar"]["children"] == [
             "calendar_nav",
             "calendar_days",
             "calendar_scope"
           ]

    assert components["calendar_nav"]["children"] == [
             "calendar_prev_button",
             "calendar_label",
             "calendar_next_button",
             "calendar_today_button"
           ]

    assert components["calendar_label"]["text"] == %{"path" => "/query/window/label"}

    assert components["calendar_prev_button"]["action"] == %{
             "event" => %{
               "name" => "query",
               "context" => %{
                 "query" => %{"path" => "/query"},
                 "component" => "schedule",
                 "windowDelta" => -1
               }
             }
           }

    assert get_in(components, ["calendar_today_button", "action", "event", "context", "anchor"]) ==
             "today"

    # One Button per marked day, picking it.
    assert components["calendar_days"]["children"] == %{
             "componentId" => "calendar_day_button",
             "path" => "/query/window/marks"
           }

    assert get_in(components, ["calendar_day_button", "action", "event", "context", "date"]) ==
             %{"path" => "date"}

    assert components["calendar_day_text"]["text"] == %{"path" => "label"}

    assert get_in(components, ["calendar_all_button", "action", "event", "context", "date"]) == ""
    assert components["calendar_scope_label"]["text"] == %{"path" => "/query/window/scopeLabel"}

    # Each row starts with its date text (card header under a row_layout).
    assert hd(components["record_row_header"]["children"]) == "record_row_when"
    assert components["record_row_when"]["text"] == %{"path" => "_calendar_when"}

    # --- v1.0 (a day calendar) ---
    event!(%{
      title: "Standup",
      starts_at: ~U[2026-10-20 09:30:00Z],
      ends_at: ~U[2026-10-20 09:45:00Z]
    })

    event!(%{title: "Late", starts_at: ~U[2026-10-21 23:30:00Z]})

    assert [message] =
             AshA2ui.Info.build_surface(DayUI,
               authorize?: false,
               query_state: %{"window" => %{"anchor" => "2026-10-20"}}
             )

    assert_valid_server_message(message, :v1_0)

    create = message["createSurface"]
    v1 = components_by_id(create["components"])
    data = create["dataModel"]

    # A day calendar has no day list: the window is the day.
    assert v1["calendar"]["children"] == ["calendar_nav"]
    refute Map.has_key?(v1, "calendar_days")
    assert hd(v1["record_row_content"]["children"]) == "record_row_when"

    assert data["query"]["window"]["from"] == "2026-10-20"
    assert data["query"]["window"]["to"] == "2026-10-20"
    assert Enum.map(data["records"], & &1["title"]) == ["Standup"]
    assert hd(data["records"])["_calendar_when"] == "2026-10-20 09:30 – 09:45"
  end

  @tag ac: "AST-173/AC-3"
  test "a week calendar beside a list table" do
    event!(%{title: "Mon", starts_at: ~U[2026-10-12 00:00:00Z]})
    event!(%{title: "Sun late", starts_at: ~U[2026-10-18 23:59:59Z]})
    event!(%{title: "Next Mon", starts_at: ~U[2026-10-19 00:00:00Z]})
    event!(%{title: "Wed", starts_at: ~U[2026-10-14 12:00:00Z]})

    {components, value} =
      v0_9_1_parts(WeekUI, query_state: %{"week" => %{"window" => %{"anchor" => "2026-10-15"}}})

    window = value["query"]["week"]["window"]
    assert window["from"] == "2026-10-12"
    assert window["to"] == "2026-10-18"
    assert window["label"] == "2026-10-12 – 2026-10-18"

    # A two-row page of the three week events, in date order; the marks
    # still cover the whole week (read again: the page is not the window).
    assert Enum.map(value["records"]["week"], & &1["title"]) == ["Mon", "Wed"]
    assert value["query"]["week"]["hasMore"] == true
    assert Enum.map(window["marks"], & &1["date"]) == ["2026-10-12", "2026-10-14", "2026-10-18"]

    # The list table beside it is untouched: no window, every record.
    assert length(value["records"]["all"]) == 4
    refute Map.has_key?(components, "calendar_all")
    assert "calendar_week" in components["root"]["children"]
    assert hd(components["record_row_week_content"]["children"]) == "record_row_week_when"
    refute "record_row_all_when" in components["record_row_all_content"]["children"]
  end

  @tag ac: "AST-173/AC-8"
  test "the fallback is basic catalog only" do
    seed_october()

    {components, _value} = v0_9_1_parts(MonthUI, october())

    basic =
      "priv/a2ui/v0_9_1/catalogs/basic/catalog.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("components")
      |> Map.keys()
      |> MapSet.new()

    kinds = components |> Map.values() |> MapSet.new(& &1["component"])

    assert MapSet.subset?(kinds, basic),
           "non-basic kinds: #{inspect(MapSet.difference(kinds, basic))}"

    # The agenda is the table's list over its records.
    assert components["records_list"]["children"] == %{
             "componentId" => "record_row",
             "path" => "/records"
           }
  end

  @tag ac: "AST-173/AC-4"
  test "encodes the admin calendar view" do
    seed_october()
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    messages = AshA2ui.Info.build_surface(MonthUI, [authorize?: false] ++ october())

    components =
      messages |> Enum.find_value(& &1["updateComponents"]) |> Map.fetch!("components")

    by_id = components_by_id(components)

    assert by_id["root"]["component"] == "entityPage"
    assert "calendar" in by_id["root"]["children"]
    refute "data_grid" in by_id["root"]["children"]

    assert by_id["calendar"] == %{
             "id" => "calendar",
             "component" => "calendarView",
             "label" => "Event",
             "granularity" => "month",
             "window" => %{"path" => "/query/window"},
             "windowAction" => %{
               "name" => "query",
               "context" => %{"query" => %{"path" => "/query"}, "component" => "schedule"}
             },
             "children" => ["data_grid"]
           }

    # The wrapped grid is the table's ordinary dataGrid, row actions and all.
    grid = by_id["data_grid"]
    assert grid["component"] == "dataGrid"
    assert grid["rows"] == %{"path" => "/records"}
    assert Enum.any?(grid["rowActions"], &(&1["context"]["action"] == "confirm"))
    assert "pagination" in grid["children"]

    # Both validate against the admin catalog definition.
    catalog = "priv/a2ui/admin_v1/catalog.json" |> File.read!() |> Jason.decode!()

    for {kind, id} <- [{"calendarView", "calendar"}, {"dataGrid", "data_grid"}] do
      schema =
        catalog["components"][kind]
        |> Map.put("$defs", catalog["$defs"] || %{})
        |> ExJsonSchema.Schema.resolve()

      assert ExJsonSchema.Validator.validate(schema, by_id[id]) == :ok
    end

    # No basic calendar controls under the admin catalog.
    refute Map.has_key?(by_id, "calendar_nav")
    refute Map.has_key?(by_id, "calendar_days")

    # The data model is the same window state.
    value =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    assert value["query"]["window"]["anchor"] == "2026-10-01"
    assert length(value["query"]["window"]["marks"]) == 5
  end

  @tag ac: "AST-173/AC-4"
  test "an exported calendar keeps the basic agenda under the admin catalog" do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    assert [message] =
             AshA2ui.Info.build_surface(DayUI,
               authorize?: false,
               query_state: %{"window" => %{"anchor" => "2026-10-20"}}
             )

    by_id = components_by_id(message["createSurface"]["components"])

    assert by_id["root"]["component"] == "entityPage"
    assert "calendar" in by_id["root"]["children"]
    assert by_id["calendar"]["component"] == "Column"
    assert by_id["calendar"]["children"] == ["calendar_nav"]
    assert by_id["calendar_prev_button"]["component"] == "Button"
    refute Enum.any?(Map.values(by_id), &(&1["component"] == "calendarView"))
  end

  test "without a carried anchor the window holds today" do
    today = Date.utc_today()
    event!(%{title: "Today", starts_on: today})

    {_components, value} = v0_9_1_parts(MonthUI, [])

    assert value["query"]["window"]["anchor"] ==
             today |> Date.beginning_of_month() |> Date.to_iso8601()

    assert Enum.map(value["records"], & &1["title"]) == ["Today"]
  end
end
