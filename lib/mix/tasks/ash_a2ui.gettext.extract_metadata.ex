defmodule Mix.Tasks.AshA2ui.Gettext.ExtractMetadata do
  @moduledoc """
  Extracts your application's A2UI display metadata into a `.pot` (Portable
  Object Template) file, `priv/gettext/a2ui_metadata.pot` by default.

  Display metadata is the text your surfaces show that you own: declared
  labels and the labels ash_a2ui humanizes from field, action and component
  names: headings, columns, fields, actions, contexts, groups and steps;
  enum and `one_of` choice labels (under a `msgctxt`), column help, row
  icon, detail and badge text, descriptions, placeholders and filter hints,
  empty states, query presets, board lane headings and canvas registry
  labels. ash_a2ui's own strings ship separately, in the catalog
  `mix ash_a2ui.gen.gettext` copies.

  The task resolves and renders every surface of the current application
  (`AshA2ui.Gettext.Metadata.surfaces/1`: its resources that use the
  `AshA2ui` extension, and its `AshA2ui.Standalone` UI modules) with the
  same code that runs at request
  time, and records every label it looks up. The msgids are exactly the
  labels a reader sees. No data is read and no application is started.

  ## Usage

      $ mix ash_a2ui.gettext.extract_metadata
      $ mix ash_a2ui.gettext.extract_metadata --check-up-to-date

  ## Options

    * `--output` / `-o` — the `.pot` path. Defaults to
      `priv/gettext/a2ui_metadata.pot`. Its basename is the domain: pass
      the same name as the `:metadata_domain` option when it is not the
      default.
    * `--check-up-to-date` — write nothing; fail when the file differs from
      what extraction would write (for CI).

  ## Workflow

  1. Run `mix ash_a2ui.gettext.extract_metadata` and commit the `.pot`.
  2. Run `mix gettext.merge priv/gettext --locale fr` and fill in the
     `msgstr`s of `fr/LC_MESSAGES/a2ui_metadata.po`.
  3. Pass `gettext_backend:` and `locale:` when building surfaces; labels
     are looked up in the `a2ui_metadata` domain (see `AshA2ui.L10n`).

  Re-run it whenever a surface changes, and add `--check-up-to-date` to CI.
  References name each surface's source file, without a line number.
  """

  use Mix.Task

  alias AshA2ui.Gettext.Metadata

  @shortdoc "Extracts your A2UI surfaces' display labels into a .pot file"

  @default_output "priv/gettext/a2ui_metadata.pot"

  @impl Mix.Task
  def run(argv) do
    {opts, _} =
      OptionParser.parse!(argv,
        strict: [output: :string, check_up_to_date: :boolean],
        aliases: [o: :output]
      )

    Mix.Task.run("app.config")

    app = Mix.Project.config()[:app]
    Application.load(app)

    output = Keyword.get(opts, :output, @default_output)
    domain = Path.basename(output, ".pot")
    messages = app |> Metadata.surfaces() |> Metadata.messages()
    content = Metadata.pot(messages, domain)

    if opts[:check_up_to_date] do
      if File.read(output) != {:ok, content} do
        Mix.raise(
          "#{output} is out of date. Run `mix ash_a2ui.gettext.extract_metadata` and commit it."
        )
      end

      Mix.shell().info("#{output} is up to date.")
    else
      output |> Path.dirname() |> File.mkdir_p!()
      File.write!(output, content)

      Mix.shell().info([:green, "* creating ", :reset, output])
      Mix.shell().info("  #{map_size(messages)} unique message(s) written.")
    end
  end
end
