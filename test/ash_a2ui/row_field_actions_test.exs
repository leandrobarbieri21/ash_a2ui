defmodule AshA2ui.RowFieldActionsTest do
  @moduledoc """
  Admin catalog 3.9: a field action on a field a table draws is a button in
  each row (the dataGrid column's `action`, gated per row by
  `actionVisible`), run through the `field_action` ashAction on the row's
  record, re-read through the table's own scoped read. A review summary
  counts each row of a table filtered by its context alone that still has
  a review waiting, once.
  """

  # Not async: the catalog is application config.
  use ExUnit.Case, async: false

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Dossier, DossierLine, DossierLinesReviewUI, Messages, SchemaHelper}

  @pending %{state: :pending, page: 2}
  @reviewed %{state: :reviewed, page: 2}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(Dossier)
      Ets.stop(DossierLine)
    end)

    dossier =
      Ash.create!(Dossier, %{name: "Harbour lease", name_review: @reviewed}, authorize?: false)

    other = Ash.create!(Dossier, %{name: "Elsewhere"}, authorize?: false)

    line = fn dossier, position, reviews ->
      Ash.create!(
        DossierLine,
        Map.merge(
          %{dossier_id: dossier.id, label: "Line #{position}", position: position, amount: 10},
          reviews
        ),
        authorize?: false
      )
    end

    first = line.(dossier, 1, %{amount_review: @pending, period_review: @pending})
    second = line.(dossier, 2, %{amount_review: @reviewed, period_review: @pending})
    done = line.(dossier, 3, %{amount_review: @reviewed})
    by_hand = line.(dossier, 4, %{})
    foreign = line.(other, 1, %{amount_review: @pending})

    %{
      dossier: dossier,
      other: other,
      first: first,
      second: second,
      done: done,
      by_hand: by_hand,
      foreign: foreign
    }
  end

  defp contexts(dossier), do: %{"dossier" => %{"value" => dossier.id, "label" => dossier.name}}

  defp surface(dossier) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(DossierLinesReviewUI,
        authorize?: false,
        context_state: %{"dossier" => %{"search" => "", "value" => dossier.id, "label" => "x"}}
      )

    SchemaHelper.assert_valid_agent_message(message, catalogs: SchemaHelper.admin_catalogs())

    grid = Enum.find(surface["components"], &(&1["component"] == "dataGrid"))
    "/" <> path = grid["rows"]["@path"]
    rows = get_in(surface["dataModel"], String.split(path, "/"))

    %{
      columns: Map.new(grid["columns"], &{&1["path"], &1}),
      rows: Map.new(rows, &{&1["id"], &1}),
      summary: surface["dataModel"]["detail"]["dossier"]["_review_summary_to_review"]
    }
  end

  defp field_action(dossier, record_id, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    context = %{
      "component" => Keyword.get(opts, :component, "lines"),
      "field" => Keyword.get(opts, :field, "amount"),
      "recordId" => record_id,
      "contexts" => contexts(dossier)
    }

    ActionHandler.handle(
      DossierLinesReviewUI,
      Messages.call("field_action", "dossier_lines_review", context),
      authorize?: false
    )
  end

  defp reviewed_count(line), do: Ash.get!(DossierLine, line.id, authorize?: false).reviewed_count

  describe "the wire" do
    test "the column carries the button, its context bound to the row", %{dossier: dossier} do
      %{columns: columns} = surface(dossier)

      assert columns["amount"]["action"] == %{
               "label" => "Mark as reviewed",
               "icon" => "check",
               "action" => "field_action",
               "context" => %{
                 "component" => "lines",
                 "field" => "amount",
                 "recordId" => %{"@path" => "id"},
                 "query" => %{"@path" => "/query"},
                 "contexts" => %{"@path" => "/context"}
               }
             }

      assert columns["amount"]["actionVisible"] == %{"path" => "_action_amount"}
      refute Map.has_key?(columns["label"], "action")
      refute Map.has_key?(columns["period"], "actionVisible")
    end

    test "each row says whether it offers the action",
         %{dossier: dossier, first: first, done: done, by_hand: by_hand} do
      %{rows: rows} = surface(dossier)

      assert rows[first.id]["_action_amount"] == true
      assert rows[done.id]["_action_amount"] == false
      assert rows[by_hand.id]["_action_amount"] == false
      refute Map.has_key?(rows[first.id], "_action_label")
    end
  end

  describe "field_action on a row" do
    test "runs the action on the row (no :field argument), refreshes the table and the context's record",
         %{dossier: dossier, first: first} do
      assert {:ok, messages} = field_action(dossier, first.id)
      assert reviewed_count(first) == 1

      refreshed =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/records", "value" => rows}} -> rows
          _other -> nil
        end)

      row = Enum.find(refreshed, &(&1["id"] == first.id))
      assert row["_action_amount"] == false
      assert row["_review_amount"]["state"] == "reviewed"

      detail =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/detail/dossier", "value" => value}} -> value
          _other -> nil
        end)

      # the summary counts what still waits: the second line only
      assert detail["_review_summary_to_review"]["count"] == 1
      assert Messages.response(messages)["value"]["kind"] == "success"
    end

    test "is refused on a row that does not offer it", %{dossier: dossier, done: done} do
      assert {:error, messages} = field_action(dossier, done.id)
      assert Messages.response(messages)["error"]
      assert reviewed_count(done) == 0
    end

    test "is refused on a row outside the table's scope", %{dossier: dossier, foreign: foreign} do
      assert {:error, _messages} = field_action(dossier, foreign.id)
      assert reviewed_count(foreign) == 0
    end

    test "only a field the table declares one for", %{dossier: dossier, first: first} do
      assert {:error, _messages} = field_action(dossier, first.id, field: "label")
      assert {:error, _messages} = field_action(dossier, first.id, component: "facts")
      assert {:error, _messages} = field_action(dossier, "")
      assert reviewed_count(first) == 0
    end
  end

  describe "review summaries over rows" do
    test "count each waiting row once, after the cards' fields, and link to the table's section",
         %{dossier: dossier} do
      # name reviewed; lines 1 and 2 wait (line 1 on two fields), 3 and 4 do
      # not; the first row's first waiting field, in column order, names it
      %{summary: summary} = surface(dossier)

      assert summary == %{
               "count" => 2,
               "field" => "period",
               "href" => "#lines",
               "label" => "Go to the first field to check"
             }
    end

    test "a waiting card field comes first", %{dossier: dossier} do
      waiting = Ash.update!(dossier, %{name_review: @pending}, authorize?: false)
      %{summary: summary} = surface(waiting)

      assert summary["count"] == 3
      assert summary["field"] == "name"
      assert summary["href"] == "#facts"
    end

    test "with every row reviewed, the fallback", %{
      dossier: dossier,
      first: first,
      second: second
    } do
      for line <- [first, second] do
        Ash.update!(line, %{}, action: :mark_reviewed, authorize?: false)
      end

      %{summary: summary} = surface(dossier)
      assert summary["count"] == 0
      assert summary["href"] == "#history"
    end
  end
end
