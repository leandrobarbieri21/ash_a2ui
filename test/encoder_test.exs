defmodule AshA2ui.EncoderTest do
  @moduledoc """
  `AshA2ui.Encoder.V0_9_1` payload tests: every message is validated against
  the vendored v0.9.1 schemas via `SchemaHelper.assert_valid_server_message/1`,
  plus targeted structural assertions on the emitted component tree, the
  frozen action-wire contract, and record serialization.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{KitchenSink, Minimal}

  @catalog_id "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

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
    KitchenSink |> ResolvedView.resolve() |> V0_9_1.encode_surface(records, [])
  end

  defp components_by_id(messages) do
    update = Enum.find(messages, &Map.has_key?(&1, "updateComponents"))
    Map.new(update["updateComponents"]["components"], &{&1["id"], &1})
  end

  describe "encode_surface/3 envelope" do
    test "returns createSurface -> updateComponents -> updateDataModel, all schema-valid" do
      messages = encode_kitchen_sink()

      assert [
               %{"createSurface" => create},
               %{"updateComponents" => update},
               %{"updateDataModel" => data}
             ] = Enum.map(messages, &assert_valid_server_message/1)

      assert Enum.all?(messages, &(&1["version"] == "v0.9.1"))
      assert create["surfaceId"] == "kitchen_sink"
      assert create["catalogId"] == @catalog_id
      assert update["surfaceId"] == "kitchen_sink"
      assert data["surfaceId"] == "kitchen_sink"
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
      messages = Minimal |> ResolvedView.resolve() |> V0_9_1.encode_surface([], [])
      Enum.each(messages, &assert_valid_server_message/1)

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
                 "table_cell_active",
                 "table_cell_count",
                 "table_cell_price",
                 "table_cell_birthday",
                 "table_cell_scheduled_at",
                 "table_cell_status",
                 "table_cell_name",
                 "table_cell_inserted_at"
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
             } = components["table_cell_name"]

      assert %{"component" => "Text", "text" => "Name", "variant" => "caption"} =
               components["table_cell_name_label"]

      assert %{"component" => "Text", "text" => %{"path" => "name"}} =
               components["table_cell_name_value"]

      assert %{"component" => "Text", "text" => %{"path" => "status"}} =
               components["table_cell_status_value"]
    end

    test "a :date format renders the cell value through formatDate" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "Text",
               "text" => %{
                 "call" => "formatDate",
                 "args" => %{"value" => %{"path" => "inserted_at"}, "format" => format},
                 "returnType" => "string"
               }
             } = components["table_cell_inserted_at_value"]

      assert is_binary(format)
    end

    test "row-action buttons carry the frozen invoke contract" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "Button",
               "child" => "row_action_update_text",
               "action" => %{
                 "event" => %{
                   "name" => "invoke",
                   "context" => %{"action" => "update", "recordId" => %{"path" => "id"}}
                 }
               }
             } = components["row_action_update_button"]

      assert %{"component" => "Text", "text" => "Update"} = components["row_action_update_text"]

      assert %{"event" => %{"name" => "invoke", "context" => %{"action" => "destroy"}}} =
               components["row_action_destroy_button"]["action"]
    end

    test "the View and Edit row controls carry the task-panel contract" do
      components = encode_kitchen_sink() |> components_by_id()

      for {id, event, label} <- [
            {"view_button", "view_record", "View"},
            {"edit_button", "start_edit", "Edit"}
          ] do
        assert %{
                 "component" => "Button",
                 "child" => child,
                 "action" => %{
                   "event" => %{
                     "name" => ^event,
                     "context" => %{"recordId" => %{"path" => "id"}, "component" => "table"}
                   }
                 }
               } = components[id]

        assert components[child]["text"] == label
      end

      refute Map.has_key?(components, "row_select_button")
    end

    test "the table heading is a humanized resource name" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Text", "text" => "Kitchen sink", "variant" => "h2"} =
               components["table_heading"]
    end

    test "headings use the Text variant hint, never literal markdown prefixes" do
      components = encode_kitchen_sink() |> components_by_id()

      literal_texts =
        for {_id, %{"component" => "Text", "text" => text}} <- components,
            is_binary(text),
            do: text

      refute Enum.any?(literal_texts, &String.starts_with?(&1, "#"))
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

      assert components["form_submit_text"]["text"] == %{"path" => "/ui/panel/primary_label"}
    end

    test "inputs use the resolved widget and bind values into /form/<field>" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "TextField",
               "label" => "Name",
               "value" => %{"path" => "/form/name"}
             } = components["form_input_name"]

      assert %{
               "component" => "CheckBox",
               "label" => "Active",
               "value" => %{"path" => "/form/active"}
             } = components["form_input_active"]

      assert %{
               "component" => "ChoicePicker",
               "label" => "Status",
               "value" => %{"path" => "/form/status"},
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
               "value" => %{"path" => "/form/birthday"},
               "enableDate" => true,
               "enableTime" => false
             } = components["form_input_birthday"]

      assert %{
               "component" => "DateTimeInput",
               "value" => %{"path" => "/form/scheduled_at"},
               "enableDate" => true,
               "enableTime" => true
             } = components["form_input_scheduled_at"]
    end

    test "per-field error Texts are bound to /errors/<field>" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "Text",
               "text" => %{"path" => "/errors/name"},
               "variant" => "caption"
             } = components["form_error_name"]
    end

    test "the submit button carries the frozen submit_form contract" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{
               "component" => "Button",
               "variant" => "primary",
               "child" => "form_submit_text",
               "action" => %{
                 "event" => %{
                   "name" => "submit_form",
                   "context" => %{
                     "values" => %{"path" => "/form"},
                     "recordId" => %{"path" => "/form/id"}
                   }
                 }
               }
             } = components["form_submit_button"]
    end
  end

  describe "status text" do
    test "a status Text bound to the typed feedback message is always present" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Text", "text" => %{"path" => "/ui/feedback/message"}} =
               components["status_text"]
    end
  end

  describe "action result panel" do
    test "a Column wrapping a Text bound to /ui/action_result_text is always present" do
      components = encode_kitchen_sink() |> components_by_id()

      assert %{"component" => "Column", "children" => ["action_result_text"]} =
               components["action_result_panel"]

      assert %{"component" => "Text", "text" => %{"path" => "/ui/action_result_text"}} =
               components["action_result_text"]
    end
  end

  describe "data model + record serialization" do
    test "the bootstrap updateDataModel carries the full reserved-path value shape" do
      assert [_, _, message] = encode_kitchen_sink()

      assert %{
               "updateDataModel" => %{
                 "surfaceId" => "kitchen_sink",
                 "path" => "/",
                 "value" => %{
                   "records" => [],
                   "form" => %{},
                   "errors" => %{},
                   "options" => %{},
                   "_empty_visible" => [%{"id" => "on"}],
                   "_empty_message" => "No Kitchen sink records yet.",
                   "ui" => %{
                     "action_result" => %{},
                     "action_result_text" => "",
                     "intent" => "browse",
                     "feedback" => %{"kind" => nil, "message" => ""},
                     "panel" => %{"visible" => [], "mode" => nil}
                   }
                 }
               }
             } = message

      refute Map.has_key?(message["updateDataModel"]["value"]["ui"], "status")
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

      [_, _, message] = encode_kitchen_sink([record])
      assert_valid_server_message(message)

      assert [row] = message["updateDataModel"]["value"]["records"]

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
               "inserted_at" => "2026-07-10T12:00:00.000000Z"
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

      [_, _, message] = encode_kitchen_sink([record])
      # the placeholder is a plain string, so the message stays schema-valid
      assert_valid_server_message(message)

      assert [row] = message["updateDataModel"]["value"]["records"]
      assert row["name"] == "unsupported type: UnsupportedValue"
      assert row["count"] == "unsupported type: tuple"
    end

    test "structs WITH a Jason implementation keep it (no placeholder)" do
      ordered = Jason.OrderedObject.new([{"kept", "as-is"}])
      record = %KitchenSink{id: "018f0000-0000-7000-8000-000000000003", name: ordered}

      [_, _, message] = encode_kitchen_sink([record])

      assert [row] = message["updateDataModel"]["value"]["records"]
      assert row["name"] == ordered
    end

    test "encode_data_model/3 emits a full-model updateDataModel by default" do
      view = ResolvedView.resolve(KitchenSink)
      record = %KitchenSink{id: "x", name: "A"}

      message = V0_9_1.encode_data_model(view, [record], [])
      assert_valid_server_message(message)

      assert %{
               "updateDataModel" => %{
                 "surfaceId" => "kitchen_sink",
                 "path" => "/",
                 "value" => %{
                   "records" => [%{"id" => "x", "name" => "A", "status" => "Draft"}],
                   "form" => %{},
                   "errors" => %{},
                   "_empty_visible" => [],
                   "ui" => %{"feedback" => %{"kind" => nil, "message" => ""}}
                 }
               }
             } = message
    end

    test "encode_data_model/3 with scope: :records only replaces /records" do
      view = ResolvedView.resolve(KitchenSink)
      record = %KitchenSink{id: "x", name: "A"}

      message = V0_9_1.encode_data_model(view, [record], scope: :records)
      assert_valid_server_message(message)

      assert %{
               "updateDataModel" => %{
                 "surfaceId" => "kitchen_sink",
                 "path" => "/records",
                 "value" => [%{"id" => "x", "name" => "A"}]
               }
             } = message
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

      messages = AshA2ui.Info.build_surface(KitchenSink, actor: nil)
      Enum.each(messages, &assert_valid_server_message/1)

      assert [%{"createSurface" => _}, %{"updateComponents" => _}, %{"updateDataModel" => data}] =
               messages

      records = data["value"]["records"]
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
      assert_valid_server_message(message)

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
