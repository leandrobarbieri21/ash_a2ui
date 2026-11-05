defmodule Mix.Tasks.AshA2ui.Gen.Gettext do
  @moduledoc """
  Copies ash_a2ui's `.pot` file into your application's `priv/gettext/`
  directory, so you can translate the library's own interface strings (button
  labels, pagination text, action feedback) with the standard gettext workflow.

  ## Usage

      $ mix ash_a2ui.gen.gettext
      $ mix ash_a2ui.gen.gettext --domain default

  ## Options

    * `--domain` / `-d` — target gettext domain. Defaults to `"ash_a2ui"`.

      With any other domain, ash_a2ui's messages are **merged** into the
      existing `priv/gettext/<domain>.pot`, after the marker comment
      `## -- ash_a2ui-gettext:start --`. The section is replaced on each run,
      so the task is idempotent, and it stops at the next library's marker,
      so it coexists with sections written by `mix ash.gen.gettext`.

  ## Workflow

  1. Run `mix ash_a2ui.gen.gettext`.
  2. Run `mix gettext.merge priv/gettext --locale fr` to create
     `priv/gettext/fr/LC_MESSAGES/ash_a2ui.po`.
  3. Fill in the `msgstr` values.
  4. Pass `gettext_backend: {MyAppWeb.Gettext, "ash_a2ui"}` and an explicit
     `locale:` when building surfaces and dispatching actions. See the
     "Localizing ash_a2ui" section of the README.

  Re-run step 1 after upgrading ash_a2ui, then `mix gettext.merge` again.
  """

  use Mix.Task

  @shortdoc "Copies ash_a2ui's .pot file for interface translation"

  @default_domain "ash_a2ui"
  @marker "## -- ash_a2ui-gettext:start --"
  @marker_pattern ~r/^## -- [\w]+-gettext:start --$/m
  @domain_regex ~r/^[a-z][a-z0-9_]*$/

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      OptionParser.parse!(argv,
        strict: [domain: :string, source: :string, output_dir: :string],
        aliases: [d: :domain]
      )

    domain = Keyword.get(opts, :domain, @default_domain)

    if not Regex.match?(@domain_regex, domain) do
      Mix.raise(
        "Invalid domain #{inspect(domain)}. Must be lowercase alphanumeric with underscores."
      )
    end

    source = Keyword.get_lazy(opts, :source, &default_source/0)

    if !File.exists?(source) do
      Mix.raise("Could not find #{source}. Run `mix ash_a2ui.gettext.extract` in ash_a2ui first.")
    end

    dest_dir = Keyword.get(opts, :output_dir, "priv/gettext")
    dest = Path.join(dest_dir, "#{domain}.pot")
    File.mkdir_p!(dest_dir)

    if domain == @default_domain do
      File.cp!(source, dest)
      Mix.shell().info([:green, "* creating ", :reset, dest])
    else
      block = build_block(source)

      content =
        case File.read(dest) do
          {:ok, existing} -> merge_into_existing(existing, block)
          {:error, :enoent} -> pot_header(domain) <> block
          {:error, reason} -> Mix.raise("Could not read #{dest}: #{inspect(reason)}")
        end

      File.write!(dest, content)
      Mix.shell().info([:green, "* updating ", :reset, dest])
    end
  end

  defp default_source, do: Application.app_dir(:ash_a2ui, "priv/gettext/ash_a2ui.pot")

  defp build_block(source) do
    entries =
      source
      |> File.read!()
      |> String.split("\n\n")
      |> Enum.filter(&String.contains?(&1, "msgid \""))
      |> Enum.reject(&(&1 =~ ~r/^msgid ""$/m))
      |> Enum.map_join("\n\n", &String.trim/1)

    @marker <> "\n" <> entries <> "\n\n"
  end

  defp merge_into_existing(existing, block) do
    if String.contains?(existing, @marker) do
      [before, rest] = String.split(existing, @marker, parts: 2)

      after_block =
        case Regex.run(@marker_pattern, rest, return: :index) do
          [{pos, _len}] -> binary_part(rest, pos, byte_size(rest) - pos)
          nil -> ""
        end

      String.trim_trailing(before) <> "\n\n" <> block <> after_block
    else
      String.trim_trailing(existing) <> "\n\n" <> block
    end
  end

  defp pot_header(domain) do
    """
    ## This file is a PO Template file.
    ##
    ## Run `mix gettext.merge priv/gettext --locale LOCALE` to merge into a .po file.
    msgid ""
    msgstr ""
    "Content-Type: text/plain; charset=UTF-8\\n"
    "Content-Transfer-Encoding: 8bit\\n"
    "Domain: #{domain}\\n"

    """
  end
end
