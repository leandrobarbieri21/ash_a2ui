defmodule AshA2ui.Board.BoardActionHandlerTest do
  @moduledoc """
  Board behavior through `AshA2ui.ActionHandler` (A2UI-105): a transition
  row action moves a card between lanes (the template-key refresh re-reads
  every lane), and a lane's own scope cannot be widened by a client query.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.BoardTaskUI

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "board_tasks",
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

  defp create_task!(name, status) do
    Ash.create!(BoardTask, %{name: name, status: status}, authorize?: false)
  end

  @tag ac: "A2UI-105/AC-5"
  test "transition moves the card between lanes" do
    card = create_task!("card", :open)
    create_task!("other", :claimed)

    # The card sits in the open lane, where :claim is visible and :complete
    # (gated on :claimed) is not.
    surface = AshA2ui.Info.build_surface(BoardTaskUI, authorize?: false)

    initial =
      Enum.find_value(surface, fn
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    assert [open_row] = initial["records"]["board_open"]
    assert open_row["name"] == "card"
    assert open_row["_visible_claim"] != []
    assert open_row["_visible_complete"] == []

    message = envelope("invoke", %{"action" => "claim", "recordId" => card.id})

    assert {:ok, messages} = ActionHandler.handle(BoardTaskUI, message, authorize?: false)
    Enum.each(messages, &assert_valid_server_message/1)

    # The record changed state.
    assert Ash.get!(BoardTask, card.id, authorize?: false).status == :claimed

    # `refreshes [:board]` (the template key) re-read every lane.
    assert value_at(messages, "/records/board_open") == []
    assert names(value_at(messages, "/records/board_claimed")) == ["card", "other"]
    assert value_at(messages, "/records/board_completed") == []

    # Totals follow the move.
    assert value_at(messages, "/_lane_total_board_open") == "0"
    assert value_at(messages, "/_lane_total_board_claimed") == "2"
    assert value_at(messages, "/_lane_total_board_completed") == "0"

    # In the claimed lane the card now offers :complete, not :claim.
    moved = Enum.find(value_at(messages, "/records/board_claimed"), &(&1["name"] == "card"))
    assert moved["_visible_claim"] == []
    assert moved["_visible_complete"] != []
  end

  @tag ac: "A2UI-105/AC-6"
  test "lane scope cannot be widened by the client" do
    create_task!("open one", :open)
    create_task!("claimed one", :claimed)
    create_task!("claimed two", :claimed)
    create_task!("archived one", :archived)

    # A query naming the open lane with a filter on the lane attribute that
    # targets another value: the lane's scope (status == :open) is ANDed, so
    # nothing from the claimed lane comes back.
    for other <- ["claimed", "archived", "completed"] do
      message =
        envelope("query", %{
          "component" => "board_open",
          "query" => %{"filters" => %{"status" => other}, "page" => 1}
        })

      assert {:ok, messages} = ActionHandler.handle(BoardTaskUI, message, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      assert value_at(messages, "/records/board_open") == []
      assert value_at(messages, "/_lane_total_board_open") == "0"
      assert %{"filters" => %{"status" => ^other}} = value_at(messages, "/query/board_open")
    end

    # The same filter on its own value narrows nothing away.
    message =
      envelope("query", %{
        "component" => "board_open",
        "query" => %{"filters" => %{"status" => "open"}, "page" => 1}
      })

    assert {:ok, messages} = ActionHandler.handle(BoardTaskUI, message, authorize?: false)
    assert names(value_at(messages, "/records/board_open")) == ["open one"]

    # A lane outside the declared `values` (archived) is not a component the
    # client can name.
    message =
      envelope("query", %{
        "component" => "board_archived",
        "query" => %{"page" => 1}
      })

    assert {:error, errors} = ActionHandler.handle(BoardTaskUI, message, authorize?: false)
    refute Enum.any?(errors, &(&1["updateDataModel"]["path"] == "/records/board_archived"))

    # A filter value that is not one of the attribute's values is rejected
    # (cast against the one_of constraint, never turned into an atom).
    message =
      envelope("query", %{
        "component" => "board_open",
        "query" => %{"filters" => %{"status" => "not_a_status_#{System.unique_integer()}"}}
      })

    assert {:error, _errors} = ActionHandler.handle(BoardTaskUI, message, authorize?: false)
  end
end
