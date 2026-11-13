defmodule AshA2uiTest do
  @moduledoc """
  End-to-end test: resource -> `build_surface` -> simulated client `action`
  envelopes through `ActionHandler.handle/3` -> updated data model, with every
  server->client message validated against the vendored A2UI 1.0 schemas.

  Covers both authoring modes: the on-resource `a2ui` block
  (`AshA2ui.Test.KitchenSink`) and the standalone UI module
  (`AshA2ui.Test.MinimalUI` via `for_resource`).
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Info
  alias AshA2ui.Test.{KitchenSink, Messages, Minimal, MinimalUI}

  defp envelope(name, surface_id, context) do
    Messages.call(name, surface_id, context, source: "e2e_test")
  end

  test "on-resource block: surface -> submit_form create -> invoke row action -> data model" do
    # 1. Initial surface: one schema-valid inline createSurface.
    messages = Info.build_surface(KitchenSink)

    assert [
             %{
               "createSurface" => %{
                 "surfaceId" => "kitchen_sink",
                 "components" => [_ | _],
                 "dataModel" => %{"records" => []}
               }
             }
           ] = messages

    Enum.each(messages, &assert_valid_agent_message/1)

    # 2. Simulated client submit_form (create) through the ActionHandler.
    create_env =
      envelope("submit_form", "kitchen_sink", %{
        "values" => %{"name" => "E2E Provider", "count" => 3, "active" => true}
      })

    assert_valid_renderer_message(create_env)

    assert {:ok, follow_ups} = ActionHandler.handle(KitchenSink, create_env)
    Enum.each(follow_ups, &assert_valid_agent_message/1)

    # the refresh, the cleared buffers, the closed task panel, and the typed
    # success feedback
    assert [
             %{"updateDataModel" => %{"path" => "/records", "value" => [row]}},
             %{"updateDataModel" => %{"path" => "/_empty_visible", "value" => []}},
             %{"updateDataModel" => %{"path" => "/form", "value" => %{}}},
             %{"updateDataModel" => %{"path" => "/errors", "value" => %{}}},
             %{"updateDataModel" => %{"path" => "/ui/intent", "value" => "browse"}},
             %{"updateDataModel" => %{"path" => "/ui/panel", "value" => %{"visible" => []}}},
             %{
               "updateDataModel" => %{
                 "path" => "/ui/feedback",
                 "value" => %{"kind" => "success", "message" => status}
               }
             },
             %{"agentFunctionResponse" => %{"value" => %{"kind" => "success"}}}
           ] = follow_ups

    assert row["name"] == "E2E Provider"
    assert row["count"] == 3
    assert status =~ "Created"

    # The record actually persisted through the normal Ash action layer.
    assert [%KitchenSink{name: "E2E Provider", count: 3, active: true} = record] =
             Ash.read!(KitchenSink)

    # 3. Invoke a row action (destroy, listed in the table's row_actions).
    invoke_env =
      envelope("invoke", "kitchen_sink", %{"action" => "destroy", "recordId" => record.id})

    assert_valid_renderer_message(invoke_env)

    assert {:ok, invoke_follow_ups} = ActionHandler.handle(KitchenSink, invoke_env)
    Enum.each(invoke_follow_ups, &assert_valid_agent_message/1)

    assert %{"updateDataModel" => %{"path" => "/records", "value" => []}} =
             hd(invoke_follow_ups)

    # 4. build_data_model reflects the changes (record gone again).
    data_model = Info.build_data_model(KitchenSink)
    assert_valid_agent_message(data_model)

    assert %{
             "updateDataModel" => %{
               "surfaceId" => "kitchen_sink",
               "path" => "/",
               "value" => %{"records" => []}
             }
           } = data_model
  end

  test "validation errors round-trip on the reserved /errors paths" do
    # name is allow_nil?: false — submitting without it must fail per-field.
    env = envelope("submit_form", "kitchen_sink", %{"values" => %{"count" => 1}})

    assert {:error, error_messages} = ActionHandler.handle(KitchenSink, env)
    Enum.each(error_messages, &assert_valid_agent_message/1)

    assert Enum.any?(error_messages, fn
             %{"updateDataModel" => %{"path" => "/errors/name"}} -> true
             _other -> false
           end)

    assert [
             %{"agentFunctionResponse" => %{"error" => %{"code" => "VALIDATION_FAILED"}}},
             %{"updateDataModel" => %{"path" => "/ui/feedback"}} | _earlier
           ] = Enum.reverse(error_messages)

    assert Ash.read!(KitchenSink) == []
  end

  test "standalone UI module: surface -> submit_form create -> data model" do
    # MinimalUI declares the surface for AshA2ui.Test.Minimal via for_resource.
    messages = Info.build_surface(MinimalUI)

    assert [
             %{
               "createSurface" => %{
                 "surfaceId" => "minimal_standalone",
                 "components" => components,
                 "dataModel" => _
               }
             }
           ] = messages

    Enum.each(messages, &assert_valid_agent_message/1)

    # The standalone field override applies.
    assert Enum.any?(components, &(&1["id"] == "records_list"))

    # No form component declared -> submit_form falls back to the resource's
    # primary create action (Track 3 convention).
    env =
      envelope("submit_form", "minimal_standalone", %{
        "values" => %{"name" => "Standalone record"}
      })

    assert {:ok, follow_ups} = ActionHandler.handle(MinimalUI, env)
    Enum.each(follow_ups, &assert_valid_agent_message/1)

    assert [%Minimal{name: "Standalone record"}] = Ash.read!(Minimal)

    data_model = Info.build_data_model(MinimalUI)
    assert_valid_agent_message(data_model)

    assert %{"updateDataModel" => %{"value" => %{"records" => [row]}}} = data_model
    assert row["name"] == "Standalone record"
  end
end
