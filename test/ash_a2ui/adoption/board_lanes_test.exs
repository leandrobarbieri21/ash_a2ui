defmodule AshA2ui.Adoption.BoardLanesTest do
  @moduledoc """
  Board lanes share the board's width instead of sizing to their cards
  (clinic's three-lane board rendered 2266px wide on a 1280px viewport):
  the lanes sit in a `Row`, each lane `Column` at layout `weight` 1, so
  every renderer that honours weights gives the lanes equal, bounded
  shares. The AshA2ui merged catalog additionally scrolls the lanes
  horizontally inside the board below a minimum lane width
  (`--a2ui-board-lane-min-width`). The browser half is
  `priv/js/probe/adoption_probe.mjs`.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Test.Adoption.{Job, JobBoardUI}

  @red %{id: "u-red", team: "red"}

  setup do
    Job |> Ash.read!(actor: @red) |> Enum.each(&Ash.destroy!(&1, authorize?: false))

    Ash.create!(Job, %{title: "A card title long enough to widen its lane", team: "red"},
      authorize?: false
    )

    :ok
  end

  defp components(ui, opts \\ []) do
    ui
    |> AshA2ui.Info.build_surface(Keyword.put(opts, :actor, @red))
    |> Enum.find_value(& &1["updateComponents"])
    |> Map.fetch!("components")
    |> Map.new(&{&1["id"], &1})
  end

  test "the lanes sit in a Row, each lane at weight 1" do
    messages = AshA2ui.Info.build_surface(JobBoardUI, actor: @red)
    Enum.each(messages, &assert_valid_server_message/1)

    by_id = components(JobBoardUI)
    lanes = by_id["board_board_lanes"]

    assert lanes["component"] == "Row"
    assert lanes["align"] == "start"
    assert lanes["children"] == ["lane_board_open", "lane_board_claimed", "lane_board_done"]

    for lane <- lanes["children"] do
      assert by_id[lane]["component"] == "Column"
      assert by_id[lane]["weight"] == 1
    end
  end

  test "the admin catalog keeps the same lanes" do
    basic = components(JobBoardUI)

    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    admin = components(JobBoardUI)

    assert admin["board_board_lanes"] == basic["board_board_lanes"]
    assert admin["lane_board_open"] == basic["lane_board_open"]
  end
end
