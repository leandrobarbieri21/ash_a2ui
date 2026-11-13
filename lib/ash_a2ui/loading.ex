defmodule AshA2ui.Loading do
  @moduledoc """
  The reserved `/ui/loading` flag: a surface's data is being fetched.

  A surface's records usually ride in its first batch, so the bootstrap
  skeleton covers the wait. Some data arrives afterwards: a host that runs a
  `:report` component's rows on arrival (off the LiveView process, so the
  filters can paint first) leaves the table empty until the rows land, and an
  empty table is indistinguishable from "no rows". The flag tells a renderer
  which of the two it is looking at.

      # when the fetch starts, and when its messages are about to be pushed
      push_event(socket, "a2ui:messages", %{messages: AshA2ui.Loading.messages(ui, true)})
      push_event(socket, "a2ui:messages", %{messages: AshA2ui.Loading.messages(ui, false)})

  The flag is a plain boolean at `/ui/loading`, so a client can bind or subscribe
  to it like any other path; a renderer reads a missing value as `false`. A
  surface with a `:report` component also carries `/ui/loading_visible`, the same
  fact as a zero-or-one list (`[%{"id" => "on"}]` while loading, `[]` otherwise)
  that the report's loading row is templated over, as the pagination sentinels
  are; `messages/3` writes both.
  The shipped hook sets both itself while a `query` or `report` call it sent
  is unanswered (see the zero-jank rules).
  """

  alias AshA2ui.ResolvedView

  @path "/ui/loading"
  @visible_path "/ui/loading_visible"

  @doc "The data-model path of the flag."
  @spec path() :: String.t()
  def path, do: @path

  @doc """
  The `updateDataModel` messages that set the flag on `ui` (a surface module,
  or an already resolved `AshA2ui.ResolvedView`).

  Options: `:actor` and `:tenant`, forwarded when `ui` has to be resolved.
  """
  @spec messages(module() | ResolvedView.t(), boolean(), keyword()) :: [map()]
  def messages(ui, loading?, opts \\ [])

  def messages(%ResolvedView{} = view, loading?, _opts) when is_boolean(loading?) do
    for {path, value} <- [
          {@path, loading?},
          {@visible_path, if(loading?, do: [%{"id" => "on"}], else: [])}
        ] do
      %{
        "version" => "1.0",
        "updateDataModel" => %{"surfaceId" => view.surface_id, "path" => path, "value" => value}
      }
    end
  end

  def messages(ui, loading?, opts) when is_atom(ui) and is_boolean(loading?) do
    ui
    |> ResolvedView.resolve(Keyword.take(opts, [:actor, :tenant]))
    |> messages(loading?, opts)
  end
end
