defmodule AshA2ui.DynamicLifecycleTest do
  @moduledoc """
  The spec-as-artifact lifecycle: canonical serialization, load-time
  re-validation, human-reviewable diffs, and promotion of a validated
  runtime spec into a checked-in standalone DSL module.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Diff
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.KitchenSink
  alias AshA2ui.Test.Minimal

  @allowlist Dynamic.allowlist([KitchenSink, Minimal])

  defp minimal_spec do
    %{
      "resource" => "Minimal",
      "title" => "Minimal things",
      "components" => [
        %{"kind" => "table", "fields" => ["name"], "read_action" => "read"},
        %{"kind" => "form", "fields" => ["name"], "create_action" => "create"}
      ]
    }
  end

  defp kitchen_sink_spec do
    %{
      "resource" => "KitchenSink",
      "title" => "Kitchen sink",
      "components" => [
        %{
          "kind" => "table",
          "fields" => ["name", "status", "count", "inserted_at"],
          "row_actions" => ["update", "destroy"],
          "query" => "default",
          "row_layout" => %{
            "title" => "name",
            "badge" => "status",
            "badge_text" => %{"draft" => "Draft"},
            "meta" => ["count", "inserted_at"],
            "columns" => 2
          }
        },
        %{
          "kind" => "form",
          "fields" => ["name", "status", "count"],
          "create_action" => "create",
          "update_action" => "update",
          "groups" => [
            %{
              "name" => "details",
              "label" => "Details",
              "columns" => 2,
              "fields" => ["status", "count"]
            }
          ]
        }
      ],
      "queries" => [
        %{
          "name" => "default",
          "search_fields" => ["name"],
          "sortable" => ["name", "inserted_at"],
          "filters" => ["status"],
          "default_sort" => [%{"field" => "inserted_at", "direction" => "desc"}],
          "presets" => [%{"name" => "drafts", "filter" => %{"status" => "draft"}}],
          "default_preset" => "drafts",
          "page_size" => 10
        }
      ],
      "fields" => [
        %{"name" => "inserted_at", "label" => "Created", "format" => "date"}
      ],
      "actions" => [
        %{
          "name" => "destroy",
          "refreshes" => ["table"],
          "visible_when" => %{"status" => "draft"}
        }
      ]
    }
  end

  defp context_spec do
    %{
      "resource" => "Appointment",
      "title" => "Appointments by owner",
      "components" => [
        %{
          "kind" => "table",
          "fields" => ["title", "status"],
          "context_filter" => %{"owner_id" => "owner"},
          "require_context" => ["owner"]
        },
        %{"kind" => "detail", "context" => "owner", "fields" => ["name", "email"]}
      ],
      "contexts" => [
        %{"name" => "owner", "resource" => "Owner", "option_label" => "name"}
      ]
    }
  end

  defp context_allowlist do
    Dynamic.allowlist([AshA2ui.Test.Appointment, AshA2ui.Test.Owner])
  end

  # Deep-scrubs Spark metadata so entity structs built at runtime (Parser)
  # compare equal to the same entities built by the compiler.
  defp scrub(%_struct{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.has_key?(:__spark_metadata__)
    |> case do
      true -> struct |> Map.put(:__spark_metadata__, nil) |> scrub_fields()
      false -> scrub_fields(struct)
    end
  end

  defp scrub(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, scrub(value)} end)
  end

  defp scrub(list) when is_list(list), do: Enum.map(list, &scrub/1)
  defp scrub(other), do: other

  defp scrub_fields(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reduce(struct, fn {key, value}, acc -> Map.put(acc, key, scrub(value)) end)
  end

  describe "serialize/1" do
    test "produces a canonical, versioned envelope" do
      serialized = Dynamic.serialize(minimal_spec())

      assert is_binary(serialized)
      assert %{"spec_format" => 1, "spec" => spec} = Jason.decode!(serialized)
      assert spec == minimal_spec()
    end

    test "is deterministic regardless of map key insertion order" do
      shuffled =
        %{}
        |> Map.put("title", "Minimal things")
        |> Map.put("components", [
          %{"read_action" => "read", "kind" => "table", "fields" => ["name"]},
          %{"create_action" => "create", "fields" => ["name"], "kind" => "form"}
        ])
        |> Map.put("resource", "Minimal")

      assert Dynamic.serialize(shuffled) == Dynamic.serialize(minimal_spec())
    end

    test "accepts a resolved surface and serializes its spec" do
      {:ok, surface} = Dynamic.resolve(minimal_spec(), allowlist: @allowlist)

      assert Dynamic.serialize(surface) == Dynamic.serialize(minimal_spec())
    end

    test "sorts keys at every nesting level, preserving array order" do
      assert Dynamic.serialize(%{"b" => %{"d" => 1, "c" => 2}, "a" => [%{"z" => 1, "y" => 2}]}) ==
               ~s({"spec":{"a":[{"y":2,"z":1}],"b":{"c":2,"d":1}},"spec_format":1})
    end
  end

  describe "fingerprint/1" do
    test "is stable across key order and input form" do
      {:ok, surface} = Dynamic.resolve(minimal_spec(), allowlist: @allowlist)

      assert Dynamic.fingerprint(minimal_spec()) == Dynamic.fingerprint(surface)
      assert Dynamic.fingerprint(minimal_spec()) =~ ~r/^sha256:[0-9a-f]{64}$/
    end

    test "differs for different specs" do
      refute Dynamic.fingerprint(minimal_spec()) == Dynamic.fingerprint(kitchen_sink_spec())
    end
  end

  describe "deserialize/2" do
    test "round-trips a serialized spec into an equivalent surface" do
      serialized = Dynamic.serialize(minimal_spec())

      assert {:ok, surface} =
               Dynamic.deserialize(serialized, allowlist: @allowlist, surface_id: "stored")

      assert surface.resource == Minimal
      assert surface.title == "Minimal things"
      assert surface.surface_id == "stored"
      assert surface.spec == minimal_spec()

      {:ok, direct} =
        Dynamic.resolve(minimal_spec(), allowlist: @allowlist, surface_id: "stored")

      assert scrub(surface.dsl_state) == scrub(direct.dsl_state)
    end

    test "re-validates against the current resource state (drift becomes errors)" do
      # A spec saved when the resource still had a "legacy" field.
      drifted =
        minimal_spec()
        |> put_in(["components", Access.at(0), "fields"], ["name", "legacy"])
        |> Dynamic.serialize()

      assert {:error, errors} = Dynamic.deserialize(drifted, allowlist: @allowlist)
      assert [%Error{} | _rest] = errors
      assert Enum.any?(Error.messages(errors), &(&1 =~ "references unknown field :legacy"))
    end

    test "reports resources that left the allowlist" do
      serialized = Dynamic.serialize(minimal_spec())
      shrunk = Dynamic.allowlist([KitchenSink])

      assert {:error, [%Error{path: "resource", message: message}]} =
               Dynamic.deserialize(serialized, allowlist: shrunk)

      assert message =~ "not available to dynamic surfaces"
    end

    test "rejects malformed JSON with a structured error" do
      assert {:error, [%Error{path: "", message: message}]} =
               Dynamic.deserialize("{not json", allowlist: @allowlist)

      assert message =~ "not valid JSON"
    end

    test "rejects envelopes without the expected shape" do
      assert {:error, [%Error{message: message}]} =
               Dynamic.deserialize(Jason.encode!(%{"spec" => minimal_spec()}),
                 allowlist: @allowlist
               )

      assert message =~ "spec_format"

      assert {:error, [%Error{message: list_message}]} =
               Dynamic.deserialize(Jason.encode!([1, 2, 3]), allowlist: @allowlist)

      assert list_message =~ "spec_format"
    end

    test "rejects unsupported spec formats by version" do
      envelope = Jason.encode!(%{"spec_format" => 99, "spec" => minimal_spec()})

      assert {:error, [%Error{path: "spec_format", message: message}]} =
               Dynamic.deserialize(envelope, allowlist: @allowlist)

      assert message =~ "99"
      assert message =~ "1"
    end
  end

  describe "diff/2" do
    test "identical specs produce an empty diff (input form independent)" do
      {:ok, surface} = Dynamic.resolve(minimal_spec(), allowlist: @allowlist)

      diff = Dynamic.diff(Dynamic.serialize(minimal_spec()), surface)

      assert %Diff{changes: []} = diff
      assert Diff.empty?(diff)
      assert Diff.summary(diff) == []
    end

    test "detects surface-level title and resource changes" do
      changed =
        minimal_spec()
        |> Map.put("title", "Renamed")
        |> Map.put("resource", "KitchenSink")

      diff = Dynamic.diff(minimal_spec(), changed)

      assert Enum.any?(diff.changes, fn change ->
               change.kind == :changed and change.entity == :surface and
                 change.option == "title" and
                 change.from == "Minimal things" and change.to == "Renamed"
             end)

      assert Enum.any?(diff.changes, fn change ->
               change.option == "resource" and change.from == "Minimal" and
                 change.to == "KitchenSink"
             end)

      assert ~s(surface: title changed from "Minimal things" to "Renamed") in Diff.summary(diff)
    end

    test "detects added and removed entities by name" do
      base = kitchen_sink_spec()

      changed =
        base
        |> Map.update!("components", fn [table | _rest] -> [table] end)
        |> Map.put("actions", [])
        |> Map.update!("fields", fn fields ->
          fields ++ [%{"name" => "count", "label" => "How many"}]
        end)

      diff = Dynamic.diff(base, changed)

      assert Enum.any?(diff.changes, fn change ->
               change.kind == :removed and change.entity == :component and
                 change.name == "form"
             end)

      assert Enum.any?(diff.changes, fn change ->
               change.kind == :removed and change.entity == :action and
                 change.name == "destroy"
             end)

      added_field =
        Enum.find(diff.changes, fn change ->
          change.kind == :added and change.entity == :field and change.name == "count"
        end)

      assert added_field.to == %{"name" => "count", "label" => "How many"}

      summary = Diff.summary(diff)
      assert ~s(removed component "form") in summary
      assert ~s(added field "count") in summary
    end

    test "reports option-level changes with old and new values" do
      changed =
        kitchen_sink_spec()
        |> update_in(["components", Access.at(0), "fields"], fn fields ->
          fields -- ["count"]
        end)
        |> update_in(["queries", Access.at(0)], fn query ->
          query
          |> Map.put("page_size", 50)
          |> Map.delete("default_preset")
        end)

      diff = Dynamic.diff(kitchen_sink_spec(), changed)

      fields_change =
        Enum.find(diff.changes, fn change ->
          change.entity == :component and change.name == "table" and change.option == "fields"
        end)

      assert fields_change.from == ["name", "status", "count", "inserted_at"]
      assert fields_change.to == ["name", "status", "inserted_at"]

      assert Enum.any?(diff.changes, fn change ->
               change.entity == :query and change.name == "default" and
                 change.option == "page_size" and change.from == 10 and change.to == 50
             end)

      unset =
        Enum.find(diff.changes, fn change ->
          change.entity == :query and change.option == "default_preset"
        end)

      assert unset.from == "drafts"
      assert unset.to == nil

      assert ~s|query "default": default_preset changed from "drafts" to (unset)| in Diff.summary(
               diff
             )
    end

    test "diffs nested presets and groups as named sub-entities" do
      changed =
        kitchen_sink_spec()
        |> update_in(["queries", Access.at(0), "presets"], fn presets ->
          presets ++ [%{"name" => "recent", "read_action" => "read"}]
        end)
        |> update_in(["components", Access.at(1), "groups", Access.at(0)], fn group ->
          Map.put(group, "columns", 3)
        end)

      diff = Dynamic.diff(kitchen_sink_spec(), changed)

      assert Enum.any?(diff.changes, fn change ->
               change.kind == :added and change.entity == :preset and change.name == "recent" and
                 change.path == ~s(query "default" preset "recent")
             end)

      assert Enum.any?(diff.changes, fn change ->
               change.kind == :changed and change.entity == :group and
                 change.path == ~s(component "form" group "details") and
                 change.option == "columns" and change.from == 2 and change.to == 3
             end)
    end

    test "diffs row_layout options in place" do
      changed =
        update_in(kitchen_sink_spec(), ["components", Access.at(0), "row_layout"], fn layout ->
          layout |> Map.put("columns", 4) |> Map.delete("badge")
        end)

      diff = Dynamic.diff(kitchen_sink_spec(), changed)

      assert Enum.any?(diff.changes, fn change ->
               change.entity == :component and change.name == "table" and
                 change.option == "row_layout.columns" and change.from == 2 and change.to == 4
             end)

      assert Enum.any?(diff.changes, fn change ->
               change.option == "row_layout.badge" and change.from == "status" and
                 change.to == nil
             end)
    end

    test "changes are JSON-encodable for host UIs" do
      diff = Dynamic.diff(minimal_spec(), Map.put(minimal_spec(), "title", "Renamed"))

      assert [%{"kind" => "changed", "path" => "surface"}] =
               diff.changes |> Jason.encode!() |> Jason.decode!()
    end
  end

  describe "to_dsl_source/2" do
    test "returns validation errors for invalid specs" do
      spec = put_in(minimal_spec(), ["components", Access.at(0), "fields"], ["bogus"])

      assert {:error, [%Error{} | _rest]} =
               Dynamic.to_dsl_source(spec,
                 module: AshA2ui.Promoted.Invalid,
                 allowlist: @allowlist
               )
    end

    test "generates a formatted module with a provenance fingerprint" do
      {:ok, source} =
        Dynamic.to_dsl_source(minimal_spec(),
          module: AshA2ui.Promoted.MinimalUI,
          allowlist: @allowlist
        )

      assert source =~ "defmodule AshA2ui.Promoted.MinimalUI do"
      assert source =~ "use AshA2ui.Standalone"
      assert source =~ "for_resource AshA2ui.Test.Minimal"
      assert source =~ Dynamic.fingerprint(minimal_spec())
      assert source =~ "AshA2ui.Dynamic.to_dsl_source/2"

      # Formatted output is a fixed point of the project formatter (same
      # locals_without_parens the extension exports for host projects).
      {formatter_opts, _bindings} = Code.eval_file(".formatter.exs")
      locals = Keyword.fetch!(formatter_opts, :locals_without_parens)

      assert IO.iodata_to_binary([
               Code.format_string!(source, locals_without_parens: locals),
               "\n"
             ]) == source
    end

    test "promoted minimal module compiles and resolves like the spec" do
      {:ok, source} =
        Dynamic.to_dsl_source(minimal_spec(),
          module: AshA2ui.Promoted.MinimalRoundTrip,
          allowlist: @allowlist,
          surface_id: "promoted_minimal"
        )

      [{module, _binary} | _rest] = Code.compile_string(source)

      {:ok, surface} =
        Dynamic.resolve(minimal_spec(), allowlist: @allowlist, surface_id: "promoted_minimal")

      assert scrub(ResolvedView.resolve(module)) == scrub(ResolvedView.resolve(surface.dsl_state))
    end

    test "round-trip: the kitchen-sink spec promotes to an equivalent surface" do
      spec = kitchen_sink_spec()

      {:ok, source} =
        Dynamic.to_dsl_source(spec,
          module: AshA2ui.Promoted.KitchenSinkUI,
          allowlist: @allowlist,
          surface_id: "promoted_kitchen_sink"
        )

      [{module, _binary} | _rest] = Code.compile_string(source)

      {:ok, surface} =
        Dynamic.resolve(spec, allowlist: @allowlist, surface_id: "promoted_kitchen_sink")

      assert scrub(ResolvedView.resolve(module)) == scrub(ResolvedView.resolve(surface.dsl_state))

      Ash.create!(
        KitchenSink,
        %{name: "promoted", active: true, count: 3, status: :draft},
        authorize?: false
      )

      assert AshA2ui.Info.build_surface(module, authorize?: false) ==
               Dynamic.build_surface(surface, authorize?: false)
    end

    test "round-trip: contexts and details promote with allowlisted resource modules" do
      {:ok, source} =
        Dynamic.to_dsl_source(context_spec(),
          module: AshA2ui.Promoted.AppointmentsUI,
          allowlist: context_allowlist(),
          surface_id: "promoted_appointments"
        )

      assert source =~ "resource AshA2ui.Test.Owner"

      [{module, _binary} | _rest] = Code.compile_string(source)

      {:ok, surface} =
        Dynamic.resolve(context_spec(),
          allowlist: context_allowlist(),
          surface_id: "promoted_appointments"
        )

      assert scrub(ResolvedView.resolve(module)) == scrub(ResolvedView.resolve(surface.dsl_state))
    end

    test "round-trip: an imported surface's nested forms promote losslessly" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.Ticket)
      assert [%{feature: "surface_id"}] = rejections

      allowlist = Dynamic.allowlist([AshA2ui.Test.Ticket])

      assert {:ok, source} =
               Dynamic.to_dsl_source(spec,
                 module: AshA2ui.Promoted.TicketUI,
                 allowlist: allowlist,
                 surface_id: "tickets"
               )

      # the nested forms came back as DSL blocks
      assert source =~ "nested_form :notes do"
      assert source =~ "fields [:body, :rating]"
      assert source =~ "nested_form :tags"

      [{module, _binary} | _rest] = Code.compile_string(source)

      {:ok, surface} =
        Dynamic.resolve(spec, allowlist: allowlist, surface_id: "tickets")

      assert %{notes: notes, tags: tags} = ResolvedView.resolve(module).nested_forms
      assert notes.mode == :create_inline and notes.fields == [:body, :rating]
      assert tags.mode == :pick_existing

      assert scrub(ResolvedView.resolve(module)) == scrub(ResolvedView.resolve(surface.dsl_state))
    end

    test "round-trip: an imported sectioned table promotes losslessly" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.Test.BucketWordsUI)

      # the spec vocabulary now carries the sections config; the fixture's
      # editable block (and the section-level surface_id) stay honest rejections
      refute Enum.any?(rejections, &(&1.feature == "sections"))
      assert Enum.any?(rejections, &(&1.feature == "editable"))

      assert [_new_words, per_bucket] = spec["components"]

      assert per_bucket["sections"] == %{
               "source" => "Bucket",
               "scope_by" => "bucket_id",
               "label" => "name",
               "sort" => "name"
             }

      allowlist = Dynamic.allowlist([AshA2ui.Test.BucketWord, AshA2ui.Test.Bucket])

      assert {:ok, source} =
               Dynamic.to_dsl_source(spec,
                 module: AshA2ui.Promoted.BucketWordsUI,
                 allowlist: allowlist,
                 surface_id: "bucket_words"
               )

      assert source =~ "component :table, :per_bucket do"
      assert source =~ "source AshA2ui.Test.Bucket"
      assert source =~ "scope_by :bucket_id"
      assert source =~ "label :name"
      assert source =~ "sort :name"

      [{module, _binary} | _rest] = Code.compile_string(source)

      {:ok, surface} =
        Dynamic.resolve(spec, allowlist: allowlist, surface_id: "bucket_words")

      assert %{sections: resolved_sections} =
               ResolvedView.resolve(module).tables |> Enum.find(&(&1.name == :per_bucket))

      assert resolved_sections.source == AshA2ui.Test.Bucket
      assert resolved_sections.scope_by == :bucket_id

      assert scrub(ResolvedView.resolve(module)) == scrub(ResolvedView.resolve(surface.dsl_state))
    end

    test "round-trip: an imported via-delegated action promotes losslessly" do
      {:ok, spec, rejections} = Importer.import(AshA2ui.ActionHandlerTest.Ticket)
      assert [%{feature: "surface_id"}] = rejections

      assert [%{"name" => "check_in", "via" => via}] = spec["actions"]

      assert via == %{
               "mfa" => "AshA2ui.ActionHandlerTest.CheckInFacade.complete/2",
               "args" => [:board]
             }

      allowlist = Dynamic.allowlist([AshA2ui.ActionHandlerTest.Ticket])
      via_allowlist = [AshA2ui.ActionHandlerTest.CheckInFacade]

      assert {:ok, source} =
               Dynamic.to_dsl_source(spec,
                 module: AshA2ui.Promoted.ViaTicketUI,
                 allowlist: allowlist,
                 via_allowlist: via_allowlist,
                 surface_id: "ticket"
               )

      assert source =~ "via {AshA2ui.ActionHandlerTest.CheckInFacade, :complete, [:board]}"

      [{module, _binary} | _rest] = Code.compile_string(source)

      {:ok, surface} =
        Dynamic.resolve(spec,
          allowlist: allowlist,
          via_allowlist: via_allowlist,
          surface_id: "ticket"
        )

      # the promoted module declares the same delegate tuple
      assert %{via: {AshA2ui.ActionHandlerTest.CheckInFacade, :complete, [:board]}} =
               ResolvedView.resolve(module).actions[:check_in]

      assert scrub(ResolvedView.resolve(module)) == scrub(ResolvedView.resolve(surface.dsl_state))
    end

    test "defaults the surface_id to the underscored module name" do
      {:ok, source} =
        Dynamic.to_dsl_source(minimal_spec(),
          module: AshA2ui.Promoted.DefaultIdUI,
          allowlist: @allowlist
        )

      assert source =~ ~s(surface_id "default_id_ui")
      refute source =~ "spec_version"

      [{module, _binary} | _rest] = Code.compile_string(source)

      assert [%{"createSurface" => %{"surfaceId" => "default_id_ui"}}] =
               AshA2ui.Info.build_surface(module, authorize?: false)
    end
  end
end
