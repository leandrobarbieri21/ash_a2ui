defmodule AshA2ui.SaveBarTest do
  @moduledoc """
  Admin catalog 3.11, editing a record in place: a `:detail` card's
  `editable` fields open as inputs (`edit` on their fieldDisplay), the
  changes wait in `/ui/edits`, and the surface's `save_bar` saves them all
  through `"save_changes"`: each card's update action on its record, with
  the save bar `confirm`'s `then_action` after them on `"then"`.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Messages, SchemaHelper, Statement, StatementEditUI}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(Statement)
    end)

    statement =
      Ash.create!(Statement, %{title: "Annual fee", amount: 1200, kind: :invoice},
        authorize?: false
      )

    %{statement: statement}
  end

  defp contexts(statement),
    do: %{"statement" => %{"value" => statement.id, "label" => statement.title}}

  defp surface(catalog, statement) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(StatementEditUI,
        authorize?: false,
        context_state: %{
          "statement" => %{"search" => "", "value" => statement.id, "label" => "x"}
        }
      )

    catalogs = if catalog == :admin_v1, do: SchemaHelper.admin_catalogs()
    SchemaHelper.assert_valid_agent_message(message, catalogs: catalogs)

    {Map.new(surface["components"], &{&1["id"], &1}), surface["dataModel"]["detail"]["statement"]}
  end

  defp save(statement, values, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    edits =
      Keyword.get(opts, :edits, %{
        "facts" => %{"recordId" => statement.id, "values" => values}
      })

    context = %{
      "edits" => edits,
      "choice" => Keyword.get(opts, :choice, "save"),
      "recordId" => statement.id,
      "contexts" => contexts(statement)
    }

    ActionHandler.handle(
      StatementEditUI,
      Messages.call("save_changes", "statement_edit", context),
      authorize?: false
    )
  end

  defp write(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> {:ok, value}
      _other -> nil
    end)
  end

  defp reload(statement), do: Ash.get!(Statement, statement.id, authorize?: false)

  describe "the wire" do
    test "an editable field's fieldDisplay names its card, field and input, and binds its values",
         %{statement: statement} do
      {components, _detail} = surface(:admin_v1, statement)
      title = components["detail_facts_field_title"]

      assert title["edit"] == %{
               "component" => "facts",
               "field" => "title",
               "recordId" => %{"@path" => "/detail/statement/id"},
               "input" => "text"
             }

      assert title["editValue"] == %{"@path" => "/detail/statement/_edit_title"}
      assert title["editVisible"] == %{"@path" => "/detail/statement/_editable_facts"}
      assert title["editDraft"] == %{"@path" => "/ui/edits/facts/values/title"}
      assert title["editError"] == %{"@path" => "/ui/edit_errors/facts/title"}

      # the amount is shown formatted and edited as the integer behind it
      assert components["detail_facts_field_amount_text"]["edit"]["input"] == "integer"

      assert components["detail_facts_field_kind"]["edit"]["input"] == "choice"

      assert components["detail_facts_field_kind"]["edit"]["options"] == [
               %{"value" => "invoice", "label" => "Invoice"},
               %{"value" => "quote", "label" => "Quote"}
             ]

      refute Map.has_key?(components["detail_facts_field_note"], "edit")
    end

    test "the record carries each editable field's stored value and whether it offers editing",
         %{statement: statement} do
      {_components, detail} = surface(:admin_v1, statement)

      assert detail["_edit_title"] == "Annual fee"
      assert detail["_edit_amount_text"] == 1200
      assert detail["amount_text"] == "$1200"
      assert detail["_edit_kind"] == "invoice"
      assert detail["_editable_facts"] == true
      refute Map.has_key?(detail, "_edit_note")

      locked = Ash.update!(statement, %{locked: true}, authorize?: false)
      {_components, detail} = surface(:admin_v1, locked)
      assert detail["_editable_facts"] == false
    end

    test "the save bar comes last in the page, with what it counts and its dialog",
         %{statement: statement} do
      {components, detail} = surface(:admin_v1, statement)

      assert List.last(components["root"]["children"]) == "save_bar"
      bar = components["save_bar"]

      assert bar["component"] == "saveBar"
      assert bar["message"] == "You have unsaved changes"
      assert bar["messageWaiting"] == "Reviewing the statement"
      assert bar["status"] == "%{count} to check"
      assert bar["statusOne"] == "1 to check"
      assert bar["saveLabel"] == "Save changes"
      assert bar["discardLabel"] == "Discard changes"
      assert bar["editReviews"] == true
      assert bar["edits"] == %{"@path" => "/ui/edits"}
      assert bar["record"] == %{"@path" => "/detail/statement"}

      assert bar["reviews"] == [
               %{"component" => "facts", "field" => "title"},
               %{"component" => "facts", "field" => "amount_text"}
             ]

      assert bar["action"] == %{
               "action" => "save_changes",
               "context" => %{
                 "edits" => %{"@path" => "/ui/edits"},
                 "recordId" => %{"@path" => "/detail/statement/id"},
                 "contexts" => %{"@path" => "/context"}
               }
             }

      assert bar["confirm"] == %{
               "title" => "Save with %{count} values unchecked?",
               "titleOne" => "Save with 1 value unchecked?",
               "message" => "%{count} values still wait.",
               "cancelLabel" => "Cancel",
               "saveLabel" => "Save progress",
               "thenLabel" => "Save and finish",
               "then" => true,
               "thenVisible" => "review_open",
               "thenWhenClear" => false
             }

      # the record says whether the dialog's second choice is offered
      assert detail["review_open"] == true
    end

    test "catalog 3.14: the bar shows while values wait where the record's field says so",
         %{statement: statement} do
      {components, detail} = surface(:admin_v1, statement)

      assert components["save_bar"]["showWhileWaiting"] == "correctable"
      # the record carries the field gating it, read with the bar's record
      assert detail["correctable"] == true

      locked = Ash.update!(statement, %{locked: true}, authorize?: false)
      {_components, detail} = surface(:admin_v1, locked)
      assert detail["correctable"] == false
    end

    test "catalog 3.16: the bar counts the values reviewed with its own words",
         %{statement: statement} do
      {components, _detail} = surface(:admin_v1, statement)

      assert components["save_bar"]["statusReviewed"] == "%{count} checked"
      assert components["save_bar"]["statusReviewedOne"] == "1 checked"
    end

    test "the basic catalog draws the card read-only and no bar", %{statement: statement} do
      {components, _detail} = surface(:basic, statement)

      refute Enum.any?(Map.values(components), &Map.has_key?(&1, "edit"))
      refute Map.has_key?(components, "save_bar")
    end

    test "the admin catalog is 3.11 or later" do
      assert Version.match?(AshA2ui.Experience.admin_catalog_version(), ">= 3.11.0")
    end
  end

  describe "save_changes" do
    test "runs the card's update action with the changed fields, as the attributes they edit",
         %{statement: statement} do
      assert {:ok, messages} =
               save(statement, %{"title" => "Yearly fee", "amount_text" => "1400"})

      saved = reload(statement)
      assert saved.title == "Yearly fee"
      assert saved.amount == 1400
      refute saved.reviewed

      assert write(messages, "/ui/edits") == {:ok, %{}}
      assert write(messages, "/ui/edit_errors") == {:ok, %{}}
      assert {:ok, detail} = write(messages, "/detail/statement")
      assert detail["title"] == "Yearly fee"
      assert detail["amount_text"] == "$1400"
      assert detail["_edit_amount_text"] == 1400

      assert Messages.feedback(messages)["kind"] == "success"
      assert Messages.feedback(messages)["message"] == "Changes saved."
    end

    test "a cleared input saves no value", %{statement: statement} do
      assert {:ok, _messages} = save(statement, %{"amount_text" => ""})
      assert reload(statement).amount == nil
    end

    test "then runs the confirm's then_action after the save", %{statement: statement} do
      assert {:ok, messages} = save(statement, %{"kind" => "quote"}, choice: "then")

      saved = reload(statement)
      assert saved.kind == :quote
      assert saved.reviewed

      assert {:ok, detail} = write(messages, "/detail/statement")
      assert detail["review_open"] == false
      assert Messages.feedback(messages)["message"] == "Saved and finished."
    end

    test "then is refused, and nothing saved, on a record that does not offer it",
         %{statement: statement} do
      Ash.update!(statement, %{reviewed: true}, authorize?: false)

      assert {:error, messages} = save(statement, %{"title" => "Yearly fee"}, choice: "then")
      assert reload(statement).title == "Annual fee"
      assert Messages.feedback(messages)["kind"] == "error"
    end

    test "is refused, and nothing saved, on a record that does not offer editing",
         %{statement: statement} do
      Ash.update!(statement, %{locked: true}, authorize?: false)

      assert {:error, messages} = save(statement, %{"title" => "Yearly fee"})
      assert reload(statement).title == "Annual fee"

      assert Messages.feedback(messages)["message"] ==
               "Editing is not available for this record."
    end

    test "a field the card does not edit is refused", %{statement: statement} do
      assert {:error, messages} = save(statement, %{"note" => "hand-written"})
      assert reload(statement).note == nil
      assert Messages.feedback(messages)["message"] =~ "not an editable field"
    end

    test "a card that is not editable is refused", %{statement: statement} do
      edits = %{"other" => %{"recordId" => statement.id, "values" => %{"title" => "x"}}}

      assert {:error, messages} = save(statement, nil, edits: edits)
      assert Messages.feedback(messages)["message"] =~ "no editable :detail"
    end

    test "a refusal keeps the changes and says why at the field's input",
         %{statement: statement} do
      assert {:error, messages} = save(statement, %{"amount_text" => "-5"})

      assert reload(statement).amount == 1200
      assert {:ok, %{"facts" => %{"amount_text" => text}}} = write(messages, "/ui/edit_errors")
      assert text =~ "greater than or equal to 0"
      refute write(messages, "/ui/edits")
      assert Messages.feedback(messages)["kind"] == "error"
    end

    test "nothing to save is refused", %{statement: statement} do
      assert {:error, messages} = save(statement, %{})
      assert Messages.feedback(messages)["message"] == "Nothing to save."
    end

    test "then with no change runs the then_action alone and writes no correction",
         %{statement: statement} do
      assert {:ok, messages} = save(statement, nil, edits: %{}, choice: "then")

      saved = reload(statement)
      assert saved.reviewed
      assert saved.title == "Annual fee"
      assert saved.amount == 1200

      assert write(messages, "/ui/edits") == {:ok, %{}}
      assert {:ok, detail} = write(messages, "/detail/statement")
      assert detail["review_open"] == false
      assert Messages.feedback(messages)["message"] == "Saved and finished."
    end
  end

  describe "the verifiers" do
    test "an editable detail card needs a save bar" do
      result =
        capture_io(:stderr, fn ->
          defmodule EditableWithoutBar do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :facts do
                context :statement
                fields [:title]

                editable do
                  fields [:title]
                  update_action :correct
                end
              end
            end
          end
        end)

      assert result =~ ~r/has no save_bar/
    end

    test "an edited attribute the update action does not accept does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule EditableNotAccepted do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :facts do
                context :statement
                fields [:title, :amount_text]

                editable do
                  fields [:amount_text]
                  update_action :review
                end
              end

              field :amount_text, do: edit(:amount)

              save_bar do
                context :statement
              end
            end
          end
        end)

      assert result =~ ~r/editable field :amount_text \(edited as :amount\) is not accepted/
    end

    test "a confirm's then_action must be an update action of the bar's record" do
      result =
        capture_io(:stderr, fn ->
          defmodule BarThenUnknown do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :facts do
                context :statement
                fields [:title]

                editable do
                  fields [:title]
                  update_action :correct
                end
              end

              save_bar do
                context :statement

                confirm do
                  title "Sure?"
                  then_action(:finish)
                end
              end
            end
          end
        end)

      assert result =~ ~r/then_action :finish is not an update action/
    end

    test "show_while_waiting names a field of the bar's record" do
      result =
        capture_io(:stderr, fn ->
          defmodule BarShowUnknown do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :facts do
                context :statement
                fields [:title]

                editable do
                  fields [:title]
                  update_action :correct
                end
              end

              save_bar do
                context :statement
                show_while_waiting(:nowhere)
              end
            end
          end
        end)

      assert result =~ ~r/show_while_waiting :nowhere is not an attribute/
    end

    test "show_while_waiting true shows the bar on every record" do
      defmodule BarShowAlways do
        @moduledoc false
        use AshA2ui.Standalone

        a2ui do
          for_resource AshA2ui.Test.Statement

          context :statement do
            resource AshA2ui.Test.Statement
            picker false
          end

          component :detail, :facts do
            context :statement
            fields [:title]

            editable do
              fields [:title]
              update_action :correct
            end
          end

          save_bar do
            context :statement
            show_while_waiting(true)
          end
        end
      end

      assert AshA2ui.Info.save_bar(BarShowAlways).show_while_waiting == true
      # no reviewed tag unless the bar declares one
      bar = AshA2ui.Info.save_bar(BarShowAlways)
      assert bar.status_reviewed == nil and bar.status_reviewed_one == nil
      assert AshA2ui.SaveBar.show_field(AshA2ui.Info.save_bar(BarShowAlways)) == nil
      assert AshA2ui.Info.save_bar(StatementEditUI).show_while_waiting == :correctable
    end
  end
end
