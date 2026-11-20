defmodule AshA2ui.Verifiers.VerifySaveBar do
  @moduledoc """
  Verifies at compile time that a `save_bar` (admin catalog 3.9) is sound:

    * its `context` is a declared context,
    * the surface has an editable `:detail` card for it to save,
    * a `:detail` card declaring `editable` has a `save_bar` to save it
      (nothing else would write its changes),
    * when the context's resource is resolvable: its `confirm`'s
      `then_action` is an update action of it, and `then_visible` a field
      of it.

  Raises `Spark.Error.DslError` on failure.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:a2ui])
    bar = Enum.find(entities, &is_struct(&1, AshA2ui.SaveBar))

    editable_details =
      Enum.filter(entities, &match?(%AshA2ui.Component{name: :detail, editable: %{}}, &1))

    contexts =
      for %AshA2ui.Context{} = context <- entities, into: %{}, do: {context.name, context}

    verify_bar(bar, editable_details, contexts, module)
  end

  defp verify_bar(nil, [], _contexts, _module), do: :ok

  defp verify_bar(nil, [detail | _], _contexts, module) do
    key = AshA2ui.Component.key(detail)

    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :editable],
       message:
         "detail #{inspect(key)} declares an editable block but the surface has no " <>
           "save_bar: its changes wait for the bar's Save"
     )}
  end

  defp verify_bar(_bar, [], _contexts, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :save_bar],
       message: "save_bar saves editable :detail cards, and the surface declares none"
     )}
  end

  defp verify_bar(bar, _details, contexts, module) do
    case Map.get(contexts, bar.context) do
      nil ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :save_bar, :context],
           message: "save_bar context #{inspect(bar.context)} is not a declared context"
         )}

      context ->
        verify_confirm(bar.confirm, context.resource, module)
    end
  end

  defp verify_confirm(nil, _resource, _module), do: :ok

  defp verify_confirm(confirm, resource, module) do
    if is_atom(resource) and Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource) do
      with :ok <- verify_then_action(confirm, resource, module) do
        verify_then_visible(confirm, resource, module)
      end
    else
      :ok
    end
  end

  defp verify_then_action(%{then_action: nil}, _resource, _module), do: :ok

  defp verify_then_action(%{then_action: action}, resource, module) do
    case ResourceInfo.action(resource, action) do
      %{type: :update} ->
        :ok

      _missing_or_not_update ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :save_bar, :confirm, :then_action],
           message:
             "save_bar confirm then_action #{inspect(action)} is not an update action of " <>
               inspect(resource)
         )}
    end
  end

  defp verify_then_visible(%{then_visible: nil}, _resource, _module), do: :ok

  defp verify_then_visible(%{then_visible: visible}, resource, module) do
    if ResourceInfo.attribute(resource, visible) || ResourceInfo.calculation(resource, visible) ||
         ResourceInfo.aggregate(resource, visible) do
      :ok
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :save_bar, :confirm, :then_visible],
         message:
           "save_bar confirm then_visible #{inspect(visible)} is not an attribute, " <>
             "calculation or aggregate of #{inspect(resource)}"
       )}
    end
  end
end
