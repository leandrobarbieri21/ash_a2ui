defmodule AshA2ui.ReviewFieldsTest do
  @moduledoc """
  Admin catalog 3.1 review fields: a field's `review` names a calculation
  saying how its value was filled in (pending, reviewed or missing, with the
  page it came from), bound on its detail card as `review`.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Review
  alias AshA2ui.Test.{Appointment, Clinic, Messages, Owner, SchemaHelper, VisitReviewUI}

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
        %{title: "Checkup", status: :scheduled, owner_id: owner.id, clinic_id: clinic.id},
        authorize?: false
      )

    %{visit: visit}
  end

  defp surface(catalog, visit) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(VisitReviewUI,
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
    test "the admin fieldDisplay binds the review of a review field only", %{visit: visit} do
      {components, _detail} = surface(:admin_v1, visit)

      assert components["detail_review_field_title"]["review"] ==
               %{"@path" => "/detail/appointment/_review_title"}

      assert components["detail_review_field_status"]["review"] ==
               %{"@path" => "/detail/appointment/_review_status"}

      refute Map.has_key?(components["detail_review_field_scheduled_for"], "review")
    end

    test "the detail record carries each normalized review", %{visit: visit} do
      {_components, detail} = surface(:admin_v1, visit)

      assert detail["title"] == "Checkup"

      assert detail["_review_title"] == %{
               "state" => "pending",
               "stateLabel" => "Not reviewed",
               "page" => 3,
               "pageLabel" => "p. 3",
               "href" => "/referrals/1#page=3",
               "quote" => "Reason for visit: checkup"
             }

      assert detail["_review_status"] == %{
               "state" => "missing",
               "stateLabel" => "Not found in the document"
             }

      refute Map.has_key?(detail, "_review_scheduled_for")
      # the calculations are loaded for the review, not drawn as fields
      refute Map.has_key?(detail, "title_review")
    end

    test "the basic catalog draws the value alone", %{visit: visit} do
      {components, _detail} = surface(:basic, visit)

      refute Enum.any?(Map.values(components), &Map.has_key?(&1, "review"))
    end

    test "selecting a record refreshes its reviews", %{visit: visit} do
      visit = Ash.update!(visit, %{status: :completed}, authorize?: false)

      {:ok, messages} =
        ActionHandler.handle(
          VisitReviewUI,
          Messages.call("context_select", "visit_review", %{
            "context" => "appointment",
            "value" => visit.id
          })
        )

      detail =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/detail/appointment", "value" => value}} -> value
          _other -> nil
        end)

      assert detail["_review_status"] == %{
               "state" => "reviewed",
               "stateLabel" => "Reviewed",
               "page" => 2,
               "pageLabel" => "p. 2"
             }
    end
  end

  describe "normalize/2" do
    test "states as atoms or strings; a missing or unknown state is no review" do
      assert Review.normalize(%{state: :reviewed})["state"] == "reviewed"
      assert Review.normalize(%{"state" => "missing"})["state"] == "missing"
      assert Review.normalize(%{state: :lost}) == nil
      assert Review.normalize(%{page: 3}) == nil
    end

    test "a value that is not a map is no review" do
      assert Review.normalize(nil) == nil
      assert Review.normalize("pending") == nil
      assert Review.normalize([%{state: :pending}]) == nil
      assert Review.normalize(~D[2026-11-03]) == nil
    end

    test "a page that is not a positive integer is left out, with its tag" do
      for page <- [0, -1, "x", "3a", 2.5, nil] do
        review = Review.normalize(%{state: :pending, page: page})
        refute Map.has_key?(review, "page"), inspect(page)
        refute Map.has_key?(review, "pageLabel"), inspect(page)
      end

      assert Review.normalize(%{state: :pending, page: "12"})["pageLabel"] == "p. 12"
    end

    test "an href or quote that is blank or not text is left out" do
      review = Review.normalize(%{state: :pending, href: "", quote: 3})

      assert review == %{"state" => "pending", "stateLabel" => "Not reviewed"}
    end

    test "the words are library strings" do
      pot = File.read!("priv/gettext/ash_a2ui.pot")

      for words <- ["Not reviewed", "Reviewed", "Not found in the document", "p. %{page}"],
          do: assert(pot =~ ~s(msgid "#{words}"), "#{words} is not in the shipped catalog")
    end
  end

  test "dynamic specs carry the review option" do
    {:ok, spec, _rejections} = Importer.import(VisitReviewUI)

    assert Enum.find(spec["fields"], &(&1["name"] == "title"))["review"] == "title_review"

    allow = AshA2ui.Dynamic.allowlist([Owner, Appointment, Clinic])
    assert {:ok, %AshA2ui.Dynamic.Surface{}} = AshA2ui.Dynamic.resolve(spec, allowlist: allow)
  end

  describe "compile-time checks" do
    test "a review that is not a field of the resource" do
      assert capture_io(:stderr, fn ->
               Code.eval_quoted(
                 quote do
                   defmodule unquote(Module.concat(__MODULE__, "ReviewUnknown")) do
                     @moduledoc false
                     use AshA2ui.Standalone

                     a2ui do
                       for_resource AshA2ui.Test.Appointment

                       component :table do
                         fields [:title]
                       end

                       field :title do
                         review(:nope)
                       end
                     end
                   end
                 end
               )
             end) =~ ~r/review names :nope, which is not a public attribute/
    end
  end
end
