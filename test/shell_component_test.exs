# Phoenix-only: under NO_PHOENIX the component and the test endpoint don't
# exist, so nothing here should even compile.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.ShellComponentTest.Host do
    @behaviour AshA2ui.Shell.Host

    @impl true
    def entries(%{surfaces: surfaces}) do
      %{
        commands: [
          %{
            "name" => "calendar",
            "description" => "Agenda",
            "input" => %{"hint" => "today | week"}
          },
          %{"name" => "help", "description" => "This list"}
        ],
        surfaces: surfaces
      }
    end

    @impl true
    def invoke({:open_surface, %{"id" => "broken"}, _target}, _context, _socket),
      do: {:error, "That surface is closed."}

    def invoke({:open_surface, %{"id" => id}, target}, _context, socket),
      do: {:ok, Phoenix.LiveView.push_navigate(socket, to: "/opened/#{id}?#{query(target)}")}

    def invoke(invocation, %{test: test}, socket) do
      send(test, {:invoked, invocation})
      {:ok, socket}
    end

    defp query(nil), do: ""
    defp query({:nth, n}), do: "n=#{n}"
    defp query({:record, id}), do: "id=#{id}"
  end

  defmodule AshA2ui.ShellComponentTest.Page do
    use Phoenix.LiveView

    @impl true
    def mount(_params, session, socket) do
      {:ok, assign(socket, :context, %{test: session["test"], surfaces: session["surfaces"]})}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <main>
        <button id="open-launcher" phx-click={AshA2ui.Shell.Component.open("launcher")}>
          All apps
        </button>
        <.live_component
          module={AshA2ui.Shell.Component}
          id="shell"
          host={AshA2ui.ShellComponentTest.Host}
          context={@context}
        />
      </main>
      """
    end
  end

  defmodule AshA2ui.ShellComponentTest do
    use ExUnit.Case, async: true

    import Phoenix.ConnTest
    import Phoenix.LiveViewTest

    @endpoint AshA2ui.Test.Endpoint

    @surfaces [
      %{
        "id" => "calendar",
        "title" => "Calendar",
        "group" => "My day",
        "description" => "Events"
      },
      %{"id" => "people", "title" => "People", "group" => "My day"},
      %{"id" => "broken", "title" => "Broken", "group" => "Other"}
    ]

    defp page(surfaces \\ @surfaces) do
      {:ok, view, _html} =
        live_isolated(build_conn(), AshA2ui.ShellComponentTest.Page,
          session: %{"test" => self(), "surfaces" => surfaces}
        )

      view
    end

    defp shell(view), do: element(view, "#shell")

    test "closed, it renders the hook and its key table and lists nothing" do
      view = page()
      assert has_element?(view, ~s(#shell[phx-hook="AshA2uiShell"][data-open="false"]))
      assert render(shell(view)) =~ ~s(&quot;ctrl+k&quot;:&quot;launcher&quot;)
      refute has_element?(view, "#shell-dialog")
    end

    test "ctrl+p opens the palette: the launcher row, the commands, the surfaces" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "palette"})

      assert has_element?(view, ~s(#shell[data-open="true"][data-mode="palette"]))
      assert has_element?(view, "#shell-item-0", "Open a surface…")
      assert has_element?(view, "#shell-item-1", "/calendar")
      assert has_element?(view, "#shell-item-2", "/help")
      assert has_element?(view, "#shell-item-3", "Calendar")
      assert has_element?(view, ~s(#shell-item-0[aria-selected="true"]))
    end

    test "ctrl+k opens the launcher, filters, and enter opens the match" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "launcher"})
      assert has_element?(view, ~s(#shell[data-mode="launcher"]))
      assert has_element?(view, "#shell-item-1", "People")

      view |> element("#shell-form") |> render_change(%{"query" => "peo"})
      refute has_element?(view, "#shell-item-1")

      assert {:error, {:live_redirect, %{to: "/opened/people?"}}} =
               view |> element("#shell-form") |> render_submit(%{"query" => "peo"})
    end

    test "/open <surface> n navigates with the target" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "palette"})

      assert {:error, {:live_redirect, %{to: "/opened/calendar?n=2"}}} =
               view |> element("#shell-form") |> render_submit(%{"query" => "/open calendar 2"})
    end

    test "a plain line goes to the host as a prompt, and the shell closes" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "palette"})
      view |> element("#shell-form") |> render_change(%{"query" => "what is on today"})
      view |> element("#shell-form") |> render_submit(%{"query" => "what is on today"})

      assert_receive {:invoked, {:prompt, "what is on today"}}
      refute has_element?(view, "#shell-dialog")
    end

    test "the arrows move the highlight and a click runs a row" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "palette"})
      render_hook(shell(view), "shell:move", %{"by" => 1})
      render_hook(shell(view), "shell:move", %{"by" => 1})
      assert has_element?(view, ~s(#shell-item-2[aria-selected="true"]))
      render_hook(shell(view), "shell:move", %{"by" => -1})
      assert has_element?(view, ~s(#shell-item-1[aria-selected="true"]))

      view |> element("#shell-item-2") |> render_click()
      assert_receive {:invoked, {:command, %{"name" => "help"}, []}}
    end

    test "a command with an argument goes in the input to finish" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "palette"})
      view |> element("#shell-item-1") |> render_click()

      assert has_element?(view, ~s(#shell-input[value="/calendar "]))
      assert_push_event(view, "ash_a2ui:shell:input", %{value: "/calendar "})
      view |> element("#shell-form") |> render_submit(%{"query" => "/calendar week"})
      assert_receive {:invoked, {:command, %{"name" => "calendar"}, ["week"]}}
    end

    test "the launcher row switches mode, and a host error keeps the shell open" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "palette"})
      view |> element("#shell-item-0") |> render_click()
      assert has_element?(view, ~s(#shell[data-mode="launcher"]))

      view |> element("#shell-form") |> render_submit(%{"query" => "broken"})
      assert has_element?(view, "#shell-error", "That surface is closed.")
    end

    test "escape closes it" do
      view = page()
      render_hook(shell(view), "shell:open", %{"mode" => "launcher"})
      render_hook(shell(view), "shell:close", %{})
      refute has_element?(view, "#shell-dialog")
    end

    test "a surface the host does not list is not offered" do
      view = page([hd(@surfaces)])
      render_hook(shell(view), "shell:open", %{"mode" => "launcher"})
      refute render(shell(view)) =~ "People"

      view |> element("#shell-form") |> render_change(%{"query" => "/open people"})
      assert has_element?(view, "#shell-item-0", "There is no people surface")
    end

    test "the open/1 JS command dispatches the window event the hook listens for" do
      view = page()
      assert render(element(view, "#open-launcher")) =~ "ash_a2ui:shell"
      assert render(element(view, "#open-launcher")) =~ "launcher"
    end
  end
end
