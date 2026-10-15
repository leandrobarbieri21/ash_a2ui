defmodule AshA2ui.MixProject do
  use Mix.Project

  @version "0.1.0"

  @description """
  An Ash extension that generates A2UI (Agent to UI) v0.9.1 payloads from Ash resources.
  """

  def project do
    [
      app: :ash_a2ui,
      version: @version,
      elixir: "~> 1.15",
      # NO_PHOENIX builds compile a different dep set (the whole Phoenix
      # stack is stripped), so they must not share _build with normal builds:
      # a shared build dir leaves an orphaned .app referencing bandit and
      # breaks whichever mode runs second. Isolate them instead.
      build_path: (System.get_env("NO_PHOENIX") && "_build_no_phoenix") || "_build",
      start_permanent: Mix.env() == :prod,
      package: package(),
      aliases: aliases(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [plt_add_apps: [:ash, :mix]],
      docs: &docs/0,
      description: @description,
      source_url: "https://github.com/lukegalea/ash_a2ui",
      homepage_url: "https://github.com/lukegalea/ash_a2ui",
      consolidate_protocols: Mix.env() != :test
    ]
  end

  defp package do
    [
      name: :ash_a2ui,
      maintainers: [
        "Luke Galea"
      ],
      licenses: ["MIT"],
      files: ~w(lib priv .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* documentation usage-rules.md usage-rules),
      links: %{
        "GitHub" => "https://github.com/lukegalea/ash_a2ui",
        "Changelog" => "https://github.com/lukegalea/ash_a2ui/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp elixirc_paths(:test) do
    elixirc_paths(:dev) ++ ["test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extra_section: "GUIDES",
      before_closing_head_tag: fn type ->
        if type == :html do
          """
          <script>
            if (location.hostname === "hexdocs.pm") {
              var script = document.createElement("script");
              script.src = "https://plausible.io/js/script.js";
              script.setAttribute("defer", "defer")
              script.setAttribute("data-domain", "ashhexdocs")
              document.head.appendChild(script);
            }
          </script>
          """
        end
      end,
      before_closing_body_tag: fn
        :html ->
          """
          <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
          <script>mermaid.initialize({startOnLoad: true})</script>
          """

        _ ->
          ""
      end,
      extras: [
        {"README.md", title: "Home"},
        "documentation/tutorials/getting-started-with-ash-a2ui.md",
        "documentation/topics/what-is-ash-a2ui.md",
        "documentation/topics/a2ui-1-0.md",
        "documentation/topics/rendering-clients.md",
        "documentation/topics/external-transports.md",
        "documentation/topics/theming.md",
        "documentation/topics/actions-and-authorization.md",
        "documentation/topics/queries-and-pagination.md",
        "documentation/topics/multi-section-surfaces.md",
        "documentation/topics/reports-and-exports.md",
        "documentation/topics/bulk-actions.md",
        "documentation/topics/contexts-and-details.md",
        "documentation/topics/agent-composed-surfaces.md",
        "documentation/topics/relationships.md",
        "documentation/topics/layout.md",
        "documentation/topics/data-model-conventions.md",
        {"documentation/dsls/DSL-AshA2ui.md", search_data: Spark.Docs.search_data_for(AshA2ui)},
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r'documentation/tutorials',
        "How To": ~r'documentation/how_to',
        Topics: ~r'documentation/topics',
        DSLs: ~r'documentation/dsls',
        "About AshA2ui": [
          "CHANGELOG.md"
        ]
      ],
      groups_for_modules: [
        Dsl: [
          AshA2ui,
          AshA2ui.Standalone
        ],
        Introspection: [
          AshA2ui.Info,
          AshA2ui.ResolvedView,
          AshA2ui.Component,
          AshA2ui.Field,
          AshA2ui.Query,
          AshA2ui.Action,
          AshA2ui.Sections,
          AshA2ui.Board,
          AshA2ui.Editable,
          AshA2ui.Export
        ],
        Encoding: [
          AshA2ui.Encoder,
          AshA2ui.Encoder.V0_9_1,
          AshA2ui.Encoder.V1_0,
          AshA2ui.TypeMapper
        ],
        Actions: [
          AshA2ui.ActionHandler,
          AshA2ui.QueryRunner,
          AshA2ui.Csv
        ],
        "LiveView Transport": [
          AshA2ui.LiveRenderer,
          AshA2ui.Presence,
          AshA2ui.PresenceBar,
          AshA2ui.Combobox,
          AshA2ui.Web.ComposerLive
        ],
        "External Transports": [
          AshA2ui.AgUi
        ],
        Internals: ~r/.*/
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.0"},
      # State-machine introspection for the canvas graph (A2UI-102) — strictly
      # optional, exactly like phoenix_live_view below: the canvas
      # introspects AshStateMachine resources only when the extension is
      # loaded and omits the state-machine sub-entity (documented
      # degradation) otherwise.
      {:ash_state_machine, "~> 0.2", optional: true},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:simple_sat, "~> 0.1", only: [:dev, :test], runtime: false},
      {:ex_json_schema, "~> 0.10", only: [:dev, :test]},
      # no :only — reactor (via ash) requires jason in all envs anyway
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.36", only: [:dev, :test]},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      # Emits the JUnit XML evidence artifact that .sdlc/verification.yaml
      # declares (report.path: test/reports/junit/*.xml). Wired up in
      # test/test_helper.exs; uploaded as a CI artifact by
      # .github/workflows/elixir.yml.
      {:junit_formatter, "~> 3.3", only: :test}
    ] ++ phoenix_deps()
  end

  # `phoenix_live_view` is a strictly optional runtime dependency: the protocol
  # core (DSL -> ResolvedView -> Encoder -> ActionHandler) depends only on `ash`.
  # `AshA2ui.LiveRenderer` and the Phoenix test endpoint are wrapped in
  # `Code.ensure_loaded?(Phoenix.LiveView)` guards so they simply vanish when
  # Phoenix isn't present.
  #
  # CI proves this with a dedicated matrix job that sets NO_PHOENIX=1, which
  # strips the whole Phoenix stack from the dep list before `mix deps.get`.
  # This is the simplest reliable mechanism: no lockfile surgery, no separate
  # mix project. (Running `mix deps.get` with NO_PHOENIX=1 locally will prune
  # the Phoenix entries from mix.lock — don't commit that; it is intended for
  # the throwaway CI checkout only.)
  defp phoenix_deps do
    if System.get_env("NO_PHOENIX") do
      []
    else
      [
        # phoenix itself comes in transitively (phoenix_live_view requires it
        # in all envs, so an :only-restricted explicit entry would conflict)
        {:phoenix_live_view, "~> 1.0", optional: true},
        {:bandit, "~> 1.0", only: [:dev, :test]},
        # required by Phoenix.LiveViewTest (live_renderer_test.exs)
        {:lazy_html, ">= 0.1.0", only: [:dev, :test]}
      ]
    end
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      "spark.formatter": "spark.formatter --extensions AshA2ui",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshA2ui",
      "spark.cheat_sheets_in_search": "spark.cheat_sheets_in_search --extensions AshA2ui"
    ]
  end
end
