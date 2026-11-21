defmodule AshA2ui.SaveBar do
  @moduledoc """
  Target struct for the `save_bar` DSL entity (admin catalog 3.11): the bar
  pinned to the bottom of a page while a person has unsaved changes to the
  surface's editable `:detail` cards. It saves them all at once through the
  `"save_changes"` client action, or discards them.

  `context` names the record the bar reads: the fields under review it
  counts and its `confirm` (`AshA2ui.SaveBar.Confirm`). See the
  editing-a-record-in-place section of the contexts-and-details topic.
  """

  defstruct [
    :context,
    :id,
    :message,
    :message_waiting,
    :status,
    :status_one,
    :confirm,
    :save_label,
    :discard_label,
    :saved_message,
    edit_reviews: false,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          context: atom,
          id: String.t() | nil,
          message: String.t() | nil,
          message_waiting: String.t() | nil,
          status: String.t() | nil,
          status_one: String.t() | nil,
          confirm: AshA2ui.SaveBar.Confirm.t() | nil,
          save_label: String.t() | nil,
          discard_label: String.t() | nil,
          saved_message: String.t() | nil,
          edit_reviews: boolean
        }

  @doc """
  The review states that count as waiting: a value nobody has reviewed yet
  (`pending`) and a value the source did not hold (`missing`), as
  `AshA2ui.Review` normalizes them.
  """
  @spec waiting_states() :: [String.t()]
  def waiting_states, do: ["pending", "missing"]
end
