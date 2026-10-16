defmodule AshA2ui.RangeFilterTest do
  @moduledoc """
  Client-driven range filters (`range_filters` on the query DSL): allowlist
  parsing, casting (including the date-string convenience on datetime
  fields), the `/query/ranges` state shape, the emitted from/to inputs, and
  compile-time verification.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper
  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.{ActionHandler, Info}
  alias AshA2ui.Test.{Appointment, Clinic, ClinicMembership, Owner}

  setup do
    on_exit(fn ->
      for resource <- [Appointment, ClinicMembership, Clinic, Owner] do
        Ets.stop(resource)
      end
    end)

    :ok
  end

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{"name" => name, "surfaceId" => "appointments", "context" => context}
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> {:ok, value}
      _other -> nil
    end)
    |> case do
      {:ok, value} -> value
      nil -> flunk("no updateDataModel for #{path} in #{inspect(messages, pretty: true)}")
    end
  end

  defp seed do
    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    Ash.create!(
      ClinicMembership,
      %{owner_id: owner.id, clinic_id: clinic.id},
      authorize?: false
    )

    for {title, iso} <- [
          {"January visit", "2026-01-15T10:00:00Z"},
          {"March visit", "2026-03-10T10:00:00Z"},
          {"May visit", "2026-05-07T08:36:39Z"}
        ] do
      {:ok, scheduled_for, 0} = DateTime.from_iso8601(iso)

      Ash.create!(
        Appointment,
        %{title: title, owner_id: owner.id, clinic_id: clinic.id, scheduled_for: scheduled_for},
        authorize?: false
      )
    end

    owner
  end

  defp query_with_ranges(owner, ranges) do
    ActionHandler.handle(
      AshA2ui.Test.AppointmentsUI,
      envelope("query", %{
        "query" => %{"ranges" => ranges},
        "contexts" => %{"owner" => %{"value" => owner.id, "label" => "x", "search" => ""}}
      }),
      authorize?: false
    )
  end

  describe "range filter reads" do
    test "a from bound keeps records at or after it" do
      owner = seed()

      assert {:ok, messages} =
               query_with_ranges(owner, %{
                 "scheduled_for" => %{"from" => "2026-03-01T00:00:00Z", "to" => ""}
               })

      Enum.each(messages, &assert_valid_server_message/1)

      assert value_at(messages, "/records") |> Enum.map(& &1["title"]) ==
               ["May visit", "March visit"]

      assert value_at(messages, "/query")["totalCount"] == 2
    end

    test "from and to bound both ends inclusively" do
      owner = seed()

      assert {:ok, messages} =
               query_with_ranges(owner, %{
                 "scheduled_for" => %{
                   "from" => "2026-01-15T10:00:00Z",
                   "to" => "2026-03-10T10:00:00Z"
                 }
               })

      assert value_at(messages, "/records") |> Enum.map(& &1["title"]) ==
               ["March visit", "January visit"]
    end

    test "plain date strings expand to day bounds on datetime fields" do
      owner = seed()

      assert {:ok, messages} =
               query_with_ranges(owner, %{
                 "scheduled_for" => %{"from" => "2026-05-07", "to" => "2026-05-07"}
               })

      assert [%{"title" => "May visit"}] = value_at(messages, "/records")

      # The state echoes the client's raw strings back.
      assert value_at(messages, "/query")["ranges"] == %{
               "scheduled_for" => %{"from" => "2026-05-07", "to" => "2026-05-07"}
             }
    end

    test "empty bounds are inactive and echo the stable empty shape" do
      owner = seed()

      assert {:ok, messages} =
               query_with_ranges(owner, %{"scheduled_for" => %{"from" => "", "to" => ""}})

      assert length(value_at(messages, "/records")) == 3

      assert value_at(messages, "/query")["ranges"] == %{
               "scheduled_for" => %{"from" => "", "to" => ""}
             }
    end

    test "rejects non-allowlisted range fields and invalid values" do
      owner = seed()

      assert {:error, messages} =
               query_with_ranges(owner, %{"title" => %{"from" => "A", "to" => ""}})

      assert value_at(messages, "/ui/feedback")["message"] =~ "not allowlisted"

      assert {:error, messages} =
               query_with_ranges(owner, %{"scheduled_for" => %{"from" => "yesterday", "to" => ""}})

      assert value_at(messages, "/ui/feedback")["message"] =~ "value is invalid"
    end
  end

  describe "encoding" do
    test "emits from/to inputs and the initial ranges state" do
      seed()

      messages = Info.build_surface(AshA2ui.Test.AppointmentsUI, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      [_create, %{"updateComponents" => %{"components" => components}}, data_model] = messages

      controls = Enum.find(components, &(&1["id"] == "query_controls_body"))
      assert "query_range_scheduled_for_from" in controls["children"]
      assert "query_range_scheduled_for_to" in controls["children"]

      from_input = Enum.find(components, &(&1["id"] == "query_range_scheduled_for_from"))
      assert from_input["component"] == "TextField"
      assert from_input["value"] == %{"path" => "/query/ranges/scheduled_for/from"}

      assert data_model["updateDataModel"]["value"]["query"]["ranges"] == %{
               "scheduled_for" => %{"from" => "", "to" => ""}
             }
    end
  end

  describe "verification" do
    test "range_filters over unknown fields do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule UnknownRangeField do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Appointment
              surface_id "x"

              query :default do
                range_filters([:nonexistent])
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/references unknown field :nonexistent in range_filters/
    end
  end
end
