defmodule AshA2ui.SectionsTest do
  @moduledoc """
  Dynamic table sets: a `:table` component with a `sections` block is a
  template expanded at runtime into one concrete table per section record —
  runtime names, scoped `/records/<name>` + `/query/<name>` paths, section
  labels as headings, per-section scoped reads, template-key `refreshes`
  fan-out, and the multi-table `"query"` action against runtime names.
  Schema-validated on both v0.9.1 and v1.0.
  """

  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ResolvedView
  alias AshA2ui.Sections
  alias AshA2ui.Test.Bucket
  alias AshA2ui.Test.BucketWord
  alias AshA2ui.Test.BucketWordsUI
  alias AshA2ui.Test.BucketWordsV1UI

  defp envelope(name, context, version \\ "v0.9.1", surface \\ "bucket_words") do
    %{
      "version" => version,
      "action" => %{
        "name" => name,
        "surfaceId" => surface,
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp paths(messages), do: Enum.map(messages, & &1["updateDataModel"]["path"])

  defp create_bucket!(name) do
    Ash.create!(Bucket, %{name: name}, authorize?: false)
  end

  defp create_word!(word, opts \\ []) do
    Ash.create!(
      BucketWord,
      %{
        word: word,
        replacement: opts[:replacement],
        state: opts[:state] || :new,
        bucket_id: opts[:bucket_id]
      },
      authorize?: false
    )
  end

  defp bucketed_word!(word, bucket, opts \\ []) do
    create_word!(word, Keyword.merge([state: :bucketed, bucket_id: bucket.id], opts))
  end

  defp runtime_name(bucket), do: Sections.section_name(:per_bucket, bucket.id)

  describe "resolution" do
    test "a sectioned table resolves its sections config with defaults applied" do
      view = ResolvedView.resolve(BucketWordsUI)

      assert view.sectioned?
      assert ResolvedView.multi_table?(view)

      per_bucket = Enum.find(view.tables, &(&1.name == :per_bucket))

      assert per_bucket.sections == %{
               source: Bucket,
               scope_by: :bucket_id,
               label: :name,
               value: :id,
               read_action: :read,
               sort: :name,
               limit: 50
             }

      new_words = Enum.find(view.tables, &(&1.name == :new_words))
      assert new_words.sections == nil
    end

    test "a single sectioned table is still a multi-table surface" do
      view = ResolvedView.resolve(BucketWordsV1UI)

      assert ResolvedView.multi_table?(view)
      assert [table] = view.tables
      assert table.records_path == "/records/per_bucket"
      assert table.query_path == "/query/per_bucket"
      # legacy single-table mirrors stay nil, like any multi-table surface
      assert view.read_action == nil
      assert view.query == nil
    end

    test "section names sanitize non-alphanumeric characters" do
      assert Sections.section_name(:per_bucket, "a3f4-9b.x") == "per_bucket_a3f4_9b_x"
      assert Sections.section_name(:per_bucket, 42) == "per_bucket_42"
    end
  end

  describe "expansion" do
    test "expand/2 replaces the template with one scoped table per section, in sort order" do
      zebra = create_bucket!("Zebra")
      alpha = create_bucket!("Alpha")

      view = ResolvedView.resolve(BucketWordsUI)
      assert {:ok, expanded} = Sections.expand(view, authorize?: false)

      assert [new_words, alpha_table, zebra_table] = expanded.tables
      assert new_words.name == :new_words

      assert alpha_table.name == runtime_name(alpha)
      assert alpha_table.section.label == "Alpha"
      assert alpha_table.section.filter == {:bucket_id, alpha.id}
      assert alpha_table.records_path == "/records/#{runtime_name(alpha)}"
      assert alpha_table.query_path == "/query/#{runtime_name(alpha)}"
      assert alpha_table.query.name == :word_q
      refute Map.has_key?(alpha_table, :sections)

      assert zebra_table.name == runtime_name(zebra)
      assert zebra_table.section.label == "Zebra"

      # components swap the template for per-section copies (root order)
      table_components = Enum.filter(expanded.components, &(&1.name == :table))

      assert Enum.map(table_components, & &1.as) == [
               :new_words,
               runtime_name(alpha),
               runtime_name(zebra)
             ]
    end

    test "refreshes targeting the template key fan out to the runtime names" do
      bucket = create_bucket!("Only")

      view = ResolvedView.resolve(BucketWordsUI)
      assert {:ok, expanded} = Sections.expand(view, authorize?: false)

      assert expanded.refreshes == %{
               approve: [:new_words, runtime_name(bucket)],
               destroy: [runtime_name(bucket)],
               update_replacement: [runtime_name(bucket)]
             }
    end

    test "zero sections leave only the static tables (still multi-table)" do
      view = ResolvedView.resolve(BucketWordsUI)
      assert {:ok, expanded} = Sections.expand(view, authorize?: false)

      assert [%{name: :new_words}] = expanded.tables
      assert ResolvedView.multi_table?(expanded)
    end

    test "views without sectioned tables are returned unchanged" do
      view = ResolvedView.resolve(AshA2ui.Test.ReviewItem)
      assert {:ok, ^view} = Sections.expand(view, authorize?: false)
    end
  end

  describe "encoder (v0.9.1)" do
    setup do
      alpha = create_bucket!("Alpha")
      zebra = create_bucket!("Zebra")

      apple = bucketed_word!("apple", alpha)
      zeal = bucketed_word!("zeal", zebra)
      fresh = create_word!("fresh")

      %{alpha: alpha, zebra: zebra, apple: apple, zeal: zeal, fresh: fresh}
    end

    test "the surface renders one suffixed section per bucket, headed by its label", ctx do
      messages = AshA2ui.Info.build_surface(BucketWordsUI, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      components =
        messages
        |> Enum.find_value(& &1["updateComponents"])
        |> Map.fetch!("components")
        |> Map.new(&{&1["id"], &1})

      alpha_sfx = "_#{runtime_name(ctx.alpha)}"
      zebra_sfx = "_#{runtime_name(ctx.zebra)}"

      assert components["root"]["children"] == [
               "status_text",
               "table_heading_new_words",
               "records_list_new_words",
               "empty_state_new_words",
               "table_heading#{alpha_sfx}",
               "query#{alpha_sfx}_controls",
               "records_list#{alpha_sfx}",
               "empty_state#{alpha_sfx}",
               "query#{alpha_sfx}_pagination",
               "table_heading#{zebra_sfx}",
               "query#{zebra_sfx}_controls",
               "records_list#{zebra_sfx}",
               "empty_state#{zebra_sfx}",
               "query#{zebra_sfx}_pagination",
               "action_result_panel"
             ]

      assert components["table_heading#{alpha_sfx}"]["text"] == "Alpha"
      assert components["table_heading#{zebra_sfx}"]["text"] == "Zebra"

      assert components["records_list#{alpha_sfx}"]["children"]["path"] ==
               "/records/#{runtime_name(ctx.alpha)}"
    end

    test "each section's records are scoped to its bucket", ctx do
      messages = AshA2ui.Info.build_surface(BucketWordsUI, authorize?: false)

      data_model =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/", "value" => value}} -> value
          _ -> nil
        end)

      records = data_model["records"]

      assert [%{"word" => "fresh"}] = records["new_words"]
      assert [%{"word" => "apple"}] = records[runtime_name(ctx.alpha)]
      assert [%{"word" => "zeal"}] = records[runtime_name(ctx.zebra)]

      assert %{"search" => "", "page" => 1} = data_model["query"][runtime_name(ctx.alpha)]
      assert %{"search" => ""} = data_model["query"][runtime_name(ctx.zebra)]
    end
  end

  describe "action handler" do
    setup do
      alpha = create_bucket!("Alpha")
      zebra = create_bucket!("Zebra")

      bucketed_word!("apple", alpha)
      bucketed_word!("avocado", alpha)
      bucketed_word!("zeal", zebra)
      fresh = create_word!("fresh")

      %{alpha: alpha, zebra: zebra, fresh: fresh}
    end

    test ~s("query" targets a runtime table by its component name), ctx do
      message =
        envelope("query", %{
          "component" => runtime_name(ctx.alpha),
          "query" => %{"search" => "app", "page" => 1}
        })

      assert {:ok, messages} = ActionHandler.handle(BucketWordsUI, message, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      records_path = "/records/#{runtime_name(ctx.alpha)}"
      assert [%{"word" => "apple"}] = value_at(messages, records_path)
      assert %{"search" => "app"} = value_at(messages, "/query/#{runtime_name(ctx.alpha)}")
    end

    test ~s(a section's "query" search never leaks other buckets' rows), ctx do
      message =
        envelope("query", %{
          "component" => runtime_name(ctx.alpha),
          "query" => %{"search" => "zeal", "page" => 1}
        })

      assert {:ok, messages} = ActionHandler.handle(BucketWordsUI, message, authorize?: false)
      assert value_at(messages, "/records/#{runtime_name(ctx.alpha)}") == []
    end

    test "a template-key refresh re-reads every runtime table of the set", ctx do
      message = envelope("invoke", %{"action" => "approve", "recordId" => ctx.fresh.id})

      assert {:ok, messages} = ActionHandler.handle(BucketWordsUI, message, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      emitted = paths(messages)

      assert "/records/new_words" in emitted
      assert "/records/#{runtime_name(ctx.alpha)}" in emitted
      assert "/records/#{runtime_name(ctx.zebra)}" in emitted
    end

    test "a refresh scoped to the template set skips static tables", ctx do
      [apple | _rest] = Ash.read!(BucketWord, authorize?: false)

      message = envelope("invoke", %{"action" => "destroy", "recordId" => apple.id})

      assert {:ok, messages} = ActionHandler.handle(BucketWordsUI, message, authorize?: false)

      emitted = paths(messages)
      refute "/records/new_words" in emitted
      assert "/records/#{runtime_name(ctx.alpha)}" in emitted
      assert "/records/#{runtime_name(ctx.zebra)}" in emitted
    end
  end

  describe "v1.0" do
    setup do
      alpha = create_bucket!("Alpha")
      apple = bucketed_word!("apple", alpha)
      %{alpha: alpha, apple: apple}
    end

    test "the surface bootstraps as one schema-valid inline createSurface", ctx do
      assert [message] = AshA2ui.Info.build_surface(BucketWordsV1UI, authorize?: false)
      assert_valid_server_message(message, :v1_0)

      create = message["createSurface"]
      assert [%{"word" => "apple"}] = create["dataModel"]["records"][runtime_name(ctx.alpha)]

      heading =
        Enum.find(create["components"], &(&1["id"] == "table_heading_#{runtime_name(ctx.alpha)}"))

      assert heading["text"] == "## Alpha"
    end

    test "an actionId'd invoke on a section row is answered with an actionResponse", ctx do
      message = %{
        "version" => "v1.0",
        "action" => %{
          "name" => "invoke",
          "surfaceId" => "bucket_words_v1",
          "actionId" => "act_1",
          "context" => %{"action" => "destroy", "recordId" => ctx.apple.id}
        }
      }

      assert {:ok, [response | followups]} =
               ActionHandler.handle(BucketWordsV1UI, message, authorize?: false)

      assert response["actionId"] == "act_1"
      assert %{"value" => %{"status" => "ok"}} = response["actionResponse"]
      assert_valid_server_message(response, :v1_0)

      assert value_at(followups, "/records/#{runtime_name(ctx.alpha)}") == []
    end
  end
end

defmodule AshA2ui.SectionsVerifierTest do
  @moduledoc """
  Compile-time failure tests for `AshA2ui.Verifiers.VerifySections`, using
  the `capture_io(:stderr)` + regex pattern from the existing verifier
  suites.
  """

  # Not async: capture_io(:stderr) captures a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "sections on a non-table component does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule FormSections do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :form do
              fields [:word]

              sections do
                source AshA2ui.Test.Bucket
                scope_by :bucket_id
              end
            end
          end
        end
      end)

    assert result =~ ~r/component :form cannot declare a sections block/
    assert result =~ ~r/only supported on :table components/
  end

  test "a sections block combined with select_context does not compile cleanly" do
    result =
      capture_io(:stderr, fn ->
        defmodule SectionsWithSelectContext do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            context :word do
              resource AshA2ui.Test.BucketWord
              option_label :word
            end

            component :table, :per_bucket do
              fields [:word]
              read_action :bucketed
              select_context :word

              sections do
                source AshA2ui.Test.Bucket
                scope_by :bucket_id
              end
            end
          end
        end
      end)

    assert result =~ ~r/cannot combine a sections block with select_context/
  end

  test "scope_by must be a public attribute of the table's resource" do
    result =
      capture_io(:stderr, fn ->
        defmodule BadScopeBy do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table, :per_bucket do
              fields [:word]
              read_action :bucketed

              sections do
                source AshA2ui.Test.Bucket
                scope_by :nope
              end
            end
          end
        end
      end)

    assert result =~ ~r/scope_by :nope is not a public attribute/
  end

  test "label must be a public attribute of the section source" do
    result =
      capture_io(:stderr, fn ->
        defmodule BadLabel do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table, :per_bucket do
              fields [:word]
              read_action :bucketed

              sections do
                source AshA2ui.Test.Bucket
                scope_by :bucket_id
                label :nope
              end
            end
          end
        end
      end)

    assert result =~ ~r/label :nope is not a public attribute of the section source/
  end

  test "read_action must be a read action of the section source" do
    result =
      capture_io(:stderr, fn ->
        defmodule BadReadAction do
          @moduledoc false
          use AshA2ui.Standalone

          a2ui do
            for_resource AshA2ui.Test.BucketWord

            component :table, :per_bucket do
              fields [:word]
              read_action :bucketed

              sections do
                source AshA2ui.Test.Bucket
                scope_by :bucket_id
                read_action :nope
              end
            end
          end
        end
      end)

    assert result =~ ~r/read_action :nope is not a read action of the section source/
  end
end
