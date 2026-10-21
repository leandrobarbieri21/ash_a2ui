defmodule AshA2ui.TimeTravelTest do
  # async: false — the temporal fixture is a shared (non-private) ETS table.
  use ExUnit.Case, async: false

  alias AshA2ui.{ActionHandler, AsOf, Info}
  alias AshA2ui.Test.SchemaHelper
  alias AshA2ui.Test.TimeTravel.{Plan, PlanUI}

  doctest AshA2ui.AsOf

  # A destroy only ends a version's period; history stays. Dropping the
  # table gives each test an empty history.
  setup do
    Ash.DataLayer.Ets.stop(Plan)
    :ok
  end

  # A plan created at t0 as "bronze", moved to "gold" at t1.
  defp plan_with_history do
    t0 = ~U[2026-01-01 00:00:00.000000Z]
    t1 = ~U[2026-03-01 00:00:00.000000Z]

    plan =
      Plan
      |> Ash.Changeset.for_create(:create, %{name: "Acme", tier: "bronze"}, as_of: t0)
      |> Ash.create!()

    plan
    |> Ash.Changeset.for_update(:change_tier, %{tier: "gold"}, as_of: t1)
    |> Ash.update!()

    %{t0: t0, t1: t1}
  end

  defp data_model(messages) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
      _other -> nil
    end)
  end

  defp tiers(messages) do
    messages |> data_model() |> Map.fetch!("records") |> Enum.map(& &1["tier"])
  end

  describe "AsOf.parse/1" do
    test "reads ISO 8601 with an offset as UTC, keeping microseconds" do
      assert {:ok, ~U[2026-10-17 14:03:00.123456Z]} =
               AsOf.parse("2026-10-17T10:03:00.123456-04:00")
    end

    test "reads datetime-local and bare dates as UTC" do
      assert {:ok, ~U[2026-10-17 14:03:00Z]} = AsOf.parse("2026-10-17T14:03")
      assert {:ok, ~U[2026-10-17 14:03:09Z]} = AsOf.parse("2026-10-17T14:03:09")
      assert {:ok, ~U[2026-10-17 00:00:00Z]} = AsOf.parse("2026-10-17")
    end

    test "anything else is now" do
      assert :error = AsOf.parse("last friday")
      assert :error = AsOf.parse("2026-13-40")
      assert :error = AsOf.parse(nil)
      assert AsOf.from_params(%{"as_of" => "nope"}) == nil
      assert AsOf.from_params(%{}) == nil
    end

    test "to_param/1 round-trips through parse/1" do
      at = ~U[2026-10-17 14:03:00.000042Z]
      assert {:ok, ^at} = at |> AsOf.to_param() |> AsOf.parse()
      assert AsOf.to_param(~U[2026-10-17 14:03:00.000000Z]) == "2026-10-17T14:03:00Z"
      assert AsOf.to_param(nil) == nil
    end
  end

  describe "build_surface/2 with :as_of" do
    test "reads the version valid at the instant" do
      %{t0: t0, t1: t1} = plan_with_history()

      assert tiers(Info.build_surface(PlanUI)) == ["gold"]
      assert tiers(Info.build_surface(PlanUI, as_of: DateTime.add(t0, 1, :day))) == ["bronze"]
      assert tiers(Info.build_surface(PlanUI, as_of: t1)) == ["gold"]
      assert tiers(Info.build_surface(PlanUI, as_of: DateTime.add(t0, -1, :day))) == []
    end

    test "a pinned surface is view-only and still schema-valid" do
      %{t0: t0} = plan_with_history()

      live = Info.build_surface(PlanUI)
      pinned = Info.build_surface(PlanUI, as_of: DateTime.add(t0, 1, :day))

      assert Jason.encode!(live) =~ "change_tier"
      refute Jason.encode!(pinned) =~ "change_tier"
      Enum.each(pinned, &SchemaHelper.assert_valid_server_message/1)
    end

    test "build_data_model/2 refreshes at the same instant" do
      %{t0: t0} = plan_with_history()

      message = Info.build_data_model(PlanUI, as_of: DateTime.add(t0, 1, :day))
      assert tiers([message]) == ["bronze"]
    end
  end

  describe "ActionHandler under :as_of" do
    test "refuses writes, and the record is unchanged" do
      %{t0: t0} = plan_with_history()
      [plan] = Ash.read!(Plan)

      envelope = %{
        "action" => %{
          "name" => "invoke",
          "context" => %{"action" => "change_tier", "recordId" => plan.id}
        }
      }

      assert {:error, messages} =
               ActionHandler.handle(PlanUI, envelope, as_of: DateTime.add(t0, 1, :day))

      assert Jason.encode!(messages) =~ "Return to now to make changes"
      assert [%{tier: "gold"}] = Ash.read!(Plan)
    end

    test "reads (query refreshes) run at the instant" do
      %{t0: t0} = plan_with_history()
      envelope = %{"action" => %{"name" => "query", "context" => %{}}}

      assert {_ok_or_error, messages} =
               ActionHandler.handle(PlanUI, envelope, as_of: DateTime.add(t0, 1, :day))

      refute Jason.encode!(messages) =~ "Return to now to make changes"
    end
  end

  if Code.ensure_loaded?(Phoenix.LiveView) do
    describe "TimeScrubber" do
      alias AshA2ui.TimeScrubber

      @from ~U[2026-01-01 00:00:00Z]
      @to ~U[2026-01-11 00:00:00Z]

      defp same?(a, b), do: DateTime.compare(a, b) == :eq

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

        require Phoenix.LiveViewTest

        html =
          Phoenix.LiveViewTest.render_component(&TimeScrubber.scrubber/1,
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
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      @endpoint AshA2ui.Test.Endpoint

      test "?as_of= pins the bootstrap, and a new instant rebuilds the surface" do
        %{t0: t0} = plan_with_history()
        conn = Plug.Test.init_test_session(build_conn(), %{})
        instant = AsOf.to_param(DateTime.add(t0, 1, :day))

        {:ok, view, _html} = live(conn, "/live-renderer/time-travel?as_of=#{instant}")
        assert_push_event(view, "a2ui:messages", %{messages: messages}, 1_000)
        assert tiers(messages) == ["bronze"]
        refute Jason.encode!(messages) =~ "change_tier"

        # Back to now: the LiveView navigates, rebuilding a live surface.
        assert {:error, {:live_redirect, %{to: "/live-renderer/time-travel"}}} =
                 render_patch(view, "/live-renderer/time-travel")
      end
    end
  end
end
