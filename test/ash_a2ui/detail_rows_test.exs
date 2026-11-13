defmodule AshA2ui.DetailRowsTest do
  @moduledoc """
  Catalog 1.12 detail rows: a field drawn as a badge (`badge_text`,
  `badge_tones`, `badge_help` on a `field`), an `empty_text` placeholder and
  a detail's `hide_empty` rows.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Gettext.Metadata
  alias AshA2ui.Test.{Appointment, AppointmentPageUI, Clinic, Owner, SchemaHelper, Surface}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    appointment =
      Ash.create!(
        Appointment,
        %{title: "Checkup", owner_id: owner.id, clinic_id: clinic.id},
        authorize?: false
      )

    %{appointment: appointment}
  end

  defp surface(catalog, appointment) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    surface =
      AshA2ui.Info.build_surface(AppointmentPageUI,
        authorize?: false,
        context_state: %{
          "appointment" => %{"search" => "", "value" => appointment.id, "label" => "x"}
        }
      )

    opts = if catalog == :admin_v1, do: [catalogs: SchemaHelper.admin_catalogs()], else: []
    SchemaHelper.assert_valid_agent_messages(surface, opts)

    {Surface.components_by_id(surface), Surface.data_model(surface)["detail"]["appointment"]}
  end

  test "a badge field's text, tone and help ride in the detail data", %{appointment: appointment} do
    {_components, detail} = surface(:admin_v1, appointment)

    assert detail["_badge_status"] == "Booked"
    assert detail["_badge_tone_status"] == "info"
    # Declared help for :completed only.
    assert detail["_badge_help_status"] == ""
    refute Map.has_key?(detail, "_badge_title")
  end

  test "the admin fieldDisplay binds the badge, the placeholder and the hiding",
       %{appointment: appointment} do
    {components, _detail} = surface(:admin_v1, appointment)

    assert %{
             "badge" => %{"@path" => "/detail/appointment/_badge_status"},
             "badgeTone" => %{"@path" => "/detail/appointment/_badge_tone_status"},
             "badgeHelp" => %{"@path" => "/detail/appointment/_badge_help_status"}
           } = components["detail_summary_field_status"]

    refute Map.has_key?(components["detail_summary_field_title"], "badge")

    assert components["detail_summary_field_scheduled_for"]["emptyText"] == "Not booked yet"
    refute Map.has_key?(components["detail_summary_field_scheduled_for"], "hideWhenEmpty")
    assert components["detail_schedule_field_scheduled_for"]["hideWhenEmpty"] == true
  end

  test "the basic catalog shows the badge text", %{appointment: appointment} do
    {components, _detail} = surface(:basic, appointment)

    assert components["detail_summary_value_status"]["text"] ==
             %{"@path" => "/detail/appointment/_badge_status"}
  end

  test "the badge texts and the placeholder are metadata to translate" do
    keys = Metadata.surface_messages(AppointmentPageUI)
    texts = Enum.map(keys, &elem(&1, 1))

    for text <- ["Booked", "Seen and signed off", "Completed", "Not booked yet"],
        do: assert(text in texts, "#{text} is not collected")
  end

  test "dynamic specs carry the badge, the placeholder and hide_empty" do
    {:ok, spec, _rejections} = Importer.import(AppointmentPageUI)
    fields = Map.new(spec["fields"], &{&1["name"], &1})

    assert fields["status"]["badge_text"] == %{"scheduled" => "Booked"}
    assert fields["status"]["badge_tones"] == %{"scheduled" => "info", "completed" => "success"}
    assert fields["status"]["badge_help"] == %{"completed" => "Seen and signed off"}
    assert fields["scheduled_for"]["empty_text"] == "Not booked yet"

    schedule = Enum.find(spec["components"], &(&1["name"] == "schedule"))
    assert schedule["hide_empty"] == ["scheduled_for"]
  end

  describe "compile-time checks" do
    test "a badge tone outside the vocabulary" do
      assert capture_io(:stderr, fn ->
               defmodule BadTone do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title, :status]
                   end

                   field :status do
                     badge_tones scheduled: :purple
                   end
                 end
               end
             end) =~ ~r/badge_tones for :scheduled must be one of/
    end

    test "hide_empty on a table, or naming a field the card does not show" do
      assert capture_io(:stderr, fn ->
               defmodule HideOnTable do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   component :table do
                     fields [:title]
                     hide_empty([:title])
                   end
                 end
               end
             end) =~ ~r/hide_empty is only valid on :detail/

      assert capture_io(:stderr, fn ->
               defmodule HideUnknown do
                 @moduledoc false
                 use AshA2ui.Standalone

                 a2ui do
                   for_resource AshA2ui.Test.Appointment

                   context :appointment do
                     resource AshA2ui.Test.Appointment
                     picker false
                   end

                   component :detail, :summary do
                     context :appointment
                     fields [:title]
                     hide_empty([:scheduled_for])
                   end
                 end
               end
             end) =~ ~r/not one of the card's fields/
    end
  end
end
