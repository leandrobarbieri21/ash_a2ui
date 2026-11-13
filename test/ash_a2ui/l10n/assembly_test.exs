defmodule AshA2ui.L10n.AssemblyTest do
  @moduledoc """
  Messages assembled from parts are catalog templates, Ash's own error
  messages go through the errors domain, translated text keeps its case,
  and a CSV filename stays an identifier.
  """

  # Shared ETS fixtures and the experience application env.
  use ExUnit.Case, async: false

  import AshA2ui.Test.BulkHelpers

  alias AshA2ui.ActionHandler
  alias AshA2ui.Bulk
  alias AshA2ui.Info
  alias AshA2ui.L10n
  alias AshA2ui.ResolvedView
  alias AshA2ui.Sections
  alias AshA2ui.Test.BoardTaskUI
  alias AshA2ui.Test.BulkTasksUI
  alias AshA2ui.Test.DomainPseudoLocale
  alias AshA2ui.Test.Gettext, as: TestGettext
  alias AshA2ui.Test.HubUI

  @pseudo [gettext_fn: {DomainPseudoLocale, :translate}, locale: "pseudo"]

  test "the bulk status line is assembled from catalog templates" do
    l10n = L10n.new(@pseudo)
    result = %{"ok" => 2, "refused" => 1, "skipped" => 0, "failed" => 2}

    assert Bulk.status_text(:approve, 5, result, nil, l10n) ==
             "⟦⟦⟪Approve⟫: 2 of 5 selected records done⟧; " <>
               "⟦⟦1 refused⟧, ⟦2 failed⟧⟧.⟧"

    assert Bulk.status_text(:approve, 5, %{result | "refused" => 0, "failed" => 0}, nil, l10n) ==
             "⟦⟦⟪Approve⟫: 2 of 5 selected records done⟧.⟧"

    assert Bulk.status_text(:approve, 5, result) ==
             "Approve: 2 of 5 selected records done; 1 refused, 2 failed."
  end

  test "a bulk failure's Ash message is translated in the errors domain" do
    reset!()
    project = project!("Apollo")
    bad = task!("Bravo", %{project_id: project.id, score: -1})

    run = fn opts ->
      {_outcome, messages} =
        ActionHandler.handle(
          BulkTasksUI,
          envelope("bulk_invoke", %{
            "action" => "approve",
            "component" => "table",
            "records" => rows([bad], [bad]),
            "contexts" => contexts(project)
          }),
          [actor: actor()] ++ opts
        )

      %{"errors" => [%{"message" => message}]} = value_at(messages, "/bulk/table/result")
      message
    end

    assert run.([]) == "score: must be greater than or equal to 0"

    fr = [gettext_backend: {TestGettext, "ash_a2ui"}, locale: "fr"]
    assert run.(fr) == "score: doit être supérieur ou égal à 0"

    # The errors domain is the host's to name.
    assert run.(fr ++ [errors_domain: "elsewhere"]) ==
             "score: must be greater than or equal to 0"
  end

  test "a context's select label keeps its own case in one message" do
    json = HubUI |> Info.build_surface(@pseudo) |> Jason.encode!()

    assert json =~ ~s("⟪Select contract⟫")
    refute json =~ "Select ⟪"
  end

  test "a section's CSV filename comes from the untranslated lane heading" do
    export = %{filename: "board.csv"}

    view =
      BoardTaskUI
      |> ResolvedView.resolve(@pseudo)
      |> then(&%{&1 | tables: Enum.map(&1.tables, fn table -> %{table | export: export} end)})

    filenames = fn view ->
      view |> Sections.expand_static() |> Map.fetch!(:tables) |> Enum.map(& &1.export.filename)
    end

    assert filenames.(view) == ["To_do.csv", "Claimed.csv", "Completed.csv"]

    # The heading itself is translated.
    headings =
      view |> Sections.expand_static() |> Map.fetch!(:tables) |> Enum.map(& &1.section.label)

    assert headings == ["⟪To do⟫", "⟪Claimed⟫", "⟪Completed⟫"]
  end
end
