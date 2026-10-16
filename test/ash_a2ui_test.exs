defmodule AshA2uiTest do
  @moduledoc """
  End-to-end test: resource -> `build_surface` -> simulated client `action`
  envelopes through `ActionHandler.handle/3` -> updated data model, with every
  server->client message validated against the vendored A2UI v0.9.1 schemas.

  Covers both authoring modes: the on-resource `a2ui` block
  (`AshA2ui.Test.KitchenSink`) and the standalone UI module
  (`AshA2ui.Test.MinimalUI` via `for_resource`).
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Info
  alias AshA2ui.Test.{KitchenSink, Minimal, MinimalUI}

  defp envelope(name, surface_id, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => surface_id,
        "sourceComponentId" => "e2e_test",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  test "on-resource block: surface -> submit_form create -> invoke row action -> data model" do
    # 1. Initial surface: ordered, schema-valid message list.
    messages = Info.build_surface(KitchenSink)

    assert [
             %{"createSurface" => %{"surfaceId" => "kitchen_sink"}},
             %{"updateComponents" => _},
             %{"updateDataModel" => %{"path" => "/", "value" => %{"records" => []}}}
           ] = messages

    Enum.each(messages, &assert_valid_server_message/1)

    # 2. Simulated client submit_form (create) through the ActionHandler.
    create_env =
      envelope("submit_form", "kitchen_sink", %{
        "values" => %{"name" => "E2E Provider", "count" => 3, "active" => true}
      })

    assert_valid_client_message(create_env)

    assert {:ok, follow_ups} = ActionHandler.handle(KitchenSink, create_env)
    Enum.each(follow_ups, &assert_valid_server_message/1)

    # the refresh, the cleared buffers, the closed task panel, and the typed
    # success feedback
    assert [
             %{"updateDataModel" => %{"path" => "/records", "value" => [row]}},
             %{"updateDataModel" => %{"path" => "/_empty_visible", "value" => []}},
             %{"updateDataModel" => %{"path" => "/form", "value" => %{}}},
             %{"updateDataModel" => %{"path" => "/errors", "value" => %{}}},
             %{"updateDataModel" => %{"path" => "/ui/action_result", "value" => %{}}},
             %{"updateDataModel" => %{"path" => "/ui/action_result_text", "value" => ""}},
             %{"updateDataModel" => %{"path" => "/ui/intent", "value" => "browse"}},
             %{"updateDataModel" => %{"path" => "/ui/panel", "value" => %{"visible" => []}}},
             %{
               "updateDataModel" => %{
                 "path" => "/ui/feedback",
                 "value" => %{"kind" => "success", "message" => status}
               }
             }
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

    assert_valid_client_message(invoke_env)

    assert {:ok, invoke_follow_ups} = ActionHandler.handle(KitchenSink, invoke_env)
    Enum.each(invoke_follow_ups, &assert_valid_server_message/1)

    assert %{"updateDataModel" => %{"path" => "/records", "value" => []}} =
             hd(invoke_follow_ups)

    # 4. build_data_model reflects the changes (record gone again).
    data_model = Info.build_data_model(KitchenSink)
    assert_valid_server_message(data_model)

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
    Enum.each(error_messages, &assert_valid_server_message/1)

    assert Enum.any?(error_messages, fn
             %{"updateDataModel" => %{"path" => "/errors/name"}} -> true
             _other -> false
           end)

    assert %{"updateDataModel" => %{"path" => "/ui/feedback"}} = List.last(error_messages)
    assert Ash.read!(KitchenSink) == []
  end

  test "standalone UI module: surface -> submit_form create -> data model" do
    # MinimalUI declares the surface for AshA2ui.Test.Minimal via for_resource.
    messages = Info.build_surface(MinimalUI)

    assert [
             %{"createSurface" => %{"surfaceId" => "minimal_standalone"}},
             %{"updateComponents" => %{"components" => components}},
             %{"updateDataModel" => _}
           ] = messages

    Enum.each(messages, &assert_valid_server_message/1)

    # The standalone field override applies.
    assert Enum.any?(components, &(&1["id"] == "records_list"))

    # No form component declared -> submit_form falls back to the resource's
    # primary create action (Track 3 convention).
    env =
      envelope("submit_form", "minimal_standalone", %{
        "values" => %{"name" => "Standalone record"}
      })

    assert {:ok, follow_ups} = ActionHandler.handle(MinimalUI, env)
    Enum.each(follow_ups, &assert_valid_server_message/1)

    assert [%Minimal{name: "Standalone record"}] = Ash.read!(Minimal)

    data_model = Info.build_data_model(MinimalUI)
    assert_valid_server_message(data_model)

    assert %{"updateDataModel" => %{"value" => %{"records" => [row]}}} = data_model
    assert row["name"] == "Standalone record"
  end
end
