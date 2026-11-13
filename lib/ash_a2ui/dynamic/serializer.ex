defmodule AshA2ui.Dynamic.Serializer do
  @moduledoc """
  The canonical serialized form of a `AshA2ui.Dynamic` surface spec — the
  storage format of the spec-as-artifact lifecycle.

  A serialized spec is a JSON envelope:

      {"spec": { ...the spec... }, "spec_format": 1}

  with **every object's keys sorted** at every nesting level (array order is
  preserved — it is meaningful: field order, component order). Canonical form
  makes serialization deterministic: two semantically identical specs
  serialize byte-identically, so fingerprints, database uniqueness, and
  version-control diffs of stored specs are all stable.

  `spec_format` versions the *envelope and spec vocabulary*, independent of
  the A2UI protocol version. Readers reject formats they don't know with a
  structured error instead of misinterpreting them.

  Use through `AshA2ui.Dynamic.serialize/1` / `deserialize/2` /
  `fingerprint/1` — deserializing through `AshA2ui.Dynamic` re-validates the
  stored spec against the **current** resource state, which is what makes
  stored specs safe to load after the schema has moved on.
  """

  alias AshA2ui.Dynamic.Error

  @spec_format 1

  @doc """
  The current spec-format version written by `serialize/1`.
  """
  @spec spec_format() :: pos_integer
  def spec_format, do: @spec_format

  @doc """
  Serializes a spec map to its canonical, versioned JSON form.
  """
  @spec serialize(map) :: String.t()
  def serialize(spec) when is_map(spec) do
    [{"spec", canonical(spec)}, {"spec_format", @spec_format}]
    |> Jason.OrderedObject.new()
    |> Jason.encode!()
  end

  @doc """
  A stable content fingerprint of a spec: the SHA-256 of its canonical
  serialization, as `"sha256:<hex>"`. Key order of the input never matters.
  """
  @spec fingerprint(map) :: String.t()
  def fingerprint(spec) when is_map(spec) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, serialize(spec)), case: :lower)
  end

  @doc """
  Parses a serialized spec back to its spec map. Returns structured errors
  for malformed JSON, envelopes without the expected shape, and spec formats
  this version does not know.

  Parsing performs **no** resource validation — that is
  `AshA2ui.Dynamic.deserialize/2`'s job (via `AshA2ui.Dynamic.resolve/2`).
  """
  @spec deserialize(String.t()) :: {:ok, map} | {:error, [Error.t()]}
  def deserialize(serialized) when is_binary(serialized) do
    case Jason.decode(serialized) do
      {:ok, %{"spec_format" => @spec_format, "spec" => spec}} ->
        {:ok, spec}

      {:ok, %{"spec_format" => format}} ->
        {:error,
         [
           Error.new(
             "spec_format",
             "spec format #{inspect(format)} is not supported — " <>
               "this version reads spec_format #{@spec_format}"
           )
         ]}

      {:ok, _other} ->
        {:error,
         [
           Error.new(
             "",
             ~s(a serialized spec must be a JSON object with "spec_format" and "spec" keys)
           )
         ]}

      {:error, %Jason.DecodeError{} = error} ->
        {:error,
         [Error.new("", "the serialized spec is not valid JSON: #{Exception.message(error)}")]}
    end
  end

  @doc """
  The canonical in-memory form of a spec value: string keys, objects sorted
  by key at every level (as `Jason.OrderedObject`), array order preserved.
  """
  @spec canonical(term) :: term
  def canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  def canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  def canonical(other), do: other
end
