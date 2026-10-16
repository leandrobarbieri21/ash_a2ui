defmodule AshA2ui.Wave6EncoderTest do
  @moduledoc """
  Encoder tests for Wave 6 layout features: card-style table rows
  (`row_layout`) and grouped N-column form grids (`group`), all messages
  validated against the vendored v0.9.1 JSON Schemas.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias Ash.DataLayer.Ets
  alias AshA2ui.Test.{KitchenSink, Promotion}

  setup do
    on_exit(fn ->
      for resource <- [Promotion, KitchenSink] do
        Ets.stop(resource)
      end
    end)

    :ok
  end

  defp components(messages) do
    %{"updateComponents" => %{"components" => components}} =
      Enum.find(messages, &Map.has_key?(&1, "updateComponents"))

    Map.new(components, &{&1["id"], &1})
  end

  defp data_model(messages) do
    %{"updateDataModel" => %{"path" => "/", "value" => value}} =
      Enum.find(messages, &Map.has_key?(&1, "updateDataModel"))

    value
  end

  describe "row_layout card rows" do
    setup do
      promotion =
        Ash.create!(
          Promotion,
          %{name: "Spring Sale", slug: "spring", trial_days: 14, is_active: true},
          authorize?: false
        )

      {:ok, promotion: promotion, messages: AshA2ui.Info.build_surface(Promotion)}
    end

    test "all messages are schema-valid", %{messages: messages} do
      Enum.each(messages, &assert_valid_server_message/1)
    end

    test "the templated record_row becomes a Card over a header + meta grid", %{
      messages: messages
    } do
      components = components(messages)

      assert components["records_list"]["children"] ==
               %{"componentId" => "record_row", "path" => "/records"}

      assert components["record_row"] ==
               %{"id" => "record_row", "component" => "Card", "child" => "record_row_body"}

      assert components["record_row_body"]["component"] == "Column"

      assert components["record_row_body"]["children"] ==
               ["record_row_header", "record_row_meta_row_0"]

      refute Map.has_key?(components, "table_cell_name")
    end

    test "the header row holds the title and the badge + actions on the right", %{
      messages: messages
    } do
      components = components(messages)

      assert components["record_row_header"]["component"] == "Row"
      assert components["record_row_header"]["justify"] == "spaceBetween"

      assert components["record_row_header"]["children"] ==
               ["record_row_title", "record_row_header_right"]

      assert components["record_row_title"] == %{
               "id" => "record_row_title",
               "component" => "Text",
               "text" => %{"path" => "name"},
               "variant" => "h4",
               "weight" => 1
             }

      assert components["record_row_header_right"]["children"] ==
               ["record_row_badge", "row_action_destroy_button", "view_button", "edit_button"]

      assert components["record_row_badge"] == %{
               "id" => "record_row_badge",
               "component" => "Text",
               "text" => %{"path" => "_badge_is_active"},
               "variant" => "caption"
             }
    end

    test "meta values render as a grid of caption-labeled equal-weight cells", %{
      messages: messages
    } do
      components = components(messages)

      assert components["record_row_meta_row_0"]["component"] == "Row"

      assert components["record_row_meta_row_0"]["children"] == [
               "record_row_meta_cell_slug",
               "record_row_meta_cell_trial_days",
               "record_row_meta_cell_expires_at"
             ]

      assert components["record_row_meta_cell_slug"] == %{
               "id" => "record_row_meta_cell_slug",
               "component" => "Column",
               "weight" => 1,
               "children" => ["record_row_meta_label_slug", "record_row_meta_value_slug"]
             }

      assert components["record_row_meta_label_slug"]["variant"] == "caption"
      assert components["record_row_meta_label_slug"]["text"] == "Slug"
      assert components["record_row_meta_value_slug"]["text"] == %{"path" => "slug"}

      # format :date on expires_at is honored inside the meta grid
      assert components["record_row_meta_value_expires_at"]["text"]["call"] == "formatDate"
    end

    test "rows carry the computed badge display text", %{messages: messages} do
      assert [row] = data_model(messages)["records"]
      assert row["_badge_is_active"] == "Active"
      # the field's own key is untouched by the badge mapping
      assert row["is_active"] == true
    end

    test "badge values without a badge_text entry fall back to the humanized value" do
      layout = %AshA2ui.RowLayout{title: :name, badge: :status, badge_text: []}

      assert AshA2ui.RowLayout.badge_data(layout, %{status: :pending_review}) ==
               %{"_badge_status" => "Pending review"}

      assert AshA2ui.RowLayout.badge_data(layout, %{status: nil}) == %{"_badge_status" => ""}
    end
  end

  describe "form groups" do
    setup do
      {:ok, messages: AshA2ui.Info.build_surface(Promotion)}
    end

    test "groups render at the position of their first member; ungrouped fields in place", %{
      messages: messages
    } do
      components = components(messages)

      assert components["form_fields"]["children"] == [
               "form_group_details",
               "form_group_scheduling",
               "form_input_is_active",
               "form_error_is_active"
             ]
    end

    test "each group is a Card-wrapped labeled section", %{messages: messages} do
      components = components(messages)

      assert components["form_group_details"] == %{
               "id" => "form_group_details",
               "component" => "Card",
               "child" => "form_group_details_body"
             }

      assert components["form_group_details_body"]["children"] == [
               "form_group_details_heading",
               "form_group_details_row_0"
             ]

      assert components["form_group_details_heading"] == %{
               "id" => "form_group_details_heading",
               "component" => "Text",
               "text" => "Details",
               "variant" => "h3"
             }

      # label defaults to the humanized group name
      assert components["form_group_scheduling_heading"]["text"] == "Scheduling"
    end

    test "grouped fields lay out in rows of equal-weight columns", %{messages: messages} do
      components = components(messages)

      assert components["form_group_details_row_0"]["component"] == "Row"

      assert components["form_group_details_row_0"]["children"] == [
               "form_group_details_cell_name",
               "form_group_details_cell_slug"
             ]

      assert components["form_group_details_cell_name"] == %{
               "id" => "form_group_details_cell_name",
               "component" => "Column",
               "weight" => 1,
               "children" => ["form_input_name", "form_error_name"]
             }

      # the inputs themselves are the unchanged per-field components
      assert components["form_input_name"]["component"] == "TextField"
      assert components["form_error_name"]["text"] == %{"path" => "/errors/name"}
    end

    test "uneven rows are padded with empty spacer columns" do
      defmodule UnevenGroupUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Promotion
          surface_id "uneven"

          component :form do
            fields [:name, :slug, :trial_days]
            create_action :create

            group :all do
              columns 2
              fields [:name, :slug, :trial_days]
            end
          end
        end
      end

      messages = AshA2ui.Info.build_surface(UnevenGroupUI)
      Enum.each(messages, &assert_valid_server_message/1)
      components = components(messages)

      assert components["form_group_all_body"]["children"] == [
               "form_group_all_heading",
               "form_group_all_row_0",
               "form_group_all_row_1"
             ]

      assert components["form_group_all_row_1"]["children"] == [
               "form_group_all_cell_trial_days",
               "form_group_all_spacer_1_1"
             ]

      assert components["form_group_all_spacer_1_1"] == %{
               "id" => "form_group_all_spacer_1_1",
               "component" => "Column",
               "weight" => 1,
               "children" => []
             }
    end

    test "single-column groups hold the input pairs directly, without grid wrappers" do
      defmodule SingleColumnGroupUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Promotion
          surface_id "single_column"

          component :form do
            fields [:name, :slug]
            create_action :create

            group :details do
              fields [:name, :slug]
            end
          end
        end
      end

      messages = AshA2ui.Info.build_surface(SingleColumnGroupUI)
      Enum.each(messages, &assert_valid_server_message/1)
      components = components(messages)

      assert components["form_group_details_body"]["children"] == [
               "form_group_details_heading",
               "form_input_name",
               "form_error_name",
               "form_input_slug",
               "form_error_slug"
             ]

      refute Map.has_key?(components, "form_group_details_row_0")
    end

    test "hidden fields drop out of groups" do
      defmodule HiddenGroupedFieldUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Promotion
          surface_id "hidden_grouped"

          component :form do
            fields [:name, :slug]
            create_action :create

            group :details do
              columns 2
              fields [:name, :slug]
            end
          end

          field :slug do
            hidden true
          end
        end
      end

      messages = AshA2ui.Info.build_surface(HiddenGroupedFieldUI)
      Enum.each(messages, &assert_valid_server_message/1)
      components = components(messages)

      assert components["form_group_details_row_0"]["children"] == [
               "form_group_details_cell_name",
               "form_group_details_spacer_0_1"
             ]
    end
  end

  describe "multi-table suffixing" do
    test "row_layout ids infix the table component name" do
      defmodule MultiTableLayoutUI do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Promotion
          surface_id "multi_layout"

          component :table, :active_items do
            fields [:name, :slug, :is_active]
            read_action :read

            row_layout do
              title :name
              badge :is_active
            end
          end

          component :table, :plain_items do
            fields [:name]
            read_action :read
          end
        end
      end

      messages = AshA2ui.Info.build_surface(MultiTableLayoutUI)
      Enum.each(messages, &assert_valid_server_message/1)
      components = components(messages)

      assert components["record_row_active_items"]["component"] == "Card"
      assert components["record_row_active_items"]["child"] == "record_row_active_items_body"

      assert components["record_row_active_items_badge"]["text"] ==
               %{"path" => "_badge_is_active"}

      assert components["record_row_active_items_meta_row_0"]["children"] ==
               [
                 "record_row_active_items_meta_cell_slug",
                 "record_row_active_items_meta_spacer_0_1"
               ]

      # the layout-less sibling keeps the flat labeled-cell rows
      assert components["record_row_plain_items"]["component"] == "Card"
      assert components["record_row_plain_items"]["child"] == "record_row_plain_items_content"
      assert components["record_row_plain_items_content"]["component"] == "Row"
    end
  end

  describe "backward compatibility" do
    test "surfaces without groups or row_layout keep the frozen flat structure" do
      messages = AshA2ui.Info.build_surface(KitchenSink)
      Enum.each(messages, &assert_valid_server_message/1)
      components = components(messages)

      # the flat baseline: Card -> record_row_content Row of labeled cells
      assert components["record_row"]["child"] == "record_row_content"
      assert components["record_row_content"]["component"] == "Row"
      assert Map.has_key?(components, "table_cell_name")
      refute Map.has_key?(components, "record_row_body")

      assert Enum.take(components["form_fields"]["children"], 2) ==
               ["form_input_active", "form_error_active"]
    end

    test "rows of layout-less tables carry no badge keys" do
      Ash.create!(KitchenSink, %{name: "Plain"}, authorize?: false)

      assert [row] =
               KitchenSink |> AshA2ui.Info.build_surface() |> data_model() |> Map.get("records")

      refute Enum.any?(Map.keys(row), &String.starts_with?(&1, "_badge_"))
    end
  end
end
