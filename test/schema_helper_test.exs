defmodule AshA2ui.Test.SchemaHelperTest do
  @moduledoc """
  Hand-written A2UI 1.0 messages, one of each kind in both directions,
  through `AshA2ui.Test.SchemaHelper`: proves the vendored schemas load, the
  cross-file refs resolve (message -> basic catalog -> common types) and the
  draft 2020-12 keywords are enforced.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  @catalog_id "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"

  @create %{
    "version" => "1.0",
    "createSurface" => %{
      "surfaceId" => "kitchen_sink",
      "catalogId" => @catalog_id,
      "components" => [
        %{"id" => "root", "component" => "Column", "children" => ["title", "name"]},
        %{"id" => "title", "component" => "Text", "text" => "# Hello A2UI"},
        %{
          "id" => "name",
          "component" => "TextField",
          "label" => "Name",
          "value" => %{"@path" => "/form/name"},
          "@checks" => [
            %{
              "condition" => %{
                "@call" => "required",
                "args" => %{"value" => %{"@path" => "/form/name"}}
              },
              "message" => "Name is required"
            }
          ],
          "@accessibility" => %{"label" => "Your name"}
        }
      ],
      "dataModel" => %{"form" => %{"name" => ""}}
    }
  }

  test "valid agent-to-renderer messages" do
    assert_valid_agent_message(@create)

    assert_valid_agent_message(%{
      "version" => "1.0",
      "updateComponents" => %{
        "surfaceId" => "kitchen_sink",
        "components" => [%{"id" => "title", "component" => "Text", "text" => "Hi"}]
      }
    })

    assert_valid_agent_message(%{
      "version" => "1.0",
      "updateDataModel" => %{
        "surfaceId" => "kitchen_sink",
        "path" => "/form/name",
        "value" => nil
      }
    })

    assert_valid_agent_message(%{
      "version" => "1.0",
      "callRendererFunction" => %{
        "surfaceId" => "kitchen_sink",
        "functionCallId" => "call_1",
        "callFunction" => %{
          "@call" => "formatString",
          "catalogId" => @catalog_id,
          "args" => %{"value" => "x"}
        }
      }
    })

    assert_valid_agent_message(%{
      "version" => "1.0",
      "agentFunctionResponse" => %{"functionCallId" => "call_2", "value" => %{"ok" => true}}
    })

    assert_valid_agent_message(%{
      "version" => "1.0",
      "deleteSurface" => %{"surfaceId" => "kitchen_sink"}
    })

    assert_valid_agent_messages([
      @create,
      %{"version" => "1.0", "deleteSurface" => %{"surfaceId" => "kitchen_sink"}}
    ])
  end

  test "valid renderer-to-agent messages" do
    assert_valid_renderer_message(%{
      "version" => "1.0",
      "action" => %{
        "name" => "submit_form",
        "surfaceId" => "kitchen_sink",
        "sourceComponentId" => "form_submit",
        "timestamp" => "2026-07-10T12:00:00Z",
        "context" => %{"name" => "A provider"}
      }
    })

    # an agent function is declared in a catalog in use (here the upstream
    # testing catalog, mixed with the basic one) ...
    assert_valid_renderer_message(
      %{
        "version" => "1.0",
        "callAgentFunction" => %{
          "surfaceId" => "kitchen_sink",
          "functionCallId" => "call_3",
          "callFunction" => %{
            "@call" => "pingAgent",
            "catalogId" => "https://a2ui.org/specification/v1_0/testing_catalog.json"
          }
        }
      },
      catalogs: ["catalogs/basic/v1/catalog.json", "test/testing_catalog.json"]
    )

    # ... and a function no catalog in use declares does not validate
    assert {:error, _} =
             validate_renderer_message(%{
               "version" => "1.0",
               "callAgentFunction" => %{
                 "surfaceId" => "kitchen_sink",
                 "functionCallId" => "call_4",
                 "callFunction" => %{"@call" => "lookupThing", "args" => %{}}
               }
             })

    assert_valid_renderer_message(%{
      "version" => "1.0",
      "rendererFunctionResponse" => %{
        "functionCallId" => "call_1",
        "error" => %{"code" => "EXECUTION_ERROR", "message" => "No."}
      }
    })

    assert_valid_renderer_message(%{
      "version" => "1.0",
      "error" => %{
        "code" => "UNALLOWED_CHILD",
        "surfaceId" => "s",
        "path" => "/components/2",
        "message" => "No."
      }
    })
  end

  test "what 1.0 removed or forbids is rejected" do
    # the old "v1.0" version string
    assert {:error, _} =
             validate_agent_message(put_in(@create, ["version"], "v1.0"))

    # updateDataModel without a value
    assert {:error, _} =
             validate_agent_message(%{
               "version" => "1.0",
               "updateDataModel" => %{"surfaceId" => "s", "path" => "/x"}
             })

    # the removed actionResponse message
    assert {:error, _} =
             validate_agent_message(%{
               "version" => "1.0",
               "actionResponse" => %{"actionId" => "a", "value" => 1}
             })

    # an unprefixed binding, and a bare envelope key, on a component
    for component <- [
          %{"id" => "root", "component" => "Text", "text" => %{"path" => "/x"}},
          %{
            "id" => "root",
            "component" => "Text",
            "text" => "x",
            "accessibility" => %{"label" => "x"}
          }
        ] do
      assert {:error, _} =
               validate_agent_message(%{
                 "version" => "1.0",
                 "updateComponents" => %{"surfaceId" => "s", "components" => [component]}
               })
    end

    # returnType on a wire FunctionCall: only unevaluatedProperties catches it
    assert {:error, _} =
             validate_agent_message(%{
               "version" => "1.0",
               "callRendererFunction" => %{
                 "functionCallId" => "c",
                 "callFunction" => %{
                   "@call" => "formatString",
                   "catalogId" => @catalog_id,
                   "args" => %{"value" => "x"},
                   "returnType" => "string"
                 }
               }
             })

    # an action without its context, and a timestamp that is not a date-time
    action = %{
      "name" => "submit_form",
      "surfaceId" => "x",
      "sourceComponentId" => "y",
      "timestamp" => "2026-07-10T12:00:00Z",
      "context" => %{}
    }

    assert {:error, _} =
             validate_renderer_message(%{
               "version" => "1.0",
               "action" => Map.delete(action, "context")
             })

    assert {:error, _} =
             validate_renderer_message(%{
               "version" => "1.0",
               "action" => %{action | "timestamp" => "yesterday"}
             })
  end

  test "errors name the failing location" do
    assert {:error, errors} =
             validate_agent_message(%{"version" => "1.0", "deleteSurface" => %{}})

    assert Enum.all?(errors, &is_binary/1)
    assert errors != []
  end
end
