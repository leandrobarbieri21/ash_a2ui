defmodule AshA2ui.L10n.MetadataRoutingTest do
  @moduledoc """
  Host display metadata beyond labels (enum choices, empty states, canvas
  registry labels, library chrome of the presence bar) goes through the
  translator once, in the right domain, and values and identifiers stay as
  they are. The protocol-wide goldens live in `pseudo_locale_test.exs`.
  """

  # async: false — the scenario builds flip the global :ash_a2ui :catalog env.
  use ExUnit.Case, async: false

  alias AshA2ui.Canvas.ObjectRef
  alias AshA2ui.Experience
  alias AshA2ui.L10n
  alias AshA2ui.ResolvedView
  alias AshA2ui.Sections
  alias AshA2ui.Test.BucketWordsUI
  alias AshA2ui.Test.DomainPseudoLocale
  alias AshA2ui.TypeMapper

  # A translator that translates nothing and reports each lookup.
  def record(msgid, _bindings, _locale, meta) do
    send(self(), {:looked_up, msgid, meta})
    nil
  end

  @pseudo [gettext_fn: {DomainPseudoLocale, :translate}, locale: "pseudo"]

  test "an enum's labels are translated under the enum's msgctxt; values are not" do
    l10n = L10n.new(gettext_fn: {__MODULE__, :record}, locale: "fr")

    assert [{:todo, "To Do"}, {:in_progress, "In Progress"}] =
             TypeMapper.choices(AshA2ui.Test.EnumRecord, :stage, l10n)

    assert_received {:looked_up, "To Do",
                     [domain: "a2ui_metadata", context: "enum:Elixir.AshA2ui.Test.Stage"]}

    # A `one_of` value has no enum module, so no msgctxt.
    TypeMapper.choices(AshA2ui.Test.HubContract, :status, l10n)
    assert_received {:looked_up, "Expired", [domain: "a2ui_metadata"]}
  end

  describe "pseudo-locale builds on both protocols" do
    alias AshA2ui.Test.L10nScenarios

    for spec <- ["v0_9_1", "v1_0"] do
      @spec_tag spec
      test "the admin hub shows every kind of host text translated once (#{spec})" do
        json = run("hub_build_#{@spec_tag}_admin")

        for text <-
              ~w(Property properties) ++
                ["Search contracts or vendors", "Expiring soon", "Ends soon", "Draft"] do
          assert json =~ ~s("⟪#{text}⟫"), "#{text} is not translated"
        end

        # Values and identifiers stay.
        assert json =~ ~s("value": "expiring_soon")
        refute json =~ "⟪expiring_soon⟫"
        refute json =~ "⟪⟪"
      end

      test "the no-results state and its clear action are translated (#{spec})" do
        json = run("hub_no_results_#{@spec_tag}_admin")

        assert json =~ ~s("⟪No results⟫")
        assert json =~ ~s("⟪Try other words or filters.⟫")
      end

      test "board lanes and enum labels are translated, enum values are not (#{spec})" do
        board = run("board_build_#{@spec_tag}_basic")
        assert board =~ "⟪To do⟫"
        assert board =~ "⟪Claimed⟫"
        refute board =~ "⟪claimed⟫"

        enum = run("enum_build_#{@spec_tag}_basic")
        assert enum =~ "⟪To Do⟫"
        assert enum =~ "⟪Very high⟫"
        assert enum =~ ~s("very_high")
      end
    end

    defp run(name) do
      L10nScenarios.run(L10nScenarios.scenario(name), @pseudo)
    end
  end

  test "a sectioned table's empty state names the records, not the runtime table name" do
    bucket = Ash.create!(AshA2ui.Test.Bucket, %{name: "Alpha"}, authorize?: false)
    view = ResolvedView.resolve(BucketWordsUI)
    expanded = Sections.expand!(view, authorize?: false)

    section =
      Enum.find(expanded.tables, &(Map.get(&1, :section) && &1.section.label == bucket.name))

    assert Experience.empty_message(expanded, section) == "No Bucket word records yet."
  end

  describe "canvas registry" do
    test "graph node labels are translated once and ids are not" do
      plain = AshA2ui.Canvas.build_graph(Canvas.Test.Registry)
      pseudo = AshA2ui.Canvas.build_graph(Canvas.Test.Registry, @pseudo)

      assert Map.keys(pseudo.nodes) == Map.keys(plain.nodes)
      assert pseudo.roots == plain.roots

      for {id, node} <- plain.nodes do
        assert pseudo.nodes[id].label == "⟪" <> node.label <> "⟫"
      end
    end

    test "an object's and its capabilities' labels are translated; a record's is data" do
      opts = [registry: Canvas.Test.Registry, authorize?: false]
      post = Ash.create!(Canvas.Test.Post, %{name: "hello"}, authorize?: false)

      {:ok, plain} = AshA2ui.Canvas.resolve("resource:blog.post", opts)
      {:ok, pseudo} = AshA2ui.Canvas.resolve("resource:blog.post", opts ++ @pseudo)

      assert pseudo.label == "⟪" <> plain.label <> "⟫"

      assert Enum.map(pseudo.capabilities, & &1.label) ==
               Enum.map(plain.capabilities, &("⟪" <> &1.label <> "⟫"))

      assert Enum.map(pseudo.capabilities, & &1.action_name) ==
               Enum.map(plain.capabilities, & &1.action_name)

      record_ref = "record:blog.post:" <> ObjectRef.encode_pk(post.id)
      assert {:ok, %{label: "hello"}} = AshA2ui.Canvas.resolve(record_ref, opts ++ @pseudo)
    end
  end
end
