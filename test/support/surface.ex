defmodule AshA2ui.Test.Surface do
  @moduledoc """
  Reads the parts of an encoded A2UI 1.0 surface in tests.

  A surface is one inline `createSurface` message (a list of one, as
  `AshA2ui.Info.build_surface/2` returns it, or the message itself). A
  data-only refresh is one `updateDataModel` message.
  """

  @doc "The `createSurface` payload of a message, or of the one in a message list."
  def create(%{"createSurface" => create}), do: create

  def create(messages) when is_list(messages),
    do: Enum.find_value(messages, &(is_map(&1) and &1["createSurface"]))

  @doc """
  The component list of a surface, or of an `updateComponents` message (a
  handler's re-render).
  """
  def components(%{"updateComponents" => %{"components" => components}}), do: components
  def components(surface), do: create(surface)["components"]

  @doc "The components of a surface (or a component list) keyed by id."
  def components_by_id([%{"component" => _} | _] = components),
    do: Map.new(components, &{&1["id"], &1})

  def components_by_id(surface), do: surface |> components() |> components_by_id()

  @doc "The data model of a surface, or the value of an `updateDataModel`."
  def data_model(%{"updateDataModel" => %{"value" => value}}), do: value
  def data_model(surface), do: create(surface)["dataModel"]

  @doc """
  The `ashAction` call of a component's action (or of the action itself) as
  `%{"name" => ..., "context" => ..., "sourceComponentId" => ...}`.
  """
  def event(%{"action" => action}), do: event(action)

  def event(%{"functionCall" => %{"@call" => "ashAction", "args" => args}}), do: args

  @doc """
  A basic component as a basic surface emits it: without the `@catalogId`
  an admin surface puts on it, and without the basic `catalogId` it adds to
  the function calls inside it.
  """
  def unqualified(%{} = map) do
    basic = AshA2ui.Encoder.basic_catalog_id()

    map
    |> Map.delete("@catalogId")
    |> then(&if(&1["catalogId"] == basic, do: Map.delete(&1, "catalogId"), else: &1))
    |> Map.new(fn {key, value} -> {key, unqualified(value)} end)
  end

  def unqualified(list) when is_list(list), do: Enum.map(list, &unqualified/1)
  def unqualified(other), do: other
end
