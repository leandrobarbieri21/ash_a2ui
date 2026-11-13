defmodule AshA2ui.L10n.ReviewFindingsTest do
  @moduledoc """
  Regression tests for the review of the localization work: each one
  reproduced a defect before its fix.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic
  alias AshA2ui.Gettext.Metadata
  alias AshA2ui.Info
  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.BoardTaskUI
  alias AshA2ui.Test.BucketWordsUI
  alias AshA2ui.Test.DomainPseudoLocale
  alias AshA2ui.Test.Experience.Task
  alias AshA2ui.Test.Gettext, as: TestGettext
  alias AshA2ui.Test.HubUI
  alias AshA2ui.Test.L10nScenarios
  alias AshA2ui.Test.LabelledReportUI
  alias AshA2ui.Test.Messages
  alias AshA2ui.Test.Minimal
  alias AshA2ui.Test.MinimalUI
  alias AshA2ui.Test.StringBadgeUI

  @pseudo [gettext_fn: {DomainPseudoLocale, :translate}, locale: "pseudo"]
  @fr [gettext_backend: {TestGettext, "ash_a2ui"}, locale: "fr"]

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :catalog) end)
  end

  defp envelope(name, context) do
    Messages.call(name, "experience_task", context)
  end

  defp error_for(messages, field) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/errors/" <> ^field, "value" => value}} -> value
      _other -> nil
    end)
  end

  test "Ash's catalog is looked up in the \"errors\" domain by default" do
    {_outcome, messages} =
      ActionHandler.handle(
        Task,
        envelope("submit_form", %{"values" => %{"name" => ""}}),
        @fr
      )

    assert error_for(messages, "name") == "est obligatoire"
  end

  test "a required field's error is translated by Ash's own msgid" do
    {_outcome, messages} =
      ActionHandler.handle(
        Task,
        envelope("submit_form", %{"values" => %{"name" => ""}}),
        @pseudo
      )

    assert error_for(messages, "name") == "⟨is required⟩"

    {_outcome, messages} =
      ActionHandler.handle(Task, envelope("submit_form", %{"values" => %{"name" => ""}}), [])

    assert error_for(messages, "name") == "attribute name is required"
  end

  test "a string badge's record value is never translated" do
    Ash.create!(BoardTask, %{name: "open"})

    pseudo = StringBadgeUI |> Info.build_surface(@pseudo) |> Jason.encode!()
    refute pseudo =~ "⟪Open⟫"
    assert pseudo =~ ~s("_badge_name":"Open")

    fr = StringBadgeUI |> Info.build_surface(@fr) |> Jason.encode!()
    refute fr =~ "Ouvrir"
  end

  test "an agent-written badge_text is shown as written" do
    spec = %{
      "resource" => "BoardTask",
      "title" => "Tasks",
      "components" => [
        %{
          "kind" => "table",
          "fields" => ["name", "priority"],
          "read_action" => "read",
          "row_layout" => %{
            "title" => "name",
            "badge" => "priority",
            "badge_text" => %{"low" => "Calme", "high" => "Urgent"}
          }
        }
      ]
    }

    Ash.create!(BoardTask, %{name: "card", priority: :high})

    {:ok, surface} = Dynamic.resolve(spec, allowlist: Dynamic.allowlist([BoardTask]))
    json = surface |> Dynamic.build_surface([authorize?: false] ++ @pseudo) |> Jason.encode!()

    assert json =~ ~s("_badge_priority":"Urgent")
  end

  test "an imported spec renders its declared labels through the catalog" do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    declared = MinimalUI |> Info.build_surface([authorize?: false] ++ @fr) |> Jason.encode!()
    assert declared =~ "Nom (autonome)"

    {:ok, spec, _rejections} = Dynamic.Importer.import(MinimalUI)
    allowlist = Dynamic.allowlist([Minimal])

    {:ok, imported} = Dynamic.resolve(spec, allowlist: allowlist, imported?: true)
    json = imported |> Dynamic.build_surface([authorize?: false] ++ @fr) |> Jason.encode!()
    assert json =~ "Nom (autonome)"

    # A composed spec's own text is still shown as written.
    {:ok, composed} = Dynamic.resolve(spec, allowlist: allowlist)
    json = composed |> Dynamic.build_surface([authorize?: false] ++ @fr) |> Jason.encode!()
    assert json =~ "Name (standalone)"
    refute json =~ "Nom (autonome)"
  end

  test "a value's label does not share a catalog entry with an action's label" do
    json = BoardTaskUI |> Info.build_surface(@fr) |> Jason.encode!()

    refute json =~ "Ouvrir"
    assert json =~ "Ouvert"

    {_context, _msgid} =
      Enum.find(Metadata.surface_messages(BoardTaskUI), &(&1 == {"one_of:status", "Open"})) ||
        flunk("the extractor does not collect the one_of label under its context")
  end

  test "an admin filter hint is translated and extracted" do
    pseudo = L10nScenarios.run(L10nScenarios.scenario("hub_build_admin"), @pseudo)
    assert pseudo =~ ~s("hint": "⟪Statuses update nightly.⟫")
    assert {nil, "Statuses update nightly."} in Metadata.surface_messages(HubUI)
  end

  @tag ac: "A2UI-NEW/AC-7"
  test "a declared report label is translated once and extracted in place of the humanized name" do
    json = LabelledReportUI |> Info.build_surface(@pseudo) |> Jason.encode!()

    assert json =~ ~s("label":"⟪Minimum length⟫")
    assert json =~ ~s("text":"⟪Letters⟫")
    refute json =~ "⟪⟪"
    refute json =~ "Min length"

    messages = Metadata.surface_messages(LabelledReportUI)

    assert {nil, "Minimum length"} in messages
    assert {nil, "Letters"} in messages
    refute {nil, "Min length"} in messages
    refute {nil, "Length"} in messages
  end

  test "the inline-edit feedback's field name is in the extracted catalog" do
    assert {nil, "Replacement"} in Metadata.surface_messages(BucketWordsUI)
  end
end
