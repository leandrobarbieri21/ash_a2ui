defmodule AshA2ui.StepFieldsTest do
  @moduledoc """
  Catalog 1.17 step fields: a field's `steps` draws a list of steps as a
  numbered stepper on a detail card, and as one Text row per step on the
  basic catalog.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Steps
  alias AshA2ui.Test.{Appointment, Clinic, Messages, Owner, SchemaHelper, VisitProgressUI}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    visit =
      Ash.create!(
        Appointment,
        %{title: "Checkup", status: :completed, owner_id: owner.id, clinic_id: clinic.id},
        authorize?: false
      )

    %{visit: visit}
  end

  defp surface(catalog, visit) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(VisitProgressUI,
        authorize?: false,
        context_state: %{
          "appointment" => %{"search" => "", "value" => visit.id, "label" => "x"}
        }
      )

    catalogs = if catalog == :admin_v1, do: SchemaHelper.admin_catalogs()
    SchemaHelper.assert_valid_agent_message(message, catalogs: catalogs)

    {Map.new(surface["components"], &{&1["id"], &1}),
     surface["dataModel"]["detail"]["appointment"]}
  end

  describe "the wire" do
    test "the admin fieldDisplay binds the steps", %{visit: visit} do
      {components, _detail} = surface(:admin_v1, visit)
      display = components["detail_progress_field_progress"]

      assert display["component"] == "fieldDisplay"
      assert display["steps"] == %{"@path" => "/detail/appointment/_steps_progress"}
      assert display["value"] == %{"@path" => "/detail/appointment/progress"}
      assert display["emptyText"] == "No steps yet"
      refute Map.has_key?(components["detail_progress_field_title"], "steps")
    end

    test "the detail record carries the numbered steps", %{visit: visit} do
      {_components, detail} = surface(:admin_v1, visit)

      assert [booked, checked_in, seen, billed] = detail["_steps_progress"]

      assert booked == %{
               "number" => 1,
               "label" => "Booked",
               "text" => "Requested online",
               "state" => "complete",
               "stateLabel" => "Complete",
               "line" => "1. Booked · Complete · Requested online"
             }

      assert checked_in["number"] == 2
      assert seen["text"] == "Checkup"

      assert billed == %{
               "number" => 4,
               "label" => "Billed",
               "text" => "Not yet",
               "note" => "Invoice not sent",
               "state" => "overdue",
               "stateLabel" => "Overdue",
               "line" => "4. Billed · Overdue · Not yet · Invoice not sent"
             }
    end

    test "the basic catalog draws one Text row per step", %{visit: visit} do
      {components, detail} = surface(:basic, visit)

      assert components["detail_progress_field_progress"]["children"] ==
               ["detail_progress_label_progress", "detail_progress_value_progress"]

      assert components["detail_progress_value_progress"] == %{
               "id" => "detail_progress_value_progress",
               "component" => "Column",
               "children" => %{
                 "componentId" => "detail_progress_step_progress",
                 "path" => "/detail/appointment/_steps_progress"
               }
             }

      assert components["detail_progress_step_progress"] == %{
               "id" => "detail_progress_step_progress",
               "component" => "Text",
               "text" => %{"@path" => "line"}
             }

      assert Enum.map(detail["_steps_progress"], & &1["line"]) == [
               "1. Booked · Complete · Requested online",
               "2. Checked in · Complete · At the front desk",
               "3. Seen · Complete · Checkup",
               "4. Billed · Overdue · Not yet · Invoice not sent"
             ]
    end

    test "selecting a record refreshes its steps", %{visit: visit} do
      {:ok, messages} =
        ActionHandler.handle(
          VisitProgressUI,
          Messages.call("context_select", "visit_progress", %{
            "context" => "appointment",
            "value" => visit.id
          })
        )

      detail =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/detail/appointment", "value" => value}} -> value
          _other -> nil
        end)

      assert length(detail["_steps_progress"]) == 4
      assert hd(detail["_steps_progress"])["label"] == "Booked"
    end
  end

  describe "normalize/2" do
    test "states as atoms or strings; a missing or unknown state is upcoming" do
      steps =
        Steps.normalize([
          %{label: "Placed", state: :complete},
          %{"label" => "Packed", "state" => "current"},
          %{label: "Shipped", state: "lost"},
          %{label: "Delivered"}
        ])

      assert Enum.map(steps, & &1["state"]) == ["complete", "current", "upcoming", "upcoming"]

      assert Enum.map(steps, & &1["stateLabel"]) ==
               ["Complete", "Current", "Upcoming", "Upcoming"]
    end

    test "a step without a label is left out and the rest are numbered 1..n" do
      steps =
        Steps.normalize([
          %{label: "Placed", state: :complete},
          %{text: "no label", state: :current},
          %{label: "", state: :current},
          "Packed",
          %{label: "Shipped", state: :upcoming}
        ])

      assert Enum.map(steps, &{&1["number"], &1["label"]}) == [{1, "Placed"}, {2, "Shipped"}]
    end

    test "text and note: blanks are left out, dates and numbers written out" do
      [step] =
        Steps.normalize([%{label: "Shipped", text: ~D[2026-11-03], note: "", state: :current}])

      assert step["text"] == "2026-11-03"
      refute Map.has_key?(step, "note")

      [step] = Steps.normalize([%{label: "Packed", text: 3, note: %{a: 1}}])
      assert step["text"] == "3"
      refute Map.has_key?(step, "note")
    end

    test "a value that is not a list has no steps" do
      assert Steps.normalize(nil) == []
      assert Steps.normalize("") == []
      assert Steps.normalize(%{label: "Placed"}) == []
    end

    test "the state's words are library strings" do
      pot = File.read!("priv/gettext/ash_a2ui.pot")

      for words <- ~w(Complete Current Upcoming Overdue),
          do: assert(pot =~ ~s(msgid "#{words}"), "#{words} is not in the shipped catalog")
    end
  end

  test "dynamic specs carry the steps option" do
    {:ok, spec, _rejections} = Importer.import(VisitProgressUI)

    assert Enum.find(spec["fields"], &(&1["name"] == "progress"))["steps"] == true

    allow = AshA2ui.Dynamic.allowlist([Owner, Appointment, Clinic])
    assert {:ok, %AshA2ui.Dynamic.Surface{}} = AshA2ui.Dynamic.resolve(spec, allowlist: allow)
  end

  describe "compile-time checks" do
    test "steps with pairs, a badge or a link" do
      for {option, value} <- [
            {:pairs, true},
            {:badge_tones, [scheduled: :info]},
            {:link_url, :page_url}
          ] do
        assert capture_io(:stderr, fn ->
                 Code.eval_quoted(
                   quote do
                     defmodule unquote(Module.concat(__MODULE__, "StepsWith#{option}")) do
                       @moduledoc false
                       use AshA2ui.Standalone

                       a2ui do
                         for_resource AshA2ui.Test.Appointment

                         component :table do
                           fields [:title, :progress]
                         end

                         field :progress do
                           steps true
                           unquote({option, [], [value]})
                         end
                       end
                     end
                   end
                 )
               end) =~ ~r/steps cannot be combined with pairs/
      end
    end
  end
end
