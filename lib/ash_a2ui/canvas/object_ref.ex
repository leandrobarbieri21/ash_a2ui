defmodule AshA2ui.Canvas.ObjectRef do
  @moduledoc """
  The parsed, client-safe shape of an opaque canvas object reference.

  Client-facing refs are **strings** — `"application:<app>"`,
  `"domain:<short>"`, `"record:<domain>.<resource>:<encoded_pk>"`,
  `"resource:<domain>.<resource>"` — and nothing in them is ever converted
  to an atom or a module (`CANVAS-SEC-006`). Parsing is pure string
  splitting plus shape validation; matching those strings against the
  registry's compile-known module names is the resolver's job.

  Record primary keys travel percent-free but URL-safe:
  `Base.url_encode64(:erlang.term_to_binary(pk), padding: false)`, decoded
  with `:erlang.binary_to_term(_, [:safe])` — the `:safe` flag is what makes
  decoding refuse to create atoms from client input. Oversized or undecodable
  payloads fail closed to `{:error, :unknown_object}`.
  """

  defstruct [:id, :kind]

  @typedoc "The four object kinds the canvas knows about."
  @type kind :: :application | :domain | :resource | :record

  @type t :: %__MODULE__{id: String.t(), kind: kind}

  @max_encoded_pk 512

  @doc """
  Parses a ref string into an `%ObjectRef{}`.

  Returns `{:error, :unknown_object}` for anything that is not shaped like
  one of the four ref forms — malformed input is indistinguishable from
  unknown input, deliberately.
  """
  @spec parse(term) :: {:ok, t} | {:error, :unknown_object}
  def parse(ref) when is_binary(ref) do
    case String.split(ref, ":", parts: 3) do
      ["application", app] -> simple(ref, :application, app)
      ["domain", short] -> simple(ref, :domain, short)
      ["resource", path] -> dotted(ref, :resource, path)
      ["record", path, encoded_pk] -> record(ref, path, encoded_pk)
      _other -> {:error, :unknown_object}
    end
  end

  def parse(_other), do: {:error, :unknown_object}

  @doc """
  Encodes a primary key (or map of primary-key fields) for the
  `record:` ref form. Server-side only — the output is opaque to clients.
  """
  @spec encode_pk(term) :: String.t()
  def encode_pk(pk) do
    pk
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Decodes the primary-key segment of a record ref. Fails closed: oversized
  payloads, undecodable data, or anything that would create a new atom
  yields `{:error, :unknown_object}`.
  """
  @spec decode_pk(String.t()) :: {:ok, term} | {:error, :unknown_object}
  def decode_pk(encoded) when is_binary(encoded) and byte_size(encoded) <= @max_encoded_pk do
    with {:ok, binary} <- Base.url_decode64(encoded, padding: false),
         {:ok, term} <- safe_binary_to_term(binary) do
      {:ok, term}
    else
      _error -> {:error, :unknown_object}
    end
  end

  def decode_pk(_oversized_or_not_a_string), do: {:error, :unknown_object}

  defp simple(ref, kind, segment) do
    if valid_segment?(segment) do
      {:ok, %__MODULE__{id: ref, kind: kind}}
    else
      {:error, :unknown_object}
    end
  end

  # `:safe` is the load-bearing flag: binary_to_term refuses to create atoms
  # that do not already exist, so a decoded ref can never mint a module or
  # atom name from client input. `:safe` still decodes functions, so a term
  # holding one is refused too (as `Plug.Crypto.non_executable_binary_to_term/2`
  # does): a primary key is data.
  # sobelow_skip ["Misc.BinToTerm"]
  defp safe_binary_to_term(binary) do
    term = :erlang.binary_to_term(binary, [:safe])
    if executable?(term), do: :error, else: {:ok, term}
  rescue
    _invalid -> :error
  end

  defp executable?(term) when is_function(term), do: true
  defp executable?([head | tail]), do: executable?(head) or executable?(tail)
  defp executable?(term) when is_tuple(term), do: term |> Tuple.to_list() |> executable?()

  defp executable?(term) when is_map(term),
    do: Enum.any?(term, fn {key, value} -> executable?(key) or executable?(value) end)

  defp executable?(_term), do: false

  defp dotted(ref, kind, path) do
    case String.split(path, ".", parts: 2) do
      [left, right] ->
        if valid_segment?(left) and valid_segment?(right) do
          {:ok, %__MODULE__{id: ref, kind: kind}}
        else
          {:error, :unknown_object}
        end

      _unsegmented ->
        {:error, :unknown_object}
    end
  end

  defp record(ref, path, encoded_pk) do
    with {:ok, %__MODULE__{id: ref, kind: :resource}} <- dotted(ref, :resource, path),
         true <- valid_segment?(encoded_pk) do
      {:ok, %__MODULE__{id: ref, kind: :record}}
    else
      _invalid -> {:error, :unknown_object}
    end
  end

  defp valid_segment?(segment) when is_binary(segment) do
    segment != "" and
      String.length(segment) <= 255 and
      not String.contains?(segment, [" ", "\n", "\t", "\r", "\0", "/", "#"])
  end
end
