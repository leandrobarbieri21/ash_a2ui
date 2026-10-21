defmodule AshA2ui.Calendar.CalendarPresetTest do
  @moduledoc """
  Presets on a calendar (`calendar_anchor`): switching to an anchored
  preset moves the window to the one holding today plus the anchor and
  clears the picked day; staying on it never moves the window again; a
  window move in the same request still applies; a plain preset only
  filters.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Calendar
  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Preset
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Calendar.{Event, PresetUI}

  @config %{
    date_field: :starts_on,
    end_date_field: nil,
    granularity: :month,
    start_kind: :date,
    end_kind: nil
  }

  @tomorrow %Preset{name: :tomorrow, calendar_anchor: 1}
  @plain %Preset{name: :plain}

  defp month_of(date), do: Date.beginning_of_month(date)

  test "parse_window follows a newly chosen anchored preset, once" do
    tomorrow = Date.add(Calendar.today(), 1)
    away = %{"window" => %{"anchor" => "2030-01-01", "selected" => "2030-01-15"}}

    # Switching to the preset: the window moves to tomorrow's month and the
    # pick is cleared.
    assert {:ok, window, true} = Calendar.parse_window(@config, away, %{}, @tomorrow)
    assert window.anchor == month_of(tomorrow)
    assert window.selected == nil
    assert window.preset == "tomorrow"
    assert Calendar.state(window, [])["preset"] == "tomorrow"

    # Staying on it: the window stays wherever the user took it.
    stayed = put_in(away, ["window", "preset"], "tomorrow")
    assert {:ok, window, false} = Calendar.parse_window(@config, stayed, %{}, @tomorrow)
    assert {window.anchor, window.selected} == {~D[2030-01-01], ~D[2030-01-15]}

    # A move in the switching request applies on top of the followed window.
    assert {:ok, window, true} =
             Calendar.parse_window(@config, away, %{"windowDelta" => 1}, @tomorrow)

    assert window.anchor == Calendar.shift(:month, month_of(tomorrow), 1)

    # A preset without an anchor, or none, never moves the window.
    assert {:ok, window, false} = Calendar.parse_window(@config, away, %{}, @plain)
    assert {window.anchor, window.preset} == {~D[2030-01-01], "plain"}

    from_plain = put_in(away, ["window", "preset"], "plain")
    assert {:ok, window, false} = Calendar.parse_window(@config, from_plain, %{}, nil)
    assert {window.anchor, window.preset} == {~D[2030-01-01], ""}

    # The carried preset must be a string.
    assert {:error, message} =
             Calendar.parse_window(@config, put_in(away, ["window", "preset"], 1), %{}, nil)

    assert message =~ ~s(window "preset" must be a string)
  end

  test "the default window follows an anchored default preset" do
    tomorrow = Date.add(Calendar.today(), 1)

    window = Calendar.default_window(@config, nil, @tomorrow)
    assert window.anchor == month_of(tomorrow)
    assert window.preset == "tomorrow"

    assert Calendar.default_window(@config).anchor == month_of(Calendar.today())
    assert Calendar.default_window(@config).preset == ""
  end

  defp envelope(context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "query",
        "surfaceId" => "calendar_presets",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => Map.put(context, "component", "schedule")
      }
    }
  end

  defp query(state, extra \\ %{}) do
    context = Map.merge(%{"query" => state}, extra)

    assert {:ok, messages} =
             ActionHandler.handle(PresetUI, envelope(context), actor: nil, authorize?: false)

    Enum.each(messages, &assert_valid_server_message/1)
    messages
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp titles(messages), do: messages |> value_at("/records") |> Enum.map(& &1["title"])
  defp window(messages), do: value_at(messages, "/query")["window"]

  test "a quick-range preset moves the window through the query action" do
    tomorrow = Date.add(Calendar.today(), 1)

    Ash.create!(Event, %{title: "Booked tomorrow", starts_on: tomorrow, status: :booked},
      authorize?: false
    )

    Ash.create!(Event, %{title: "Confirmed tomorrow", starts_on: tomorrow, status: :confirmed},
      authorize?: false
    )

    Ash.create!(Event, %{title: "Booked far away", starts_on: ~D[2030-01-15], status: :booked},
      authorize?: false
    )

    away = %{
      "pageSize" => 10,
      "preset" => "",
      "window" => %{"anchor" => "2030-01-01", "selected" => "2030-01-15", "preset" => ""}
    }

    assert titles(query(away)) == ["Booked far away"]

    # Choosing the preset (then Apply): tomorrow's month, booked only.
    booked = query(Map.put(away, "preset", "booked"), %{"page" => 1})
    assert titles(booked) == ["Booked tomorrow"]
    assert window(booked)["anchor"] == Date.to_iso8601(month_of(tomorrow))
    assert window(booked)["selected"] == ""
    assert window(booked)["preset"] == "booked"

    # Navigating while on the preset goes where the user asked.
    carried = Map.merge(away, %{"preset" => "booked", "window" => window(booked)})
    back = query(carried, %{"anchor" => "2030-01-01"})
    assert titles(back) == ["Booked far away"]
    assert window(back)["anchor"] == "2030-01-01"

    # A plain preset filters where the window is.
    confirmed =
      query(Map.merge(carried, %{"preset" => "confirmed", "window" => window(back)}), %{
        "page" => 1
      })

    assert titles(confirmed) == []
    assert window(confirmed)["anchor"] == "2030-01-01"
    assert window(confirmed)["preset"] == "confirmed"
  end

  test "composed surfaces carry calendar_anchor both ways" do
    allowlist = Dynamic.allowlist([Event])

    {:ok, spec, _rejections} = Importer.import(PresetUI)
    [query] = spec["queries"]

    assert Enum.map(query["presets"], &{&1["name"], &1["calendar_anchor"]}) ==
             [{"booked", 1}, {"confirmed", nil}]

    assert {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)
    [resolved] = ResolvedView.resolve(surface.dsl_state).tables
    presets = resolved.query.presets
    assert Enum.map(presets, &{&1.name, &1.calendar_anchor}) == [booked: 1, confirmed: nil]

    schema = Dynamic.spec_schema(allowlist)
    preset = schema["properties"]["queries"]["items"]["properties"]["presets"]["items"]
    assert preset["properties"]["calendar_anchor"]["type"] == "integer"
  end
end
