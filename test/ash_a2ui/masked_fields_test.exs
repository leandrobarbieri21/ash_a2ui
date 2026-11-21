defmodule AshA2ui.MaskedFieldsTest do
  @moduledoc """
  Hidden fields: a value the actor's field policies forbid (`Ash.ForbiddenField`)
  renders the masked text with a reason — never `null` or empty, and never
  the hidden value — on table rows, `:detail` cards and the view panel,
  while the `/form` edit buffer and CSV exports keep the empty value they
  always had. Secondary text (badges, diagram markers, canvas record
  labels) draws the masked word too.
  """

  # The catalog env toggle is global.
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.Canvas.ObjectRef
  alias AshA2ui.Encoder
  alias AshA2ui.Info
  alias AshA2ui.Masked
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{Messages, SecureClient, SecureLease, SecureLeasesUI, Surface}

  @admin %{role: :admin}
  @viewer %{role: :viewer}
  @masked_text "Hidden"
  @reason "You do not have access to this value."
  # A distinctive stored rate: a viewer's payload must never carry it.
  @rate "424242"

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)

    client =
      Ash.create!(SecureClient, %{name: "Acme Lines", credit_line: "5000"}, authorize?: false)

    lease =
      Ash.create!(
        SecureLease,
        %{name: "Loft", rate: @rate, note: nil, state: :open, client_id: client.id},
        authorize?: false
      )

    %{client: client, lease: lease}
  end

  defp wire(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp forbidden(field, type, secret),
    do: %Ash.ForbiddenField{field: field, type: type, original_value: secret}

  defp envelope(name, context),
    do: Messages.call(name, "secure_leases", context)

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp table_rows do
    [%{"createSurface" => %{"dataModel" => %{"records" => rows}}}] =
      Info.build_surface(SecureLeasesUI, actor: @viewer)

    rows
  end

  # --- the Masked module ------------------------------------------------------

  describe "AshA2ui.Masked" do
    test "masked? is true for a forbidden field only" do
      assert Masked.masked?(forbidden(:rate, :attribute, "x"))
      assert Masked.masked?(forbidden(:client, :relationship, nil))
      refute Masked.masked?(nil)
      refute Masked.masked?("Hidden")
      refute Masked.masked?(%Ash.NotLoaded{field: :rate, type: :attribute})
    end

    test "text and reason read English without a translator" do
      assert Masked.text(nil) == @masked_text
      assert Masked.reason(nil) == @reason
    end

    test "row_data carries the reason per field, and nothing when empty" do
      assert Masked.row_data([], nil) == %{}
      assert Masked.row_data([:rate], nil) == %{"_masked" => %{"rate" => @reason}}

      assert Masked.row_data([:rate, :note], nil) == %{
               "_masked" => %{"rate" => @reason, "note" => @reason}
             }
    end

    test "a forbidden step anywhere in a source walk masks it; a nil or unloaded step ends it" do
      client = %SecureClient{name: "Acme", credit_line: forbidden(:credit_line, :attribute, "x")}

      lease = %SecureLease{name: "Loft", client: client}

      assert Masked.forbidden_source?(lease, [:client, :credit_line])
      refute Masked.forbidden_source?(lease, [:client, :name])

      unloaded = %SecureLease{
        name: "Loft",
        client: %Ash.NotLoaded{field: :client, type: :relationship}
      }

      refute Masked.forbidden_source?(unloaded, [:client, :credit_line])
      refute Masked.forbidden_source?(%SecureLease{name: "Loft"}, [:client, :credit_line])

      relationship_forbidden = %SecureLease{
        name: "Loft",
        client: forbidden(:client, :relationship, client)
      }

      assert Masked.forbidden_source?(relationship_forbidden, [:client, :name])
    end
  end

  # --- table rows -------------------------------------------------------------

  describe "a forbidden field in a table row" do
    test "draws the masked text with its reason; a visible nil stays null" do
      [row] =
        Enum.filter(table_rows(), &(&1["name"] == "Loft"))

      assert row["rate"] == @masked_text

      assert row["_masked"] == %{
               "rate" => @reason,
               "client_credit" => @reason
             }

      # the source walk hits a forbidden leaf: the client's credit line
      assert row["client_credit"] == @masked_text
      assert row["_masked"]["client_credit"] == @reason

      # the client's name is not forbidden, so the walk reads it
      assert row["client_name"] == "Acme Lines"

      # a nil the reader may see renders empty (null), no _masked entry
      assert row["note"] == nil
      refute Map.has_key?(row["_masked"], "note")
    end

    test "draws the value for an actor who may see it, with no _masked key" do
      [%{"createSurface" => %{"dataModel" => %{"records" => rows}}}] =
        Info.build_surface(SecureLeasesUI, actor: @admin)

      assert [%{"rate" => @rate, "client_credit" => "5000", "client_name" => "Acme Lines"}] =
               Enum.filter(rows, &(&1["name"] == "Loft"))

      refute Enum.any?(rows, &Map.has_key?(&1, "_masked"))
    end

    test "the read with field policies is schema-valid on the admin catalog" do
      messages = Info.build_surface(SecureLeasesUI, actor: @viewer)
      assert_valid_agent_messages(messages, catalogs: admin_catalogs())
    end
  end

  # --- the leak: nothing of the struct reaches the wire -----------------------

  describe "the forbidden struct never reaches the wire" do
    test "a row built with original_value leaks neither the value nor the struct" do
      view = ResolvedView.resolve(SecureLeasesUI)
      [table] = view.tables

      record = %{
        lease_record()
        | rate: forbidden(:rate, :attribute, "SECRET-4711"),
          client: forbidden(:client, :relationship, "SECRET-4711")
      }

      row = wire(Encoder.serialize_row(view, table, record, nil))

      assert row["rate"] == @masked_text
      assert row["_masked"]["rate"] == @reason
      # the forbidden relationship masks every source field behind it
      assert row["client_name"] == @masked_text
      assert row["client_credit"] == @masked_text
      refute Jason.encode!(row) =~ "SECRET-4711"
      refute Jason.encode!(row) =~ "ForbiddenField"
    end

    test "a detail record built with original_value leaks neither" do
      view = ResolvedView.resolve(SecureLeasesUI)

      record = %{
        lease_record()
        | rate: forbidden(:rate, :attribute, "SECRET-4711"),
          client: forbidden(:client, :relationship, "SECRET-4711")
      }

      values = wire(ResolvedView.record_values(view, record, [:name, :rate, :note, :client_name]))

      assert values["rate"] == @masked_text
      assert values["client_name"] == @masked_text
      assert values["_masked"] == %{"rate" => @reason, "client_name" => @reason}
      refute Jason.encode!(values) =~ "SECRET-4711"
    end

    test "the handler's view panel leaks neither" do
      lease = lease_record()

      assert {:ok, messages} =
               ActionHandler.handle(
                 SecureLeasesUI,
                 envelope("view_record", %{"recordId" => lease.id}),
                 actor: @viewer
               )

      encoded = wire(messages) |> Jason.encode!()
      refute encoded =~ "424242"
      refute encoded =~ "ForbiddenField"
      assert encoded =~ @masked_text
    end
  end

  # --- detail card ------------------------------------------------------------

  describe "a forbidden field on a :detail card" do
    test "the initial render draws masked, the badge tone stays neutral" do
      lease = lease_record()

      surface =
        Info.build_surface(SecureLeasesUI,
          actor: @viewer,
          context_state: %{"lease" => %{"search" => "", "value" => lease.id, "label" => "Loft"}}
        )

      detail = Surface.data_model(surface)["detail"]["lease"]

      assert detail["rate"] == @masked_text
      assert detail["_masked"] == %{"rate" => @reason}
      assert detail["_badge_rate"] == @masked_text
      assert detail["_badge_tone_rate"] == "neutral"
      assert detail["note"] == nil
      refute Map.has_key?(detail["_masked"], "note")
      refute Jason.encode!(surface) =~ "424242"

      admin_surface =
        Info.build_surface(SecureLeasesUI,
          actor: @admin,
          context_state: %{"lease" => %{"search" => "", "value" => lease.id, "label" => "Loft"}}
        )

      admin_detail = Surface.data_model(admin_surface)["detail"]["lease"]
      assert admin_detail["rate"] == @rate
      refute Map.has_key?(admin_detail, "_masked")
    end

    test "the detail refresh through the handler draws masked" do
      lease = lease_record()

      assert {:ok, messages} =
               ActionHandler.handle(
                 SecureLeasesUI,
                 envelope("context_select", %{"context" => "lease", "value" => lease.id}),
                 actor: @viewer
               )

      detail = value_at(messages, "/detail/lease")
      assert detail["rate"] == @masked_text
      assert detail["_masked"] == %{"rate" => @reason}
      refute Jason.encode!(messages) =~ "424242"
    end
  end

  # --- view panel and form ----------------------------------------------------

  describe "the view panel and the form buffer" do
    test "view_record populates the panel masked, never the form" do
      lease = lease_record()

      assert {:ok, messages} =
               ActionHandler.handle(
                 SecureLeasesUI,
                 envelope("view_record", %{"recordId" => lease.id}),
                 actor: @viewer
               )

      panel = value_at(messages, "/ui/panel/record")
      assert panel["rate"] == @masked_text
      assert panel["_masked"] == %{"rate" => @reason}
      assert panel["note"] == nil

      # the edit buffer is never written in view mode
      refute value_at(messages, "/form")
    end

    test "start_edit holds null for the forbidden field, with no masked entry" do
      lease = lease_record()

      assert {:ok, messages} =
               ActionHandler.handle(
                 SecureLeasesUI,
                 envelope("start_edit", %{"recordId" => lease.id}),
                 actor: @viewer
               )

      form = value_at(messages, "/form")
      assert form["rate"] == nil
      assert form["name"] == "Loft"
      refute Map.has_key?(form, "_masked")
      refute Jason.encode!(form) =~ @masked_text
      refute Jason.encode!(form) =~ "424242"
    end
  end

  # --- NotLoaded, unknown fields, CSV -----------------------------------------

  describe "values that are not forbidden are unchanged" do
    test "an unloaded field serializes null with no _masked entry" do
      view = ResolvedView.resolve(SecureLeasesUI)

      # read as the viewer, so :rate arrives forbidden
      [viewer_record] = Ash.read!(SecureLease, actor: @viewer)
      record = Map.put(viewer_record, :note, %Ash.NotLoaded{field: :note, type: :attribute})

      values = wire(ResolvedView.record_values(view, record, [:name, :note, :rate]))

      assert values["note"] == nil
      assert values["rate"] == @masked_text
      assert values["_masked"] == %{"rate" => @reason}
    end

    test "an unknown field name behaves as before" do
      view = ResolvedView.resolve(SecureLeasesUI)
      values = wire(ResolvedView.record_values(view, lease_record(), [:bogus_field]))

      assert values["bogus_field"] == nil
      refute Map.has_key?(values, "_masked")
    end

    test "a nil the reader may see serializes null with no _masked entry" do
      view = ResolvedView.resolve(SecureLeasesUI)
      values = wire(ResolvedView.record_values(view, lease_record(), [:note]))

      assert values["note"] == nil
      refute Map.has_key?(values, "_masked")
    end

    test "a CSV export of a forbidden column is still an empty cell" do
      Ash.create!(
        AshA2ui.Test.ExportContract,
        %{name: "Acme", value: "1200.50", currency: "CAD", status: :active, margin: "9"},
        authorize?: false
      )

      {:ok, messages} =
        ActionHandler.handle(
          AshA2ui.Test.ExportContractsUI,
          Messages.call("export", "export_contracts", %{}),
          actor: @viewer
        )

      assert %{"dataUrl" => url} =
               Enum.find_value(messages, fn
                 %{
                   "callRendererFunction" => %{
                     "callFunction" => %{"@call" => "downloadFile"} = call
                   }
                 } ->
                   call["args"]

                 _ ->
                   nil
               end)

      csv = url |> String.split(",") |> List.last() |> Base.decode64!()
      assert csv =~ "\r\nAcme,1200.50,active,CAD,Acme (CAD),0,\r\n"
      refute csv =~ @masked_text
    end
  end

  # --- diagram markers --------------------------------------------------------

  describe "a diagram marker with a forbidden label" do
    test "renders the masked text with initials ?; a masked node label keeps the label's initials" do
      view = ResolvedView.resolve(AshA2ui.Test.MaskedDiagramUI)
      [diagram] = view.diagrams

      loaded = AshA2ui.Diagram.load(diagram, view, %{}, actor: @viewer)

      markers =
        loaded.state["markers"]
        |> Map.values()
        |> List.flatten()

      assert [%{"label" => @masked_text, "initials" => "?"} = masked, plain, node_masked] =
               Enum.sort_by(markers, & &1["id"])

      assert masked["nodeLabel"] == @masked_text
      assert plain["label"] == "Second"
      assert plain["initials"] == "S"
      assert node_masked["label"] == "Third"
      assert node_masked["initials"] == "T"
      assert node_masked["nodeLabel"] == @masked_text

      messages = AshA2ui.Diagram.refresh_messages(AshA2ui.Test.MaskedDiagramUI)
      encoded = wire(messages) |> Jason.encode!()
      assert encoded =~ @masked_text
      refute encoded =~ "SECRET-4711"
    end
  end

  # --- canvas record labels ---------------------------------------------------

  describe "the canvas default record label of a forbidden name" do
    test "is the masked text, never the hidden value" do
      thing = Ash.create!(MaskedCanvas.Test.Thing, %{name: "SECRET-4711"}, authorize?: false)

      ref = "record:leases.thing:" <> ObjectRef.encode_pk(thing.id)

      {:ok, object} =
        AshA2ui.Canvas.resolve(ref, registry: MaskedCanvas.Test.Registry, actor: @viewer)

      assert object.label == @masked_text
      refute inspect(object, limit: :infinity) =~ "SECRET-4711"
    end
  end

  # --- admin catalog emission -------------------------------------------------

  describe "the masked binding emission" do
    test "fieldDisplay and dataGrid columns bind the reason for policy-covered fields" do
      [%{"createSurface" => %{"components" => components}}] =
        Info.build_surface(SecureLeasesUI, actor: @admin)

      by_id = Surface.components_by_id(components)

      # the view panel's field displays bind /ui/panel/record/_masked/<field>
      assert by_id["field_display_rate"]["masked"] == %{
               "@path" => "/ui/panel/record/_masked/rate"
             }

      assert by_id["field_display_name"]["masked"] == %{
               "@path" => "/ui/panel/record/_masked/name"
             }

      # the detail card's field displays bind /detail/<context>/_masked/<field>
      assert by_id["detail_card_field_rate"]["masked"] == %{
               "@path" => "/detail/lease/_masked/rate"
             }

      # the dataGrid columns bind row-relatively, source fields included
      grid = Enum.find(components, &(&1["component"] == "dataGrid"))
      paths = Map.new(grid["columns"], fn column -> {column["path"], column["masked"]} end)

      assert paths["rate"] == %{"path" => "_masked/rate"}
      assert paths["client_credit"] == %{"path" => "_masked/client_credit"}
      assert paths["client_name"] == %{"path" => "_masked/client_name"}
      assert paths["name"] == %{"path" => "_masked/name"}
    end

    test "a surface over a resource without field policies emits no masked binding" do
      [%{"createSurface" => %{"components" => components}}] =
        Info.build_surface(AshA2ui.Test.MinimalUI, actor: nil)

      refute Enum.any?(components, &Map.has_key?(&1, "masked"))

      grid = Enum.find(components, &(&1["component"] == "dataGrid"))
      refute Enum.any?(grid["columns"], &Map.has_key?(&1, "masked"))
    end
  end

  # --- helpers ----------------------------------------------------------------

  defp lease_record do
    [lease] = Ash.read!(SecureLease, actor: @admin)
    Ash.load!(lease, :client, actor: @admin)
  end
end
