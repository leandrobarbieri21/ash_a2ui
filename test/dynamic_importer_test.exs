defmodule AshA2ui.DynamicImporterTest do
  @moduledoc """
  The composer's Import: a declared surface reads back as the dynamic spec
  vocabulary, with every feature that vocabulary cannot carry surfaced as a
  rejection instead of silently dropped.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Importer

  describe "import/1 — the happy path round-trips through resolve/2" do
    test "a standalone UI module imports to a spec that resolves" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.MinimalUI)

      assert spec["resource"] == "Minimal"
      assert [%{"kind" => "table"} = table] = spec["components"]
      assert table["fields"] == ["name"]
      assert [%{"name" => "name", "label" => "Name (standalone)"}] = spec["fields"]

      # surface_id is resolve/deploy metadata, not spec vocabulary — the one
      # honest rejection this fixture produces.
      assert [%{feature: "surface_id", path: "a2ui.surface_id"}] = rejections

      # The imported spec resolves like any composed one.
      allow = Dynamic.allowlist([AshA2ui.Test.Minimal])

      assert {:ok, %Dynamic.Surface{}} = Dynamic.resolve(spec, allowlist: allow)
    end

    test "an inline resource surface imports its nested forms losslessly" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.Ticket)

      kinds = spec["components"] |> Enum.map(& &1["kind"]) |> Enum.sort()
      assert kinds == ["form", "table"]

      # Nested relationship forms are spec vocabulary: both of Ticket's
      # nested forms import, one create_inline with explicit fields, one
      # pick_existing inheriting everything.
      [_table, form] = spec["components"]

      assert form["nested_forms"] == [
               %{"name" => "notes", "fields" => ["body", "rating"]},
               %{"name" => "tags"}
             ]

      # the only honest rejection this fixture produces
      assert [%{feature: "surface_id", path: "a2ui.surface_id"}] = rejections

      allow = Dynamic.allowlist([AshA2ui.Test.Ticket])
      assert {:ok, %Dynamic.Surface{}} = Dynamic.resolve(spec, allowlist: allow)
    end

    test "a searchable nested form imports with its option vocabulary" do
      {:ok, spec, _rejections} = Importer.import(AshA2ui.Test.TicketSearchUI)

      [_table, form] = spec["components"]
      assert [%{"name" => "tags", "option_search" => ["name"]}] = form["nested_forms"]

      allow = Dynamic.allowlist([AshA2ui.Test.Ticket, AshA2ui.Test.Author, AshA2ui.Test.Tag])
      assert {:ok, %Dynamic.Surface{}} = Dynamic.resolve(spec, allowlist: allow)
    end
  end

  describe "import/1 — declared features the spec cannot say are visible rejections" do
    test "via-delegated actions import their MFA (the host gates it at resolve)" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.ActionHandlerTest.Ticket)

      # the delegation is spec vocabulary now: carried as "Mod.fun/arity"
      # plus its extra args, with no rejection
      refute Enum.any?(rejections, &(&1.feature == "via"))

      assert [%{"name" => "check_in", "via" => via}] = spec["actions"]

      # args carry as terms (JSON has no atoms: a serialized spec
      # normalizes them to strings)
      assert via == %{
               "mfa" => "AshA2ui.ActionHandlerTest.CheckInFacade.complete/2",
               "args" => [:board]
             }

      allow = Dynamic.allowlist([AshA2ui.ActionHandlerTest.Ticket])

      # resolving requires the host's :via_allowlist — the RCE guard
      assert {:error, errors} = Dynamic.resolve(spec, allowlist: allow)
      assert Enum.any?(Error.messages(errors), &(&1 =~ ":via_allowlist"))

      assert {:ok, %Dynamic.Surface{}} =
               Dynamic.resolve(spec,
                 allowlist: allow,
                 via_allowlist: [AshA2ui.ActionHandlerTest.CheckInFacade]
               )
    end

    test "inline editing is rejected; sectioned tables import their sections config" do
      {:ok, _spec, rejections} = Importer.import(AshA2ui.Test.EditableWordsUI)
      assert Enum.any?(rejections, &(&1.feature == "editable"))

      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.BucketWordsUI)

      # sections are spec vocabulary; the fixture's editable block is the
      # honest remainder (plus the section-level surface_id)
      assert Enum.any?(rejections, &(&1.feature == "editable"))
      refute Enum.any?(rejections, &(&1.feature == "sections"))

      assert [_new_words, per_bucket] = spec["components"]

      assert per_bucket["sections"] == %{
               "source" => "Bucket",
               "scope_by" => "bucket_id",
               "label" => "name",
               "sort" => "name"
             }

      allow = Dynamic.allowlist([AshA2ui.Test.BucketWord, AshA2ui.Test.Bucket])
      assert {:ok, %Dynamic.Surface{}} = Dynamic.resolve(spec, allowlist: allow)
    end

    test "boards (source-less sections, display :board) import as spec vocabulary" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.BoardTaskUI)

      refute Enum.any?(rejections, &(&1.feature in ["sections", "display"]))

      assert [board] = spec["components"]
      assert board["display"] == "board"

      assert board["sections"] == %{
               "scope_by" => "status",
               "values" => ["open", "claimed", "completed"],
               "labels" => %{"open" => "To do"}
             }

      allow = Dynamic.allowlist([AshA2ui.Test.BoardTask])
      assert {:ok, %Dynamic.Surface{}} = Dynamic.resolve(spec, allowlist: allow)
    end

    test "wizard steps are rejected visibly; the form's fields still import" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.Enrollment)

      assert [%{path: path}] = Enum.filter(rejections, &(&1.feature == "steps"))
      assert path =~ ~r/^components\[\d+\]\.steps$/

      form = Enum.find(spec["components"], &(&1["kind"] == "form"))
      assert form["fields"] == ["name", "email", "role", "team"]
      refute Map.has_key?(form, "steps")
    end
  end

  describe "import/1 — nothing to import" do
    test "a module without an a2ui section is an error, not an empty spec" do
      # (Every resource in the test support carries the extension; a plain
      # module is the honest no-surface case.)
      assert {:error, %{feature: "a2ui"}} = Importer.import(Enum)
    end
  end

  test "Rejection.messages/1 renders one path (feature): reason line per rejection" do
    {:ok, _spec, rejections} = Importer.import(AshA2ui.Test.MinimalUI)

    [line] = Importer.Rejection.messages(rejections)
    assert line =~ "a2ui.surface_id (surface_id):"
    assert line =~ "resolve :surface_id option"
  end
end
