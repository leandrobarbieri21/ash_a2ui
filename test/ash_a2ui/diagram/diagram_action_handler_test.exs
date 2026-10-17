defmodule AshA2ui.Diagram.DiagramActionHandlerTest do
  @moduledoc """
  A diagram marker's link through `AshA2ui.ActionHandler` (A2UI-108): an
  `"open_surface"` naming a diagram is accepted only for a surface the
  diagram's own markers link to, re-read as the actor; anything else is
  refused. The client never supplies the link.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Diagram.{FlowUI, Visit}

  setup do
    on_exit(fn -> Application.delete_env(:ash_a2ui, :link_resolver) end)
    :ok
  end

  defp envelope(context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "open_surface",
        "surfaceId" => "visit_flow",
        "sourceComponentId" => "diagram_flow_marker_label_link",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp feedback(messages) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value}} -> value
      _other -> nil
    end)
  end

  defp open(context, actor) do
    ActionHandler.handle(FlowUI, envelope(context), actor: actor, authorize?: false)
  end

  @tag ac: "A2UI-108/AC-6"
  test "a marker opens only the surfaces its diagram links to" do
    visit = Ash.create!(Visit, %{patient: "Ada Lovelace", node: "triage"}, authorize?: false)
    red = %{team: "red"}

    assert {:ok, []} =
             open(%{"diagram" => "flow", "surface" => "visit", "recordId" => visit.id}, red)

    # A surface no marker links to is refused, whatever the client sends.
    assert {:error, messages} =
             open(%{"diagram" => "flow", "surface" => "admin", "recordId" => visit.id}, red)

    assert feedback(messages)["kind"] == "error"
    assert feedback(messages)["message"] =~ ~s(Diagram "flow" does not link to "admin")

    # An unknown diagram links nowhere.
    assert {:error, _messages} =
             open(%{"diagram" => "nope", "surface" => "visit", "recordId" => visit.id}, red)

    # An actor whose markers carry no link (none readable) cannot open it.
    assert {:error, _messages} =
             open(%{"diagram" => "flow", "surface" => "visit", "recordId" => visit.id}, %{
               team: "blue"
             })

    # A vetoed link is not openable either.
    Application.put_env(:ash_a2ui, :link_resolver, AshA2ui.Test.Diagram.VetoResolver)
    Ash.create!(Visit, %{patient: "Bea Blue", node: "exam", team: "blue"}, authorize?: false)

    assert {:error, _messages} =
             open(%{"diagram" => "flow", "surface" => "visit"}, %{team: "blue"})

    # A marker without a link binds no surface: acknowledged, nothing opens.
    assert {:ok, []} = open(%{"diagram" => "flow", "surface" => ""}, red)

    # A non-string surface is malformed.
    assert {:error, messages} = open(%{"diagram" => "flow", "surface" => 7}, red)
    assert feedback(messages)["message"] =~ "Malformed open_surface action"
  end
end
