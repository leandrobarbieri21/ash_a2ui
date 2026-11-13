defmodule AshA2ui.ManifestTest do
  @moduledoc """
  `AshA2ui.Manifest`: the per-surface description of tables, presets and row
  actions, checked against what the encoder renders for the same surface.
  """

  # ETS fixtures are private to the test process; the configured catalog is
  # never touched (every build passes `:catalog`).
  use ExUnit.Case, async: true

  alias AshA2ui.Manifest
  alias AshA2ui.Test.{ManifestTask, Minimal, PseudoLocale, Referral}

  @catalogs [:basic, :admin_v1]
  @pseudo [gettext_fn: {PseudoLocale, :translate}, locale: "pseudo"]

  defp seed_tasks do
    for {title, status} <- [{"Write", :open}, {"Ship", :open}, {"Plan", :done}] do
      Ash.create!(ManifestTask, %{title: title, status: status}, authorize?: false)
    end
  end

  defp components(messages) do
    messages
    |> Enum.flat_map(
      &(get_in(&1, ["createSurface", "components"]) ||
          get_in(&1, ["updateComponents", "components"]) || [])
    )
    |> Map.new(&{&1["id"], &1})
  end

  defp data_model(messages) do
    Enum.find_value(messages, fn
      %{"createSurface" => %{"dataModel" => value}} -> value
      %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
      _other -> nil
    end)
  end

  defp at(data, "/" <> path), do: get_in(data, String.split(path, "/"))

  describe "for_surface/2" do
    test "describes each table: resource, read, columns, query and presets" do
      manifest = Manifest.for_surface(ManifestTask, catalog: :admin_v1)

      assert %{version: 2, surface_id: "manifest_tasks", resource: ManifestTask} = manifest
      assert manifest.version == Manifest.version()
      assert manifest.catalog == :admin_v1

      assert [open, done] = manifest.tables

      assert %{
               id: "open_tasks",
               label: "Open tasks",
               resource: ManifestTask,
               read_action: :read,
               display: :list,
               sectioned: false,
               component_id: "data_grid_open_tasks",
               records_path: "/records/open_tasks",
               columns: [
                 %{name: :title, label: "Task"},
                 %{name: :status, label: "Status"},
                 %{name: :note, label: "Note"}
               ],
               query: %{name: :open_query, default_preset: :live, preset_picker_label: "View"},
               row_actions: [
                 "open_tasks.complete",
                 "open_tasks.annotate",
                 "open_tasks.discard",
                 "open_tasks.purge"
               ]
             } = open

      assert open.presets == [
               %{
                 name: :live,
                 label: "Live",
                 read_action: :read,
                 filter: [
                   %{field: :status, op: :eq, value: :open},
                   %{field: :archived_at, op: :is_nil, value: nil}
                 ]
               },
               %{name: :archived, label: "Archived", read_action: :archived, filter: []}
             ]

      assert %{id: "done_tasks", read_action: :done, query: nil, presets: []} = done
      assert done.row_actions == ["done_tasks.reopen"]
    end

    test "names the card body for a table with a row_layout" do
      assert [%{component_id: "record_row_body"}] =
               Manifest.for_surface(AshA2ui.Test.Promotion, catalog: :basic).tables

      assert [
               %{component_id: "record_row_inbox_body"},
               %{component_id: "record_row_everything_content"}
             ] =
               Manifest.for_surface(AshA2ui.Test.BulkCardsUI, catalog: :basic).tables
    end

    test "names the element carrying the rows for the catalog it is built for" do
      assert [%{component_id: "record_row_open_tasks_content"}, _done] =
               Manifest.for_surface(ManifestTask, catalog: :basic).tables

      assert [%{component_id: "record_row_content"}] =
               Manifest.for_surface(Referral, catalog: :basic).tables

      assert [%{component_id: "data_grid", query: query}] =
               Manifest.for_surface(Referral, catalog: :admin_v1).tables

      assert query.default_sort == [
               %{field: :status_priority, direction: :asc},
               %{field: :code, direction: :asc}
             ]
    end

    test "a row action with visible_when lists its conditions" do
      %{row_actions: actions} = Manifest.for_surface(ManifestTask, catalog: :basic)
      by_id = Map.new(actions, &{&1.id, &1})

      assert by_id["open_tasks.complete"].visible_when == [
               %{field: :status, op: :eq, value: :open},
               %{field: :archived_at, op: :is_nil, value: nil}
             ]

      assert by_id["done_tasks.reopen"].visible_when == [
               %{field: :status, op: :in, value: [:done]}
             ]

      assert by_id["open_tasks.annotate"].visible_when == []
    end

    test "a prompt row action lists its fields and its confirm control" do
      %{row_actions: actions} = Manifest.for_surface(ManifestTask, catalog: :admin_v1)
      annotate = Enum.find(actions, &(&1.ash_action == :annotate))

      assert %{
               id: "open_tasks.annotate",
               table: "open_tasks",
               label: "Add note",
               resource: ManifestTask,
               action_type: :update,
               via: false,
               prompt_title: "Annotate task",
               confirm: :prompt,
               confirm_label: "Confirm",
               selector: ~s([data-a2ui-action="annotate"])
             } = annotate

      assert annotate.prompt_fields == [
               %{
                 name: :note,
                 label: "Note",
                 type: Ash.Type.String,
                 widget: :text_field,
                 required: true,
                 options: nil,
                 relationship: nil
               },
               %{
                 name: :priority,
                 label: "Priority",
                 type: Ash.Type.Atom,
                 widget: :choice_picker,
                 required: true,
                 options: [%{value: "low", label: "Low"}, %{value: "high", label: "High"}],
                 relationship: nil
               },
               %{
                 name: :urgent,
                 label: "Urgent",
                 type: Ash.Type.Boolean,
                 widget: :check_box,
                 required: false,
                 options: nil,
                 relationship: nil
               }
             ]
    end

    test "a destroy is confirmed by the admin grid's dialog, not by the basic button" do
      discard = fn catalog ->
        Enum.find(
          Manifest.for_surface(ManifestTask, catalog: catalog).row_actions,
          &(&1.ash_action == :discard)
        )
      end

      assert %{action_type: :destroy, confirm: :destructive, confirm_label: "Discard"} =
               discard.(:admin_v1)

      assert %{action_type: :destroy, confirm: nil, confirm_label: nil} = discard.(:basic)
    end

    test "a surface without row actions has tables and no row actions" do
      for catalog <- @catalogs do
        manifest = Manifest.for_surface(Minimal, catalog: catalog)

        assert manifest.row_actions == []
        assert [%{id: "table", resource: Minimal, row_actions: [], query: nil}] = manifest.tables
      end
    end

    test "is plain data: it encodes as JSON" do
      for catalog <- @catalogs, module <- Manifest.surfaces(:ash_a2ui) do
        assert {:ok, _json} = Jason.encode(Manifest.for_surface(module, catalog: catalog))
      end
    end
  end

  describe "labels are the rendered ones" do
    # Every label the manifest states is read off the payload the encoder
    # builds for the same surface, with and without a translator.
    for catalog <- @catalogs, {variant, l10n} <- [plain: [], translated: @pseudo] do
      @tag catalog: catalog, l10n: l10n
      test "#{catalog}, #{variant}", %{catalog: catalog, l10n: l10n} do
        seed_tasks()

        for module <- [ManifestTask, Referral] do
          opts = [catalog: catalog] ++ l10n
          manifest = Manifest.for_surface(module, opts)
          rendered = components(AshA2ui.Info.build_surface(module, [authorize?: false] ++ opts))

          assert manifest.row_actions != []

          for table <- manifest.tables do
            assert Map.has_key?(rendered, table.component_id), "#{table.component_id} renders"
            assert_preset_picker(rendered, manifest, table)
          end

          for action <- manifest.row_actions do
            table = Enum.find(manifest.tables, &(&1.id == action.table))
            assert_row_action_rendered(catalog, rendered, manifest, table, action)
          end

          if catalog == :admin_v1, do: assert_grid(rendered, manifest)
        end
      end
    end

    test "translated labels are the translator's" do
      manifest = Manifest.for_surface(ManifestTask, [catalog: :admin_v1] ++ @pseudo)
      annotate = Enum.find(manifest.row_actions, &(&1.ash_action == :annotate))

      assert annotate.label == "⟦Add note⟧"
      assert annotate.confirm_label == "⟦Confirm⟧"
      assert annotate.prompt_title == "⟦Annotate task⟧"
      assert hd(manifest.tables).query.preset_picker_label == "⟦View⟧"
    end
  end

  defp suffix(manifest, table) do
    if length(manifest.tables) > 1, do: "_#{table.id}", else: ""
  end

  defp assert_row_action_rendered(:basic, rendered, manifest, table, action) do
    base = "row_action#{suffix(manifest, table)}_#{action.ash_action}"

    assert rendered["#{base}_text"]["text"] == action.label

    case action.confirm do
      :prompt ->
        assert rendered["#{base}_confirm_text"]["text"] == action.confirm_label
        assert rendered["#{base}_prompt_title"]["text"] == "### " <> action.prompt_title

        for field <- action.prompt_fields do
          input = rendered["#{base}_prompt_input_#{field.name}"]
          assert input["label"] == field.label
          assert_options(input, field)
        end

      nil ->
        refute Map.has_key?(rendered, "#{base}_confirm_button")
    end
  end

  defp assert_row_action_rendered(:admin_v1, rendered, manifest, table, action) do
    grid = rendered["data_grid#{suffix(manifest, table)}"]

    entry =
      Enum.find(grid["rowActions"], &(&1["context"]["action"] == to_string(action.ash_action)))

    assert entry["label"] == action.label
    assert Map.has_key?(entry, "visiblePath") == (action.visible_when != [])

    case action.confirm do
      :prompt ->
        assert entry["prompt"]["confirmLabel"] == action.confirm_label
        assert entry["prompt"]["title"] == action.prompt_title

        for field <- action.prompt_fields do
          input =
            rendered[
              "row_action#{suffix(manifest, table)}_#{action.ash_action}_prompt_input_#{field.name}"
            ]

          assert input["label"] == field.label
          assert_options(input, field)
        end

      # The grid's ConfirmDialog reads its confirm button's label off the
      # entry's own label (ash_admin_catalog.js, syncConfirmDialog).
      :destructive ->
        assert entry["destructive"] == true
        assert action.confirm_label == entry["label"]

      nil ->
        refute Map.has_key?(entry, "prompt")
        refute Map.has_key?(entry, "destructive")
    end
  end

  defp assert_options(input, %{options: nil}), do: refute(input["component"] == "ChoicePicker")

  defp assert_options(input, %{options: options}) do
    assert input["component"] == "ChoicePicker"
    assert Enum.map(input["options"], &%{value: &1["value"], label: &1["label"]}) == options
  end

  defp assert_grid(rendered, manifest) do
    for table <- manifest.tables do
      grid = rendered[table.component_id]
      assert grid["label"] == table.label

      assert Enum.map(
               grid["columns"],
               &%{name: String.to_existing_atom(&1["path"]), label: &1["label"]}
             ) ==
               table.columns
    end
  end

  defp assert_preset_picker(_rendered, _manifest, %{query: nil}), do: :ok

  defp assert_preset_picker(rendered, manifest, table) do
    picker = rendered["query#{suffix(manifest, table)}_preset_picker"]
    assert picker["label"] == table.query.preset_picker_label

    preset_options = Enum.reject(picker["options"], &(&1["value"] == ""))

    assert Enum.map(preset_options, &{&1["value"], &1["label"]}) ==
             Enum.map(table.presets, &{to_string(&1.name), &1.label})
  end

  describe "visible?/2 and filter_input/1" do
    test "agree with the rows the server marks visible, on records and on data-model rows" do
      tasks = seed_tasks()
      manifest = Manifest.for_surface(ManifestTask, catalog: :basic)

      data =
        data_model(AshA2ui.Info.build_surface(ManifestTask, authorize?: false, catalog: :basic))

      for action <- manifest.row_actions, action.visible_when != [] do
        table = Enum.find(manifest.tables, &(&1.id == action.table))

        for row <- at(data, table.records_path) do
          rendered? = row["_visible_#{action.ash_action}"] != []
          # The conditions alone, over the row's rendered values...
          assert Manifest.visible?(action.visible_when, row) == rendered?,
                 "#{action.id} on #{row["title"]}"

          # ...and the server's verdict the row carries.
          assert Manifest.visible?(action, row) == rendered?
          refute Manifest.visible?(action, Map.put(row, "_visible_#{action.ash_action}", []))
        end

        expected = tasks |> Enum.filter(&Manifest.visible?(action, &1)) |> ids()

        read =
          ManifestTask
          |> Ash.Query.filter_input(Manifest.filter_input(action))
          |> Ash.read!(authorize?: false)
          |> ids()

        assert read == expected, action.id
      end
    end

    test "an action whose conditions exclude every row renders on none" do
      seed_tasks()
      manifest = Manifest.for_surface(ManifestTask, catalog: :basic)
      purge = Enum.find(manifest.row_actions, &(&1.id == "open_tasks.purge"))
      table = hd(manifest.tables)
      live = Enum.find(table.presets, &(&1.name == table.query.default_preset))

      rows =
        at(
          data_model(
            AshA2ui.Info.build_surface(ManifestTask, authorize?: false, catalog: :basic)
          ),
          table.records_path
        )

      assert length(rows) == 2
      refute Enum.any?(rows, &Manifest.visible?(purge, &1))
      assert Enum.all?(rows, &(&1["_visible_purge"] == []))
      refute "purge" in Enum.flat_map(rows, & &1["_actions"])

      # The table's default read, narrowed to the action's rows: nothing.
      assert ManifestTask
             |> Ash.Query.for_read(live.read_action)
             |> Ash.Query.filter_input(Manifest.filter_input(live))
             |> Ash.Query.filter_input(Manifest.filter_input(purge))
             |> Ash.read!(authorize?: false) == []
    end

    test "compare values as the encoder writes them" do
      conditions = [%{field: :status, op: :in, value: [:pending, :approved]}]

      assert Manifest.visible?(conditions, %{"status" => "approved"})
      assert Manifest.visible?(conditions, %{status: :pending})
      refute Manifest.visible?(conditions, %{"status" => "declined"})

      refute Manifest.visible?([%{field: :deleted_at, op: :is_nil, value: nil}], %{
               deleted_at: ~U[2026-01-01 00:00:00Z]
             })

      assert Manifest.visible?([], %{})
      assert Manifest.filter_input([]) == %{}
    end
  end

  describe "for_surfaces/2 and surfaces/1" do
    test "keys manifests by surface id" do
      assert %{"manifest_tasks" => %{module: ManifestTask}, "referrals" => %{module: Referral}} =
               Manifest.for_surfaces([ManifestTask, Referral], catalog: :basic)
    end

    test "refuses two surfaces with one id" do
      assert_raise ArgumentError, ~r/both declare the surface id "referrals"/, fn ->
        Manifest.for_surfaces([Referral, Referral])
      end
    end

    test "finds an application's surfaces, and every one of them builds" do
      surfaces = Manifest.surfaces(:ash_a2ui)

      assert ManifestTask in surfaces
      assert Referral in surfaces
      refute AshA2ui.Manifest in surfaces
      refute AshA2ui.Test.Domain in surfaces

      for catalog <- @catalogs, module <- surfaces do
        assert %{version: 2} = Manifest.for_surface(module, catalog: catalog)
      end
    end
  end

  defp ids(records), do: records |> Enum.map(& &1.id) |> Enum.sort()
end
