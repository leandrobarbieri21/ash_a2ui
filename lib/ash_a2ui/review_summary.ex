defmodule AshA2ui.ReviewSummary do
  @moduledoc """
  Target struct for the `review_summary` DSL entity (admin catalog 3.6): an
  `alert` `:detail` that sums up the review of the record its context
  selects — how many of the surface's `review` fields still wait for a
  person, and a link to the first one.

  A field waits while its review's state is `pending` or `missing` (see
  `AshA2ui.Review`): filled in automatically and not checked, or looked for
  and not found, and not checked either. "First" is the surface's
  declaration order: its `:detail` components in order, each one's fields
  in order. The link goes to the section of the card holding that field:
  its `section_nav` entry's `#anchor` when the nav lists the section, else
  the section's own id (`#section_<component>`). With nothing waiting it is
  `fallback_href`, worded `fallback_label`.

  The record carries the summary at `/detail/<context>/_review_summary_<component>`:

      %{
        "count" => 2,                 # fields still waiting
        "field" => "fee",             # the first one ("" when none)
        "href" => "#overview",        # where the link goes ("" for no link)
        "label" => "Go to first flagged field"
      }

  See `data/3`.
  """

  alias AshA2ui.{Label, Review}

  defstruct [
    :link_label,
    :fallback_href,
    :fallback_label,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          link_label: String.t() | nil,
          fallback_href: String.t() | nil,
          fallback_label: String.t() | nil
        }

  @waiting ~w(pending missing)

  @doc "The data key a summary component's record carries its summary at."
  @spec key(AshA2ui.Component.t()) :: String.t()
  def key(component), do: "_review_summary_#{AshA2ui.Component.key(component)}"

  @doc """
  The review summaries of `context`'s record: one `_review_summary_<component>`
  per `:detail` component of that context declaring a `review_summary`.
  """
  @spec data(AshA2ui.ResolvedView.t(), atom, struct()) :: %{String.t() => map}
  def data(view, context, record) do
    for %{component: %{review_summary: %__MODULE__{} = summary} = component} <- view.details,
        component.context == context,
        into: %{} do
      {key(component), summary(view, context, summary, record)}
    end
  end

  defp summary(view, context, summary, record) do
    waiting = waiting(view, context, record)

    case waiting do
      [{field, detail} | _rest] ->
        %{
          "count" => length(waiting),
          "field" => to_string(field),
          "href" => href(view, detail.component),
          "label" => translate(view, summary.link_label || "Go to the first field to review")
        }

      [] ->
        %{
          "count" => 0,
          "field" => "",
          "href" => summary.fallback_href || "",
          "label" => (summary.fallback_label && translate(view, summary.fallback_label)) || ""
        }
    end
  end

  # The surface's review fields still waiting on `record`, in declaration
  # order, each with the card that shows it (a field on two cards counts once).
  defp waiting(view, context, record) do
    for detail <- view.details,
        detail.context == context,
        is_nil(detail.component.alert),
        field <- detail.fields,
        %AshA2ui.Field{review: source} when not is_nil(source) <- [view.fields[field]],
        %{"state" => state} <- [Review.normalize(Map.get(record, source))],
        state in @waiting,
        reduce: [] do
      acc -> if List.keymember?(acc, field, 0), do: acc, else: acc ++ [{field, detail}]
    end
  end

  # The section a card sits in: its nav entry's anchor, else the section's id.
  defp href(view, component) do
    case section_start(view, component) do
      nil ->
        "#detail_#{AshA2ui.Component.key(component)}"

      start ->
        anchor =
          view.section_nav &&
            Enum.find_value(view.section_nav.items, &(&1.component == start && &1.anchor))

        "#" <> (anchor || "section_#{start}")
    end
  end

  defp section_start(_view, %{section: nil}), do: nil

  defp section_start(view, component) do
    view.components
    |> Enum.chunk_by(&Map.get(&1, :section))
    |> Enum.find_value(fn [first | _] = run ->
      if Enum.any?(run, &(&1 == component)), do: AshA2ui.Component.key(first)
    end)
  end

  defp translate(view, text), do: Label.translate(view.l10n, text)

  @doc "The words a summary shows, for the metadata template."
  @spec texts(t()) :: [String.t()]
  def texts(%__MODULE__{} = summary),
    do:
      Enum.reject(
        [summary.link_label || "Go to the first field to review", summary.fallback_label],
        &is_nil/1
      )
end
