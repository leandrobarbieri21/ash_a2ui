defmodule AshA2ui.QueryHiddenFiltersTest do
  @moduledoc """
  `hidden_filters` leaves a filter's picker out of a query's controls when
  the page sets that filter itself. The filter still applies: the query
  action accepts it. Each entry must be in `filters`, and the option
  round-trips through dynamic specs.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.QueryRunner
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{LinkedFiltersUI, Paginated}

  defp components(ui) do
    [_create, components, _data] = AshA2ui.Info.build_surface(ui, authorize?: false)
    Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
  end

  test "every filter gets a picker by default" do
    components = components(Paginated)

    assert %{"component" => "ChoicePicker"} = components["query_filter_status"]
    assert %{"component" => "ChoicePicker"} = components["query_filter_category"]
  end

  test "hidden_filters leaves those pickers out of the controls, and only those" do
    components = components(LinkedFiltersUI)

    refute Map.has_key?(components, "query_filter_secret")

    assert components["query_controls_body"]["children"] == [
             "query_filter_status",
             "query_apply_button"
           ]
  end

  test "a hidden filter still applies" do
    view = ResolvedView.resolve(LinkedFiltersUI)
    context = %{"query" => %{"filters" => %{"secret" => "true"}}}

    assert {:ok, params} = QueryRunner.parse(view, context)
    assert params.filters == [secret: true]
  end

  test "hidden_filters must name entries of filters" do
    result =
      capture_io(:stderr, fn ->
        Module.create(
          Module.concat(__MODULE__, :"Fixture#{System.unique_integer([:positive])}"),
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :status, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                filters [:status]
                hidden_filters [:title]
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end,
          Macro.Env.location(__ENV__)
        )
      end)

    assert result =~ ~r/hidden_filters \[:title\] are not in its filters/
  end

  test "the option round-trips through a dynamic spec" do
    {:ok, spec, _rejections} = Importer.import(LinkedFiltersUI)
    assert [%{"hidden_filters" => ["secret"]}] = spec["queries"]

    allowlist = Dynamic.allowlist([AshA2ui.Test.BulkTask])
    {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)
    [_create, message, _data] = Dynamic.build_surface(surface, authorize?: false)
    ids = Enum.map(message["updateComponents"]["components"], & &1["id"])

    assert "query_filter_status" in ids
    refute "query_filter_secret" in ids
  end
end
