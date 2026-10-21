defmodule AshA2ui.AsOf do
  @moduledoc """
  The `?as_of=` grammar: how a surface is pinned to an instant.

  Ash temporal resources read "as of" one instant (`as_of:` on any read).
  A surface built with `as_of:` (`AshA2ui.Info.build_surface/2`) reads every
  table, option list, context and detail at that instant, so it shows the
  data as it was then. This module is the URL side of that: what `?as_of=`
  may carry, and how an instant is written back into a link.

  ## What `parse/1` accepts

    * a full ISO 8601 datetime with an offset (`2026-10-17T14:03:00Z`,
      `2026-10-17T10:03:00-04:00`). It is shifted to UTC. Microseconds are
      kept, so a link to the exact instant a change happened shows the state
      after it.
    * a `datetime-local` value without a zone (`2026-10-17T14:03` or
      `2026-10-17T14:03:00`), which is what a browser's datetime input posts.
      It is read as UTC.
    * a date (`2026-10-17`), read as the start of that day in UTC.

  Anything else, and an absent parameter, is `:error`, which means "now". A
  surface whose link no longer parses shows the present rather than failing.

  ## What `to_param/1` writes

  ISO 8601 in UTC, with the microseconds when there are any, so `parse/1`
  of `to_param/1` is the same instant. `nil` (now) writes no parameter.
  """

  @typedoc "An instant a surface is pinned to. `nil` means now."
  @type t :: DateTime.t() | nil

  @doc """
  Parses an `?as_of=` value: `{:ok, datetime}` in UTC, or `:error` for an
  absent or unparseable value (both mean "now").
  """
  @spec parse(term) :: {:ok, DateTime.t()} | :error
  def parse(value) when is_binary(value) do
    value = String.trim(value)

    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.shift_zone!(datetime, "Etc/UTC")}
      {:error, _reason} -> parse_local(value)
    end
  end

  def parse(_absent_or_not_a_string), do: :error

  @doc """
  `parse/1` for a params map: the instant under `"as_of"`, or `nil` (now).
  """
  @spec from_params(map | term) :: t
  def from_params(%{"as_of" => value}) do
    case parse(value) do
      {:ok, datetime} -> datetime
      :error -> nil
    end
  end

  def from_params(_params), do: nil

  @doc """
  The `?as_of=` value for an instant: ISO 8601 in UTC. `nil` for now.
  """
  @spec to_param(t) :: String.t() | nil
  def to_param(nil), do: nil

  def to_param(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> drop_zero_microseconds()
    |> DateTime.to_iso8601()
  end

  @doc """
  A path with its `as_of` query parameter set to `as_of` (or removed, for
  now). Every other query parameter is kept.

      iex> AshA2ui.AsOf.put_param("/app/people?ctx[person]=1", ~U[2026-10-17 14:03:00Z])
      "/app/people?as_of=2026-10-17T14%3A03%3A00Z&ctx%5Bperson%5D=1"

      iex> AshA2ui.AsOf.put_param("/app/people?as_of=2026-10-17", nil)
      "/app/people"
  """
  @spec put_param(String.t(), t) :: String.t()
  def put_param(path, as_of) when is_binary(path) do
    %URI{path: base, query: query} = URI.parse(path)

    # Flat decoding keeps nested keys (`ctx[person]`) as they were written,
    # so they round-trip without Plug's nested-params parser.
    params =
      (query || "")
      |> URI.decode_query()
      |> Map.delete("as_of")

    params =
      case to_param(as_of) do
        nil -> params
        value -> Map.put(params, "as_of", value)
      end

    case URI.encode_query(params) do
      "" -> base || "/"
      encoded -> (base || "/") <> "?" <> encoded
    end
  end

  @doc """
  The read option for an instant: `[as_of: datetime]`, or `[]` for now.

  Append it to the options of any Ash read (`for_read/4`, `Ash.get/3`, a
  code interface). An `as_of` on a resource that is not temporal only
  anchors `now()` in its expressions, so passing it to every read of a
  time-travelled surface is safe.
  """
  @spec read_opt(t | keyword) :: keyword
  def read_opt(%DateTime{} = as_of), do: [as_of: as_of]
  def read_opt(nil), do: []
  def read_opt(opts) when is_list(opts), do: read_opt(Keyword.get(opts, :as_of))

  @doc "Whether `as_of` pins a past or future instant rather than now."
  @spec pinned?(t | keyword) :: boolean
  def pinned?(%DateTime{}), do: true
  def pinned?(nil), do: false
  def pinned?(opts) when is_list(opts), do: pinned?(Keyword.get(opts, :as_of))

  # datetime-local posts "YYYY-MM-DDTHH:MM[:SS]" without a zone; a bare date
  # is the start of that day. Both are UTC.
  defp parse_local(value) do
    case Regex.run(
           ~r/^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?))?$/,
           value
         ) do
      [_match, date] -> at(date, "00:00:00")
      [_match, date, time] -> at(date, pad_seconds(time))
      nil -> :error
    end
  end

  defp at(date, time) do
    with {:ok, day} <- Date.from_iso8601(date),
         {:ok, time_of_day} <- Time.from_iso8601(time) do
      {:ok, DateTime.new!(day, time_of_day, "Etc/UTC")}
    else
      _invalid -> :error
    end
  end

  defp pad_seconds(<<_::binary-size(5)>> = hh_mm), do: hh_mm <> ":00"
  defp pad_seconds(time), do: time

  defp drop_zero_microseconds(%DateTime{microsecond: {0, _precision}} = datetime),
    do: %{datetime | microsecond: {0, 0}}

  defp drop_zero_microseconds(datetime), do: datetime
end
