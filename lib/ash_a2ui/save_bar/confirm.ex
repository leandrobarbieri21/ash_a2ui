defmodule AshA2ui.SaveBar.Confirm do
  @moduledoc """
  Target struct for a `save_bar`'s `confirm` entity (admin catalog 3.11): the
  dialog a save opens while fields under review still wait. Cancel closes it
  with nothing saved; the save choice saves; the `then` choice saves and
  then runs `then_action` on the bar's record, in the same transaction.
  """

  defstruct [
    :title,
    :title_one,
    :message,
    :message_one,
    :then_action,
    :then_label,
    :then_visible,
    :then_saved_message,
    :cancel_label,
    :save_label,
    then_when_clear: false,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          title_one: String.t() | nil,
          message: String.t() | nil,
          message_one: String.t() | nil,
          then_action: atom | nil,
          then_label: String.t() | nil,
          then_visible: atom | nil,
          then_saved_message: String.t() | nil,
          cancel_label: String.t() | nil,
          save_label: String.t() | nil,
          then_when_clear: boolean
        }
end
