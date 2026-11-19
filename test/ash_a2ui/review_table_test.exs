defmodule AshA2ui.ReviewTableTest do
  @moduledoc """
  Admin catalog 3.3 review fields in tables: a review field a table draws
  carries each row's review at `_review_<field>`, bound by its dataGrid
  column as `review` and by a column subtitle as `reviewPath`.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Appointment, Clinic, Messages, Owner, SchemaHelper, VisitReviewTableUI}

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

    %{owner: owner, visit: visit}
  end

  defp surface(catalog, owner) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(VisitReviewTableUI,
        authorize?: false,
        context_state: %{"owner" => %{"search" => "", "value" => owner.id, "label" => "x"}}
      )

    catalogs = if catalog == :admin_v1, do: SchemaHelper.admin_catalogs()
    SchemaHelper.assert_valid_agent_message(message, catalogs: catalogs)

    {Map.new(surface["components"], &{&1["id"], &1}), surface["dataModel"]}
  end

  defp columns(components),
    do: Map.new(components["data_grid"]["columns"], &{&1["path"], &1})

  defp rows(components, data) do
    "/" <> path = components["data_grid"]["rows"]["@path"]
    get_in(data, String.split(path, "/"))
  end

  describe "the wire" do
    test "a review field's column binds the row's review", %{owner: owner} do
      {components, _data} = surface(:admin_v1, owner)
      columns = columns(components)

      assert columns["title"]["review"] == %{"path" => "_review_title"}
      assert columns["title"]["placement"] == "expand"

      refute Map.has_key?(columns["seen_by"], "review")
      refute Map.has_key?(columns["scheduled_for"], "review")
    end

    test "a subtitle that is a review field binds its review as reviewPath", %{owner: owner} do
      {components, _data} = surface(:admin_v1, owner)

      assert columns(components)["scheduled_for"]["subtitle"] == %{
               "path" => "status",
               "reviewPath" => "_review_status"
             }
    end

    test "each row carries its normalized reviews", %{owner: owner} do
      {components, data} = surface(:admin_v1, owner)
      [row] = rows(components, data)

      assert row["_review_title"] == %{
               "state" => "pending",
               "stateLabel" => "Not reviewed",
               "page" => 3,
               "pageLabel" => "p. 3",
               "href" => "/referrals/1#page=3",
               "quote" => "Reason for visit: checkup"
             }

      assert row["_review_status"] == %{
               "state" => "missing",
               "stateLabel" => "Not found in the document"
             }

      refute Map.has_key?(row, "_review_seen_by")
      refute Map.has_key?(row, "title_review")
    end

    test "a completed visit's status reads reviewed, with its page", %{owner: owner, visit: visit} do
      # The status review is "reviewed" once completed; a review value that
      # is not a map is none.
      Ash.update!(visit, %{status: :completed}, authorize?: false)
      {components, data} = surface(:admin_v1, owner)
      [row] = rows(components, data)

      assert row["_review_status"]["state"] == "reviewed"
      assert row["_review_status"]["pageLabel"] == "p. 2"
    end

    test "the basic catalog draws the value alone", %{owner: owner} do
      {components, _data} = surface(:basic, owner)

      refute Enum.any?(Map.values(components), &Map.has_key?(&1, "review"))
    end

    test "a refreshed row carries its reviews as the first render did", %{
      owner: owner,
      visit: visit
    } do
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)
      Ash.update!(visit, %{status: :completed}, authorize?: false)

      {:ok, messages} =
        ActionHandler.handle(
          VisitReviewTableUI,
          Messages.call("context_select", "visit_review_table", %{
            "context" => "owner",
            "value" => owner.id
          })
        )

      rows =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"value" => [%{"_review_status" => _} | _] = value}} -> value
          _other -> nil
        end)

      assert [%{"_review_status" => %{"state" => "reviewed"}, "_review_title" => title}] = rows
      assert title["pageLabel"] == "p. 3"
    end
  end

  describe "compile-time checks" do
    test "a review field drawn in a table whose resource lacks the review" do
      assert capture_io(:stderr, fn ->
               Code.eval_quoted(
                 quote do
                   defmodule unquote(Module.concat(__MODULE__, "TableReviewUnknown")) do
                     @moduledoc false
                     use AshA2ui.Standalone

                     a2ui do
                       for_resource AshA2ui.Test.Appointment

                       component :detail, :visit do
                         context :appointment
                         fields [:title]
                       end

                       context :appointment do
                         resource AshA2ui.Test.Appointment
                         option_label :title
                         picker false
                       end

                       component :table, :owners do
                         resource AshA2ui.Test.Owner
                         fields [:name]
                       end

                       field :name do
                         review(:title_review)
                       end
                     end
                   end
                 end
               )
             end) =~
               ~r/review names :title_review, which is not a public attribute, calculation or aggregate of AshA2ui.Test.Owner, whose table draws :name/
    end
  end
end
