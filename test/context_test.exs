defmodule AshA2ui.ContextTest do
  @moduledoc """
  Surface contexts, end to end: ResolvedView resolution, initial payloads
  (empty and carried `/context` state), the `context_search` /
  `context_select` / `context_clear` client actions with their cascades
  (dependent options, auto_select_single, detail records, scoped table
  refreshes), and context-scoped `query` reads. Every emitted message is
  validated against the vendored v0.9.1 JSON Schemas.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias Ash.DataLayer.Ets
  alias AshA2ui.{ActionHandler, Info, ResolvedView}
  alias AshA2ui.Test.{Appointment, AppointmentsUI, Clinic, ClinicMembership, Owner}

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

  defp assert_all_valid(messages), do: Enum.each(messages, &assert_valid_server_message/1)

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

  defp refute_path(messages, path) do
    refute Enum.any?(messages, &match?(%{"updateDataModel" => %{"path" => ^path}}, &1)),
           "unexpected updateDataModel for #{path}"
  end

  defp create_owner(name, email),
    do: Ash.create!(Owner, %{name: name, email: email}, authorize?: false)

  defp create_clinic(name), do: Ash.create!(Clinic, %{name: name}, authorize?: false)

  defp join(owner, clinic),
    do:
      Ash.create!(ClinicMembership, %{owner_id: owner.id, clinic_id: clinic.id},
        authorize?: false
      )

  defp create_appointment(title, owner, clinic) do
    Ash.create!(
      Appointment,
      %{
        title: title,
        owner_id: owner.id,
        clinic_id: clinic.id,
        scheduled_for: DateTime.utc_now()
      },
      authorize?: false
    )
  end

  # Ada belongs to two clinics (no auto-select), Bob to exactly one
  # (auto_select_single kicks in); one appointment per (owner, clinic) pair.
  defp seed do
    ada = create_owner("Ada Lovelace", "ada@example.com")
    bob = create_owner("Bob Ross", "bob@example.com")
    north = create_clinic("North")
    south = create_clinic("South")
    east = create_clinic("East")
    join(ada, north)
    join(ada, south)
    join(bob, east)

    %{
      ada: ada,
      bob: bob,
      north: north,
      south: south,
      east: east,
      ada_north: create_appointment("Ada North checkup", ada, north),
      ada_south: create_appointment("Ada South dental", ada, south),
      bob_east: create_appointment("Bob East exam", bob, east)
    }
  end

  defp contexts_state(selected) do
    Map.new(selected, fn {name, record} ->
      {to_string(name), %{"search" => "", "value" => record.id, "label" => "x"}}
    end)
  end

  # --- resolution ---------------------------------------------------------------

  describe "ResolvedView resolution" do
    test "resolves contexts with defaults, order, and dependencies" do
      view = ResolvedView.resolve(AppointmentsUI)

      assert view.context_order == [:owner, :clinic, :appointment]

      assert %{
               resource: Owner,
               option_value: :id,
               option_label: :email,
               option_sort: :email,
               search_fields: [:email, :name],
               option_limit: 10,
               depends_on: nil,
               picker: true
             } = view.contexts[:owner]

      assert %{
               resource: Clinic,
               option_label: :name,
               depends_on: :owner,
               depends_on_path: [:memberships, :owner_id],
               auto_select_single: true,
               picker: true
             } = view.contexts[:clinic]

      assert %{resource: Appointment, picker: false} = view.contexts[:appointment]
    end

    test "resolves detail components against their context's resource" do
      view = ResolvedView.resolve(AppointmentsUI)

      assert [owner_card, appointment_detail] = view.details
      assert owner_card.name == :owner_card
      assert owner_card.context == :owner
      assert owner_card.fields == [:name, :email]
      assert owner_card.detail_path == "/detail/owner"

      assert appointment_detail.context == :appointment
      assert appointment_detail.detail_path == "/detail/appointment"
    end

    test "resolves table context options" do
      view = ResolvedView.resolve(AppointmentsUI)

      assert [table] = view.tables
      assert table.context_filter == [owner_id: :owner, clinic_id: :clinic]
      assert table.require_context == [:owner, :clinic]
      assert table.select_context == :appointment
    end

    test "context and detail initial states" do
      view = ResolvedView.resolve(AppointmentsUI)

      assert ResolvedView.contexts?(view)

      assert ResolvedView.context_state(view) == %{
               "owner" => %{"search" => "", "value" => "", "label" => ""},
               "clinic" => %{"search" => "", "value" => "", "label" => ""},
               "appointment" => %{"search" => "", "value" => "", "label" => ""}
             }

      assert ResolvedView.detail_state(view) == %{"owner" => %{}, "appointment" => %{}}
    end
  end

  # --- initial payload ------------------------------------------------------------

  describe "initial payload" do
    test "emits context state, empty details, owner options, and no records" do
      %{ada: _ada} = seed()

      messages = Info.build_surface(AppointmentsUI, authorize?: false)
      assert_all_valid(messages)

      [_create, %{"updateComponents" => %{"components" => components}}, data_model] = messages
      value = data_model["updateDataModel"]["value"]

      # All three contexts start unselected; both details empty.
      assert value["context"]["owner"] == %{"search" => "", "value" => "", "label" => ""}
      assert value["detail"] == %{"owner" => %{}, "appointment" => %{}}

      # Owner options load (sorted by email); the dependent clinic list is
      # empty while no owner is selected; pickerless contexts load nothing.
      assert [%{"label" => "ada@example.com"}, %{"label" => "bob@example.com"}] =
               value["options"]["owner"]

      assert value["options"]["clinic"] == []
      refute Map.has_key?(value["options"], "appointment")

      # require_context unmet: no records, honest empty query state.
      assert value["records"] == []
      assert value["query"]["totalCount"] == 0

      ids = MapSet.new(components, & &1["id"])
      assert "context_owner" in ids
      assert "context_clinic" in ids
      refute "context_appointment" in ids
      assert "detail_owner_card" in ids
      assert "detail_appointment_detail" in ids
      assert "row_context_button" in ids

      by_id = Map.new(components, &{&1["id"], &1})

      # Picker sections and details render as Cards over a _body layout
      # (section chrome for every renderer, no client smarts required).
      assert %{"component" => "Card", "child" => "context_owner_body"} = by_id["context_owner"]

      assert %{
               "component" => "Column",
               "children" => [
                 "context_owner_label",
                 "context_owner_selected_row",
                 "context_owner_controls",
                 "context_owner_options"
               ]
             } = by_id["context_owner_body"]

      # The clinic picker is not searchable: no _controls child.
      assert %{
               "component" => "Column",
               "children" => [
                 "context_clinic_label",
                 "context_clinic_selected_row",
                 "context_clinic_options"
               ]
             } = by_id["context_clinic_body"]

      assert %{"component" => "Card", "child" => "detail_owner_card_body"} =
               by_id["detail_owner_card"]

      assert %{"component" => "Column", "children" => ["detail_owner_card_heading" | _]} =
               by_id["detail_owner_card_body"]

      # The owner picker is searchable; the clinic picker (no option_search)
      # emits no search controls.
      assert "context_owner_search_input" in ids
      refute "context_clinic_search_input" in ids

      # Root: the feedback line, then contexts, then components in
      # declaration order (no form, so no task panel and no create button).
      root = Enum.find(components, &(&1["id"] == "root"))

      assert root["children"] ==
               [
                 "status_text",
                 "context_owner",
                 "context_clinic",
                 "detail_owner_card",
                 "table_heading",
                 "query_controls",
                 "records_list",
                 "empty_state",
                 "query_pagination",
                 "detail_appointment_detail",
                 "action_result_panel"
               ]
    end

    test "formless surfaces render no View/Edit row controls (no panel to open)" do
      seed()

      [_create, %{"updateComponents" => %{"components" => components}}, _data] =
        Info.build_surface(AppointmentsUI, authorize?: false)

      ids = MapSet.new(components, & &1["id"])

      # AppointmentsUI declares no :form — there is no task panel for View
      # to open, so the dead controls are omitted; the context-select button
      # remains the row's selection affordance.
      refute "view_button" in ids
      refute "edit_button" in ids
      assert "row_context_button" in ids

      row_content = Enum.find(components, &(&1["id"] == "record_row_content"))
      assert "row_context_button" in row_content["children"]
      refute "view_button" in row_content["children"]

      label = Enum.find(components, &(&1["id"] == "row_context_text"))
      assert label["text"] == "Select appointment"
    end

    test "row select_context button dispatches context_select with bindings" do
      seed()

      [_create, %{"updateComponents" => %{"components" => components}}, _data] =
        Info.build_surface(AppointmentsUI, authorize?: false)

      button = Enum.find(components, &(&1["id"] == "row_context_button"))
      event = button["action"]["event"]

      assert event["name"] == "context_select"

      assert event["context"] == %{
               "context" => "appointment",
               "value" => %{"path" => "id"},
               "query" => %{"path" => "/query"},
               "contexts" => %{"path" => "/context"}
             }
    end

    test "a carried context_state scopes records, options, and details" do
      %{ada: ada, north: north} = seed()

      messages =
        Info.build_surface(AppointmentsUI,
          authorize?: false,
          context_state: contexts_state(owner: ada, clinic: north)
        )

      assert_all_valid(messages)
      [_create, _components, data_model] = messages
      value = data_model["updateDataModel"]["value"]

      assert [%{"title" => "Ada North checkup"}] = value["records"]
      assert [%{"label" => "North"}, %{"label" => "South"}] = value["options"]["clinic"]
      assert %{"name" => "Ada Lovelace", "email" => "ada@example.com"} = value["detail"]["owner"]
      assert value["context"]["owner"]["value"] == ada.id
    end

    test "context-less surfaces keep the frozen data-model shape" do
      [_create, _components, data_model] =
        Info.build_surface(AshA2ui.Test.MinimalUI, authorize?: false)

      value = data_model["updateDataModel"]["value"]
      refute Map.has_key?(value, "context")
      refute Map.has_key?(value, "detail")
    end
  end

  # --- context_search --------------------------------------------------------------

  describe "context_search" do
    test "returns the filtered, dependency-free option page" do
      seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_search", %{"context" => "owner", "search" => "ada"}),
                 authorize?: false
               )

      assert_all_valid(messages)
      assert [%{"label" => "ada@example.com"}] = value_at(messages, "/options/owner")
    end

    test "rejects undeclared and unsearchable contexts" do
      assert {:error, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_search", %{"context" => "nope", "search" => "x"}),
                 authorize?: false
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "not declared"

      assert {:error, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_search", %{"context" => "clinic", "search" => "x"}),
                 authorize?: false
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "not searchable"
    end
  end

  # --- context_select ---------------------------------------------------------------

  describe "context_select" do
    test "selects a root context: state, dependent options, detail, scoped table" do
      %{ada: ada} = seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{"context" => "owner", "value" => ada.id}),
                 authorize?: false
               )

      assert_all_valid(messages)

      context = value_at(messages, "/context")

      assert context["owner"] == %{
               "search" => "",
               "value" => ada.id,
               "label" => "ada@example.com"
             }

      # Two clinics: no auto-select.
      assert context["clinic"]["value"] == ""

      assert [%{"label" => "North"}, %{"label" => "South"}] =
               value_at(messages, "/options/clinic")

      assert %{"name" => "Ada Lovelace", "email" => "ada@example.com", "id" => _} =
               value_at(messages, "/detail/owner")

      # require_context met through :owner — records scope to Ada only.
      records = value_at(messages, "/records")

      assert Enum.map(records, & &1["title"]) |> Enum.sort() ==
               ["Ada North checkup", "Ada South dental"]

      assert value_at(messages, "/query")["totalCount"] == 2

      # a settled selection clears the previous outcome (and so settles the
      # admin dataGrid's busy "Select <context>" row action)
      assert value_at(messages, "/ui/feedback") == %{"kind" => nil, "message" => ""}
    end

    test "auto_select_single cascades a sole dependent option into selection" do
      %{bob: bob, east: east} = seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{"context" => "owner", "value" => bob.id}),
                 authorize?: false
               )

      assert_all_valid(messages)

      context = value_at(messages, "/context")
      assert context["clinic"] == %{"search" => "", "value" => east.id, "label" => "East"}

      assert [%{"title" => "Bob East exam"}] = value_at(messages, "/records")
    end

    test "narrows to a dependent selection" do
      %{ada: ada, north: north} = seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{
                   "context" => "clinic",
                   "value" => north.id,
                   "contexts" => contexts_state(owner: ada)
                 }),
                 authorize?: false
               )

      assert_all_valid(messages)
      assert value_at(messages, "/context")["clinic"]["value"] == north.id
      assert [%{"title" => "Ada North checkup"}] = value_at(messages, "/records")
    end

    test "rejects a dependent value outside the parent's scope" do
      %{ada: ada, east: east} = seed()

      # East is Bob's clinic — not reachable under Ada.
      assert {:error, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{
                   "context" => "clinic",
                   "value" => east.id,
                   "contexts" => contexts_state(owner: ada)
                 }),
                 authorize?: false
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "not found"
    end

    test "re-selecting the parent clears stale dependent selections" do
      %{ada: ada, bob: bob, east: east} = seed()

      # Client carries a clinic that belonged to the previously selected owner.
      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{
                   "context" => "owner",
                   "value" => ada.id,
                   "contexts" => contexts_state(owner: bob, clinic: east)
                 }),
                 authorize?: false
               )

      context = value_at(messages, "/context")
      assert context["owner"]["value"] == ada.id
      assert context["clinic"]["value"] == ""
    end

    test "selects a pickerless context through select_context (master/detail)" do
      %{ada: ada, north: north, ada_north: appointment} = seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{
                   "context" => "appointment",
                   "value" => appointment.id,
                   "contexts" => contexts_state(owner: ada, clinic: north)
                 }),
                 authorize?: false
               )

      assert_all_valid(messages)

      assert %{"title" => "Ada North checkup", "status" => "scheduled"} =
               value_at(messages, "/detail/appointment")

      # The owner/clinic selections are untouched; no table filters on
      # :appointment, so no /records refresh is included.
      context = value_at(messages, "/context")
      assert context["owner"]["value"] == ada.id
      refute_path(messages, "/records")
    end

    test "rejects unknown values and contexts" do
      seed()

      assert {:error, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{
                   "context" => "owner",
                   "value" => Ash.UUID.generate()
                 }),
                 authorize?: false
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "not found"

      assert {:error, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_select", %{"context" => "nope", "value" => "x"}),
                 authorize?: false
               )

      assert value_at(messages, "/ui/feedback")["message"] =~ "not declared"
    end
  end

  # --- context_clear -----------------------------------------------------------------

  describe "context_clear" do
    test "clears the selection and cascades dependents back to empty" do
      %{ada: ada, north: north} = seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_clear", %{
                   "context" => "owner",
                   "contexts" => contexts_state(owner: ada, clinic: north)
                 }),
                 authorize?: false
               )

      assert_all_valid(messages)

      context = value_at(messages, "/context")
      assert context["owner"]["value"] == ""
      assert context["clinic"]["value"] == ""

      assert value_at(messages, "/options/clinic") == []
      assert value_at(messages, "/detail/owner") == %{}
      assert value_at(messages, "/records") == []
      assert value_at(messages, "/query")["totalCount"] == 0
      assert value_at(messages, "/ui/feedback") == %{"kind" => nil, "message" => ""}
    end

    test "clearing only the dependent keeps the parent" do
      %{ada: ada, north: north} = seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("context_clear", %{
                   "context" => "clinic",
                   "contexts" => contexts_state(owner: ada, clinic: north)
                 }),
                 authorize?: false
               )

      context = value_at(messages, "/context")
      assert context["owner"]["value"] == ada.id
      assert context["clinic"]["value"] == ""

      # Owner still selected: require_context stays met, both Ada rows back.
      assert length(value_at(messages, "/records")) == 2
    end
  end

  # --- scoped query reads ---------------------------------------------------------------

  describe "context-scoped query actions" do
    test "query reads AND the carried context filters" do
      %{ada: ada} = seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("query", %{
                   "query" => %{"search" => "checkup"},
                   "contexts" => contexts_state(owner: ada)
                 }),
                 authorize?: false
               )

      assert_all_valid(messages)
      assert [%{"title" => "Ada North checkup"}] = value_at(messages, "/records")
      assert value_at(messages, "/query")["totalCount"] == 1
    end

    test "query reads without required contexts return no records and no read" do
      seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("query", %{"query" => %{}}),
                 authorize?: false
               )

      assert value_at(messages, "/records") == []
      assert value_at(messages, "/query")["totalCount"] == 0
    end

    test "malformed carried contexts degrade to unselected" do
      seed()

      assert {:ok, messages} =
               ActionHandler.handle(
                 AppointmentsUI,
                 envelope("query", %{
                   "query" => %{},
                   "contexts" => %{"owner" => "garbage", "clinic" => %{"value" => 42}}
                 }),
                 authorize?: false
               )

      assert value_at(messages, "/records") == []
    end
  end
end
