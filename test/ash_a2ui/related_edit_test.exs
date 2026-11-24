defmodule AshA2ui.RelatedEditTest do
  @moduledoc """
  Editing a related record's values in place: a `:detail` field whose `edit`
  names `[relationship, attribute]` opens as the input of that attribute of
  the record a `belongs_to` or `has_one` leads to, starts from its value,
  and is saved through the card's update action as the relationship's
  argument, the map `manage_relationship` takes, holding the related
  record's primary key.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Messages, SchemaHelper, Statement, StatementTerm, StatementTermEditUI}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(Statement)
      Ets.stop(StatementTerm)
    end)

    statement = Ash.create!(Statement, %{title: "Annual fee", amount: 1200}, authorize?: false)

    term =
      Ash.create!(
        StatementTerm,
        %{statement_id: statement.id, ends_on: ~D[2027-06-30], notice_days: 30, renewal: :manual},
        authorize?: false
      )

    %{statement: statement, term: term}
  end

  defp surface(statement) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(StatementTermEditUI,
        authorize?: false,
        context_state: %{
          "statement" => %{"search" => "", "value" => statement.id, "label" => "x"}
        }
      )

    SchemaHelper.assert_valid_agent_message(message, catalogs: SchemaHelper.admin_catalogs())

    {Map.new(surface["components"], &{&1["id"], &1}), surface["dataModel"]["detail"]["statement"]}
  end

  defp save(statement, values) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    context = %{
      "edits" => %{"term" => %{"recordId" => statement.id, "values" => values}},
      "choice" => "save",
      "recordId" => statement.id,
      "contexts" => %{"statement" => %{"value" => statement.id, "label" => statement.title}}
    }

    ActionHandler.handle(
      StatementTermEditUI,
      Messages.call("save_changes", "statement_term_edit", context),
      authorize?: false
    )
  end

  defp write(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> {:ok, value}
      _other -> nil
    end)
  end

  defp reload(record), do: Ash.get!(record.__struct__, record.id, authorize?: false)

  describe "the wire" do
    test "a field edited through a relationship takes the related attribute's input",
         %{statement: statement} do
      {components, _detail} = surface(statement)

      assert components["detail_term_field_term_ends_text"]["edit"]["input"] == "date"
      assert components["detail_term_field_term_notice_text"]["edit"]["input"] == "integer"

      renewal = components["detail_term_field_term_renewal_text"]["edit"]
      assert renewal["input"] == "choice"
      assert Enum.map(renewal["options"], & &1["value"]) == ["manual", "automatic"]

      assert components["detail_term_field_term_ends_text"]["editValue"] ==
               %{"@path" => "/detail/statement/_edit_term_ends_text"}
    end

    test "the input starts from the related record's value", %{statement: statement} do
      {_components, detail} = surface(statement)

      assert detail["term_ends_text"] == "2027-06-30"
      assert detail["_edit_term_ends_text"] == "2027-06-30"
      assert detail["_edit_term_notice_text"] == 30
      assert detail["_edit_term_renewal_text"] == "manual"
      assert detail["_edit_title"] == "Annual fee"
    end

    test "with no related record the input starts empty" do
      bare = Ash.create!(Statement, %{title: "No term"}, authorize?: false)
      {_components, detail} = surface(bare)

      assert detail["_edit_term_ends_text"] == nil
      assert detail["_edit_term_renewal_text"] == nil
      assert detail["_editable_term"] == true
    end
  end

  describe "save_changes" do
    test "saves the related values through the card's action, with the record's own",
         %{statement: statement, term: term} do
      assert {:ok, messages} =
               save(statement, %{
                 "title" => "Yearly fee",
                 "term_ends_text" => "2028-01-31",
                 "term_notice_text" => "60",
                 "term_renewal_text" => "automatic"
               })

      assert reload(statement).title == "Yearly fee"

      saved = reload(term)
      assert saved.ends_on == ~D[2028-01-31]
      assert saved.notice_days == 60
      assert saved.renewal == :automatic

      assert {:ok, detail} = write(messages, "/detail/statement")
      assert detail["term_ends_text"] == "2028-01-31"
      assert detail["_edit_term_notice_text"] == 60
      assert Messages.feedback(messages)["kind"] == "success"
    end

    test "only the changed related value moves", %{statement: statement, term: term} do
      assert {:ok, _messages} = save(statement, %{"term_notice_text" => "45"})

      saved = reload(term)
      assert saved.notice_days == 45
      assert saved.ends_on == ~D[2027-06-30]
      assert saved.renewal == :manual
    end

    test "a related record's refusal is shown at the field's input, and nothing is saved",
         %{statement: statement, term: term} do
      Ash.update!(term, %{locked: true}, authorize?: false)

      assert {:error, messages} = save(statement, %{"term_ends_text" => "2028-01-31"})

      assert reload(term).ends_on == ~D[2027-06-30]

      assert {:ok, %{"term" => %{"term_ends_text" => text}}} =
               write(messages, "/ui/edit_errors")

      assert text =~ "never corrected"
      assert Messages.feedback(messages)["kind"] == "error"
    end

    test "a related value the related action refuses is shown at its input",
         %{statement: statement, term: term} do
      assert {:error, messages} = save(statement, %{"term_notice_text" => "-1"})

      assert reload(term).notice_days == 30

      assert {:ok, %{"term" => %{"term_notice_text" => text}}} =
               write(messages, "/ui/edit_errors")

      assert text =~ "greater than or equal to 0"
    end
  end

  describe "the verifier" do
    test "the update action must take the relationship's argument" do
      result =
        capture_io(:stderr, fn ->
          defmodule RelatedNoArgument do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :term do
                context :statement
                fields [:term_ends_text]

                editable do
                  fields [:term_ends_text]
                  update_action :review
                end
              end

              field :term_ends_text, do: edit([:term, :ends_on])

              save_bar do
                context :statement
              end
            end
          end
        end)

      assert result =~ ~r/edits through :term, but update action :review takes no :term argument/
    end

    test "the attribute must be the related resource's" do
      result =
        capture_io(:stderr, fn ->
          defmodule RelatedNoAttribute do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :term do
                context :statement
                fields [:term_ends_text]

                editable do
                  fields [:term_ends_text]
                  update_action :correct
                end
              end

              field :term_ends_text, do: edit([:term, :starts_on])

              save_bar do
                context :statement
              end
            end
          end
        end)

      assert result =~ ~r/names no attribute of AshA2ui.Test.StatementTerm/
    end

    test "the relationship must lead to one record" do
      result =
        capture_io(:stderr, fn ->
          defmodule RelatedNotToOne do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :term do
                context :statement
                fields [:term_ends_text]

                editable do
                  fields [:term_ends_text]
                  update_action :correct
                end
              end

              field :term_ends_text, do: edit([:terms, :ends_on])

              save_bar do
                context :statement
              end
            end
          end
        end)

      assert result =~ ~r/edits through :terms, which is not a belongs_to or has_one/
    end
  end
end
