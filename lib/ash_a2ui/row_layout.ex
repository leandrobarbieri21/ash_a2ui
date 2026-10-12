defmodule AshA2ui.RowLayout do
  @moduledoc """
  Target struct for the `row_layout` DSL entity — the card-style record
  layout of a `:table` component: a header row (title + optional badge,
  alongside the row's actions) above an N-column grid of caption-labeled
  metadata values.
  """

  defstruct [
    :title,
    :badge,
    :meta,
    badge_text: [],
    badge_tones: [],
    columns: 2,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          title: atom,
          badge: atom | nil,
          meta: [atom] | nil,
          badge_text: keyword(String.t()),
          badge_tones: keyword(atom),
          columns: pos_integer
        }

  @doc """
  The computed badge row data a serialized record carries when its table
  declares a `row_layout` with a `badge`: `%{"_badge_<field>" => text}`,
  where the text is the `badge_text` entry matching the record's value
  (atom/boolean values only — keyword keys), the humanized value otherwise,
  and `""` for `nil`. Layouts declaring `badge_tones` add
  `"_badge_tone_<field>"`: the matching tone (`"neutral"` when unmatched).
  Empty for layout-less tables and badge-less layouts.

  Shared by the encoder and `AshA2ui.ActionHandler` so initial renders and
  query/action refreshes serialize rows identically.
  """
  @spec badge_data(t() | nil, Ash.Resource.record()) :: %{String.t() => String.t()}
  def badge_data(layout, record)

  def badge_data(nil, _record), do: %{}
  def badge_data(%__MODULE__{badge: nil}, _record), do: %{}

  def badge_data(%__MODULE__{badge: badge, badge_tones: []} = layout, record) do
    %{"_badge_#{badge}" => badge_text(layout, Map.get(record, badge))}
  end

  def badge_data(%__MODULE__{badge: badge} = layout, record) do
    value = Map.get(record, badge)

    %{
      "_badge_#{badge}" => badge_text(layout, value),
      "_badge_tone_#{badge}" => badge_tone(layout, value)
    }
  end

  @tones ~w(neutral info success warning danger accent)a

  @doc "The badge tone vocabulary `badge_tones` values are drawn from."
  @spec tones() :: [atom]
  def tones, do: @tones

  defp badge_tone(_layout, nil), do: "neutral"

  defp badge_tone(layout, value) do
    tone = is_atom(value) && Keyword.get(layout.badge_tones, value)
    to_string(tone || :neutral)
  end

  defp badge_text(_layout, nil), do: ""

  defp badge_text(layout, value) do
    declared = is_atom(value) && Keyword.get(layout.badge_text, value)

    declared ||
      value
      |> to_string()
      |> String.replace("_", " ")
      |> String.capitalize()
  end
end
