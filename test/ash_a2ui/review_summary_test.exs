defmodule AshA2ui.ReviewSummaryTest do
  @moduledoc """
  Admin catalog 3.6 review summaries: an alert `:detail` declaring
  `review_summary` counts the surface's review fields still waiting on its
  record (pending or missing) and links to the first one's section, in
  declaration order: the section nav's anchor when the nav lists it, else
  the section's id; with nothing waiting, the declared fallback.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.Gettext.Metadata
  alias AshA2ui.Test.{Dossier, DossierReviewUI, SchemaHelper}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(Dossier)
    end)

    :ok
  end

  defp dossier(reviews) do
    Ash.create!(
      Dossier,
      Map.merge(%{name: "Harbour lease", owner: "Ana", notes: "Read from the scan"}, reviews),
      authorize?: false
    )
  end

  defp surface(dossier) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(DossierReviewUI,
        authorize?: false,
        context_state: %{"dossier" => %{"search" => "", "value" => dossier.id, "label" => "x"}}
      )

    SchemaHelper.assert_valid_agent_message(message, catalogs: SchemaHelper.admin_catalogs())

    {Map.new(surface["components"], &{&1["id"], &1}),
     surface["dataModel"]["detail"]["dossier"]["_review_summary_to_review"]}
  end

  test "the alert binds its count and link to the summary its record carries" do
    {components, _summary} = surface(dossier(%{}))

    assert components["detail_to_review"]["count"] == %{
             "@path" => "/detail/dossier/_review_summary_to_review/count"
           }

    assert components["detail_to_review"]["linkHref"] == %{
             "@path" => "/detail/dossier/_review_summary_to_review/href"
           }

    assert components["detail_to_review"]["linkLabel"] == %{
             "@path" => "/detail/dossier/_review_summary_to_review/label"
           }
  end

  test "counts what waits and links to the first in declaration order, by the nav's anchor" do
    {_components, summary} =
      surface(
        dossier(%{
          name_review: %{state: :reviewed},
          owner_review: %{state: :pending, page: 2},
          notes_review: %{"state" => "missing"}
        })
      )

    assert summary == %{
             "count" => 2,
             "field" => "owner",
             "href" => "#facts",
             "label" => "Go to the first field to check"
           }
  end

  test "a section the nav does not list is reached by its own id" do
    {_components, summary} =
      surface(
        dossier(%{
          name_review: %{state: :reviewed},
          owner_review: %{state: :reviewed},
          notes_review: %{state: :pending}
        })
      )

    assert %{"count" => 1, "field" => "notes", "href" => "#section_notes_card"} = summary
  end

  test "with nothing waiting it is the fallback; a field without a review never waits" do
    {_components, summary} = surface(dossier(%{name_review: %{state: :reviewed}}))

    assert summary == %{
             "count" => 0,
             "field" => "",
             "href" => "#history",
             "label" => "Go to history"
           }
  end

  test "the metadata template collects the summary's words" do
    keys = Metadata.surface_messages(DossierReviewUI) |> Enum.map(&elem(&1, 1))

    assert "Go to the first field to check" in keys
    assert "Go to history" in keys
  end

  describe "compile-time checks" do
    defp compile(name, body) do
      capture_io(:stderr, fn ->
        Code.eval_quoted(
          quote do
            defmodule unquote(Module.concat(__MODULE__, name)) do
              @moduledoc false
              use AshA2ui.Standalone

              a2ui do
                for_resource AshA2ui.Test.Dossier

                context :dossier do
                  resource AshA2ui.Test.Dossier
                  picker false
                end

                unquote(body)
              end
            end
          end
        )
      end)
    end

    test "a review summary needs an alert" do
      body =
        quote do
          component :detail, :summary do
            context :dossier
            fields [:name]
            review_summary(fallback_href: "#x")
          end
        end

      assert compile("NoAlert", body) =~ ~r/declare `alert` on the component/
    end

    test "a review summary draws the alert's link itself" do
      body =
        quote do
          component :detail, :summary do
            context :dossier
            alert(message: :notes, link_href: :file_url)
            review_summary(fallback_href: "#x")
          end
        end

      assert compile("OwnLink", body) =~ ~r/drop the alert's `link_href`/
    end
  end
end
