# Minimal Phoenix test endpoint + router for LiveRenderer tests
# (Phoenix.LiveViewTest-ready). Guarded so the NO_PHOENIX CI job (which strips
# the Phoenix stack) still compiles test/support cleanly.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Test.ErrorHTML do
    @moduledoc false

    def render(template, _assigns) do
      Phoenix.Controller.status_message_from_template(template)
    end
  end

  defmodule AshA2ui.Test.Router do
    @moduledoc false

    use Phoenix.Router

    import Phoenix.LiveView.Router

    pipeline :browser do
      plug(:accepts, ["html"])
      plug(:fetch_session)
    end

    scope "/" do
      pipe_through(:browser)

      # LiveRenderer test LiveViews (defined in test/live_renderer_test.exs;
      # the `live` macro only records the module as route metadata, so it is
      # safe to reference modules that are loaded later, at test time).
      live("/live-renderer/stubbed", AshA2ui.Test.StubbedLive)
      live("/live-renderer/pubsub", AshA2ui.Test.PubsubStubLive)
      live("/live-renderer/defaults", AshA2ui.Test.DefaultsLive)
      live("/live-renderer/query", AshA2ui.Test.QueryDefaultsLive)
      live("/live-renderer/query-pubsub", AshA2ui.Test.QueryPubsubLive)
      live("/live-renderer/multi-table", AshA2ui.Test.MultiTableLive)
      live("/live-renderer/context-pubsub", AshA2ui.Test.ContextPubsubLive)
      live("/live-renderer/deep-link", AshA2ui.Test.DeepLinkLive)
      live("/live-renderer/people-deep-link", AshA2ui.Test.PeopleDeepLinkLive)
      live("/live-renderer/open-surface-callback", AshA2ui.Test.OpenSurfaceCallbackLive)
      live("/live-renderer/time-travel", AshA2ui.Test.TimeTravelLive)

      # The actor picker, reachable both ways hosts wire it: standalone
      # (its own live_session — links from surfaces reload the document)
      # and in-session (a shared live_session carrying
      # `on_mount AshA2ui.Actor`, so in-app navigation renders it without
      # a document reload).
      live("/acting-as", AshA2ui.ActorPickerLive)

      live_session :a2ui_shared, on_mount: AshA2ui.Actor do
        live("/acting-as/shared", AshA2ui.ActorPickerLive)
      end

      # The presence surface fixture (AshA2ui.Presence + PresenceBar).
      live("/presence", AshA2ui.Test.PresenceLive)

      # The surface composer (AshA2ui.Web.ComposerLive), configured with one
      # standalone UI module fixture and one on-resource surface.
      live("/composer", AshA2ui.Test.ComposerLive)

      # The same composer with a host-NAMED allowlist map (the escape hatch
      # for colliding resource short names).
      live("/composer/named", AshA2ui.Test.ComposerNamedAllowlistLive)

      # A master/detail surface whose related tables read other resources.
      live("/composer/related", AshA2ui.Test.ComposerRelatedLive)
    end
  end

  defmodule AshA2ui.Test.Endpoint do
    @moduledoc false

    use Phoenix.Endpoint, otp_app: :ash_a2ui

    @session_options [
      store: :cookie,
      key: "_ash_a2ui_test",
      signing_salt: "aaaaaaaaaaaaaaaa",
      same_site: "Lax"
    ]

    socket("/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]]
    )

    plug(Plug.Session, @session_options)
    plug(AshA2ui.Test.Router)
  end
end
