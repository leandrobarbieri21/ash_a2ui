defmodule AshA2ui.Diagram.DiagramEncoderTest do
  @moduledoc """
  Live-diagram payloads (A2UI-108): the basic fallback (a List of nodes with
  their markers) on v0.9.1 and v1.0, schema-validated and basic-catalog
  only; the `/diagram/<name>` state with markers keyed by node id and
  server-resolved links; the admin `liveDiagram`; and refreshes that move
  markers, as the actor.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Test.Diagram.{Flow, FlowUI, FlowV1UI, MalformedUI, Visit}

  setup do
    on_exit(fn ->
      Application.delete_env(:ash_a2ui, :catalog)
      Application.delete_env(:ash_a2ui, :open_surface_url)
      Application.delete_env(:ash_a2ui, :link_resolver)
    end)

    :ok
  end

  defp visit!(patient, node, status, team \\ "red") do
    Ash.create!(Visit, %{patient: patient, node: node, status: status, team: team},
      authorize?: false
    )
  end

  defp components_by_id(components), do: Map.new(components, &{&1["id"], &1})

  defp parts(ui, opts) do
    messages = AshA2ui.Info.build_surface(ui, [authorize?: false] ++ opts)
    Enum.each(messages, &assert_valid_server_message/1)

    components =
      messages |> Enum.find_value(& &1["updateComponents"]) |> Map.fetch!("components")

    value =
      Enum.find_value(messages, fn
        %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
        _other -> nil
      end)

    {components_by_id(components), value}
  end

  defp labels(markers), do: Enum.map(markers, & &1["label"])

  @tag ac: "A2UI-108/AC-3"
  test "encodes the basic fallback for both versions" do
    ada = visit!("Ada Lovelace", "triage", :waiting)
    visit!("Alan Turing", "triage", :active)
    visit!("Grace Hopper", "exam", :executing)

    Application.put_env(:ash_a2ui, :open_surface_url, "/s/{surface}/{recordId}")

    # --- v0.9.1 ---
    {components, value} = parts(FlowUI, [])

    # Diagrams sit after the context pickers, before the tables.
    assert components["root"]["children"] == [
             "status_text",
             "diagram_flow",
             "table_heading",
             "records_list",
             "empty_state",
             "action_result_panel"
           ]

    assert components["diagram_flow"]["children"] == [
             "diagram_flow_heading",
             "diagram_flow_description",
             "diagram_flow_error",
             "diagram_flow_nodes"
           ]

    assert components["diagram_flow_heading"]["text"] == "Visits in flight"

    assert components["diagram_flow_nodes"]["children"] == %{
             "componentId" => "diagram_flow_node",
             "path" => "/diagram/flow/nodes"
           }

    assert components["diagram_flow_node_markers"]["children"] == %{
             "componentId" => "diagram_flow_marker",
             "path" => "markers"
           }

    assert components["diagram_flow_marker"]["children"] == [
             "diagram_flow_marker_initials",
             "diagram_flow_marker_label",
             "diagram_flow_marker_status"
           ]

    # Without link_buttons the label stays plain Text.
    refute Map.has_key?(components, "diagram_flow_marker_label_link")

    # The state: markers keyed by node id, nodes in first-seen order.
    diagram = value["diagram"]["flow"]
    assert diagram["error"] == ""
    assert Map.keys(diagram["markers"]) |> Enum.sort() == ["exam", "triage"]
    assert labels(diagram["markers"]["triage"]) == ["Ada Lovelace", "Alan Turing"]

    [first | _] = diagram["markers"]["triage"]

    assert first == %{
             "id" => ada.id,
             "nodeId" => "triage",
             "nodeLabel" => "Triage",
             "label" => "Ada Lovelace",
             "initials" => "AL",
             "status" => "waiting",
             "statusLabel" => "Waiting",
             "tone" => "warning",
             "link" => %{
               "surface" => "visit",
               "recordId" => ada.id,
               "label" => "Ada Lovelace",
               "href" => "/s/visit/#{ada.id}"
             }
           }

    # Nodes in the order their first marker appears (the source sorts by
    # patient: Ada and Alan at triage, then Grace at the exam).
    assert Enum.map(diagram["nodes"], &Map.take(&1, ["id", "label", "count"])) == [
             %{"id" => "triage", "label" => "Triage", "count" => 2},
             %{"id" => "exam", "label" => "Exam", "count" => 1}
           ]

    assert hd(diagram["markers"]["exam"])["tone"] == "accent"

    # --- v1.0 (an MFA source, and a source that fails) ---
    assert [message] = AshA2ui.Info.build_surface(FlowV1UI, authorize?: false)
    assert_valid_server_message(message, :v1_0)

    create = message["createSurface"]
    v1 = components_by_id(create["components"])

    assert "diagram_flow" in v1["root"]["children"]
    assert "diagram_offline" in v1["root"]["children"]
    assert v1["diagram_flow_heading"]["text"] =~ "Flow"

    assert labels(create["dataModel"]["diagram"]["flow"]["markers"]["triage"]) == [
             "Ada Lovelace",
             "Alan Turing"
           ]

    assert create["dataModel"]["diagram"]["offline"] == %{
             "markers" => %{},
             "nodes" => [],
             "error" => "This diagram is unavailable."
           }
  end

  @tag ac: "A2UI-108/AC-8"
  test "the fallback is basic catalog only" do
    visit!("Ada Lovelace", "triage", :waiting)

    {components, _value} = parts(FlowUI, link_buttons: true)

    basic =
      "priv/a2ui/v0_9_1/catalogs/basic/catalog.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("components")
      |> Map.keys()
      |> MapSet.new()

    kinds = components |> Map.values() |> MapSet.new(& &1["component"])

    assert MapSet.subset?(kinds, basic),
           "non-basic kinds: #{inspect(MapSet.difference(kinds, basic))}"

    # With link_buttons the marker label is a link Button carrying the
    # diagram's name and the marker's bound (server-resolved) link.
    assert "diagram_flow_marker_label_link" in components["diagram_flow_marker"]["children"]

    assert components["diagram_flow_marker_label_link"] == %{
             "id" => "diagram_flow_marker_label_link",
             "component" => "Button",
             "variant" => "borderless",
             "child" => "diagram_flow_marker_label",
             "action" => %{
               "event" => %{
                 "name" => "open_surface",
                 "context" => %{
                   "diagram" => "flow",
                   "surface" => %{"path" => "link/surface"},
                   "recordId" => %{"path" => "link/recordId"}
                 }
               }
             }
           }
  end

  @tag ac: "A2UI-108/AC-4"
  test "encodes the admin live diagram" do
    visit!("Ada Lovelace", "triage", :waiting)
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    messages = AshA2ui.Info.build_surface(FlowUI, authorize?: false)

    by_id =
      messages
      |> Enum.find_value(& &1["updateComponents"])
      |> Map.fetch!("components")
      |> components_by_id()

    assert by_id["root"]["component"] == "entityPage"
    assert "diagram_flow" in by_id["root"]["children"]

    assert by_id["diagram_flow"] == %{
             "id" => "diagram_flow",
             "component" => "liveDiagram",
             "label" => "Visits in flight",
             "description" => "Where every visit is right now.",
             "source" => Flow.source(),
             "markers" => %{"path" => "/diagram/flow/markers"},
             "nodes" => %{"path" => "/diagram/flow/nodes"},
             "error" => %{"path" => "/diagram/flow/error"}
           }

    # No basic fallback components under the admin catalog.
    refute Map.has_key?(by_id, "diagram_flow_nodes")

    catalog = "priv/a2ui/admin_v1/catalog.json" |> File.read!() |> Jason.decode!()

    schema =
      catalog["components"]["liveDiagram"]
      |> Map.put("$defs", catalog["$defs"] || %{})
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, by_id["diagram_flow"]) == :ok
  end

  @tag ac: "A2UI-108/AC-5"
  test "refreshes move markers, as the actor" do
    ada = visit!("Ada Lovelace", "triage", :waiting)
    visit!("Bea Blue", "exam", :active, "blue")

    red = %{team: "red"}
    blue = %{team: "blue"}

    {_components, value} = parts(FlowUI, actor: red)
    assert Map.keys(value["diagram"]["flow"]["markers"]) == ["triage"]

    # The host's state changes (the engine moved the token)...
    Ash.update!(ada, %{node: "exam", status: :executing}, authorize?: false)

    # ...and a full data-model refresh (what a PubSub-driven LiveRenderer
    # refresh pushes) carries the moved marker.
    refresh = AshA2ui.Info.build_data_model(FlowUI, actor: red, authorize?: false)
    assert_valid_server_message(refresh)
    markers = refresh["updateDataModel"]["value"]["diagram"]["flow"]["markers"]
    assert Map.keys(markers) == ["exam"]
    assert hd(markers["exam"])["status"] == "executing"

    # refresh_messages/2 writes just /diagram/<name>.
    assert [message] = AshA2ui.Diagram.refresh_messages(FlowUI, actor: red)
    assert_valid_server_message(message)
    assert message["updateDataModel"]["path"] == "/diagram/flow"
    assert labels(message["updateDataModel"]["value"]["markers"]["exam"]) == ["Ada Lovelace"]

    # Another actor sees only their own markers.
    assert [blue_message] = AshA2ui.Diagram.refresh_messages(FlowUI, actor: blue)
    assert labels(blue_message["updateDataModel"]["value"]["markers"]["exam"]) == ["Bea Blue"]

    # v1.0 surfaces get v1.0 writes.
    assert [v1_flow, v1_offline] = AshA2ui.Diagram.refresh_messages(FlowV1UI, actor: red)
    assert_valid_server_message(v1_flow, :v1_0)
    assert v1_flow["version"] == "v1.0"
    assert v1_offline["updateDataModel"]["value"]["error"] == "This diagram is unavailable."
  end

  @tag ac: "A2UI-108/AC-7"
  test "links are resolved on the server and may be vetoed" do
    visit!("Bea Blue", "exam", :active, "blue")
    visit!("Ada Lovelace", "triage", :waiting)
    Application.put_env(:ash_a2ui, :link_resolver, AshA2ui.Test.Diagram.VetoResolver)

    [red] = AshA2ui.Diagram.refresh_messages(FlowUI, actor: %{team: "red"})
    assert hd(red["updateDataModel"]["value"]["markers"]["triage"])["link"]["surface"] == "visit"

    # The resolver vetoes every link for the blue team: markers stay, links go.
    [blue] = AshA2ui.Diagram.refresh_messages(FlowUI, actor: %{team: "blue"})
    marker = hd(blue["updateDataModel"]["value"]["markers"]["exam"])
    assert marker["label"] == "Bea Blue"
    refute Map.has_key?(marker, "link")
  end

  test "a malformed marker is a source bug" do
    assert_raise ArgumentError, ~r/marker status must be one of/, fn ->
      AshA2ui.Info.build_surface(MalformedUI, authorize?: false)
    end
  end

  test "initials" do
    assert AshA2ui.Diagram.initials("Ada Lovelace") == "AL"
    assert AshA2ui.Diagram.initials("Grace Brewster Hopper") == "GB"
    assert AshA2ui.Diagram.initials("élodie") == "É"
    assert AshA2ui.Diagram.initials("  ") == "?"
  end
end
