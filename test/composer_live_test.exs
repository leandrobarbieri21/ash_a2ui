# The whole file is Phoenix-only: under NO_PHOENIX the composer LiveView, the
# test endpoint and the route don't exist, so nothing here should even compile.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Web.ComposerLiveTest do
    @moduledoc """
    The surface composer's contract: browse lists the configured surfaces,
    import shows the spec AND its rejections honestly, every edit re-resolves
    with errors inline, the preview renders the resolved entities, and the
    export shows the to_dsl_source output — the full import → edit → resolve
    → export round trip in a LiveView.
    """

    use ExUnit.Case, async: false

    import Phoenix.ConnTest
    import Phoenix.LiveViewTest

    alias AshA2ui.Dynamic

    @endpoint AshA2ui.Test.Endpoint

    setup do
      [conn: Plug.Test.init_test_session(build_conn(), %{})]
    end

    defp open_composer(conn) do
      {:ok, view, html} = live(conn, "/composer")
      {view, html}
    end

    defp import_module(view, module) do
      render_click(view, "import", %{"module" => inspect(module)})
    end

    defp assigns(view) do
      :sys.get_state(view.pid).socket.assigns
    end

    describe "browse" do
      test "lists the configured surfaces with their resources", %{conn: conn} do
        {_view, html} = open_composer(conn)

        assert html =~ "Surface editor"
        assert html =~ "MinimalUI"
        assert html =~ "resource: Minimal"
        assert html =~ "Ticket"
        assert html =~ "resource: Ticket"
      end

      test "a listed module without an a2ui section shows as such", %{conn: conn} do
        {_view, html} = open_composer(conn)

        assert html =~ "NoSurface"
        assert html =~ "no a2ui section"
      end
    end

    describe "import" do
      test "shows the spec rows, the honest rejection, the preview and the export", %{
        conn: conn
      } do
        {view, _html} = open_composer(conn)
        html = import_module(view, AshA2ui.Test.MinimalUI)

        # the editor page, over the imported spec
        assert html =~ "imported from AshA2ui.Test.MinimalUI"
        assert html =~ ~s(name="spec[resource]")
        assert html =~ "Name (standalone)"

        # the honesty contract: the one feature the spec cannot carry
        assert html =~ "Import rejections"
        assert html =~ "a2ui.surface_id (surface_id):"
        assert html =~ "resolve :surface_id option"

        # the resolve landed: preview renders the resolved entities
        assert html =~ "Preview — resolves"
        assert html =~ ~r/dyn_minimal_[0-9a-f]{8}/

        # and the export shows the DSL source
        assert html =~ "Export — DSL source"
        assert html =~ "defmodule AshA2ui.Test.ComposedSurface do"
        assert html =~ "use AshA2ui.Standalone"

        socket = assigns(view)
        assert socket.page == :editor
        assert socket.spec["resource"] == "Minimal"
        assert %Dynamic.Surface{} = socket.surface
        assert length(socket.rejections) == 1
      end

      test "imports nested forms into the spec (only the surface id is rejected)", %{
        conn: conn
      } do
        {view, _html} = open_composer(conn)
        html = import_module(view, AshA2ui.Test.Ticket)

        # Nested forms are spec vocabulary now: they land in the imported
        # spec (the editor's schema-introspected rows render them as JSON
        # inputs), and the only honest rejection left is the surface id.
        assert html =~ "Import rejections"
        assert html =~ "a2ui.surface_id (surface_id):"
        refute html =~ "no spec vocabulary"

        socket = assigns(view)
        assert %{rejections: [rejection]} = socket
        assert rejection.feature == "surface_id"

        assert [_table, form] = socket.spec["components"]
        assert [%{"name" => "notes"}, %{"name" => "tags"}] = form["nested_forms"]
        assert %Dynamic.Surface{} = socket.surface

        # the editor rows are schema-introspected: the new vocabulary gets
        # its inputs (JSON textareas) without composer-specific code
        assert html =~ "composer-components-1-nested_forms"
      end

      test "a module with no a2ui section shows the nothing-to-import rejection", %{conn: conn} do
        {view, _html} = open_composer(conn)
        html = import_module(view, AshA2ui.Test.NoSurface)

        assert html =~ "declares no AshA2ui surface"
        # and the empty spec is honestly invalid, not silently ok
        assert html =~ "Does not resolve"
        refute assigns(view).surface
      end
    end

    describe "edit → resolve → export round trip" do
      test "a validate edit updates the spec, the preview and the export", %{conn: conn} do
        {view, _html} = open_composer(conn)
        import_module(view, AshA2ui.Test.MinimalUI)

        html =
          render_change(view, "validate", %{
            "spec" => %{
              "resource" => "Minimal",
              "title" => "Edited title",
              "components" => %{
                "0" => %{
                  "kind" => "table",
                  "name" => "",
                  "fields" => "name",
                  "read_action" => "read"
                }
              },
              "fields" => %{"0" => %{"name" => "name", "label" => "Renamed label"}}
            }
          })

        socket = assigns(view)
        assert socket.spec["title"] == "Edited title"
        assert socket.spec["fields"] == [%{"name" => "name", "label" => "Renamed label"}]
        assert %Dynamic.Surface{} = socket.surface
        assert socket.surface.title == "Edited title"

        # preview and export follow the edit
        assert html =~ "Edited title"
        assert html =~ "Renamed label"
        assert assigns(view).export =~ "Edited title"
      end

      test "typed numbers and checkboxes coerce to the spec's JSON types", %{conn: conn} do
        {view, _html} = open_composer(conn)
        import_module(view, AshA2ui.Test.MinimalUI)

        render_change(view, "validate", %{
          "spec" => %{
            "resource" => "Minimal",
            "components" => %{"0" => %{"kind" => "table", "fields" => "name"}},
            "queries" => %{
              "0" => %{"name" => "main", "page_size" => "25", "sortable" => "name"}
            },
            "fields" => %{"0" => %{"name" => "name", "hidden" => "true"}}
          }
        })

        socket = assigns(view)

        assert [%{"name" => "main", "page_size" => 25, "sortable" => ["name"]}] =
                 socket.spec["queries"]

        assert [%{"name" => "name", "hidden" => true}] = socket.spec["fields"]
        assert %Dynamic.Surface{} = socket.surface
      end

      test "an unknown field reference renders the verifier's error inline", %{conn: conn} do
        {view, _html} = open_composer(conn)
        import_module(view, AshA2ui.Test.MinimalUI)

        html =
          render_change(view, "validate", %{
            "spec" => %{
              "resource" => "Minimal",
              "components" => %{"0" => %{"kind" => "table", "fields" => "bogus"}}
            }
          })

        assert html =~ "Does not resolve"
        assert html =~ "bogus"
        refute assigns(view).surface
      end

      test "invalid JSON in a structured field reports the decode error and keeps resolving", %{
        conn: conn
      } do
        {view, _html} = open_composer(conn)
        import_module(view, AshA2ui.Test.MinimalUI)

        html =
          render_change(view, "validate", %{
            "spec" => %{
              "resource" => "Minimal",
              "components" => %{"0" => %{"kind" => "table", "row_layout" => "not json"}}
            }
          })

        # the decode error is named (the row_layout key is left out of the resolve)
        assert html =~ "invalid JSON"
        assert html =~ "components[0].row_layout"

        # the rest of the spec still resolves — the editor never lies silent
        assert %Dynamic.Surface{} = assigns(view).surface
      end

      test "a non-numeric page_size reports a coercion error", %{conn: conn} do
        {view, _html} = open_composer(conn)
        import_module(view, AshA2ui.Test.MinimalUI)

        html =
          render_change(view, "validate", %{
            "spec" => %{
              "resource" => "Minimal",
              "queries" => %{"0" => %{"name" => "main", "page_size" => "lots"}}
            }
          })

        assert html =~ "must be a whole number"
        assert html =~ "queries[0].page_size"
      end
    end

    describe "rows" do
      test "add-row appends a seed row and remove-row drops it", %{conn: conn} do
        {view, _html} = open_composer(conn)
        import_module(view, AshA2ui.Test.MinimalUI)

        assert [%{"kind" => "table"}] = assigns(view).spec["components"]

        render_click(view, "add-row", %{"section" => "components"})
        assert [%{"kind" => "table"}, %{"kind" => "table"}] = assigns(view).spec["components"]

        html = render(view)
        assert html =~ "composer-components-1"

        render_click(view, "remove-row", %{"section" => "components", "index" => "1"})
        assert [%{"kind" => "table"}] = assigns(view).spec["components"]
        refute render(view) =~ "composer-components-1"
      end

      test "removing every component renders the resolve's honest error", %{conn: conn} do
        {view, _html} = open_composer(conn)
        import_module(view, AshA2ui.Test.MinimalUI)

        render_click(view, "remove-row", %{"section" => "components", "index" => "0"})

        html = render(view)
        assert html =~ "at least one component"
        refute assigns(view).surface
      end
    end

    test "reset returns to the browse page", %{conn: conn} do
      {view, _html} = open_composer(conn)
      import_module(view, AshA2ui.Test.MinimalUI)

      html = render_click(view, "reset", %{})

      assert html =~ "Surface editor"
      assert assigns(view).page == :browse
      assert assigns(view).surface == nil
    end

    describe "host-named allowlist map" do
      test "a master/detail surface imports its context, related tables and links", %{
        conn: conn
      } do
        {:ok, view, _html} = live(conn, "/composer/related")

        html = render_click(view, "import", %{"module" => "AshA2ui.Test.Links.PeopleUI"})

        assert html =~ "Preview — resolves"
        assert html =~ "resource: AshA2ui.Test.Links.Note"
        assert html =~ "resource: AshA2ui.Test.Links.Participant"
        assert html =~ "link: note"
        assert html =~ "links: participants"
        assert html =~ "context person"

        socket = assigns(view)
        assert [%{feature: "surface_id"}] = socket.rejections
        assert %Dynamic.Surface{} = socket.surface

        assert Enum.map(socket.spec["components"], &Map.get(&1, "resource")) ==
                 [nil, nil, "Note", "Participant"]
      end

      test "a short-name import does not resolve until the resource is renamed", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/composer/named")

        html = render_click(view, "import", %{"module" => "AshA2ui.Test.MinimalUI"})

        # the honest error names what IS available (quotes escape in HTML)
        assert html =~ "is not available to dynamic surfaces"
        assert html =~ "renamed"
        refute assigns(view).surface

        # renaming the resource to the host's name resolves the same spec
        html =
          render_change(view, "validate", %{
            "spec" => %{"resource" => "renamed", "components" => %{"0" => %{"kind" => "table"}}}
          })

        assert html =~ "Preview — resolves"
        assert %Dynamic.Surface{} = assigns(view).surface
      end
    end
  end
end
