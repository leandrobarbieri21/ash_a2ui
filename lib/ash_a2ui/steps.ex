defmodule AshA2ui.Steps do
  @moduledoc """
  The steps of a field declared `steps true`: a list of maps drawn as a
  numbered stepper on `:detail` cards (admin catalog 1.17).

  A step is a map with a `label` (required), an optional `text` (the line
  under the label) and `note` (a smaller line), and a `state`: one of
  `"complete"`, `"current"`, `"upcoming"` or `"overdue"`. Keys and the state
  may be atoms or strings. `normalize/2` turns a raw value into the wire
  steps a record carries at `_steps_<field>`:

      %{
        "number" => 1,                       # its place among the steps drawn
        "label" => "Placed",
        "text" => "3 Nov 2026",              # only when present
        "note" => "Paid by card",            # only when present
        "state" => "complete",
        "stateLabel" => "Complete",          # the state in words, translated
        "line" => "1. Placed · Complete · 3 Nov 2026 · Paid by card"
      }

  `line` is the whole step as one line of text, for renderers that draw
  plain text (the basic catalog).

  Bad values never fail a render:

    * a value that is not a list (`nil`, `""`, a map) has no steps;
    * an entry that is not a map, or has no label (`nil`, `""` or not
      text), is left out, and the steps that remain are numbered 1..n;
    * a missing or unknown state reads as `"upcoming"`;
    * a `text` or `note` that is `nil` or `""` is left out; a number, atom,
      date or time is written with `to_string/1`; any other value is left
      out.
  """

  import AshA2ui.Gettext, only: [msg: 1]

  alias AshA2ui.L10n

  @states ~w(complete current upcoming overdue)

  @typedoc "One step on the wire."
  @type step :: %{optional(String.t()) => String.t() | pos_integer}

  @doc "The step states, in the order a stepper usually reads them."
  @spec states() :: [String.t()]
  def states, do: @states

  @doc """
  The wire steps of a raw `value`, with each state's words translated by
  `l10n` (see the module doc for the shape and the rules for bad values).
  """
  @spec normalize(term, L10n.t()) :: [step]
  def normalize(value, l10n \\ nil)

  def normalize(value, l10n) when is_list(value) do
    value
    |> Enum.flat_map(&entry/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {step, number} -> wire(step, number, l10n) end)
  end

  def normalize(_value, _l10n), do: []

  @doc """
  The steps data a `:detail` record carries for its `steps` fields:
  `%{"_steps_<field>" => steps}`.
  """
  @spec data(struct(), [AshA2ui.Field.t()], L10n.t()) :: %{String.t() => [step]}
  def data(record, fields, l10n) do
    Map.new(fields, fn %AshA2ui.Field{name: name} ->
      {"_steps_#{name}", normalize(Map.get(record, name), l10n)}
    end)
  end

  defp entry(entry) when is_map(entry) do
    case text(get(entry, :label)) do
      nil ->
        []

      label ->
        [
          %{
            label: label,
            text: text(get(entry, :text)),
            note: text(get(entry, :note)),
            state: state(get(entry, :state))
          }
        ]
    end
  end

  defp entry(_entry), do: []

  defp get(entry, key), do: Map.get(entry, key, Map.get(entry, Atom.to_string(key)))

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

  defp state(state) when is_atom(state) and not is_nil(state), do: state(Atom.to_string(state))
  defp state(state) when state in @states, do: state
  defp state(_state), do: "upcoming"

  defp wire(step, number, l10n) do
    state_label = state_label(l10n, step.state)

    %{
      "number" => number,
      "label" => step.label,
      "state" => step.state,
      "stateLabel" => state_label,
      "line" =>
        Enum.join(
          [
            "#{number}. #{step.label}",
            state_label | Enum.reject([step.text, step.note], &is_nil/1)
          ],
          " · "
        )
    }
    |> put_present("text", step.text)
    |> put_present("note", step.note)
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp state_label(l10n, "complete"), do: L10n.t(l10n, msg("Complete"))
  defp state_label(l10n, "current"), do: L10n.t(l10n, msg("Current"))
  defp state_label(l10n, "upcoming"), do: L10n.t(l10n, msg("Upcoming"))
  defp state_label(l10n, "overdue"), do: L10n.t(l10n, msg("Overdue"))
end
