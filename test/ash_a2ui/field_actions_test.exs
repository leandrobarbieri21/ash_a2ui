defmodule AshA2ui.FieldActionsTest do
  @moduledoc """
  Admin catalog 3.2 field actions: a field's `field_action` names an update
  action of the detail card's record, drawn as a button beside the value
  (`action`, gated per record by `actionVisible`) and run through the
  `field_action` ashAction with the field's name as its `:field` argument.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.{Finding, FindingFieldsUI, Messages, SchemaHelper}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(Finding)
    end)

    finding = Ash.create!(Finding, %{title: "Annual fee", amount: 1200}, authorize?: false)
    %{finding: finding}
  end

  defp contexts(finding), do: %{"finding" => %{"value" => finding.id, "label" => finding.title}}

  defp surface(catalog, finding) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(FindingFieldsUI,
        authorize?: false,
        context_state: %{"finding" => %{"search" => "", "value" => finding.id, "label" => "x"}}
      )

    catalogs = if catalog == :admin_v1, do: SchemaHelper.admin_catalogs()
    SchemaHelper.assert_valid_agent_message(message, catalogs: catalogs)

    {Map.new(surface["components"], &{&1["id"], &1}), surface["dataModel"]["detail"]["finding"]}
  end

  defp field_action(finding, field, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    context =
      %{
        "component" => Keyword.get(opts, :component, "facts"),
        "field" => field,
        "recordId" => Keyword.get(opts, :record_id, finding.id),
        "contexts" => contexts(finding)
      }

    ActionHandler.handle(
      FindingFieldsUI,
      Messages.call("field_action", "finding_fields", context),
      authorize?: false
    )
  end

  defp detail_write(messages) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/detail/finding", "value" => value}} -> value
      _other -> nil
    end)
  end

  describe "the wire" do
    test "a field action's button rides on its fieldDisplay, like a row action entry",
         %{finding: finding} do
      {components, _detail} = surface(:admin_v1, finding)

      assert components["detail_facts_field_title"]["action"] == %{
               "label" => "Mark as checked",
               "icon" => "check",
               "action" => "field_action",
               "context" => %{
                 "component" => "facts",
                 "field" => "title",
                 "recordId" => %{"@path" => "/detail/finding/id"},
                 "contexts" => %{"@path" => "/context"}
               }
             }

      assert components["detail_facts_field_title"]["actionVisible"] ==
               %{"@path" => "/detail/finding/_action_title"}

      assert components["detail_facts_field_amount"]["action"]["context"]["field"] == "amount"
      refute Map.has_key?(components["detail_facts_field_note"], "action")
      refute Map.has_key?(components["detail_facts_field_note"], "actionVisible")
    end

    test "the detail record says, per field, whether the record offers it", %{finding: finding} do
      {_components, detail} = surface(:admin_v1, finding)

      assert detail["_action_title"] == true
      assert detail["_action_amount"] == true
      refute Map.has_key?(detail, "_action_note")
      # the gate is loaded for the button, not drawn as a field
      refute Map.has_key?(detail, "title_open")

      checked = Ash.update!(finding, %{checked_fields: [:title]}, authorize?: false)
      {_components, detail} = surface(:admin_v1, checked)
      assert detail["_action_title"] == false
    end

    test "the basic catalog draws no button", %{finding: finding} do
      {components, _detail} = surface(:basic, finding)

      refute Enum.any?(Map.values(components), &Map.has_key?(&1, "actionVisible"))
    end

    test "the admin catalog is 3.2" do
      assert AshA2ui.Experience.admin_catalog_version() == "3.2.0"
    end
  end

  describe "field_action" do
    test "runs the field's action with the field's name, and sends the card's record again",
         %{finding: finding} do
      assert {:ok, messages} = field_action(finding, "title")

      assert Ash.get!(Finding, finding.id, authorize?: false).checked_fields == [:title]

      detail = detail_write(messages)
      assert detail["id"] == finding.id
      assert detail["_action_title"] == false
      assert detail["_action_amount"] == true

      assert Messages.response(messages)["value"]["kind"] == "success"
    end

    test "is refused on a record that does not offer it", %{finding: finding} do
      Ash.update!(finding, %{checked_fields: [:title]}, authorize?: false)

      assert {:error, messages} = field_action(finding, "title")
      assert Messages.response(messages)["error"]

      assert Ash.get!(Finding, finding.id, authorize?: false).checked_fields == [:title]
    end

    test "a field action without a gate is offered on every record", %{finding: finding} do
      assert {:ok, _messages} = field_action(finding, "amount")
      assert {:ok, _messages} = field_action(finding, "amount")

      assert Ash.get!(Finding, finding.id, authorize?: false).checked_fields == [:amount]
    end

    test "only a field the card declares one for: the client never names the action",
         %{finding: finding} do
      assert {:error, _messages} = field_action(finding, "note")
      assert {:error, _messages} = field_action(finding, "title", component: "elsewhere")
      assert {:error, _messages} = field_action(finding, "checked_fields")

      assert Ash.get!(Finding, finding.id, authorize?: false).checked_fields == []
    end

    test "a record the card's context cannot read is refused", %{finding: finding} do
      assert {:error, _messages} = field_action(finding, "title", record_id: Ash.UUID.generate())
      assert {:error, _messages} = field_action(finding, "title", record_id: "")
    end

    test "a surface pinned to an earlier moment refuses it", %{finding: finding} do
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)

      context = %{
        "component" => "facts",
        "field" => "title",
        "recordId" => finding.id,
        "contexts" => contexts(finding)
      }

      assert {:error, _messages} =
               ActionHandler.handle(
                 FindingFieldsUI,
                 Messages.call("field_action", "finding_fields", context),
                 authorize?: false,
                 as_of: ~U[2026-01-01 00:00:00Z]
               )

      assert Ash.get!(Finding, finding.id, authorize?: false).checked_fields == []
    end
  end

  test "dynamic specs carry field actions and the action's icon" do
    {:ok, spec, _rejections} = Importer.import(FindingFieldsUI)

    title = Enum.find(spec["fields"], &(&1["name"] == "title"))
    assert title["field_action"] == "check_field"
    assert title["field_action_visible"] == "title_open"
    assert Enum.find(spec["actions"], &(&1["name"] == "check_field"))["icon"] == "check"

    allow = AshA2ui.Dynamic.allowlist([Finding])
    assert {:ok, %AshA2ui.Dynamic.Surface{}} = AshA2ui.Dynamic.resolve(spec, allowlist: allow)
  end

  describe "compile-time checks" do
    defp compile(name, field_body) do
      capture_io(:stderr, fn ->
        Code.eval_quoted(
          quote do
            defmodule unquote(Module.concat(__MODULE__, name)) do
              @moduledoc false
              use AshA2ui.Standalone

              a2ui do
                for_resource AshA2ui.Test.Finding

                context :finding do
                  resource AshA2ui.Test.Finding
                  picker false
                end

                component :detail, :facts do
                  context :finding
                  fields [:title]
                end

                field :title, do: unquote(field_body)
              end
            end
          end
        )
      end)
    end

    test "a field action that is not an update action of the card's record" do
      assert compile("NotUpdate", quote(do: field_action(:read))) =~
               ~r/field_action names :read, which is not an update action/
    end

    test "a field action without a :field argument" do
      assert compile("NoFieldArgument", quote(do: field_action(:update))) =~
               ~r/declares no :field argument/
    end

    test "a gate that is not a field of the card's record" do
      body =
        quote do
          field_action(:check_field)
          field_action_visible(:nope)
        end

      assert compile("UnknownGate", body) =~ ~r/field_action_visible names :nope/
    end
  end
end
