defmodule AshA2ui.Adoption.ActionLabelsTest do
  @moduledoc """
  An `action` entity's `label` names its buttons — row, bulk and prompt, in
  both compositions — so a host needs no thin wrapper action just to get a
  readable label ("Confirm match"). Without one, the label stays the
  humanized action name.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.Adoption.{Job, LabelledBulkJobsUI, LabelledJobsUI}

  @red %{id: "u-red", team: "red"}

  setup do
    Job |> Ash.read!(actor: @red) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    %{job: Ash.create!(Job, %{title: "Open job", team: "red"}, authorize?: false)}
  end

  # The basic emission validates against the vendored v0.9.1 schemas; the
  # admin emission's custom kinds are pinned by the admin catalog instead.
  defp components(ui \\ LabelledJobsUI) do
    messages = AshA2ui.Info.build_surface(ui, actor: @red)
    unless AshA2ui.Experience.admin?(), do: Enum.each(messages, &assert_valid_server_message/1)

    messages
    |> Enum.find_value(& &1["updateComponents"])
    |> Map.fetch!("components")
    |> Map.new(&{&1["id"], &1})
  end

  test "basic composition: row, prompt and bulk buttons carry the label" do
    by_id = components()

    assert by_id["row_action_claim_text"]["text"] == "Take it"
    assert by_id["row_action_assign_text"]["text"] == "Assign clerk"
    assert by_id["row_action_assign_prompt_title"]["text"] == "Assign clerk"
    assert components(LabelledBulkJobsUI)["bulk_action_claim_text"]["text"] == "Take it"
    # No label: the humanized action name, as before.
    assert by_id["row_action_lock_text"]["text"] == "Lock"
  end

  test "admin composition: rowActions entries carry the label" do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)

    by_id = components()
    labels = Map.new(by_id["data_grid"]["rowActions"], &{&1["label"], &1["context"]["action"]})

    assert labels["Take it"] == "claim"
    assert labels["Assign clerk"] == "assign"
    assert labels["Lock"] == "lock"

    assert hd(Enum.filter(by_id["data_grid"]["rowActions"], &(&1["label"] == "Assign clerk")))[
             "prompt"
           ]["title"] ==
             "Assign clerk"
  end

  test "the bulk run's status line uses the label", %{job: job} do
    envelope = %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "bulk_invoke",
        "surfaceId" => "adoption_labelled_bulk_jobs",
        "sourceComponentId" => "test",
        "timestamp" => "2026-10-16T00:00:00Z",
        "context" => %{
          "action" => "claim",
          "component" => "table",
          "records" => [%{"id" => job.id, "_selected" => true}]
        }
      }
    }

    assert {:ok, messages} = ActionHandler.handle(LabelledBulkJobsUI, envelope, actor: @red)

    feedback =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value}} -> value
        _other -> nil
      end)

    assert feedback["message"] == "Take it: 1 of 1 selected records done."
  end

  test "a single-row invoke's success status uses the label", %{job: job} do
    invoke = fn ui, surface_id, action ->
      ActionHandler.handle(
        ui,
        %{
          "version" => "v0.9.1",
          "action" => %{
            "name" => "invoke",
            "surfaceId" => surface_id,
            "sourceComponentId" => "test",
            "timestamp" => "2026-10-16T00:00:00Z",
            "context" => %{"action" => action, "recordId" => job.id, "component" => "table"}
          }
        },
        actor: @red
      )
    end

    feedback = fn messages ->
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value}} -> value
        _other -> nil
      end)
    end

    assert {:ok, messages} = invoke.(LabelledJobsUI, "adoption_labelled_jobs", "claim")
    assert feedback.(messages) == %{"kind" => "success", "message" => "Take it: done."}
  end

  test "the dynamic spec carries the label: resolve, import and promote" do
    allowlist = Dynamic.allowlist([Job])

    spec = %{
      "resource" => "Job",
      "components" => [%{"kind" => "table", "fields" => ["title"], "row_actions" => ["claim"]}],
      "actions" => [%{"name" => "claim", "label" => "Take it"}]
    }

    assert {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)

    [_create, components, _data] = Dynamic.build_surface(surface, actor: @red)

    text =
      Enum.find(
        components["updateComponents"]["components"],
        &(&1["id"] == "row_action_claim_text")
      )

    assert text["text"] == "Take it"

    assert {:ok, imported, _surface_id_rejection} =
             Importer.import(LabelledJobsUI)

    assert %{"name" => "claim", "label" => "Take it"} =
             Enum.find(imported["actions"], &(&1["name"] == "claim"))

    assert {:ok, source} =
             Dynamic.to_dsl_source(spec, module: Promoted.LabelUI, allowlist: allowlist)

    assert source =~ ~s(label "Take it")
  end
end
