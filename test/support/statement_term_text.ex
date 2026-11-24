defmodule AshA2ui.Test.StatementTermText do
  @moduledoc """
  Fixture calculation: one of a statement's term values as shown on its
  card, in words ("2027-06-30", "30 days", "automatic"), or `nil` while the
  statement has no term or the term no value.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:term]

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn
      %{term: %{} = term} -> text(opts[:field], Map.get(term, opts[:field]))
      _no_term -> nil
    end)
  end

  defp text(_field, nil), do: nil
  defp text(:notice_days, days), do: "#{days} days"
  defp text(_field, value), do: to_string(value)
end
