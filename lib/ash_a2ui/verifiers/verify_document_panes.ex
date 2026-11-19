defmodule AshA2ui.Verifiers.VerifyDocumentPanes do
  @moduledoc """
  Verifies at compile time that `document_pane` entities (see
  `AshA2ui.DocumentPane`) are sound:

    * a surface declares at most one pane (the pane holds the surface's
      sections beside its document),
    * the pane's name is a lowercase identifier (`[a-z][a-z0-9_]*`: it
      appears in data-model paths and component ids), and so is its
      `url_param` (`[a-z][a-z0-9_-]*`),
    * its `context` is a declared context that at least one `:detail`
      component renders (the pane is bound to those cards), and
    * its `source` and `regions` name public attributes, calculations or
      aggregates of the context's resource.

  The resource checks are skipped when the context's resource cannot be
  loaded at verification time (cross-module compile ordering), matching the
  other verifiers.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @name ~r/^[a-z][a-z0-9_]*$/
  @param ~r/^[a-z][a-z0-9_-]*$/

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:a2ui])
    panes = Enum.filter(entities, &is_struct(&1, AshA2ui.DocumentPane))

    case panes do
      [_first, second | _rest] ->
        error(
          module,
          second,
          "a surface has at most one document pane: it holds the surface's sections"
        )

      panes ->
        Enum.find_value(panes, :ok, &pane_error(&1, entities, module))
    end
  end

  defp pane_error(pane, entities, module) do
    context =
      Enum.find(entities, &match?(%AshA2ui.Context{name: name} when name == pane.context, &1))

    cond do
      not Regex.match?(@name, Atom.to_string(pane.name)) ->
        error(module, pane, "the name must be a lowercase identifier ([a-z][a-z0-9_]*)")

      not Regex.match?(@param, AshA2ui.DocumentPane.url_param(pane)) ->
        error(module, pane, "url_param must be a lowercase identifier ([a-z][a-z0-9_-]*)")

      is_nil(context) ->
        error(module, pane, "context #{inspect(pane.context)} is not a declared context")

      not Enum.any?(
        entities,
        &match?(%AshA2ui.Component{name: :detail, context: c} when c == pane.context, &1)
      ) ->
        error(
          module,
          pane,
          "no :detail component renders context #{inspect(pane.context)}: a document pane " <>
            "is bound to the detail cards of its context"
        )

      true ->
        field_error(pane, context.resource, module)
    end
  end

  defp field_error(pane, resource, module) do
    if resource && Code.ensure_loaded?(resource) && Info.resource?(resource) do
      known = known_field_names(resource)

      Enum.find_value(
        [:source, :regions],
        &unknown_field_error(pane, &1, known, resource, module)
      )
    end
  end

  defp unknown_field_error(pane, option, known, resource, module) do
    name = Map.get(pane, option)

    if name && not MapSet.member?(known, name) do
      error(
        module,
        pane,
        "#{option} names #{inspect(name)}, which is not a public attribute, calculation " <>
          "or aggregate of #{inspect(resource)}"
      )
    end
  end

  defp known_field_names(resource) do
    [
      Info.public_attributes(resource),
      Info.public_calculations(resource),
      Info.public_aggregates(resource)
    ]
    |> Enum.concat()
    |> MapSet.new(& &1.name)
  end

  defp error(module, pane, message) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :document_pane, pane.name],
       message: "document_pane #{inspect(pane.name)}: " <> message
     )}
  end
end
