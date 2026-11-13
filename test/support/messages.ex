defmodule AshA2ui.Test.Messages do
  @moduledoc """
  Builds the A2UI 1.0 renderer-to-agent messages `AshA2ui.ActionHandler`
  consumes, and reads the function-call answer out of its follow-ups.

  `call/4` is what the shipped renderer sends for every server-handled
  control (an `ashAction` function call); `action/4` builds a plain
  `action` event, which the handler refuses.
  """

  @timestamp "2026-11-12T12:00:00Z"

  @doc "A plain `action` event (spec-valid; `AshA2ui.ActionHandler` refuses it)."
  def action(name, surface_id, context, opts \\ []) do
    %{
      "version" => "1.0",
      "action" => %{
        "name" => name,
        "surfaceId" => surface_id,
        "sourceComponentId" => Keyword.get(opts, :source, "test_component"),
        "timestamp" => @timestamp,
        "context" => context
      }
    }
  end

  @doc """
  A `callAgentFunction` calling the ash_a2ui catalog's `ashAction`. `:id`
  sets the `functionCallId` (default: a fresh one).
  """
  def call(name, surface_id, context, opts \\ []) do
    %{
      "version" => "1.0",
      "callAgentFunction" => %{
        "surfaceId" => surface_id,
        "functionCallId" => Keyword.get_lazy(opts, :id, &call_id/0),
        "callFunction" => %{
          "@call" => "ashAction",
          "catalogId" => AshA2ui.Encoder.ash_catalog_id(),
          "args" => %{
            "name" => name,
            "sourceComponentId" => Keyword.get(opts, :source, "test_component"),
            "context" => context
          }
        }
      }
    }
  end

  @doc "A fresh `functionCallId`."
  def call_id, do: "call_#{System.unique_integer([:positive])}"

  @doc "The `agentFunctionResponse` body of a follow-up list, or nil."
  def response(messages) do
    Enum.find_value(messages, fn
      %{"agentFunctionResponse" => response} -> response
      _other -> nil
    end)
  end

  @doc "The `/ui/feedback` map the last feedback write of a follow-up list sets."
  def feedback(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value}} -> value
      _other -> nil
    end)
  end

  @doc "The catalogs a payload that calls ash_a2ui functions validates against."
  def catalogs, do: ["catalogs/basic/v1/catalog.json", "catalogs/ash_a2ui/catalog.json"]
end
