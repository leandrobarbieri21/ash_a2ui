defmodule AshA2ui.SaveBar do
  @moduledoc """
  Target struct for the `save_bar` DSL entity (admin catalog 3.11): the bar
  pinned to the bottom of a page while a person has unsaved changes to the
  surface's editable `:detail` cards. It saves them all at once through the
  `"save_changes"` client action, or discards them.

  `context` names the record the bar reads: the fields under review it
  counts and its `confirm` (`AshA2ui.SaveBar.Confirm`). With
  `show_while_waiting` (admin catalog 3.14) the bar also shows while those
  fields wait, before anything changed. The rows of the context's tables
  count too (admin catalog 3.16): the ones a `review_summary` would count,
  carried on the record at `rows_key/0`. With `status_reviewed` (3.17) it
  also counts the fields and rows reviewed so far, beside the ones still
  waiting. See the editing-a-record-in-place
  section of the contexts-and-details topic.
  """

  defstruct [
    :context,
    :id,
    :message,
    :message_waiting,
    :status,
    :status_one,
    :status_reviewed,
    :status_reviewed_one,
    :confirm,
    :save_label,
    :discard_label,
    :saved_message,
    edit_reviews: false,
    show_while_waiting: false,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          context: atom,
          id: String.t() | nil,
          message: String.t() | nil,
          message_waiting: String.t() | nil,
          status: String.t() | nil,
          status_one: String.t() | nil,
          status_reviewed: String.t() | nil,
          status_reviewed_one: String.t() | nil,
          confirm: AshA2ui.SaveBar.Confirm.t() | nil,
          save_label: String.t() | nil,
          discard_label: String.t() | nil,
          saved_message: String.t() | nil,
          edit_reviews: boolean,
          show_while_waiting: boolean | atom
        }

  @doc """
  The review states that count as waiting: a value nobody has reviewed yet
  (`pending`) and a value the source did not hold (`missing`), as
  `AshA2ui.Review` normalizes them.
  """
  @spec waiting_states() :: [String.t()]
  def waiting_states, do: ["pending", "missing"]

  @doc """
  The key of the bar's record holding its table rows' count (admin catalog
  3.16): `%{"waiting" => n}`, the rows (and `pairs` items) of the
  context's tables still waiting, as `AshA2ui.ReviewSummary` counts them.
  A table row is not edited through the bar, so the server counts them.
  """
  @spec rows_key() :: String.t()
  def rows_key, do: "_review_rows"

  @doc """
  The field of the bar's record gating `show_while_waiting`, or `nil` when
  the option is off or `true` (no field to read).
  """
  @spec show_field(t()) :: atom | nil
  def show_field(%__MODULE__{show_while_waiting: field})
      when is_atom(field) and field not in [nil, true, false],
      do: field

  def show_field(_bar), do: nil
end
