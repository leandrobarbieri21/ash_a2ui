defmodule AshA2ui.Shell do
  @moduledoc """
  The command shell: a command palette, a surface launcher and `/open`, as
  data. One key table, one slash grammar and one way to list what is on
  offer, shared by every transport that draws them.

  This module is the pure half and needs no Phoenix. The LiveView half,
  `AshA2ui.Shell.Component`, draws it in a page; a terminal client can route
  the same lines the same way.

  ## What the shell is fed

  The host supplies two lists, in the ACP wire shapes, so a web page and an
  ACP client offer the same things from the same source:

    * **commands** — ACP `AvailableCommand` maps, as an agent sends them in
      `available_commands_update`:
      `%{"name" => "calendar", "description" => "...", "input" => %{"hint" => "today | week"}}`.
      `input` is optional; a command with a hint takes an argument.
    * **surfaces** — `SurfaceEntry` maps, as `_ash/surfaces/list` returns
      them: `%{"id" => "calendar", "title" => "Calendar", "group" => "My day",
      "description" => "..."}`.

  Both lists are what the person may use. The shell filters and routes; it
  never widens. A host that lists a surface the person cannot open has a
  bug the shell cannot fix, so build the lists from the same doors and
  policies the transports enforce.

  ## Keys

  `keys/0` is the key table: `ctrl+p` opens the palette and `ctrl+k` the
  launcher. The JS hook reads it from the component, so there is no second
  copy in the browser.

  ## Lines

  `route/2` turns one typed line into an invocation:

  | Line | Invocation |
  |---|---|
  | `what is on today` (no leading slash) | `{:prompt, "what is on today"}` — the agent gets it |
  | `/open calendar`, `/open people 3`, `/open people <id>` | `{:open_surface, entry, target}` |
  | `/open`, `/home` | `:launcher` |
  | `/calendar week` (a command's name) | `{:command, command, ["week"]}` |
  | `/agent` (a surface's id or title, unique prefix allowed) | `{:open_surface, entry, nil}` |
  | anything else after a slash | `{:error, message}` |

  A target is `nil`, `{:nth, n}` (a positive integer: the `n`th row) or
  `{:record, id}`.
  """

  @typedoc "An ACP `AvailableCommand` map."
  @type command :: %{required(String.t()) => term()}

  @typedoc "A `SurfaceEntry` map (`_ash/surfaces/list`)."
  @type surface :: %{required(String.t()) => term()}

  @typedoc "What the shell offers: the host's commands and surfaces."
  @type entries :: %{commands: [command()], surfaces: [surface()]}

  @type target :: nil | {:nth, pos_integer()} | {:record, String.t()}

  @type invocation ::
          {:prompt, String.t()}
          | {:open_surface, surface(), target()}
          | {:command, command(), [String.t()]}
          | :launcher

  @type mode :: :palette | :launcher

  @typedoc """
  One row in the palette or launcher. `action` is what choosing it does:
  hand the host an invocation, put text in the input to finish, switch
  mode, or nothing (an explanation).
  """
  @type item :: %{
          required(:label) => String.t(),
          required(:group) => String.t(),
          required(:action) =>
            {:invoke, invocation()} | {:complete, String.t()} | {:mode, mode()} | :none,
          optional(:detail) => String.t() | nil,
          optional(:hint) => String.t() | nil
        }

  @keys %{"ctrl+p" => :palette, "ctrl+k" => :launcher}

  # Slash commands the shell itself answers, before the host's commands.
  @builtins %{"open" => :open, "home" => :launcher}

  @doc "The key table: key label → mode."
  @spec keys() :: %{String.t() => mode()}
  def keys, do: @keys

  @doc "The key label that opens `mode` (`\"ctrl+k\"`), or `nil`."
  @spec key_for(mode(), %{String.t() => mode()}) :: String.t() | nil
  def key_for(mode, keys \\ @keys) do
    Enum.find_value(keys, fn {key, m} -> if m == mode, do: key end)
  end

  @doc "The slash commands the shell answers itself (`open`, `home`)."
  @spec builtins() :: [String.t()]
  def builtins, do: @builtins |> Map.keys() |> Enum.sort()

  # -- routing -----------------------------------------------------------------

  @doc """
  Route one typed line (see the table in the moduledoc). `nil` for a blank
  line.
  """
  @spec route(String.t(), entries()) :: invocation() | {:error, String.t()} | nil
  def route(line, entries) when is_binary(line) do
    case String.trim(line) do
      "" -> nil
      "/" <> rest -> route_slash(String.trim(rest), entries)
      text -> {:prompt, text}
    end
  end

  defp route_slash("", _entries), do: nil

  defp route_slash(rest, entries) do
    [name | args] = String.split(rest)

    case Map.get(@builtins, String.downcase(name)) do
      :open -> open_args(args, entries)
      :launcher -> :launcher
      nil -> route_named(name, rest, entries)
    end
  end

  # A host command by name, else a surface named directly (`/agent` is
  # `/open agent`).
  defp route_named(name, rest, entries) do
    with nil <- match_command(rest, commands(entries)),
         {:error, _no_surface} <- open_args(String.split(rest), entries) do
      {:error, "There is no /#{name} command. Press ctrl+p to see them."}
    else
      {command, args} when is_map(command) -> {:command, command, args}
      {:open_surface, _entry, _target} = open -> open
    end
  end

  # `/open [surface words…] [id | n]`: the longest run of leading words that
  # names one surface, then an optional target.
  defp open_args([], _entries), do: :launcher

  defp open_args(args, entries) do
    surfaces = surfaces(entries)

    found =
      Enum.find_value(length(args)..1//-1, fn take ->
        {name, rest} = Enum.split(args, take)

        case find_surface(Enum.join(name, " "), surfaces) do
          nil -> nil
          entry -> {entry, rest}
        end
      end)

    case found do
      {entry, []} -> {:open_surface, entry, nil}
      {entry, [target]} -> {:open_surface, entry, target(target)}
      {_entry, _extra} -> {:error, "Use /open <surface> [id | n]."}
      nil -> {:error, "There is no #{Enum.join(args, " ")} surface. Press ctrl+k to see yours."}
    end
  end

  @doc """
  The surface `name` names: by id or title (case, spaces, dashes and
  underscores ignored), else by a prefix of either that only one surface
  has. `nil` when there is none or the prefix is ambiguous.
  """
  @spec find_surface(String.t(), [surface()]) :: surface() | nil
  def find_surface(name, surfaces) do
    needle = normalize(name)

    cond do
      needle == "" -> nil
      exact = Enum.find(surfaces, &(needle in names(&1))) -> exact
      true -> unique_prefix(surfaces, needle)
    end
  end

  defp unique_prefix(surfaces, needle) do
    case Enum.filter(surfaces, &prefix?(&1, needle)) do
      [entry] -> entry
      _none_or_many -> nil
    end
  end

  defp prefix?(surface, needle), do: Enum.any?(names(surface), &String.starts_with?(&1, needle))

  defp names(surface), do: Enum.map([surface["id"], surface["title"]], &normalize/1)

  defp normalize(nil), do: ""

  defp normalize(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[\s_-]+/, "_")
    |> String.trim("_")
  end

  @doc "`\"3\"` is `{:nth, 3}`; any other non-blank text is `{:record, text}`."
  @spec target(String.t()) :: target()
  def target(text) do
    case Integer.parse(text) do
      {n, ""} when n > 0 -> {:nth, n}
      _other -> {:record, text}
    end
  end

  # The longest command name the text is, or starts with at a word boundary.
  defp match_command(text, commands) do
    lowered = String.downcase(text)

    commands
    |> Enum.filter(fn command ->
      name = String.downcase(command["name"])
      lowered == name or String.starts_with?(lowered, name <> " ")
    end)
    |> Enum.max_by(&String.length(&1["name"]), fn -> nil end)
    |> case do
      nil ->
        nil

      command ->
        rest = text |> String.slice(String.length(command["name"])..-1//1) |> String.split()
        {command, rest}
    end
  end

  # -- what the palette and launcher list ----------------------------------------

  @doc """
  The surfaces matching `needle` (a case-insensitive substring of title, id,
  group or description), in their given order. A blank needle matches all.
  """
  @spec filter_surfaces([surface()], String.t()) :: [surface()]
  def filter_surfaces(surfaces, needle) do
    needle = needle |> to_string() |> String.trim() |> String.downcase()

    if needle == "" do
      surfaces
    else
      Enum.filter(surfaces, fn s ->
        [s["title"], s["id"], s["group"], s["description"]]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
        |> String.downcase()
        |> String.contains?(needle)
      end)
    end
  end

  @doc "The commands matching `needle` (a substring of name or description)."
  @spec filter_commands([command()], String.t()) :: [command()]
  def filter_commands(commands, needle) do
    needle = needle |> to_string() |> String.trim() |> String.downcase()

    if needle == "" do
      commands
    else
      Enum.filter(commands, fn c ->
        String.contains?(String.downcase("#{c["name"]} #{c["description"]}"), needle)
      end)
    end
  end

  @doc """
  The rows to show for `query` in `mode`.

    * **launcher** — the surfaces matching the query, grouped by their
      `group`. A slash line is routed as in the palette.
    * **palette**, plain text — the matching commands, then the matching
      surfaces, then *Ask the agent* with the text. With no text, the
      launcher's own row leads.
    * **palette**, a slash line — what the line runs, when it routes, then
      the slash names it could be completing.
  """
  @spec items(mode(), String.t(), entries()) :: [item()]
  def items(:launcher, query, entries) do
    case String.trim(query) do
      "/" <> _slash = line ->
        slash_items(line, entries)

      text ->
        entries
        |> surfaces()
        |> filter_surfaces(text)
        |> Enum.map(&surface_item(&1, &1["group"] || "Surfaces"))
    end
  end

  def items(:palette, query, entries) do
    case String.trim(query) do
      "/" <> _slash = line ->
        slash_items(line, entries)

      "" ->
        [launcher_item() | command_items(commands(entries))] ++ surface_items(surfaces(entries))

      text ->
        command_items(filter_commands(commands(entries), text)) ++
          surface_items(filter_surfaces(surfaces(entries), text)) ++ [prompt_item(text)]
    end
  end

  defp slash_items(line, entries) do
    routed =
      case route(line, entries) do
        nil ->
          []

        {:error, message} ->
          [%{label: message, group: "Run", action: :none}]

        invocation ->
          [
            %{
              label: describe(invocation),
              detail: line,
              group: "Run",
              action: {:invoke, invocation}
            }
          ]
      end

    routed ++ completions(line, entries)
  end

  # Slash names the first word could be completing, unless the line already
  # carries arguments.
  defp completions(line, entries) do
    case String.split(String.trim_leading(line, "/"), " ", parts: 2) do
      [word] ->
        word = String.downcase(word)

        builtins =
          for name <- builtins(), String.starts_with?(name, word) do
            %{
              label: "/#{name}",
              detail: builtin_detail(name),
              hint: if(name == "open", do: "<surface> [id | n]"),
              group: "Shell",
              action: {:complete, "/#{name} "}
            }
          end

        commands =
          for c <- commands(entries), String.starts_with?(String.downcase(c["name"]), word) do
            command_item(c)
          end

        surfaces =
          for s <- surfaces(entries),
              Enum.any?(names(s), &String.starts_with?(&1, normalize(word))) do
            surface_item(s, "Surfaces")
          end

        builtins ++ commands ++ surfaces

      _with_arguments ->
        []
    end
  end

  defp builtin_detail("open"), do: "Open a surface by name, with a record id or a row number"
  defp builtin_detail("home"), do: "Open the surface launcher"

  defp launcher_item do
    %{
      label: "Open a surface…",
      detail: "Every surface you can open",
      hint: key_for(:launcher),
      group: "Shell",
      action: {:mode, :launcher}
    }
  end

  defp command_items(commands), do: Enum.map(commands, &command_item/1)

  defp command_item(command) do
    hint = get_in(command, ["input", "hint"])

    %{
      label: "/" <> command["name"],
      detail: command["description"],
      hint: hint,
      group: "Commands",
      # A command that takes an argument goes in the input to finish.
      action:
        if(hint,
          do: {:complete, "/#{command["name"]} "},
          else: {:invoke, {:command, command, []}}
        )
    }
  end

  defp surface_items(surfaces), do: Enum.map(surfaces, &surface_item(&1, "Surfaces"))

  defp surface_item(surface, group) do
    %{
      label: surface["title"],
      detail: surface["description"],
      group: group,
      action: {:invoke, {:open_surface, surface, nil}}
    }
  end

  defp prompt_item(text) do
    %{label: "Ask the agent", detail: text, group: "Agent", action: {:invoke, {:prompt, text}}}
  end

  @doc "A one-line description of what an invocation does."
  @spec describe(invocation()) :: String.t()
  def describe({:prompt, text}), do: "Ask the agent: #{text}"
  def describe(:launcher), do: "Open a surface…"
  def describe({:open_surface, entry, nil}), do: "Open #{entry["title"]}"
  def describe({:open_surface, entry, {:nth, n}}), do: "Open #{entry["title"]}, row #{n}"
  def describe({:open_surface, entry, {:record, id}}), do: "Open #{entry["title"]}, record #{id}"

  def describe({:command, command, args}),
    do: Enum.join(["/" <> command["name"] | args], " ")

  defp commands(entries), do: Map.get(entries, :commands, [])
  defp surfaces(entries), do: Map.get(entries, :surfaces, [])
end
