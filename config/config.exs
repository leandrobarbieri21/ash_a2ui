import Config

# ash 3.33 requires an explicit string-length counting mode whenever any
# resource declares `min_length`/`max_length` on a string (our test fixtures
# do). Codepoints matches how SQL data layers count, so validation agrees
# with stored-value bounds. Host applications consuming this library must set
# this for their own resources too.
config :ash, default_string_length_count: :codepoints

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [],
    "AshA2ui.Standalone": []
  ]

if Mix.env() == :dev do
  config :git_ops,
    mix_project: AshA2ui.MixProject,
    github_handle_lookup?: true,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/lukegalea/ash_a2ui",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
    version_tag_prefix: "v"
end

if Mix.env() == :test do
  config :ash, :validate_domain_resource_inclusion?, false
  config :ash, :validate_domain_config_inclusion?, false

  # SchemaHelper resolves the A2UI spec's cross-file $refs from the vendored
  # copies in priv/a2ui/v0_9_1 instead of the network.
  config :ex_json_schema, :remote_schema_resolver, {AshA2ui.Test.SchemaHelper, :resolve_remote}

  config :logger, level: :warning

  # The calendar time zone tests cut days in real zones (America/Toronto,
  # America/Santiago); the calendar default stays Etc/UTC.
  config :elixir, :time_zone_database, Tz.TimeZoneDatabase

  # JUnit XML output for mix test — the evidence artifact .sdlc/verification.yaml
  # declares (report.path: test/reports/junit/*.xml). junit_formatter writes
  # the report at the end of every run, creating the directory if missing.
  config :junit_formatter,
    report_dir: "test/reports/junit",
    report_file: "junit_report.xml",
    automatic_create_dir?: true,
    print_report_file: true,
    # Adds file= to each testcase so a report entry traces back to the
    # acceptance file's `test: path::name` reference.
    include_filename?: true

  # Minimal Phoenix endpoint used only by (future) LiveRenderer tests.
  # Skipped when the Phoenix stack is excluded (NO_PHOENIX=1, see mix.exs):
  # the endpoint module is never compiled or started in that case, and
  # configuring the missing :phoenix app would warn.
  if is_nil(System.get_env("NO_PHOENIX")) do
    config :ash_a2ui, AshA2ui.Test.Endpoint,
      url: [host: "localhost", port: 4002],
      secret_key_base: String.duplicate("a", 64),
      live_view: [signing_salt: "aaaaaaaaaaaaaaaa"],
      render_errors: [
        formats: [html: AshA2ui.Test.ErrorHTML],
        layout: false
      ],
      check_origin: false,
      server: false,
      pubsub_server: AshA2ui.Test.PubSub

    config :phoenix, :json_library, Jason
  end
end
