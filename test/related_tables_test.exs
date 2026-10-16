defmodule AshA2ui.RelatedTablesTest do
  @moduledoc """
  Related tables: a `:table` component naming its own `resource` reads that
  resource (scoped by a context), with fields, queries, `source` columns and
  links resolved against it — read-only, as the surface's actor.
  """

  # Shared ETS fixtures.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Links.{Note, Participant, PeopleTaskUI, PeopleUI, Person}
  alias AshA2ui.Test.Paginated

  setup do
    for resource <- [Participant, Note, Person] do
      resource |> Ash.read!(authorize?: false) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    ada = Ash.create!(Person, %{name: "Ada"}, authorize?: false)
    bob = Ash.create!(Person, %{name: "Bob"}, authorize?: false)

    kickoff =
      Ash.create!(Note, %{title: "Kickoff", person_id: ada.id, amount: 3}, authorize?: false)

    review =
      Ash.create!(Note, %{title: "Review", person_id: ada.id, amount: 1}, authorize?: false)

    _bobs = Ash.create!(Note, %{title: "Bob's", person_id: bob.id}, authorize?: false)

    Ash.create!(Participant, %{note_id: kickoff.id, person_id: bob.id}, authorize?: false)
    Ash.create!(Participant, %{note_id: review.id, person_id: ada.id}, authorize?: false)

    %{ada: ada, bob: bob, kickoff: kickoff, review: review}
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp root(messages), do: value_at(messages, "/")

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "people",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  test "related tables resolve against their own resource" do
    view = ResolvedView.resolve(PeopleUI)
    tables = Map.new(view.tables, &{&1.name, &1})

    assert tables[:table].resource == Person
    assert tables[:their_notes].resource == Note
    assert tables[:their_notes].read_action == :read
    assert tables[:participations].resource == Participant

    assert {:note, [:title]} in tables[:participations].loads or
             :note in tables[:participations].loads
  end

  test "unselected, related tables read nothing; selected, they read the person's rows", %{
    ada: ada,
    bob: bob
  } do
    messages = AshA2ui.Info.build_surface(PeopleUI)
    Enum.each(messages, &assert_valid_server_message/1)
    assert root(messages)["records"]["their_notes"] == []

    state = AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})
    messages = AshA2ui.Info.build_surface(PeopleUI, context_state: state)
    records = root(messages)["records"]

    # query default sort applies, against Note's attributes
    assert Enum.map(records["their_notes"], & &1["title"]) == ["Kickoff", "Review"]
    kickoff = hd(records["their_notes"])
    assert kickoff["status"] == "Open"

    # links on the related table's own relationships
    assert [%{"surface" => "person", "recordId" => bob_id, "label" => "Bob"}] =
             kickoff["_links"]["participant_links"]

    assert bob_id == bob.id

    # a source column + link through the related resource
    assert [participation] = records["participations"]
    assert participation["note_title"] == "Review"
    assert participation["_links"]["note_title"]["surface"] == "note"
  end

  test "context_select refreshes the related tables", %{bob: bob} do
    {:ok, messages} =
      ActionHandler.handle(
        PeopleUI,
        envelope("context_select", %{"context" => "person", "value" => bob.id})
      )

    records = value_at(messages, "/records/their_notes")
    assert Enum.map(records, & &1["title"]) == ["Bob's"]
  end

  test "a related table's query runs against its resource", %{ada: ada} do
    state = AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})

    {:ok, messages} =
      ActionHandler.handle(
        PeopleUI,
        envelope("query", %{
          "component" => "their_notes",
          "query" => %{"search" => "rev"},
          "contexts" => state
        }),
        []
      )

    records = value_at(messages, "/records/their_notes")
    assert Enum.map(records, & &1["title"]) == ["Review"]
  end

  defp components_by_id(messages) do
    Enum.find_value(messages, fn
      %{"updateComponents" => %{"components" => components}} ->
        Map.new(components, &{&1["id"], &1})

      _other ->
        nil
    end)
  end

  describe "task affordances on a surface with a related table" do
    setup do
      on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
      :ok
    end

    test "the related table gets no View/Edit controls and no create button" do
      messages = AshA2ui.Info.build_surface(PeopleTaskUI)
      Enum.each(messages, &assert_valid_server_message/1)
      comps = components_by_id(messages)

      # The master table (over the surface's own resource) keeps both.
      assert comps["create_table_button"]["action"]["event"]["name"] == "start_create"
      assert comps["view_table_button"]["action"]["event"]["name"] == "view_record"
      assert "view_table_button" in comps["record_row_table_content"]["children"]
      assert "create_table_button" in comps["root"]["children"]

      # The related table is a read-only view of Note records.
      refute Map.has_key?(comps, "view_their_notes_button")
      refute Map.has_key?(comps, "edit_their_notes_button")
      refute Map.has_key?(comps, "create_their_notes_button")
      refute "create_their_notes_button" in comps["root"]["children"]

      assert comps["record_row_their_notes_content"]["children"] == [
               "table_cell_their_notes_title",
               "table_cell_their_notes_status",
               "table_cell_their_notes_amount"
             ]
    end

    test "the select_context button says it selects, in both compositions" do
      basic = components_by_id(AshA2ui.Info.build_surface(PeopleTaskUI))

      assert basic["row_context_table_button"]["action"]["event"]["name"] == "context_select"
      assert basic["row_context_table_text"]["text"] == "Select person"
      # distinct from the task panel's own row control
      assert basic["view_table_button_text"]["text"] == "View"

      Application.put_env(:ash_a2ui, :catalog, :admin_v1)
      admin = components_by_id(AshA2ui.Info.build_surface(PeopleTaskUI))

      master_actions = admin["data_grid_table"]["rowActions"]

      assert %{"label" => "Select person", "action" => "context_select"} =
               Enum.find(master_actions, &(&1["action"] == "context_select"))

      assert Enum.any?(master_actions, &(&1["action"] == "view_record"))
      assert admin["data_grid_table"]["rowClick"]["action"] == "context_select"

      # admin: the related grid has no task controls, no row click into the
      # panel, and no create button
      notes_actions = admin["data_grid_their_notes"]["rowActions"]
      refute Enum.any?(notes_actions, &(&1["action"] in ["view_record", "start_edit"]))
      refute Map.has_key?(admin["data_grid_their_notes"], "rowClick")
      refute Map.has_key?(admin, "create_their_notes_button")
      assert Map.has_key?(admin, "create_table_button")
    end
  end

  describe "initial-render rows equal refresh rows" do
    test "a related table's rows read the same before and after a context selection", %{
      ada: ada
    } do
      state = AshA2ui.Info.context_state_for(PeopleUI, %{"person" => ada.id})
      initial = root(AshA2ui.Info.build_surface(PeopleUI, context_state: state))

      {:ok, messages} =
        ActionHandler.handle(
          PeopleUI,
          envelope("context_select", %{"context" => "person", "value" => ada.id})
        )

      refreshed = value_at(messages, "/records/their_notes")

      assert refreshed == initial["records"]["their_notes"]
      # enum values read as their labels on both paths, never raw
      assert Enum.map(refreshed, & &1["status"]) == ["Open", "Open"]
      assert refreshed != []
    end

    test "a surface table's rows read the same after a query refresh" do
      for {name, status} <- [{"Alpha", :open}, {"Bravo", :closed}] do
        Ash.create!(Paginated, %{name: name, status: status}, authorize?: false)
      end

      [_create, _components, data] = AshA2ui.Info.build_surface(Paginated)
      initial = data["updateDataModel"]["value"]["records"]

      {:ok, messages} =
        ActionHandler.handle(Paginated, %{
          "version" => "v0.9.1",
          "action" => %{"name" => "query", "context" => %{"query" => %{}}}
        })

      refreshed = value_at(messages, "/records")

      assert refreshed == initial
      assert Enum.map(refreshed, & &1["status"]) == ["Open", "Closed"]
    end
  end
end
