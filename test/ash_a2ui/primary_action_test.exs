defmodule AshA2ui.PrimaryActionTest do
  @moduledoc """
  `primary_action` draws a table's row click as one button per row, with a
  label and a variant chosen per row from `label_from`. The admin dataGrid's
  `rowClick` gains `labelPath`, `variantPath` and `inline`; rows carry
  `_primary_label` and `_primary_variant`, on the first render and on every
  refresh. Tables without it are unchanged. The renderer half is driven in a
  browser by `priv/js/probe/primary_action_probe.mjs`.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  require Ash.Query

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{Paginated, Submission}

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)

    Submission |> Ash.read!(authorize?: false) |> Enum.each(&Ash.destroy!(&1, authorize?: false))

    for {title, state} <- [
          {"Draft one", :draft},
          {"Sent one", :submitted},
          {"Done one", :approved}
        ] do
      Ash.create!(Submission, %{title: title, state: state}, authorize?: false)
    end

    :ok
  end

  defp surface(ui) do
    [_create, components, data] = AshA2ui.Info.build_surface(ui, authorize?: false)
    by_id = Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
    {by_id, data["updateDataModel"]["value"]}
  end

  defp rows_by_title(records), do: Map.new(records, &{&1["title"], &1})

  test "the row click names the row's label and variant and asks to be drawn inline" do
    {by_id, _data} = surface(Submission)
    grid = by_id["data_grid"]

    assert grid["rowClick"] == %{
             "label" => "View",
             "action" => "view_record",
             "context" => %{"recordId" => %{"path" => "id"}, "component" => "table"},
             "labelPath" => "_primary_label",
             "variantPath" => "_primary_variant",
             "inline" => true
           }

    # the button is the row's View, so View leaves the row actions; the
    # others stay
    actions = Enum.map(grid["rowActions"], & &1["action"])
    refute "view_record" in actions
    assert "start_edit" in actions

    catalog = "priv/a2ui/admin_v1/catalog.json" |> File.read!() |> Jason.decode!()

    schema =
      catalog["components"]["dataGrid"]
      |> Map.put("$defs", catalog["$defs"] || %{})
      |> ExJsonSchema.Schema.resolve()

    assert ExJsonSchema.Validator.validate(schema, grid) == :ok
  end

  test "each row carries its label and variant; unmapped values get the defaults" do
    {_by_id, data} = surface(Submission)
    rows = rows_by_title(data["records"])

    assert %{"_primary_label" => "Review", "_primary_variant" => "primary"} = rows["Sent one"]
    assert %{"_primary_label" => "Finish", "_primary_variant" => "default"} = rows["Draft one"]

    # :view has no labels/variants entry: the row click's label and `variant`
    assert %{"_primary_label" => "View", "_primary_variant" => "borderless"} = rows["Done one"]

    # label_from is loaded for the table without being one of its columns
    refute Map.has_key?(rows["Sent one"], "next_step")
  end

  test "a refreshed row (serialize_row, as every handler refresh) carries the same keys" do
    view = ResolvedView.resolve(Submission)
    [table] = view.tables

    record =
      Submission
      |> Ash.Query.filter(title == "Sent one")
      |> Ash.Query.load(table.loads)
      |> Ash.read_one!(authorize?: false)

    row = V0_9_1.serialize_row(view, table, record, nil)

    assert row["_primary_label"] == "Review"
    assert row["_primary_variant"] == "primary"
  end

  test "a table without primary_action is unchanged" do
    {by_id, data} = surface(Paginated)

    refute Map.has_key?(by_id["data_grid"]["rowClick"], "inline")
    refute Map.has_key?(by_id["data_grid"]["rowClick"], "labelPath")
    refute Enum.any?(data["records"], &Map.has_key?(&1, "_primary_label"))
  end

  describe "dynamic specs" do
    test "import, resolve, build and promote carry the primary action" do
      {:ok, spec, _rejections} = Importer.import(Submission)
      table = Enum.find(spec["components"], &(&1["kind"] == "table"))

      assert table["primary_action"] == %{
               "label_from" => "next_step",
               "labels" => %{"finish" => "Finish", "review" => "Review"},
               "variants" => %{"finish" => "default", "review" => "primary"},
               "variant" => "borderless"
             }

      allowlist = Dynamic.allowlist([Submission])
      {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)

      [_create, components, data] = Dynamic.build_surface(surface, authorize?: false)
      grid = Enum.find(components["updateComponents"]["components"], &(&1["id"] == "data_grid"))
      assert grid["rowClick"]["inline"] == true

      assert %{"_primary_label" => "Review"} =
               rows_by_title(data["updateDataModel"]["value"]["records"])["Sent one"]

      {:ok, source} =
        Dynamic.to_dsl_source(spec,
          module: AshA2ui.Promoted.SubmissionsPrimary,
          allowlist: allowlist,
          surface_id: "promoted_submissions"
        )

      assert source =~ "primary_action do"
      assert source =~ "label_from :next_step"
      assert source =~ "variant :borderless"

      [{module, _binary} | _rest] = Code.compile_string(source)
      [table] = ResolvedView.resolve(module).tables

      assert table.component.primary_action ==
               hd(surface_tables(surface)).component.primary_action
    end

    test "an unknown variant in a spec is rejected" do
      {:ok, spec, _rejections} = Importer.import(Submission)

      spec =
        update_in(spec, ["components"], fn components ->
          Enum.map(components, fn
            %{"kind" => "table"} = table -> put_in(table, ["primary_action", "variant"], "loud")
            other -> other
          end)
        end)

      allowlist = Dynamic.allowlist([Submission])
      assert {:error, [error]} = Dynamic.resolve(spec, allowlist: allowlist)
      assert error.path =~ "primary_action"
    end

    defp surface_tables(surface), do: ResolvedView.resolve(surface.dsl_state).tables
  end

  describe "verifier" do
    defp define(body) do
      capture_io(:stderr, fn ->
        Module.create(
          Module.concat(__MODULE__, :"Fixture#{System.unique_integer([:positive])}"),
          body,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    defp resource(a2ui) do
      quote do
        use Ash.Resource, domain: nil, extensions: [AshA2ui]

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :state, :atom, public?: true
        end

        actions do
          defaults [:read, create: :*, update: :*]
        end

        a2ui do
          unquote(a2ui)
        end
      end
    end

    @form (quote do
             component :form do
               fields [:title]
               create_action :create
               update_action :update
             end
           end)

    test "a valid primary_action compiles cleanly" do
      result =
        define(
          resource(
            quote do
              component :table do
                fields [:title]

                primary_action do
                  label_from(:state)
                  labels open: "Review"
                  variants(open: :primary)
                end
              end

              unquote(@form)
            end
          )
        )

      refute result =~ "primary_action"
    end

    test "a table without a row click is rejected" do
      result =
        define(
          resource(
            quote do
              component :table do
                fields [:title]

                primary_action do
                  label "Open"
                end
              end
            end
          )
        )

      assert result =~ ~r/declares a primary_action but has no row click to draw/
    end

    test "label_from must be a public field of the table's resource" do
      result =
        define(
          resource(
            quote do
              component :table do
                fields [:title]

                primary_action do
                  label_from(:nope)
                end
              end

              unquote(@form)
            end
          )
        )

      assert result =~ ~r/label_from :nope, which is not a public attribute/
    end

    test "labels and variants need label_from" do
      result =
        define(
          resource(
            quote do
              component :table do
                fields [:title]

                primary_action do
                  labels open: "Review"
                end
              end

              unquote(@form)
            end
          )
        )

      assert result =~ ~r/declares labels or variants without label_from/
    end

    test "variants must be Button variants" do
      result =
        define(
          resource(
            quote do
              component :table do
                fields [:title]

                primary_action do
                  label_from(:state)
                  variants(open: :loud)
                end
              end

              unquote(@form)
            end
          )
        )

      assert result =~ ~r/has an unknown variant in variants/
    end

    test "only tables take a primary_action" do
      result =
        define(
          resource(
            quote do
              component :table do
                fields [:title]
              end

              component :form do
                fields [:title]
                create_action :create

                primary_action do
                  label "Open"
                end
              end
            end
          )
        )

      assert result =~ ~r/`primary_action` is only supported on :table components/
    end
  end
end
