defmodule AshA2ui.Test.LeaseTermText do
  @moduledoc """
  Fixture calculation: a lease's term as its cards show it: the end, the
  notice ("60 days"), the date notice is due by ("Notice by 2027-05-01"),
  or the timeline of the two dates as steps. `nil` (or no steps) while the
  lease has no term or the term no value.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [term: [:ends_on, :notice_days, :notice_by]]

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn
      %{term: %{} = term} -> text(opts[:part], term)
      _no_term -> if opts[:part] == :timeline, do: [], else: nil
    end)
  end

  defp text(:ends_on, %{ends_on: ends_on}), do: ends_on && Date.to_iso8601(ends_on)
  defp text(:notice_days, %{notice_days: days}), do: days && "#{days} days"
  defp text(:notice_by, %{notice_by: by}), do: by && "Notice by #{Date.to_iso8601(by)}"

  defp text(:timeline, term) do
    [
      %{label: "Notice by", text: term.notice_by && Date.to_iso8601(term.notice_by)},
      %{label: "Ends", text: term.ends_on && Date.to_iso8601(term.ends_on)}
    ]
  end
end
