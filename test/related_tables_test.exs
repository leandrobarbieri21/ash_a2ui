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

  # Every component id whose action dispatches `event`, sorted.
  defp ids_dispatching(comps, event) do
    for {id, %{"action" => %{"event" => %{"name" => ^event}}}} <- comps, do: id
  end

  defp texts(comps), do: for({_id, %{"component" => "Text", "text" => t}} <- comps, do: t)

  describe "task affordances on a surface with a related table" do
    setup do
      on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
      :ok
    end

    test "basic: only the master table gets View/Edit and the one create button" do
      messages = AshA2ui.Info.build_surface(PeopleTaskUI)
      Enum.each(messages, &assert_valid_server_message/1)
      comps = components_by_id(messages)

      # The master table (over the surface's own resource) keeps all three.
      assert ids_dispatching(comps, "view_record") == ["view_table_button"]
      assert ids_dispatching(comps, "start_edit") == ["edit_table_button"]
      assert ids_dispatching(comps, "start_create") == ["create_table_button"]

      assert "view_table_button" in comps["record_row_table_content"]["children"]
      assert "edit_table_button" in comps["record_row_table_content"]["children"]
      assert "create_table_button" in comps["root"]["children"]

      # The related tables — one with a query of its own — are read-only
      # views of Note / Participant records: no controls, no create button.
      for table <- ["their_notes", "participations"] do
        refute Map.has_key?(comps, "view_#{table}_button")
        refute Map.has_key?(comps, "edit_#{table}_button")
        refute Map.has_key?(comps, "create_#{table}_button")
        refute "create_#{table}_button" in comps["root"]["children"]
      end

      assert comps["record_row_their_notes_content"]["children"] == [
               "table_cell_their_notes_title",
               "table_cell_their_notes_status",
               "table_cell_their_notes_amount"
             ]

      assert comps["record_row_participations_content"]["children"] == [
               "table_cell_participations_note_title"
             ]

      # One create label in the whole tree, never repeated per table.
      label = comps["create_table_text"]["text"]
      assert label =~ ~r/^Create /
      assert Enum.count(texts(comps), &(&1 == label)) == 1
    end

    test "admin_v1: only the master grid gets View/Edit and the one create button" do
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)
      comps = components_by_id(AshA2ui.Info.build_surface(PeopleTaskUI))

      master = Enum.map(comps["data_grid_table"]["rowActions"], & &1["action"])
      assert "view_record" in master
      assert "start_edit" in master

      for grid <- ["data_grid_their_notes", "data_grid_participations"] do
        actions = Enum.map(comps[grid]["rowActions"], & &1["action"])
        refute "view_record" in actions
        refute "start_edit" in actions
        refute Map.has_key?(comps[grid], "rowClick")
      end

      assert ids_dispatching(comps, "start_create") == ["create_table_button"]
      label = comps["create_table_text"]["text"]
      assert Enum.count(texts(comps), &(&1 == label)) == 1
    end

    test "the select_context button says it selects, in both compositions" do
      basic = components_by_id(AshA2ui.Info.build_surface(PeopleTaskUI))

      assert basic["row_context_table_button"]["action"]["event"]["name"] == "context_select"
      assert basic["row_context_table_text"]["text"] == "Select person"
      # distinct from the task panel's own row control
      assert basic["view_table_button_text"]["text"] == "View"
      refute "View person" in texts(basic)

      Application.put_env(:ash_a2ui, :catalog, :admin_v1)
      admin = components_by_id(AshA2ui.Info.build_surface(PeopleTaskUI))

      master_actions = admin["data_grid_table"]["rowActions"]

      assert %{"label" => "Select person", "action" => "context_select"} =
               Enum.find(master_actions, &(&1["action"] == "context_select"))

      assert Enum.any?(master_actions, &(&1["action"] == "view_record"))
      assert admin["data_grid_table"]["rowClick"]["action"] == "context_select"
      assert admin["data_grid_table"]["rowClick"]["label"] == "Select person"
      refute Enum.any?(master_actions, &(&1["label"] == "View person"))

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

    test "a related table's rows read the same on every path: initial, deep link, " <>
           "context_select, back/forward and query refresh",
         %{ada: ada, bob: bob} do
      # Bob participates in Ada's Kickoff note: the participations table
      # carries a source column and a link, the notes table an enum.
      _ = bob
      ids = %{"person" => ada.id}

      # Deep link: the ctx ids from the URL, validated through the
      # authorized reads (AshA2ui.LiveRenderer's mount does exactly this).
      state = AshA2ui.Info.context_state_for(PeopleUI, ids)
      deep_link = root(AshA2ui.Info.build_surface(PeopleUI, context_state: state))["records"]

      # Back/forward to the same ctx params: the handle_params refresh.
      %{"updateDataModel" => %{"value" => back_forward}} =
        AshA2ui.Info.build_data_model(PeopleUI, context_state: state)

      # The row-button selection.
      {:ok, selected} =
        ActionHandler.handle(
          PeopleUI,
          envelope("context_select", %{"context" => "person", "value" => ada.id})
        )

      # A query refresh of the related table under the same selection.
      {:ok, queried} =
        ActionHandler.handle(
          PeopleUI,
          envelope("query", %{"component" => "their_notes", "query" => %{}, "contexts" => state})
        )

      notes = deep_link["their_notes"]
      participations = deep_link["participations"]

      assert Enum.map(notes, & &1["status"]) == ["Open", "Open"]
      assert [%{"note_title" => "Review", "_links" => %{"note_title" => _}}] = participations

      assert back_forward["records"]["their_notes"] == notes
      assert back_forward["records"]["participations"] == participations
      assert value_at(selected, "/records/their_notes") == notes
      assert value_at(selected, "/records/participations") == participations
      assert value_at(queried, "/records/their_notes") == notes
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
