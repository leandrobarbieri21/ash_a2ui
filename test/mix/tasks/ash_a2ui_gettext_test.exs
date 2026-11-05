defmodule Mix.Tasks.AshA2ui.GettextTest do
  # async: false — the gen task tests swap the global Mix shell.
  use ExUnit.Case, async: false

  alias AshA2ui.Gettext.Metadata
  alias Mix.Tasks.AshA2ui.Gen.Gettext, as: Gen
  alias Mix.Tasks.AshA2ui.Gettext.Extract
  alias Mix.Tasks.AshA2ui.Gettext.ExtractMetadata

  @shipped "priv/gettext/ash_a2ui.pot"
  # The metadata template of the test/support fixture surfaces. Re-record
  # (only on purpose) with
  # `RECORD_L10N_GOLDEN=1 mix test test/mix/tasks/ash_a2ui_gettext_test.exs`.
  @metadata_golden "test/ash_a2ui/l10n/golden/a2ui_metadata.pot"

  describe "the shipped catalog" do
    test "is up to date with the marked strings in lib/" do
      assert File.read!(@shipped) == Extract.build_pot(),
             "#{@shipped} is stale. Run `mix ash_a2ui.gettext.extract` and commit it."
    end

    test "carries every marked string once, with file references" do
      messages = Extract.extract_messages()

      assert {nil, [reference]} = messages["Save changes"]
      assert reference =~ ~r{^lib/ash_a2ui/experience\.ex:\d+$}

      assert Enum.any?(
               elem(messages["Cancel"], 1),
               &(&1 =~ ~r{^lib/ash_a2ui/encoder/v0_9_1\.ex:\d+$})
             )

      assert Map.has_key?(messages, "%{first}–%{last} of %{total}")

      pot = File.read!(@shipped)
      assert length(Regex.scan(~r/^msgid "Next"$/m, pot)) == 1
    end

    test "writes a plural message as msgid_plural with two msgstr forms" do
      assert File.read!(@shipped) =~ """
             msgid "Report complete: %{count} row."
             msgid_plural "Report complete: %{count} rows."
             msgstr[0] ""
             msgstr[1] ""
             """
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

  describe "mix ash_a2ui.gettext.extract_metadata" do
    setup do
      dir =
        Path.join(
          System.tmp_dir!(),
          "ash_a2ui_extract_metadata_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
      %{output: Path.join(dir, "a2ui_metadata.pot")}
    end

    test "walks the app's extension resources and standalone UI modules" do
      surfaces = Metadata.surfaces(:ash_a2ui)

      assert AshA2ui.Test.Minimal in surfaces
      assert AshA2ui.Test.Experience.Task in surfaces
      assert AshA2ui.Test.MinimalUI in surfaces
      assert AshA2ui.Test.BulkTasksUI in surfaces
      refute AshA2ui.Test.BulkProject in surfaces
      assert surfaces == Enum.sort(Enum.uniq(surfaces))
    end

    test "writes the fixtures' labels, stable against the golden", %{output: output} do
      ExtractMetadata.run(["--output", output])
      pot = File.read!(output)

      if System.get_env("RECORD_L10N_GOLDEN"), do: File.write!(@metadata_golden, pot)

      assert pot == File.read!(@metadata_golden), "the metadata template changed"
      assert pot =~ ~s("Domain: a2ui_metadata\\n")
      # A humanized resource heading, a declared column label, an action.
      assert pot =~ ~r{^#: test/support/bulk_tasks_ui\.ex:\d+$}m
      assert length(Regex.scan(~r/^msgid "Bulk task"$/m, pot)) == 1
      # Library strings are in ash_a2ui.pot, not here.
      refute pot =~ ~s(msgid "Save changes")
    end

    test "is idempotent", %{output: output} do
      ExtractMetadata.run(["--output", output])
      once = File.read!(output)
      ExtractMetadata.run(["--output", output])

      assert File.read!(output) == once

      assert Metadata.pot(Metadata.messages(Metadata.surfaces(:ash_a2ui)), "a2ui_metadata") ==
               once
    end

    test "--check-up-to-date passes when current and fails when stale", %{output: output} do
      assert_raise Mix.Error, ~r/out of date/, fn ->
        ExtractMetadata.run(["--output", output, "--check-up-to-date"])
      end

      ExtractMetadata.run(["--output", output])
      ExtractMetadata.run(["--output", output, "--check-up-to-date"])
      assert_received {:mix_shell, :info, [message]} when is_binary(message)

      File.write!(output, File.read!(output) <> "\nmsgid \"Gone\"\nmsgstr \"\"\n")

      assert_raise Mix.Error, ~r/out of date/, fn ->
        ExtractMetadata.run(["--output", output, "--check-up-to-date"])
      end
    end

    test "names the domain after the output file" do
      dir = Path.join(System.tmp_dir!(), "ash_a2ui_labels_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)
      output = Path.join(dir, "labels.pot")

      ExtractMetadata.run(["--output", output])
      assert File.read!(output) =~ ~s("Domain: labels\\n")
    end

    test "writes msgctxt, so homographs are separate entries, and escapes PO strings" do
      messages = %{
        {nil, "Open"} => ["lib/a.ex"],
        {"enum:Elixir.MyApp.Status", "Open"} => ["lib/a.ex", "lib/b.ex"],
        {nil, ~s(Say "hi"\\now)} => ["lib/b.ex"]
      }

      assert Metadata.pot(messages, "a2ui_metadata") =~
               """
               #: lib/a.ex
               msgid "Open"
               msgstr ""

               #: lib/a.ex
               #: lib/b.ex
               msgctxt "enum:Elixir.MyApp.Status"
               msgid "Open"
               msgstr ""

               #: lib/b.ex
               msgid "Say \\"hi\\"\\\\now"
               msgstr ""
               """
    end
  end
end
