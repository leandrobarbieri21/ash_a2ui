# The fixtures this suite exercises (TestDomain, Protected, Gadget, Widget)
# live in test/support/action_handler_fixtures.ex — they are shared with
# relationship_test.exs and v1_0_action_handler_test.exs, and support files
# compile before any test runs, so cross-file load order cannot matter.

defmodule AshA2ui.ActionHandlerTest do
  @moduledoc """
  Round-trip tests for `AshA2ui.ActionHandler.handle/3` against the frozen
  cross-track wire contract: client `action` envelopes in, schema-valid
  `updateDataModel` follow-ups out.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ActionHandlerTest.{CheckInFacade, Gadget, Protected, Ticket, Widget}
  alias AshA2ui.Test.{KitchenSink, Minimal, MinimalUI}

  @actor %{id: "test-actor"}

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

  defp last_value_at(messages, path) do
    messages |> Enum.reverse() |> value_at(path)
  end

  defp paths(messages) do
    Enum.map(messages, & &1["updateDataModel"]["path"])
  end

  defp assert_all_valid(messages) do
    Enum.each(messages, &assert_valid_server_message/1)
    messages
  end

  describe "submit_form (create)" do
    test "creates a record and returns schema-valid refresh messages" do
      env =
        envelope("submit_form", "kitchen_sink", %{
          "values" => %{"name" => "Widget", "count" => 2}
        })

      assert_valid_client_message(env)

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

    test "merges a generic action's map result under /ui/action_result" do
      record = Ash.create!(Gadget, %{name: "G"}, authorize?: false)

      env =
        envelope("invoke", "gadget", %{
          "action" => "generate_secret",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(Gadget, env)
      assert_all_valid(messages)

      # the batch clears /ui/action_result before setting it; last write wins
      result = last_value_at(messages, "/ui/action_result")
      assert result["secret"] == "s3cr3t"
      assert result["record_id"] == record.id

      # the regular refresh messages still accompany the action result
      assert "/records" in paths(messages)
      assert value_at(messages, "/ui/feedback")["message"] =~ "generate_secret"
    end

    test "serializes a map result to display text at /ui/action_result_text" do
      record = Ash.create!(Gadget, %{name: "G"}, authorize?: false)

      env =
        envelope("invoke", "gadget", %{
          "action" => "generate_secret",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(Gadget, env)
      assert_all_valid(messages)

      # the clear precedes the set, so the last write at the path wins
      text = last_value_at(messages, "/ui/action_result_text")
      assert text =~ "Secret: s3cr3t"
      assert text =~ "Record id: #{record.id}"
    end

    test "invokes an update action listed in row_actions on the identified record" do
      record = Ash.create!(Widget, %{name: "W"}, authorize?: false)

      env = envelope("invoke", "widget", %{"action" => "touch", "recordId" => record.id})
      assert_valid_client_message(env)

      assert {:ok, messages} = ActionHandler.handle(Widget, env)
      assert_all_valid(messages)

      # the *invoked* update action ran (not the form's :update, which would
      # have been a no-op empty-param update)
      updated = Ash.get!(Widget, record.id, authorize?: false)
      assert updated.touched == true
      assert updated.name == "W"

      assert [row] = value_at(messages, "/records")
      assert row["touched"] == true
      assert value_at(messages, "/ui/feedback")["message"] =~ "touch"
    end

    test "subsequent actions clear /ui/action_result and /ui/action_result_text" do
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

      assert value_at(messages, "/ui/action_result") == %{}
      assert value_at(messages, "/ui/action_result_text") == ""
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
      assert value_at(messages, "/ui/feedback")["message"] =~ "check_in"

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
      assert value_at(messages, "/ui/feedback")["message"] =~ "check_in"
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

      assert value_at(messages, "/ui/feedback")["message"] =~ "not authorized"
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

      assert value_at(messages, "/ui/feedback") == %{
               "kind" => "error",
               "message" => ~s(Malformed start_edit action: context is missing "recordId".)
             }
    end

    test "select_row is no longer an action" do
      record = Ash.create!(KitchenSink, %{name: "Pick", count: 5}, authorize?: false)
      env = envelope("select_row", "kitchen_sink", %{"recordId" => record.id})

      assert {:error, [message]} = ActionHandler.handle(KitchenSink, env)
      assert_valid_server_message(message)
      assert value_at([message], "/ui/feedback")["message"] == ~s(Unknown action "select_row".)
      refute value_at([message], "/form")
    end
  end

  describe "envelope parsing" do
    test "accepts a bare inner action map" do
      bare = %{"name" => "submit_form", "context" => %{"values" => %{"name" => "Bare"}}}

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, bare)
      assert_all_valid(messages)
      assert [%{name: "Bare"}] = Ash.read!(KitchenSink, authorize?: false)
    end

    test "unknown action name returns an /ui/feedback error message" do
      env = envelope("explode", "kitchen_sink", %{})

      assert {:error, [message]} = ActionHandler.handle(KitchenSink, env)
      assert_valid_server_message(message)
      assert value_at([message], "/ui/feedback")["message"] =~ ~s(Unknown action "explode")
    end

    test "malformed message returns an /ui/feedback error message" do
      assert {:error, [message]} = ActionHandler.handle(KitchenSink, %{"wat" => true})
      assert_valid_server_message(message)
      assert value_at([message], "/ui/feedback")["message"] =~ "Malformed"
    end
  end

  describe "authorization" do
    test "Forbidden maps to a not-authorized /ui/feedback without field errors" do
      env = envelope("submit_form", "protected", %{"values" => %{"name" => "Nope"}})

      assert {:error, messages} = ActionHandler.handle(Protected, env)
      assert_all_valid(messages)

      assert value_at(messages, "/ui/feedback")["message"] =~ "not authorized"
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

      assert Enum.all?(messages, fn message ->
               message["updateDataModel"]["surfaceId"] == "minimal_standalone"
             end)
    end
  end
end
