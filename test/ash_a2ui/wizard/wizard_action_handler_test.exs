defmodule AshA2ui.Wizard.WizardActionHandlerTest do
  @moduledoc """
  A2UI-106/AC-2..AC-6: the wizard_next / wizard_back actions, submit
  failures returning to the owning step, and the index resets.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Enrollment

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "enrollments",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp handle(name, context), do: handle_on(Enrollment, name, context)

  defp handle_on(module, name, context) do
    {tag, messages} = ActionHandler.handle(module, envelope(name, context))
    Enum.each(messages, &assert_valid_server_message/1)
    {tag, messages}
  end

  defp paths(messages), do: Enum.map(messages, & &1["updateDataModel"]["path"])

  defp value_at(messages, path) do
    messages
    |> Enum.filter(&(&1["updateDataModel"]["path"] == path))
    |> List.last()
    |> Kernel.||(%{"updateDataModel" => %{}})
    |> get_in(["updateDataModel", "value"])
  end

  defp records, do: Ash.read!(Enrollment, authorize?: false)

  @tag ac: "A2UI-106/AC-2"
  test "next validates only reached steps" do
    context = %{
      "values" => %{"name" => "", "email" => "ada@example.com", "role" => "", "team" => ""},
      "index" => 0
    }

    assert {:error, messages} = handle("wizard_next", context)

    # the step-one error is written...
    assert is_binary(value_at(messages, "/errors/name"))
    # ...the later-step required error is not
    refute "/errors/team" in paths(messages)
    # the index stays on step one
    assert value_at(messages, "/ui/wizard")["index"] == 0
    assert value_at(messages, "/ui/wizard")["who_visible"] == [%{"id" => "on"}]
    # nothing is written to the data layer
    assert records() == []
  end

  @tag ac: "A2UI-106/AC-2"
  test "an invalid step-one value is reported even when required fields pass" do
    context = %{"values" => %{"name" => "Ada", "email" => "not-an-email"}, "index" => 0}

    assert {:error, messages} = handle("wizard_next", context)
    assert value_at(messages, "/errors/email") =~ "email"
    refute "/errors/team" in paths(messages)
    assert records() == []
  end

  @tag ac: "A2UI-106/AC-3"
  test "next advances when the step is valid" do
    context = %{
      "values" => %{"name" => "Ada", "email" => "ada@example.com", "role" => "", "team" => ""},
      "index" => 0
    }

    assert {:ok, messages} = handle("wizard_next", context)

    wizard = value_at(messages, "/ui/wizard")
    assert wizard["index"] == 1
    assert wizard["who_visible"] == []
    assert wizard["what_visible"] == [%{"id" => "on"}]
    assert Enum.map(wizard["steps"], & &1["state"]) == ["done", "current", "todo"]
    assert wizard["nav"]["back_visible"] == [%{"id" => "on"}]

    # /errors clears and /form is left to the client
    assert value_at(messages, "/errors") == %{}
    refute "/form" in paths(messages)
    assert records() == []

    # step two: team is now a reached field
    assert {:error, messages} = handle("wizard_next", %{context | "index" => 1})
    assert is_binary(value_at(messages, "/errors/team"))
    assert value_at(messages, "/ui/wizard")["index"] == 1

    # once every field step is valid the review step opens with the submit
    # (the panel's submit gate opens and its label becomes the create label)
    filled = put_in(context, ["values", "team"], "Core")
    assert {:ok, messages} = handle("wizard_next", %{filled | "index" => 1})
    wizard = value_at(messages, "/ui/wizard")
    assert wizard["index"] == 2
    assert wizard["confirm_visible"] == [%{"id" => "on"}]
    assert wizard["nav"]["next_visible"] == []
    refute Map.has_key?(wizard["nav"], "submit_visible")
    assert value_at(messages, "/ui/panel/submit_visible") == [%{"id" => "on"}]
    assert value_at(messages, "/ui/panel/primary_label") =~ "Create"
    assert records() == []
  end

  @tag ac: "A2UI-106/AC-3"
  test "next over an existing record validates the update changeset without writing" do
    record =
      Ash.create!(Enrollment, %{name: "Ada", email: "ada@example.com", team: "Core"},
        authorize?: false
      )

    context = %{
      "values" => %{"name" => "Grace", "email" => "grace@example.com", "team" => ""},
      "recordId" => record.id,
      "index" => 0
    }

    assert {:ok, messages} = handle("wizard_next", context)
    assert value_at(messages, "/ui/wizard")["index"] == 1
    assert [%{name: "Ada"}] = records()
  end

  @tag ac: "A2UI-106/AC-4"
  test "back does not validate" do
    assert {:ok, messages} = handle("wizard_back", %{"index" => 1})

    # the step moves (and the panel's label and submit gate with it);
    # nothing validates and /form is untouched
    assert paths(messages) == [
             "/ui/wizard",
             "/ui/panel/primary_label",
             "/ui/panel/submit_visible"
           ]

    assert value_at(messages, "/ui/wizard")["index"] == 0
    assert value_at(messages, "/ui/panel/primary_label") == "Next"

    # no validation even when the carried form is invalid
    assert {:ok, messages} =
             handle("wizard_back", %{"index" => 2, "values" => %{"name" => ""}})

    refute "/errors" in paths(messages)
    refute "/form" in paths(messages)
    assert value_at(messages, "/ui/wizard")["index"] == 1
  end

  @tag ac: "A2UI-106/AC-5"
  test "submit failure returns to the owning step" do
    context = %{
      "values" => %{"name" => "", "email" => "ada@example.com", "role" => "x", "team" => "Core"}
    }

    assert {:error, messages} = handle("submit_form", context)
    assert is_binary(value_at(messages, "/errors/name"))
    assert value_at(messages, "/ui/wizard")["index"] == 0
    assert records() == []

    # an error owned by step two lands on step two
    context = %{"values" => %{"name" => "Ada", "email" => "ada@example.com", "team" => ""}}
    assert {:error, messages} = handle("submit_form", context)
    assert is_binary(value_at(messages, "/errors/team"))
    assert value_at(messages, "/ui/wizard")["index"] == 1
  end

  @tag ac: "A2UI-106/AC-6"
  test "index resets after submit and task changes" do
    context = %{
      "values" => %{
        "name" => "Ada",
        "email" => "ada@example.com",
        "role" => "x",
        "team" => "Core"
      }
    }

    assert {:ok, messages} = handle("submit_form", context)
    assert value_at(messages, "/ui/wizard")["index"] == 0
    assert [%{name: "Ada"}] = records()

    assert {:ok, messages} = handle("start_create", %{})
    assert value_at(messages, "/ui/wizard")["index"] == 0

    assert {:ok, messages} = handle("cancel_record_task", %{})
    assert value_at(messages, "/ui/wizard")["index"] == 0

    [record] = records()
    assert {:ok, messages} = handle("start_edit", %{"recordId" => record.id})
    assert value_at(messages, "/ui/wizard")["index"] == 0

    # a successful edit-task submission also resets
    edit = %{
      "values" => %{"id" => record.id, "name" => "Grace", "email" => "g@example.com"},
      "recordId" => record.id
    }

    assert {:ok, messages} = handle("submit_form", edit)
    assert value_at(messages, "/ui/wizard")["index"] == 0
  end

  @tag ac: "A2UI-106/AC-6"
  test "a row action leaves the open task's step alone" do
    record =
      Ash.create!(Enrollment, %{name: "Ada", email: "ada@example.com", team: "Core"},
        authorize?: false
      )

    # A row action is not the task. The open task's step, panel label and
    # submit gate are left as they are (nothing moves /ui/wizard without
    # also rewriting the label).
    assert {:ok, messages} =
             handle_on(AshA2ui.Test.EnrollmentRowActionsUI, "invoke", %{
               "action" => "destroy",
               "recordId" => record.id
             })

    assert records() == []
    refute "/ui/wizard" in paths(messages)
    refute "/ui/panel/primary_label" in paths(messages)

    # select_row no longer exists, so it cannot move the step either
    kept = Ash.create!(Enrollment, %{name: "Cy", team: "Ops"}, authorize?: false)
    assert {:error, messages} = handle("select_row", %{"recordId" => kept.id})
    refute "/ui/wizard" in paths(messages)
    refute "/form" in paths(messages)
  end
end
