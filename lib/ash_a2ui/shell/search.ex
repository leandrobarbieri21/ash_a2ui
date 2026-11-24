defmodule AshA2ui.Shell.Search do
  @moduledoc """
  Find a record by what a person knows about it: a business reference (a
  licence number, a contract number) or an id. The other half of
  `/open <surface> <id>`, for when the person has the reference but not the
  surface or the id.

  The host lists what may be searched, as entries
  (`AshA2ui.Shell.Host.searchable/1`); `find/3` looks one typed term up in
  all of them:

      entries = MyAppWeb.Shell.searchable(actor)

      AshA2ui.Shell.Search.find(term, entries, actor: actor, tenant: tenant)
      #=> %{hits: [%{key: :contracts, id: "...", field: :number, path: "/app/r/contracts/...", entry: entry}],
      #     failed: []}

  ## What it does

    * A blank term (or `nil`) reads nothing.
    * The term is cast to each field's Ash type first
      (`Ash.Type.cast_input/3`), and compared only with the fields it casts
      to. A licence number never reaches a UUID column, and a UUID is never
      compared with a name.
    * Each entry is one read of its resource on its primary read action, an
      OR of the matching fields, limited, with `read_opts` (`actor:`,
      `tenant:`, ...) passed to `Ash.read/2` as they are. The read is
      authorized as the actor, so a record they may not read is not found,
      and a read the policies forbid outright finds nothing.
    * An entry whose read errors or raises (a field the resource does not
      have, a data layer failure) is reported in `failed`, never folded into
      "no match": a search that could not look somewhere says so. The other
      entries still answer.

  A hit's `path` comes from the entry and is a deep link, so the host
  re-authorizes the record when it is opened. A search result is never
  trusted on its own.

  The host decides what is searchable, who may search it, and what a hit
  opens; this module only casts, reads and reports.
  """

  alias Ash.Resource.Info

  @default_limit 10

  @typedoc """
  One searchable surface, as the host lists it.

    * `key` — the surface's key, echoed in each hit;
    * `resource` — the Ash resource to read;
    * `fields` — the attributes of `resource` that identify one record to a
      person;
    * `path` — the deep link for a record id (`fn id -> "/app/r/contracts/" <> id end`).

  Any other keys are kept, and come back in the hit's `entry` (a host puts
  its own surface struct there, say).
  """
  @type entry :: %{
          required(:key) => term(),
          required(:resource) => module(),
          required(:fields) => [atom()],
          required(:path) => (String.t() -> String.t()),
          optional(atom()) => term()
        }

  @typedoc "One record found: the entry it was found in, its id, the field that matched, its deep link."
  @type hit :: %{
          key: term(),
          id: String.t(),
          field: atom(),
          path: String.t(),
          entry: entry()
        }

  @type result :: %{hits: [hit()], failed: [entry()]}

  @doc """
  The records `term` identifies across `entries`, read with `read_opts`.
  Records are identified by their `id`.

  `read_opts` go to `Ash.read/2` (`actor:`, `tenant:`, ...), except
  `limit:`, the most records read per entry (default #{@default_limit}).
  """
  @spec find(String.t() | nil, [entry()], keyword()) :: result()
  def find(term, entries, read_opts \\ [])

  def find(term, entries, read_opts) when is_binary(term) do
    case String.trim(term) do
      "" ->
        %{hits: [], failed: []}

      term ->
        {limit, read_opts} = Keyword.pop(read_opts, :limit, @default_limit)

        entries
        |> Enum.map(&{&1, look_up(&1, term, limit, read_opts)})
        |> Enum.reduce(%{hits: [], failed: []}, fn
          {_entry, {:ok, hits}}, acc -> %{acc | hits: acc.hits ++ hits}
          {entry, :error}, acc -> %{acc | failed: acc.failed ++ [entry]}
        end)
    end
  end

  def find(_term, _entries, _read_opts), do: %{hits: [], failed: []}

  defp look_up(%{fields: fields} = entry, term, limit, read_opts) do
    case matchable(entry.resource, fields, term) do
      [] -> {:ok, []}
      matches -> read(entry, matches, limit, read_opts)
    end
  rescue
    _error -> :error
  end

  # Each field the term casts to, with the cast value. A field the resource
  # does not have is an error in the host's list, not a miss.
  defp matchable(resource, fields, term) do
    for field <- fields,
        attribute = attribute!(resource, field),
        {:ok, value} when not is_nil(value) <-
          [Ash.Type.cast_input(attribute.type, term, attribute.constraints)],
        do: {field, value}
  end

  defp attribute!(resource, field) do
    Info.attribute(resource, field) ||
      raise ArgumentError, "#{inspect(resource)} has no attribute #{inspect(field)}"
  end

  defp read(entry, matches, limit, read_opts) do
    filter = [or: Enum.map(matches, fn {field, value} -> [{field, value}] end)]

    entry.resource
    |> Ash.Query.do_filter(filter)
    |> Ash.Query.limit(limit)
    |> Ash.read(read_opts)
    |> case do
      {:ok, records} -> {:ok, Enum.map(records, &hit(entry, &1, matches))}
      # Nothing there is the actor's to read: an answer, not a failure.
      {:error, %Ash.Error.Forbidden{}} -> {:ok, []}
      {:error, _error} -> :error
    end
  end

  defp hit(entry, record, matches) do
    id = to_string(record.id)

    %{
      key: entry.key,
      id: id,
      field: matched_field(record, matches),
      path: entry.path.(id),
      entry: entry
    }
  end

  defp matched_field(record, [{first, _value} | _] = matches) do
    Enum.find_value(matches, first, fn {field, value} ->
      Map.get(record, field) == value && field
    end)
  end
end
