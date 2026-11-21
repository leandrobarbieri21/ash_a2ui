defmodule AshA2ui.Masked do
  @moduledoc """
  A field the reader's field policies forbid (`%Ash.ForbiddenField{}`) is
  not a known-empty value: a surface that drew `null` would read as "known
  and empty", and a surface that drew the struct would leak it. The rule,
  in this one place:

  * a forbidden field's value draws `text/1` — the library word "Hidden",
    translated for the reader;
  * the record carries the reason beside it, under the reserved `"_masked"`
    key (`%{"<field>" => reason/1}`, only masked fields listed), the same
    reserved-key convention as `_values`;
  * nothing else from the struct — never `original_value` — reaches the
    wire.

  `%Ash.NotLoaded{}` and a visible `nil` are not masked: they stay `null`
  and carry no `"_masked"` entry. A `source` field is masked when any step
  of its relationship walk is forbidden — a forbidden relationship masks
  everything behind it, a forbidden leaf masks itself.
  """

  import AshA2ui.Gettext, only: [msg: 1]

  alias AshA2ui.L10n

  @doc "Whether `value` is a field the actor's field policies forbid."
  @spec masked?(term) :: boolean
  def masked?(%Ash.ForbiddenField{}), do: true
  def masked?(_other), do: false

  @doc """
  The words a masked field's cell draws: the library string "Hidden",
  translated with the surface translator. A `nil` translator reads English.
  """
  @spec text(L10n.t()) :: String.t()
  def text(l10n), do: L10n.t(l10n, msg("Hidden"))

  @doc """
  The reason a surface shows beside the masked text: the library string
  "You do not have access to this value.", translated the same way.
  """
  @spec reason(L10n.t()) :: String.t()
  def reason(l10n), do: L10n.t(l10n, msg("You do not have access to this value."))

  @doc """
  The reserved `"_masked"` entry of a record: `%{"<field>" => reason}` for
  every masked field, `%{}` (no key on the record) when the list is empty.
  """
  @spec row_data([atom | String.t()], L10n.t()) :: %{String.t() => %{String.t() => String.t()}}
  def row_data([], _l10n), do: %{}

  def row_data(fields, l10n),
    do: %{"_masked" => Map.new(fields, &{to_string(&1), reason(l10n)})}

  @doc """
  Whether a `source` field's read of `record` along `path`
  (`[:relationship, ..., :attribute]`) hit a forbidden step — a forbidden
  relationship or a forbidden leaf. A `nil` or unloaded step ends the walk
  unmasked: what was never loaded cannot be forbidden.
  """
  @spec forbidden_source?(Ash.Resource.record(), [atom]) :: boolean
  def forbidden_source?(record, [attribute]), do: masked?(Map.get(record, attribute))

  def forbidden_source?(record, [relationship | rest]) do
    case Map.get(record, relationship) do
      %Ash.ForbiddenField{} -> true
      %Ash.NotLoaded{} -> false
      nil -> false
      related -> forbidden_source?(related, rest)
    end
  end
end
