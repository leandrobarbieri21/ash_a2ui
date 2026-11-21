defmodule AshA2ui.Pairs do
  @moduledoc """
  The items of a field declared `pairs true`: a list of labeled values whose
  labels vary per record (admin catalog 1.16), such as the terms a record
  was read with. Each item may carry its own review and a key (catalog
  3.10), so a renderer can draw a review per item and the field's
  `field_action` as a button per item.

  An item is a map with a `term` and a `value`, and optionally:

    * `review`: how the item was filled in, in `AshA2ui.Review`'s shape
      (`state`, `page`, `href`, `quote`, `boxes`);
    * `key`: the item's stable address within the record (text or an
      integer), sent back as the field action's `item`;
    * `action`: whether the item offers the field's action (a boolean,
      `true` when absent).

  Keys may be atoms or strings. `normalize/3` turns a raw value into the
  wire items a row carries at `_pairs_<field>`:

      %{
        "term" => "Notice",
        "value" => "60 days",
        "key" => "0",                      # only when present
        "review" => %{"state" => ...},     # only when present (AshA2ui.Review)
        "action" => true                   # only when the field has a field action
      }

  An item offers the field's action only when it has a key, it does not say
  `action: false`, and the record offers the action
  (`field_action_visible`).

  Bad values never fail a render:

    * a value that is not a list has no items;
    * an entry that is not a map, or has no term (`nil`, `""`), is left out;
    * a `value` that is `nil` is `""`; a number, atom, date or decimal is
      written with `to_string/1`;
    * a `key` that is not text or an integer, or is `""`, is left out;
    * a review that `AshA2ui.Review.normalize/2` does not take is left out.
  """

  alias AshA2ui.{L10n, Review}

  @typedoc "One item on the wire."
  @type item :: %{optional(String.t()) => term}

  @doc """
  The wire items of a raw `value`, their reviews' words translated by
  `l10n`. `offered` is whether the record offers the field's action: `nil`
  when the field has none (no item carries `action`).
  """
  @spec normalize(term, L10n.t(), boolean | nil) :: [item]
  def normalize(value, l10n \\ nil, offered \\ nil)

  def normalize(value, l10n, offered) when is_list(value),
    do: Enum.flat_map(value, &entry(&1, l10n, offered))

  def normalize(_value, _l10n, _offered), do: []

  @doc """
  The pairs data a table row carries for its `pairs` fields:
  `%{"_pairs_<field>" => items}`. `offers` maps a field with a field action
  to whether the record offers it (see
  `AshA2ui.ResolvedView.field_action_offered?/2`).
  """
  @spec data(struct(), [AshA2ui.Field.t()], L10n.t(), %{atom => boolean}) ::
          %{String.t() => [item]}
  def data(record, fields, l10n, offers \\ %{}) do
    Map.new(fields, fn %AshA2ui.Field{name: name} ->
      {"_pairs_#{name}", normalize(Map.get(record, name), l10n, Map.get(offers, name))}
    end)
  end

  @doc """
  The item of `items` (wire items, see `normalize/3`) whose key is `key`, or
  `nil`.
  """
  @spec find(term, String.t()) :: item | nil
  def find(items, key) when is_list(items) and is_binary(key),
    do: Enum.find(items, &(Map.get(&1, "key") == key))

  def find(_items, _key), do: nil

  @doc "Whether a wire item's review still waits for a person (`pending` or `missing`)."
  @spec waiting?(item) :: boolean
  def waiting?(%{"review" => %{"state" => state}}), do: state in ~w(pending missing)
  def waiting?(_item), do: false

  defp entry(entry, l10n, offered) when is_map(entry) and not is_struct(entry) do
    case text(get(entry, :term)) do
      nil ->
        []

      term ->
        key = key(get(entry, :key))

        item =
          %{"term" => term, "value" => text(get(entry, :value)) || ""}
          |> put_present("key", key)
          |> put_present("review", Review.normalize(get(entry, :review), l10n))

        [put_action(item, offered, key, get(entry, :action))]
    end
  end

  defp entry(_entry, _l10n, _offered), do: []

  defp put_action(item, nil, _key, _own), do: item

  defp put_action(item, offered, key, own),
    do: Map.put(item, "action", offered == true and is_binary(key) and own != false)

  defp get(entry, key), do: Map.get(entry, key, Map.get(entry, Atom.to_string(key)))

  defp key(value) when is_binary(value) and value != "", do: value
  defp key(value) when is_integer(value), do: Integer.to_string(value)
  defp key(_value), do: nil

  defp text(nil), do: nil
  defp text(""), do: nil
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_boolean(value), do: nil

  defp text(value)
       when is_number(value) or is_atom(value) or is_struct(value, Date) or
              is_struct(value, DateTime) or is_struct(value, NaiveDateTime) or
              is_struct(value, Time),
       do: to_string(value)

  defp text(%Decimal{} = value), do: Decimal.to_string(value)
  defp text(_value), do: nil

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
