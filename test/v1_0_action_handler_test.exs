defmodule AshA2ui.V10ActionHandlerTest.TestDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule AshA2ui.V10ActionHandlerTest.Gadget do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.V10ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    action :generate_secret, :map do
      argument :record_id, :uuid, allow_nil?: true

      run fn input, _context ->
        {:ok, %{secret: "s3cr3t", record_id: input.arguments[:record_id]}}
      end
    end
  end

  a2ui do
    surface_id "gadget_v1"
    spec_version "1.0"

    component :table do
      fields [:name]
      read_action :read
      row_actions [:generate_secret, :destroy]
    end
  end
end

defmodule AshA2ui.V10ActionHandlerTest.Protected do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.V10ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  a2ui do
    surface_id "protected_v1"
    spec_version "1.0"

    component :table do
      fields [:name]
      read_action :read
    end

    component :form do
      fields [:name]
      create_action :create
      update_action :update
    end
  end
end

defmodule AshA2ui.V10ActionHandlerTest do
  @moduledoc """
  The v1.0 `actionResponse` contract of `AshA2ui.ActionHandler` — the
  handler half of the executable v1.0 spec:

    * a v1.0 action envelope carrying an `actionId` receives a schema-valid
      `actionResponse` message as the *first* follow-up, `{"value": ...}` on
      success and `{"error": {code, message}}` on failure, echoing the
      client's `actionId` verbatim;
    * the response mirrors the structured `/ui/response` data-model write
      (the v1.0 replacement of the `/ui/status` / `/ui/action_result` /
      `/ui/action_result_text` trio), with stable machine-readable codes
      (`VALIDATION_FAILED`, `UNAUTHORIZED`, `INVALID_ACTION`,
      `ACTION_FAILED`);
    * every follow-up message is a valid v1.0 server->client message;
    * actions *without* an `actionId` (wantResponse false) and v0.9.1
      surfaces get no `actionResponse` — the v0.9.1 wire is byte-identical
      to before.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{KitchenSink, KitchenSinkV1UI}
  alias AshA2ui.V10ActionHandlerTest.{Gadget, Protected}

  @actor %{id: "test-actor"}

  defp envelope(name, surface_id, context, opts \\ []) do
    action =
      %{
        "name" => name,
        "surfaceId" => surface_id,
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
      |> maybe_action_id(opts[:action_id])

    %{"version" => "v1.0", "action" => action}
  end

  defp maybe_action_id(action, nil), do: action

  defp maybe_action_id(action, action_id),
    do: Map.merge(action, %{"actionId" => action_id, "wantResponse" => true})

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp assert_all_valid(messages) do
    Enum.each(messages, &assert_valid_server_message(&1, :v1_0))
    messages
  end

  describe "actionResponse on success" do
    test "a submit_form with an actionId gets a value response echoing the id" do
      env =
        envelope("submit_form", "kitchen_sink_v1", %{"values" => %{"name" => "Widget"}},
          action_id: "action-123"
        )

      assert_valid_client_message(env, :v1_0)

      assert {:ok, [response | rest]} = ActionHandler.handle(KitchenSinkV1UI, env)
      assert_all_valid([response | rest])

      assert %{
               "version" => "v1.0",
               "actionId" => "action-123",
               "actionResponse" => %{"value" => value}
             } = response

      assert value["status"] == "ok"
      assert value["message"] =~ ~r/creat/i

      # The response mirrors the structured /ui/response data-model write.
      assert value == value_at(rest, "/ui/response")
    end

    test "a map-returning generic action carries result + resultText in the response value" do
      record = Ash.create!(Gadget, %{name: "G1"}, authorize?: false)

      env =
        envelope(
          "invoke",
          "gadget_v1",
          %{"action" => "generate_secret", "recordId" => record.id},
          action_id: "action-777"
        )

      assert {:ok, [response | rest]} = ActionHandler.handle(Gadget, env)
      assert_all_valid([response | rest])

      assert %{"actionResponse" => %{"value" => value}} = response
      assert value["status"] == "ok"
      assert value["result"] == %{"secret" => "s3cr3t", "record_id" => record.id}
      assert value["resultText"] =~ "Secret: s3cr3t"
      assert value == value_at(rest, "/ui/response")
    end

    test "success writes /ui/response instead of the v0.9.1 status trio" do
      env =
        envelope("submit_form", "kitchen_sink_v1", %{"values" => %{"name" => "W"}},
          action_id: "a-1"
        )

      assert {:ok, messages} = ActionHandler.handle(KitchenSinkV1UI, env)

      assert %{"status" => "ok"} = value_at(messages, "/ui/response")

      for legacy <- ["/ui/status", "/ui/action_result", "/ui/action_result_text"] do
        refute Enum.any?(messages, &(&1["updateDataModel"]["path"] == legacy)),
               "v1.0 follow-ups still write the legacy #{legacy} path"
      end
    end
  end

  describe "actionResponse on failure" do
    test "a validation error yields an error response with code VALIDATION_FAILED" do
      env = envelope("submit_form", "kitchen_sink_v1", %{"values" => %{}}, action_id: "a-400")

      assert {:error, [response | rest]} = ActionHandler.handle(KitchenSinkV1UI, env)
      assert_all_valid([response | rest])

      assert %{
               "actionId" => "a-400",
               "actionResponse" => %{
                 "error" => %{"code" => "VALIDATION_FAILED", "message" => message}
               }
             } = response

      assert is_binary(message) and message != ""

      assert value_at(rest, "/errors/name") =~ "required"

      assert %{"status" => "error", "code" => "VALIDATION_FAILED"} =
               value_at(rest, "/ui/response")
    end

    test "a forbidden action yields code UNAUTHORIZED without leaking policy details" do
      env =
        envelope("submit_form", "protected_v1", %{"values" => %{"name" => "X"}},
          action_id: "a-401"
        )

      assert {:error, [response | rest]} = ActionHandler.handle(Protected, env, actor: nil)
      assert_all_valid([response | rest])

      assert %{"actionResponse" => %{"error" => %{"code" => "UNAUTHORIZED"}}} = response

      refute Enum.any?(
               rest,
               &String.starts_with?(&1["updateDataModel"]["path"] || "", "/errors/")
             )
    end

    test "an unknown action name yields code INVALID_ACTION" do
      env = envelope("bogus_action", "kitchen_sink_v1", %{}, action_id: "a-404")

      assert {:error, [response | _rest]} = ActionHandler.handle(KitchenSinkV1UI, env)
      assert %{"actionResponse" => %{"error" => %{"code" => "INVALID_ACTION"}}} = response
    end

    test "a malformed envelope still answers the pending actionId" do
      malformed = %{"version" => "v1.0", "action" => %{"actionId" => "a-500", "context" => %{}}}

      assert {:error, [response | rest]} = ActionHandler.handle(KitchenSinkV1UI, malformed)
      assert_all_valid([response | rest])

      assert %{
               "actionId" => "a-500",
               "actionResponse" => %{"error" => %{"code" => "INVALID_ACTION"}}
             } = response
    end
  end

  describe "no actionId / v0.9.1 isolation" do
    test "a v1.0 action without an actionId gets no actionResponse" do
      env = envelope("submit_form", "kitchen_sink_v1", %{"values" => %{"name" => "W"}})

      assert {:ok, messages} = ActionHandler.handle(KitchenSinkV1UI, env)
      refute Enum.any?(messages, &Map.has_key?(&1, "actionResponse"))
    end

    test "a v0.9.1 surface never emits an actionResponse, even if the client sends an actionId" do
      env =
        envelope("submit_form", "kitchen_sink", %{"values" => %{"name" => "W"}},
          action_id: "ignored"
        )

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)

      refute Enum.any?(messages, &Map.has_key?(&1, "actionResponse"))
      assert Enum.all?(messages, &(&1["version"] == "v0.9.1"))
      assert is_binary(value_at(messages, "/ui/feedback")["message"])
    end

    test "actionResponses for distinct actionIds echo each id exactly once" do
      for id <- ["id-1", "id-2", "id-3"] do
        env =
          envelope("submit_form", "kitchen_sink_v1", %{"values" => %{"name" => id}},
            action_id: id
          )

        assert {:ok, messages} = ActionHandler.handle(KitchenSinkV1UI, env)

        assert [%{"actionId" => ^id}] = Enum.filter(messages, &Map.has_key?(&1, "actionResponse"))
      end
    end
  end

  describe "protected resource with actor" do
    test "an authorized action succeeds with a value response" do
      env =
        envelope("submit_form", "protected_v1", %{"values" => %{"name" => "Allowed"}},
          action_id: "a-200"
        )

      assert {:ok, [response | _rest]} = ActionHandler.handle(Protected, env, actor: @actor)
      assert %{"actionResponse" => %{"value" => %{"status" => "ok"}}} = response
    end
  end
end
