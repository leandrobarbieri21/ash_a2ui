defmodule AshA2ui.Board.BoardSwimlanesTest do
  @moduledoc """
  Board swimlanes (A2UI-105B): `swimlanes_by` splits a `display :board`
  into rows across its stage columns. Every (swimlane, lane) cell is an
  expanded table scoped by both attributes; the encoder keeps the stages
  side by side under a header row and stacks one tone-carrying row per
  swimlane; transitions refresh every cell and client filters cannot widen
  a cell.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ContextRunner
  alias AshA2ui.ResolvedView
  alias AshA2ui.Sections
  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.SwimlaneBoardUI
  alias AshA2ui.Test.SwimlaneBoardV1UI

  @cells [
    "board_open__very_high",
    "board_claimed__very_high",
    "board_completed__very_high",
    "board_open__low",
    "board_claimed__low",
    "board_completed__low"
  ]

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  defp create_task!(name, status, severity) do
    Ash.create!(BoardTask, %{name: name, status: status, severity: severity}, authorize?: false)
  end

  defp expanded(ui) do
    {:ok, view} = ui |> ResolvedView.resolve() |> Sections.expand(authorize?: false)
    view
  end

  defp count_reads(fun) do
    handler_id = "board-swimlanes-reads-#{System.unique_integer([:positive])}"
    parent = self()
    domain = Ash.Domain.Info.short_name(AshA2ui.Test.Domain)

    :telemetry.attach(
      handler_id,
      [:ash, domain, :read, :start],
      fn _event, _measurements, _metadata, _config ->
        if self() == parent, do: send(parent, :ash_read)
      end,
      nil
    )

    try do
      result = fun.()
      {result, collect_reads(0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp collect_reads(count) do
    receive do
      :ash_read -> collect_reads(count + 1)
    after
      0 -> count
    end
  end

  # The admin catalog's semantic root is not basic-catalog valid, so its
  # surfaces skip the basic schema check (as the lane-only board's do).
  defp surface_parts(ui, validate? \\ true) do
    messages = AshA2ui.Info.build_surface(ui, authorize?: false)
    if validate?, do: Enum.each(messages, &assert_valid_server_message/1)

    components =
      messages
      |> Enum.find_value(& &1["updateComponents"])
      |> Map.fetch!("components")
      |> Map.new(&{&1["id"], &1})

    value =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    {components, value}
  end

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "swimlane_tasks",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp names(rows), do: rows |> Enum.map(& &1["name"]) |> Enum.sort()

  @tag ac: "A2UI-105B/AC-1"
  test "cells cross lanes and swimlanes" do
    {view, reads} = count_reads(fn -> expanded(SwimlaneBoardUI) end)

    # No read enumerates either axis.
    assert reads == 0

    # One cell per (swimlane, lane), swimlane-major, in the declared orders:
    # swimlane_values [:very_high, :low] drops :medium.
    assert Enum.map(view.tables, & &1.name) == @cells
    assert Enum.map(view.tables, & &1.records_path) == Enum.map(@cells, &"/records/#{&1}")
    assert Enum.map(view.tables, & &1.query_path) == Enum.map(@cells, &"/query/#{&1}")

    [first | _rest] = view.tables
    assert first.section.lane == "board_open"
    assert first.section.label == "To do"

    assert first.section.swimlane == %{
             value: :very_high,
             label: "Critical",
             tone: "danger",
             name: "board__very_high",
             filter: {:severity, :very_high}
           }

    assert Enum.map(view.tables, & &1.section.swimlane.label) ==
             ["Critical", "Critical", "Critical", "Low", "Low", "Low"]

    assert Enum.map(view.tables, & &1.section.swimlane.tone) ==
             ["danger", "danger", "danger", "success", "success", "success"]

    # Each cell's reads AND both filters.
    for table <- view.tables do
      assert {:ok, scope} = ContextRunner.table_scope(view, table, %{})
      assert scope == [table.section.filter, table.section.swimlane.filter]
    end

    # The template key fans out to every cell.
    assert view.refreshes == %{claim: @cells, complete: @cells}

    # Unlisted swimlanes are neutral; every value without swimlane_values.
    v1 = expanded(SwimlaneBoardV1UI)

    assert Enum.map(v1.tables, & &1.name) == [
             "board_open__low",
             "board_claimed__low",
             "board_open__medium",
             "board_claimed__medium",
             "board_open__very_high",
             "board_claimed__very_high"
           ]

    assert v1.tables |> Enum.map(& &1.section.swimlane.tone) |> Enum.uniq() ==
             ["info", "neutral", "warning"]

    # Built, each cell holds only its own records; empty cells are kept.
    create_task!("hot open", :open, :very_high)
    create_task!("cool claimed", :claimed, :low)
    create_task!("medium open", :open, :medium)
    create_task!("archived hot", :archived, :very_high)

    {_components, value} = surface_parts(SwimlaneBoardUI)

    assert names(value["records"]["board_open__very_high"]) == ["hot open"]
    assert names(value["records"]["board_claimed__low"]) == ["cool claimed"]

    for cell <- @cells -- ["board_open__very_high", "board_claimed__low"] do
      assert value["records"][cell] == []
      assert value["_empty_visible_#{cell}"] == [%{"id" => "on"}]
    end
  end

  @tag ac: "A2UI-105B/AC-2"
  test "encodes swimlane rows under the stages" do
    for name <- ["a", "b", "c"], do: create_task!(name, :open, :very_high)
    create_task!("d", :claimed, :very_high)
    create_task!("e", :claimed, :low)

    {components, value} = surface_parts(SwimlaneBoardUI)

    # One root child for the board.
    assert components["root"]["children"] == ["status_text", "board_board", "action_result_panel"]

    assert components["board_board"]["children"] == ["board_board_heading", "board_board_lanes"]

    # The board splits vertically: the stage header row, then one row per
    # swimlane, top to bottom.
    assert components["board_board_lanes"] == %{
             "id" => "board_board_lanes",
             "component" => "Column",
             "children" => [
               "board_board_stages",
               "swimlane_board__very_high",
               "swimlane_board__low"
             ]
           }

    # The stages stay side by side: a Row of weighted stage Columns, each
    # headed by the stage label and its column total.
    assert components["board_board_stages"] == %{
             "id" => "board_board_stages",
             "component" => "Row",
             "align" => "start",
             "children" => ["stage_board_open", "stage_board_claimed", "stage_board_completed"]
           }

    for {lane, label} <- [
          {"board_open", "To do"},
          {"board_claimed", "Claimed"},
          {"board_completed", "Completed"}
        ] do
      assert components["stage_#{lane}"]["component"] == "Column"
      assert components["stage_#{lane}"]["weight"] == 1
      assert components["stage_#{lane}"]["children"] == ["stage_#{lane}_header"]

      assert components["stage_#{lane}_header"]["children"] ==
               ["stage_#{lane}_heading", "stage_#{lane}_total"]

      assert components["stage_#{lane}_heading"] |> Map.take(["text", "variant"]) ==
               %{"text" => label, "variant" => "h3"}

      assert components["stage_#{lane}_total"]["text"] == %{"path" => "/_lane_total_#{lane}"}
    end

    # Each swimlane row: its header (label + total) over a Row of its cells,
    # one per stage, in stage order.
    for {swimlane, label, cells} <- [
          {"board__very_high", "Critical", Enum.take(@cells, 3)},
          {"board__low", "Low", Enum.drop(@cells, 3)}
        ] do
      row = "swimlane_#{swimlane}"
      assert components[row]["component"] == "Column"
      assert components[row]["children"] == ["#{row}_header", "#{row}_cells"]
      assert components["#{row}_header"]["children"] == ["#{row}_heading", "#{row}_total"]
      assert components["#{row}_heading"]["text"] == label
      assert components["#{row}_total"]["text"] == %{"path" => "/_swimlane_total_#{swimlane}"}

      assert components["#{row}_cells"] == %{
               "id" => "#{row}_cells",
               "component" => "Row",
               "align" => "start",
               "children" => Enum.map(cells, &"lane_#{&1}")
             }
    end

    for cell <- @cells do
      # A cell is a lane Column at weight 1, headed by its total alone (the
      # stage and swimlane headings name it).
      assert components["lane_#{cell}"]["weight"] == 1

      assert components["lane_#{cell}"]["children"] == [
               "lane_#{cell}_header",
               "query_#{cell}_controls",
               "records_list_#{cell}",
               "empty_state_#{cell}",
               "query_#{cell}_pagination"
             ]

      assert components["lane_#{cell}_header"]["children"] == ["lane_#{cell}_total"]
      refute Map.has_key?(components, "table_heading_#{cell}")
      assert components["records_list_#{cell}"]["children"]["path"] == "/records/#{cell}"
      assert components["record_row_#{cell}"]["component"] == "Card"
    end

    # Totals per cell (the query's totalCount: 3, though the page holds 2),
    # per swimlane row and per stage column; a tone per swimlane.
    assert value["_lane_total_board_open__very_high"] == "3"
    assert length(value["records"]["board_open__very_high"]) == 2
    assert value["_lane_total_board_claimed__very_high"] == "1"
    assert value["_lane_total_board_claimed__low"] == "1"
    assert value["_lane_total_board_completed__low"] == "0"
    assert value["_swimlane_total_board__very_high"] == "4"
    assert value["_swimlane_total_board__low"] == "1"
    assert value["_lane_total_board_open"] == "3"
    assert value["_lane_total_board_claimed"] == "2"
    assert value["_lane_total_board_completed"] == "0"
    assert value["_swimlane_tone_board__very_high"] == "danger"
    assert value["_swimlane_tone_board__low"] == "success"

    # --- v1.0 (no query: totals from the row count) ---
    assert [message] = AshA2ui.Info.build_surface(SwimlaneBoardV1UI, authorize?: false)
    assert_valid_server_message(message, :v1_0)

    create = message["createSurface"]
    v1 = Map.new(create["components"], &{&1["id"], &1})

    assert v1["board_board_lanes"]["children"] == [
             "board_board_stages",
             "swimlane_board__low",
             "swimlane_board__medium",
             "swimlane_board__very_high"
           ]

    assert v1["board_board_stages"]["children"] == ["stage_board_open", "stage_board_claimed"]
    assert v1["stage_board_open_heading"]["text"] == "### Open"
    assert v1["swimlane_board__very_high_heading"]["text"] == "### Very high"

    assert v1["lane_board_open__very_high"]["children"] == [
             "lane_board_open__very_high_header",
             "records_list_board_open__very_high",
             "empty_state_board_open__very_high"
           ]

    assert create["dataModel"]["_lane_total_board_open__very_high"] == "3"
    assert create["dataModel"]["_swimlane_total_board__very_high"] == "4"
    assert create["dataModel"]["_lane_total_board_claimed"] == "2"
    assert create["dataModel"]["_swimlane_tone_board__medium"] == "neutral"
    assert create["dataModel"]["_swimlane_tone_board__low"] == "info"

    # --- the admin catalog falls back to the basic composition ---
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    {admin, admin_value} = surface_parts(SwimlaneBoardUI, false)

    assert admin["root"]["component"] == "entityPage"
    assert "board_board" in admin["root"]["children"]

    for id <-
          ["board_board_lanes", "board_board_stages", "swimlane_board__low_cells"] ++
            Enum.map(@cells, &"lane_#{&1}") do
      assert admin[id] == components[id], "#{id} differs under the admin catalog"
    end

    assert admin_value["_swimlane_tone_board__very_high"] == "danger"
  end

  @tag ac: "A2UI-105B/AC-3"
  test "transition moves the card between cells" do
    card = create_task!("card", :open, :very_high)
    create_task!("other", :claimed, :very_high)
    create_task!("low one", :claimed, :low)

    message = envelope("invoke", %{"action" => "claim", "recordId" => card.id})

    assert {:ok, messages} = ActionHandler.handle(SwimlaneBoardUI, message, authorize?: false)
    Enum.each(messages, &assert_valid_server_message/1)

    assert Ash.get!(BoardTask, card.id, authorize?: false).status == :claimed

    # Every cell refreshed: the card left the open cell for the claimed one,
    # in its own swimlane.
    for cell <- @cells, do: assert(is_list(value_at(messages, "/records/#{cell}")), cell)

    assert value_at(messages, "/records/board_open__very_high") == []
    assert names(value_at(messages, "/records/board_claimed__very_high")) == ["card", "other"]
    assert names(value_at(messages, "/records/board_claimed__low")) == ["low one"]

    # Cell, swimlane and stage totals follow the move.
    assert value_at(messages, "/_lane_total_board_open__very_high") == "0"
    assert value_at(messages, "/_lane_total_board_claimed__very_high") == "2"
    assert value_at(messages, "/_swimlane_total_board__very_high") == "2"
    assert value_at(messages, "/_swimlane_total_board__low") == "1"
    assert value_at(messages, "/_lane_total_board_open") == "0"
    assert value_at(messages, "/_lane_total_board_claimed") == "3"

    moved =
      Enum.find(value_at(messages, "/records/board_claimed__very_high"), &(&1["name"] == "card"))

    assert moved["_visible_complete"] != []
    assert moved["_visible_claim"] == []
  end

  @tag ac: "A2UI-105B/AC-4"
  test "cell scope cannot be widened by the client" do
    create_task!("hot open", :open, :very_high)
    create_task!("cool open", :open, :low)
    create_task!("medium open", :open, :medium)
    create_task!("hot claimed", :claimed, :very_high)

    query = fn filters ->
      message =
        envelope("query", %{
          "component" => "board_open__very_high",
          "query" => %{"filters" => filters, "page" => 1}
        })

      assert {:ok, messages} = ActionHandler.handle(SwimlaneBoardUI, message, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)
      messages
    end

    # A filter on either axis naming another value narrows to nothing: both
    # scopes are ANDed onto the read.
    for filters <- [
          %{"status" => "claimed"},
          %{"severity" => "low"},
          %{"severity" => "medium"},
          %{"status" => "claimed", "severity" => "low"}
        ] do
      messages = query.(filters)
      assert value_at(messages, "/records/board_open__very_high") == [], inspect(filters)
      assert value_at(messages, "/_lane_total_board_open__very_high") == "0"
    end

    # Its own values narrow nothing away.
    messages = query.(%{"status" => "open", "severity" => "very_high"})
    assert names(value_at(messages, "/records/board_open__very_high")) == ["hot open"]

    # A one-cell query leaves the aggregates of the rows and columns it
    # does not fully cover alone.
    refute value_at(messages, "/_swimlane_total_board__very_high")
    refute value_at(messages, "/_lane_total_board_open")

    # A swimlane outside swimlane_values (medium) is not a component the
    # client can name.
    message =
      envelope("query", %{"component" => "board_open__medium", "query" => %{"page" => 1}})

    assert {:error, _errors} = ActionHandler.handle(SwimlaneBoardUI, message, authorize?: false)
  end
end
