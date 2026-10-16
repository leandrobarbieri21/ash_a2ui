defmodule AshA2ui.LinksTest.PersonVetoResolver do
  @moduledoc false
  # Vetoes relationship links to people; keeps {surface, id_path} links.
  @behaviour AshA2ui.LinkResolver

  @impl true
  def surface_for({:resource, AshA2ui.Test.Links.Person}, _context), do: nil
  def surface_for({:surface, "person"}, _context), do: "people"
  def surface_for(_target, _context), do: nil
end

defmodule AshA2ui.LinksTest do
  @moduledoc """
  Reference links (`link` / `links` field options): DSL resolution and
  loads, row/detail/panel serialization of the reserved `_links` key,
  per-actor pruning (authorized relationship loads + the link resolver),
  calculation-terminal `source` columns, the admin catalog's link/badge/
  format/rowClick column hints and link-aware detail FieldDisplays, and
  deep-link context validation.
  """

  # Shared ETS fixtures + global app env (link resolver, URL template).
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Links.{Note, NotesUI, Participant, Person}

  setup do
    for resource <- [Participant, Note, Person] do
      resource |> Ash.read!(authorize?: false) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end

    on_exit(fn ->
      Application.delete_env(:ash_a2ui, :link_resolver)
      Application.delete_env(:ash_a2ui, :open_surface_url)
      Application.put_env(:ash_a2ui, :catalog, :basic)
    end)

    ada = Ash.create!(Person, %{name: "Ada"}, authorize?: false)
    bob = Ash.create!(Person, %{name: "Bob"}, authorize?: false)
    hidden = Ash.create!(Person, %{name: "Hidden", visible: false}, authorize?: false)

    note =
      Ash.create!(
        Note,
        %{
          title: "Kickoff",
          person_id: ada.id,
          subject_id: bob.id,
          amount: 42,
          status: :open,
          body: "- first point\n- second point"
        },
        authorize?: false
      )

    for person <- [ada, bob, hidden] do
      Ash.create!(Participant, %{note_id: note.id, person_id: person.id}, authorize?: false)
    end

    secret =
      Ash.create!(Note, %{title: "Secret", person_id: hidden.id, status: :closed},
        authorize?: false
      )

    %{ada: ada, bob: bob, hidden: hidden, note: note, secret: secret}
  end

  defp data_model(messages) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
      _other -> nil
    end)
  end

  defp row(messages, title) do
    messages |> data_model() |> Map.fetch!("records") |> Enum.find(&(&1["title"] == title))
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp components_by_id(messages) do
    update = Enum.find(messages, &Map.has_key?(&1, "updateComponents"))
    Map.new(update["updateComponents"]["components"], &{&1["id"], &1})
  end

  defp envelope(name, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => "notes",
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp admin! do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
  end

  describe "resolution" do
    test "link fields resolve with their options and drive the table loads" do
      view = ResolvedView.resolve(NotesUI)

      assert view.fields[:person_name].link == :person
      assert view.fields[:subject_id].link == {:person, :subject_id}
      assert view.fields[:participant_links].links == :participants

      [table] = view.tables
      # the calculation terminal of a source path loads through the path
      assert {:person, [:display_name]} in table.loads
      # links load their relationship with the label
      assert :participants in table.loads or {:participants, [:name]} in table.loads
    end
  end

  describe "row serialization" do
    test "rows carry _links: single, explicit {surface, id_path} and multi-valued", %{
      ada: ada,
      bob: bob,
      hidden: hidden
    } do
      messages = AshA2ui.Info.build_surface(NotesUI)
      Enum.each(messages, &assert_valid_server_message/1)

      row = row(messages, "Kickoff")

      # calculation-terminal source column
      assert row["person_name"] == "Dr. Ada"

      assert row["_links"]["person_name"] == %{
               "surface" => "person",
               "recordId" => ada.id,
               "label" => "Dr. Ada"
             }

      assert row["_links"]["subject_id"] == %{
               "surface" => "person",
               "recordId" => bob.id,
               "label" => bob.id
             }

      # many_to_many links: the hidden participant is pruned by its read
      # policy (the authorized load never returns it)
      links = row["_links"]["participant_links"]
      assert Enum.map(links, & &1["label"]) |> Enum.sort() == ["Ada", "Bob"]
      refute Enum.any?(links, &(&1["recordId"] == hidden.id))

      # the virtual links field's cell value is the joined labels
      assert row["participant_links"] |> String.split(", ") |> Enum.sort() == ["Ada", "Bob"]
    end

    test "a link to a record the actor cannot read is pruned (and the cell is blank)" do
      row = NotesUI |> AshA2ui.Info.build_surface() |> row("Secret")

      assert row["person_name"] == ""
      refute Map.has_key?(row["_links"], "person_name")
      refute Map.has_key?(row["_links"], "subject_id")
      refute Map.has_key?(row["_links"], "participant_links")
    end

    test "the resolver maps targets to surface keys and may veto them", %{bob: bob} do
      defmodule VetoResolver do
        @behaviour AshA2ui.LinkResolver

        @impl true
        def surface_for({:resource, AshA2ui.Test.Links.Person}, %{actor: nil}), do: nil
        def surface_for({:surface, "person"}, _context), do: "people"
      end

      Application.put_env(:ash_a2ui, :link_resolver, VetoResolver)

      row = NotesUI |> AshA2ui.Info.build_surface() |> row("Kickoff")

      assert Map.keys(row["_links"]) == ["subject_id"]
      assert row["_links"]["subject_id"]["surface"] == "people"
      assert row["_links"]["subject_id"]["recordId"] == bob.id
    end

    test "open_surface_url adds a server-built href", %{ada: ada} do
      Application.put_env(:ash_a2ui, :open_surface_url, "/app/r/{surface}/{recordId}")

      row = NotesUI |> AshA2ui.Info.build_surface() |> row("Kickoff")

      assert row["_links"]["person_name"]["href"] == "/app/r/person/#{ada.id}"
    end

    test "surfaces without link fields serialize rows without _links" do
      Ash.create!(AshA2ui.Test.Post, %{title: "Plain"}, authorize?: false)

      [row | _] =
        AshA2ui.Test.Post |> AshA2ui.Info.build_surface() |> data_model() |> Map.get("records")

      refute Map.has_key?(row, "_links")
    end

    test "action-driven table refreshes carry the same _links", %{ada: ada} do
      {:ok, messages} =
        ActionHandler.handle(
          NotesUI,
          envelope("context_select", %{"context" => "person", "value" => ada.id})
        )

      rows = value_at(messages, "/records")
      assert [%{"title" => "Kickoff"} = row] = rows
      assert row["_links"]["person_name"]["recordId"] == ada.id
      assert length(row["_links"]["participant_links"]) == 2
    end
  end

  describe "detail and view-panel records" do
    test "a selected detail record carries _links and its virtual link values", %{
      note: note,
      ada: ada
    } do
      {:ok, messages} =
        ActionHandler.handle(
          NotesUI,
          envelope("context_select", %{"context" => "note", "value" => note.id})
        )

      detail = value_at(messages, "/detail/note")
      assert detail["title"] == "Kickoff"
      assert detail["person_name"] == "Dr. Ada"
      assert detail["_links"]["person_name"]["recordId"] == ada.id
      assert detail["participant_links"] |> String.split(", ") |> Enum.sort() == ["Ada", "Bob"]
    end

    test "the initial build of a deep-linked detail carries _links too", %{note: note} do
      state = AshA2ui.Info.context_state_for(NotesUI, %{"note" => note.id})
      messages = AshA2ui.Info.build_surface(NotesUI, context_state: state)

      detail = data_model(messages)["detail"]["note"]
      assert detail["_links"]["person_name"]["label"] == "Dr. Ada"
    end

    test "view_record's display record carries the form field's link", %{note: note, ada: ada} do
      admin!()

      {:ok, messages} =
        ActionHandler.handle(NotesUI, envelope("view_record", %{"recordId" => note.id}))

      record = value_at(messages, "/ui/panel/record")
      assert record["person_id"] == ada.id
      # the bare foreign key is no label: the destination's name is
      assert record["_links"]["person_id"] == %{
               "surface" => "person",
               "recordId" => ada.id,
               "label" => "Ada"
             }
    end
  end

  describe "admin catalog emission" do
    setup do
      admin!()
      :ok
    end

    test "columns carry link/badge/format hints and the grid a rowClick" do
      comps = NotesUI |> AshA2ui.Info.build_surface() |> components_by_id()
      grid = comps["data_grid"]
      columns = Map.new(grid["columns"], &{&1["path"], &1})

      assert columns["person_name"]["link"] == %{"path" => "_links/person_name"}
      assert columns["participant_links"]["link"] == %{"path" => "_links/participant_links"}
      assert columns["subject_id"]["link"] == %{"path" => "_links/subject_id"}
      # link columns render labels — never mono
      refute Map.has_key?(columns["subject_id"], "mono")

      assert columns["status"]["badge"] == %{
               "path" => "_badge_status",
               "tonePath" => "_badge_tone_status"
             }

      assert columns["amount"]["format"] == "number"
      assert columns["amount"]["align"] == "end"

      # whole-row click = the master/detail select envelope
      assert grid["rowClick"]["action"] == "context_select"

      assert grid["rowClick"] ==
               Enum.find(grid["rowActions"], &(&1["action"] == "context_select"))
    end

    test "rows serve the badge text the badge column binds" do
      messages = AshA2ui.Info.build_surface(NotesUI)
      assert row(messages, "Kickoff")["_badge_status"] == "Open"
      assert row(messages, "Kickoff")["_badge_tone_status"] == "success"
      assert row(messages, "Secret")["_badge_tone_status"] == "neutral"
    end

    test "admin details render FieldDisplays with link bindings" do
      comps = NotesUI |> AshA2ui.Info.build_surface() |> components_by_id()

      assert %{"component" => "fieldDisplay", "link" => %{"path" => path}} =
               comps["detail_note_detail_field_person_name"]

      assert path == "/detail/note/_links/person_name"
      refute Map.has_key?(comps["detail_note_detail_field_title"], "link")
      assert comps["detail_note_detail_field_body"]["value"] == %{"path" => "/detail/note/body"}
    end

    test "the panel's FieldDisplay binds the view record's link" do
      comps = NotesUI |> AshA2ui.Info.build_surface() |> components_by_id()

      assert comps["field_display_person_id"]["link"] == %{
               "path" => "/ui/panel/record/_links/person_id"
             }

      refute Map.has_key?(comps["field_display_title"], "link")
    end
  end

  describe "basic catalog link buttons" do
    defp link_button(comps, value_id) do
      Map.get(comps, "#{value_id}_link")
    end

    defp assert_link_button(comps, value_id, field, prefix) do
      button = link_button(comps, value_id)

      assert %{
               "component" => "Button",
               "variant" => "borderless",
               "child" => ^value_id,
               "action" => %{"event" => %{"name" => "open_surface", "context" => context}}
             } = button

      assert context == %{
               "field" => field,
               "surface" => %{"path" => "#{prefix}_links/#{field}/surface"},
               "recordId" => %{"path" => "#{prefix}_links/#{field}/recordId"}
             }

      # the value Text is unchanged: same id, same binding, now the child
      assert comps[value_id]["component"] == "Text"
      button
    end

    test "card-row meta values link to-one fields; to-many and plain fields stay Text" do
      messages = AshA2ui.Info.build_surface(NotesUI)
      Enum.each(messages, &assert_valid_server_message/1)
      comps = components_by_id(messages)

      # link :person (through a source column) and link {:person, :subject_id}
      assert_link_button(comps, "record_row_meta_value_person_name", "person_name", "")
      assert_link_button(comps, "record_row_meta_value_subject_id", "subject_id", "")

      assert comps["record_row_meta_cell_person_name"]["children"] == [
               "record_row_meta_label_person_name",
               "record_row_meta_value_person_name_link"
             ]

      # links :participants is to-many: plain text in the basic catalog
      refute link_button(comps, "record_row_meta_value_participant_links")
      refute link_button(comps, "record_row_meta_value_amount")
      refute link_button(comps, "record_row_title")
      assert comps["record_row_title"]["weight"] == 1
    end

    test "flat table cells link to-one fields" do
      messages = AshA2ui.Info.build_surface(AshA2ui.Test.Links.PagedNotesUI)
      Enum.each(messages, &assert_valid_server_message/1)
      comps = components_by_id(messages)

      assert_link_button(comps, "table_cell_person_name_value", "person_name", "")

      assert comps["table_cell_person_name"]["children"] == [
               "table_cell_person_name_label",
               "table_cell_person_name_value_link"
             ]

      refute link_button(comps, "table_cell_title_value")
    end

    test "related tables link through their own resource's relationships" do
      comps = components_by_id(AshA2ui.Info.build_surface(AshA2ui.Test.Links.PeopleUI))

      assert_link_button(
        comps,
        "table_cell_participations_note_title_value",
        "note_title",
        ""
      )

      refute link_button(comps, "table_cell_their_notes_participant_links_value")
    end

    test "detail values link through /detail/<context>/_links" do
      comps = components_by_id(AshA2ui.Info.build_surface(NotesUI))

      assert_link_button(
        comps,
        "detail_note_detail_value_person_name",
        "person_name",
        "/detail/note/"
      )

      refute link_button(comps, "detail_note_detail_value_participant_links")
      refute link_button(comps, "detail_note_detail_value_title")
    end

    test "the v1.0 surface carries the same link buttons, schema-valid" do
      [create] = AshA2ui.Info.build_surface(NotesUI, spec_version: "1.0")
      assert_valid_server_message(create, :v1_0)

      comps = Map.new(create["createSurface"]["components"], &{&1["id"], &1})
      button = link_button(comps, "record_row_meta_value_person_name")
      assert button["action"]["event"]["name"] == "open_surface"
      assert button["action"]["event"]["wantResponse"] == true
    end

    test "a field the resolver vetoes keeps its plain value Text", %{bob: bob} do
      Application.put_env(:ash_a2ui, :link_resolver, AshA2ui.LinksTest.PersonVetoResolver)
      comps = components_by_id(AshA2ui.Info.build_surface(NotesUI))

      refute link_button(comps, "record_row_meta_value_person_name")

      assert comps["record_row_meta_cell_person_name"]["children"] == [
               "record_row_meta_label_person_name",
               "record_row_meta_value_person_name"
             ]

      # the {surface, id_path} link still resolves ("people")
      assert link_button(comps, "record_row_meta_value_subject_id")

      {:ok, []} =
        ActionHandler.handle(
          NotesUI,
          envelope("open_surface", %{
            "field" => "subject_id",
            "surface" => "people",
            "recordId" => bob.id
          })
        )

      assert {:error, _messages} =
               ActionHandler.handle(
                 NotesUI,
                 envelope("open_surface", %{"field" => "person_name", "surface" => "person"})
               )
    end

    test "rows are untouched: encoder and handler refresh serialize them identically", %{
      ada: ada
    } do
      initial = NotesUI |> AshA2ui.Info.build_surface() |> data_model() |> Map.fetch!("records")

      {:ok, messages} =
        ActionHandler.handle(
          NotesUI,
          envelope("context_select", %{"context" => "person", "value" => ada.id})
        )

      refreshed = value_at(messages, "/records")
      kickoff = Enum.find(refreshed, &(&1["title"] == "Kickoff"))

      assert kickoff == Enum.find(initial, &(&1["title"] == "Kickoff"))
      assert kickoff["_links"]["person_name"]["surface"] == "person"
      refute Enum.any?(Map.keys(kickoff), &String.contains?(&1, "open"))
    end
  end

  describe "the open_surface action" do
    test "accepts a to-one link field's resolved surface, with no follow-ups", %{
      ada: ada,
      bob: bob
    } do
      for {field, record_id} <- [{"person_name", ada.id}, {"subject_id", bob.id}] do
        assert {:ok, []} =
                 ActionHandler.handle(
                   NotesUI,
                   envelope("open_surface", %{
                     "field" => field,
                     "surface" => "person",
                     "recordId" => record_id
                   })
                 )
      end
    end

    test "a row without a link for the field binds no surface: acknowledged" do
      assert {:ok, []} =
               ActionHandler.handle(
                 NotesUI,
                 envelope("open_surface", %{"field" => "person_name"})
               )

      assert {:ok, []} =
               ActionHandler.handle(
                 NotesUI,
                 envelope("open_surface", %{"field" => "person_name", "surface" => ""})
               )
    end

    test "rejects surfaces and fields the view does not link" do
      for context <- [
            %{"field" => "person_name", "surface" => "elsewhere"},
            # to-many links are not opened from the basic catalog
            %{"field" => "participant_links", "surface" => "person"},
            %{"field" => "title", "surface" => "person"},
            %{"field" => "no_such_field", "surface" => "person"},
            %{"surface" => "person"},
            %{"field" => "person_name", "surface" => 42}
          ] do
        assert {:error, messages} =
                 ActionHandler.handle(NotesUI, envelope("open_surface", context))

        assert %{"kind" => "error", "message" => message} = value_at(messages, "/ui/feedback")
        assert is_binary(message) and message != ""
      end
    end

    test "on v1.0 an accepted request answers its actionResponse", %{ada: ada} do
      message = %{
        "version" => "v1.0",
        "action" => %{
          "name" => "open_surface",
          "surfaceId" => "notes",
          "sourceComponentId" => "record_row_meta_value_person_name_link",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
          "actionId" => "a1",
          "context" => %{"field" => "person_name", "surface" => "person", "recordId" => ada.id}
        }
      }

      assert {:ok, [response]} = ActionHandler.handle(NotesUI, message, spec_version: "1.0")
      assert response["actionResponse"] == %{"value" => %{"status" => "ok", "message" => ""}}
      assert_valid_server_message(response, :v1_0)
    end
  end

  describe "deep-link context validation" do
    test "readable ids select (labels derived server-side), others are dropped", %{
      ada: ada,
      hidden: hidden
    } do
      assert %{"person" => %{"value" => value, "label" => "Ada"}} =
               AshA2ui.Info.context_state_for(NotesUI, %{"person" => ada.id})

      assert value == ada.id

      # unreadable (policy) and unknown names are not selected
      state = AshA2ui.Info.context_state_for(NotesUI, %{"person" => hidden.id, "nope" => "x"})
      assert state["person"]["value"] == ""
      refute Map.has_key?(state, "nope")
    end

    test "surfaces without contexts validate to an empty state" do
      assert AshA2ui.Info.context_state_for(AshA2ui.Test.Post, %{"x" => "y"}) == %{}
    end
  end
end
