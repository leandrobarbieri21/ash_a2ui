defmodule AshA2ui.Experience.FeedbackAndValidationTest do
  @moduledoc """
  A2UI-101/AC-14..AC-16: experience-layer typed feedback — validation failures
  retain the open task and its values while flagging errors, successes close
  the panel with success feedback and refresh the collection, and forged
  events still hit the same authorized actions as before.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Experience
  alias AshA2ui.Test.Experience.Protected
  alias AshA2ui.Test.Experience.Task
  alias AshA2ui.Test.Messages

  defp envelope(name, context \\ %{}) do
    Messages.call(name, "experience_task", context, id: "call-1")
  end

  defp by_path(messages) do
    messages
    |> Enum.filter(&Map.has_key?(&1, "updateDataModel"))
    |> Map.new(&{&1["updateDataModel"]["path"], &1["updateDataModel"]["value"]})
  end

  describe "validation failures" do
    @tag ac: "A2UI-101/AC-14"
    test "validation failure retains mode values and field errors" do
      record = Ash.create!(Task, %{name: "Editable"}, authorize?: false)

      assert {:ok, _} =
               ActionHandler.handle(Task, envelope("start_edit", %{"recordId" => record.id}))

      assert {:error, messages} =
               ActionHandler.handle(
                 Task,
                 envelope("submit_form", %{"values" => %{"name" => ""}, "recordId" => record.id})
               )

      values = by_path(messages)

      # the field error stays associated with its input
      assert is_binary(values["/errors/name"])
      assert values["/errors/name"] != ""

      # typed feedback reports the failure
      assert values["/ui/feedback"]["kind"] == "error"
      assert values["/ui/feedback"]["message"] != ""

      # the mode, panel, and submitted /form values are retained (no writes
      # in the error batch would clobber the client's open task)
      refute Map.has_key?(values, "/ui/intent")
      refute Map.has_key?(values, "/ui/panel")
      refute Map.has_key?(values, "/form")
    end
  end

  describe "successes" do
    @tag ac: "A2UI-101/AC-15"
    test "success closes panel with typed feedback" do
      assert {:ok, _} = ActionHandler.handle(Task, envelope("start_create"))

      assert {:ok, messages} =
               ActionHandler.handle(
                 Task,
                 envelope("submit_form", %{"values" => %{"name" => "Created!"}})
               )

      values = by_path(messages)

      assert values["/ui/feedback"] ==
               Experience.feedback("success", "Created successfully.", %{
                 "functionCallId" => "call-1"
               })

      assert values["/ui/intent"] == "browse"
      assert values["/ui/panel"]["visible"] == []
      assert values["/ui/panel"]["submit_visible"] == []

      # the collection data refreshes with the new record
      assert Enum.any?(values["/records"], &(&1["name"] == "Created!"))
    end

    @tag ac: "A2UI-101/AC-15"
    test "every invoke success carries typed feedback on the rendered path" do
      # The audit's headline failure: invoke successes wrote /ui/status —
      # which nothing rendered — so a successful row action looked
      # like a no-op. The feedback region binds /ui/feedback/message.
      record = Ash.create!(Task, %{name: "Doomed"}, authorize?: false)

      assert {:ok, messages} =
               ActionHandler.handle(
                 Task,
                 envelope("invoke", %{"action" => "destroy", "recordId" => record.id})
               )

      values = by_path(messages)

      # typed success on the path the status Text binds...
      assert values["/ui/feedback"] ==
               Experience.feedback("success", "Destroy completed.", %{
                 "functionCallId" => "call-1"
               })

      # ...with the classic status text still flowing alongside (the
      # programmatic contract, unchanged)...
      assert values["/ui/feedback"]["message"] == "Destroy completed."

      # ...and no panel/mode writes: a browse-mode invoke never closes a task
      refute Map.has_key?(values, "/ui/intent")
      refute Map.has_key?(values, "/ui/panel")
    end

    @tag ac: "A2UI-101/AC-15"
    test "invoke failures keep their typed error feedback" do
      record = Ash.create!(Task, %{name: "Survivor"}, authorize?: false)

      # destroy requires a recordId-bearing allowlisted row action; a
      # non-allowlisted action is rejected before any write
      assert {:error, messages} =
               ActionHandler.handle(Task, envelope("invoke", %{"action" => "explode"}))

      values = by_path(messages)
      assert values["/ui/feedback"]["kind"] == "error"
      assert values["/ui/feedback"]["message"] != ""

      # the untouched record proves the rejection happened before the write
      assert Ash.get!(Task, record.id, authorize?: false).name == "Survivor"
    end
  end

  describe "forged events" do
    @tag ac: "A2UI-101/AC-16"
    test "forged events still hit authorized actions" do
      record = Ash.create!(Protected, %{name: "Secret"}, authorize?: false)
      actor = %{admin: false}

      # forged start_edit: the authorized read succeeds, the update
      # authorization pre-flight rejects, and nothing changes
      assert {:error, messages} =
               ActionHandler.handle(
                 Protected,
                 envelope("start_edit", %{"recordId" => record.id}),
                 actor: actor
               )

      assert unauthorized?(messages)
      assert Ash.get!(Protected, record.id, authorize?: false).name == "Secret"

      # forged submit_form: the pre-existing authorized update path rejects
      assert {:error, messages} =
               ActionHandler.handle(
                 Protected,
                 envelope("submit_form", %{
                   "values" => %{"name" => "Hacked"},
                   "recordId" => record.id
                 }),
                 actor: actor
               )

      assert unauthorized?(messages)
      assert Ash.get!(Protected, record.id, authorize?: false).name == "Secret"
    end
  end

  defp unauthorized?(messages) do
    Enum.any?(messages, fn
      %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => %{"message" => value}}} ->
        value =~ "not authorized"

      _other ->
        false
    end)
  end

  describe "every rejection reaches the typed feedback" do
    # Before /ui/status was removed these paths wrote only /ui/status, which
    # nothing bound once the status Text read /ui/feedback/message.
    defp assert_error_feedback(messages, pattern) do
      values = by_path(messages)
      refute Map.has_key?(values, "/ui/status")
      assert %{"kind" => "error", "message" => message} = values["/ui/feedback"]
      assert message =~ pattern
      values
    end

    test "a forbidden start_edit" do
      record = Ash.create!(Protected, %{name: "Locked"}, authorize?: false)

      assert {:error, messages} =
               ActionHandler.handle(
                 Protected,
                 envelope("start_edit", %{"recordId" => record.id}),
                 actor: %{id: "viewer", admin: false}
               )

      values = assert_error_feedback(messages, "not authorized")
      refute Map.has_key?(values, "/form")
      refute Map.has_key?(values, "/ui/panel")
    end

    test "a malformed message is refused; an unknown action reaches the feedback" do
      assert {:error, []} = ActionHandler.handle(Task, %{"bogus" => true})

      assert {:error, messages} = ActionHandler.handle(Task, envelope("explode"))
      assert_error_feedback(messages, ~s(Unknown action "explode"))
    end

    test "a query allowlist rejection" do
      envelope =
        Messages.call("query", "test_surface", %{
          "query" => %{"sort" => %{"field" => "category", "dir" => "asc"}}
        })

      assert {:error, messages} = ActionHandler.handle(AshA2ui.Test.Paginated, envelope)
      values = assert_error_feedback(messages, "category")
      refute Map.has_key?(values, "/records")
    end

    test "a rejected ashAction call is answered with the feedback's code and message" do
      call = Messages.call("explode", "kitchen_sink_v1", %{}, id: "a-1")

      assert {:error, messages} = ActionHandler.handle(AshA2ui.Test.KitchenSinkV1UI, call)
      assert_valid_agent_messages(messages)

      feedback = by_path(messages)["/ui/feedback"]

      assert %{"kind" => "error", "code" => "UNKNOWN_ACTION", "functionCallId" => "a-1"} =
               feedback

      assert feedback["message"] =~ "Unknown action"

      assert %{"agentFunctionResponse" => %{"functionCallId" => "a-1", "error" => error}} =
               List.last(messages)

      assert error == %{"code" => "UNKNOWN_ACTION", "message" => feedback["message"]}
    end
  end
end
