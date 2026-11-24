defmodule AshA2ui.SaveBarRowsTest do
  @moduledoc """
  Admin catalog 3.16: a save bar counts the rows of its context's tables
  still waiting for review, as a review summary counts them. The bar's
  record carries `_review_rows`, `%{"waiting" => n}`, refreshed with the
  record, so checking a row's ✓ counts down and the bar stays while any
  row waits.
  """

  # Not async: the catalog is application config.
  use ExUnit.Case, async: false

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Dossier, DossierLine, DossierLinesReviewUI, DossierLinesSaveBarUI}
  alias AshA2ui.Test.{Messages, SchemaHelper}

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

    # line 1 waits on two fields (counted once), line 2 on one; 3 and 4 do not
    first = line.(dossier, 1, %{amount_review: @pending, period_review: @pending})
    second = line.(dossier, 2, %{amount_review: @pending})
    line.(dossier, 3, %{amount_review: @reviewed})
    line.(dossier, 4, %{})
    # another dossier's line never counts
    line.(other, 1, %{amount_review: @pending})

    %{dossier: dossier, first: first, second: second}
  end

  defp detail(ui, dossier) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(ui,
        authorize?: false,
        context_state: %{"dossier" => %{"search" => "", "value" => dossier.id, "label" => "x"}}
      )

    SchemaHelper.assert_valid_agent_message(message, catalogs: SchemaHelper.admin_catalogs())
    surface["dataModel"]["detail"]["dossier"]
  end

  defp check_line(dossier, line) do
    context = %{
      "component" => "lines",
      "field" => "amount",
      "recordId" => line.id,
      "contexts" => %{"dossier" => %{"value" => dossier.id, "label" => dossier.name}}
    }

    {:ok, messages} =
      ActionHandler.handle(
        DossierLinesSaveBarUI,
        Messages.call("field_action", "dossier_lines_save_bar", context),
        authorize?: false
      )

    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/detail/dossier", "value" => value}} -> value
      _other -> nil
    end)
  end

  test "the bar's record carries the rows still waiting, each row once", %{dossier: dossier} do
    record = detail(DossierLinesSaveBarUI, dossier)

    # line 3 is reviewed; line 4 has no review, so it counts nowhere
    assert record[AshA2ui.SaveBar.rows_key()] == %{"waiting" => 2, "reviewed" => 1}
    # the card's field is the bar's own to count, with the unsaved changes
    assert record["_review_name"]["state"] == "reviewed"
  end

  test "the count agrees with the review summary's rows", %{dossier: dossier} do
    waiting = Ash.update!(dossier, %{name_review: @pending}, authorize?: false)

    # the summary counts the name and the two lines; the bar, the two lines
    # beside the name it reads itself
    assert detail(DossierLinesReviewUI, waiting)["_review_summary_to_review"]["count"] == 3
    assert detail(DossierLinesSaveBarUI, waiting)["_review_rows"]["waiting"] == 2
  end

  test "checking a line counts down with the record's refresh, to zero", %{
    dossier: dossier,
    first: first,
    second: second
  } do
    assert check_line(dossier, first)["_review_rows"] == %{"waiting" => 1, "reviewed" => 2}
    assert check_line(dossier, second)["_review_rows"] == %{"waiting" => 0, "reviewed" => 3}
  end

  test "a row waiting on one field and reviewed on another still waits", %{dossier: dossier} do
    # line 1: amount reviewed, period still pending
    [first | _] =
      DossierLine |> Ash.Query.sort(position: :asc) |> Ash.read!(authorize?: false)

    Ash.update!(first, %{amount_review: @reviewed}, authorize?: false)

    assert detail(DossierLinesSaveBarUI, dossier)["_review_rows"] == %{
             "waiting" => 2,
             "reviewed" => 1
           }
  end

  test "a surface with no save bar on the context carries no rows count", %{dossier: dossier} do
    refute Map.has_key?(detail(DossierLinesReviewUI, dossier), "_review_rows")
  end
end
