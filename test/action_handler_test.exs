# The fixtures this suite exercises (TestDomain, Protected, Gadget, Widget)
# live in test/support/action_handler_fixtures.ex — they are shared with
# relationship_test.exs and v1_0_action_handler_test.exs, and support files
# compile before any test runs, so cross-file load order cannot matter.

defmodule AshA2ui.ActionHandlerTest do
  @moduledoc """
  Round-trip tests for `AshA2ui.ActionHandler.handle/3`: A2UI 1.0 `action`
  messages in, schema-valid `updateDataModel` follow-ups out. The function
  call path and the message validation are in renderer_messages_test.exs.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ActionHandlerTest.{CheckInFacade, Gadget, Protected, Ticket, Widget}
  alias AshA2ui.Test.{KitchenSink, Messages, Minimal, MinimalUI}

  @actor %{id: "test-actor"}

  defp envelope(name, surface_id, context),
    do: Messages.call(name, surface_id, context, id: "call-1")

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp paths(messages) do
    for(%{"updateDataModel" => %{"path" => path}} <- messages, do: path)
  end

  defp assert_all_valid(messages) do
    Enum.each(messages, &assert_valid_agent_message/1)
    messages
  end

  describe "submit_form (create)" do
    test "creates a record and returns schema-valid refresh messages" do
      env =
        envelope("submit_form", "kitchen_sink", %{
          "values" => %{"name" => "Widget", "count" => 2}
        })

      assert_valid_renderer_message(env)

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert [record] = Ash.read!(KitchenSink, authorize?: false)
      assert record.name == "Widget"
      assert record.count == 2

      assert [row] = value_at(messages, "/records")
      assert row["id"] == record.id
      assert row["name"] == "Widget"
      assert row["count"] == 2

      assert value_at(messages, "/form") == %{}
      assert value_at(messages, "/errors") == %{}
      assert value_at(messages, "/ui/feedback")["message"] =~ ~r/creat/i
    end

    test "ignores unknown keys in values instead of failing" do
      env =
        envelope("submit_form", "kitchen_sink", %{
          "values" => %{"name" => "Lax", "bogus_key" => "ignored"}
        })

      assert {:ok, _messages} = ActionHandler.handle(KitchenSink, env)
      assert [%{name: "Lax"}] = Ash.read!(KitchenSink, authorize?: false)
    end
  end

  describe "submit_form (update)" do
    test "updates the record identified by recordId" do
      record = Ash.create!(KitchenSink, %{name: "Before"}, authorize?: false)

      env =
        envelope("submit_form", "kitchen_sink", %{
          "values" => %{"name" => "After"},
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert Ash.get!(KitchenSink, record.id, authorize?: false).name == "After"
      assert [%{"name" => "After"}] = value_at(messages, "/records")
      assert value_at(messages, "/ui/feedback")["message"] =~ ~r/updat/i
    end
  end

  describe "submit_form (validation errors)" do
    test "maps a missing required field to /errors/<field> and does not create the record" do
      env = envelope("submit_form", "kitchen_sink", %{"values" => %{}})

      assert {:error, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert value_at(messages, "/errors/name") =~ "required"
      assert is_binary(value_at(messages, "/ui/feedback")["message"])
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end
  end

  describe "invoke" do
    test "invokes a destroy action listed in row_actions" do
      record = Ash.create!(KitchenSink, %{name: "Doomed"}, authorize?: false)

      env =
        envelope("invoke", "kitchen_sink", %{
          "action" => "destroy",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert Ash.read!(KitchenSink, authorize?: false) == []
      assert value_at(messages, "/records") == []
    end

    test "rejects an action that is not listed in row_actions" do
      record = Ash.create!(KitchenSink, %{name: "Safe"}, authorize?: false)

      env =
        envelope("invoke", "kitchen_sink", %{
          "action" => "create",
          "recordId" => record.id
        })

      assert {:error, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert value_at(messages, "/ui/feedback")["message"] =~ "not allowed"
      assert length(Ash.read!(KitchenSink, authorize?: false)) == 1
    end

    test "puts a generic action's map result in the success feedback" do
      record = Ash.create!(Gadget, %{name: "G"}, authorize?: false)

      env =
        envelope("invoke", "gadget", %{
          "action" => "generate_secret",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(Gadget, env)
      assert_all_valid(messages)

      feedback = value_at(messages, "/ui/feedback")
      assert feedback["kind"] == "success"
      assert feedback["result"] == %{"secret" => "s3cr3t", "record_id" => record.id}

      # the regular refresh messages still accompany the action result
      assert "/records" in paths(messages)
      assert feedback["message"] == "Generate secret completed."
    end

    test "renders a map result as display text in the feedback's resultText" do
      record = Ash.create!(Gadget, %{name: "G"}, authorize?: false)

      env =
        envelope("invoke", "gadget", %{
          "action" => "generate_secret",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(Gadget, env)
      assert_all_valid(messages)

      text = value_at(messages, "/ui/feedback")["resultText"]
      assert text =~ "Secret: s3cr3t"
      assert text =~ "Record id: #{record.id}"
    end

    test "invokes an update action listed in row_actions on the identified record" do
      record = Ash.create!(Widget, %{name: "W"}, authorize?: false)

      env = envelope("invoke", "widget", %{"action" => "touch", "recordId" => record.id})
      assert_valid_renderer_message(env)

      assert {:ok, messages} = ActionHandler.handle(Widget, env)
      assert_all_valid(messages)

      # the *invoked* update action ran (not the form's :update, which would
      # have been a no-op empty-param update)
      updated = Ash.get!(Widget, record.id, authorize?: false)
      assert updated.touched == true
      assert updated.name == "W"

      assert [row] = value_at(messages, "/records")
      assert row["touched"] == true
      assert value_at(messages, "/ui/feedback")["message"] == "Touch completed."
    end

    test "the next action's feedback carries no stale result" do
      record = Ash.create!(Gadget, %{name: "G"}, authorize?: false)

      secret_env =
        envelope("invoke", "gadget", %{
          "action" => "generate_secret",
          "recordId" => record.id
        })

      assert {:ok, _messages} = ActionHandler.handle(Gadget, secret_env)

      destroy_env =
        envelope("invoke", "gadget", %{"action" => "destroy", "recordId" => record.id})

      assert {:ok, messages} = ActionHandler.handle(Gadget, destroy_env)
      assert_all_valid(messages)

      assert %{"kind" => "success", "result" => %{}, "resultText" => ""} =
               value_at(messages, "/ui/feedback")
    end
  end

  describe "invoke (via delegation)" do
    test "delegates to the host MFA with the record and actor, and renders the standard success channel" do
      record = Ash.create!(Ticket, %{name: "Waitlisted"}, authorize?: false)

      env = envelope("invoke", "ticket", %{"action" => "check_in", "recordId" => record.id})

      assert {:ok, messages} = ActionHandler.handle(Ticket, env, actor: @actor)
      assert_all_valid(messages)

      # the delegate — not the direct dispatch — ran the resource action,
      # under the actor the host passed to the handler
      assert Ash.get!(Ticket, record.id, authorize?: false).status == "checked_in"

      assert [row] = value_at(messages, "/records")
      assert row["status"] == "checked_in"
      assert value_at(messages, "/ui/feedback")["message"] == "Check in completed."

      call = Process.get({CheckInFacade, :last_call})
      assert call.source == :board
      assert call.context.record.id == record.id
      assert call.context.actor == @actor
      assert call.context.action == :check_in
      assert call.context.tenant == nil
      assert call.context.surface_id == "ticket"
      assert call.context.selected == %{}
    end

    test "a delegate that does not write leaves the record untouched (the direct action never runs)" do
      record = Ash.create!(Ticket, %{name: "stale"}, authorize?: false)

      env = envelope("invoke", "ticket", %{"action" => "check_in", "recordId" => record.id})

      assert {:ok, messages} = ActionHandler.handle(Ticket, env)
      assert_all_valid(messages)

      assert Ash.get!(Ticket, record.id, authorize?: false).status == "open"
      assert value_at(messages, "/ui/feedback")["message"] == "Check in completed."
    end

    test "propagates a delegate error into /errors/<field> and /ui/feedback" do
      record = Ash.create!(Ticket, %{name: "completed"}, authorize?: false)

      env = envelope("invoke", "ticket", %{"action" => "check_in", "recordId" => record.id})

      assert {:error, messages} = ActionHandler.handle(Ticket, env)
      assert_all_valid(messages)

      assert value_at(messages, "/errors/status") =~ "task already completed"
      assert is_binary(value_at(messages, "/ui/feedback")["message"])
    end

    test "propagates Ash.Error.Forbidden as the not-authorized status" do
      record = Ash.create!(Ticket, %{name: "locked"}, authorize?: false)

      env = envelope("invoke", "ticket", %{"action" => "check_in", "recordId" => record.id})

      assert {:error, messages} = ActionHandler.handle(Ticket, env)
      assert_all_valid(messages)

      assert %{"code" => "FORBIDDEN", "message" => text} = value_at(messages, "/ui/feedback")
      assert text =~ "not authorized"
    end

    test "a via action without a recordId is rejected" do
      env = envelope("invoke", "ticket", %{"action" => "check_in"})

      assert {:error, messages} = ActionHandler.handle(Ticket, env)
      assert_all_valid(messages)

      assert value_at(messages, "/ui/feedback")["message"] =~ "recordId"
    end
  end

  describe "start_edit form population" do
    test "populates /form with the record's values and opens the edit task" do
      record = Ash.create!(KitchenSink, %{name: "Pick", count: 5}, authorize?: false)

      env = envelope("start_edit", "kitchen_sink", %{"recordId" => record.id})

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      form = value_at(messages, "/form")
      assert form["id"] == record.id
      assert form["name"] == "Pick"
      assert form["count"] == 5

      assert value_at(messages, "/ui/intent") == "edit"
      assert value_at(messages, "/ui/panel")["mode"] == "edit"
    end

    test "missing recordId is treated as malformed" do
      env = envelope("start_edit", "kitchen_sink", %{})

      assert {:error, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert %{
               "kind" => "error",
               "code" => "INVALID_ACTION",
               "functionCallId" => "call-1",
               "message" => ~s(Malformed start_edit action: context is missing "recordId".)
             } = value_at(messages, "/ui/feedback")
    end

    test "select_row is no longer an action" do
      record = Ash.create!(KitchenSink, %{name: "Pick", count: 5}, authorize?: false)
      env = envelope("select_row", "kitchen_sink", %{"recordId" => record.id})

      assert {:error, [message, _response]} = ActionHandler.handle(KitchenSink, env)
      assert_valid_agent_message(message)
      assert value_at([message], "/ui/feedback")["message"] == ~s(Unknown action "select_row".)
      refute value_at([message], "/form")
    end
  end

  describe "message parsing" do
    test "refuses a bare inner action map: only a 1.0 message is accepted" do
      bare = %{"name" => "submit_form", "context" => %{"values" => %{"name" => "Bare"}}}

      assert {:error, []} = ActionHandler.handle(KitchenSink, bare)
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end

    test "unknown action name returns an UNKNOWN_ACTION feedback error" do
      env = envelope("explode", "kitchen_sink", %{})

      assert {:error, [message, _response]} = ActionHandler.handle(KitchenSink, env)
      assert_valid_agent_message(message)

      assert %{"kind" => "error", "code" => "UNKNOWN_ACTION", "message" => text} =
               value_at([message], "/ui/feedback")

      assert text =~ ~s(Unknown action "explode")
    end

    test "a message that is no renderer-to-agent message is refused with no follow-ups" do
      assert {:error, []} = ActionHandler.handle(KitchenSink, %{"wat" => true})
    end
  end

  describe "authorization" do
    test "Forbidden maps to a not-authorized /ui/feedback without field errors" do
      env = envelope("submit_form", "protected", %{"values" => %{"name" => "Nope"}})

      assert {:error, messages} = ActionHandler.handle(Protected, env)
      assert_all_valid(messages)

      assert %{"code" => "FORBIDDEN", "message" => text} = value_at(messages, "/ui/feedback")
      assert text =~ "not authorized"
      refute Enum.any?(paths(messages), &String.starts_with?(&1, "/errors/"))
      assert Ash.read!(Protected, authorize?: false) == []
    end

    test "the actor is honored on both the write and the refresh read" do
      env = envelope("submit_form", "protected", %{"values" => %{"name" => "Yep"}})

      assert {:ok, messages} = ActionHandler.handle(Protected, env, actor: @actor)
      assert_all_valid(messages)

      assert [%{name: "Yep"}] = Ash.read!(Protected, authorize?: false)
      assert [%{"name" => "Yep"}] = value_at(messages, "/records")
    end

    test "authorize?: false bypasses policies (explicit opt-out)" do
      env = envelope("submit_form", "protected", %{"values" => %{"name" => "Bypass"}})

      assert {:ok, _messages} = ActionHandler.handle(Protected, env, authorize?: false)
      assert [%{name: "Bypass"}] = Ash.read!(Protected, authorize?: false)
    end
  end

  describe "standalone UI modules" do
    test "a standalone UI module works as the first argument" do
      env =
        envelope("submit_form", "minimal_standalone", %{
          "values" => %{"name" => "Standalone"}
        })

      assert {:ok, messages} = ActionHandler.handle(MinimalUI, env)
      assert_all_valid(messages)

      assert [%{name: "Standalone"}] = Ash.read!(Minimal, authorize?: false)

      assert [%{"agentFunctionResponse" => %{"functionCallId" => "call-1"}} | updates] =
               Enum.reverse(messages)

      assert Enum.all?(updates, fn message ->
               message["updateDataModel"]["surfaceId"] == "minimal_standalone"
             end)
    end
  end
end
