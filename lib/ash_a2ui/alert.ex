defmodule AshA2ui.Alert do
  @moduledoc """
  Target struct for the `alert` DSL entity: a `:detail` component drawn as
  an alert (admin catalog 3.5's `alertBanner`) — a title, a message read from
  the context's record and an optional link, toned by `variant`.
  """

  defstruct [
    :title,
    :message,
    :link_href,
    :link_label,
    variant: :info,
    layout: :inline,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          message: atom | nil,
          link_href: atom | nil,
          link_label: atom | nil,
          variant: :info | :success | :warning | :danger | :neutral,
          layout: :inline | :section
        }

  @doc "The record fields an alert reads."
  @spec fields(t() | nil) :: [atom]
  def fields(nil), do: []

  def fields(%__MODULE__{} = alert),
    do: Enum.reject([alert.message, alert.link_href, alert.link_label], &is_nil/1)
end
