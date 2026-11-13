defmodule AshA2ui.EncoderTest do
  @moduledoc """
  `AshA2ui.Encoder` payload tests: every message is validated against
  the vendored A2UI 1.0 schemas via `SchemaHelper.assert_valid_agent_message/2`,
  plus targeted structural assertions on the emitted component tree, the
  action contract, and record serialization. The rules the schemas cannot
  express are asserted directly:

    * `updateDataModel` always carries `"value"` (an omitted value deletes
      the key at path);
    * no wire function call carries `returnType`;
    * every generated component id, action name and function name is a
      UAX #31 identifier (asserted against the ASCII subset
      `^[A-Za-z_][A-Za-z0-9_]*$`; generated identifiers are ASCII
      snake_case).
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import AshA2ui.Test.Surface

  alias AshA2ui.Encoder
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{KitchenSink, Minimal}

  @catalog_id "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
  @ash_catalog_id "https://github.com/lukegalea/ash_a2ui/catalogs/ash_a2ui/v1"

  # ASCII subset of UAX #31's ^[\p{XID_Start}_][\p{XID_Continue}]*$
  @identifier ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  # A struct with NO Jason implementation anywhere — what a custom Ash type
  # (or a host lib's value type) might drop into an attribute.
  defmodule UnsupportedValue do
    @moduledoc false
    defstruct [:payload]
  end

  defmodule NoRead do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
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
      defaults create: :*
    end

    a2ui do
      component :table do
        fields [:name]
      end
    end
  end

  defp encode_kitchen_sink(records \\ []) do
    KitchenSink |> ResolvedView.resolve() |> Encoder.encode_surface(records, [])
  end

  # Depth-first walk over every map in a message tree, collecting what
  # `picker` returns.
  defp collect(value, picker) when is_map(value) do
    List.wrap(picker.(value)) ++
      Enum.flat_map(value, fn {_key, child} -> collect(child, picker) end)
  end

  defp collect(value, picker) when is_list(value), do: Enum.flat_map(value, &collect(&1, picker))
  defp collect(_scalar, _picker), do: []

  defp calls(tree) do
    collect(tree, fn
      %{"@call" => _} = call -> call
      _other -> nil
    end)
  end

  describe "encode_surface/3 envelope" do
    test "returns one schema-valid inline createSurface with components and data model" do
      assert [message] = encode_kitchen_sink()
      assert_valid_agent_message(message)

      assert %{"version" => "1.0", "createSurface" => create} = message
      assert create["surfaceId"] == "kitchen_sink"
      assert create["catalogId"] == @catalog_id
      assert [_ | _] = create["components"]
      assert is_map(create["dataModel"])
      refute Map.has_key?(create, "theme")
      refute Map.has_key?(create, "surfaceProperties")
    end

    test "every action is an ashAction call in the ash_a2ui catalog naming its source" do
      components = encode_kitchen_sink() |> components()

      actions =
        collect(components, fn
          %{"id" => id, "action" => action} -> {id, action}
          _other -> nil
        end)

      assert actions != []

      for {id, action} <- actions do
        assert %{
                 "functionCall" => %{
                   "@call" => "ashAction",
                   "catalogId" => @ash_catalog_id,
                   "args" => %{"name" => name, "sourceComponentId" => ^id, "context" => _}
                 }
               } = action

        assert name =~ @identifier
      end
    end

    test "no wire function call carries returnType" do
      calls = encode_kitchen_sink() |> components() |> calls()

      # the KitchenSink fixture formats :inserted_at as a date
      assert Enum.any?(calls, &(&1["@call"] == "formatDate"))
      refute Enum.any?(calls, &Map.has_key?(&1, "returnType"))
    end

    test "every component id and function name is a UAX #31 identifier" do
      components = encode_kitchen_sink() |> components()

      for %{"id" => id} <- components, do: assert(id =~ @identifier, "component id #{id}")

      for %{"@call" => call} <- calls(components),
          do: assert(call =~ @identifier, "function name #{call}")
    end

    test "a component with id root is present and references only ids as children" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Column", "children" => children} = components["root"]

      # the task panel and the feedback line lead; the table follows
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

    test "a table-only surface omits the form section" do
      messages = Minimal |> ResolvedView.resolve() |> Encoder.encode_surface([], [])
      assert_valid_agent_message(hd(messages))

      components = components_by_id(messages)

      assert components["root"]["children"] ==
               [
                 "status_text",
                 "table_heading",
                 "records_list",
                 "empty_state",
                 "action_result_panel"
               ]

      refute Map.has_key?(components, "form")
      refute Map.has_key?(components, "form_slot")
      # no create action, no form: no create button and no View control
      refute Map.has_key?(components, "create_button")
      refute Map.has_key?(components, "view_button")
    end
  end

  describe "table composition (List + Card/Row template)" do
    test "the List is bound to /records with a Card-wrapped row as item template" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "List",
               "children" => %{"componentId" => "record_row", "path" => "/records"}
             } = components["records_list"]

      assert %{"component" => "Card", "child" => "record_row_content"} =
               components["record_row"]

      assert %{"component" => "Row", "children" => row_children} =
               components["record_row_content"]

      assert row_children ==
               [
                 "table_cell_active_row",
                 "table_cell_count_row",
                 "table_cell_price_row",
                 "table_cell_birthday_row",
                 "table_cell_scheduled_at_row",
                 "table_cell_status_row",
                 "table_cell_name_row",
                 "table_cell_inserted_at_row"
               ] ++
                 [
                   "row_action_update_button",
                   "row_action_destroy_button",
                   "view_button",
                   "edit_button"
                 ]
    end

    test "cells are labeled Rows: a caption label plus the bound value Text" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "Row",
               "children" => ["table_cell_name_label", "table_cell_name_value"]
             } = components["table_cell_name_row"]

      assert %{"component" => "Text", "text" => "Name", "variant" => "caption"} =
               components["table_cell_name_label"]

      assert %{"component" => "Text", "text" => %{"@path" => "name"}} =
               components["table_cell_name_value"]

      assert %{"component" => "Text", "text" => %{"@path" => "status"}} =
               components["table_cell_status_value"]
    end

    test "a :date format renders the cell value through formatDate" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "Text",
               "text" => %{
                 "@call" => "formatDate",
                 "args" => %{"value" => %{"@path" => "inserted_at"}, "format" => format}
               }
             } = components["table_cell_inserted_at_value"]

      assert is_binary(format)
    end

    test "row-action buttons carry the invoke contract" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Button", "child" => "row_action_update_text"} =
               components["row_action_update_button"]

      assert %{
               "name" => "invoke",
               "sourceComponentId" => "row_action_update_button",
               "context" => %{"action" => "update", "recordId" => %{"@path" => "id"}}
             } = event(components["row_action_update_button"])

      assert %{"component" => "Text", "text" => "Update"} = components["row_action_update_text"]

      assert %{"name" => "invoke", "context" => %{"action" => "destroy"}} =
               event(components["row_action_destroy_button"])
    end

    test "the View and Edit row controls carry the task-panel contract" do
      components = encode_kitchen_sink() |> components_by_id()

      for {id, event, label} <- [
            {"view_button", "view_record", "View"},
            {"edit_button", "start_edit", "Edit"}
          ] do
        assert %{"component" => "Button", "child" => child} = components[id]

        assert %{
                 "name" => ^event,
                 "context" => %{"recordId" => %{"@path" => "id"}, "component" => "table"}
               } = event(components[id])

        assert components[child]["text"] == label
      end

      refute Map.has_key?(components, "row_select_button")
    end

    test "the table heading is a humanized resource name, as a Markdown heading" do
      components = encode_kitchen_sink() |> components_by_id()

      # 1.0's basic Text has no heading variants: a heading is Markdown
      assert %{"component" => "Text", "text" => "## Kitchen sink"} = components["table_heading"]
      refute Map.has_key?(components["table_heading"], "variant")
    end

    test "no Text uses a variant outside the basic catalog's caption and body" do
      components = encode_kitchen_sink() |> components()

      for %{"component" => "Text", "variant" => variant} <- components,
          do: assert(variant in ["caption", "body"])
    end
  end

  describe "form composition" do
    test "the carded form panel holds the field pairs and the gated submit" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "List", "children" => %{"componentId" => "form"}} =
               components["form_slot"]

      assert %{"component" => "Card", "child" => "form_body"} = components["form"]

      assert %{"component" => "Column", "children" => children} = components["form_fields"]

      assert children ==
               Enum.flat_map(
                 [:active, :count, :price, :birthday, :scheduled_at, :status, :name],
                 &["form_input_#{&1}", "form_error_#{&1}"]
               )

      assert components["form_footer"]["children"] == ["form_submit_slot", "form_cancel_button"]

      assert components["form_submit_slot"]["children"] == %{
               "componentId" => "form_submit_button",
               "path" => "/ui/panel/submit_visible"
             }

      assert components["form_submit_text"]["text"] == %{"@path" => "/ui/panel/primary_label"}
    end

    test "inputs use the resolved widget and bind values into /form/<field>" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "TextField",
               "label" => "Name",
               "value" => %{"@path" => "/form/name"}
             } = components["form_input_name"]

      assert %{
               "component" => "CheckBox",
               "label" => "Active",
               "value" => %{"@path" => "/form/active"}
             } = components["form_input_active"]

      assert %{
               "component" => "ChoicePicker",
               "label" => "Status",
               "value" => %{"@path" => "/form/status"},
               "variant" => "mutuallyExclusive",
               "options" => [
                 %{"label" => "Draft", "value" => "draft"},
                 %{"label" => "Published", "value" => "published"},
                 %{"label" => "Archived", "value" => "archived"}
               ]
             } = components["form_input_status"]
    end

    test "numeric fields get the number TextField variant" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "TextField", "variant" => "number"} = components["form_input_count"]
      assert %{"component" => "TextField", "variant" => "number"} = components["form_input_price"]
      refute Map.has_key?(components["form_input_name"], "variant")
    end

    test "date-only fields enable only the date part of DateTimeInput" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "DateTimeInput",
               "value" => %{"@path" => "/form/birthday"},
               "enableDate" => true,
               "enableTime" => false
             } = components["form_input_birthday"]

      assert %{
               "component" => "DateTimeInput",
               "value" => %{"@path" => "/form/scheduled_at"},
               "enableDate" => true,
               "enableTime" => true
             } = components["form_input_scheduled_at"]
    end

    test "per-field error Texts are bound to /errors/<field>" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "Text",
               "text" => %{"@path" => "/errors/name"},
               "variant" => "caption"
             } = components["form_error_name"]
    end

    test "the submit button carries the submit_form contract" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Button", "variant" => "primary", "child" => "form_submit_text"} =
               components["form_submit_button"]

      assert %{
               "name" => "submit_form",
               "sourceComponentId" => "form_submit_button",
               "context" => %{
                 "values" => %{"@path" => "/form"},
                 "recordId" => %{"@path" => "/form/id"}
               }
             } = event(components["form_submit_button"])
    end
  end

  describe "status text" do
    test "a status Text bound to the typed feedback message is always present" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Text", "text" => %{"@path" => "/ui/feedback/message"}} =
               components["status_text"]
    end
  end

  describe "action result panel" do
    test "a Column wrapping a Text bound to /ui/feedback/resultText is always present" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Column", "children" => ["action_result_text"]} =
               components["action_result_panel"]

      assert %{"component" => "Text", "text" => %{"@path" => "/ui/feedback/resultText"}} =
               components["action_result_text"]
    end
  end

  describe "data model + record serialization" do
    test "the initial data model carries the full reserved-path value shape" do
      data_model = encode_kitchen_sink() |> data_model()

      assert %{
               "records" => [],
               "form" => %{},
               "errors" => %{},
               "options" => %{},
               "_empty_visible" => [%{"id" => "on"}],
               "_empty_message" => "No Kitchen sink records yet.",
               "ui" => %{
                 "intent" => "browse",
                 "feedback" => %{
                   "kind" => "",
                   "message" => "",
                   "code" => "",
                   "functionCallId" => "",
                   "result" => %{},
                   "resultText" => ""
                 },
                 "panel" => %{"visible" => [], "mode" => nil}
               }
             } = data_model

      for retired <- ["status", "action_result", "action_result_text", "response"],
          do: refute(Map.has_key?(data_model["ui"], retired))
    end

    test "records are serialized to JSON-safe maps with stringified values" do
      record = %KitchenSink{
        id: "018f0000-0000-7000-8000-000000000001",
        name: "Widget",
        active: true,
        count: 3,
        price: Decimal.new("9.99"),
        birthday: ~D[2020-01-02],
        scheduled_at: ~U[2026-01-02 03:04:05Z],
        status: :published,
        inserted_at: ~U[2026-07-10 12:00:00.000000Z],
        updated_at: ~U[2026-07-10 12:00:00.000000Z]
      }

      [message] = encode_kitchen_sink([record])
      assert_valid_agent_message(message)

      assert [row] = data_model(message)["records"]

      assert row == %{
               "id" => "018f0000-0000-7000-8000-000000000001",
               "name" => "Widget",
               "active" => true,
               "count" => 3,
               "price" => "9.99",
               "birthday" => "2020-01-02",
               "scheduled_at" => "2026-01-02T03:04:05Z",
               # Enum values carry their display label, the same one the form
               # picker for this field has always shown.
               "status" => "Published",
               "inserted_at" => "2026-07-10T12:00:00.000000Z",
               "_values" => %{"status" => "published"}
             }
    end

    test "values no Jason implementation covers render a readable placeholder, not a crash" do
      # A struct without a Jason implementation (what a custom Ash type might
      # return) and a tuple (an Ash.Type.Tuple value) cannot be JSON-encoded:
      # the encoder degrades them to readable placeholders instead of raising
      # a Jason.EncodeError at the transport.
      record = %KitchenSink{
        id: "018f0000-0000-7000-8000-000000000002",
        name: %UnsupportedValue{payload: "secret"},
        count: {:from, :to}
      }

      [message] = encode_kitchen_sink([record])
      # the placeholder is a plain string, so the message stays schema-valid
      assert_valid_agent_message(message)

      assert [row] = data_model(message)["records"]
      assert row["name"] == "unsupported type: UnsupportedValue"
      assert row["count"] == "unsupported type: tuple"
    end

    test "structs WITH a Jason implementation keep it (no placeholder)" do
      ordered = Jason.OrderedObject.new([{"kept", "as-is"}])
      record = %KitchenSink{id: "018f0000-0000-7000-8000-000000000003", name: ordered}

      [message] = encode_kitchen_sink([record])

      assert [row] = data_model(message)["records"]
      assert row["name"] == ordered
    end

    test "encode_data_model/3 emits a full-model updateDataModel by default" do
      view = ResolvedView.resolve(KitchenSink)
      record = %KitchenSink{id: "x", name: "A"}

      message = Encoder.encode_data_model(view, [record], [])
      assert_valid_agent_message(message)

      assert %{
               "updateDataModel" => %{
                 "surfaceId" => "kitchen_sink",
                 "path" => "/",
                 "value" => %{
                   "records" => [%{"id" => "x", "name" => "A", "status" => "Draft"}],
                   "form" => %{},
                   "errors" => %{},
                   "_empty_visible" => [],
                   "ui" => %{"feedback" => %{"kind" => "", "message" => ""}}
                 }
               }
             } = message
    end

    test "encode_data_model/3 matches the initial data model of encode_surface/3" do
      view = ResolvedView.resolve(KitchenSink)
      record = %KitchenSink{id: "x", name: "A"}

      assert Encoder.encode_data_model(view, [record], [])["updateDataModel"]["value"] ==
               view |> Encoder.encode_surface([record], []) |> data_model()
    end

    test "encode_data_model/3 with scope: :records only replaces /records" do
      view = ResolvedView.resolve(KitchenSink)
      record = %KitchenSink{id: "x", name: "A"}

      message = Encoder.encode_data_model(view, [record], scope: :records)
      assert_valid_agent_message(message)

      assert %{
               "updateDataModel" => %{
                 "surfaceId" => "kitchen_sink",
                 "path" => "/records",
                 "value" => [%{"id" => "x", "name" => "A"}]
               }
             } = message
    end
  end

  describe "wire builders" do
    test "update_data_model/3 always carries value; nil deletes the key at path" do
      message = Encoder.update_data_model("kitchen_sink", "/form/name", nil)
      assert_valid_agent_message(message)

      assert message["updateDataModel"] == %{
               "surfaceId" => "kitchen_sink",
               "path" => "/form/name",
               "value" => nil
             }
    end

    test "call_renderer_function/4 names the function's catalog and a fresh call id" do
      message =
        Encoder.call_renderer_function("kitchen_sink", "downloadFile", %{
          "filename" => "a.csv",
          "mimeType" => "text/csv",
          "dataUrl" => "data:text/csv;base64,YSxi"
        })

      assert_valid_agent_message(message)

      assert %{
               "version" => "1.0",
               "callRendererFunction" => %{
                 "surfaceId" => "kitchen_sink",
                 "functionCallId" => "fc_" <> _,
                 "callFunction" => %{"@call" => "downloadFile", "catalogId" => @ash_catalog_id}
               }
             } = message

      other = Encoder.call_renderer_function("kitchen_sink", "downloadFile", %{})

      refute other["callRendererFunction"]["functionCallId"] ==
               message["callRendererFunction"]["functionCallId"]
    end

    test "call_renderer_function/4 honours catalog_id and function_call_id" do
      message =
        Encoder.call_renderer_function("kitchen_sink", "openUrl", %{"url" => "https://a.example"},
          catalog_id: @catalog_id,
          function_call_id: "fc_1"
        )

      assert_valid_agent_message(message)
      assert message["callRendererFunction"]["functionCallId"] == "fc_1"
      assert message["callRendererFunction"]["callFunction"]["catalogId"] == @catalog_id
    end

    test "agent_function_response/2 carries a value or an error" do
      ok = Encoder.agent_function_response("fc_1", {:ok, %{"done" => true}})
      assert_valid_agent_message(ok)

      assert ok["agentFunctionResponse"] == %{
               "functionCallId" => "fc_1",
               "value" => %{"done" => true}
             }

      error = Encoder.agent_function_response("fc_2", {:error, "forbidden", "Not allowed."})
      assert_valid_agent_message(error)

      assert error["agentFunctionResponse"] == %{
               "functionCallId" => "fc_2",
               "error" => %{"code" => "forbidden", "message" => "Not allowed."}
             }
    end

    test "with_catalog/2 qualifies a component from another catalog and its calls" do
      admin = AshA2ui.Experience.admin_catalog_id()

      text = %{
        "id" => "cell",
        "component" => "Text",
        "text" => %{"@call" => "formatDate", "args" => %{"value" => %{"@path" => "at"}}}
      }

      assert %{
               "@catalogId" => @catalog_id,
               "text" => %{"@call" => "formatDate", "catalogId" => @catalog_id}
             } = Encoder.with_catalog(text, admin)

      assert Encoder.with_catalog(text, @catalog_id) == text

      page = %{"id" => "root", "component" => "entityPage", "title" => "T", "children" => []}
      assert Encoder.with_catalog(page, admin) == page
      assert Encoder.with_catalog(page, @catalog_id)["@catalogId"] == admin
    end

    test "with_catalog/2 leaves a call that names its catalog alone" do
      button = %{
        "id" => "b",
        "component" => "Button",
        "child" => "t",
        "action" => Encoder.ash_action("go", %{}, "b")
      }

      assert Encoder.with_catalog(button, AshA2ui.Experience.admin_catalog_id())["action"] ==
               button["action"]
    end
  end

  describe "Info.build_surface/2 and Info.build_data_model/2 (end-to-end)" do
    test "loads records through Ash and emits schema-valid messages" do
      Ash.create!(
        KitchenSink,
        %{
          name: "First",
          active: true,
          count: 1,
          price: Decimal.new("1.50"),
          birthday: ~D[2021-03-04],
          scheduled_at: ~U[2026-02-03 04:05:06Z],
          status: :draft
        },
        authorize?: false
      )

      Ash.create!(KitchenSink, %{name: "Second", status: :archived}, authorize?: false)

      assert [message] = AshA2ui.Info.build_surface(KitchenSink, actor: nil)
      assert_valid_agent_message(message)

      records = data_model(message)["records"]
      assert length(records) == 2

      first = Enum.find(records, &(&1["name"] == "First"))
      assert first["price"] == "1.50"
      assert first["birthday"] == "2021-03-04"
      assert first["scheduled_at"] == "2026-02-03T04:05:06Z"
      assert first["status"] == "Draft"
      assert is_binary(first["id"])
      assert is_binary(first["inserted_at"])

      assert Enum.find(records, &(&1["name"] == "Second"))["status"] == "Archived"
    end

    test "build_data_model/2 output is schema-valid and contains the records" do
      Ash.create!(KitchenSink, %{name: "Only", status: :draft}, authorize?: false)

      message = AshA2ui.Info.build_data_model(KitchenSink, actor: nil)
      assert_valid_agent_message(message)

      assert [%{"name" => "Only"}] =
               Enum.filter(
                 message["updateDataModel"]["value"]["records"],
                 &(&1["name"] == "Only")
               )
    end

    test "raises a sensible error when the resource has no read action" do
      assert_raise ArgumentError, ~r/no read action/, fn ->
        AshA2ui.Info.build_surface(NoRead)
      end
    end
  end
end
