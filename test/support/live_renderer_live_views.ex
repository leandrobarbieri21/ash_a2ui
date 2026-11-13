# Track 4 test fixtures for live_renderer_test.exs: hand-written schema-valid
# A2UI messages, stub seam functions, and the LiveView modules routed in
# AshA2ui.Test.Router. Lives in test/support (not the .exs) so the router's
# compile-time `__checks__` (which capture &LiveView.__live__/0) resolve
# without undefined-module warnings. Guarded like the endpoint so the
# NO_PHOENIX job compiles cleanly.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Test.LiveRendererFixtures do
    @moduledoc """
    Hand-written, schema-valid A2UI 1.0 message fixtures plus a tiny
    listener mailbox so the stub `surface_fn`/`data_model_fn`/`action_fn`
    injected into the test LiveViews can report their calls back to the
    test process (registered via the `:live_renderer_test_listener` app env).
    """

    alias AshA2ui.Experience
    alias AshA2ui.Test.Messages

    @catalog_id "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    @surface_id "minimal_standalone"

    def surface_id, do: @surface_id

    def create_surface do
      %{
        "version" => "1.0",
        "createSurface" => %{
          "surfaceId" => @surface_id,
          "catalogId" => @catalog_id,
          "components" => [
            %{"id" => "root", "component" => "Column", "children" => ["title"]},
            %{"id" => "title", "component" => "Text", "text" => "Providers"}
          ],
          "dataModel" => %{"records" => [%{"id" => "1", "name" => "Acme"}]}
        }
      }
    end

    def update_data_model, do: write("/records", [%{"id" => "1", "name" => "Acme"}])

    def surface_messages, do: [create_surface()]

    def action_ok_messages,
      do: [update_data_model(), write("/ui/feedback", Experience.feedback("success", "saved"))]

    def action_error_messages do
      [
        write("/errors/name", "has already been taken"),
        write(
          "/ui/feedback",
          Experience.feedback("error", "error", %{"code" => "VALIDATION_FAILED"})
        )
      ]
    end

    # The export's downloadFile call, as AshA2ui.ActionHandler pushes it.
    def download_call(call_id) do
      %{
        "version" => "1.0",
        "callRendererFunction" => %{
          "surfaceId" => @surface_id,
          "functionCallId" => call_id,
          "callFunction" => %{
            "@call" => "downloadFile",
            "catalogId" => AshA2ui.Encoder.ash_catalog_id(),
            "args" => %{"filename" => "rows.csv", "dataUrl" => "data:text/csv;base64,YQ=="}
          }
        }
      }
    end

    def function_response(call_id, outcome \\ {:ok, nil})

    def function_response(call_id, {:ok, value}),
      do: %{
        "version" => "1.0",
        "rendererFunctionResponse" => %{"functionCallId" => call_id, "value" => value}
      }

    def function_response(call_id, {:error, code}),
      do: %{
        "version" => "1.0",
        "rendererFunctionResponse" => %{
          "functionCallId" => call_id,
          "error" => %{"code" => code, "message" => "could not save"}
        }
      }

    def write(path, value),
      do: %{
        "version" => "1.0",
        "updateDataModel" => %{"surfaceId" => @surface_id, "path" => path, "value" => value}
      }

    def action_envelope(name \\ "submit_form", context \\ %{"form" => %{"name" => "Acme"}}) do
      Messages.call(name, @surface_id, context, source: "form_submit")
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
    def pseudo_locale(_socket), do: "pseudo"

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
        %{
          "callAgentFunction" => %{
            "callFunction" => %{"args" => %{"context" => %{"fail" => true}}}
          }
        } ->
          {:error, Fixtures.action_error_messages()}

        %{
          "callAgentFunction" => %{
            "callFunction" => %{"args" => %{"context" => %{"export" => call_id}}}
          }
        } ->
          {:ok, [Fixtures.download_call(call_id)]}

        %{"callAgentFunction" => _call} ->
          {:ok, Fixtures.action_ok_messages()}

        # Function responses, errors and malformed messages: the real
        # handler validates them.
        _other ->
          AshA2ui.ActionHandler.handle(ui, envelope, opts)
      end
    end

    # The `on_function_response:` callback: reports the settled call.
    def function_response(response, function_name, socket) do
      Fixtures.notify({:on_function_response, function_name, response})
      socket
    end

    # `:surfaces` stubs: the fixture messages addressed to the UI's own
    # surface id, so a page with two surfaces gets two distinguishable
    # bootstraps.
    def scoped_surface(ui, opts) do
      Fixtures.notify({:surface_fn, ui, opts})
      Enum.map(Fixtures.surface_messages(), &readdress(&1, ui))
    end

    def scoped_data_model(ui, opts) do
      Fixtures.notify({:data_model_fn, ui, opts})
      readdress(Fixtures.update_data_model(), ui)
    end

    # The notes surface answers a context_select by rewriting its /context
    # (as the real handler does); the main surface answers as `action/3`.
    def scoped_action(AshA2ui.Test.Links.NotesUI = ui, envelope, opts) do
      notes_context_action(ui, envelope, opts)
    end

    def scoped_action(ui, envelope, opts), do: action(ui, envelope, opts)

    # The selection the notes surface is built with: the URL's `?person=`.
    def notes_selection(params, _socket) when is_map(params),
      do: %{person: params["person"]}

    def notes_selection(_not_mounted_at_router, _socket), do: nil

    defp readdress(message, ui) do
      surface_id = AshA2ui.ResolvedView.surface_id(ui)

      Map.new(message, fn
        {"version", _} = version -> version
        {kind, payload} -> {kind, Map.put(payload, "surfaceId", surface_id)}
      end)
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

      value =
        get_in(envelope, ["callAgentFunction", "callFunction", "args", "context", "value"]) || ""

      {:ok,
       [
         %{
           "version" => "1.0",
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
           "version" => "1.0",
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

  defmodule AshA2ui.Test.FunctionCallLive do
    @moduledoc false

    # Renderer function calls: the stub answers an action whose context
    # carries "export" with a downloadFile callRendererFunction, and the
    # LiveView settles the rendererFunctionResponse that answers it.
    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.MinimalUI,
      surface_fn: &Stubs.surface/2,
      action_fn: &Stubs.action/3,
      on_function_response: &Stubs.function_response/3
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
    # "a2ui:message" event into AshA2ui.ActionHandler.handle/3.
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

  defmodule AshA2ui.Test.SurfacesLive do
    @moduledoc false

    # A main surface plus an extra one (`:surfaces`): the notes surface,
    # selected by the URL's `?person=`, built, pushed, answered and
    # refreshed by the LiveRenderer with no host code. deep_link injects
    # handle_params, so a patch to another person rebuilds the notes.
    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.MinimalUI,
      actor_fn: &Stubs.actor/1,
      tenant_fn: &Stubs.tenant/1,
      deep_link: true,
      pubsub: [module: AshA2ui.Test.PubSub, topics: ["ash_a2ui_test:surfaces"]],
      surfaces: [
        notes: [ui: AshA2ui.Test.Links.NotesUI, context: &Stubs.notes_selection/2]
      ],
      surface_fn: &Stubs.scoped_surface/2,
      data_model_fn: &Stubs.scoped_data_model/2,
      action_fn: &Stubs.scoped_action/3
  end

  defmodule AshA2ui.Test.LocalizedLive do
    @moduledoc false

    alias AshA2ui.Test.LiveRendererStubs, as: Stubs

    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.MinimalUI,
      locale_fn: &Stubs.pseudo_locale/1,
      gettext_fn: {AshA2ui.Test.PseudoLocale, :translate},
      surface_fn: &Stubs.surface/2,
      action_fn: &Stubs.action/3
  end
end
