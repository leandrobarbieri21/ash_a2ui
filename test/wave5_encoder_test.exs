defmodule AshA2ui.Wave5EncoderTest do
  @moduledoc """
  Encoder tests for Wave 5: searchable-select composites and nested-form
  sections, all messages validated against the vendored v0.9.1 JSON Schemas.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias Ash.DataLayer.Ets
  alias AshA2ui.Test.{Author, Tag, Ticket, TicketNote, TicketSearchUI}

  setup do
    on_exit(fn ->
      for resource <- [Ticket, TicketNote, Tag, Author] do
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

  describe "searchable select composite (TicketSearchUI)" do
    setup do
      author = Ash.create!(Author, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
      {:ok, author: author, messages: AshA2ui.Info.build_surface(TicketSearchUI)}
    end

    test "all messages are schema-valid", %{messages: messages} do
      Enum.each(messages, &assert_valid_server_message/1)
    end

    test "emits the composite instead of a ChoicePicker", %{messages: messages} do
      components = components(messages)

      refute Map.has_key?(components, "form_input_author_id")

      assert components["form_fields"]["children"] ==
               [
                 "form_input_subject",
                 "form_error_subject",
                 "form_select_author_id",
                 "form_error_author_id",
                 "nested_tags"
               ]

      assert components["form_select_author_id"]["children"] == [
               "form_select_author_id_label",
               "form_select_author_id_selected",
               "form_select_author_id_controls",
               "form_select_author_id_options"
             ]

      assert components["form_select_author_id_selected"]["text"] ==
               %{"path" => "/select/author_id/label"}

      assert components["form_select_author_id_search_input"]["value"] ==
               %{"path" => "/select/author_id/search"}

      assert components["form_select_author_id_search_button"]["action"]["event"] == %{
               "name" => "option_search",
               "context" => %{
                 "field" => "author_id",
                 "search" => %{"path" => "/select/author_id/search"}
               }
             }

      assert components["form_select_author_id_options"]["children"] == %{
               "componentId" => "form_select_author_id_option_button",
               "path" => "/options/author_id"
             }

      assert components["form_select_author_id_option_button"]["action"]["event"] == %{
               "name" => "option_select",
               "context" => %{"field" => "author_id", "value" => %{"path" => "value"}}
             }

      assert components["form_select_author_id_option_text"]["text"] == %{"path" => "label"}
    end

    test "searchable pick_existing renders search controls and nested_add options",
         %{messages: messages} do
      components = components(messages)

      assert components["nested_tags"]["children"] == [
               "nested_tags_heading",
               "nested_tags_rows",
               "nested_tags_controls",
               "nested_tags_options"
             ]

      assert components["nested_tags_rows"]["children"] == %{
               "componentId" => "nested_tags_row",
               "path" => "/form/tags"
             }

      assert components["nested_tags_row"]["children"] ==
               ["nested_tags_row_label", "nested_tags_remove_button"]

      assert components["nested_tags_row_label"]["text"] == %{"path" => "label"}

      assert components["nested_tags_remove_button"]["action"]["event"] == %{
               "name" => "nested_remove",
               "context" => %{
                 "argument" => "tags",
                 "row" => %{"path" => "_row"},
                 "rows" => %{"path" => "/form/tags"}
               }
             }

      assert components["nested_tags_option_button"]["action"]["event"] == %{
               "name" => "nested_add",
               "context" => %{
                 "argument" => "tags",
                 "value" => %{"path" => "value"},
                 "rows" => %{"path" => "/form/tags"}
               }
             }
    end

    test "initial data model carries /select state, nested /form arrays and options",
         %{messages: messages, author: author} do
      value = data_model(messages)

      assert value["select"] == %{
               "author_id" => %{"search" => "", "label" => ""},
               "tags" => %{"search" => "", "picked" => []}
             }

      assert value["form"] == %{"tags" => []}

      assert value["options"]["author_id"] == [
               %{"label" => "Ada", "value" => author.id}
             ]

      assert value["options"]["tags"] == []
    end
  end

  describe "non-searchable nested forms (Ticket)" do
    setup do
      tag = Ash.create!(Tag, %{name: "urgent"}, authorize?: false)
      {:ok, tag: tag, messages: AshA2ui.Info.build_surface(Ticket)}
    end

    test "all messages are schema-valid", %{messages: messages} do
      Enum.each(messages, &assert_valid_server_message/1)
    end

    test "create_inline renders widget-mapped row inputs and an add button",
         %{messages: messages} do
      components = components(messages)

      assert components["nested_notes"]["children"] ==
               ["nested_notes_heading", "nested_notes_rows", "nested_notes_add_button"]

      assert components["nested_notes_heading"]["text"] == "Notes"

      assert components["nested_notes_row"]["children"] == [
               "nested_notes_input_body",
               "nested_notes_row_error_body",
               "nested_notes_input_rating",
               "nested_notes_row_error_rating",
               "nested_notes_remove_button"
             ]

      assert components["nested_notes_input_body"] == %{
               "id" => "nested_notes_input_body",
               "component" => "TextField",
               "label" => "Body",
               "value" => %{"path" => "body"}
             }

      assert components["nested_notes_input_rating"]["variant"] == "number"

      assert components["nested_notes_row_error_body"]["text"] == %{"path" => "_error_body"}

      assert components["nested_notes_add_button"]["action"]["event"] == %{
               "name" => "nested_add",
               "context" => %{"argument" => "notes", "rows" => %{"path" => "/form/notes"}}
             }
    end

    test "non-searchable pick_existing renders a ChoicePicker with inline options",
         %{messages: messages, tag: tag} do
      components = components(messages)

      assert components["nested_tags"]["children"] == [
               "nested_tags_heading",
               "nested_tags_rows",
               "nested_tags_picker",
               "nested_tags_add_button"
             ]

      assert components["nested_tags_picker"]["options"] == [
               %{"label" => "urgent", "value" => tag.id}
             ]

      assert components["nested_tags_picker"]["value"] == %{"path" => "/select/tags/picked"}

      assert components["nested_tags_add_button"]["action"]["event"] == %{
               "name" => "nested_add",
               "context" => %{
                 "argument" => "tags",
                 "value" => %{"path" => "/select/tags/picked"},
                 "rows" => %{"path" => "/form/tags"}
               }
             }
    end

    test "non-searchable belongs_to selects keep the frozen ChoicePicker shape",
         %{messages: messages} do
      components = components(messages)

      assert components["form_input_author_id"]["component"] == "ChoicePicker"
      refute Map.has_key?(components, "form_select_author_id")
    end

    test "initial data model: /select carries only the picker state", %{messages: messages} do
      value = data_model(messages)

      assert value["select"] == %{"tags" => %{"search" => "", "picked" => []}}
      assert value["form"] == %{"notes" => [], "tags" => []}
      assert Map.has_key?(value["options"], "tags")
      assert Map.has_key?(value["options"], "author_id")
    end
  end
end
