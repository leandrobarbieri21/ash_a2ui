defmodule AshA2ui.Wizard.WizardSecurityTest do
  @moduledoc """
  A2UI-106/AC-7: client-carried wizard state is re-validated server-side —
  /form keys outside the form's fields never reach the changeset (on Next
  and on the final submit_form alike), the
  carried index is clamped (or refused when it is not an integer), and no
  atom is created from client input.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Enrollment

  defp handle(name, context) do
    message = %{"version" => "v0.9.1", "action" => %{"name" => name, "context" => context}}
    {tag, messages} = ActionHandler.handle(Enrollment, message)
    Enum.each(messages, &assert_valid_server_message/1)
    {tag, messages}
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  # The attributes of the first changeset the probe reported; any further
  # reports from the same call (an atomic update re-runs the change) are
  # drained so the next call starts from an empty mailbox.
  defp probe! do
    assert_received {:wizard_probe, attributes, _arguments}
    drain_probe()
    attributes
  end

  defp drain_probe do
    receive do
      {:wizard_probe, _attributes, _arguments} -> drain_probe()
    after
      0 -> :ok
    end
  end

  defp unique_key, do: "wizard_probe_key_#{System.unique_integer([:positive])}"

  @tag ac: "A2UI-106/AC-7"
  test "carried state is filtered" do
    unknown = unique_key()

    values = %{
      "name" => "Ada",
      "email" => "ada@example.com",
      # accepted by the Ash action, but not a field of the form
      "internal_note" => "smuggled",
      # not known anywhere
      unknown => "x",
      "id" => Ash.UUID.generate()
    }

    assert {:ok, _messages} = handle("wizard_next", %{"values" => values, "index" => 0})

    assert_received {:wizard_probe, attributes, arguments}
    refute Map.has_key?(attributes, :internal_note)
    assert attributes[:name] == "Ada"
    assert arguments == %{}

    # no atom was created for the unknown key
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    assert Ash.read!(Enrollment, authorize?: false) == []
  end

  @tag ac: "A2UI-106/AC-7"
  test "submit_form on a stepped form casts the same filtered values Next validated" do
    values = %{
      "name" => "Ada",
      "email" => "ada@example.com",
      "team" => "Core",
      # accepted by the Ash action, but not a field of the form
      "internal_note" => "smuggled"
    }

    assert {:ok, _messages} = handle("wizard_next", %{"values" => values, "index" => 1})
    next_attributes = probe!()

    assert {:ok, _messages} = handle("submit_form", %{"values" => values})
    submit_attributes = probe!()

    # Next and Submit built the changeset from the same values
    assert submit_attributes == next_attributes
    refute Map.has_key?(submit_attributes, :internal_note)

    assert [record] = Ash.read!(Enrollment, authorize?: false)
    assert record.name == "Ada"
    assert record.internal_note == nil

    # the same holds for an edit
    edit = Map.put(values, "name", "Grace")

    assert {:ok, _messages} =
             handle("wizard_next", %{"values" => edit, "index" => 1, "recordId" => record.id})

    next_attributes = probe!()

    assert {:ok, _messages} = handle("submit_form", %{"values" => edit, "recordId" => record.id})
    submit_attributes = probe!()

    assert submit_attributes == next_attributes
    assert [%{name: "Grace", internal_note: nil}] = Ash.read!(Enrollment, authorize?: false)
  end

  @tag ac: "A2UI-106/AC-7"
  test "an out-of-range index is clamped into the step range" do
    valid = %{"name" => "Ada", "email" => "ada@example.com", "team" => "Core"}

    assert {:ok, messages} = handle("wizard_next", %{"values" => valid, "index" => 99})
    assert value_at(messages, "/ui/wizard")["index"] == 2

    assert {:ok, messages} = handle("wizard_back", %{"index" => -7})
    assert value_at(messages, "/ui/wizard")["index"] == 0

    # a clamped index still validates every reached step
    assert {:error, messages} = handle("wizard_next", %{"values" => %{}, "index" => 1_000})
    assert is_binary(value_at(messages, "/errors/name"))
    assert is_binary(value_at(messages, "/errors/team"))
  end

  @tag ac: "A2UI-106/AC-7"
  test "a non-integer index is refused without creating atoms" do
    bogus = unique_key()

    for index <- [bogus, %{"path" => "/ui/wizard/index"}, 1.5, nil, [1]] do
      assert {:error, messages} = handle("wizard_next", %{"values" => %{}, "index" => index})
      assert value_at(messages, "/ui/feedback")["message"] =~ "Malformed wizard action"
      refute value_at(messages, "/ui/wizard")

      assert {:error, _messages} = handle("wizard_back", %{"index" => index})
    end

    refute_received {:wizard_probe, _attributes, _arguments}
    assert_raise ArgumentError, fn -> String.to_existing_atom(bogus) end
  end

  @tag ac: "A2UI-106/AC-7"
  test "wizard actions are refused on forms without steps" do
    message = %{
      "version" => "v0.9.1",
      "action" => %{"name" => "wizard_next", "context" => %{"index" => 0}}
    }

    assert {:error, messages} = ActionHandler.handle(AshA2ui.Test.Promotion, message)
    assert value_at(messages, "/ui/feedback")["message"] =~ "does not declare steps"
  end
end
