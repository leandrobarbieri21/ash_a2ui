defmodule AshA2ui.TimeTravelTest do
  # async: false — the temporal fixture is a shared (non-private) ETS table.
  use ExUnit.Case, async: false

  alias Ash.DataLayer.Ets
  alias AshA2ui.{ActionHandler, AsOf, Info}
  alias AshA2ui.Test.SchemaHelper
  alias AshA2ui.Test.TimeTravel.{Plan, PlanUI}

  doctest AshA2ui.AsOf

  # A destroy only ends a version's period; history stays. Dropping the
  # table gives each test an empty history.
  setup do
    Ets.stop(Plan)
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
end
