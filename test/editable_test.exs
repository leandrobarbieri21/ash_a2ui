defmodule AshA2ui.EditableTest do
  @moduledoc """
  Inline cell editing: `editable` blocks render allowlisted table fields as
  in-row TextField + Save cells committing per cell through the
  `"edit_cell"` client action, with validation errors mirrored into the
  failing row's reserved `_error_<field>` key. A cell's Save called as an
  `ashAction` function is answered with its feedback. Schema-validated
  against A2UI 1.0.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Bucket
  alias AshA2ui.Test.BucketWord
  alias AshA2ui.Test.BucketWordsUI
  alias AshA2ui.Test.EditableWordsUI
  alias AshA2ui.Test.EditableWordsV1UI
  alias AshA2ui.Test.Messages
  alias AshA2ui.Test.Surface

  defp envelope(name, context, surface \\ "editable_words") do
    Messages.call(name, surface, context)
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"createSurface" => %{"dataModel" => value}} when path == "/" -> value
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp create_word!(word, opts) do
    Ash.create!(
      BucketWord,
      %{
        word: word,
        replacement: opts[:replacement],
        state: opts[:state] || :new,
        bucket_id: opts[:bucket_id]
      },
      authorize?: false
    )
  end

  describe "resolution" do
    test "an editable block resolves onto the table with the update action defaulted" do
      view = ResolvedView.resolve(EditableWordsUI)

      assert [table] = view.tables
      assert table.editable == %{fields: [:replacement], update_action: :update_replacement}
    end

    test "tables without an editable block resolve editable: nil" do
      view = ResolvedView.resolve(AshA2ui.Test.ReviewItem)
      assert Enum.all?(view.tables, &is_nil(&1.editable))
    end
  end

  describe "encoder" do
    setup do
      create_word!("teh", replacement: "the")
      messages = AshA2ui.Info.build_surface(EditableWordsUI, authorize?: false)
      Enum.each(messages, &assert_valid_agent_message/1)

      components =
        messages
        |> Surface.components()
        |> Map.new(&{&1["id"], &1})

      %{components: components}
    end

    test "an editable cell is a TextField + Save button + error mirror", %{
      components: components
    } do
      assert components["table_cell_replacement_row"]["children"] == [
               "table_cell_replacement_input",
               "table_cell_replacement_save_button",
               "table_cell_replacement_error"
             ]

      input = components["table_cell_replacement_input"]
      assert input["component"] == "TextField"
      assert input["value"] == %{"@path" => "replacement"}

      error = components["table_cell_replacement_error"]
      assert error["text"] == %{"@path" => "_error_replacement"}
    end

    test "the Save button dispatches edit_cell with the row id, field and value", %{
      components: components
    } do
      event = components["table_cell_replacement_save_button"]["action"]["functionCall"]["args"]

      assert event["name"] == "edit_cell"

      assert event["context"] == %{
               "recordId" => %{"@path" => "id"},
               "component" => "table",
               "field" => "replacement",
               "value" => %{"@path" => "replacement"}
             }
    end

    test "non-editable columns keep the plain label/value cell", %{components: components} do
      assert components["table_cell_word_row"]["children"] == [
               "table_cell_word_label",
               "table_cell_word_value"
             ]
    end
  end

  describe "action handler" do
    setup do
      %{word: create_word!("teh", replacement: "the")}
    end

    test "a valid edit_cell commits the field and refreshes", %{word: word} do
      message =
        envelope("edit_cell", %{
          "recordId" => word.id,
          "field" => "replacement",
          "value" => "their"
        })

      assert {:ok, messages} = ActionHandler.handle(EditableWordsUI, message, authorize?: false)
      Enum.each(messages, &assert_valid_agent_message/1)

      assert [%{"replacement" => "their"}] = value_at(messages, "/records")
      assert Ash.get!(BucketWord, word.id, authorize?: false).replacement == "their"
    end

    test "a validation error mirrors into the failing row's _error_<field> key", %{word: word} do
      other = create_word!("adn", replacement: "and")

      message =
        envelope("edit_cell", %{
          "recordId" => word.id,
          "field" => "replacement",
          "value" => "NOT LOWERCASE"
        })

      assert {:error, messages} =
               ActionHandler.handle(EditableWordsUI, message, authorize?: false)

      Enum.each(messages, &assert_valid_agent_message/1)

      assert value_at(messages, "/errors/replacement") =~ "lowercase"

      rows = value_at(messages, "/records")
      failing = Enum.find(rows, &(&1["id"] == word.id))
      untouched = Enum.find(rows, &(&1["id"] == other.id))

      # the submitted value is kept in the row for correction
      assert failing["replacement"] == "NOT LOWERCASE"
      assert failing["_error_replacement"] =~ "lowercase"
      refute Map.has_key?(untouched, "_error_replacement")

      # the write never happened
      assert Ash.get!(BucketWord, word.id, authorize?: false).replacement == "the"
    end

    test "a field outside the editable allowlist is rejected before Ash", %{word: word} do
      message =
        envelope("edit_cell", %{"recordId" => word.id, "field" => "word", "value" => "hax"})

      assert {:error, messages} =
               ActionHandler.handle(EditableWordsUI, message, authorize?: false)

      assert value_at(messages, "/ui/feedback")["message"] =~ "not editable"
      assert Ash.get!(BucketWord, word.id, authorize?: false).word == "teh"
    end

    test "a missing recordId is rejected", %{word: _word} do
      message = envelope("edit_cell", %{"field" => "replacement", "value" => "x"})

      assert {:error, messages} =
               ActionHandler.handle(EditableWordsUI, message, authorize?: false)

      assert value_at(messages, "/ui/feedback")["message"] =~ ~s(missing "recordId")
    end
  end

  describe "sections interplay" do
    test "edit_cell targets an expanded runtime table by its component name" do
      bucket = Ash.create!(Bucket, %{name: "Alpha"}, authorize?: false)
      word = create_word!("teh", replacement: "the", state: :bucketed, bucket_id: bucket.id)

      runtime = AshA2ui.Sections.section_name(:per_bucket, bucket.id)

      message =
        envelope(
          "edit_cell",
          %{
            "recordId" => word.id,
            "component" => runtime,
            "field" => "replacement",
            "value" => "their"
          },
          "bucket_words"
        )

      assert {:ok, messages} = ActionHandler.handle(BucketWordsUI, message, authorize?: false)

      # update_replacement's refreshes [:per_bucket] fans out to the runtime table
      assert [%{"replacement" => "their"}] = value_at(messages, "/records/#{runtime}")
      assert value_at(messages, "/records/new_words") == nil
    end
  end

  describe "ashAction calls" do
    setup do
      %{word: create_word!("teh", replacement: "the")}
    end

    test "an editable cell's Save button calls ashAction edit_cell", %{word: _word} do
      assert [message] = AshA2ui.Info.build_surface(EditableWordsV1UI, authorize?: false)
      assert_valid_agent_message(message)

      save =
        Enum.find(
          message["createSurface"]["components"],
          &(&1["id"] == "table_cell_replacement_save_button")
        )

      assert save["action"]["functionCall"]["@call"] == "ashAction"
      assert save["action"]["functionCall"]["args"]["name"] == "edit_cell"
    end

    test "a successful commit called as ashAction is answered with its feedback", %{
      word: word
    } do
      message =
        Messages.call(
          "edit_cell",
          "editable_words_v1",
          %{"recordId" => word.id, "field" => "replacement", "value" => "their"},
          id: "cell_1"
        )

      assert {:ok, messages} = ActionHandler.handle(EditableWordsV1UI, message, authorize?: false)
      Enum.each(messages, &assert_valid_agent_message/1)

      assert %{"functionCallId" => "cell_1", "value" => %{"kind" => "success"}} =
               Messages.response(messages)

      assert %{"agentFunctionResponse" => _} = List.last(messages)
    end

    test "a failed commit is answered with VALIDATION_FAILED and the row mirror", %{
      word: word
    } do
      message =
        Messages.call(
          "edit_cell",
          "editable_words_v1",
          %{"recordId" => word.id, "field" => "replacement", "value" => "NOT LOWERCASE"},
          id: "cell_2"
        )

      assert {:error, messages} =
               ActionHandler.handle(EditableWordsV1UI, message, authorize?: false)

      Enum.each(messages, &assert_valid_agent_message/1)

      assert %{"functionCallId" => "cell_2", "error" => %{"code" => "VALIDATION_FAILED"}} =
               Messages.response(messages)

      rows = value_at(messages, "/records")
      assert [%{"_error_replacement" => error_text}] = rows
      assert error_text =~ "lowercase"
    end
  end
end

defmodule AshA2ui.EditableVerifierTest do
  @moduledoc """
  Compile-time failure tests for `AshA2ui.Verifiers.VerifyEditable`.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "editable on a non-table component does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule FormEditable do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :form do
              fields [:word]

              editable do
                fields [:word]
              end
            end
          end
        end
      end)

    assert result =~ ~r/only supported on :table components/
  end

  test "editable combined with row_layout does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule EditableCardRows do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table do
              fields [:word, :replacement]

              row_layout do
                title :word
              end

              editable do
                fields [:replacement]
              end
            end
          end
        end
      end)

    assert result =~ ~r/cannot combine an editable block with a row_layout/
  end

  test "editable fields outside the table's fields do not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule EditableUnknownField do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table do
              fields [:word]

              editable do
                fields [:replacement]
              end
            end
          end
        end
      end)

    assert result =~ ~r/editable field :replacement is not one of table/
  end

  test "editable fields not accepted by the update action do not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule EditableUnacceptedField do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table do
              fields [:word, :replacement]

              editable do
                fields [:word]
                update_action :update_replacement
              end
            end
          end
        end
      end)

    assert result =~ ~r/editable field :word is not accepted by update action/
  end

  test "an unknown editable update_action does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule EditableUnknownAction do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table do
              fields [:word, :replacement]

              editable do
                fields [:replacement]
                update_action :nope
              end
            end
          end
        end
      end)

    assert result =~ ~r/editable update_action :nope is not an update action/
  end
end
