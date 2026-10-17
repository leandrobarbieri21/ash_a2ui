defmodule AshA2ui.Verifiers.VerifyDiagrams do
  @moduledoc """
  Verifies at compile time that `diagram` entities (see `AshA2ui.Diagram`)
  are sound:

    * diagram names are unique and are lowercase identifiers
      (`[a-z][a-z0-9_]*`: they appear in the `/diagram/<name>` path and in
      component ids),
    * a module `source` exports `diagram/1` (the `AshA2ui.Diagram.Source`
      callback), and an `{module, function, args}` source exports
      `function` with arity `length(args) + 1`.

  Source checks are skipped when the module cannot be loaded at
  verification time (cross-module compile ordering), matching the other
  verifiers.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @name ~r/^[a-z][a-z0-9_]*$/

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    diagrams =
      dsl_state
      |> Verifier.get_entities([:a2ui])
      |> Enum.filter(&is_struct(&1, AshA2ui.Diagram))

    with :ok <- verify_unique(diagrams, module) do
      Enum.reduce_while(diagrams, :ok, fn diagram, :ok ->
        diagram |> verify_diagram(module) |> halt_on_error()
      end)
    end
  end

  defp halt_on_error(:ok), do: {:cont, :ok}
  defp halt_on_error({:error, error}), do: {:halt, {:error, error}}

  defp verify_unique(diagrams, module) do
    diagrams
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        error(module, name, "duplicate diagram #{inspect(name)}: diagram names must be unique")
    end
  end

  defp verify_diagram(diagram, module) do
    if Regex.match?(@name, Atom.to_string(diagram.name)) do
      verify_source(diagram, module)
    else
      error(
        module,
        diagram.name,
        "diagram #{inspect(diagram.name)}: the name must be a lowercase identifier " <>
          "([a-z][a-z0-9_]*)"
      )
    end
  end

  defp verify_source(%{source: {source, function, args}} = diagram, module) do
    arity = length(args) + 1

    if loadable?(source) and not function_exported?(source, function, arity) do
      error(
        module,
        diagram.name,
        "diagram #{inspect(diagram.name)}: the source #{inspect(source)}.#{function}/#{arity} " <>
          "is not exported"
      )
    else
      :ok
    end
  end

  defp verify_source(%{source: source} = diagram, module) when is_atom(source) do
    if loadable?(source) and not function_exported?(source, :diagram, 1) do
      error(
        module,
        diagram.name,
        "diagram #{inspect(diagram.name)}: the source #{inspect(source)} does not export " <>
          "diagram/1 (implement AshA2ui.Diagram.Source)"
      )
    else
      :ok
    end
  end

  defp loadable?(source), do: Code.ensure_loaded?(source)

  defp error(module, name, message) do
    {:error, DslError.exception(module: module, path: [:a2ui, :diagram, name], message: message)}
  end
end
