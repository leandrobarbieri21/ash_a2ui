defmodule Mix.Tasks.AshA2ui.Gettext.Extract do
  @moduledoc """
  Extracts ash_a2ui's library-owned strings into a `.pot` (Portable Object
  Template) file.

  Scans `lib/**/*.ex` for `AshA2ui.Gettext.msg/1` and `msg_plural/2` calls
  with string literals and writes each unique msgid once (with its
  `msgid_plural` and two `msgstr` forms for a plural), with the files it
  appears in as gettext source references.

  ## Usage

      $ mix ash_a2ui.gettext.extract
      $ mix ash_a2ui.gettext.extract --check-up-to-date

  ## Options

    * `--output` / `-o` — the `.pot` path. Defaults to
      `priv/gettext/ash_a2ui.pot`.
    * `--check-up-to-date` — write nothing; fail when the file differs from
      what extraction would write (for CI).

  ## Workflow

  This task is for ash_a2ui development. It regenerates
  `priv/gettext/ash_a2ui.pot`, which ships in the Hex package. Applications
  run `mix ash_a2ui.gen.gettext` to copy it into their own `priv/gettext`.

  References name the file only, without a line number, so the template
  changes when a string does, not whenever code above it moves.
  """

  use Mix.Task

  @shortdoc "Extracts ash_a2ui's translatable strings into a .pot file"

  @default_output "priv/gettext/ash_a2ui.pot"
  @domain "ash_a2ui"

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      OptionParser.parse!(argv,
        strict: [output: :string, check_up_to_date: :boolean],
        aliases: [o: :output]
      )

    output = Keyword.get(opts, :output, @default_output)
    content = build_pot()

    if opts[:check_up_to_date] do
      if File.read(output) != {:ok, content} do
        Mix.raise("#{output} is out of date. Run `mix ash_a2ui.gettext.extract` and commit it.")
      end

      Mix.shell().info("#{output} is up to date.")
    else
      output |> Path.dirname() |> File.mkdir_p!()
      File.write!(output, content)

      Mix.shell().info([:green, "* creating ", :reset, output])
      Mix.shell().info("  #{content |> extract_count()} unique message(s) written.")
    end
  end

  @doc """
  The `.pot` content extraction writes, built from the sources under
  `root` (the project root by default).
  """
  @spec build_pot(Path.t()) :: String.t()
  def build_pot(root \\ File.cwd!()) do
    entries =
      root
      |> extract_messages()
      |> Enum.sort_by(fn {msgid, _files} -> msgid end)
      |> Enum.map_join("\n", fn {msgid, {plural, files}} -> pot_entry(msgid, plural, files) end)

    pot_header() <> entries
  end

  @doc """
  Every marked msgid under `root`, mapped to its `msgid_plural` (or `nil`)
  and the unique `file:line` references (files relative to `root`) it
  appears at, in source order.
  """
  @spec extract_messages(Path.t()) :: %{String.t() => {String.t() | nil, [String.t()]}}
  def extract_messages(root \\ File.cwd!()) do
    root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn path, acc ->
      file = Path.relative_to(path, root)

      path
      |> File.read!()
      |> Code.string_to_quoted!(file: file)
      |> msgids()
      |> Enum.reduce(acc, &add_message(&2, &1, file))
    end)
  end

  defp add_message(acc, {msgid, plural, line}, file) do
    reference = "#{file}:#{line}"

    Map.update(acc, msgid, {plural, [reference]}, fn {plural, references} ->
      {plural, Enum.uniq(references ++ [reference])}
    end)
  end

  defp msgids(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:msg, meta, [msgid]} = node, acc when is_binary(msgid) ->
          {node, [{msgid, nil, meta[:line]} | acc]}

        {:msg_plural, meta, [msgid, plural]} = node, acc
        when is_binary(msgid) and is_binary(plural) ->
          {node, [{msgid, plural, meta[:line]} | acc]}

        {{:., _, [{:__aliases__, _, [:AshA2ui, :Gettext]}, name]}, meta, args} = node, acc
        when name in [:msg, :msg_plural] ->
          case args do
            [msgid] when is_binary(msgid) ->
              {node, [{msgid, nil, meta[:line]} | acc]}

            [msgid, plural] when is_binary(msgid) and is_binary(plural) ->
              {node, [{msgid, plural, meta[:line]} | acc]}

            _dynamic ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp extract_count(content) do
    length(Regex.scan(~r/^msgid "./m, content))
  end

  defp pot_header do
    """
    ## This file is a PO Template file.
    ##
    ## `msgid`s here are extracted from ash_a2ui's source code.
    ##
    ## Run `mix ash_a2ui.gettext.extract` to refresh this file.
    ## Run `mix ash_a2ui.gen.gettext` in your app to copy this file.
    ## Run `mix gettext.merge priv/gettext --locale LOCALE` to merge into a .po file.
    msgid ""
    msgstr ""
    "Content-Type: text/plain; charset=UTF-8\\n"
    "Content-Transfer-Encoding: 8bit\\n"
    "Domain: #{@domain}\\n"

    """
  end

  defp pot_entry(msgid, nil, files) do
    """
    #{references(files)}
    msgid #{inspect(msgid)}
    msgstr ""
    """
  end

  defp pot_entry(msgid, plural, files) do
    """
    #{references(files)}
    msgid #{inspect(msgid)}
    msgid_plural #{inspect(plural)}
    msgstr[0] ""
    msgstr[1] ""
    """
  end

  defp references(files), do: Enum.map_join(files, "\n", &"#: #{&1}")
end
