# Phoenix-only: under NO_PHOENIX the scrubber, the LiveRenderer and the test
# endpoint don't exist, so nothing here should even compile.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.TimeTravelLiveTest do
    # async: false — the temporal fixture is a shared (non-private) ETS table.
    use ExUnit.Case, async: false

    import Phoenix.ConnTest
    import Phoenix.LiveViewTest

    alias Ash.DataLayer.Ets
    alias AshA2ui.{AsOf, TimeScrubber}
    alias AshA2ui.Test.TimeTravel.Plan

    @endpoint AshA2ui.Test.Endpoint

    @from ~U[2026-01-01 00:00:00Z]
    @to ~U[2026-01-11 00:00:00Z]

    setup do
      Ets.stop(Plan)
      :ok
    end

    defp same?(a, b), do: DateTime.compare(a, b) == :eq

    describe "TimeScrubber" do
      test "a position resolves against the host's span" do
        assert same?(TimeScrubber.instant(%{"position" => "0"}, @from, @to), @from)

        assert same?(
                 TimeScrubber.instant(%{"position" => "500"}, @from, @to),
                 ~U[2026-01-06 00:00:00Z]
               )

        # The right-hand end of a span that ended in the past is that end.
        assert same?(TimeScrubber.instant(%{"position" => "1000"}, @from, @to), @to)
        assert TimeScrubber.instant(%{"position" => "x"}, @from, @to) == nil
      end

      test "the right-hand end of a span ending now is now" do
        assert TimeScrubber.instant(%{"position" => "1000"}, @from, DateTime.utc_now()) == nil
      end

      test "a position within one step of a mark snaps to the mark" do
        mark = %{at: ~U[2026-01-06 00:05:00.000123Z], label: "Merged"}

        assert TimeScrubber.instant(%{"position" => "500"}, @from, @to, [mark]) == mark.at
        refute TimeScrubber.instant(%{"position" => "400"}, @from, @to, [mark]) == mark.at
      end

      test "renders the marks as links to their exact instants" do
        mark = %{at: ~U[2026-01-06 00:05:00.000123Z], label: "Merged", tone: :secondary}

        html =
          render_component(&TimeScrubber.scrubber/1,
            id: "t",
            from: @from,
            to: @to,
            as_of: mark.at,
            marks: [mark],
            path: &AsOf.put_param("/plans", &1)
          )

        assert html =~ "As of 2026-01-06 00:05 UTC"
        assert html =~ "as_of=2026-01-06T00%3A05%3A00.000123Z"
        assert html =~ ~s(id="t-now")
        assert html =~ ~s(aria-current="true")
      end
    end

    describe "LiveRenderer time_travel: true" do
      test "?as_of= pins the bootstrap, and a new instant rebuilds the surface" do
        t0 = ~U[2026-01-01 00:00:00.000000Z]

        Plan
        |> Ash.Changeset.for_create(:create, %{name: "Acme", tier: "bronze"}, as_of: t0)
        |> Ash.create!()
        |> Ash.Changeset.for_update(:change_tier, %{tier: "gold"},
          as_of: ~U[2026-03-01 00:00:00.000000Z]
        )
        |> Ash.update!()

        conn = Plug.Test.init_test_session(build_conn(), %{})
        instant = AsOf.to_param(DateTime.add(t0, 1, :day))

        {:ok, view, _html} = live(conn, "/live-renderer/time-travel?as_of=#{instant}")
        assert_push_event(view, "a2ui:messages", %{messages: messages}, 1_000)

        assert [%{"tier" => "bronze"}] =
                 Enum.find_value(messages, fn
                   %{"updateDataModel" => %{"path" => "/", "value" => value}} ->
                     value["records"]

                   _other ->
                     nil
                 end)

        refute Jason.encode!(messages) =~ "change_tier"

        # Back to now: the LiveView navigates, rebuilding a live surface.
        assert {:error, {:live_redirect, %{to: "/live-renderer/time-travel"}}} =
                 render_patch(view, "/live-renderer/time-travel")
      end
    end
  end
end
