defmodule AshA2ui.AgUiTest do
  @moduledoc """
  Conformance tests for `AshA2ui.AgUi` — the AG-UI transport layer.

  Event shapes are asserted against the AG-UI protocol's published event
  reference (docs.ag-ui.com; `@ag-ui/core` schemas): required fields,
  camelCase keys, and the SSE `data: <json>\\n\\n` frame encoding. The A2UI
  binding (ACTIVITY_SNAPSHOT / `a2ui_operations` / `a2ui-surface`) matches
  `@ag-ui/a2ui-middleware` and CopilotKit's `createA2UIMessageRenderer`.
  The wrapped A2UI operations themselves are validated against the vendored
  A2UI schemas.
  """
  use ExUnit.Case, async: true

  alias AshA2ui.AgUi
  alias AshA2ui.Test.{KitchenSinkV1UI, Minimal, MinimalUI, SchemaHelper}

  describe "lifecycle events" do
    test "run_started/2" do
      assert AgUi.run_started("thread-1", "run-1") ==
               %{"type" => "RUN_STARTED", "threadId" => "thread-1", "runId" => "run-1"}
    end

    test "run_finished/3 without result" do
      assert AgUi.run_finished("thread-1", "run-1") ==
               %{"type" => "RUN_FINISHED", "threadId" => "thread-1", "runId" => "run-1"}
    end

    test "run_finished/3 with result" do
      assert AgUi.run_finished("t", "r", result: %{"ok" => true})["result"] == %{"ok" => true}
    end

    test "run_error/2" do
      assert AgUi.run_error("boom") == %{"type" => "RUN_ERROR", "message" => "boom"}
      assert AgUi.run_error("boom", code: "timeout")["code"] == "timeout"
    end
  end

  describe "text message events" do
    test "start defaults role to assistant" do
      assert AgUi.text_message_start("m1") ==
               %{"type" => "TEXT_MESSAGE_START", "messageId" => "m1", "role" => "assistant"}
    end

    test "content carries the delta" do
      assert AgUi.text_message_content("m1", "Hi") ==
               %{"type" => "TEXT_MESSAGE_CONTENT", "messageId" => "m1", "delta" => "Hi"}
    end

    test "content rejects the spec-invalid empty delta" do
      assert_raise ArgumentError, fn -> AgUi.text_message_content("m1", "") end
    end

    test "end closes the message" do
      assert AgUi.text_message_end("m1") == %{"type" => "TEXT_MESSAGE_END", "messageId" => "m1"}
    end
  end

  describe "tool call events" do
    test "start/args/end/result shapes" do
      assert AgUi.tool_call_start("tc1", "list_tickets", parent_message_id: "m1") ==
               %{
                 "type" => "TOOL_CALL_START",
                 "toolCallId" => "tc1",
                 "toolCallName" => "list_tickets",
                 "parentMessageId" => "m1"
               }

      refute Map.has_key?(AgUi.tool_call_start("tc1", "list_tickets"), "parentMessageId")

      assert AgUi.tool_call_args("tc1", ~s({"q":)) ==
               %{"type" => "TOOL_CALL_ARGS", "toolCallId" => "tc1", "delta" => ~s({"q":)}

      assert AgUi.tool_call_end("tc1") == %{"type" => "TOOL_CALL_END", "toolCallId" => "tc1"}

      assert AgUi.tool_call_result("mt1", "tc1", ~s({"ok":true})) ==
               %{
                 "type" => "TOOL_CALL_RESULT",
                 "messageId" => "mt1",
                 "toolCallId" => "tc1",
                 "content" => ~s({"ok":true}),
                 "role" => "tool"
               }
    end
  end

  describe "pending_tool_call/4 — the HITL pause" do
    test "emits the start/args/end triple with encoded args and no result" do
      events =
        AgUi.pending_tool_call("tc-confirm", "request_admin_confirmation", %{
          "summary" => "Approve the referral?"
        })

      assert [
               %{
                 "type" => "TOOL_CALL_START",
                 "toolCallId" => "tc-confirm",
                 "toolCallName" => "request_admin_confirmation"
               },
               %{"type" => "TOOL_CALL_ARGS", "toolCallId" => "tc-confirm", "delta" => args},
               %{"type" => "TOOL_CALL_END", "toolCallId" => "tc-confirm"}
             ] = events

      assert Jason.decode!(args) == %{"summary" => "Approve the referral?"}

      # The pause convention: no TOOL_CALL_RESULT — the host emits
      # run_finished/3 with this call unresolved and waits for the user.
      refute Enum.any?(events, &(&1["type"] == "TOOL_CALL_RESULT"))
    end

    test "passes string args through verbatim and forwards options" do
      assert [start_event, %{"delta" => ~s({"x":1})}, _end_event] =
               AgUi.pending_tool_call("tc", "confirm", ~s({"x":1}), parent_message_id: "m9")

      assert start_event["parentMessageId"] == "m9"
    end
  end

  describe "surface_activity/2 — the A2UI binding" do
    test "wraps A2UI messages in the a2ui-surface activity snapshot" do
      messages = AshA2ui.Info.build_surface(MinimalUI)
      event = AgUi.surface_activity("surface-minimal", messages)

      assert event["type"] == "ACTIVITY_SNAPSHOT"
      assert event["messageId"] == "surface-minimal"
      assert event["activityType"] == "a2ui-surface"
      assert event["replace"] == true
      assert event["content"] == %{"a2ui_operations" => messages}
    end

    test "wrapped operations are valid A2UI v0.9.1 server messages" do
      messages = AshA2ui.Info.build_surface(MinimalUI)
      event = AgUi.surface_activity("surface-minimal", messages)

      for operation <- event["content"]["a2ui_operations"] do
        SchemaHelper.assert_valid_server_message(operation)
      end
    end

    test "the whole event JSON round-trips" do
      messages = AshA2ui.Info.build_surface(MinimalUI)
      event = AgUi.surface_activity("s", messages)

      assert event == event |> Jason.encode!() |> Jason.decode!()
    end
  end

  describe "encode_sse/1" do
    test "produces a data: frame terminated by a blank line" do
      frame = "t" |> AgUi.run_started("r") |> AgUi.encode_sse() |> IO.iodata_to_binary()

      assert String.starts_with?(frame, "data: ")
      assert String.ends_with?(frame, "\n\n")

      assert frame
             |> String.trim_leading("data: ")
             |> String.trim()
             |> Jason.decode!() == AgUi.run_started("t", "r")
    end
  end

  describe "decode_run_input/1" do
    test "extracts ids, chat messages, and forwarded props" do
      body = %{
        "threadId" => "thread-1",
        "runId" => "run-1",
        "state" => %{},
        "tools" => [],
        "context" => [],
        "messages" => [
          %{"id" => "m1", "role" => "user", "content" => "hello"},
          %{"id" => "m2", "role" => "assistant", "content" => "hi"},
          # transport bookkeeping roles are dropped:
          %{"id" => "m3", "role" => "tool", "content" => "{}", "toolCallId" => "tc"},
          %{
            "id" => "m4",
            "role" => "activity",
            "activityType" => "a2ui-surface",
            "content" => %{}
          },
          # malformed entries are dropped, not raised on:
          %{"id" => "m5", "role" => "user", "content" => ""},
          %{"id" => "m6", "role" => "user", "content" => %{"nested" => true}},
          %{"role" => "alien", "content" => "?"}
        ],
        "forwardedProps" => %{"custom" => 1}
      }

      assert AgUi.decode_run_input(body) == %{
               thread_id: "thread-1",
               run_id: "run-1",
               messages: [
                 %{role: :user, content: "hello"},
                 %{role: :assistant, content: "hi"}
               ],
               tool_results: %{"tc" => "{}"},
               a2ui_action: nil,
               forwarded_props: %{"custom" => 1}
             }
    end

    test "collects tool-result messages by toolCallId (last write wins)" do
      body = %{
        "messages" => [
          %{"id" => "t1", "role" => "tool", "toolCallId" => "tc-1", "content" => ~s({"ok":1})},
          %{"id" => "t2", "role" => "tool", "toolCallId" => "tc-1", "content" => "second wins"},
          # malformed entries are dropped, not raised on:
          %{"id" => "t3", "role" => "tool", "content" => "no toolCallId"},
          %{"id" => "t4", "role" => "tool", "toolCallId" => "tc-2", "content" => %{"n" => 1}},
          %{"id" => "t5", "role" => "tool", "toolCallId" => 42, "content" => "bad id"}
        ]
      }

      assert AgUi.decode_run_input(body).tool_results == %{"tc-1" => "second wins"}
    end

    test "surfaces forwardedProps.a2uiAction" do
      action = %{"userAction" => %{"name" => "invoke", "surfaceId" => "s"}}

      decoded =
        AgUi.decode_run_input(%{"forwardedProps" => %{"a2uiAction" => action}})

      assert decoded.a2ui_action == action
    end

    test "tolerates a hostile or empty body" do
      assert AgUi.decode_run_input(%{}) == %{
               thread_id: "",
               run_id: "",
               messages: [],
               tool_results: %{},
               a2ui_action: nil,
               forwarded_props: %{}
             }

      assert AgUi.decode_run_input(%{
               "threadId" => 42,
               "messages" => "nope",
               "forwardedProps" => []
             }).messages == []
    end
  end

  describe "decode_action/1" do
    test "decodes the CopilotKit userAction wrapper into the v0.9.1 envelope" do
      assert {:ok, envelope} =
               AgUi.decode_action(%{
                 "userAction" => %{
                   "name" => "invoke",
                   "surfaceId" => "tickets",
                   "sourceComponentId" => "row_action_archive",
                   "timestamp" => "2026-07-13T12:00:00Z",
                   "context" => %{"action" => "archive", "recordId" => "abc"},
                   "dataContextPath" => "/records/0"
                 }
               })

      assert envelope == %{
               "version" => "v0.9.1",
               "action" => %{
                 "name" => "invoke",
                 "surfaceId" => "tickets",
                 "sourceComponentId" => "row_action_archive",
                 "timestamp" => "2026-07-13T12:00:00Z",
                 "context" => %{"action" => "archive", "recordId" => "abc"}
               }
             }

      # renderer extras (dataContextPath) must not leak into the envelope
      refute Map.has_key?(envelope["action"], "dataContextPath")
    end

    test "decodes a bare user-action map and an enveloped action" do
      assert {:ok, %{"action" => %{"name" => "start_create", "context" => %{}}}} =
               AgUi.decode_action(%{"name" => "start_create"})

      assert {:ok, %{"action" => %{"name" => "query"}}} =
               AgUi.decode_action(%{"action" => %{"name" => "query", "context" => %{}}})
    end

    test "rejects payloads without a usable action name" do
      assert :error = AgUi.decode_action(%{})
      assert :error = AgUi.decode_action(%{"name" => ""})
      assert :error = AgUi.decode_action(%{"name" => 42})
      assert :error = AgUi.decode_action(%{"userAction" => %{"context" => %{}}})
    end

    test "decoded envelopes are valid A2UI client messages and drive the ActionHandler" do
      record =
        Minimal
        |> Ash.Changeset.for_create(:create, %{name: "before"})
        |> Ash.create!()

      {:ok, envelope} =
        AgUi.decode_action(%{
          "userAction" => %{
            "name" => "view_record",
            "surfaceId" => "minimal_standalone",
            "timestamp" => "2026-07-13T12:00:00Z",
            "context" => %{"recordId" => record.id}
          }
        })

      SchemaHelper.assert_valid_client_message(envelope)

      assert {:ok, messages} = AshA2ui.ActionHandler.handle(MinimalUI, envelope)
      assert Enum.any?(messages, &match?(%{"updateDataModel" => _}, &1))

      assert Enum.any?(
               messages,
               &match?(%{"updateDataModel" => %{"path" => "/ui/intent", "value" => "view"}}, &1)
             )
    end
  end

  describe "resolve_pending/2 — the HITL resume" do
    defp action_input(user_action) do
      AgUi.decode_run_input(%{
        "forwardedProps" => %{"a2uiAction" => %{"userAction" => user_action}}
      })
    end

    test "an a2ui action carrying the pending toolCallId resolves it" do
      input =
        action_input(%{
          "name" => "invoke",
          "surfaceId" => "somewhere-else",
          "context" => %{"toolCallId" => "tc-confirm", "action" => "approve", "recordId" => "r1"}
        })

      assert {:resume, "tc-confirm", action} =
               AgUi.resolve_pending(input, %{tool_call_id: "tc-confirm"})

      assert action["name"] == "invoke"
      assert action["context"]["action"] == "approve"
      assert action["context"]["recordId"] == "r1"
    end

    test "an a2ui action from the pending confirmation surface resolves it" do
      input =
        action_input(%{
          "name" => "invoke",
          "surfaceId" => "confirm-surface",
          "context" => %{"action" => "approve"}
        })

      assert {:resume, "tc-confirm", action} =
               AgUi.resolve_pending(input, %{
                 tool_call_id: "tc-confirm",
                 surface_id: "confirm-surface"
               })

      assert action["surfaceId"] == "confirm-surface"
    end

    test "an unrelated a2ui action does not resolve the pending call" do
      input =
        action_input(%{
          "name" => "invoke",
          "surfaceId" => "another-surface",
          "context" => %{"action" => "select"}
        })

      assert AgUi.resolve_pending(input, %{
               tool_call_id: "tc-confirm",
               surface_id: "confirm-surface"
             }) == :none
    end

    test "a tool-result message in the history resolves it" do
      input =
        AgUi.decode_run_input(%{
          "messages" => [
            %{
              "id" => "t1",
              "role" => "tool",
              "toolCallId" => "tc-confirm",
              "content" => ~s({"decision":"approved"})
            }
          ]
        })

      assert {:resume, "tc-confirm", ~s({"decision":"approved"})} =
               AgUi.resolve_pending(input, %{tool_call_id: "tc-confirm"})
    end

    test "returns :none when nothing resolves the call" do
      assert AgUi.resolve_pending(AgUi.decode_run_input(%{}), %{tool_call_id: "tc"}) == :none

      # a malformed action payload never resolves anything
      malformed =
        AgUi.decode_run_input(%{
          "forwardedProps" => %{"a2uiAction" => %{"userAction" => %{"context" => %{}}}}
        })

      assert AgUi.resolve_pending(malformed, %{tool_call_id: "tc", surface_id: "s"}) == :none
    end
  end

  describe "refresh_activity/3 — surface freshness" do
    test "re-wraps a declared surface with freshly built messages" do
      event = AgUi.refresh_activity("surface-minimal", MinimalUI)

      assert event["type"] == "ACTIVITY_SNAPSHOT"
      assert event["messageId"] == "surface-minimal"
      assert event["activityType"] == "a2ui-surface"
      assert event["content"] == %{"a2ui_operations" => AshA2ui.Info.build_surface(MinimalUI)}
    end

    test "a refresh reflects records created after the original emission" do
      first = AgUi.refresh_activity("s", MinimalUI, spec_version: "0.9.1")

      name = "fresh-record-#{System.unique_integer([:positive])}"

      Minimal
      |> Ash.Changeset.for_create(:create, %{name: name})
      |> Ash.create!()

      refreshed = AgUi.refresh_activity("s", MinimalUI, spec_version: "0.9.1")

      refute Jason.encode!(first["content"]) =~ name
      assert Jason.encode!(refreshed["content"]) =~ name
    end

    test "rebuilds a Dynamic surface through the server-held struct" do
      {:ok, surface} =
        AshA2ui.Dynamic.resolve(
          %{
            "resource" => "Minimal",
            "title" => "Minimal (designed)",
            "components" => [%{"kind" => "table", "fields" => ["name"]}]
          },
          allowlist: AshA2ui.Dynamic.allowlist([Minimal])
        )

      event = AgUi.refresh_activity("surface-dyn", surface)

      assert event["messageId"] == "surface-dyn"
      assert event["content"] == %{"a2ui_operations" => AshA2ui.Dynamic.build_surface(surface)}
    end
  end

  describe "spec_version override (transport version pinning)" do
    test "a v1.0 surface pinned to 0.9.1 emits the v0.9.1 triple" do
      messages = AshA2ui.Info.build_surface(KitchenSinkV1UI, spec_version: "0.9.1")

      assert [%{"createSurface" => create} | _rest] = messages
      refute Map.has_key?(create, "components")
      assert Enum.any?(messages, &match?(%{"updateComponents" => _}, &1))
      assert Enum.all?(messages, &(&1["version"] == "v0.9.1"))

      for message <- messages, do: SchemaHelper.assert_valid_server_message(message)
    end

    test "a default surface pinned to 1.0 emits the single inline createSurface" do
      assert [%{"createSurface" => create}] =
               AshA2ui.Info.build_surface(MinimalUI, spec_version: "1.0")

      assert Map.has_key?(create, "components")
    end

    test "an invalid override raises" do
      assert_raise ArgumentError, fn ->
        AshA2ui.Info.build_surface(MinimalUI, spec_version: "2.0")
      end
    end
  end
end
