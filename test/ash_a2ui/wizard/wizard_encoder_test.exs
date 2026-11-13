defmodule AshA2ui.Wizard.WizardEncoderTest do
  @moduledoc """
  A2UI-106/AC-1: a stepped form encodes the /ui/wizard state and the
  wizard composition, and forms without steps carry none of it.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Encoder
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Enrollment
  alias AshA2ui.Test.KitchenSink

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    :ok
  end

  # Full surfaces of forms without steps, under the basic and admin
  # catalogs. First captured before wizard steps existed (08f8173);
  # re-baselined when /ui/status was removed and again for the A2UI 1.0
  # wire, each time with no change to the forms themselves.
  @baseline_dir Path.expand("baseline", __DIR__)

  @baseline_fixtures [
    {"kitchen_sink", KitchenSink},
    {"experience_task", AshA2ui.Test.Experience.Task},
    {"ticket", AshA2ui.Test.Ticket},
    {"ticket_search", AshA2ui.Test.TicketSearchUI}
  ]

  @baseline_configs [
    {"basic", :basic},
    {"admin", :admin_v1}
  ]

  defp parts(module) do
    [%{"createSurface" => %{"components" => components, "dataModel" => data}} = create] =
      AshA2ui.Info.build_surface(module)

    assert_valid_agent_message(create)

    {Map.new(components, &{&1["id"], &1}), data}
  end

  defp assert_wizard_state(model) do
    wizard = model["ui"]["wizard"]

    assert wizard["index"] == 0

    assert wizard["steps"] == [
             %{"name" => "who", "label" => "Who", "state" => "current"},
             %{"name" => "what", "label" => "What", "state" => "todo"},
             %{"name" => "confirm", "label" => "Confirm", "state" => "todo"}
           ]

    # only the first step's fields are visible
    assert wizard["who_visible"] == [%{"id" => "on"}]
    assert wizard["what_visible"] == []
    assert wizard["confirm_visible"] == []

    assert wizard["nav"] == %{
             "back_visible" => [],
             "next_visible" => [%{"id" => "on"}]
           }
  end

  defp assert_wizard_components(comps) do
    assert comps["form_wizard"]["children"] == [
             "form_wizard_progress",
             "form_step_who_slot",
             "form_step_what_slot",
             "form_step_confirm_slot",
             "form_wizard_nav"
           ]

    assert comps["form_wizard_progress"]["children"] == %{
             "componentId" => "form_wizard_progress_item",
             "path" => "/ui/wizard/steps"
           }

    # each step page sits behind its zero-or-one sentinel
    for step <- ~w(who what confirm) do
      assert comps["form_step_#{step}_slot"]["children"] == %{
               "componentId" => "form_step_#{step}",
               "path" => "/ui/wizard/#{step}_visible"
             }
    end

    # step one holds exactly its own fields' inputs
    who = comps["form_step_who"]["children"]
    assert "form_input_name" in who and "form_input_email" in who
    refute "form_input_role" in who or "form_input_team" in who

    what = comps["form_step_what"]["children"]
    assert "form_input_role" in what and "form_input_team" in what

    # the review step is a read-only summary of /form
    assert "form_review_name" in comps["form_step_confirm"]["children"]
    assert comps["form_review_team_value"]["text"] == %{"@path" => "/form/team"}

    refute Enum.any?(
             comps["form_step_confirm"]["children"],
             &String.starts_with?(&1, "form_input")
           )

    # Back and Next controls
    assert comps["form_wizard_nav"]["children"] == [
             "form_wizard_back_slot",
             "form_wizard_next_slot"
           ]

    assert %{
             "functionCall" => %{
               "@call" => "ashAction",
               "args" => %{"name" => "wizard_back", "context" => back}
             }
           } =
             comps["form_wizard_back_button"]["action"]

    assert back["index"] == %{"@path" => "/ui/wizard/index"}

    assert %{
             "functionCall" => %{
               "@call" => "ashAction",
               "args" => %{"name" => "wizard_next", "context" => next}
             }
           } =
             comps["form_wizard_next_button"]["action"]

    assert next["values"] == %{"@path" => "/form"}
    assert next["index"] == %{"@path" => "/ui/wizard/index"}
  end

  @tag ac: "A2UI-106/AC-1"
  test "encodes steps" do
    {comps, model} = parts(Enrollment)
    assert_wizard_state(model)
    assert_wizard_components(comps)

    # The wizard is the panel's form content; the Next label is the panel's
    # primary label and the submit keeps the panel's submit gate.
    assert comps["form_fields"]["children"] == ["form_wizard"]
    assert comps["form_wizard_next_text"]["text"] == %{"@path" => "/ui/panel/primary_label"}
    refute Map.has_key?(comps, "form_wizard_submit_slot")

    assert comps["form_submit_slot"]["children"] == %{
             "componentId" => "form_submit_button",
             "path" => "/ui/panel/submit_visible"
           }
  end

  @tag ac: "A2UI-106/AC-1"
  test "forms without steps carry no wizard state or components" do
    {comps, model} = parts(KitchenSink)
    refute Map.has_key?(model["ui"], "wizard")

    refute Enum.any?(Map.keys(comps), fn id ->
             String.starts_with?(id, "form_wizard") or String.starts_with?(id, "form_step_")
           end)

    assert List.first(comps["form_fields"]["children"]) == "form_input_active"
  end

  @tag ac: "A2UI-106/AC-1"
  test "removing the steps from a stepped view restores the plain form encoding" do
    view = ResolvedView.resolve(Enrollment)

    plain =
      update_in(view.components, fn components ->
        Enum.map(components, &%{&1 | steps: []})
      end)

    [%{"createSurface" => %{"components" => components, "dataModel" => data}}] =
      Encoder.encode_surface(plain, [], [])

    ids = Enum.map(components, & &1["id"])

    refute Enum.any?(ids, &String.starts_with?(&1, "form_wizard"))
    refute Map.has_key?(data["ui"], "wizard")

    fields =
      Enum.find(components, &(&1["id"] == "form_fields"))

    assert fields["children"] == [
             "form_input_name",
             "form_error_name",
             "form_input_email",
             "form_error_email",
             "form_input_role",
             "form_error_role",
             "form_input_team",
             "form_error_team"
           ]
  end

  @tag ac: "A2UI-106/AC-1"
  test "forms without steps encode exactly as they did before wizard steps" do
    for {config, catalog} <- @baseline_configs,
        {fixture, module} <- @baseline_fixtures do
      Application.put_env(:ash_a2ui, :catalog, catalog)

      path = Path.join(@baseline_dir, "#{fixture}.#{config}.json")
      encoded = module |> AshA2ui.Info.build_surface() |> Jason.encode!() |> Jason.decode!()

      # Re-record on purpose with RECORD_WIZARD_BASELINE=1.
      if System.get_env("RECORD_WIZARD_BASELINE"),
        do: File.write!(path, Jason.encode!(encoded, pretty: true))

      assert encoded == path |> File.read!() |> Jason.decode!(),
             "#{fixture} (#{config}) no longer matches #{Path.relative_to_cwd(path)}"
    end
  end

  @tag ac: "A2UI-106/AC-1"
  test "the review step shows a searchable select's label, not its id" do
    {comps, model} = parts(AshA2ui.Test.TicketWizardUI)

    assert comps["form_review_author_id_value"]["text"] == %{
             "@path" => "/select/author_id/label"
           }

    assert comps["form_review_subject_value"]["text"] == %{"@path" => "/form/subject"}
    assert model["select"]["author_id"] == %{"search" => "", "label" => ""}
  end
end
