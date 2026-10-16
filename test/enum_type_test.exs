defmodule AshA2ui.EnumTypeTest do
  @moduledoc """
  `Ash.Type.Enum`-typed attributes behave like `one_of`-constrained atoms:
  they default to ChoicePickers and their options come from the enum module's
  `values/0` — labels from `label/1` when the enum declares them, humanized
  values otherwise. Covers the form input, the query filter picker, and the
  submit-side cast.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.EnumRecord

  defp components(messages) do
    %{"updateComponents" => %{"components" => components}} =
      Enum.find(messages, &Map.has_key?(&1, "updateComponents"))

    Map.new(components, &{&1["id"], &1})
  end

  test "Ash.Type.Enum maps to :choice_picker in the TypeMapper" do
    assert AshA2ui.TypeMapper.widget_for(AshA2ui.Test.Severity) == :choice_picker
    assert AshA2ui.TypeMapper.widget_for(AshA2ui.Test.Stage) == :choice_picker
    refute AshA2ui.TypeMapper.enum_type?(Ash.Type.String)
    refute AshA2ui.TypeMapper.enum_type?(nil)
  end

  test "the form input is a ChoicePicker with options from values/0" do
    components = EnumRecord |> AshA2ui.Info.build_surface() |> components()

    assert %{
             "component" => "ChoicePicker",
             "options" => [
               %{"label" => "Low", "value" => "low"},
               %{"label" => "Medium", "value" => "medium"},
               %{"label" => "Very high", "value" => "very_high"}
             ]
           } = components["form_input_severity"]
  end

  test "declared enum labels win over humanization" do
    components = EnumRecord |> AshA2ui.Info.build_surface() |> components()

    assert %{
             "component" => "ChoicePicker",
             "options" => [
               %{"label" => "To Do", "value" => "todo"},
               %{"label" => "In Progress", "value" => "in_progress"}
             ]
           } = components["form_input_stage"]
  end

  test "query filter pickers get the enum options (plus All)" do
    components = EnumRecord |> AshA2ui.Info.build_surface() |> components()

    assert %{
             "component" => "ChoicePicker",
             "options" => [%{"label" => "All", "value" => ""} | options]
           } = components["query_filter_severity"]

    assert Enum.map(options, & &1["value"]) == ["low", "medium", "very_high"]
  end

  test "submitted enum strings cast through the form action" do
    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "submit_form",
        "context" => %{
          "values" => %{"name" => "cast me", "severity" => "very_high", "stage" => ["todo"]}
        }
      }
    }

    assert {:ok, _messages} = AshA2ui.ActionHandler.handle(EnumRecord, envelope, actor: nil)

    assert [%{severity: :very_high, stage: :todo}] =
             EnumRecord |> Ash.read!(action: :read, authorize?: false) |> Enum.take(1)
  end

  test "an enum filter value is validated and applied" do
    Ash.create!(EnumRecord, %{name: "low one", severity: :low}, authorize?: false)
    Ash.create!(EnumRecord, %{name: "high one", severity: :very_high}, authorize?: false)

    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "query",
        "context" => %{
          "query" => %{"filters" => %{"severity" => "very_high"}, "page" => 1}
        }
      }
    }

    assert {:ok, messages} = AshA2ui.ActionHandler.handle(EnumRecord, envelope, actor: nil)

    assert %{"updateDataModel" => %{"path" => "/records", "value" => [record]}} =
             Enum.find(messages, &match?(%{"updateDataModel" => %{"path" => "/records"}}, &1))

    # table rows read enum values as their labels, on refreshes as on the
    # initial render
    assert record["severity"] == "Very high"

    bogus = put_in(envelope, ["action", "context", "query", "filters", "severity"], "bogus")
    assert {:error, error_messages} = AshA2ui.ActionHandler.handle(EnumRecord, bogus, actor: nil)

    assert [
             %{
               "updateDataModel" => %{"path" => "/ui/feedback", "value" => %{"message" => status}}
             }
           ] =
             error_messages

    assert status =~ "invalid"
  end
end
