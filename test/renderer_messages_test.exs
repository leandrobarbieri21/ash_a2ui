defmodule AshA2ui.RendererMessagesTest do
  @moduledoc """
  The A2UI 1.0 renderer-to-agent half of `AshA2ui.ActionHandler.handle/3`:

    * `callAgentFunction` calling `ashAction` dispatches like an action and
      ends its follow-ups with the matching `agentFunctionResponse`;
    * a function call the agent does not run, or one that fails its schema,
      is answered with `UNKNOWN_FUNCTION` or `INVALID_FUNCTION_CALL`;
    * `rendererFunctionResponse` and `error` are validated and produce no
      follow-ups;
    * a plain `action` event is refused with an `UNKNOWN_FUNCTION`
      feedback error and runs nothing;
    * anything else, including a wrong version, is refused with none.

  Every follow-up is validated against the vendored 1.0 schemas, and every
  refused message is checked to fail the renderer-to-agent schema too, so
  the handler and the spec agree on what is malformed.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper
  import ExUnit.CaptureLog

  alias AshA2ui.ActionHandler
  alias AshA2ui.ActionHandlerTest.{Gadget, Protected}
  alias AshA2ui.Encoder
  alias AshA2ui.Test.{KitchenSink, Messages, Paginated}

  @catalogs Messages.catalogs()

  defp assert_all_valid(messages) do
    Enum.each(messages, &assert_valid_agent_message(&1, catalogs: @catalogs))
    assert_valid_agent_messages(messages, catalogs: @catalogs)
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp feedback_writes(messages),
    do: for(%{"updateDataModel" => %{"path" => "/ui/feedback", "value" => v}} <- messages, do: v)

  defp invalid_message?(message),
    do: match?({:error, _errors}, validate_renderer_message(message, catalogs: @catalogs))

  # A callAgentFunction whose body is `body` merged over a valid ashAction call.
  defp call_with(body, opts \\ []) do
    call = Messages.call("submit_form", "kitchen_sink", %{"values" => %{"name" => "X"}}, opts)
    update_in(call, ["callAgentFunction"], &Map.merge(&1, body))
  end

  defp call_function(function, opts \\ []) do
    call_with(%{"callFunction" => function}, opts)
  end

  describe "callAgentFunction ashAction" do
    test "dispatches the action and answers last, with the settled feedback as the value" do
      call =
        Messages.call("submit_form", "kitchen_sink", %{"values" => %{"name" => "Called"}},
          id: "call-1"
        )

      assert_valid_renderer_message(call, catalogs: @catalogs)

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, call)
      assert_all_valid(messages)
      assert [%{name: "Called"}] = Ash.read!(KitchenSink, authorize?: false)

      assert %{"agentFunctionResponse" => response} = List.last(messages)
      assert response["functionCallId"] == "call-1"

      # The data model, feedback included, is written before the response.
      assert [feedback] = feedback_writes(messages)
      assert response["value"] == feedback

      assert %{
               "kind" => "success",
               "code" => "",
               "functionCallId" => "call-1",
               "result" => %{},
               "resultText" => ""
             } = feedback

      assert feedback["message"] =~ ~r/creat/i
      assert [%{"name" => "Called"}] = value_at(messages, "/records")
    end

    test "a validation failure answers VALIDATION_FAILED with the feedback's message" do
      call = Messages.call("submit_form", "kitchen_sink", %{"values" => %{}}, id: "call-2")

      assert {:error, messages} = ActionHandler.handle(KitchenSink, call)
      assert_all_valid(messages)

      assert value_at(messages, "/errors/name")
      feedback = Messages.feedback(messages)

      assert %{"kind" => "error", "code" => "VALIDATION_FAILED", "functionCallId" => "call-2"} =
               feedback

      assert Messages.response(messages) == %{
               "functionCallId" => "call-2",
               "error" => %{"code" => "VALIDATION_FAILED", "message" => feedback["message"]}
             }
    end

    test "a forbidden write answers FORBIDDEN" do
      call = Messages.call("submit_form", "protected", %{"values" => %{"name" => "No"}})

      assert {:error, messages} = ActionHandler.handle(Protected, call)
      assert_all_valid(messages)
      assert %{"error" => %{"code" => "FORBIDDEN"}} = Messages.response(messages)
    end

    test "an unknown action name answers UNKNOWN_ACTION" do
      call = Messages.call("explode", "kitchen_sink", %{})

      assert {:error, messages} = ActionHandler.handle(KitchenSink, call)
      assert_all_valid(messages)
      assert %{"error" => %{"code" => "UNKNOWN_ACTION"}} = Messages.response(messages)
    end

    test "a write on a surface pinned to an instant answers READ_ONLY_AS_OF" do
      call = Messages.call("submit_form", "kitchen_sink", %{"values" => %{"name" => "Then"}})

      assert {:error, messages} =
               ActionHandler.handle(KitchenSink, call, as_of: ~U[2026-01-01 00:00:00Z])

      assert_all_valid(messages)
      assert %{"error" => %{"code" => "READ_ONLY_AS_OF"}} = Messages.response(messages)
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end

    test "a generic action's map result is in the response value" do
      record = Ash.create!(Gadget, %{name: "G"}, authorize?: false)

      call =
        Messages.call("invoke", "gadget", %{
          "action" => "generate_secret",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(Gadget, call)
      assert_all_valid(messages)

      assert %{"value" => %{"result" => %{"secret" => "s3cr3t"}, "resultText" => text}} =
               Messages.response(messages)

      assert text =~ "Secret: s3cr3t"
    end

    test "a quiet action (a query) leaves the feedback alone and answers an empty value" do
      call = Messages.call("query", "paginated", %{"query" => %{}}, id: "call-q")

      assert {:ok, messages} = ActionHandler.handle(Paginated, call)
      assert_all_valid(messages)

      assert feedback_writes(messages) == []
      assert Messages.response(messages) == %{"functionCallId" => "call-q", "value" => %{}}
    end

    test "a quiet action's failure still writes its feedback under the call's id" do
      call =
        Messages.call("query", "paginated", %{"query" => %{"sort" => "nope"}}, id: "call-qe")

      assert {:error, messages} = ActionHandler.handle(Paginated, call)
      assert_all_valid(messages)

      assert [%{"kind" => "error", "functionCallId" => "call-qe"}] = feedback_writes(messages)
      assert %{"error" => %{"code" => _code}} = Messages.response(messages)
    end

    test "the quiet actions are the ones the shipped hook writes no pending state for" do
      source = File.read!("priv/js/ash_a2ui_protocol.js")

      [_all, list] =
        Regex.run(~r/export const QUIET_ACTIONS = Object\.freeze\(\[([^\]]*)\]/, source)

      names = Regex.scan(~r/"([a-z_]+)"/, list, capture: :all_but_first) |> List.flatten()

      assert Enum.sort(names) == Enum.sort(ActionHandler.quiet_actions())
    end

    test "a plain action event is refused with UNKNOWN_FUNCTION and runs nothing" do
      action = Messages.action("submit_form", "kitchen_sink", %{"values" => %{"name" => "Event"}})
      assert_valid_renderer_message(action)

      {result, log} = with_log(fn -> ActionHandler.handle(KitchenSink, action) end)

      assert {:error, messages} = result
      assert_all_valid(messages)
      assert log =~ "Refused an A2UI action event"
      refute Messages.response(messages)

      assert %{"kind" => "error", "code" => "UNKNOWN_FUNCTION", "functionCallId" => ""} =
               Messages.feedback(messages)

      assert Ash.read!(KitchenSink, authorize?: false) == []
    end

    test "a call without a catalogId resolves to ashAction by name" do
      call =
        "submit_form"
        |> Messages.call("kitchen_sink", %{"values" => %{"name" => "Default catalog"}})
        |> update_in(["callAgentFunction", "callFunction"], &Map.delete(&1, "catalogId"))

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, call)
      assert %{"value" => %{"kind" => "success"}} = Messages.response(messages)
    end
  end

  describe "refused function calls" do
    # Each answer is an agentFunctionResponse error under the call's id, plus
    # an error feedback carrying the id, so the renderer's pending state for
    # the call settles. Nothing reaches Ash.
    defp assert_refused(call, code) do
      call_id = call["callAgentFunction"]["functionCallId"]

      {result, log} = with_log(fn -> ActionHandler.handle(KitchenSink, call) end)
      assert {:error, messages} = result
      assert_all_valid(messages)
      assert log =~ code

      assert %{"functionCallId" => ^call_id, "error" => %{"code" => ^code, "message" => message}} =
               Messages.response(messages)

      assert %{"kind" => "error", "code" => ^code, "functionCallId" => ^call_id} =
               Messages.feedback(messages)

      assert %{"agentFunctionResponse" => _response} = List.last(messages)
      assert message != ""
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end

    test "an unknown function is UNKNOWN_FUNCTION" do
      call =
        call_function(%{
          "@call" => "fetchFxRate",
          "catalogId" => Encoder.ash_catalog_id(),
          "args" => %{}
        })

      assert invalid_message?(call)
      assert_refused(call, "UNKNOWN_FUNCTION")
    end

    test "a rendererOnly basic-catalog function is not an agent function: UNKNOWN_FUNCTION" do
      call =
        call_function(%{
          "@call" => "formatString",
          "catalogId" => Encoder.basic_catalog_id(),
          "args" => %{"value" => "Hello"}
        })

      # A well-formed call to a function the catalog declares for the renderer.
      assert_valid_renderer_message(call, catalogs: @catalogs)
      assert_refused(call, "UNKNOWN_FUNCTION")
    end

    test "the agentOnly downloadFile runs on the renderer, never the agent: UNKNOWN_FUNCTION" do
      call =
        call_function(%{
          "@call" => "downloadFile",
          "catalogId" => Encoder.ash_catalog_id(),
          "args" => %{"filename" => "x.csv", "dataUrl" => "data:text/csv;base64,"}
        })

      assert_valid_renderer_message(call, catalogs: @catalogs)
      assert_refused(call, "UNKNOWN_FUNCTION")
    end

    test "ashAction under another catalog id is UNKNOWN_FUNCTION" do
      call =
        call_function(%{
          "@call" => "ashAction",
          "catalogId" => Encoder.basic_catalog_id(),
          "args" => %{"name" => "submit_form"}
        })

      # The schema checks the call against every active catalog's functions
      # at once, so only the agent can tell the catalog id is wrong.
      assert_valid_renderer_message(call, catalogs: @catalogs)
      assert_refused(call, "UNKNOWN_FUNCTION")
    end

    test "a call without callFunction is INVALID_FUNCTION_CALL" do
      call =
        "submit_form"
        |> Messages.call("kitchen_sink", %{})
        |> update_in(["callAgentFunction"], &Map.delete(&1, "callFunction"))

      assert invalid_message?(call)
      assert_refused(call, "INVALID_FUNCTION_CALL")
    end

    test "an empty function name is INVALID_FUNCTION_CALL" do
      call =
        call_function(%{"@call" => "", "catalogId" => Encoder.ash_catalog_id(), "args" => %{}})

      assert invalid_message?(call)
      assert_refused(call, "INVALID_FUNCTION_CALL")
    end

    test "a wire returnType is INVALID_FUNCTION_CALL" do
      call =
        call_function(%{
          "@call" => "ashAction",
          "catalogId" => Encoder.ash_catalog_id(),
          "args" => %{"name" => "submit_form"},
          "returnType" => "object"
        })

      assert invalid_message?(call)
      assert_refused(call, "INVALID_FUNCTION_CALL")
    end

    test "an undeclared key on callAgentFunction is INVALID_FUNCTION_CALL" do
      call = call_with(%{"undeclared" => true})

      assert invalid_message?(call)
      assert_refused(call, "INVALID_FUNCTION_CALL")
    end

    test "an empty surfaceId is INVALID_FUNCTION_CALL" do
      call = call_with(%{"surfaceId" => ""})
      assert_refused(call, "INVALID_FUNCTION_CALL")
    end

    for {label, args} <- [
          {"args that are not an object", "submit_form"},
          {"args without a name", %{"context" => %{}}},
          {"a non-string name", %{"name" => 7}},
          {"an undeclared argument", %{"name" => "submit_form", "actionId" => "a-1"}},
          {"a context that is not an object", %{"name" => "submit_form", "context" => [1]}},
          {"a non-string sourceComponentId", %{"name" => "submit_form", "sourceComponentId" => 1}}
        ] do
      @args args
      test "ashAction with #{label} is INVALID_FUNCTION_CALL" do
        call =
          call_function(%{
            "@call" => "ashAction",
            "catalogId" => Encoder.ash_catalog_id(),
            "args" => @args
          })

        assert invalid_message?(call)
        assert_refused(call, "INVALID_FUNCTION_CALL")
      end
    end

    test "a call without a functionCallId cannot be answered: no follow-ups" do
      call =
        "submit_form"
        |> Messages.call("kitchen_sink", %{"values" => %{"name" => "Unanswerable"}})
        |> update_in(["callAgentFunction"], &Map.delete(&1, "functionCallId"))

      assert invalid_message?(call)

      assert capture_log(fn -> assert {:error, []} = ActionHandler.handle(KitchenSink, call) end) =~
               "without a functionCallId"

      assert Ash.read!(KitchenSink, authorize?: false) == []
    end

    test "an empty functionCallId cannot be answered either" do
      call = call_with(%{}, id: "")

      with_log(fn -> assert {:error, []} = ActionHandler.handle(KitchenSink, call) end)
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end
  end

  describe "malformed messages" do
    # Refused before anything is dispatched: no follow-ups, a logged reason.
    defp assert_malformed(message) do
      assert invalid_message?(message)
      {result, log} = with_log(fn -> ActionHandler.handle(KitchenSink, message) end)
      assert result == {:error, []}
      assert log =~ "Refused an A2UI renderer message"
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end

    defp submit,
      do: Messages.call("submit_form", "kitchen_sink", %{"values" => %{"name" => "M"}})

    test ~s(the version must be "1.0": "v1.0", "0.9", "v0.9.1" and none are refused) do
      for version <- ["v1.0", "0.9", "v0.9.1", 1.0] do
        assert_malformed(%{submit() | "version" => version})
      end

      assert_malformed(Map.delete(submit(), "version"))
    end

    test "the version check comes first, so a function call with another version is not answered" do
      call = Messages.call("submit_form", "kitchen_sink", %{"values" => %{"name" => "M"}})
      assert_malformed(%{call | "version" => "0.9"})
    end

    test "an extra top-level key is refused" do
      assert_malformed(Map.put(submit(), "extra", true))
    end

    test "an agent-to-renderer message is not a renderer message" do
      assert_malformed(%{
        "version" => "1.0",
        "updateComponents" => %{"surfaceId" => "kitchen_sink", "components" => []}
      })
    end

    test "the 0.9-era actionResponse is not a renderer message" do
      assert_malformed(%{
        "version" => "1.0",
        "actionResponse" => %{"actionId" => "a-1", "value" => %{}}
      })
    end

    test "something that is not a JSON object is refused" do
      with_log(fn ->
        assert {:error, []} = ActionHandler.handle(KitchenSink, "submit_form")
        assert {:error, []} = ActionHandler.handle(KitchenSink, nil)
      end)
    end
  end

  describe "rendererFunctionResponse" do
    defp respond(body, opts \\ []) do
      message = %{"version" => "1.0", "rendererFunctionResponse" => body}
      test_pid = self()

      with_log(fn ->
        ActionHandler.handle(
          KitchenSink,
          message,
          Keyword.put_new(opts, :on_function_response, &send(test_pid, {:response, &1}))
        )
      end)
      |> elem(0)
    end

    test "a value response goes to the callback, with no follow-ups" do
      body = %{"functionCallId" => "fc_1", "value" => nil}
      assert_valid_renderer_message(%{"version" => "1.0", "rendererFunctionResponse" => body})

      assert respond(body) == {:ok, []}
      assert_received {:response, ^body}
    end

    test "an error response goes to the callback" do
      body = %{
        "functionCallId" => "fc_2",
        "error" => %{"code" => "INVALID_FUNCTION_CALL", "message" => "not registered"}
      }

      assert respond(body) == {:ok, []}
      assert_received {:response, ^body}
    end

    test "without a callback a valid response is accepted and ignored" do
      assert respond(%{"functionCallId" => "fc_3", "value" => 1}, on_function_response: nil) ==
               {:ok, []}
    end

    for {label, body} <- [
          {"both value and error",
           %{
             "functionCallId" => "fc",
             "value" => 1,
             "error" => %{"code" => "X", "message" => "m"}
           }},
          {"neither value nor error", %{"functionCallId" => "fc"}},
          {"no functionCallId", %{"value" => 1}},
          {"an empty functionCallId", %{"functionCallId" => "", "value" => 1}},
          {"an error without a message",
           %{"functionCallId" => "fc", "error" => %{"code" => "X"}}},
          {"an undeclared key", %{"functionCallId" => "fc", "value" => 1, "extra" => true}}
        ] do
      @body body
      test "a response with #{label} is refused and not handed on" do
        assert respond(@body) == {:error, []}
        refute_received {:response, _body}
      end
    end
  end

  describe "renderer error" do
    defp report(error) do
      message = %{"version" => "1.0", "error" => error}
      with_log(fn -> ActionHandler.handle(KitchenSink, message) end)
    end

    for code <- ~w(VALIDATION_FAILED UNALLOWED_PARENT UNALLOWED_CHILD) do
      @code code
      test "#{code} with surfaceId and path is logged by code, surface and path only" do
        error = %{
          "code" => @code,
          "surfaceId" => "kitchen_sink",
          "path" => "/components/3/child",
          "message" => "secret-value-#{@code}"
        }

        assert_valid_renderer_message(%{"version" => "1.0", "error" => error})
        assert {{:ok, []}, log} = report(error)
        assert log =~ "A2UI renderer error #{@code}"
        assert log =~ ~s(surfaceId="kitchen_sink")
        assert log =~ ~s(path="/components/3/child")
        refute log =~ "secret-value-#{@code}"
      end

      test "#{code} without a path is refused" do
        error = %{"code" => @code, "surfaceId" => "kitchen_sink", "message" => "m"}
        refute match?(:ok, validate_renderer_message(%{"version" => "1.0", "error" => error}))
        assert {{:error, []}, _log} = report(error)
      end
    end

    test "another code may name the function call it is about" do
      error = %{"code" => "EXPRESSION_ERROR", "functionCallId" => "fc_9", "message" => "m"}

      assert_valid_renderer_message(%{"version" => "1.0", "error" => error})
      assert {{:ok, []}, log} = report(error)
      assert log =~ ~s(functionCallId="fc_9")
    end

    test "another code naming a surface is accepted" do
      error = %{"code" => "EXPRESSION_ERROR", "surfaceId" => "kitchen_sink", "message" => "m"}
      assert {{:ok, []}, _log} = report(error)
    end

    test "an error carrying both surfaceId and functionCallId is refused" do
      error = %{
        "code" => "EXPRESSION_ERROR",
        "surfaceId" => "kitchen_sink",
        "functionCallId" => "fc_9",
        "message" => "m"
      }

      refute match?(:ok, validate_renderer_message(%{"version" => "1.0", "error" => error}))
      assert {{:error, []}, _log} = report(error)
    end

    test "an error carrying neither is refused" do
      error = %{"code" => "EXPRESSION_ERROR", "message" => "m"}
      refute match?(:ok, validate_renderer_message(%{"version" => "1.0", "error" => error}))
      assert {{:error, []}, _log} = report(error)
    end

    test "an error without a message is refused" do
      assert {{:error, []}, _log} = report(%{"code" => "EXPRESSION_ERROR", "surfaceId" => "s"})
    end
  end
end
