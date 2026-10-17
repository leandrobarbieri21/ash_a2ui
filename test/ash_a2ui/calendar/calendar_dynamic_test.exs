defmodule AshA2ui.Calendar.CalendarDynamicTest do
  @moduledoc """
  Calendars in composed surfaces (A2UI-109, Jira AST-176): the dynamic
  spec carries `display: "calendar"` with `date_field`, `end_date_field`
  and `granularity`; the same calendar rules as the DSL
  (`AshA2ui.Calendar.validate/2`, run through `VerifyCalendar`) reject a
  spec the DSL would reject; and a declared calendar exports to a spec that
  resolves, promotes and serializes back.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.Calendar.{Event, MonthUI}

  @allowlist Dynamic.allowlist([Event])

  defp tables(surface), do: AshA2ui.ResolvedView.resolve(surface.dsl_state).tables

  defp spec(table_overrides, extra \\ %{}) do
    Map.merge(
      %{
        "resource" => "Event",
        "queries" => [%{"name" => "schedule", "page_size" => 10}],
        "components" => [
          Map.merge(
            %{
              "kind" => "table",
              "name" => "schedule",
              "fields" => ["title", "starts_on", "ends_on"],
              "display" => "calendar",
              "date_field" => "starts_on",
              "end_date_field" => "ends_on",
              "granularity" => "week",
              "query" => "schedule"
            },
            table_overrides
          )
        ]
      },
      extra
    )
  end

  defp messages({:error, errors}), do: errors |> Error.messages() |> Enum.join("\n")

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  @tag ac: "A2UI-109/AC-1"
  test "a composed calendar resolves, renders and re-queries as the actor" do
    Ash.create!(Event, %{title: "Red Mon", starts_on: ~D[2026-10-12], team: "red"},
      authorize?: false
    )

    Ash.create!(Event, %{title: "Red next", starts_on: ~D[2026-10-19], team: "red"},
      authorize?: false
    )

    Ash.create!(Event, %{title: "Blue Mon", starts_on: ~D[2026-10-12], team: "blue"},
      authorize?: false
    )

    assert {:ok, surface} = Dynamic.resolve(spec(%{}), allowlist: @allowlist)

    assert [table] = tables(surface)
    assert table.calendar.granularity == :week
    assert table.calendar.end_date_field == :ends_on

    red = %{team: "red"}

    messages =
      Dynamic.build_surface(surface,
        actor: red,
        authorize?: false,
        query_state: %{"window" => %{"anchor" => "2026-10-14"}}
      )

    Enum.each(messages, &assert_valid_server_message/1)
    data = Enum.find_value(messages, &get_in(&1, ["updateDataModel", "value"]))

    assert data["query"]["window"]["from"] == "2026-10-12"
    assert Enum.map(data["records"], & &1["title"]) == ["Red Mon"]

    components = Enum.find_value(messages, &get_in(&1, ["updateComponents", "components"]))
    assert Enum.any?(components, &(&1["id"] == "calendar_nav"))

    # The window action is the standard query, served on the held surface.
    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "query",
        "surfaceId" => surface.surface_id,
        "sourceComponentId" => "calendar_next_button",
        "timestamp" => "2026-10-17T00:00:00Z",
        "context" => %{
          "component" => "schedule",
          "query" => data["query"],
          "windowDelta" => 1
        }
      }
    }

    assert {:ok, reply} = Dynamic.handle_action(surface, envelope, actor: red, authorize?: false)
    assert value_at(reply, "/query")["window"]["from"] == "2026-10-19"
    assert Enum.map(value_at(reply, "/records"), & &1["title"]) == ["Red next"]
  end

  @tag ac: "A2UI-109/AC-2"
  test "rejects what the DSL rejects" do
    table = fn change -> fn spec -> update_in(spec, ["components", Access.at(0)], change) end end
    put = fn key, value -> table.(&Map.put(&1, key, value)) end
    drop = fn key -> table.(&Map.delete(&1, key)) end

    cases = [
      {drop.("query"), ~r/display :calendar needs a query/},
      {drop.("date_field"), ~r/display :calendar needs a date_field/},
      {put.("date_field", "title"),
       ~r/date_field :title must be a public :date or datetime attribute.*its date and datetime attributes: \[:starts_on, :ends_on, :starts_at, :ends_at\]/s},
      {put.("date_field", "status"), ~r/date_field :status must be a public :date or datetime/},
      {put.("date_field", "zz_not_an_attribute_of_anything_9f3"),
       ~r/date_field "zz_not_an_attribute_of_anything_9f3" is not an attribute of the resource/},
      {put.("end_date_field", "notes"), ~r/end_date_field :notes must be a public :date/},
      {put.("end_date_field", "starts_on"), ~r/end_date_field must differ from date_field/},
      {put.("granularity", "year"), ~r/granularity must be one of: day, month, week/},
      {put.("display", "board"), ~r/display must be one of: calendar, list/},
      {put.("display", "list"),
       ~r/(date_field|end_date_field|granularity) is only supported with display :calendar/},
      {put.("bulk_actions", ["confirm"]), ~r/unknown key "bulk_actions"/}
    ]

    for {change, pattern} <- cases do
      result = Dynamic.resolve(change.(spec(%{})), allowlist: @allowlist)
      assert {:error, _errors} = result, "expected a rejection matching #{inspect(pattern)}"

      assert messages(result) =~ pattern,
             "expected #{inspect(pattern)}, got:\n#{messages(result)}"
    end
  end

  @tag ac: "A2UI-109/AC-3"
  test "a declared calendar exports, promotes and serializes back" do
    {:ok, spec, rejections} = Importer.import(MonthUI)

    # Only the deployment metadata is outside the vocabulary now.
    assert Enum.map(rejections, & &1.feature) == ["surface_id"]

    [table] = spec["components"]

    assert Map.take(table, ~w(display date_field end_date_field granularity query)) == %{
             "display" => "calendar",
             "date_field" => "starts_on",
             "end_date_field" => "ends_on",
             "granularity" => "month",
             "query" => "schedule"
           }

    assert {:ok, surface} = Dynamic.resolve(spec, allowlist: @allowlist)
    assert hd(tables(surface)).calendar.date_field == :starts_on

    # The spec serializes and deserializes losslessly.
    assert {:ok, back} = spec |> Dynamic.serialize() |> Dynamic.deserialize(allowlist: @allowlist)
    assert hd(tables(back)).calendar == hd(tables(surface)).calendar

    # Promoting to DSL source keeps the calendar, and the module compiles.
    assert {:ok, source} =
             Dynamic.to_dsl_source(spec,
               module: AshA2ui.Calendar.PromotedMonthUI,
               allowlist: @allowlist
             )

    assert source =~ "display :calendar"
    assert source =~ "date_field :starts_on"
    assert source =~ "end_date_field :ends_on"
    assert source =~ "granularity :month"

    [{module, _binary}] = Code.compile_string(source)

    assert hd(AshA2ui.ResolvedView.resolve(module).tables).calendar ==
             hd(tables(surface)).calendar
  end

  test "the spec schema offers the calendar vocabulary" do
    component = Dynamic.spec_schema(@allowlist)["properties"]["components"]["items"]

    assert component["properties"]["display"]["enum"] == ["list", "calendar"]
    assert component["properties"]["granularity"]["enum"] == ["day", "week", "month"]
    assert Map.has_key?(component["properties"], "date_field")
    assert Map.has_key?(component["properties"], "end_date_field")
  end
end
