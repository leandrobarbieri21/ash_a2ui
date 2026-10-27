defmodule AshA2ui.PrimaryAction do
  @moduledoc """
  Target struct for the `primary_action` DSL entity — a `:table`'s primary
  row action (the row click: the `select_context` selection, else View)
  drawn as one button per row, with a per-row label and variant.

  `label_from` names a field whose value picks the row's `labels` and
  `variants` entries; values without an entry (and every row when there is
  no `label_from`) get `label` (default: the row click's own label) and
  `variant`. Variants are the A2UI Button's: `:default`, `:primary` and
  `:borderless`.
  """

  defstruct [
    :label_from,
    :label,
    labels: [],
    variants: [],
    variant: :default,
    __spark_metadata__: nil
  ]

  @type variant :: :default | :primary | :borderless

  @type t :: %__MODULE__{
          label_from: atom | nil,
          label: String.t() | nil,
          labels: keyword(String.t()),
          variants: keyword(variant),
          variant: variant
        }

  @variants [:default, :primary, :borderless]

  @doc "The Button variants a primary action may take."
  @spec variants() :: [variant]
  def variants, do: @variants

  @doc """
  The computed row data a serialized record carries when its table declares
  a `primary_action`: `%{"_primary_label" => label, "_primary_variant" =>
  variant}`. `default_label` is the row click's own label, used when the
  action declares no `label` and the row's value has no `labels` entry.
  Empty for tables without one.

  Shared by the initial render and every refresh (`serialize_row`), so a
  refreshed row reads the same as the row it replaces.
  """
  @spec row_data(t() | nil, Ash.Resource.record(), String.t()) :: %{String.t() => String.t()}
  def row_data(nil, _record, _default_label), do: %{}

  def row_data(%__MODULE__{} = action, record, default_label) do
    value = action.label_from && Map.get(record, action.label_from)

    %{
      "_primary_label" => entry(action.labels, value) || action.label || default_label,
      "_primary_variant" => to_string(entry(action.variants, value) || action.variant)
    }
  end

  # Keyword entries match atom values (including booleans), as row_layout's
  # badge_text does, and string values by name (a calculation that returns
  # a string); anything else has no entry.
  defp entry(_keyword, nil), do: nil
  defp entry(keyword, value) when is_atom(value), do: Keyword.get(keyword, value)

  defp entry(keyword, value) when is_binary(value) do
    Enum.find_value(keyword, fn {key, entry} -> Atom.to_string(key) == value && entry end)
  end

  defp entry(_keyword, _value), do: nil
end
