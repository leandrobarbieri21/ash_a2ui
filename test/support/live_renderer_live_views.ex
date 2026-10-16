# Track 4 test fixtures for live_renderer_test.exs: hand-written schema-valid
# A2UI messages, stub seam functions, and the LiveView modules routed in
# AshA2ui.Test.Router. Lives in test/support (not the .exs) so the router's
# compile-time `__checks__` (which capture &LiveView.__live__/0) resolve
# without undefined-module warnings. Guarded like the endpoint so the
# NO_PHOENIX job compiles cleanly.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Test.LiveRendererFixtures do
    @moduledoc """
    Hand-written, schema-valid A2UI v0.9.1 message fixtures plus a tiny
    listener mailbox so the stub `surface_fn`/`data_model_fn`/`action_fn`
    injected into the test LiveViews can report their calls back to the
    test process (registered via the `:live_renderer_test_listener` app env).
    """

    @catalog_id "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"
    @surface_id "minimal_standalone"

    def surface_id, do: @surface_id

    def create_surface do
      %{
        "version" => "v0.9.1",
        "createSurface" => %{"surfaceId" => @surface_id, "catalogId" => @catalog_id}
      }
    end

    def update_components do
      %{
        "version" => "v0.9.1",
        "updateComponents" => %{
          "surfaceId" => @surface_id,
          "components" => [
            %{"id" => "root", "component" => "Column", "children" => ["title"]},
            %{"id" => "title", "component" => "Text", "text" => "Providers"}
          ]
        }
      }
    end

    def update_data_model do
      %{
        "version" => "v0.9.1",
        "updateDataModel" => %{
          "surfaceId" => @surface_id,
          "path" => "/records",
          "value" => [%{"id" => "1", "name" => "Acme"}]
        }
      }
    end

    def surface_messages, do: [create_surface(), update_components(), update_data_model()]

    def action_ok_messages do
      [
        update_data_model(),
        %{
          "version" => "v0.9.1",
          "updateDataModel" => %{
            "surfaceId" => @surface_id,
            "path" => "/ui/feedback",
            "value" => %{"kind" => "success", "message" => "saved"}
          }
        }
      ]
    end

    def action_error_messages do
      [
        %{
          "version" => "v0.9.1",
          "updateDataModel" => %{
            "surfaceId" => @surface_id,
            "path" => "/errors/name",
            "value" => "has already been taken"
          }
        },
        %{
          "version" => "v0.9.1",
          "updateDataModel" => %{
            "surfaceId" => @surface_id,
            "path" => "/ui/feedback",
            "value" => %{"kind" => "error", "message" => "error"}
          }
        }
      ]
    end

    def action_envelope(name \\ "submit_form", context \\ %{"form" => %{"name" => "Acme"}}) do
      %{
        "version" => "v0.9.1",
        "action" => %{
          "name" => name,
          "surfaceId" => @surface_id,
          "sourceComponentId" => "form_submit",
          "timestamp" => "2026-07-10T12:00:00Z",
          "context" => context
        }
      }
    end

    def notify(message) do
      case Application.get_env(:ash_a2ui, :live_renderer_test_listener) do
        pid when is_pid(pid) -> send(pid, message)
        _ -> :ok
      end
    end
  end

  defmodule AshA2ui.Test.LiveRendererStubs do
    @moduledoc """
    Named-capture stubs injected through the LiveRenderer test seams
    (`surface_fn:`/`data_model_fn:`/`action_fn:`). They return the
    hand-written schema-valid fixtures and report every call to the
    listening test process.
    """

    alias AshA2ui.Test.LiveRendererFixtures, as: Fixtures

    def actor(_socket), do: :stub_actor
    def tenant(_socket), do: :stub_tenant

    def surface(ui, opts) do
      Fixtures.notify({:surface_fn, ui, opts})
      Fixtures.surface_messages()
    end

    def data_model(ui, opts) do
      Fixtures.notify({:data_model_fn, ui, opts})
      Fixtures.update_data_model()
    end

    def action(ui, envelope, opts) do
      Fixtures.notify({:action_fn, ui, envelope, opts})

      case envelope do
        %{"action" => %{"context" => %{"fail" => true}}} ->
          {:error, Fixtures.action_error_messages()}

        _ ->
          {:ok, Fixtures.action_ok_messages()}
      end
    end

    # Reference-link navigation callback (`open_surface:`).
    def open_surface(args, socket) do
      Fixtures.notify({:open_surface, args})
      {:noreply, socket}
    end

    # A NotesUI context_select follow-up: /context rewritten with the
    # selected person id from the envelope (deep-link push_patch tests).
    def notes_context_action(ui, envelope, opts) do
      Fixtures.notify({:action_fn, ui, envelope, opts})
      value = get_in(envelope, ["action", "context", "value"]) || ""

      {:ok,
       [
         %{
           "version" => "v0.9.1",
           "updateDataModel" => %{
             "surfaceId" => "notes",
             "path" => "/context",
             "value" => %{
               "person" => %{"search" => "", "value" => value, "label" => "Someone"},
               "note" => %{"search" => "", "value" => "", "label" => ""}
             }
           }
         }
       ]}
    end

    # A context_select follow-up: rewrites /context wholesale (the shape the
    # real ActionHandler emits), so the LiveRenderer can track it.
    def context_action(ui, envelope, opts) do
      Fixtures.notify({:action_fn, ui, envelope, opts})

      {:ok,
       [
         %{
           "version" => "v0.9.1",
           "updateDataModel" => %{
             "surfaceId" => Fixtures.surface_id(),
             "path" => "/context",
             "value" => %{"owner" => %{"search" => "", "value" => "o-1", "label" => "Ada"}}
           }
         }
       ]}
    end
  end

  defmodule AshA2ui.Test.StubbedLive do
    @moduledoc false

    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.MinimalUI,
      actor_fn: &Stubs.actor/1,
      tenant_fn: &Stubs.tenant/1,
      surface_fn: &Stubs.surface/2,
      data_model_fn: &Stubs.data_model/2,
      action_fn: &Stubs.action/3
  end

  defmodule AshA2ui.Test.PubsubStubLive do
    @moduledoc false

    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.MinimalUI,
      pubsub: [module: AshA2ui.Test.PubSub, topics: ["ash_a2ui_test:providers"]],
      surface_fn: &Stubs.surface/2,
      data_model_fn: &Stubs.data_model/2
  end

  defmodule AshA2ui.Test.DefaultsLive do
    @moduledoc false

    # Real defaults: AshA2ui.Info.build_surface/2, build_data_model/2 and
    # AshA2ui.ActionHandler.handle/3 — exercised only by the
    # :integration_pending test until Tracks 2/3 merge.
    use AshA2ui.LiveRenderer, ui: AshA2ui.Test.MinimalUI
  end

  defmodule AshA2ui.Test.QueryDefaultsLive do
    @moduledoc false

    # Real defaults against the query-enabled fixture, proving the "query"
    # action needs no LiveRenderer changes: it flows through the same
    # "a2ui:action" event into AshA2ui.ActionHandler.handle/3.
    use AshA2ui.LiveRenderer, ui: AshA2ui.Test.Paginated
  end

  defmodule AshA2ui.Test.QueryPubsubLive do
    @moduledoc false

    # Real defaults + PubSub against the query-enabled fixture: proves a
    # PubSub-driven refresh re-runs the client's last query state instead of
    # resetting the surface to the query defaults.
    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.Paginated,
      pubsub: [module: AshA2ui.Test.PubSub, topics: ["ash_a2ui_test:paginated"]]
  end

  defmodule AshA2ui.Test.MultiTableLive do
    @moduledoc false

    # Real defaults against the multi-table fixture: PubSub refreshes must
    # rebuild the data model for every table.
    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.ReviewItem,
      pubsub: [module: AshA2ui.Test.PubSub, topics: ["ash_a2ui_test:review"]]
  end

  defmodule AshA2ui.Test.ContextPubsubLive do
    @moduledoc false

    # Stubbed transport proving PubSub refreshes re-run the client's last
    # /context selections (passed as :context_state) instead of resetting
    # the surface to the unselected state. Stubs because the private ETS
    # fixtures aren't shared across the test and LiveView processes.
    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.MinimalUI,
      pubsub: [module: AshA2ui.Test.PubSub, topics: ["ash_a2ui_test:appointments"]],
      surface_fn: &Stubs.surface/2,
      data_model_fn: &Stubs.data_model/2,
      action_fn: &Stubs.context_action/3
  end

  defmodule AshA2ui.Test.DeepLinkLive do
    @moduledoc false

    # Deep links over the shared-ETS link fixtures: URL ctx/q params seed
    # the bootstrap (validated through authorized reads inside the async
    # task), context changes push_patch the URL, and back/forward
    # re-applies it. Stubbed builds report the opts they receive.
    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.Links.NotesUI,
      deep_link: true,
      open_surface_url: "/app/r/{surface}/{recordId}",
      surface_fn: &Stubs.surface/2,
      data_model_fn: &Stubs.data_model/2,
      action_fn: &Stubs.notes_context_action/3
  end

  defmodule AshA2ui.Test.PeopleDeepLinkLive do
    @moduledoc false

    # Unstubbed: the real Info builds and ActionHandler over the shared-ETS
    # related-table fixture, so a deep-linked mount renders exactly what the
    # library renders and basic-catalog link Buttons reach the real
    # open_surface validation before navigating.
    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.Links.PeopleUI,
      deep_link: true,
      open_surface_url: "/app/r/{surface}/{recordId}"
  end

  defmodule AshA2ui.Test.OpenSurfaceCallbackLive do
    @moduledoc false

    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.MinimalUI,
      open_surface: &Stubs.open_surface/2,
      surface_fn: &Stubs.surface/2
  end
end
