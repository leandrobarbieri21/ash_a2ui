defmodule AshA2ui.ColumnCellsTest do
  @moduledoc """
  `column` entities on a `:table`: the admin dataGrid column hints
  (`subtitle`, `icon`, `more`, `detail`, catalog 1.8), the fields they read
  from folded out of the column list, the per-row `_icon_*` / `_detail_*`
  keys, and the compile-time checks.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Importer
  alias AshA2ui.Test.ColumnTask

  setup do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)
    :ok
  end

  defp surface(resource) do
    [_create, components, data] = AshA2ui.Info.build_surface(resource, authorize?: false)
    by_id = Map.new(components["updateComponents"]["components"], &{&1["id"], &1})
    {by_id, data["updateDataModel"]["value"]}
  end

  test "the grid draws the declared columns, with the fields they read from folded in" do
    {components, _data} = surface(ColumnTask)

    assert components["data_grid"]["columns"] == [
             %{
               "label" => "Title",
               "path" => "title",
               "subtitle" => %{"path" => "assignee_name"},
               "icon" => %{
                 "path" => "_icon_title",
                 "labelPath" => "_icon_label_title",
                 "tonePath" => "_icon_tone_title"
               }
             },
             %{
               "label" => "Status",
               "path" => "status",
               "badge" => %{"path" => "_badge_status", "tonePath" => "_badge_tone_status"},
               "detail" => %{
                 "path" => "_detail_status",
                 "datePath" => "due_on",
                 "iconPath" => "_detail_icon_status",
                 "iconTonePath" => "_detail_icon_tone_status"
               }
             },
             %{
               "label" => "First tag",
               "path" => "first_tag",
               "more" => %{"path" => "tag_count", "textPath" => "_more_text_first_tag"}
             }
           ]
  end

  test "rows carry the icon, its tone and label, and the detail text and its icon" do
    Ash.create!(
      ColumnTask,
      %{
        title: "Fix the roof",
        assignee_name: "Sam Okafor",
        priority: :high,
        first_tag: "Exterior",
        tag_count: 3,
        status_detail: :overdue,
        due_on: ~D[2026-11-01]
      },
      authorize?: false
    )

    Ash.create!(ColumnTask, %{title: "Order filters", priority: :normal}, authorize?: false)

    {_components, data} = surface(ColumnTask)
    rows = Map.new(data["records"], &{&1["title"], &1})

    assert %{
             "_icon_title" => "alert",
             "_icon_tone_title" => "danger",
             "_icon_label_title" => "High priority",
             "_detail_status" => "Overdue since {date}",
             "_detail_icon_status" => "alert",
             "_detail_icon_tone_status" => "danger",
             "assignee_name" => "Sam Okafor",
             "tag_count" => 3,
             "_more_text_first_tag" => "+2 more",
             "due_on" => "2026-11-01"
           } = rows["Fix the roof"]

    # a value with no icon or detail entry, or none at all, serializes as ""
    assert %{
             "_icon_title" => "",
             "_icon_tone_title" => "neutral",
             "_icon_label_title" => "",
             "_detail_status" => "",
             "_detail_icon_status" => "",
             "_detail_icon_tone_status" => "neutral"
           } = rows["Order filters"]
  end

  describe "the \"+N more\" tag's words" do
    defmodule FrenchTag do
      @moduledoc false
      # A translator with French plural forms (1 is singular, 2 and up plural).
      @library %{
        "+%{count} more" => {"+%{count} autre", "+%{count} autres"},
        "%{count} item" => {"%{count} élément", "%{count} éléments"},
        "%{count} %{noun}" => "%{count} %{noun}",
        "%{more}, show all %{list}" => "%{more}, afficher les %{list}"
      }
      @labels %{"properties" => "propriétés"}

      def translate(msgid, bindings, _locale, meta) do
        template =
          case {meta[:domain], Map.get(@library, msgid), meta[:count]} do
            {"ash_a2ui", {one, _many}, count} when count in [0, 1] -> one
            {"ash_a2ui", {_one, many}, _count} -> many
            {"ash_a2ui", text, _count} -> text
            {_metadata, _none, _count} -> Map.get(@labels, msgid)
          end

        template && AshA2ui.L10n.interpolate(template, bindings)
      end
    end

    @column %AshA2ui.Column{
      name: :property_name,
      more: :line_count,
      more_values: :property_names,
      more_noun: "properties"
    }

    defp tag(column, record, l10n \\ nil) do
      data = AshA2ui.Column.row_data([column], record, l10n)

      Map.take(
        data,
        ~w(_more_text_property_name _more_caption_property_name _more_label_property_name)
      )
    end

    test "rows carry the tag's text, the list's caption and the tag's label" do
      record = %{
        line_count: 3,
        property_names: ["Harbourfront Tower", "Elm Court", "Maple Plaza"]
      }

      assert tag(@column, record) == %{
               "_more_text_property_name" => "+2 more",
               "_more_caption_property_name" => "3 properties",
               "_more_label_property_name" => "+2 more, show all 3 properties"
             }
    end

    test "the count picks its plural form in the reader's language" do
      l10n = AshA2ui.L10n.new(gettext_fn: {FrenchTag, :translate}, locale: "fr")
      two = %{line_count: 2, property_names: ["Elm Court", "Maple Plaza"]}
      three = %{line_count: 3, property_names: ["Harbourfront Tower", "Elm Court", "Maple Plaza"]}

      assert tag(@column, two, l10n) == %{
               "_more_text_property_name" => "+1 autre",
               "_more_caption_property_name" => "2 propriétés",
               "_more_label_property_name" => "+1 autre, afficher les 2 propriétés"
             }

      assert tag(@column, three, l10n)["_more_text_property_name"] == "+2 autres"

      unnamed = %{@column | more_noun: nil}
      assert tag(unnamed, three, l10n)["_more_caption_property_name"] == "3 éléments"
    end

    test "below two values there is no tag; without a list, no caption" do
      assert tag(@column, %{line_count: 1, property_names: ["Elm Court"]}) == %{
               "_more_text_property_name" => "",
               "_more_caption_property_name" => "",
               "_more_label_property_name" => ""
             }

      count_only = %{@column | more_values: nil}

      assert tag(count_only, %{line_count: "4"}) == %{
               "_more_text_property_name" => "+3 more",
               "_more_caption_property_name" => "",
               "_more_label_property_name" => "+3 more"
             }
    end
  end

  test "a table without columns emits no cell hints and no row keys" do
    {components, data} = surface(AshA2ui.Test.Paginated)

    for column <- components["data_grid"]["columns"] do
      refute Enum.any?(~w(subtitle icon more detail), &Map.has_key?(column, &1))
    end

    for row <- data["records"] do
      refute Enum.any?(Map.keys(row), &String.starts_with?(&1, ["_icon_", "_detail_"]))
    end
  end

  test "columns round-trip through a dynamic spec and its promoted DSL" do
    {:ok, spec, _rejections} = Importer.import(ColumnTask)
    [table] = spec["components"]

    assert [
             %{"name" => "title", "subtitle" => "assignee_name", "icon" => "priority"} = title,
             %{"name" => "first_tag", "more" => "tag_count"},
             %{"name" => "status", "detail" => "status_detail", "detail_date" => "due_on"}
           ] = table["columns"]

    assert title["icon_names"] == %{"high" => "alert", "low" => "check"}
    status = List.last(table["columns"])
    assert status["detail_icon_names"] == %{"due_soon" => "clock", "overdue" => "alert"}
    assert status["detail_icon_tones"] == %{"overdue" => "danger"}

    allowlist = Dynamic.allowlist([ColumnTask])
    {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)
    [_create, message, _data] = Dynamic.build_surface(surface, authorize?: false)
    grid = Enum.find(message["updateComponents"]["components"], &(&1["id"] == "data_grid"))
    {components, _data} = surface(ColumnTask)
    assert grid["columns"] == components["data_grid"]["columns"]

    assert {:ok, source} =
             Dynamic.to_dsl_source(spec,
               module: AshA2ui.Test.PromotedColumns,
               allowlist: allowlist
             )

    assert source =~ "column :title do"
    assert source =~ "icon_names high: :alert, low: :check"
    assert source =~ "detail_text"
    assert source =~ "detail_icon_names due_soon: :clock, overdue: :alert"
  end

  test "a dynamic spec's columns go through the same checks" do
    {:ok, spec, _rejections} = Importer.import(ColumnTask)

    bad =
      update_in(spec, ["components", Access.at(0), "columns", Access.at(0)], fn column ->
        Map.put(column, "icon_names", %{"high" => "rocket"})
      end)

    allowlist = Dynamic.allowlist([ColumnTask])
    assert {:error, [error | _]} = Dynamic.resolve(bad, allowlist: allowlist)
    assert error.message =~ "icon_names must be one of"
  end

  describe "compile-time checks" do
    defp define(table_body) do
      capture_io(:stderr, fn ->
        Module.create(
          Module.concat(__MODULE__, :"Fixture#{System.unique_integer([:positive])}"),
          quote do
            use Ash.Resource, domain: nil, extensions: [AshA2ui]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :owner, :string, public?: true
              attribute :priority, :atom, public?: true
            end

            actions do
              defaults [:read]
            end

            a2ui do
              component :table do
                fields [:title, :owner, :priority]
                unquote(table_body)
              end
            end
          end,
          Macro.Env.location(__ENV__)
        )
      end)
    end

    test "a valid column compiles cleanly" do
      assert define(
               quote do
                 column :title do
                   subtitle :owner
                 end
               end
             ) == ""
    end

    test "a column must read from table fields" do
      result =
        define(
          quote do
            column :title do
              subtitle :nope
            end
          end
        )

      assert result =~ ~r/column :title references field :nope/
    end

    test "a field a column reads from cannot be a column of its own" do
      result =
        define(
          quote do
            column :title do
              subtitle :owner
            end

            column :owner do
              icon :priority
              icon_names high: :alert
            end
          end
        )

      assert result =~ ~r/column :title reads from :owner, which is a column of its own/
    end

    test "caption_text needs a caption field" do
      result =
        define(
          quote do
            column :title do
              caption_text("Created {date}")
            end
          end
        )

      assert result =~ ~r/caption_text without a caption field/
    end

    test "a caption must be a table field" do
      result =
        define(
          quote do
            column :title do
              caption(:nope)
            end
          end
        )

      assert result =~ ~r/column :title references field :nope/
    end

    test "badge_help needs a badge field" do
      result =
        define(
          quote do
            row_layout do
              title :title
              badge_help(open: "Still to do")
            end
          end
        )

      assert result =~ ~r/row_layout declares badge_help without a badge field/
    end

    test "icon names come from the vocabulary" do
      result =
        define(
          quote do
            column :title do
              icon :priority
              icon_names high: :rocket
            end
          end
        )

      assert result =~ ~r/icon_names for :high must be one of/
    end

    test "icon options need an icon field" do
      result =
        define(
          quote do
            column :title do
              icon_tones high: :danger
            end
          end
        )

      assert result =~ ~r/without an icon field/
    end

    test "detail icons come from the vocabulary and need a detail field" do
      bad_icon =
        define(
          quote do
            column :title do
              detail :priority
              detail_icon_names high: :rocket
            end
          end
        )

      assert bad_icon =~ ~r/detail_icon_names for :high must be one of/

      no_detail =
        define(
          quote do
            column :title do
              detail_icon_names high: :alert
            end
          end
        )

      assert no_detail =~ ~r/without a detail field/
    end
  end
end
