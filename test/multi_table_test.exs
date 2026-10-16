defmodule AshA2ui.MultiTableTest do
  @moduledoc """
  Multiple named table components: the scoped data model
  (`/records/<component_name>`, `/query/<component_name>`), per-table
  component ids/contexts, per-action `refreshes` metadata, and the
  multi-table `query` action.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.ReviewItem

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "review",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp paths(messages), do: Enum.map(messages, & &1["updateDataModel"]["path"])

  defp components_by_id(messages) do
    messages
    |> Enum.find_value(& &1["updateComponents"])
    |> Map.fetch!("components")
    |> Map.new(&{&1["id"], &1})
  end

  defp create_item!(name, opts \\ []) do
    Ash.create!(
      ReviewItem,
      %{name: name, state: opts[:state] || :new, count: opts[:count] || 0},
      authorize?: false
    )
  end

  describe "resolution" do
    test "each table component resolves to a scoped table with frozen paths" do
      view = ResolvedView.resolve(ReviewItem)

      assert ResolvedView.multi_table?(view)
      assert [new_items, done_items] = view.tables

      assert new_items.name == :new_items
      assert new_items.read_action == :new_items
      assert new_items.records_path == "/records/new_items"
      assert new_items.query_path == "/query/new_items"
      assert new_items.query.name == :new_q
      assert new_items.row_actions == [:approve, :destroy]

      assert done_items.name == :done_items
      assert done_items.records_path == "/records/done_items"
      assert done_items.query_path == nil
      assert done_items.query == nil
    end

    test "legacy single-table fields are nil/unions on multi-table surfaces" do
      view = ResolvedView.resolve(ReviewItem)

      assert view.read_action == nil
      assert view.query == nil
      assert view.row_actions == [:approve, :destroy]
    end

    test "refreshes metadata maps action names to table components" do
      view = ResolvedView.resolve(ReviewItem)

      assert view.refreshes == %{approve: [:new_items]}
    end

    test "single-table views keep the unscoped paths" do
      view = ResolvedView.resolve(AshA2ui.Test.Paginated)

      refute ResolvedView.multi_table?(view)
      assert [table] = view.tables
      assert table.name == :table
      assert table.records_path == "/records"
      assert table.query_path == "/query"
    end
  end

  describe "encoder: component tree" do
    setup do
      messages = AshA2ui.Info.build_surface(ReviewItem)
      Enum.each(messages, &assert_valid_server_message/1)
      %{messages: messages, components: components_by_id(messages)}
    end

    test "root interleaves per-table sections in declaration order", %{components: components} do
      assert components["root"]["children"] == [
               "form_slot",
               "status_text",
               "table_heading_new_items",
               "query_new_items_controls",
               "create_new_items_button",
               "records_list_new_items",
               "empty_state_new_items",
               "query_new_items_pagination",
               "table_heading_done_items",
               "create_done_items_button",
               "records_list_done_items",
               "empty_state_done_items",
               "action_result_panel"
             ]
    end

    test "each table renders its own suffixed list, row, and cells", %{components: components} do
      assert %{
               "children" => %{
                 "componentId" => "record_row_new_items",
                 "path" => "/records/new_items"
               }
             } =
               components["records_list_new_items"]

      assert %{
               "children" => %{
                 "componentId" => "record_row_done_items",
                 "path" => "/records/done_items"
               }
             } =
               components["records_list_done_items"]

      assert components["record_row_new_items"] == %{
               "id" => "record_row_new_items",
               "component" => "Card",
               "child" => "record_row_new_items_content"
             }

      assert components["record_row_new_items_content"]["children"] == [
               "table_cell_new_items_name",
               "table_cell_new_items_count",
               "row_action_new_items_approve_button",
               "row_action_new_items_destroy_button",
               "view_new_items_button",
               "edit_new_items_button"
             ]

      assert components["table_cell_done_items_state_value"]["text"] == %{"path" => "state"}
    end

    test "headings show the humanized component names", %{components: components} do
      assert components["table_heading_new_items"]["text"] == "New items"
      assert components["table_heading_done_items"]["text"] == "Done items"
    end

    test "row action buttons carry component + the whole /query binding", %{
      components: components
    } do
      assert %{
               "action" => %{
                 "event" => %{
                   "name" => "invoke",
                   "context" => %{
                     "action" => "approve",
                     "recordId" => %{"path" => "id"},
                     "component" => "new_items",
                     "query" => %{"path" => "/query"}
                   }
                 }
               }
             } = components["row_action_new_items_approve_button"]
    end

    test "query controls are scoped to the table's query path", %{components: components} do
      assert %{"value" => %{"path" => "/query/new_items/search"}} =
               components["query_new_items_search_input"]

      assert %{
               "action" => %{
                 "event" => %{
                   "name" => "query",
                   "context" => %{
                     "query" => %{"path" => "/query/new_items"},
                     "component" => "new_items",
                     "page" => 1
                   }
                 }
               }
             } = components["query_new_items_apply_button"]

      assert %{"text" => %{"path" => "/query/new_items/_range_text"}} =
               components["query_new_items_page_text"]

      # the query-less table gets no controls
      refute Map.has_key?(components, "query_done_items_controls")
    end
  end

  describe "encoder: data model" do
    test "records and query are objects keyed by table component name" do
      create_item!("Fresh")
      create_item!("Old", state: :done)

      messages = AshA2ui.Info.build_surface(ReviewItem)
      Enum.each(messages, &assert_valid_server_message/1)

      data = value_at(messages, "/")

      assert [%{"name" => "Fresh", "count" => 0}] = data["records"]["new_items"]
      assert [%{"name" => "Old", "state" => "Done"}] = data["records"]["done_items"]

      assert %{"new_items" => %{"page" => 1, "totalCount" => 1}} = data["query"]
      refute Map.has_key?(data["query"], "done_items")
    end

    test "build_data_model covers all tables" do
      create_item!("Fresh")
      create_item!("Old", state: :done)

      message = AshA2ui.Info.build_data_model(ReviewItem)
      assert_valid_server_message(message)

      data = message["updateDataModel"]["value"]
      assert [%{"name" => "Fresh"}] = data["records"]["new_items"]
      assert [%{"name" => "Old"}] = data["records"]["done_items"]
    end
  end

  describe "action handler: refreshes" do
    test "an action with refreshes metadata refreshes only the named tables" do
      item = create_item!("Fresh")
      create_item!("Old", state: :done)

      env = envelope("invoke", %{"action" => "approve", "recordId" => item.id})
      assert_valid_client_message(env)

      assert {:ok, messages} = ActionHandler.handle(ReviewItem, env)
      Enum.each(messages, &assert_valid_server_message/1)

      # the update-type row action ran the :approve action itself
      assert Ash.get!(ReviewItem, item.id, authorize?: false).state == :done

      # only the declared table refreshed — done_items is (intentionally) stale
      assert value_at(messages, "/records/new_items") == []
      assert "/query/new_items" in paths(messages)
      refute "/records/done_items" in paths(messages)

      # the standard form/errors/ui follow-ups are unaffected by refreshes
      assert value_at(messages, "/form") == %{}
      assert value_at(messages, "/errors") == %{}
      assert value_at(messages, "/ui/feedback")["message"] =~ "approve"
    end

    test "an action without refreshes metadata refreshes every table" do
      item = create_item!("Doomed")
      create_item!("Old", state: :done)

      env = envelope("invoke", %{"action" => "destroy", "recordId" => item.id})

      assert {:ok, messages} = ActionHandler.handle(ReviewItem, env)
      Enum.each(messages, &assert_valid_server_message/1)

      assert value_at(messages, "/records/new_items") == []
      assert [%{"name" => "Old"}] = value_at(messages, "/records/done_items")
      assert "/query/new_items" in paths(messages)
    end

    test "submit_form success refreshes every table by default" do
      env = envelope("submit_form", %{"values" => %{"name" => "Created", "count" => 1}})

      assert {:ok, messages} = ActionHandler.handle(ReviewItem, env)
      Enum.each(messages, &assert_valid_server_message/1)

      assert [%{"name" => "Created", "count" => 1}] = value_at(messages, "/records/new_items")
      assert value_at(messages, "/records/done_items") == []
    end

    test "a carried per-table query state scopes the refresh of its table" do
      item = create_item!("Match me")
      create_item!("Other")

      env =
        envelope("invoke", %{
          "action" => "destroy",
          "recordId" => item.id,
          "component" => "new_items",
          "query" => %{"new_items" => %{"search" => "Other"}}
        })

      assert {:ok, messages} = ActionHandler.handle(ReviewItem, env)

      assert [%{"name" => "Other"}] = value_at(messages, "/records/new_items")
      assert value_at(messages, "/query/new_items")["search"] == "Other"
    end
  end

  describe "action handler: query" do
    test "a query action targets the table named by component" do
      create_item!("Beta")
      create_item!("Alpha")

      env =
        envelope("query", %{
          "component" => "new_items",
          "query" => %{"search" => "Alpha"}
        })

      assert {:ok, messages} = ActionHandler.handle(ReviewItem, env)
      Enum.each(messages, &assert_valid_server_message/1)

      assert paths(messages) == [
               "/records/new_items",
               "/_empty_visible_new_items",
               "/query/new_items"
             ]

      assert [%{"name" => "Alpha"}] = value_at(messages, "/records/new_items")
    end

    test "a query action without component is rejected on multi-table surfaces" do
      env = envelope("query", %{"query" => %{"search" => "x"}})

      assert {:error, messages} = ActionHandler.handle(ReviewItem, env)
      assert value_at(messages, "/ui/feedback")["message"] =~ ~s(require "component")
    end

    test "a query action naming an unknown component is rejected" do
      env = envelope("query", %{"component" => "nope", "query" => %{}})

      assert {:error, messages} = ActionHandler.handle(ReviewItem, env)
      assert value_at(messages, "/ui/feedback")["message"] =~ "Unknown table component"
    end

    test "a query action targeting a table without a query is rejected" do
      env = envelope("query", %{"component" => "done_items", "query" => %{}})

      assert {:error, messages} = ActionHandler.handle(ReviewItem, env)
      assert value_at(messages, "/ui/feedback")["message"] =~ "No query is configured"
    end
  end
end
