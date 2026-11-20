defmodule AshA2ui.ContextRecordTest do
  @moduledoc """
  A table's `context_record`: the surface fetches the selected record once,
  with the table's loads beside its details', and hands it to the table's
  read in the query context (`AshA2ui.ContextRunner.context_record/2`).
  """

  # Not async: the read counter is a node-global telemetry handler.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias Ash.DataLayer.Ets
  alias AshA2ui.{ContextRunner, Info}
  alias AshA2ui.Test.{Appointment, Clinic, Owner, SharedOwnerVisitsUI}

  setup do
    on_exit(fn ->
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    ada = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    Ash.create!(
      Appointment,
      %{title: "Checkup", owner_id: ada.id, clinic_id: clinic.id},
      authorize?: false
    )

    %{ada: ada}
  end

  defp state(owner), do: %{"owner" => %{"value" => owner.id, "label" => owner.email}}

  defp data_model(opts) do
    messages = Info.build_surface(SharedOwnerVisitsUI, [authorize?: false] ++ opts)
    Enum.each(messages, &assert_valid_agent_message/1)
    [%{"createSurface" => %{"dataModel" => data_model}}] = messages
    data_model
  end

  test "a table naming the context reads with its selected record, loaded", %{ada: ada} do
    model = data_model(context_state: state(ada))

    assert [%{"title" => "Checkup", "owner_greeting" => "Hello Ada"}] =
             model["records"]["visits"]

    assert [%{"owner_greeting" => "not handed"}] = model["records"]["plain_visits"]
    assert model["detail"]["owner"]["name"] == "Ada"
  end

  test "build_data_model hands it too", %{ada: ada} do
    %{"updateDataModel" => %{"value" => model}} =
      Info.build_data_model(SharedOwnerVisitsUI,
        authorize?: false,
        context_state: state(ada)
      )

    assert [%{"owner_greeting" => "Hello Ada"}] = model["records"]["visits"]
  end

  test "the selected record is read once, for the details and the table", %{ada: ada} do
    test = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:ash, :domain, :read, :start],
      fn _event, _measure, meta, _config ->
        if meta[:resource_short_name] == :owner, do: send(test, :owner_read)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    data_model(context_state: state(ada))

    assert_received :owner_read
    refute_received :owner_read
  end

  test "nothing selected hands nothing and reads no table" do
    model = data_model([])

    assert model["records"]["visits"] == []
    assert model["detail"]["owner"] == %{}
  end

  describe "context_record/2" do
    test "reads a calculation context, a query or a context map", %{ada: ada} do
      context = %{ash_a2ui: %{context_records: %{owner: ada}}}

      assert ContextRunner.context_record(context, :owner) == ada
      assert ContextRunner.context_record(%{source_context: context}, :owner) == ada

      assert Owner |> Ash.Query.set_context(context) |> ContextRunner.context_record(:owner) ==
               ada

      assert ContextRunner.context_record(context, :clinic) == nil
      assert ContextRunner.context_record(%{}, :owner) == nil
      assert ContextRunner.context_record(nil, :owner) == nil
    end

    test "read_context/2 names only the table's context_record contexts", %{ada: ada} do
      assert ContextRunner.read_context(%{context_record: [owner: []]}, %{owner: ada}) ==
               %{ash_a2ui: %{context_records: %{owner: ada}}}

      assert ContextRunner.read_context(%{context_record: []}, %{owner: ada}) == %{}
      assert ContextRunner.read_context(%{context_record: [owner: []]}, %{}) == %{}
    end
  end
end
