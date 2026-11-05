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
  @spec badge_data(t() | nil, Ash.Resource.record(), AshA2ui.L10n.t()) ::
          %{String.t() => String.t()}
  def badge_data(layout, record, l10n \\ nil)

  def badge_data(nil, _record, _l10n), do: %{}
  def badge_data(%__MODULE__{badge: nil}, _record, _l10n), do: %{}

  def badge_data(%__MODULE__{badge: badge, badge_tones: []} = layout, record, l10n) do
    %{"_badge_#{badge}" => badge_text(layout, record, l10n)}
  end

  def badge_data(%__MODULE__{badge: badge} = layout, record, l10n) do
    value = Map.get(record, badge)

    %{
      "_badge_#{badge}" => badge_text(layout, record, l10n),
      "_badge_tone_#{badge}" => badge_tone(layout, value)
    }
  end

  @tones ~w(neutral info success warning danger accent pending gray)a

  @doc "The badge tone vocabulary `badge_tones` values are drawn from."
  @spec tones() :: [atom]
  def tones, do: @tones

  defp badge_tone(_layout, nil), do: "neutral"

  defp badge_tone(layout, value) do
    tone = is_atom(value) && Keyword.get(layout.badge_tones, value)
    to_string(tone || :neutral)
  end

  defp badge_text(layout, record, l10n) do
    badge_text(layout, record, Map.get(record, layout.badge), l10n)
  end

  defp badge_text(_layout, _record, nil, _l10n), do: ""

  # Display metadata is translated; a record's own value is not. A declared
  # text, the label of an enumerated value (under its msgctxt, as the pickers
  # and lane headings label it) and an atom value such as a boolean are
  # metadata. Any other value is record data and is only humanized.
  defp badge_text(layout, record, value, l10n) do
    declared = is_atom(value) && Keyword.get(layout.badge_text, value)

    cond do
      declared ->
        AshA2ui.Label.translate(l10n, declared)

      context = choice_context(record, layout.badge) ->
        AshA2ui.Label.translate(l10n, AshA2ui.Label.humanize(value), context)

      is_atom(value) ->
        AshA2ui.Label.translate(l10n, AshA2ui.Label.humanize(value))

      true ->
        AshA2ui.Label.humanize(value)
    end
  end

  defp choice_context(%{__struct__: resource}, badge),
    do: AshA2ui.TypeMapper.choice_context(resource, badge)

  defp choice_context(_plain_map, _badge), do: nil
end
