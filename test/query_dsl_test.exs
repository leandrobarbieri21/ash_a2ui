defmodule AshA2ui.QueryDslTest do
  @moduledoc """
  DSL parsing, `Info.queries/1`, `ResolvedView` resolution, and compile-time
  verifier tests for the `query` entity — the named, server-enforced allowlist
  for search/sort/filter/pagination.
  """

  # Not async: the verifier tests use capture_io(:stderr), a global device.
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.Paginated

  describe "query entity parsing" do
    test "query options parse with entity-schema defaults" do
      assert [query] = AshA2ui.Info.queries(Paginated)

      assert %AshA2ui.Query{
               name: :default,
               search_fields: [:name],
               sortable: [:name, :inserted_at],
               filters: [:status, :category],
               default_sort: [name: :asc],
               page_size: 5,
               max_page_size: 10
             } = query
    end

    test "page_size and max_page_size default to 25 and 100" do
      defmodule Defaulted do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshA2ui]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read]
        end

        a2ui do
          query :default do
            sortable [:name]
          end

          component :table do
            fields [:name]
            query :default
          end
        end
      end

      assert [query] = AshA2ui.Info.queries(Defaulted)

      assert %AshA2ui.Query{
               name: :default,
               search_fields: [],
               sortable: [:name],
               filters: [],
               default_sort: [],
               page_size: 25,
               max_page_size: 100
             } = query
    end

    test "a resource without query entities has none" do
      assert AshA2ui.Info.queries(AshA2ui.Test.KitchenSink) == []
    end

    test "the table component carries the query reference" do
      table = Paginated |> AshA2ui.Info.components() |> Enum.find(&(&1.name == :table))
      assert table.query == :default
    end
  end

  describe "ResolvedView query resolution" do
    test "resolves the table's referenced query config" do
      view = ResolvedView.resolve(Paginated)

      assert %AshA2ui.Query{name: :default, page_size: 5} = view.query
    end

    test "is nil when the table references no query" do
      view = ResolvedView.resolve(AshA2ui.Test.KitchenSink)
      assert view.query == nil
    end
  end

  describe "VerifyQueries" do
    test "search field that is not a public attribute does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadSearchField do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                search_fields [:nope]
              end

              component :table do
                fields [:name]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/query :default references unknown field :nope in search_fields/
    end

    test "search field that is not a string type does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule NonStringSearchField do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
              attribute :count, :integer, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                search_fields [:count]
              end

              component :table do
                fields [:name]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/search_fields entry :count must be a string/
    end

    test "sortable field that is not a public attribute does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadSortable do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
              attribute :secret, :string
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                sortable [:name, :secret]
              end

              component :table do
                fields [:name]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/query :default references unknown field :secret in sortable/
    end

    test "filter that is not a public attribute does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadFilter do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                filters [:missing]
              end

              component :table do
                fields [:name]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/query :default references unknown field :missing in filters/
    end

    test "default_sort on an unknown field does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule BadDefaultSort do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                default_sort ghost: :desc
              end

              component :table do
                fields [:name]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/query :default references unknown field :ghost in default_sort/
    end

    test "module-based (non-expression) calculation in sortable does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule ModuleCalcSortable do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            calculations do
              calculate :shout, :string, AshA2ui.Test.Article.ShoutTitle, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                sortable [:shout]
              end

              component :table do
                fields [:title, :shout]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/the calculation :shout is not sortable/
      assert result =~ ~r/expression-backed calculations/
    end

    test "expression calculation in filters compiles cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule ExprCalcFilter do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            calculations do
              calculate :loud, :string, expr(title <> "!"), public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                filters [:loud]
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        end)

      assert result == ""
    end

    test "module-based calculation in filters does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule ModuleCalcFilter do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            calculations do
              calculate :shout, :string, AshA2ui.Test.Article.ShoutTitle, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                filters [:shout]
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/the calculation :shout is not filterable/
      assert result =~ ~r/expression-backed calculations/
    end

    # A string aggregate may be searched (see query_hub_test.exs); a count
    # cannot.
    test "a non-string aggregate in search_fields does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule AggregateSearch do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :comments, AshA2ui.Test.Comment,
                destination_attribute: :article_id,
                public?: true
            end

            aggregates do
              count :comment_count, :comments, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                search_fields [:comment_count]
              end

              component :table do
                fields [:title]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/search_fields entry :comment_count must resolve to a string/
    end

    test "table referencing an undeclared query does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule MissingQueryRef do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:name]
                query :nonexistent
              end
            end
          end
        end)

      assert result =~ ~r/component :table references undeclared query :nonexistent/
    end

    test "duplicate query names do not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule DuplicateQueryNames do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                sortable [:name]
              end

              query :default do
                search_fields [:name]
              end

              component :table do
                fields [:name]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/duplicate query name :default/
    end

    test "page_size greater than max_page_size does not compile cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule PageSizeTooBig do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                page_size 200
                max_page_size 100
              end

              component :table do
                fields [:name]
                query :default
              end
            end
          end
        end)

      assert result =~ ~r/query :default page_size 200 exceeds max_page_size 100/
    end

    test "a valid query block compiles cleanly" do
      result =
        capture_io(:stderr, fn ->
          defmodule GoodQuery do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true

              attribute :status, :atom,
                public?: true,
                constraints: [one_of: [:a, :b]]
            end

            actions do
              defaults [:read]
            end

            a2ui do
              query :default do
                search_fields [:name]
                sortable [:name]
                filters [:status]
                default_sort name: :asc
              end

              component :table do
                fields [:name, :status]
                query :default
              end
            end
          end
        end)

      refute result =~ ~r/query/
    end
  end
end
