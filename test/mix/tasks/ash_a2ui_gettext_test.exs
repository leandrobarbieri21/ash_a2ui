defmodule Mix.Tasks.AshA2ui.GettextTest do
  # async: false — the gen task tests swap the global Mix shell.
  use ExUnit.Case, async: false

  alias Mix.Tasks.AshA2ui.Gen.Gettext, as: Gen
  alias Mix.Tasks.AshA2ui.Gettext.Extract

  @shipped "priv/gettext/ash_a2ui.pot"

  describe "the shipped catalog" do
    test "is up to date with the marked strings in lib/" do
      assert File.read!(@shipped) == Extract.build_pot(),
             "#{@shipped} is stale. Run `mix ash_a2ui.gettext.extract` and commit it."
    end

    test "carries every marked string once, with file references" do
      messages = Extract.extract_messages()

      assert messages["Save changes"] == ["lib/ash_a2ui/experience.ex"]
      assert "lib/ash_a2ui/encoder/v0_9_1.ex" in messages["Cancel"]
      assert Map.has_key?(messages, "%{first}–%{last} of %{total}")

      pot = File.read!(@shipped)
      assert length(Regex.scan(~r/^msgid "Next"$/m, pot)) == 1
    end
  end

  describe "mix ash_a2ui.gen.gettext" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "ash_a2ui_gen_gettext_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
      %{dir: dir, source: Path.expand(@shipped)}
    end

    test "copies the catalog under the ash_a2ui domain", %{dir: dir, source: source} do
      Gen.run(["--source", source, "--output-dir", dir])

      assert File.read!(Path.join(dir, "ash_a2ui.pot")) == File.read!(source)
    end

    test "merges into another domain idempotently, next to other libraries' sections", %{
      dir: dir,
      source: source
    } do
      dest = Path.join(dir, "default.pot")

      File.write!(dest, """
      msgid ""
      msgstr ""

      msgid "Mine"
      msgstr ""

      ## -- ash-gettext:start --
      msgid "Ash's own"
      msgstr ""
      """)

      Gen.run(["--domain", "default", "--source", source, "--output-dir", dir])
      once = File.read!(dest)
      Gen.run(["--domain", "default", "--source", source, "--output-dir", dir])

      assert File.read!(dest) == once
      assert once =~ ~s(msgid "Mine")
      assert once =~ "## -- ash_a2ui-gettext:start --\n"
      assert once =~ ~s(## -- ash-gettext:start --\nmsgid "Ash's own")
      assert length(Regex.scan(~r/^msgid "Save changes"$/m, once)) == 1
      refute once =~ ~s(Domain: ash_a2ui)
    end

    test "rejects an invalid domain", %{dir: dir, source: source} do
      assert_raise Mix.Error, ~r/Invalid domain/, fn ->
        Gen.run(["--domain", "Bad-Domain", "--source", source, "--output-dir", dir])
      end
    end
  end
end
