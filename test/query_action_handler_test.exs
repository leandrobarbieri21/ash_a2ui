defmodule AshA2ui.QueryActionHandlerTest do
  @moduledoc """
  `AshA2ui.ActionHandler` tests for the `"query"` client action and the
  query-aware success refreshes of `submit_form`/`invoke`. Pins the frozen
  wire contract: context `{"query" => <the /query map>}` (plus optional
  `"page"`/`"pageDelta"`), follow-ups on `/records` and `/query`, and
  allowlist rejections on `/ui/feedback` that never reach Ash.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Paginated

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "paginated",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp seed!(count, attrs_fn) do
    for i <- 1..count do
      Ash.create!(Paginated, attrs_fn.(i), authorize?: false)
    end
  end

  defp by_path(messages) do
    Map.new(messages, fn %{"updateDataModel" => %{"path" => path, "value" => value}} ->
      {path, value}
    end)
  end

  describe "the query action" do
    test "returns schema-valid /records and /query follow-ups" do
      seed!(7, &%{name: "Item #{&1}", status: :open})

      envelope = envelope("query", %{"query" => %{"search" => "item"}})
      assert_valid_client_message(envelope)

      assert {:ok, messages} = ActionHandler.handle(Paginated, envelope, actor: nil)
      Enum.each(messages, &assert_valid_server_message/1)

      values = by_path(messages)

      assert [%{"name" => "Item 1"} | _] = values["/records"]
      assert length(values["/records"]) == 5

      assert %{
               "search" => "item",
               "page" => 1,
               "pageSize" => 5,
               "totalCount" => 7,
               "hasMore" => true
             } = values["/query"]
    end

    test "pageDelta pages forward from the submitted query state" do
      seed!(7, &%{name: "Item #{&1}"})

      envelope = envelope("query", %{"query" => %{"page" => 1}, "pageDelta" => 1})

      assert {:ok, messages} = ActionHandler.handle(Paginated, envelope, actor: nil)
      values = by_path(messages)

      assert Enum.map(values["/records"], & &1["name"]) == ["Item 6", "Item 7"]
      assert %{"page" => 2, "hasMore" => false} = values["/query"]
    end

    test "filters narrow the records" do
      seed!(2, &%{name: "Open #{&1}", status: :open})
      seed!(1, &%{name: "Closed #{&1}", status: :closed})

      envelope = envelope("query", %{"query" => %{"filters" => %{"status" => "closed"}}})

      assert {:ok, messages} = ActionHandler.handle(Paginated, envelope, actor: nil)
      values = by_path(messages)

      assert [%{"name" => "Closed 1"}] = values["/records"]
      assert values["/query"]["filters"] == %{"status" => "closed", "category" => ""}
    end

    test "rejects a non-allowlisted sort with a /ui/feedback error and no records" do
      envelope =
        envelope("query", %{"query" => %{"sort" => %{"field" => "status", "dir" => "asc"}}})

      assert {:error, [message]} = ActionHandler.handle(Paginated, envelope, actor: nil)
      assert_valid_server_message(message)

      assert %{"path" => "/ui/feedback", "value" => %{"message" => value}} =
               message["updateDataModel"]

      assert value =~ ~s(Sort field "status" is not allowlisted)
    end

    test "rejects a non-allowlisted filter with a /ui/feedback error" do
      envelope = envelope("query", %{"query" => %{"filters" => %{"name" => "x"}}})

      assert {:error, [message]} = ActionHandler.handle(Paginated, envelope, actor: nil)

      assert %{"path" => "/ui/feedback", "value" => %{"message" => value}} =
               message["updateDataModel"]

      assert value =~ ~s(Filter "name" is not allowlisted)
    end

    test "rejects the query action on a surface without a query" do
      envelope = envelope("query", %{"query" => %{}})

      assert {:error, [message]} =
               ActionHandler.handle(AshA2ui.Test.KitchenSink, envelope, actor: nil)

      assert %{"path" => "/ui/feedback", "value" => %{"message" => value}} =
               message["updateDataModel"]

      assert value =~ ~r/No query is configured/
    end
  end

  describe "query-aware success refreshes" do
    test "submit_form carrying the current /query refreshes within that state" do
      seed!(7, &%{name: "Item #{&1}"})

      context = %{
        "values" => %{"name" => "Zed"},
        "query" => %{"page" => 2}
      }

      assert {:ok, messages} =
               ActionHandler.handle(Paginated, envelope("submit_form", context), actor: nil)

      Enum.each(messages, &assert_valid_server_message/1)
      values = by_path(messages)

      # 8 records after the create; page 2 of 5 sorted by name: Item 6, Item 7, Zed
      assert Enum.map(values["/records"], & &1["name"]) == ["Item 6", "Item 7", "Zed"]
      assert %{"page" => 2, "totalCount" => 8, "hasMore" => false} = values["/query"]
      assert values["/form"] == %{}
      assert values["/ui/feedback"]["message"] == "Created successfully."
    end

    test "submit_form without query context refreshes with the query defaults" do
      seed!(6, &%{name: "Item #{&1}"})

      context = %{"values" => %{"name" => "Aardvark"}}

      assert {:ok, messages} =
               ActionHandler.handle(Paginated, envelope("submit_form", context), actor: nil)

      values = by_path(messages)

      assert [%{"name" => "Aardvark"} | _] = values["/records"]
      assert length(values["/records"]) == 5
      assert %{"page" => 1, "totalCount" => 7, "hasMore" => true} = values["/query"]
    end

    test "an invalid query context on submit_form falls back to defaults (the write still succeeds)" do
      context = %{
        "values" => %{"name" => "Only"},
        "query" => %{"sort" => %{"field" => "status", "dir" => "asc"}}
      }

      assert {:ok, messages} =
               ActionHandler.handle(Paginated, envelope("submit_form", context), actor: nil)

      values = by_path(messages)
      assert [%{"name" => "Only"}] = values["/records"]
      assert %{"page" => 1, "sort" => %{"field" => "name", "dir" => "asc"}} = values["/query"]
    end

    test "invoke success refreshes respect the carried query state" do
      records = seed!(3, &%{name: "Item #{&1}"})
      seed!(1, fn _ -> %{name: "Other"} end)
      victim = List.last(records)

      context = %{
        "action" => "destroy",
        "recordId" => victim.id,
        "query" => %{"search" => "item"}
      }

      assert {:ok, messages} =
               ActionHandler.handle(Paginated, envelope("invoke", context), actor: nil)

      Enum.each(messages, &assert_valid_server_message/1)
      values = by_path(messages)

      # "Other" is filtered out by the carried search; the victim is gone.
      assert Enum.map(values["/records"], & &1["name"]) == ["Item 1", "Item 2"]
      assert %{"search" => "item", "totalCount" => 2} = values["/query"]
    end

    test "surfaces without a query keep the original refresh shape (no /query message)" do
      context = %{"values" => %{"name" => "Plain"}}

      assert {:ok, messages} =
               ActionHandler.handle(AshA2ui.Test.Minimal, envelope("submit_form", context),
                 actor: nil
               )

      paths = Enum.map(messages, & &1["updateDataModel"]["path"])
      refute "/query" in paths
    end
  end
end
