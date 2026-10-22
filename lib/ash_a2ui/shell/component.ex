# The component is a Phoenix rendering, guarded like the LiveView transport
# for the NO_PHOENIX CI job.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Shell.Component do
    @moduledoc """
    The shell in a page: a command palette (`ctrl+p`) and a surface launcher
    (`ctrl+k`) over whatever LiveView renders it. Mount it once, in the
    app layout:

        <.live_component
          module={AshA2ui.Shell.Component}
          id="a2ui-shell"
          host={MyAppWeb.Shell}
          context={@current_user}
        />

    and add the hook (`priv/js/ash_a2ui_shell_hook.js`) to the LiveSocket:

        import {AshA2uiShell} from "../../deps/ash_a2ui/priv/js/ash_a2ui_shell_hook.js"
        let liveSocket = new LiveSocket("/live", Socket, {hooks: {AshA2uiShell, ...}})

    ## Attributes

      * `:id` (required) — the DOM id. The input, list and rows derive theirs.
      * `:host` (required) — a module implementing `AshA2ui.Shell.Host`.
      * `:context` — passed to the host's callbacks; usually the actor. A
        changed context drops the entries the shell had read.
      * `:keys` — the key table, default `AshA2ui.Shell.keys/0`.

    ## Events

    The hook pushes these to the component; a test can push them with
    `render_hook/3` on the component's root:

      * `"shell:open"` `%{"mode" => "palette" | "launcher"}`, optionally with
        `"query"` to start from;
      * `"shell:move"` `%{"by" => 1 | -1}` — the arrow keys;
      * `"shell:close"` — escape.

    The input posts `"shell:filter"` as it changes and `"shell:run"` on
    enter, which runs the highlighted row; clicking a row posts
    `"shell:choose"`.

    Anything can open the shell without a key: `open/1` is a `JS` command
    that dispatches the window event the hook listens for.

    It renders in the shared neobrutalist vocabulary (2px borders, hard
    shadows, `--a2ui-*` tokens with fallbacks) and needs no host CSS.
    """

    use Phoenix.LiveComponent

    alias AshA2ui.Shell
    alias Phoenix.LiveView.JS

    @doc """
    A `JS` command that opens the shell in `mode` (`"palette"` or
    `"launcher"`), for a button: `phx-click={AshA2ui.Shell.Component.open("launcher")}`.
    """
    @spec open(String.t(), JS.t()) :: JS.t()
    def open(mode \\ "palette", js \\ %JS{}) when mode in ["palette", "launcher"] do
      JS.dispatch(js, "ash_a2ui:shell", detail: %{mode: mode})
    end

    @impl true
    def mount(socket) do
      {:ok,
       assign(socket,
         open?: false,
         mode: :palette,
         query: "",
         items: [],
         active: 0,
         entries: nil,
         error: nil
       )}
    end

    @impl true
    def update(assigns, socket) do
      socket =
        socket
        |> assign(:id, assigns.id)
        |> assign(:host, assigns.host)
        |> assign(:context, Map.get(assigns, :context))
        |> assign(:keys, Map.get(assigns, :keys) || Shell.keys())

      # Another actor's entries are not this one's.
      socket = if changed?(socket, :context), do: assign(socket, :entries, nil), else: socket

      {:ok, socket}
    end

    @impl true
    def handle_event("shell:open", params, socket) do
      socket =
        socket
        |> ensure_entries()
        |> assign(open?: true, mode: mode(params["mode"]), error: nil)
        |> filter(params["query"] || "")

      {:noreply, socket}
    end

    def handle_event("shell:close", _params, socket), do: {:noreply, close(socket)}

    def handle_event("shell:filter", %{"query" => query}, socket),
      do: {:noreply, socket |> assign(:error, nil) |> filter(query)}

    def handle_event("shell:move", %{"by" => by}, socket) do
      count = length(socket.assigns.items)
      step = if by in [-1, "-1"], do: -1, else: 1

      active =
        if count == 0, do: 0, else: Integer.mod(socket.assigns.active + step, count)

      {:noreply, assign(socket, :active, active)}
    end

    def handle_event("shell:choose", %{"index" => index}, socket) do
      case Integer.parse(to_string(index)) do
        {i, ""} -> run(Enum.at(socket.assigns.items, i), socket)
        _bad -> {:noreply, socket}
      end
    end

    def handle_event("shell:run", params, socket) do
      query = params["query"]

      # Enter can arrive before the last change did: route what was typed.
      socket =
        if is_binary(query) and query != socket.assigns.query,
          do: filter(socket, query),
          else: socket

      run(Enum.at(socket.assigns.items, socket.assigns.active), socket)
    end

    defp run(nil, socket), do: {:noreply, socket}
    defp run(%{action: :none}, socket), do: {:noreply, socket}

    defp run(%{action: {:complete, text}}, socket),
      do: {:noreply, socket |> filter(text) |> push_event("ash_a2ui:shell:input", %{value: text})}

    defp run(%{action: {:mode, mode}}, socket),
      do: {:noreply, socket |> assign(:mode, mode) |> filter("")}

    defp run(%{action: {:invoke, :launcher}}, socket),
      do: run(%{action: {:mode, :launcher}}, socket)

    defp run(%{action: {:invoke, invocation}}, socket) do
      %{host: host, context: context} = socket.assigns

      case host.invoke(invocation, context, close(socket)) do
        {:ok, socket} -> {:noreply, socket}
        {:error, message} -> {:noreply, assign(socket, :error, message)}
      end
    end

    defp ensure_entries(%{assigns: %{entries: nil}} = socket) do
      %{host: host, context: context} = socket.assigns
      assign(socket, :entries, host.entries(context))
    end

    defp ensure_entries(socket), do: socket

    defp filter(socket, query) do
      items = Shell.items(socket.assigns.mode, query, socket.assigns.entries || %{})
      assign(socket, query: query, items: items, active: 0)
    end

    defp close(socket),
      do: assign(socket, open?: false, query: "", items: [], active: 0, error: nil)

    defp mode("launcher"), do: :launcher
    defp mode(_palette), do: :palette

    @impl true
    def render(assigns) do
      assigns =
        assigns
        |> assign(:keys_json, Jason.encode!(assigns.keys))
        |> assign(:rows, rows(assigns.items))
        |> assign(:palette_key, Shell.key_for(:palette, assigns.keys))
        |> assign(:launcher_key, Shell.key_for(:launcher, assigns.keys))

      ~H"""
      <div
        id={@id}
        phx-hook="AshA2uiShell"
        phx-target={@myself}
        data-keys={@keys_json}
        data-open={to_string(@open?)}
        data-mode={@mode}
      >
        <div
          :if={@open?}
          id={"#{@id}-overlay"}
          style="position:fixed;inset:0;z-index:1000;display:flex;align-items:flex-start;justify-content:center;padding:10vh 1rem 1rem;"
        >
          <div
            id={"#{@id}-backdrop"}
            aria-hidden="true"
            phx-click="shell:close"
            phx-target={@myself}
            style="position:absolute;inset:0;background:rgba(0,0,0,0.45);"
          >
          </div>
          <div
            id={"#{@id}-dialog"}
            role="dialog"
            aria-modal="true"
            aria-label={title(@mode)}
            style="position:relative;width:100%;max-width:40rem;max-height:75vh;display:flex;flex-direction:column;
                   background:var(--a2ui-color-surface, #fff);color:var(--a2ui-color-on-surface, #111827);
                   border:2px solid var(--a2ui-color-border, #111827);border-radius:var(--a2ui-border-radius, 5px);
                   box-shadow:4px 4px 0 0 var(--a2ui-color-border, #111827);
                   font-family:var(--a2ui-font-family, inherit);font-size:var(--a2ui-font-size-m, 0.875rem);"
          >
            <form
              id={"#{@id}-form"}
              phx-change="shell:filter"
              phx-submit="shell:run"
              phx-target={@myself}
              style="margin:0;padding:0.75rem;border-bottom:2px solid var(--a2ui-color-border, #111827);"
            >
              <label for={"#{@id}-input"} style="display:block;font-weight:700;margin-bottom:0.375rem;">
                {title(@mode)}
              </label>
              <input
                id={"#{@id}-input"}
                name="query"
                type="text"
                value={@query}
                autocomplete="off"
                spellcheck="false"
                role="combobox"
                aria-expanded="true"
                aria-controls={"#{@id}-list"}
                aria-activedescendant={@rows != [] && "#{@id}-item-#{@active}"}
                placeholder={placeholder(@mode)}
                phx-debounce="50"
                style="width:100%;box-sizing:border-box;padding:0.5rem 0.625rem;
                       background:var(--a2ui-color-input, #fff);color:var(--a2ui-color-on-input, #111827);
                       border:2px solid var(--a2ui-color-border, #111827);border-radius:var(--a2ui-textfield-border-radius, 5px);
                       font:inherit;"
              />
              <p
                :if={@error}
                id={"#{@id}-error"}
                role="alert"
                style="margin:0.5rem 0 0;color:var(--a2ui-marker-danger-background, #dc2626);font-weight:700;"
              >
                {@error}
              </p>
            </form>

            <ul
              id={"#{@id}-list"}
              role="listbox"
              aria-label={title(@mode)}
              style="list-style:none;margin:0;padding:0.375rem;overflow-y:auto;flex:1 1 auto;"
            >
              <%= for row <- @rows do %>
                <li
                  :if={row.header}
                  role="presentation"
                  style="padding:0.5rem 0.625rem 0.25rem;font-size:var(--a2ui-font-size-xs, 0.75rem);font-weight:700;text-transform:uppercase;letter-spacing:0.04em;opacity:0.7;"
                >
                  {row.header}
                </li>
                <li
                  id={"#{@id}-item-#{row.index}"}
                  role="option"
                  aria-selected={to_string(row.index == @active)}
                  aria-disabled={row.item.action == :none && "true"}
                  data-shell-item
                  phx-click="shell:choose"
                  phx-value-index={row.index}
                  phx-target={@myself}
                  style={row_style(row.item, row.index == @active)}
                >
                  <span style="font-weight:700;white-space:nowrap;">{row.item.label}</span>
                  <span
                    :if={row.item[:hint]}
                    style="white-space:nowrap;font-family:var(--a2ui-font-family-mono, ui-monospace, monospace);font-size:var(--a2ui-font-size-xs, 0.75rem);opacity:0.8;"
                  >
                    {row.item.hint}
                  </span>
                  <span
                    :if={row.item[:detail]}
                    style="min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;opacity:0.75;"
                  >
                    {row.item.detail}
                  </span>
                </li>
              <% end %>
              <li :if={@rows == []} id={"#{@id}-empty"} role="presentation" style="padding:0.75rem 0.625rem;opacity:0.7;">
                {empty(@mode)}
              </li>
            </ul>

            <p style="margin:0;padding:0.5rem 0.75rem;border-top:2px solid var(--a2ui-color-border, #111827);font-size:var(--a2ui-font-size-xs, 0.75rem);opacity:0.75;">
              enter runs · ↑ ↓ move · esc closes<span :if={@mode == :palette && @launcher_key}> · {@launcher_key} surfaces</span><span :if={@mode == :launcher && @palette_key}> · {@palette_key} commands</span>
            </p>
          </div>
        </div>
      </div>
      """
    end

    # Rows with a group header wherever the group changes.
    defp rows(items) do
      {rows, _last} =
        items
        |> Enum.with_index()
        |> Enum.map_reduce(nil, fn {item, index}, last ->
          header = if item.group != last, do: item.group
          {%{item: item, index: index, header: header}, item.group}
        end)

      rows
    end

    defp row_style(item, active?) do
      Enum.join([
        "display:flex;align-items:baseline;gap:0.625rem;padding:0.375rem 0.625rem;" <>
          "border:2px solid transparent;border-radius:3px;",
        if(item.action != :none, do: "cursor:pointer;", else: ""),
        if(active?,
          do:
            "border-color:var(--a2ui-color-border, #111827);" <>
              "background:var(--a2ui-color-primary, #2563eb);color:var(--a2ui-color-on-primary, #fff);",
          else: ""
        )
      ])
    end

    defp title(:launcher), do: "Open a surface"
    defp title(:palette), do: "Commands"

    defp placeholder(:launcher), do: "Type to filter your surfaces"
    defp placeholder(:palette), do: "Type a command, /open <surface>, or ask the agent"

    defp empty(:launcher), do: "No surface matches."
    defp empty(:palette), do: "Nothing matches."
  end
end
