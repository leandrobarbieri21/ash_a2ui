defmodule AshA2ui.Dynamic.Error do
  @moduledoc """
  A structured, LLM-legible validation error for an agent-composed surface
  spec (see `AshA2ui.Dynamic`).

  * `path` — where in the spec the problem is, as a dotted string. Parse
    errors use JSON positions (`"components[0].row_actions"`); verifier
    errors use the DSL path the compile-time diagnostics use
    (`"a2ui.component.table.fields"`).
  * `message` — the same explanation the compile-time verifier would print,
    listing what is available where that helps self-correction.

  Messages are English in every locale: they are written for agents and
  developers, never shown to a reader, and are not translated.

  The struct is JSON-encodable (`Jason.Encoder` over `path` + `message`), so
  hosts can feed the error list straight back to an LLM tool loop.
  """

  @derive {Jason.Encoder, only: [:path, :message]}
  defstruct [:path, :message]

  @type t :: %__MODULE__{path: String.t(), message: String.t()}

  @doc """
  Builds an error from a spec path and message.
  """
  @spec new(String.t() | [term], String.t()) :: t()
  def new(path, message) when is_binary(path), do: %__MODULE__{path: path, message: message}

  def new(path, message) when is_list(path) do
    %__MODULE__{path: Enum.map_join(path, ".", &to_string/1), message: message}
  end

  @doc """
  Converts a `Spark.Error.DslError` raised/returned by the shared verifiers
  into a `#{inspect(__MODULE__)}` (dropping the synthetic module, keeping the
  DSL path and the byte-identical compile-time message).
  """
  @spec from_dsl_error(Spark.Error.DslError.t()) :: t()
  def from_dsl_error(%Spark.Error.DslError{path: path, message: message}) do
    new(path || [], String.trim_trailing(to_string(message)))
  end

  @doc """
  One `"path: message"` line per error — the plain-text rendering hosts can
  return as an LLM tool error result.
  """
  @spec messages([t()]) :: [String.t()]
  def messages(errors) do
    Enum.map(errors, fn %__MODULE__{path: path, message: message} ->
      case path do
        "" -> message
        path -> "#{path}: #{message}"
      end
    end)
  end
end
