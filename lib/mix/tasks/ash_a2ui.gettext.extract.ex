defmodule Mix.Tasks.AshA2ui.Gettext.Extract do
  @moduledoc """
  Extracts ash_a2ui's library-owned strings into a `.pot` (Portable Object
  Template) file.

  Scans `lib/**/*.ex` for `AshA2ui.Gettext.msg/1` calls with a string
  literal and writes each unique msgid once, with the files it appears in as
  gettext source references.

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
      |> Enum.map_join("\n", fn {msgid, files} -> pot_entry(msgid, files) end)

    pot_header() <> entries
  end

  @doc """
  Every marked msgid under `root`, mapped to the sorted, unique list of
  files (relative to `root`) it appears in.
  """
  @spec extract_messages(Path.t()) :: %{String.t() => [String.t()]}
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
      |> Enum.reduce(acc, fn msgid, acc ->
        Map.update(acc, msgid, [file], &Enum.uniq(&1 ++ [file]))
      end)
    end)
  end

  defp msgids(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:msg, _meta, [msgid]} = node, acc when is_binary(msgid) ->
          {node, [msgid | acc]}

        {{:., _, [{:__aliases__, _, [:AshA2ui, :Gettext]}, :msg]}, _meta, [msgid]} = node, acc
        when is_binary(msgid) ->
          {node, [msgid | acc]}

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

  defp pot_entry(msgid, files) do
    """
    #{Enum.map_join(files, "\n", &"#: #{&1}")}
    msgid #{inspect(msgid)}
    msgstr ""
    """
  end
end
