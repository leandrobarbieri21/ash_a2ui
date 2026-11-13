defmodule AshA2ui.Board.BoardGoldenTest do
  @moduledoc """
  Boards without `swimlanes_by` encode byte-for-byte as before swimlanes
  (A2UI-105B): the surfaces of the lane-only board fixtures — queried,
  unqueried, the admin catalog's basic fallback — and a transition's
  handler reply match golden payloads first captured on the pre-swimlane
  base (0add6c5) and re-recorded for the A2UI 1.0 wire.

  Re-record (only on purpose, when the wire itself changes) with
  `RECORD_BOARD_GOLDEN=1 mix test test/ash_a2ui/board/board_golden_test.exs`.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.Messages

  @golden_dir Path.expand("golden", __DIR__)

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
    :ok
  end

  # The substitutions replace each seeded random id with a stable tag.
  defp seed(rows) do
    rows
    |> Enum.map(fn {name, status, priority} ->
      task =
        Ash.create!(BoardTask, %{name: name, status: status, priority: priority},
          authorize?: false
        )

      {task, "TASK_#{String.upcase(name)}"}
    end)
  end

  defp substitutions(seeded) do
    for {task, tag} <- seeded,
        separator <- ["-", "_", " "],
        do: {String.replace(task.id, "-", separator), tag}
  end

  defp normalize(messages, substitutions) do
    json = Jason.encode!(messages)
    Enum.reduce(substitutions, json, fn {id, tag}, acc -> String.replace(acc, id, tag) end)
  end

  defp assert_golden(file, json) do
    path = Path.join(@golden_dir, "#{file}.json")

    if System.get_env("RECORD_BOARD_GOLDEN") do
      File.write!(path, json)
    end

    assert json == File.read!(path), "#{file} differs from its pre-swimlane golden"
  end

  defp claim_envelope(card) do
    Messages.call("invoke", "board_tasks", %{"action" => "claim", "recordId" => card.id},
      id: "call-claim"
    )
  end

  @tag ac: "A2UI-105B/AC-6"
  test "a board without swimlanes encodes as before" do
    # Three open tasks (the open lane pages at page_size 2) and one per
    # other status, archived outside the declared lanes.
    seeded =
      seed([
        {"alpha", :open, :high},
        {"bravo", :open, :low},
        {"charlie", :open, :low},
        {"delta", :claimed, :high},
        {"echo", :completed, :low},
        {"foxtrot", :archived, :high}
      ])

    subs = substitutions(seeded)

    assert_golden(
      "board_task_ui",
      normalize(AshA2ui.Info.build_surface(AshA2ui.Test.BoardTaskUI, authorize?: false), subs)
    )

    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    assert_golden(
      "board_task_admin_ui",
      normalize(AshA2ui.Info.build_surface(AshA2ui.Test.BoardTaskUI, authorize?: false), subs)
    )

    Application.delete_env(:ash_a2ui, :catalog)

    [{alpha, _tag} | _rest] = seeded

    assert {:ok, messages} =
             ActionHandler.handle(AshA2ui.Test.BoardTaskUI, claim_envelope(alpha),
               authorize?: false
             )

    assert_golden("board_task_claim", normalize(messages, subs))
  end

  @tag ac: "A2UI-105B/AC-6"
  test "an unqueried board without swimlanes encodes as before" do
    # One task per lane: without a query the lane's read has no sort, so a
    # lane holding several records would order them by ETS hash.
    subs = substitutions(seed([{"alpha", :open, :high}, {"delta", :claimed, :low}]))

    assert_golden(
      "board_task_unqueried_ui",
      normalize(
        AshA2ui.Info.build_surface(AshA2ui.Test.BoardTaskUnqueriedUI, authorize?: false),
        subs
      )
    )
  end
end
