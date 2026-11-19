defmodule AshA2ui.Review do
  @moduledoc """
  The review of a field declared `review :name`: how its value was filled
  in, drawn on `:detail` cards (admin catalog 3.1).

  The named attribute or calculation holds a map with a `state`, one of
  `"pending"` (filled in automatically, nobody has checked it yet),
  `"reviewed"` (a person checked it) or `"missing"` (looked for and not
  found), and an optional citation: `page` (the page of the source document
  the value came from), `href` (an address that opens the source there),
  `quote` (the words the value was read from) and `boxes` (where on its
  pages the value sits, for a document pane: see `AshA2ui.DocumentPane`).
  Keys and the state may be atoms or strings. `normalize/2` turns it into
  the wire review a record carries at `_review_<field>`:

      %{
        "state" => "pending",
        "stateLabel" => "Not reviewed",      # the state in words, translated
        "page" => 3,                         # only when present
        "pageLabel" => "p. 3",               # the page tag, translated
        "href" => "/documents/9#page=3",     # only when present
        "quote" => "Annual fee: $14,400",    # only when present
        "boxes" => [%{"page" => 3, "x" => 0.1, "y" => 0.42,
                      "width" => 0.3, "height" => 0.02}]   # only when present
      }

  Each box is a rectangle on a page, as fractions of the page from its
  top-left corner (`x` and `width` of its width, `y` and `height` of its
  height), the shape `AshA2ui.DocumentPane` draws. On a surface whose
  `document_pane` is bound to the field's card, a review with boxes links to
  them: its `href` becomes the pane's (`AshA2ui.DocumentPane.region_href/2`).

  Bad values never fail a render:

    * a value that is not a map, or a map without a known state, is no
      review (`nil`): the field draws as it would without one;
    * a `page` that is not a positive integer (or a string of one) is left
      out, and so is its `pageLabel`;
    * an `href` or `quote` that is not text, or is `""`, is left out;
    * a box that is not on a positive page, or whose numbers are not
      fractions of the page (from 0 to 1, a positive width and height, not
      past the page's edge), is left out, and so is an empty list.
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
        |> put_present("boxes", boxes(get(value, :boxes)))
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

  @doc """
  A box as the wire carries it (`%{"page", "x", "y", "width", "height"}`),
  or `nil` when it is not a box on a page: `page` a positive integer, the
  rest numbers from 0 to 1 with a positive width and height, the box not
  past the page's right or bottom edge. Keys may be atoms or strings.
  """
  @spec box(term) :: %{String.t() => number} | nil
  def box(value) when is_map(value) and not is_struct(value) do
    with page when is_integer(page) <- page(get(value, :page)),
         [x, y, w, h] <- Enum.map([:x, :y, :width, :height], &fraction(get(value, &1))),
         true <- Enum.all?([x, y, w, h], &is_number/1),
         true <- w > 0 and h > 0 and x + w <= 1.0001 and y + h <= 1.0001 do
      %{"page" => page, "x" => x, "y" => y, "width" => w, "height" => h}
    else
      _not_a_box -> nil
    end
  end

  def box(_value), do: nil

  defp boxes(list) when is_list(list) do
    case list |> Enum.map(&box/1) |> Enum.reject(&is_nil/1) do
      [] -> nil
      boxes -> boxes
    end
  end

  defp boxes(_value), do: nil

  defp fraction(n) when is_integer(n) and n in 0..1, do: n * 1.0
  defp fraction(n) when is_float(n) and n >= 0 and n <= 1, do: n
  defp fraction(%Decimal{} = n), do: n |> Decimal.to_float() |> fraction()
  defp fraction(_n), do: nil

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp state_label(l10n, "pending"), do: L10n.t(l10n, msg("Not reviewed"))
  defp state_label(l10n, "reviewed"), do: L10n.t(l10n, msg("Reviewed"))
  defp state_label(l10n, "missing"), do: L10n.t(l10n, msg("Not found in the document"))

  defp page_label(l10n, page), do: L10n.t(l10n, msg("p. %{page}"), page: page)
end
