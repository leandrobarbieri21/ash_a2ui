defmodule AshA2ui.V10EncoderTest do
  @moduledoc """
  `AshA2ui.Encoder.V1_0` payload tests — the encoder half of the executable
  v1.0 spec. Every emitted message is validated against the vendored v1.0
  schemas, and the semantic rules the schemas cannot express are asserted
  directly:

    * inline `createSurface` (one message; no create-then-update flash),
    * `wantResponse: true` on every emitted action event,
    * the structured `/ui/response` reserved path (replacing the v0.9.1
      `/ui/action_result` / `/ui/action_result_text` pair; the typed
      `/ui/feedback` stays on both wire versions),
    * no `returnType`/`callableFrom` on wire FunctionCalls (v1.0 dropped
      wire-level function metadata; only draft-2020-12's
      `unevaluatedProperties` would catch it, which our draft-7 validator
      ignores — so it is asserted structurally here),
    * `updateDataModel` always carries `"value"` (in v1.0 an omitted value
      *deletes* the key at path, so an accidental omission is destructive),
    * every generated component id / action name / function name conforms
      to the UAX #31 identifier rule (asserted against the ASCII subset
      `^[A-Za-z_][A-Za-z0-9_]*$` — all generated identifiers are ASCII
      snake_case, a strict subset of `XID_Start`/`XID_Continue`).
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.Encoder.V1_0
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{KitchenSink, KitchenSinkV1UI}

  @catalog_id "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"

  # ASCII subset of UAX #31's ^[\p{XID_Start}_][\p{XID_Continue}]*$
  @identifier ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  defp resolve(opts \\ []), do: ResolvedView.resolve(KitchenSinkV1UI, opts)

  defp encode_surface(records \\ [], opts \\ []) do
    resolve() |> V1_0.encode_surface(records, opts)
  end

  defp create_payload(opts \\ []) do
    [%{"createSurface" => create}] = encode_surface([], opts)
    create
  end

  defp components_by_id(create) do
    Map.new(create["components"], &{&1["id"], &1})
  end

  # Depth-first walk over every map/list in a message tree.
  defp walk(value, fun) when is_map(value) do
    fun.(value)
    Enum.each(value, fn {_key, child} -> walk(child, fun) end)
  end

  defp walk(value, fun) when is_list(value), do: Enum.each(value, &walk(&1, fun))
  defp walk(_scalar, _fun), do: :ok

  describe "encode_surface/3: inline createSurface" do
    test "emits a single schema-valid v1.0 message with inline components and dataModel" do
      assert [message] = encode_surface()
      assert_valid_server_message(message, :v1_0)

      assert %{"version" => "v1.0", "createSurface" => create} = message
      assert create["surfaceId"] == "kitchen_sink_v1"
      assert create["catalogId"] == @catalog_id
      assert is_list(create["components"]) and create["components"] != []
      assert is_map(create["dataModel"])
    end

    test "the component tree matches the v0.9.1 shape (same ids, same root children)" do
      components = create_payload() |> components_by_id()

      assert %{"component" => "Column", "children" => children} = components["root"]

      assert children == [
               "form_slot",
               "status_text",
               "table_heading",
               "create_button",
               "records_list",
               "empty_state",
               "action_result_panel"
             ]

      assert Enum.all?(children, &Map.has_key?(components, &1))
    end

    test "the initial data model seeds the structured /ui/response object" do
      data_model = create_payload()["dataModel"]

      assert data_model["ui"]["response"] == %{
               "status" => "",
               "message" => "",
               "result" => %{},
               "resultText" => ""
             }

      # the experience layer's /ui state passes through the upgrade
      assert data_model["ui"]["feedback"] == %{"kind" => nil, "message" => ""}
      assert data_model["ui"]["intent"] == "browse"
      assert data_model["ui"]["panel"]["visible"] == []
      refute Map.has_key?(data_model["ui"], "action_result")
      refute Map.has_key?(data_model["ui"], "status")

      assert data_model["records"] == []
      assert data_model["form"] == %{}
      assert data_model["errors"] == %{}
    end

    test "surface_properties opt lands as createSurface.surfaceProperties and validates" do
      properties = %{"agentDisplayName" => "Support Agent"}

      assert [message] = encode_surface([], surface_properties: properties)
      assert_valid_server_message(message, :v1_0)
      assert message["createSurface"]["surfaceProperties"] == properties
    end

    test "without the opt no surfaceProperties key is emitted" do
      refute Map.has_key?(create_payload(), "surfaceProperties")
    end
  end

  describe "encode_surface/3: v1.0 semantic rules" do
    test "every action event carries wantResponse: true" do
      events = collect_events(create_payload()["components"])

      assert events != []

      for event <- events do
        assert event["wantResponse"] == true,
               "action event #{inspect(event["name"])} is missing wantResponse: true"
      end
    end

    test "no wire FunctionCall carries returnType or callableFrom" do
      calls = collect_calls(create_payload()["components"])

      # The KitchenSink fixture formats :inserted_at as a date -> formatDate.
      assert Enum.any?(calls, &(&1["call"] == "formatDate"))

      for call <- calls do
        refute Map.has_key?(call, "returnType"),
               "wire FunctionCall #{inspect(call["call"])} carries returnType"

        refute Map.has_key?(call, "callableFrom"),
               "wire FunctionCall #{inspect(call["call"])} carries callableFrom"
      end
    end

    test "result components bind the /ui/response paths, and no v0.9.1 result binding remains" do
      components = create_payload() |> components_by_id()

      # the status line is the typed feedback on both wire versions
      assert components["status_text"]["text"] == %{"path" => "/ui/feedback/message"}
      assert components["action_result_text"]["text"] == %{"path" => "/ui/response/resultText"}

      walk(create_payload()["components"], fn map ->
        case map do
          %{"path" => path} when is_binary(path) ->
            refute path in ["/ui/status", "/ui/action_result", "/ui/action_result_text"],
                   "component tree still binds the v0.9.1 status path #{path}"

          _other ->
            :ok
        end
      end)
    end

    test "every component id, action name, and function name is a UAX #31 identifier" do
      create = create_payload()

      walk(create["components"], fn map ->
        if id = map["id"], do: assert(id =~ @identifier, "component id #{inspect(id)}")

        case map do
          %{"event" => %{"name" => name}} ->
            assert name =~ @identifier, "action name #{inspect(name)}"

          %{"call" => call} when is_binary(call) ->
            assert call == "@index" or call =~ @identifier, "function name #{inspect(call)}"

          _other ->
            :ok
        end
      end)
    end
  end

  describe "encode_data_model/3" do
    test "emits a schema-valid v1.0 updateDataModel with the upgraded ui block" do
      message = resolve() |> V1_0.encode_data_model([], [])

      assert_valid_server_message(message, :v1_0)
      assert message["version"] == "v1.0"

      assert %{"path" => "/", "value" => value} = message["updateDataModel"]

      assert value["ui"]["response"] == %{
               "status" => "",
               "message" => "",
               "result" => %{},
               "resultText" => ""
             }

      assert value["ui"]["feedback"] == %{"kind" => nil, "message" => ""}
      refute Map.has_key?(value["ui"], "action_result_text")
      refute Map.has_key?(value["ui"], "status")
    end

    test "always carries a value key (an omitted value would delete the key in v1.0)" do
      message = resolve() |> V1_0.encode_data_model([], [])
      assert Map.has_key?(message["updateDataModel"], "value")
    end

    test "serializes records exactly like v0.9.1" do
      record = seed_record()

      v1 = resolve() |> V1_0.encode_data_model([record], [])

      v0 =
        KitchenSink
        |> ResolvedView.resolve()
        |> V0_9_1.encode_data_model([record], [])

      assert v1["updateDataModel"]["value"]["records"] ==
               v0["updateDataModel"]["value"]["records"]
    end
  end

  describe "call_function/3" do
    test "builds a schema-valid callFunction message with a unique call id" do
      message = V1_0.call_function("openUrl", %{"url" => "https://example.com"})

      assert_valid_server_message(message, :v1_0)

      assert message["callFunction"] == %{
               "call" => "openUrl",
               "args" => %{"url" => "https://example.com"}
             }

      assert String.starts_with?(message["functionCallId"], "fc_")
      refute Map.has_key?(message, "wantResponse")

      other = V1_0.call_function("openUrl", %{"url" => "https://example.com"})
      refute message["functionCallId"] == other["functionCallId"]
    end

    test "want_response and explicit ids are honored" do
      message = V1_0.call_function("focus", %{}, want_response: true, function_call_id: "fc_1")

      assert message["wantResponse"] == true
      assert message["functionCallId"] == "fc_1"
      assert message["callFunction"] == %{"call" => "focus"}
    end
  end

  describe "v0.9.1 isolation" do
    test "the same resource without spec_version still emits the v0.9.1 triple" do
      messages =
        KitchenSink
        |> ResolvedView.resolve()
        |> V0_9_1.encode_surface([], [])

      assert [
               %{"version" => "v0.9.1", "createSurface" => _},
               %{"version" => "v0.9.1", "updateComponents" => _},
               %{"version" => "v0.9.1", "updateDataModel" => _}
             ] = messages
    end
  end

  defp collect_events(components) do
    collect(components, fn
      %{"event" => %{"name" => _} = event} -> event
      _other -> nil
    end)
  end

  defp collect_calls(components) do
    collect(components, fn
      %{"call" => call} = function_call when is_binary(call) -> function_call
      _other -> nil
    end)
  end

  defp collect(tree, picker) do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    walk(tree, fn map ->
      if picked = picker.(map), do: Agent.update(agent, &[picked | &1])
    end)

    found = agent |> Agent.get(& &1) |> Enum.reverse()
    Agent.stop(agent)
    found
  end

  defp seed_record do
    KitchenSink
    |> Ash.Changeset.for_create(:create, %{
      name: "Widget",
      active: true,
      count: 3,
      price: Decimal.new("19.99"),
      birthday: ~D[2020-02-29],
      scheduled_at: ~U[2026-01-02 03:04:05Z],
      status: :published
    })
    |> Ash.create!()
  end
end
