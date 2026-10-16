defmodule AshA2ui.CalculationAggregateTest.ArticleUI do
  @moduledoc false
  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Article
    surface_id "articles_plain"

    component :table do
      fields [:title, :display_title, :shout_title, :comment_count]
      read_action :read
      row_actions [:destroy]
    end

    component :form do
      fields [:title, :status]
      create_action :create
      update_action :update
    end
  end
end

defmodule AshA2ui.CalculationAggregateTest do
  @moduledoc """
  Calculation & aggregate columns: record loading (`Ash.Query.load` on every
  read path), JSON-safe serialization, label/widget defaults, and query
  sorting on sortable calculations/aggregates.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.CalculationAggregateTest.ArticleUI
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{Article, Comment}

  defp envelope(name, surface_id, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => surface_id,
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

  defp create_article!(title, opts \\ []) do
    article =
      Ash.create!(Article, %{title: title, status: opts[:status] || :draft}, authorize?: false)

    comments = Keyword.get(opts, :comments, 0)

    if comments > 0 do
      for _ <- 1..comments do
        Ash.create!(Comment, %{body: "c", article_id: article.id}, authorize?: false)
      end
    end

    article
  end

  describe "resolution" do
    test "calc/aggregate fields get humanized labels and a default widget" do
      view = ResolvedView.resolve(ArticleUI)

      assert view.fields[:display_title].label == "Display title"
      assert view.fields[:comment_count].label == "Comment count"
      # calculations use their declared type; aggregates fall back
      assert view.fields[:display_title].widget == :text_field
      assert view.fields[:comment_count].widget == :text_field
    end

    test "loads covers every calculation and aggregate field of the table" do
      view = ResolvedView.resolve(ArticleUI)

      assert Enum.sort(view.loads) == [:comment_count, :display_title, :shout_title]
    end
  end

  describe "record loading & serialization" do
    test "build_surface loads and serializes calculation and aggregate columns" do
      create_article!("Alpha", comments: 2)

      messages = AshA2ui.Info.build_surface(ArticleUI)
      Enum.each(messages, &assert_valid_server_message/1)

      assert [row] = value_at(messages, "/")["records"]

      assert row["title"] == "Alpha"
      assert row["display_title"] == "Alpha (draft)"
      assert row["shout_title"] == "ALPHA"
      assert row["comment_count"] == 2
    end

    test "build_surface through a query loads calc/aggregate columns too" do
      create_article!("Beta", comments: 1, status: :published)

      messages = AshA2ui.Info.build_surface(Article)
      Enum.each(messages, &assert_valid_server_message/1)

      assert [row] = value_at(messages, "/")["records"]

      assert row["display_title"] == "Beta (published)"
      assert row["comment_count"] == 1
    end

    test "build_data_model refreshes include calc/aggregate values" do
      create_article!("Gamma", comments: 3)

      message = AshA2ui.Info.build_data_model(ArticleUI)
      assert_valid_server_message(message)

      assert [row] = message["updateDataModel"]["value"]["records"]
      assert row["comment_count"] == 3
      assert row["display_title"] == "Gamma (draft)"
    end
  end

  describe "action follow-up re-reads" do
    test "submit_form success refresh serializes calc/aggregate columns (plain read)" do
      env =
        envelope("submit_form", "articles_plain", %{"values" => %{"title" => "Delta"}})

      assert {:ok, messages} = ActionHandler.handle(ArticleUI, env)
      Enum.each(messages, &assert_valid_server_message/1)

      assert [row] = value_at(messages, "/records")
      assert row["display_title"] == "Delta (draft)"
      assert row["shout_title"] == "DELTA"
      assert row["comment_count"] == 0
    end

    test "invoke success refresh serializes calc/aggregate columns (query read)" do
      doomed = create_article!("Doomed", comments: 1)
      create_article!("Stays", comments: 2)

      env =
        envelope("invoke", "articles", %{"action" => "destroy", "recordId" => doomed.id})

      assert {:ok, messages} = ActionHandler.handle(Article, env)
      Enum.each(messages, &assert_valid_server_message/1)

      assert [row] = value_at(messages, "/records")
      assert row["title"] == "Stays"
      assert row["comment_count"] == 2
    end
  end

  describe "query sorting on calculations and aggregates" do
    test "sorts by an aggregate" do
      create_article!("One", comments: 1)
      create_article!("Three", comments: 3)
      create_article!("Zero")

      env =
        envelope("query", "articles", %{
          "query" => %{"sort" => %{"field" => "comment_count", "dir" => "desc"}}
        })

      assert {:ok, messages} = ActionHandler.handle(Article, env)
      Enum.each(messages, &assert_valid_server_message/1)

      counts = messages |> value_at("/records") |> Enum.map(& &1["comment_count"])
      assert counts == [3, 1, 0]

      assert value_at(messages, "/query")["sort"] == %{
               "field" => "comment_count",
               "dir" => "desc"
             }
    end

    test "sorts by an expression calculation" do
      create_article!("Bravo")
      create_article!("Alpha")

      env =
        envelope("query", "articles", %{
          "query" => %{"sort" => %{"field" => "display_title", "dir" => "desc"}}
        })

      assert {:ok, messages} = ActionHandler.handle(Article, env)

      titles = messages |> value_at("/records") |> Enum.map(& &1["title"])
      assert titles == ["Bravo", "Alpha"]
    end

    test "rejects sorting by a field outside the allowlist (module calc not sortable)" do
      env =
        envelope("query", "articles", %{
          "query" => %{"sort" => %{"field" => "shout_title", "dir" => "asc"}}
        })

      assert {:error, messages} = ActionHandler.handle(Article, env)
      assert value_at(messages, "/ui/feedback")["message"] =~ "not allowlisted"
    end
  end
end
