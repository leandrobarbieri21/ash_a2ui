defmodule AshA2ui.Wizard.WizardExperienceTest do
  @moduledoc """
  A2UI-106/AC-9: under experience v2 a stepped form's panel primary label
  reads "Next" before the last step and the usual create/save label on it,
  and the panel's submit gate follows the step.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Experience
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Enrollment
  alias AshA2ui.Test.Experience.Task

  setup do
    Application.put_env(:ash_a2ui, :experience_version, 2)
    on_exit(fn -> Application.delete_env(:ash_a2ui, :experience_version) end)
    :ok
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp handle(name, context) do
    message = %{"version" => "v0.9.1", "action" => %{"name" => name, "context" => context}}
    {tag, messages} = ActionHandler.handle(Enrollment, message)
    Enum.each(messages, &assert_valid_server_message/1)
    {tag, messages}
  end

  @tag ac: "A2UI-106/AC-9"
  test "primary label follows the step" do
    view = ResolvedView.resolve(Enrollment)

    for index <- [0, 1] do
      panel = Experience.panel_state(:create, view, nil, index)
      assert panel["primary_label"] == "Next"
      assert panel["submit_visible"] == []

      assert Experience.panel_state(:edit, view, "id", index)["primary_label"] == "Next"
    end

    last = Experience.panel_state(:create, view, nil, 2)
    assert last["primary_label"] == Experience.create_label(view)
    assert last["submit_visible"] == [%{"id" => "on"}]
    assert Experience.panel_state(:edit, view, "id", 2)["primary_label"] == "Save changes"

    # the default index is the first step
    assert Experience.panel_state(:create, view, nil)["primary_label"] == "Next"
    # view mode never offers a primary action
    assert Experience.panel_state(:view, view, "id", 0)["primary_label"] == ""

    # forms without steps keep their labels at any index
    task = ResolvedView.resolve(Task)
    assert Experience.panel_state(:create, task, nil, 0)["primary_label"] == "Create Task"
    assert Experience.panel_state(:create, task, nil, 0)["submit_visible"] == [%{"id" => "on"}]
  end

  @tag ac: "A2UI-106/AC-9"
  test "the handler rewrites the label as the wizard moves" do
    assert {:ok, messages} = handle("start_create", %{})
    assert value_at(messages, "/ui/panel")["primary_label"] == "Next"

    valid = %{"name" => "Ada", "email" => "ada@example.com", "team" => "Core"}

    assert {:ok, messages} = handle("wizard_next", %{"values" => valid, "index" => 0})
    assert value_at(messages, "/ui/panel/primary_label") == "Next"
    assert value_at(messages, "/ui/panel/submit_visible") == []

    assert {:ok, messages} = handle("wizard_next", %{"values" => valid, "index" => 1})
    assert value_at(messages, "/ui/panel/primary_label") == "Create Enrollment"
    assert value_at(messages, "/ui/panel/submit_visible") == [%{"id" => "on"}]

    assert {:ok, messages} = handle("wizard_back", %{"index" => 2})
    assert value_at(messages, "/ui/panel/primary_label") == "Next"

    assert {:ok, messages} = handle("wizard_back", %{"index" => 2, "recordId" => "some-id"})
    assert value_at(messages, "/ui/panel/primary_label") == "Next"

    assert {:ok, messages} =
             handle("wizard_next", %{"values" => valid, "index" => 1, "recordId" => nil})

    assert value_at(messages, "/ui/panel/primary_label") == "Create Enrollment"
  end
end
