defmodule AshA2ui.QueryHubTest do
  @moduledoc """
  The hub filter bar and table header (admin catalog 1.10): multi-select
  and grouped filter options, facet counts, filter hints and labels, path
  filters, a search placeholder and aggregate search, bare controls, page
  size options, column help, detail help, a header sorted by another field,
  the fields' column order, and the compile-time checks for each.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshA2ui.QueryRunner
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.{HubContract, HubLine, HubRole, HubUI, SchemaHelper}

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    :ok
  end

  defp contract!(name, status, properties, vendor, attrs \\ %{}) do
    contract =
      Ash.create!(HubContract, Map.merge(%{name: name, status: status}, attrs), authorize?: false)

    for property <- properties do
      Ash.create!(HubLine, %{property: property, contract_id: contract.id}, authorize?: false)
    end

    Ash.create!(HubRole, %{role: :vendor, party_name: vendor, contract_id: contract.id},
      authorize?: false
    )

    Ash.create!(HubRole, %{role: :pmc, party_name: "Acme PMC", contract_id: contract.id},
      authorize?: false
    )

    contract
  end

  defp seed! do
    contract!("Roofing", :active, ["Elm", "Oak"], "Roofs Inc")
    contract!("Plumbing", :expiring_soon, ["Oak"], "Pipes Ltd", %{verified: true})
    contract!("HVAC", :renewal_scheduled, ["Pine"], "Air Co", %{status_help: "Renews itself."})
    contract!("Secret", :active, ["Hidden"], "Spy Co", %{secret: true})
  end

  defp surface(opts \\ [authorize?: false]) do
    [_create, components, data] = AshA2ui.Info.build_surface(HubUI, opts)
    by_id = Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
    {by_id, data["updateDataModel"]["value"]}
  end

  defp run!(state, opts \\ [authorize?: false]) do
    view = ResolvedView.resolve(HubUI)
    {:ok, params} = QueryRunner.parse(view, %{"query" => state})
    {:ok, records, state} = QueryRunner.run(view, params, opts)
    {Enum.map(records, & &1.name) |> Enum.sort(), state}
  end

  describe "the controls (admin catalog)" do
    test "controls_card false emits the Row itself under the controls id" do
      {components, _data} = surface()

      assert %{"component" => "Row", "align" => "end", "children" => children} =
               components["query_controls"]

      refute Map.has_key?(components, "query_controls_body")

      assert children == [
               "query_search_input",
               "query_filter_status",
               "query_filter_verified",
               "query_filter_property",
               "query_filter_vendor",
               "query_apply_button"
             ]
    end

    test "the search box carries the placeholder and keeps its label" do
      {components, _data} = surface()

      assert components["query_search_input"] == %{
               "id" => "query_search_input",
               "component" => "TextField",
               "label" => "Search",
               "placeholder" => "Search contracts or vendors",
               "value" => %{"path" => "/query/search"}
             }
    end

    test "a multi-select picker: no All, grouped options, hint, counts, the field's label" do
      {components, _data} = surface()

      assert components["query_filter_status"] == %{
               "id" => "query_filter_status",
               "component" => "ChoicePicker",
               "label" => "Contract status",
               "variant" => "multipleSelection",
               "value" => %{"path" => "/query/filters/status"},
               "hint" => "Statuses update nightly.",
               "counts" => %{"path" => "/query/facets/status"},
               "options" => [
                 %{"label" => "Active", "value" => "active"},
                 %{"label" => "Expiring soon", "value" => "expiring", "group" => true},
                 %{
                   "label" => "Expiring soon",
                   "value" => "expiring_soon",
                   "parent" => "expiring"
                 },
                 %{
                   "label" => "Renewal scheduled",
                   "value" => "renewal_scheduled",
                   "parent" => "expiring"
                 },
                 %{"label" => "Expired", "value" => "expired"},
                 %{"label" => "Draft", "value" => "draft"}
               ]
             }
    end

    test "a single-select picker keeps All and its variant" do
      {components, _data} = surface()

      assert %{
               "variant" => "mutuallyExclusive",
               "label" => "Verified",
               "options" => [%{"label" => "All", "value" => ""} | _]
             } = components["query_filter_verified"]
    end

    test "path filter pickers bind their options from the query state" do
      {components, _data} = surface()

      assert components["query_filter_property"] == %{
               "id" => "query_filter_property",
               "component" => "ChoicePicker",
               "label" => "Property",
               "variant" => "multipleSelection",
               "value" => %{"path" => "/query/filters/property"},
               "options" => [],
               "dynamicOptions" => %{"path" => "/query/options/property"},
               "counts" => %{"path" => "/query/facets/property"}
             }

      # No filter_labels entry: the declared field label of :vendor_name is
      # not the filter's (the filter is named :vendor), so it humanizes.
      assert components["query_filter_vendor"]["label"] == "Vendor"
    end

    test "the pager offers the page sizes, with the page-1 query envelope" do
      {components, _data} = surface()

      assert %{
               "pageSizeOptions" => [2, 10],
               "pageSizeAction" => %{
                 "name" => "query",
                 "context" => %{
                   "query" => %{"path" => "/query"},
                   "page" => 1,
                   "component" => "table"
                 }
               }
             } = components["pagination"]
    end
  end

  describe "empty states" do
    test "the emptyState binds the query state's choice and carries the clear action" do
      {components, data} = surface()

      assert %{
               "title" => %{"path" => "/query/emptyState/title"},
               "message" => %{"path" => "/query/emptyState/message"},
               "icon" => %{"path" => "/query/emptyState/icon"},
               "clearVisible" => %{"path" => "/query/emptyState/clear"},
               "clearAction" => %{
                 "label" => "Clear search and filters",
                 "action" => %{
                   "name" => "query",
                   "context" => %{"query" => %{"path" => "/query"}, "page" => 1}
                 }
               }
             } = components["empty_state"]

      assert data["query"]["emptyState"] == %{
               "title" => "No contracts yet",
               "message" => "Contracts you add show here.",
               "icon" => "inbox",
               "clear" => false
             }
    end

    test "no results while searching or filtering, the preset's own state otherwise" do
      {_names, state} = run!(%{"search" => "nothing"})

      assert state["emptyState"] == %{
               "title" => "No results",
               "message" => "Try other words or filters.",
               "icon" => "search",
               "clear" => true
             }

      {_names, state} = run!(%{"filters" => %{"status" => ["draft"]}})
      assert state["emptyState"]["clear"] == true

      {_names, state} = run!(%{"preset" => "archived"})

      assert state["emptyState"] == %{
               "title" => "No archived contracts",
               "message" => "",
               "icon" => "archive",
               "clear" => false
             }
    end

    test "tables without empty states keep the plain emptyState" do
      {components, _data} =
        AshA2ui.Test.ColumnTask
        |> AshA2ui.Info.build_surface(authorize?: false)
        |> Enum.at(1)
        |> then(&{Map.new(&1["updateComponents"]["components"], fn c -> {c["id"], c} end), nil})

      assert components["empty_state"] == %{
               "id" => "empty_state",
               "component" => "emptyState",
               "message" => %{"path" => "_empty_message"},
               "children" => []
             }
    end
  end

  describe "the controls (basic catalog)" do
    setup do
      Application.put_env(:ash_a2ui, :catalog, :basic)
      :ok
    end

    test "only spec keys: groups flatten, no hint, counts, placeholder or path pickers" do
      {components, _data} = surface()

      status = components["query_filter_status"]
      refute Map.has_key?(status, "hint")
      refute Map.has_key?(status, "counts")
      assert status["variant"] == "multipleSelection"
      assert Enum.all?(status["options"], &(Map.keys(&1) |> Enum.sort() == ["label", "value"]))
      assert length(status["options"]) == 5

      refute Map.has_key?(components["query_search_input"], "placeholder")
      refute Map.has_key?(components, "query_filter_property")
      refute Map.has_key?(components, "query_filter_vendor")
    end

    test "the basic surface stays valid against the A2UI schema" do
      HubUI
      |> AshA2ui.Info.build_surface(authorize?: false)
      |> Enum.each(&SchemaHelper.assert_valid_server_message/1)
    end
  end

  describe "goldens" do
    @golden_dir Path.expand("golden", __DIR__)

    # The hub surface's components, per catalog. Re-record on purpose with
    # `RECORD_HUB_GOLDEN=1 mix test test/ash_a2ui/query_hub_test.exs`.
    for catalog <- [:admin_v1, :basic] do
      test "the hub components match the #{catalog} golden" do
        Application.put_env(:ash_a2ui, :catalog, unquote(catalog))
        [_create, components, _data] = AshA2ui.Info.build_surface(HubUI, authorize?: false)
        json = Jason.encode!(components, pretty: true)
        path = Path.join(@golden_dir, "hub_#{unquote(catalog)}_components.json")

        if System.get_env("RECORD_HUB_GOLDEN") do
          File.mkdir_p!(@golden_dir)
          File.write!(path, json)
        end

        assert Jason.decode!(json) == path |> File.read!() |> Jason.decode!()
      end
    end
  end

  describe "the grid columns" do
    test "column_order :fields keeps the fields' order, with help, sortField and helpPath" do
      {components, _data} = surface()

      assert [name, property, status] = components["data_grid"]["columns"]
      assert name["path"] == "name"

      assert property["help"] == %{
               "title" => "Property",
               "body" => "Where the work happens.\n\n**Portfolio** — every property of the PMC."
             }

      assert %{
               "path" => "status_text",
               "label" => "Status",
               "sortable" => true,
               "sortField" => "status",
               "badge" => %{
                 "path" => "_badge_status_text",
                 "tonePath" => "_badge_tone_status_text"
               },
               "detail" => %{
                 "path" => "_detail_status_text",
                 "helpPath" => "_detail_help_status_text"
               }
             } = status
    end

    test "widths, the more values list and its noun" do
      {components, _data} = surface()
      [name, property | _] = components["data_grid"]["columns"]

      assert name["width"] == 320
      assert property["moreNoun"] == "properties"

      assert property["more"] == %{
               "path" => "line_count",
               "valuesPath" => "_more_values_property_name"
             }

      assert components["data_grid"]["rowClick"]["width"] == 96
      refute Enum.any?(components["data_grid"]["columns"], &(&1["path"] == "property_names"))

      seed!()
      {_components, data} = surface()
      rows = Map.new(data["records"], &{&1["name"], &1})
      assert rows["HVAC"]["_more_values_property_name"] == ["Pine"]

      {_components, data} = surface(authorize?: false, query_state: %{"pageSize" => 10})
      roofing = Enum.find(data["records"], &(&1["name"] == "Roofing"))
      assert Enum.sort(roofing["_more_values_property_name"]) == ["Elm", "Oak"]
    end

    test "rows carry the detail help and the new tones" do
      seed!()
      contract!("Windows", :expired, ["Elm"], "Glass Co")
      contract!("Painting", :draft, ["Oak"], "Paint Co")

      {_records, state} = run!(%{"pageSize" => 10})
      assert state["totalCount"] == 6

      {_components, data} = surface(authorize?: false, query_state: %{"pageSize" => 10})
      rows = Map.new(data["records"], &{&1["name"], &1})

      assert rows["HVAC"]["_detail_help_status_text"] == "Renews itself."
      assert rows["HVAC"]["_detail_status_text"] == "Renews soon"
      assert rows["Roofing"]["_detail_help_status_text"] == ""
      assert rows["Windows"]["_badge_tone_status_text"] == "gray"
      assert rows["Painting"]["_badge_tone_status_text"] == "pending"
      refute Map.has_key?(rows["HVAC"], "_detail_help_name")
    end
  end

  describe "the runner" do
    setup do
      seed!()
      :ok
    end

    test "multi-select filters echo lists; leaf values filter with in" do
      {names, state} = run!(%{"filters" => %{"status" => ["expiring_soon", "renewal_scheduled"]}})

      assert names == ["HVAC", "Plumbing"]
      assert state["filters"]["status"] == ["expiring_soon", "renewal_scheduled"]
      assert state["filters"]["property"] == []

      {_names, state} = run!(%{"filters" => %{"status" => ["active"]}})
      assert state["filters"]["status"] == ["active"]
    end

    test "a path filter over a to-many path matches any related value" do
      {names, _state} = run!(%{"filters" => %{"property" => ["Elm"]}, "pageSize" => 10})
      assert names == ["Roofing"]

      {names, _state} = run!(%{"filters" => %{"property" => ["Oak"]}, "pageSize" => 10})
      assert names == ["Plumbing", "Roofing"]
    end

    test "a path filter over a filtered aggregate never matches the other party" do
      {names, _state} = run!(%{"filters" => %{"vendor" => ["Air Co"]}})
      assert names == ["HVAC"]

      {names, _state} = run!(%{"filters" => %{"vendor" => ["Acme PMC"]}})
      assert names == []
    end

    test "search reaches a string aggregate (the vendor), not the other party" do
      {names, _state} = run!(%{"search" => "pipes"})
      assert names == ["Plumbing"]

      {names, _state} = run!(%{"search" => "acme"})
      assert names == []
    end

    test "path filter options: distinct, sorted, the actor's readable records only" do
      {_names, state} = run!(%{}, authorize?: true, actor: %{id: 1})

      assert state["options"]["property"] == [
               %{"label" => "Elm", "value" => "Elm"},
               %{"label" => "Oak", "value" => "Oak"},
               %{"label" => "Pine", "value" => "Pine"}
             ]

      assert Enum.map(state["options"]["vendor"], & &1["value"]) == [
               "Air Co",
               "Pipes Ltd",
               "Roofs Inc"
             ]
    end

    test "facets count every other filter, not the field's own selection" do
      {_names, state} =
        run!(%{"filters" => %{"status" => ["active"], "property" => ["Oak"]}},
          authorize?: true,
          actor: %{id: 1}
        )

      # status: counted with property=Oak, not with status=active.
      assert state["facets"]["status"] == %{
               "active" => 1,
               "expiring_soon" => 1,
               "renewal_scheduled" => 0,
               "expired" => 0,
               "draft" => 0,
               "expiring" => 1
             }

      # property: counted with status=active (the secret contract is not
      # readable, so its "Hidden" property never shows).
      assert state["facets"]["property"] == %{"Elm" => 1, "Oak" => 1, "Pine" => 0}
      assert state["facets"]["verified"] == %{"true" => 0, "false" => 1}
      assert state["facets"]["vendor"]["Roofs Inc"] == 1
    end

    test "facets follow search too" do
      {_names, state} = run!(%{"search" => "hvac"})
      assert state["facets"]["status"]["renewal_scheduled"] == 1
      assert state["facets"]["status"]["expiring"] == 1
      assert state["facets"]["status"]["active"] == 0
    end

    test "a state built without a read holds empty facets and options" do
      view = ResolvedView.resolve(HubUI)
      state = QueryRunner.state(view.query, QueryRunner.default_params(view.query), 0, false)

      assert state["facets"] == %{
               "status" => %{},
               "verified" => %{},
               "property" => %{},
               "vendor" => %{}
             }

      assert state["options"] == %{"property" => [], "vendor" => []}
    end

    test "page sizes: a listed size is taken, others are rejected" do
      view = ResolvedView.resolve(HubUI)

      assert {:ok, %{page_size: 10}} =
               QueryRunner.parse(view, %{"query" => %{"pageSize" => 10}, "page" => 1})

      assert {:error, reason} = QueryRunner.parse(view, %{"query" => %{"pageSize" => 7}})
      assert reason =~ "Page size 7 is not offered"
    end

    test "a size change starts again at page 1, however it is sent" do
      view = ResolvedView.resolve(HubUI)
      {_names, state} = run!(%{"page" => 2})
      assert state["appliedPageSize"] == 2

      resized = %{"query" => Map.merge(state, %{"pageSize" => 10}), "pageDelta" => 0}
      assert {:ok, %{page: 1, page_size: 10}} = QueryRunner.parse(view, resized)

      same = %{"query" => state, "pageDelta" => 0}
      assert {:ok, %{page: 2}} = QueryRunner.parse(view, same)
    end

    test "path filter names are allowlisted like filters" do
      view = ResolvedView.resolve(HubUI)

      assert {:error, reason} =
               QueryRunner.parse(view, %{"query" => %{"filters" => %{"lines" => ["Elm"]}}})

      assert reason =~ "is not allowlisted"

      assert {:ok, %{filters: [property: ["Elm", "Oak"]]}} =
               QueryRunner.parse(view, %{
                 "query" => %{"filters" => %{"property" => ["Elm", "Oak"]}}
               })
    end
  end

  test "queries without the new options keep their state shape" do
    view = ResolvedView.resolve(AshA2ui.Test.Paginated)
    state = QueryRunner.state(view.query, QueryRunner.default_params(view.query), 0, false)
    refute Map.has_key?(state, "facets")
    refute Map.has_key?(state, "options")
  end

  describe "compile-time checks" do
    defp compile(query_body, table_body \\ quote(do: nil)) do
      capture_io(:stderr, fn ->
        Module.create(
          Module.concat(__MODULE__, :"Fixture#{System.unique_integer([:positive])}"),
          quote do
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.HubContract

              query :default do
                sortable [:name]
                filters [:status, :verified]
                unquote(query_body)
              end

              component :table do
                fields [:name, :status, :status_text, :status_help]
                query :default
                unquote(table_body)
              end
            end
          end,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    test "a path filter must reach a public attribute" do
      assert compile(quote(do: path_filters(property: [:lines, :nope]))) =~
               ~r/path_filters :property: :nope is not a public attribute/

      assert compile(quote(do: path_filters(property: [:nope, :property]))) =~
               ~r/step :nope of \[:nope, :property\] is not a public relationship/

      assert compile(quote(do: path_filters(status: :vendor_name))) =~
               ~r/:status is already in filters/
    end

    test "filter options must name filters of the query" do
      assert compile(quote(do: multi_select_filters([:name]))) =~
               ~r/multi_select_filters \[:name\] are not filters of the query/

      assert compile(quote(do: filter_hints(name: "x"))) =~
               ~r/filter_hints \[:name\] are not filters of the query/

      assert compile(quote(do: facet_counts([:name]))) =~
               ~r/facet_counts \[:name\] are not filters of the query/
    end

    test "groups gather declared choices, a value of their own, each leaf once" do
      assert compile(quote(do: filter_groups(status: [soon: [:nope]]))) =~
               ~r/leaves \["nope"\] are not choices of the field/

      assert compile(quote(do: filter_groups(status: [active: [:active, :draft]]))) =~
               ~r/group values \["active"\] are also leaf values/

      assert compile(quote(do: filter_groups(status: [a: [:draft], b: [:draft]]))) =~
               ~r/leaves \["draft"\] are in more than one group/

      assert compile(quote(do: filter_groups(verified: [a: [true]]))) =~
               ~r/:verified declares no choices/

      assert compile(
               quote do
                 filter_groups(status: [soon: [:draft]])
                 group_labels(status: [later: "Later"])
               end
             ) =~ ~r/group_labels \[:later\] are not groups of the field/
    end

    test "variant empty states need the query's own, more_values needs more" do
      assert compile(quote(do: no_results_state(title: "None"))) =~
               ~r/declares no_results_state without its own empty_state/

      assert compile(
               quote(do: nil),
               quote do
                 column :name do
                   more_values(:status_help)
                 end
               end
             ) =~ ~r/declares more_values without a more field/
    end

    test "page sizes stay within max_page_size" do
      assert compile(quote(do: page_size_options([10, 500]))) =~
               ~r/page_size_options \[500\] exceed max_page_size 100/
    end

    test "a column's sort_by must be sortable, detail_help needs a detail, help_title needs help" do
      assert compile(
               quote(do: nil),
               quote do
                 column :status_text do
                   sort_by(:status)
                 end
               end
             ) =~ ~r/column :status_text sort_by :status must be in the sortable list/

      assert compile(
               quote(do: nil),
               quote do
                 column :status_text do
                   detail_help(:status_help)
                 end
               end
             ) =~ ~r/declares detail_help without a detail field/

      assert compile(
               quote(do: nil),
               quote do
                 column :name do
                   help_title("Name")
                 end
               end
             ) =~ ~r/declares help_title without help/
    end

    test "the hub fixture itself compiles cleanly" do
      assert compile(
               quote do
                 path_filters(property: [:lines, :property], vendor: :vendor_name)
                 multi_select_filters([:status, :property])
                 filter_groups(status: [soon: [:expiring_soon, :renewal_scheduled]])
                 facet_counts(true)
                 page_size_options([10, 25])
               end
             ) == ""
    end
  end

  describe "filter_order" do
    test "orders the pickers by the listed names, the rest after in declared order" do
      query = %AshA2ui.Query{
        filters: [:status, :verification, :expiry],
        path_filters: [property: [:lines, :property, :name], vendor: :vendor_name],
        filter_order: [:status, :verification, :property, :vendor]
      }

      assert AshA2ui.Query.filter_names(query) ==
               [:status, :verification, :property, :vendor, :expiry]
    end

    test "unset keeps filters first, then path filters" do
      query = %AshA2ui.Query{filters: [:status], path_filters: [vendor: :vendor_name]}
      assert AshA2ui.Query.filter_names(query) == [:status, :vendor]
    end
  end
end
