defmodule AshA2ui.Board.BoardEncoderTest do
  @moduledoc """
  Board rendering (A2UI-105): a `display :board` table emits its lanes side
  by side — a horizontal `List` of lane `Column`s, each with its heading and
  total, card list and pagination — on v0.9.1 and v1.0, schema-validated.
  `display :list` output is unchanged: list-mode sectioned surfaces match
  golden payloads captured from the pre-board base commit (08f8173).
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.Bucket
  alias AshA2ui.Test.BucketWord

  @golden_dir Path.expand("golden", __DIR__)

  setup do
    on_exit(fn ->
      Application.delete_env(:ash_a2ui, :experience_version)
      Application.delete_env(:ash_a2ui, :catalog)
    end)

    :ok
  end

  defp create_task!(name, status) do
    Ash.create!(BoardTask, %{name: name, status: status, priority: :high}, authorize?: false)
  end

  defp components_by_id(components), do: Map.new(components, &{&1["id"], &1})

  defp v0_9_1_parts(ui) do
    messages = AshA2ui.Info.build_surface(ui, authorize?: false)
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

  # The golden payloads replace the random ids of the seeded rows with
  # stable tags (dash, underscore and space forms: ids appear raw, in
  # runtime names and in humanized empty-state text).
  defp seed_bucket_words do
    alpha = Ash.create!(Bucket, %{name: "Alpha"}, authorize?: false)
    zebra = Ash.create!(Bucket, %{name: "Zebra"}, authorize?: false)

    apple =
      Ash.create!(BucketWord, %{word: "apple", state: :bucketed, bucket_id: alpha.id},
        authorize?: false
      )

    zeal =
      Ash.create!(BucketWord, %{word: "zeal", state: :bucketed, bucket_id: zebra.id},
        authorize?: false
      )

    fresh = Ash.create!(BucketWord, %{word: "fresh"}, authorize?: false)

    for {id, tag} <- [
          {alpha.id, "BUCKET_ALPHA"},
          {zebra.id, "BUCKET_ZEBRA"},
          {apple.id, "WORD_APPLE"},
          {zeal.id, "WORD_ZEAL"},
          {fresh.id, "WORD_FRESH"}
        ],
        separator <- ["-", "_", " "],
        do: {String.replace(id, "-", separator), tag}
  end

  defp normalized_surface(ui, substitutions) do
    ui
    |> AshA2ui.Info.build_surface(authorize?: false)
    |> Jason.encode!()
    |> then(fn json ->
      Enum.reduce(substitutions, json, fn {id, tag}, acc -> String.replace(acc, id, tag) end)
    end)
  end

  @tag ac: "A2UI-105/AC-4"
  test "encodes lanes side by side" do
    create_task!("alpha", :open)
    create_task!("bravo", :open)
    create_task!("charlie", :open)
    create_task!("delta", :claimed)

    # --- v0.9.1 (experience v2, the default) ---
    {components, value} = v0_9_1_parts(AshA2ui.Test.BoardTaskUI)

    # One root child for the whole board; no per-lane root children.
    assert components["root"]["children"] == ["status_text", "board_board", "action_result_panel"]

    assert components["board_board"] == %{
             "id" => "board_board",
             "component" => "Column",
             "children" => ["board_board_heading", "board_board_lanes"]
           }

    assert components["board_board_heading"]["text"] == "Board"

    # The lanes sit side by side: a horizontal List of lane Columns.
    assert components["board_board_lanes"] == %{
             "id" => "board_board_lanes",
             "component" => "List",
             "direction" => "horizontal",
             "align" => "start",
             "children" => ["lane_board_open", "lane_board_claimed", "lane_board_completed"]
           }

    for {lane, label} <- [
          {"board_open", "To do"},
          {"board_claimed", "Claimed"},
          {"board_completed", "Completed"}
        ] do
      assert components["lane_#{lane}"]["component"] == "Column"

      # heading + total, query controls (the query declares a filter), card
      # list, empty state, pagination
      assert components["lane_#{lane}"]["children"] == [
               "lane_#{lane}_header",
               "query_#{lane}_controls",
               "records_list_#{lane}",
               "empty_state_#{lane}",
               "query_#{lane}_pagination"
             ]

      assert components["lane_#{lane}_header"]["children"] ==
               ["table_heading_#{lane}", "lane_#{lane}_total"]

      assert components["table_heading_#{lane}"]["text"] == label
      assert components["lane_#{lane}_total"]["text"] == %{"path" => "/_lane_total_#{lane}"}

      assert components["records_list_#{lane}"]["children"] == %{
               "componentId" => "record_row_#{lane}",
               "path" => "/records/#{lane}"
             }

      # Cards: the row_layout composition under the lane suffix.
      assert components["record_row_#{lane}"]["component"] == "Card"
      assert components["query_#{lane}_pagination"]["component"] == "List"
      # Lanes never render the stacked list composition's h2 heading.
      assert components["table_heading_#{lane}"]["variant"] == "h3"
    end

    # Totals: the query's totalCount (3 open, though the page holds 2).
    assert value["_lane_total_board_open"] == "3"
    assert value["_lane_total_board_claimed"] == "1"
    assert value["_lane_total_board_completed"] == "0"
    assert length(value["records"]["board_open"]) == 2
    assert value["query"]["board_open"]["_pagination_visible"] == [%{"id" => "on"}]

    # --- v0.9.1, experience v1 (the pinned legacy emission) ---
    Application.put_env(:ash_a2ui, :experience_version, 1)
    {legacy, legacy_value} = v0_9_1_parts(AshA2ui.Test.BoardTaskUI)

    assert legacy["root"]["children"] == ["board_board", "status_text", "action_result_panel"]

    assert legacy["lane_board_open"]["children"] == [
             "lane_board_open_header",
             "query_board_open_controls",
             "records_list_board_open",
             "query_board_open_pagination"
           ]

    assert legacy_value["_lane_total_board_open"] == "3"
    Application.delete_env(:ash_a2ui, :experience_version)

    # --- v1.0 (no query: totals from the row count, no pagination) ---
    assert [message] = AshA2ui.Info.build_surface(AshA2ui.Test.BoardTaskV1UI, authorize?: false)
    assert_valid_server_message(message, :v1_0)

    create = message["createSurface"]
    v1 = components_by_id(create["components"])

    assert v1["board_board_lanes"]["direction"] == "horizontal"
    assert v1["board_board_lanes"]["children"] == ["lane_board_open", "lane_board_claimed"]
    # v1.0 headings are Markdown (the h1-h5 Text variants were dropped).
    assert v1["table_heading_board_open"]["text"] == "### Open"
    assert v1["board_board_heading"]["text"] == "## Board"

    assert v1["lane_board_open"]["children"] == [
             "lane_board_open_header",
             "records_list_board_open",
             "empty_state_board_open"
           ]

    assert create["dataModel"]["_lane_total_board_open"] == "3"
    assert create["dataModel"]["_lane_total_board_claimed"] == "1"

    # --- the admin catalog falls back to the basic board composition ---
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    admin_messages = AshA2ui.Info.build_surface(AshA2ui.Test.BoardTaskUI, authorize?: false)

    admin =
      admin_messages
      |> Enum.find_value(& &1["updateComponents"])
      |> Map.fetch!("components")
      |> components_by_id()

    assert admin["root"]["component"] == "entityPage"
    assert "board_board" in admin["root"]["children"]
    assert admin["board_board_lanes"] == components["board_board_lanes"]
    assert admin["lane_board_open"] == components["lane_board_open"]
    Application.delete_env(:ash_a2ui, :catalog)

    # --- display :list output is unchanged ---
    # List-mode sectioned surfaces encode exactly as on the pre-board base.
    substitutions = seed_bucket_words()

    for {experience, prefix} <- [{1, "exp1"}, {2, "exp2"}],
        {ui, file} <- [
          {AshA2ui.Test.BucketWordsUI, "bucket_words_ui"},
          {AshA2ui.Test.BucketWordsV1UI, "bucket_words_v1_ui"}
        ] do
      Application.put_env(:ash_a2ui, :experience_version, experience)

      golden = @golden_dir |> Path.join("#{prefix}_#{file}.json") |> File.read!()

      assert Jason.decode!(normalized_surface(ui, substitutions)) == Jason.decode!(golden),
             "#{inspect(ui)} (experience v#{experience}) differs from its base golden"
    end
  end
end
