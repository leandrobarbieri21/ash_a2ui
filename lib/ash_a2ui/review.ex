defmodule AshA2ui.Review do
  @moduledoc """
  The review of a field declared `review :name`: how its value was filled
  in, drawn on `:detail` cards (admin catalog 3.1).

  The named attribute or calculation holds a map with a `state`, one of
  `"pending"` (filled in automatically, nobody has checked it yet),
  `"reviewed"` (a person checked it) or `"missing"` (looked for and not
  found), and an optional citation: `page` (the page of the source document
  the value came from), `href` (an address that opens the source there) and
  `quote` (the words the value was read from). Keys and the state may be
  atoms or strings. `normalize/2` turns it into the wire review a record
  carries at `_review_<field>`:

      %{
        "state" => "pending",
        "stateLabel" => "Not reviewed",      # the state in words, translated
        "page" => 3,                         # only when present
        "pageLabel" => "p. 3",               # the page tag, translated
        "href" => "/documents/9#page=3",     # only when present
        "quote" => "Annual fee: $14,400"     # only when present
      }

  Bad values never fail a render:

    * a value that is not a map, or a map without a known state, is no
      review (`nil`): the field draws as it would without one;
    * a `page` that is not a positive integer (or a string of one) is left
      out, and so is its `pageLabel`;
    * an `href` or `quote` that is not text, or is `""`, is left out.
  """

  import AshA2ui.Gettext, only: [msg: 1]

  alias AshA2ui.L10n

  @states ~w(pending reviewed missing)

  @typedoc "One review on the wire."
  @type review :: %{optional(String.t()) => String.t() | pos_integer}

  @doc "The review states."
  @spec states() :: [String.t()]
  def states, do: @states

  @doc """
  The wire review of a raw `value`, with its words translated by `l10n`
  (see the module doc for the shape and the rules for bad values).
  """
  @spec normalize(term, L10n.t()) :: review | nil
  def normalize(value, l10n \\ nil)

  def normalize(value, l10n) when is_map(value) and not is_struct(value) do
    case state(get(value, :state)) do
      nil ->
        nil

      state ->
        page = page(get(value, :page))

        %{"state" => state, "stateLabel" => state_label(l10n, state)}
        |> put_present("page", page)
        |> put_present("pageLabel", page && page_label(l10n, page))
        |> put_present("href", text(get(value, :href)))
        |> put_present("quote", text(get(value, :quote)))
    end
  end

  def normalize(_value, _l10n), do: nil

  @doc """
  The review data a `:detail` record carries for its `review` fields:
  `%{"_review_<field>" => review}`, `nil` for a field with no review.
  """
  @spec data(struct(), [AshA2ui.Field.t()], L10n.t()) :: %{String.t() => review | nil}
  def data(record, fields, l10n) do
    Map.new(fields, fn %AshA2ui.Field{name: name, review: source} ->
      {"_review_#{name}", normalize(Map.get(record, source), l10n)}
    end)
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp state(state) when is_atom(state) and not is_nil(state), do: state(Atom.to_string(state))
  defp state(state) when state in @states, do: state
  defp state(_state), do: nil

  defp page(page) when is_integer(page) and page > 0, do: page

  defp page(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number > 0 -> number
      _other -> nil
    end
  end

  defp page(_page), do: nil

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp state_label(l10n, "pending"), do: L10n.t(l10n, msg("Not reviewed"))
  defp state_label(l10n, "reviewed"), do: L10n.t(l10n, msg("Reviewed"))
  defp state_label(l10n, "missing"), do: L10n.t(l10n, msg("Not found in the document"))

  defp page_label(l10n, page), do: L10n.t(l10n, msg("p. %{page}"), page: page)
end
