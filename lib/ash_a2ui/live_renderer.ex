# AshA2ui.LiveRenderer is the optional LiveView transport. The whole module is
# guarded so the protocol core compiles when phoenix_live_view is absent
# (proven by the NO_PHOENIX CI job).
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.LiveRenderer do
    @moduledoc """
    Batteries-included LiveView transport for A2UI surfaces:

        defmodule MyAppWeb.PromotionsProviderA2uiLive do
          use AshA2ui.LiveRenderer,
            ui: MyApp.UI.PromotionsProviderUI,
            actor_fn: &(&1.assigns.current_admin)
        end

    - `mount/3` derives the actor/tenant (via `:actor_fn` / `:tenant_fn`) and,
      on the connected mount, starts the surface build as an async task —
      the LiveView process stays free (coordinator, not worker) and the
      container renders instantly, so the shipped JS hook's bootstrap
      skeleton (`priv/js/ash_a2ui_hook.js`) is visible from the first paint.
      When the task completes, the surface messages are pushed as the
      `"a2ui:messages"` event to the hook (`priv/js/ash_a2ui_hook.js`)
      hosting `<a2ui-surface>`, hydrating the surface over the skeleton. On
      the static (disconnected) render only the introspection assigns are
      set — the surface is built once, on the connected mount. A failed
      bootstrap crashes the LiveView, matching the synchronous behavior
      (a silent no-op would leave the skeleton up forever).
    - `render/1` renders the hook container
      (`<div id="ash-a2ui-surface" phx-hook="AshA2ui" phx-update="ignore">`).
    - `handle_event("a2ui:message", message, socket)` takes one A2UI 1.0
      renderer-to-agent message, verbatim, routes it through
      `AshA2ui.ActionHandler.handle/3` and pushes the follow-up messages,
      for both `{:ok, messages}` and `{:error, messages}` results (an
      action's error messages carry validation feedback on the reserved
      `/errors/<field>` and `/ui/feedback` data-model paths, and a function
      call's end with its `agentFunctionResponse`). A
      `rendererFunctionResponse` is matched to the `callRendererFunction`
      this LiveView pushed (see "Renderer function calls" below).
    - With `:pubsub` configured it subscribes on the connected mount and
      pushes debounced `AshA2ui.Info.build_data_model/2` refreshes when
      broadcasts arrive (see "PubSub live refresh" below).
    - With `:surfaces` it does all of the above for more than one surface
      on the page (see "Additional surfaces" below).

    All injected callbacks (`mount/3`, `render/1`, `handle_event/3`,
    `handle_info/2`, `handle_async/3`) are `defoverridable`. If you override
    `handle_async/3`, delegate the `:ash_a2ui_surface` key (and, with
    `:surfaces`, the `{:ash_a2ui_surface, name}` keys) to
    `AshA2ui.LiveRenderer.handle_async/4` — it delivers the bootstrap
    messages; dropping it strands the client on the skeleton.

    ## Options

      * `:ui` (required) — the resource or standalone UI module whose `a2ui`
        section defines the surface.
      * `:actor_fn` (optional) — a 1-arity function `socket -> actor` used to
        derive the actor on mount; the actor is passed to every surface,
        data-model and action call. Defaults to `nil` (no actor).
      * `:tenant_fn` (optional) — a 1-arity function `socket -> tenant`,
        same semantics as `:actor_fn`. Defaults to `nil` (no tenant).
      * `:deep_link` (optional, default `false`) — keep the URL in step with
        the surface's context selections (see "Deep links" below). Requires
        the LiveView to be mounted at the router (it injects
        `handle_params/3`).
      * `:time_travel` (optional, default `false`) — read the surface as of
        the URL's `?as_of=` instant (see "Time travel" below). Requires the
        LiveView to be mounted at the router (it injects `handle_params/3`).
      * `:open_surface` (optional) — a 2-arity function `(args, socket) ->
        {:noreply, socket}` handling reference-link navigation (the
        `"a2ui:open_surface"` event, `args = %{"surface" => _, "recordId" =>
        _, "query" => _}`). Defaults to navigating to `:open_surface_url`.
      * `:open_surface_url` (optional) — the navigation URL template for
        reference links, with `{surface}` and `{recordId}` placeholders
        (e.g. `"/app/r/{surface}/{recordId}"`). Defaults to
        `config :ash_a2ui, :open_surface_url`; without either, link
        activations are acknowledged and ignored. With either this or
        `:open_surface`, the initial surface is built with
        `link_buttons: true`, so basic-catalog to-one links render as
        link Buttons; without both they stay plain text.
      * `:header` (optional, default `true`) — `false` when the page
        around the surface already owns its heading: the surface is built
        with `header: false` (see `AshA2ui.Info.build_surface/2`), so it
        does not render a second `<h1>`.
      * `:locale_fn` (optional) — a 1-arity function `socket -> locale`
        (`"fr"`), called on mount. The locale is assigned as
        `:ash_a2ui_locale` and passed to every surface, data-model and
        action call as `:locale`; ash_a2ui never reads the ambient Gettext
        locale. Defaults to `nil` (no locale).
      * `:gettext_backend` / `:gettext_fn` / `:metadata_domain` / `:errors_domain` (optional)
        — the translator for the library's own strings and the host's
        display labels, passed to every call (see
        `AshA2ui.Info.build_surface/2` and `AshA2ui.L10n`), e.g.
        `gettext_backend: {MyAppWeb.Gettext, "ash_a2ui"}`. Without either
        translator nothing is translated.
      * `:on_function_response` (optional) — a 3-arity function
        `(response, function_name, socket) -> socket` called with each
        `rendererFunctionResponse` body that answers a
        `callRendererFunction` this LiveView pushed. See "Renderer function
        calls".
      * `:surfaces` (optional) — more surfaces this LiveView builds, pushes,
        answers and refreshes beside the main one, as `name: [ui: module,
        context: fun]`. `:ui` is required; `:context` is an optional
        2-arity function `(params, socket) -> %{"<context>" => id} | nil`.
        See "Additional surfaces".
      * `:pubsub` (optional) — enables live refresh:
        `pubsub: [module: MyApp.PubSub, topics: ["providers:created", ...]]`.
        Topics are explicit configuration: pass the topics your resource's
        `Ash.Notifier.PubSub` notifier publishes (the extension does not try
        to introspect them). See "PubSub live refresh".

    ## PubSub live refresh

    When `:pubsub` is configured, the connected mount subscribes to every
    listed topic via `Phoenix.PubSub.subscribe/2`. Ash's PubSub notifier
    broadcasts a `%Ash.Notifier.Notification{}` by default (`broadcast_type
    :notification`), but may also send `%Phoenix.Socket.Broadcast{}` or a
    plain `%{topic: _, event: _, payload: _}` map depending on
    `broadcast_type` — so `handle_info/2` treats *any* message it receives
    (other than its internal refresh timer) as a data-change signal.
    Notifications are debounced: the first one schedules a refresh 150 ms
    out (`Process.send_after/3`) and further notifications coalesce into it. The refresh calls `AshA2ui.Info.build_data_model/2` with the
    mounted actor/tenant and pushes the resulting `updateDataModel` message
    (wrapped in a one-element list) as `"a2ui:messages"`.

    For surfaces with a `query`, the LiveView tracks the last `/query` state
    it pushed (from the mount payload and every action follow-up) and passes
    it to the refresh as `:query_state`, so a PubSub refresh re-runs the
    user's current search/filters/sort/page instead of resetting the surface
    to the query defaults. Surfaces with `context` entities get the same
    treatment for `/context` (passed as `:context_state`), so refreshes keep
    the user's selections, dependent option lists, details, and table
    scoping.

    Override `handle_info/2` if your LiveView receives unrelated messages.

    ## Additional surfaces

    A page can show more than one surface, say a small summary card above
    the main one. List the others under `:surfaces`:

        use AshA2ui.LiveRenderer,
          ui: MyApp.UI.OrderUI,
          actor_fn: & &1.assigns.current_user,
          surfaces: [
            order_summary: [
              ui: MyApp.UI.OrderSummaryUI,
              context: &MyAppWeb.OrderLive.summary_context/2
            ]
          ]

        def summary_context(params, _socket), do: %{"order" => params["id"]}

    For each one:

      * **Build.** The connected mount starts its build in its own async
        task (`{:ash_a2ui_surface, name}`), as the same actor, tenant,
        `as_of` and locale/translator as the main surface, with `header:
        false`. The result is pushed as `"a2ui:messages"`.
      * **Selection.** `:context` is called with the mount's params and the
        socket. The ids it returns are validated through
        `AshA2ui.Info.context_state_for/3` (the same authorized reads a
        deep link takes) and the surface is built with that context. With
        no `:context`, or `nil` / `%{}`, it is built with none.
        `handle_params/4` (injected by `deep_link`/`time_travel`, or called
        by a host's own) calls it again and rebuilds the surface when the
        selection changed.
      * **Calls.** `"a2ui:message"` calls are routed by their
        `surfaceId` (`callAgentFunction.surfaceId`): the surface's UI
        answers through the same handler and options, and its follow-ups
        (ending in the call's `agentFunctionResponse`) are pushed. Its query and
        context state are tracked in `:ash_a2ui_surfaces` (by name), never in
        the main surface's state or the URL. Everything else goes to the
        main UI as before.
      * **Refresh.** A PubSub refresh rebuilds every built surface's data
        model with its own tracked state, in the same push as the main
        one. The summary on a page usually shows the same records the
        topics announce changes to, so it should not go stale. A surface
        still bootstrapping is skipped.

    The surface id is the UI's `surface_id`. `render/1` still renders the
    one default container; a page with more surfaces renders its own
    layout, with a container per surface and `primary` on the main one:

        <AshA2ui.LiveRenderer.surface_container id="order-summary" surface="order_summary" />
        <AshA2ui.LiveRenderer.surface_container id="order" surface="order" primary />

    Without `:surfaces`, nothing changes.

    ## Renderer function calls

    An action can answer with a `callRendererFunction` (an export's
    `downloadFile`). The LiveView remembers the `functionCallId` of every
    call it pushes, and the renderer answers each with a
    `rendererFunctionResponse`. A response settles its call: an `error`
    response is logged at warning level, and the `:on_function_response`
    callback, when set, receives it. A response whose id matches no pending
    call (a duplicate, a late answer to a settled call, or an id this
    LiveView never sent) is logged and dropped.

    ## Deep links

    The connected mount reads the surface's initial state from the URL:

      * `?ctx[<context>]=<record id>` — context selections. Each id is
        validated through the same **authorized** read a `"context_select"`
        performs (in declaration order, dependency filters included), so a
        link can only ever select what the actor may read; unknown names
        and unreadable ids are dropped silently. Labels are derived
        server-side.
      * `?q[search]=…&q[page]=2&q[sort][field]=…&q[sort][dir]=desc&q[filters][<f>]=…`
        — the `/query` state (on multi-table surfaces keyed by table:
        `?q[<table>][page]=2`), validated against the query allowlist like
        any client input (invalid state falls back to the defaults).

    With `deep_link: true` the LiveView also writes context changes back:
    after an action changes `/context` (e.g. a master/detail row select),
    it `push_patch`es the current path with the new `ctx` params (other
    params kept), and browser back/forward re-applies the URL's selections —
    so a detail view is a shareable, back-button-friendly URL.

    ## Time travel

    With `time_travel: true` the surface reads as of the instant in the
    URL's `?as_of=` parameter (`AshA2ui.AsOf.parse/1`; absent or
    unparseable means now). Every read — tables, options, contexts, details
    and the PubSub refreshes — runs at that instant
    (`AshA2ui.Info.build_surface/2`'s `:as_of`), and a pinned surface is
    view-only: its row and bulk actions are stripped and
    `AshA2ui.ActionHandler` refuses writes. The instant is assigned as
    `:ash_a2ui_as_of` (`nil` for now), so the host can render
    `AshA2ui.TimeScrubber` above the surface. When `?as_of=` changes (a
    scrubber patch, back/forward) the LiveView navigates to the new URL,
    which rebuilds the surface: a pinned surface and a live one have
    different controls, not only different data.

    ## Reference links

    The shipped JS hook pushes `"a2ui:open_surface"` when an admin-catalog
    reference link is activated (see `AshA2ui.Links`). Basic-catalog link
    Buttons call `ashAction` with the name `"open_surface"` instead, which
    `AshA2ui.ActionHandler` validates against the surface's link fields;
    an accepted one takes the same path. Those Buttons are only rendered
    when this LiveView can navigate (an `:open_surface` callback or an
    `:open_surface_url` template, see `AshA2ui.Info.build_surface/2`'s
    `:link_buttons`). The default handling navigates
    (`push_navigate`) to the `:open_surface_url` template; pass
    `:open_surface` to do anything else.

    ## Introspection assigns

    `mount/3` assigns `:ash_a2ui_ui`, `:ash_a2ui_actor`,
    `:ash_a2ui_tenant`, `:ash_a2ui_locale` and `:ash_a2ui_as_of` (always `nil` without
    `time_travel: true`) on the socket, and `:ash_a2ui_surfaces`: each
    additional surface's `selection`, `query_state` and `context_state`, by
    name (`%{}` without `:surfaces`).

    ## Test seams (not public API)

    Internal override options used by the test suite to inject stubs while
    the encoder and action handler are built in parallel — do not rely on
    them in applications:

      * `:surface_fn` — `(ui, opts -> [message])`, defaults to
        `AshA2ui.Info.build_surface/2`.
      * `:data_model_fn` — `(ui, opts -> message)`, defaults to
        `AshA2ui.Info.build_data_model/2`.
      * `:action_fn` — `(ui, message, opts -> {:ok, [message]} |
        {:error, [message]})`, defaults to `AshA2ui.ActionHandler.handle/3`.
      * `:refresh_debounce_ms` — PubSub refresh debounce window, defaults
        to `150`.

    FROZEN CONTRACT — the `use` options (`:ui`, `:actor_fn`) are the interface
    Track 6 codes against; do not change outside an integration commit.
    """

    use Phoenix.Component

    import Phoenix.LiveView,
      only: [connected?: 1, push_event: 3, push_navigate: 2, push_patch: 2, start_async: 3]

    alias Plug.Conn.Query

    require Logger

    @messages_event "a2ui:messages"
    @refresh_message {:ash_a2ui, :refresh}
    @default_debounce_ms 150

    defmacro __using__(opts) do
      quote do
        use Phoenix.LiveView

        @doc false
        def __ash_a2ui_config__ do
          AshA2ui.LiveRenderer.build_config(unquote(opts))
        end

        @impl true
        def mount(params, session, socket) do
          AshA2ui.LiveRenderer.mount(__ash_a2ui_config__(), params, session, socket)
        end

        @impl true
        def render(assigns) do
          # Only change tracking passes through: the LiveView's own assigns
          # (an `:id`, say) must not reach the container's attrs.
          AshA2ui.LiveRenderer.surface_container(Map.take(assigns, [:__changed__]))
        end

        @impl true
        def handle_event("a2ui:message", message, socket) do
          AshA2ui.LiveRenderer.handle_message(__ash_a2ui_config__(), message, socket)
        end

        @impl true
        def handle_event("a2ui:open_surface", args, socket) do
          AshA2ui.LiveRenderer.handle_open_surface(__ash_a2ui_config__(), args, socket)
        end

        unquote(
          if Keyword.get(opts, :deep_link, false) or Keyword.get(opts, :time_travel, false) do
            quote do
              @impl true
              def handle_params(params, uri, socket) do
                AshA2ui.LiveRenderer.handle_params(__ash_a2ui_config__(), params, uri, socket)
              end

              defoverridable handle_params: 3
            end
          end
        )

        @impl true
        def handle_info(message, socket) do
          AshA2ui.LiveRenderer.handle_notification(__ash_a2ui_config__(), message, socket)
        end

        @impl true
        def handle_async(:ash_a2ui_surface, result, socket) do
          AshA2ui.LiveRenderer.handle_async(
            __ash_a2ui_config__(),
            :ash_a2ui_surface,
            result,
            socket
          )
        end

        def handle_async({:ash_a2ui_surface, _name} = key, result, socket) do
          AshA2ui.LiveRenderer.handle_async(__ash_a2ui_config__(), key, result, socket)
        end

        defoverridable mount: 3, render: 1, handle_event: 3, handle_info: 2, handle_async: 3
      end
    end

    @doc false
    def build_config(opts) do
      %{
        ui: Keyword.fetch!(opts, :ui),
        actor_fn: Keyword.get(opts, :actor_fn) || fn _socket -> nil end,
        tenant_fn: Keyword.get(opts, :tenant_fn) || fn _socket -> nil end,
        pubsub: normalize_pubsub(Keyword.get(opts, :pubsub)),
        refresh_debounce_ms: Keyword.get(opts, :refresh_debounce_ms, @default_debounce_ms),
        deep_link: Keyword.get(opts, :deep_link, false),
        time_travel: Keyword.get(opts, :time_travel, false),
        open_surface: Keyword.get(opts, :open_surface),
        open_surface_url: Keyword.get(opts, :open_surface_url),
        on_function_response: Keyword.get(opts, :on_function_response),
        header: Keyword.get(opts, :header, true),
        surfaces: normalize_surfaces(Keyword.get(opts, :surfaces, [])),
        locale_fn: Keyword.get(opts, :locale_fn) || fn _socket -> nil end,
        l10n:
          Keyword.take(opts, [:gettext_backend, :gettext_fn, :metadata_domain, :errors_domain]),
        surface_fn: Keyword.get(opts, :surface_fn, &AshA2ui.Info.build_surface/2),
        data_model_fn: Keyword.get(opts, :data_model_fn, &AshA2ui.Info.build_data_model/2),
        action_fn: Keyword.get(opts, :action_fn, &AshA2ui.ActionHandler.handle/3)
      }
    end

    @doc false
    def mount(config, params, _session, socket) do
      actor = config.actor_fn.(socket)
      tenant = config.tenant_fn.(socket)
      locale = config.locale_fn.(socket)
      url_state = url_state(params)
      as_of = url_as_of(config, params)

      socket =
        assign(socket,
          ash_a2ui_ui: config.ui,
          ash_a2ui_actor: actor,
          ash_a2ui_tenant: tenant,
          ash_a2ui_as_of: as_of,
          ash_a2ui_locale: locale,
          ash_a2ui_l10n: l10n_opts(config, locale),
          ash_a2ui_refresh_scheduled?: false,
          ash_a2ui_query_state: nil,
          ash_a2ui_context_state: nil,
          ash_a2ui_uri: nil,
          ash_a2ui_url_ctx: url_state.ctx,
          ash_a2ui_pending_calls: %{},
          ash_a2ui_surfaces: %{}
        )

      socket =
        if connected?(socket) do
          subscribe(config.pubsub)

          # Zero jank: the surface build is a DB read (records + options +
          # contexts) and must not block the mount — the container renders
          # now, the JS hook shows its skeleton, and the bootstrap messages
          # hydrate the surface when the task lands. URL-carried state is
          # validated inside the task (authorized context reads).
          socket
          |> start_async(:ash_a2ui_surface, fn ->
            opts =
              [actor: actor, tenant: tenant] ++
                AshA2ui.AsOf.read_opt(as_of) ++ l10n_opts(config, locale)

            config.surface_fn.(
              config.ui,
              opts ++
                initial_state_opts(config.ui, url_state, opts) ++
                link_button_opts(config) ++ header_opts(config)
            )
          end)
          |> start_surfaces(config, params)
        else
          socket
        end

      {:ok, socket}
    end

    # The additional surfaces (`:surfaces`): each built in its own async
    # task, as the same actor/tenant/as_of/l10n as the main surface, with its
    # context selection from the host's `context` function.
    defp start_surfaces(socket, config, params) do
      Enum.reduce(config.surfaces, socket, fn surface, socket ->
        start_surface(socket, config, surface, surface_selection(surface, params, socket))
      end)
    end

    defp start_surface(socket, config, surface, selection) do
      opts = call_opts(socket)

      socket
      |> put_surface_state(surface.name, %{
        selection: selection,
        built?: false,
        query_state: nil,
        context_state: nil
      })
      |> start_async({:ash_a2ui_surface, surface.name}, fn ->
        context =
          if selection == %{},
            do: [],
            else: [context_state: AshA2ui.Info.context_state_for(surface.ui, selection, opts)]

        config.surface_fn.(
          surface.ui,
          opts ++ context ++ link_button_opts(config) ++ [header: false]
        )
      end)
    end

    defp surface_selection(%{context: nil}, _params, _socket), do: %{}

    defp surface_selection(%{context: context}, params, socket) do
      case context.(params, socket) do
        selection when is_map(selection) ->
          for {key, id} <- selection, is_binary(id) and id != "", into: %{} do
            {to_string(key), id}
          end

        _none ->
          %{}
      end
    end

    # A params change (live navigation, back/forward) that changes an extra
    # surface's selection rebuilds that surface.
    defp restart_changed_surfaces(socket, config, params) do
      Enum.reduce(config.surfaces, socket, fn surface, socket ->
        name = surface.name
        selection = surface_selection(surface, params, socket)

        case socket.assigns.ash_a2ui_surfaces do
          %{^name => %{selection: ^selection}} -> socket
          _changed -> start_surface(socket, config, surface, selection)
        end
      end)
    end

    defp put_surface_state(socket, name, state) do
      assign(socket, :ash_a2ui_surfaces, Map.put(socket.assigns.ash_a2ui_surfaces, name, state))
    end

    defp update_surface_state(socket, name, fun) do
      case socket.assigns.ash_a2ui_surfaces do
        %{^name => state} -> put_surface_state(socket, name, fun.(state))
        _unknown -> socket
      end
    end

    # The URL's ctx/q params (anything else — including a LiveView not
    # mounted at the router — carries no state).
    defp url_state(params) when is_map(params) do
      %{
        ctx: string_map(Map.get(params, "ctx")),
        query: params |> Map.get("q") |> query_params()
      }
    end

    defp url_state(_not_mounted_at_router), do: %{ctx: %{}, query: nil}

    # time_travel: the URL's ?as_of= instant, nil (now) otherwise.
    defp url_as_of(%{time_travel: true}, params), do: AshA2ui.AsOf.from_params(params)
    defp url_as_of(_config, _params), do: nil

    defp string_map(map) when is_map(map) do
      for {key, value} <- map, is_binary(key) and is_binary(value) and value != "", into: %{} do
        {key, value}
      end
    end

    defp string_map(_other), do: %{}

    # URL values are strings; the /query state's page/pageSize are integers.
    defp query_params(map) when is_map(map) and map_size(map) > 0 do
      Map.new(map, fn
        {key, value} when key in ["page", "pageSize"] and is_binary(value) ->
          case Integer.parse(value) do
            {int, ""} -> {key, int}
            _not_an_integer -> {key, value}
          end

        {key, value} when is_map(value) and key not in ["sort", "filters", "ranges"] ->
          {key, query_params(value)}

        pair ->
          pair
      end)
    end

    defp query_params(_none), do: nil

    # Basic-catalog link Buttons only when an accepted "open_surface" can
    # navigate somewhere (a callback or a URL template); otherwise link
    # values stay plain Text rather than controls that do nothing.
    defp link_button_opts(config) do
      if navigates?(config), do: [link_buttons: true], else: []
    end

    # `header: false` only when configured, so the default build is unchanged.
    defp header_opts(%{header: false}), do: [header: false]
    defp header_opts(_config), do: []

    defp navigates?(config) do
      is_function(config.open_surface, 2) or
        is_binary(config.open_surface_url || Application.get_env(:ash_a2ui, :open_surface_url))
    end

    defp initial_state_opts(ui, url_state, opts) do
      context =
        if url_state.ctx == %{},
          do: [],
          else: [context_state: AshA2ui.Info.context_state_for(ui, url_state.ctx, opts)]

      query = if url_state.query, do: [query_state: url_state.query], else: []

      context ++ query
    end

    @doc """
    Default `handle_params/3` injected by `deep_link: true`: records the
    current URI (the base for context `push_patch`es) and — on browser
    back/forward to different `ctx` params — re-applies the URL's context
    selections (validated like the mount's) and pushes the refreshed data
    model. An additional surface (`:surfaces`) whose `:context` selection
    changed with the params is rebuilt.
    """
    def handle_params(config, params, uri, socket) do
      first? = is_nil(socket.assigns[:ash_a2ui_uri])
      socket = assign(socket, :ash_a2ui_uri, uri)
      ctx = url_state(params).ctx

      cond do
        first? or not connected?(socket) ->
          {:noreply, assign(socket, :ash_a2ui_url_ctx, ctx)}

        # A new instant rebuilds the surface: pinned and live surfaces carry
        # different controls, so a data-model refresh is not enough.
        url_as_of(config, params) != socket.assigns[:ash_a2ui_as_of] ->
          {:noreply, push_navigate(socket, to: request_path(uri))}

        true ->
          socket
          |> restart_changed_surfaces(config, params)
          |> apply_url_context(config, ctx)
      end
    end

    defp apply_url_context(socket, config, ctx) do
      cond do
        not config.deep_link ->
          {:noreply, socket}

        ctx == socket.assigns[:ash_a2ui_url_ctx] ->
          {:noreply, socket}

        true ->
          opts = call_opts(socket)
          context_state = AshA2ui.Info.context_state_for(config.ui, ctx, opts)

          data_model =
            config.data_model_fn.(
              config.ui,
              socket |> assign(:ash_a2ui_context_state, context_state) |> refresh_opts()
            )

          socket =
            socket
            |> assign(:ash_a2ui_url_ctx, ctx)
            |> track_query_state([data_model])
            |> track_context_state([data_model])

          {:noreply, push_messages(socket, [data_model])}
      end
    end

    @doc """
    Default handler for the `"a2ui:open_surface"` event (reference links):
    the `:open_surface` callback when configured, else `push_navigate` to
    the `:open_surface_url` template (or `config :ash_a2ui,
    :open_surface_url`) — the target is always built server-side. Without
    either, the request is ignored.
    """
    def handle_open_surface(config, args, socket) do
      surface = Map.get(args, "surface")

      cond do
        not is_binary(surface) or surface == "" ->
          {:noreply, socket}

        is_function(config.open_surface, 2) ->
          config.open_surface.(args, socket)

        template = config.open_surface_url || Application.get_env(:ash_a2ui, :open_surface_url) ->
          record_id = Map.get(args, "recordId")
          record_id = if is_binary(record_id) or is_integer(record_id), do: to_string(record_id)
          path = AshA2ui.Links.href(template, surface, record_id)

          {:noreply, push_navigate(socket, to: with_query(path, args))}

        true ->
          {:noreply, socket}
      end
    end

    defp with_query(path, %{"query" => query}) when is_map(query) and map_size(query) > 0 do
      separator = if String.contains?(path, "?"), do: "&", else: "?"
      path <> separator <> Query.encode(query)
    end

    defp with_query(path, _args), do: path

    defp request_path(uri) do
      case URI.parse(uri) do
        %URI{path: path, query: nil} -> path || "/"
        %URI{path: path, query: query} -> (path || "/") <> "?" <> query
      end
    end

    @doc """
    The hook container: `<div id="ash-a2ui-surface" phx-hook="AshA2ui"
    phx-update="ignore">`. `render/1` of a LiveRenderer LiveView renders it
    with the defaults.

    A page that shows a second surface renders a second container with its
    own `id` and `surface`; the JS hook then takes only that surface's
    messages (see the LiveView topic of the usage rules).

        <AshA2ui.LiveRenderer.surface_container id="summary" surface="order_summary" />
    """
    attr(:id, :string, default: "ash-a2ui-surface", doc: "The container's DOM id.")

    attr(:surface, :string,
      default: nil,
      doc: "The surface id this container renders (`data-a2ui-surface`). Unset renders any."
    )

    attr(:primary, :boolean,
      default: false,
      doc: "Takes the messages that name no surface (`data-a2ui-primary`)."
    )

    def surface_container(assigns) do
      # A host that passes its own assigns through (`surface_container(assigns)`)
      # may hold an unrelated `@surface`, `@id` or `@primary` (a struct, a map):
      # only a string id or surface and a literal `true` count, anything else
      # renders as the default rather than crashing the render.
      attrs = [
        id: if(is_binary(assigns[:id]), do: assigns.id, else: "ash-a2ui-surface"),
        surface: if(is_binary(assigns[:surface]), do: assigns.surface),
        primary: assigns[:primary] == true
      ]

      # assign/2 keeps change tracking in a template; a hand call has none to keep.
      assigns =
        if Map.has_key?(assigns, :__changed__),
          do: assign(assigns, attrs),
          else: Map.merge(assigns, Map.new(attrs))

      ~H"""
      <div
        id={@id}
        phx-hook="AshA2ui"
        phx-update="ignore"
        data-a2ui-surface={@surface}
        data-a2ui-primary={@primary}
      ></div>
      """
    end

    @doc false
    def handle_message(config, message, socket) do
      case message_surface(config, message) do
        nil -> handle_main_message(config, message, socket)
        surface -> handle_surface_message(config, surface, message, socket)
      end
    end

    # A message from an extra surface (`:surfaces`), by the `surfaceId` it
    # names; anything else (a rendererFunctionResponse names none) is the
    # main surface's.
    defp message_surface(%{surfaces: []}, _message), do: nil

    defp message_surface(config, message) do
      case message_surface_id(message) do
        surface_id when is_binary(surface_id) ->
          Enum.find(config.surfaces, &(&1.surface_id == surface_id))

        _none ->
          nil
      end
    end

    defp message_surface_id(%{"callAgentFunction" => %{"surfaceId" => surface_id}}),
      do: surface_id

    defp message_surface_id(%{"action" => %{"surfaceId" => surface_id}}), do: surface_id
    defp message_surface_id(%{"error" => %{"surfaceId" => surface_id}}), do: surface_id
    defp message_surface_id(_message), do: nil

    # The extra surface's UI answers, with the same call options; its
    # follow-ups are tracked in its own state and never touch the main
    # surface's query/context state or the URL.
    defp handle_surface_message(config, surface, message, socket) do
      {outcome, messages} = config.action_fn.(surface.ui, message, call_opts(socket))

      socket =
        socket
        |> update_surface_state(surface.name, &track_states(&1, messages))
        |> push_messages(messages)

      maybe_open_surface(config, outcome, message, socket)
    end

    defp handle_main_message(config, message, socket) do
      {outcome, messages} = config.action_fn.(config.ui, message, call_opts(socket))

      case {outcome, message} do
        {:ok, %{"rendererFunctionResponse" => response}} ->
          {:noreply, settle_function_response(config, response, socket)}

        _action_call_or_refusal ->
          previous_context = socket.assigns.ash_a2ui_context_state

          socket =
            socket
            |> track_query_state(messages)
            |> track_context_state(messages)
            |> push_messages(messages)
            |> maybe_patch_context(config, previous_context)

          maybe_open_surface(config, outcome, message, socket)
      end
    end

    # A basic-catalog reference link arrives as an "open_surface" ashAction
    # call. Once the handler accepted it
    # (the field links to that surface for this actor), it navigates exactly
    # like the "a2ui:open_surface" event the admin catalog's link cells push.
    defp maybe_open_surface(config, :ok, message, socket) do
      case action_name(message) do
        {"open_surface", context} when is_map(context) ->
          handle_open_surface(config, Map.take(context, ["surface", "recordId"]), socket)

        _other ->
          {:noreply, socket}
      end
    end

    defp maybe_open_surface(_config, _outcome, _message, socket), do: {:noreply, socket}

    defp action_name(%{
           "callAgentFunction" => %{"callFunction" => %{"args" => %{"name" => name} = args}}
         }),
         do: {name, Map.get(args, "context", %{})}

    defp action_name(_message), do: nil

    # A rendererFunctionResponse settles the pending call with its id, once.
    defp settle_function_response(config, %{"functionCallId" => call_id} = response, socket) do
      case Map.pop(socket.assigns.ash_a2ui_pending_calls, call_id, :none) do
        {:none, _pending} ->
          Logger.warning(
            "Dropped an A2UI rendererFunctionResponse for #{inspect(call_id)}: no pending call " <>
              "has that id (a duplicate, a late answer, or an id this LiveView never sent)."
          )

          socket

        {function_name, pending} ->
          log_function_error(function_name, call_id, response)
          socket = assign(socket, :ash_a2ui_pending_calls, pending)

          case config.on_function_response do
            callback when is_function(callback, 3) -> callback.(response, function_name, socket)
            _none -> socket
          end
      end
    end

    defp log_function_error(function_name, call_id, %{"error" => %{"code" => code}}) do
      Logger.warning(
        "A2UI renderer function #{function_name} (#{inspect(call_id)}) failed: #{code}"
      )
    end

    defp log_function_error(_function_name, _call_id, _response), do: :ok

    # deep_link: a changed /context is written back to the URL (the ctx
    # params), so the selection is shareable and back-button friendly.
    defp maybe_patch_context(socket, %{deep_link: true}, previous) do
      current = socket.assigns.ash_a2ui_context_state
      uri = socket.assigns[:ash_a2ui_uri]

      if is_binary(uri) and is_map(current) and current != previous do
        ctx = context_ids(current)

        if ctx == socket.assigns[:ash_a2ui_url_ctx] do
          socket
        else
          socket
          |> assign(:ash_a2ui_url_ctx, ctx)
          |> push_patch(to: patched_path(uri, ctx), replace: false)
        end
      else
        socket
      end
    end

    defp maybe_patch_context(socket, _config, _previous), do: socket

    defp context_ids(context_state) do
      for {name, %{"value" => value}} <- context_state,
          is_binary(value) and value != "",
          into: %{},
          do: {name, value}
    end

    defp patched_path(uri, ctx) do
      %URI{path: path, query: query} = URI.parse(uri)

      params =
        (query || "")
        |> Query.decode()
        |> Map.delete("ctx")
        |> then(&if(ctx == %{}, do: &1, else: Map.put(&1, "ctx", ctx)))

      case Query.encode(params) do
        "" -> path || "/"
        encoded -> (path || "/") <> "?" <> encoded
      end
    end

    @doc """
    Delivers the async surface bootstrap started by `mount/3`. On `{:ok,
    messages}` the messages are tracked (query/context state) and pushed to
    the hook; on `{:exit, reason}` the LiveView exits with the same reason —
    a failed bootstrap must crash loudly, not strand the client on the
    skeleton.
    """
    def handle_async(_config, :ash_a2ui_surface, {:ok, messages}, socket) do
      socket =
        socket
        |> track_query_state(messages)
        |> track_context_state(messages)

      {:noreply, push_messages(socket, messages)}
    end

    def handle_async(_config, :ash_a2ui_surface, {:exit, reason}, _socket) do
      exit(reason)
    end

    def handle_async(_config, {:ash_a2ui_surface, name}, {:ok, messages}, socket) do
      socket =
        update_surface_state(socket, name, fn state ->
          state |> track_states(messages) |> Map.put(:built?, true)
        end)

      {:noreply, push_messages(socket, messages)}
    end

    def handle_async(_config, {:ash_a2ui_surface, _name}, {:exit, reason}, _socket) do
      exit(reason)
    end

    @doc false
    def handle_notification(config, message, socket)

    def handle_notification(config, @refresh_message, socket) do
      socket = assign(socket, :ash_a2ui_refresh_scheduled?, false)
      data_model = config.data_model_fn.(config.ui, refresh_opts(socket))

      socket =
        socket
        |> track_query_state([data_model])
        |> track_context_state([data_model])

      {socket, surface_models} = refresh_surfaces(config, socket)

      {:noreply, push_messages(socket, [data_model | surface_models])}
    end

    def handle_notification(%{pubsub: nil}, _message, socket) do
      {:noreply, socket}
    end

    # Any other message while :pubsub is configured is treated as a broadcast
    # on a subscribed topic (an %Ash.Notifier.Notification{}, a
    # %Phoenix.Socket.Broadcast{}, or an arbitrary payload) and coalesced into
    # the next scheduled refresh.
    def handle_notification(config, _message, socket) do
      {:noreply, schedule_refresh(config, socket)}
    end

    # The extra surfaces refresh with the main one, each with its own tracked
    # query/context state. One still bootstrapping is skipped: its build is
    # already reading the changed data.
    defp refresh_surfaces(config, socket) do
      Enum.reduce(config.surfaces, {socket, []}, fn surface, {socket, models} ->
        name = surface.name

        case socket.assigns.ash_a2ui_surfaces do
          %{^name => %{built?: true} = state} ->
            model = config.data_model_fn.(surface.ui, state_opts(call_opts(socket), state))

            {update_surface_state(socket, surface.name, &track_states(&1, [model])),
             models ++ [model]}

          _not_built ->
            {socket, models}
        end
      end)
    end

    defp subscribe(nil), do: :ok

    defp subscribe(%{module: module, topics: topics}) do
      Enum.each(topics, &Phoenix.PubSub.subscribe(module, &1))
    end

    defp schedule_refresh(config, socket) do
      if socket.assigns.ash_a2ui_refresh_scheduled? do
        socket
      else
        Process.send_after(self(), @refresh_message, config.refresh_debounce_ms)
        assign(socket, :ash_a2ui_refresh_scheduled?, true)
      end
    end

    defp push_messages(socket, []), do: socket

    defp push_messages(socket, messages) do
      socket
      |> track_renderer_calls(messages)
      |> push_event(@messages_event, %{messages: messages})
    end

    # Every callRendererFunction pushed is pending until the renderer's
    # rendererFunctionResponse with its id arrives.
    defp track_renderer_calls(socket, messages) do
      calls =
        for %{"callRendererFunction" => %{"functionCallId" => id, "callFunction" => call}} <-
              messages,
            into: %{},
            do: {id, call["@call"]}

      if calls == %{},
        do: socket,
        else:
          assign(
            socket,
            :ash_a2ui_pending_calls,
            Map.merge(socket.assigns.ash_a2ui_pending_calls, calls)
          )
    end

    # Remembers the last /query state pushed to the client (from the full
    # data model: the inline createSurface.dataModel on mount, a root
    # updateDataModel on refresh, or a /query update in an action follow-up)
    # so PubSub refreshes can re-run the user's current query instead of the
    # declared defaults.
    defp track_query_state(socket, messages) do
      assign(
        socket,
        :ash_a2ui_query_state,
        fold_query_state(socket.assigns.ash_a2ui_query_state, messages)
      )
    end

    defp fold_query_state(state, messages) do
      Enum.reduce(messages, state, fn
        %{"updateDataModel" => %{"path" => "/query", "value" => value}}, _acc
        when is_map(value) ->
          value

        # Multi-table surfaces scope follow-ups per table
        # (/query/<component_name>); fold them into the tracked keyed map.
        %{"updateDataModel" => %{"path" => "/query/" <> table, "value" => value}}, acc
        when is_map(value) ->
          Map.put((is_map(acc) && acc) || %{}, table, value)

        message, acc ->
          root_value(message, "query", acc)
      end)
    end

    # Same for the last /context state (surface contexts): a context change
    # rewrites /context wholesale; the full data model carries it under
    # "context".
    defp track_context_state(socket, messages) do
      assign(
        socket,
        :ash_a2ui_context_state,
        fold_context_state(socket.assigns.ash_a2ui_context_state, messages)
      )
    end

    defp fold_context_state(state, messages) do
      Enum.reduce(messages, state, fn
        %{"updateDataModel" => %{"path" => "/context", "value" => value}}, _acc
        when is_map(value) ->
          value

        message, acc ->
          root_value(message, "context", acc)
      end)
    end

    # An extra surface's tracked query/context state.
    defp track_states(state, messages) do
      %{
        state
        | query_state: fold_query_state(state.query_state, messages),
          context_state: fold_context_state(state.context_state, messages)
      }
    end

    # `key` of a whole data model: createSurface's inline dataModel, or a
    # root updateDataModel (no path, or "/"). Otherwise the tracked `acc`.
    defp root_value(%{"createSurface" => %{"dataModel" => %{} = model}}, key, acc),
      do: map_value(model, key, acc)

    defp root_value(%{"updateDataModel" => %{"value" => %{} = model} = update}, key, acc) do
      if Map.get(update, "path", "/") == "/", do: map_value(model, key, acc), else: acc
    end

    defp root_value(_message, _key, acc), do: acc

    defp map_value(model, key, acc) do
      case Map.get(model, key) do
        value when is_map(value) -> value
        _absent -> acc
      end
    end

    defp call_opts(socket) do
      [actor: socket.assigns.ash_a2ui_actor, tenant: socket.assigns.ash_a2ui_tenant] ++
        AshA2ui.AsOf.read_opt(socket.assigns[:ash_a2ui_as_of]) ++
        Map.get(socket.assigns, :ash_a2ui_l10n, [])
    end

    defp l10n_opts(config, nil), do: config.l10n
    defp l10n_opts(config, locale), do: [{:locale, locale} | config.l10n]

    defp refresh_opts(socket) do
      state_opts(call_opts(socket), %{
        query_state: socket.assigns.ash_a2ui_query_state,
        context_state: socket.assigns.ash_a2ui_context_state
      })
    end

    defp state_opts(opts, state) do
      opts =
        case state.query_state do
          nil -> opts
          query_state -> Keyword.put(opts, :query_state, query_state)
        end

      case state.context_state do
        nil -> opts
        context_state -> Keyword.put(opts, :context_state, context_state)
      end
    end

    defp normalize_surfaces(surfaces) do
      for {name, opts} <- surfaces do
        opts = Keyword.validate!(opts, [:ui, :context])
        ui = Keyword.fetch!(opts, :ui)
        context = Keyword.get(opts, :context)

        unless is_nil(context) or is_function(context, 2) do
          raise ArgumentError,
                "the #{inspect(name)} surface's :context must be a 2-arity function " <>
                  "(params, socket) -> selection map, got: #{inspect(context)}"
        end

        %{name: name, ui: ui, surface_id: AshA2ui.ResolvedView.surface_id(ui), context: context}
      end
    end

    defp normalize_pubsub(nil), do: nil

    defp normalize_pubsub(opts) do
      %{module: Keyword.fetch!(opts, :module), topics: Keyword.get(opts, :topics, [])}
    end
  end
end
