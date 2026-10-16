defmodule AshA2ui.Experience.PaginationVisibilityTest do
  @moduledoc """
  A2UI-101/AC-1..AC-5: experience-layer conditional pagination — the
  `_pagination_visible` / `_previous_visible` / `_next_visible` sentinels
  and the `_range_text` result range, plus the data-driven empty state.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.Experience
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Experience.Task

  defp seed!(count) do
    for i <- 1..count do
      Ash.create!(Task, %{name: "Item #{:erlang.unique_integer([:positive])}-#{i}"},
        authorize?: false
      )
    end
  end

  defp data_model!(build_fun) do
    case build_fun.() do
      %{"updateDataModel" => %{"value" => model}} -> model
      [_create, _components, %{"updateDataModel" => %{"value" => model}}] -> model
    end
  end

  defp components_by_id(components_message) do
    Map.new(components_message["updateComponents"]["components"], &{&1["id"], &1})
  end

  describe "empty result sets" do
    @tag ac: "A2UI-101/AC-1"
    test "zero records hide pagination and show empty state" do
      [create, components, data] = AshA2ui.Info.build_surface(Task)
      model = data_model!(fn -> [create, components, data] end)
      query = model["query"]

      # the pagination sentinel is empty: nothing prev/next/page is visible
      assert query["_pagination_visible"] == []
      assert query["_previous_visible"] == []
      assert query["_next_visible"] == []
      assert query["_range_text"] == ""

      # the empty state is on, with its message
      assert model["_empty_visible"] != []
      assert model["_empty_message"] == "No Task records yet."

      # the tree binds accordingly
      comps = components_by_id(components)

      assert %{"children" => %{"componentId" => "empty_state_text", "path" => "/_empty_visible"}} =
               comps["empty_state"]

      assert %{"children" => %{"path" => "/query/_pagination_visible"}} =
               comps["query_pagination"]

      assert %{"text" => %{"path" => "/query/_range_text"}} = comps["query_page_text"]
    end
  end

  describe "single page" do
    @tag ac: "A2UI-101/AC-2"
    test "single page hides pagination entirely" do
      seed!(2)

      model =
        data_model!(fn -> AshA2ui.Info.build_surface(Task, actor: nil) end)

      query = model["query"]

      assert query["_pagination_visible"] == []
      assert query["_previous_visible"] == []
      assert query["_next_visible"] == []

      # records exist, so the empty state is off
      assert model["_empty_visible"] == []
    end
  end

  describe "overflow" do
    @tag ac: "A2UI-101/AC-3"
    test "overflow page shows next without previous" do
      records = seed!(3)

      # Page 1 loaded through the query pipeline with the count probe
      # withheld (totalCount nil): the range renders "Showing" style.
      state = %{
        "search" => "",
        "filters" => %{},
        "sort" => nil,
        "page" => 1,
        "pageSize" => 2,
        "totalCount" => nil,
        "hasMore" => true
      }

      view = Task |> ResolvedView.resolve()

      model =
        data_model!(fn ->
          V0_9_1.encode_data_model(view, Enum.take(records, 2), query_state: state)
        end)

      query = model["query"]

      assert query["_next_visible"] != []
      assert query["_previous_visible"] == []
      assert query["_pagination_visible"] != []
      assert query["_range_text"] == "Showing 1–2"
    end
  end

  describe "last page" do
    @tag ac: "A2UI-101/AC-4"
    test "last page shows previous without next" do
      seed!(3)

      model =
        data_model!(fn ->
          AshA2ui.Info.build_data_model(Task, query_state: %{"page" => 2})
        end)

      query = model["query"]

      assert query["_pagination_visible"] != []
      assert query["_previous_visible"] != []
      assert query["_next_visible"] == []

      # the previous affordance survives a sparse current page (1 record)
      assert length(model["records"]) == 1
    end
  end

  describe "known total" do
    @tag ac: "A2UI-101/AC-5"
    test "known total renders of form" do
      state =
        Experience.pagination_state(%{
          "page" => 2,
          "pageSize" => 5,
          "hasMore" => false,
          "totalCount" => 42
        })

      assert state.range_text == "6–10 of 42"

      # and through a natural surface build
      seed!(3)

      model = data_model!(fn -> AshA2ui.Info.build_data_model(Task, actor: nil) end)

      assert model["query"]["_range_text"] == "1–2 of 3"
    end
  end
end
