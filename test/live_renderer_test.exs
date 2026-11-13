# The whole file is Phoenix-only: under NO_PHOENIX the LiveRenderer, the test
# endpoint and the fixture LiveViews (test/support/live_renderer_live_views.ex)
# don't exist, so nothing here should even compile.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.LiveRendererTest do
    # async: false — the stub listener lives in global app env and the tests
    # share the app-wide test endpoint/PubSub.
    use ExUnit.Case, async: false

    import ExUnit.CaptureLog
    import Phoenix.Component, only: [sigil_H: 2]
    import Phoenix.ConnTest
    import Phoenix.LiveViewTest

    alias AshA2ui.Test.Links.NotesUI
    alias AshA2ui.Test.LiveRendererFixtures, as: Fixtures
    alias AshA2ui.Test.{Messages, MinimalUI, SchemaHelper, Surface}
    alias Plug.Conn.Query

    @endpoint AshA2ui.Test.Endpoint

    setup do
      Application.put_env(:ash_a2ui, :live_renderer_test_listener, self())

      on_exit(fn ->
        Application.delete_env(:ash_a2ui, :live_renderer_test_listener)
      end)

      [conn: Plug.Test.init_test_session(build_conn(), %{})]
    end

    describe "mount" do
      test "connected mount pushes schema-valid a2ui:messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        # The bootstrap now lands via the mount's async task — allow it
        # a generous window on slow CI.
        assert_push_event(view, "a2ui:messages", %{messages: messages}, 1_000)

        Enum.each(messages, &SchemaHelper.assert_valid_agent_message/1)
        assert [%{"createSurface" => %{"components" => [_ | _], "dataModel" => _}}] = messages
      end

      test "static render outputs the hook container without building the surface", %{conn: conn} do
        conn = get(conn, "/live-renderer/stubbed")
        html = html_response(conn, 200)

        assert html =~ ~s(id="ash-a2ui-surface")
        assert html =~ ~s(phx-hook="AshA2ui")
        assert html =~ ~s(phx-update="ignore")

        # surface_fn must not run on the static (disconnected) render
        refute_receive {:surface_fn, _, _}, 100
      end

      test "actor_fn and tenant_fn results are passed to surface_fn", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/stubbed")

        assert_receive {:surface_fn, MinimalUI, opts}
        assert opts[:actor] == :stub_actor
        assert opts[:tenant] == :stub_tenant
      end

      test "a LiveView that cannot navigate builds without link Buttons", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/stubbed")

        assert_receive {:surface_fn, MinimalUI, opts}, 1_000
        refute Keyword.has_key?(opts, :link_buttons)
      end

      test "an :open_surface callback turns basic-catalog link Buttons on", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/open-surface-callback")

        assert_receive {:surface_fn, MinimalUI, opts}, 1_000
        assert opts[:link_buttons] == true
      end

      test "assigns ui/actor/tenant on the socket for introspection", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.ash_a2ui_ui == MinimalUI
        assert assigns.ash_a2ui_actor == :stub_actor
        assert assigns.ash_a2ui_tenant == :stub_tenant
      end
    end

    describe "localization options" do
      test "locale_fn and the translator reach the build and every action", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/localized")

        assert_receive {:surface_fn, MinimalUI, opts}, 1_000
        assert opts[:locale] == "pseudo"
        assert opts[:gettext_fn] == {AshA2ui.Test.PseudoLocale, :translate}

        envelope = Fixtures.action_envelope()
        render_hook(view, "a2ui:message", envelope)

        assert_receive {:action_fn, MinimalUI, ^envelope, opts}
        assert opts[:locale] == "pseudo"
        assert opts[:gettext_fn] == {AshA2ui.Test.PseudoLocale, :translate}
      end

      test "without them no localization option is passed", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/stubbed")

        assert_receive {:surface_fn, MinimalUI, opts}, 1_000
        refute Enum.any?(AshA2ui.L10n.option_keys(), &Keyword.has_key?(opts, &1))
      end
    end

    describe "a2ui:message round-trip" do
      test "routes the envelope through action_fn and pushes the ok messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")
        envelope = Fixtures.action_envelope()
        SchemaHelper.assert_valid_renderer_message(envelope)

        render_hook(view, "a2ui:message", envelope)

        assert_receive {:action_fn, MinimalUI, ^envelope, opts}
        assert opts[:actor] == :stub_actor
        assert opts[:tenant] == :stub_tenant

        assert_push_event(view, "a2ui:messages", %{
          messages:
            [
              _,
              %{
                "updateDataModel" => %{
                  "path" => "/ui/feedback",
                  "value" => %{"message" => "saved"}
                }
              }
            ] = messages
        })

        Enum.each(messages, &SchemaHelper.assert_valid_agent_message/1)
      end

      test "an error tuple from action_fn also pushes its messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")
        envelope = Fixtures.action_envelope("invoke", %{"fail" => true})

        render_hook(view, "a2ui:message", envelope)

        assert_receive {:action_fn, MinimalUI, ^envelope, _opts}

        assert_push_event(view, "a2ui:messages", %{
          messages: [%{"updateDataModel" => %{"path" => "/errors/name"}} | _] = messages
        })

        Enum.each(messages, &SchemaHelper.assert_valid_agent_message/1)
      end
    end

    describe "renderer function calls" do
      setup %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/function-call")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        export = Fixtures.action_envelope("export", %{"export" => "fc_export"})
        render_hook(view, "a2ui:message", export)

        assert_push_event(view, "a2ui:messages", %{
          messages: [%{"callRendererFunction" => %{"functionCallId" => "fc_export"}} = call]
        })

        SchemaHelper.assert_valid_agent_message(call, catalogs: Messages.catalogs())
        [view: view]
      end

      defp pending_calls(view), do: :sys.get_state(view.pid).socket.assigns.ash_a2ui_pending_calls

      test "a pushed callRendererFunction is pending until its response settles it", %{
        view: view
      } do
        assert pending_calls(view) == %{"fc_export" => "downloadFile"}

        response = Fixtures.function_response("fc_export")
        SchemaHelper.assert_valid_renderer_message(response)
        render_hook(view, "a2ui:message", response)

        assert_receive {:on_function_response, "downloadFile",
                        %{"functionCallId" => "fc_export", "value" => nil}}

        assert pending_calls(view) == %{}
      end

      test "an error response is logged and handed to the callback", %{view: view} do
        log =
          capture_log(fn ->
            render_hook(
              view,
              "a2ui:message",
              Fixtures.function_response("fc_export", {:error, "QUOTA"})
            )

            _ = :sys.get_state(view.pid)
          end)

        assert log =~ "downloadFile"
        assert log =~ "QUOTA"
        assert_receive {:on_function_response, "downloadFile", %{"error" => %{"code" => "QUOTA"}}}
      end

      test "a duplicate response is dropped", %{view: view} do
        render_hook(view, "a2ui:message", Fixtures.function_response("fc_export"))
        assert_receive {:on_function_response, "downloadFile", _response}

        log =
          capture_log(fn ->
            render_hook(view, "a2ui:message", Fixtures.function_response("fc_export"))
            _ = :sys.get_state(view.pid)
          end)

        assert log =~ "no pending call has that id"
        refute_receive {:on_function_response, _name, _response}, 100
      end

      test "a response to an id this LiveView never sent is dropped", %{view: view} do
        capture_log(fn ->
          render_hook(view, "a2ui:message", Fixtures.function_response("fc_unknown"))
          _ = :sys.get_state(view.pid)
        end)

        refute_receive {:on_function_response, _name, _response}, 100
        assert pending_calls(view) == %{"fc_export" => "downloadFile"}
      end

      test "a malformed response settles nothing and pushes nothing", %{view: view} do
        malformed = %{
          "version" => "1.0",
          "rendererFunctionResponse" => %{"functionCallId" => "fc_export"}
        }

        capture_log(fn ->
          render_hook(view, "a2ui:message", malformed)
          _ = :sys.get_state(view.pid)
        end)

        refute_receive {:on_function_response, _name, _response}, 100
        refute_push_event(view, "a2ui:messages", %{messages: _messages}, 100)
        assert pending_calls(view) == %{"fc_export" => "downloadFile"}
      end
    end

    describe "PubSub live refresh" do
      test "a notification broadcast triggers a debounced data-model push", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/pubsub")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        notification = %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal}

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:providers",
          notification
        )

        assert_receive {:data_model_fn, MinimalUI, _opts}, 1_000

        assert_push_event(view, "a2ui:messages", %{messages: [message]}, 1_000)
        SchemaHelper.assert_valid_agent_message(message)
        assert %{"updateDataModel" => %{"path" => "/records"}} = message
      end

      test "arbitrary broadcast payloads on subscribed topics also trigger a refresh", %{
        conn: conn
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/pubsub")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:providers",
          %{topic: "ash_a2ui_test:providers", event: "create", payload: %{}}
        )

        assert_receive {:data_model_fn, MinimalUI, _opts}, 1_000
        assert_push_event(view, "a2ui:messages", %{messages: [_message]}, 1_000)
      end

      test "rapid notifications coalesce into a single refresh", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/pubsub")

        for _ <- 1..5 do
          Phoenix.PubSub.broadcast(
            AshA2ui.Test.PubSub,
            "ash_a2ui_test:providers",
            %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal}
          )
        end

        assert_receive {:data_model_fn, MinimalUI, _opts}, 1_000
        refute_receive {:data_model_fn, _, _}, 300
      end

      test "handle_info messages are ignored when pubsub is not configured", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        send(view.pid, %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal})
        send(view.pid, :unrelated)

        refute_receive {:data_model_fn, _, _}, 400
      end
    end

    describe "integration with real defaults" do
      test "mount with default surface_fn pushes schema-valid messages", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/defaults")

        assert_push_event(view, "a2ui:messages", %{messages: messages}, 1_000)
        assert messages != []
        Enum.each(messages, &SchemaHelper.assert_valid_agent_message/1)
      end

      test "a query action round-trips through the LiveView transport", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/query")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        envelope =
          Messages.call(
            "query",
            "paginated",
            %{"query" => %{"search" => "nothing matches this"}, "page" => 1},
            source: "query_apply_button"
          )

        SchemaHelper.assert_valid_renderer_message(envelope)
        render_hook(view, "a2ui:message", envelope)

        assert_push_event(view, "a2ui:messages", %{messages: messages})
        Enum.each(messages, &SchemaHelper.assert_valid_agent_message/1)

        assert [
                 %{"updateDataModel" => %{"path" => "/records", "value" => []}},
                 %{"updateDataModel" => %{"path" => "/_empty_visible", "value" => [_on]}},
                 %{"updateDataModel" => %{"path" => "/query", "value" => query_state}},
                 %{"agentFunctionResponse" => %{"value" => %{}}}
               ] = messages

        assert %{
                 "search" => "nothing matches this",
                 "page" => 1,
                 "hasMore" => false,
                 "_pagination_visible" => []
               } = query_state
      end

      test "a quiet ashAction function call round-trips and is answered last", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/query")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        call =
          Messages.call("query", "paginated", %{"query" => %{"search" => "x"}}, id: "fc_query")

        SchemaHelper.assert_valid_renderer_message(call,
          catalogs: Messages.catalogs()
        )

        render_hook(view, "a2ui:message", call)

        assert_push_event(view, "a2ui:messages", %{messages: messages})
        Enum.each(messages, &SchemaHelper.assert_valid_agent_message/1)

        # A query is quiet: it leaves /ui/feedback alone and answers with
        # an empty value.
        assert %{"agentFunctionResponse" => %{"functionCallId" => "fc_query", "value" => %{}}} =
                 List.last(messages)

        refute Enum.any?(
                 messages,
                 &match?(%{"updateDataModel" => %{"path" => "/ui/feedback"}}, &1)
               )

        assert %{"search" => "x"} = :sys.get_state(view.pid).socket.assigns.ash_a2ui_query_state
      end

      test "a malformed message pushes nothing", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/query")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        capture_log(fn ->
          render_hook(view, "a2ui:message", %{"version" => "v1.0", "callAgentFunction" => %{}})
          _ = :sys.get_state(view.pid)
        end)

        refute_push_event(view, "a2ui:messages", %{messages: _messages}, 100)
      end

      test "a PubSub refresh re-runs the client's last query state, not the defaults", %{
        conn: conn
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/query-pubsub")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        envelope =
          Messages.call("query", "paginated", %{"query" => %{"search" => "needle"}, "page" => 1},
            source: "query_apply_button"
          )

        render_hook(view, "a2ui:message", envelope)

        assert_push_event(view, "a2ui:messages", %{
          messages: [_records, _empty_state, _query, _response]
        })

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:paginated",
          %Ash.Notifier.Notification{resource: AshA2ui.Test.Paginated}
        )

        assert_push_event(
          view,
          "a2ui:messages",
          %{messages: [%{"updateDataModel" => %{"path" => "/", "value" => value}}]},
          1_000
        )

        # Without query-state tracking the refresh would rebuild with the
        # declared defaults and push "search" => "".
        assert %{"search" => "needle", "page" => 1} = value["query"]
      end

      test "a PubSub refresh re-runs the client's last context state, not unselected", %{
        conn: conn
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/context-pubsub")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        envelope =
          Messages.call(
            "context_select",
            Fixtures.surface_id(),
            %{"context" => "owner", "value" => "o-1", "contexts" => %{}},
            source: "context_owner_option_button"
          )

        SchemaHelper.assert_valid_renderer_message(envelope)
        render_hook(view, "a2ui:message", envelope)

        # The stub's follow-up rewrites /context; the LiveRenderer must
        # track it and hand it to the next refresh as :context_state.
        assert_push_event(view, "a2ui:messages", %{messages: [_context_update]})

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:appointments",
          %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal}
        )

        assert_receive {:data_model_fn, MinimalUI, opts}, 1_000

        assert opts[:context_state] == %{
                 "owner" => %{"search" => "", "value" => "o-1", "label" => "Ada"}
               }
      end

      test "a PubSub refresh on a multi-table surface rebuilds every table", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/multi-table")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:review",
          %Ash.Notifier.Notification{resource: AshA2ui.Test.ReviewItem}
        )

        assert_push_event(view, "a2ui:messages", %{messages: [message]}, 1_000)
        SchemaHelper.assert_valid_agent_message(message)

        assert %{"updateDataModel" => %{"path" => "/", "value" => value}} = message
        assert %{"new_items" => _, "done_items" => _} = value["records"]
        assert %{"new_items" => %{"page" => 1}} = value["query"]
      end
    end

    describe "deep links and reference links" do
      setup do
        alias AshA2ui.Test.Links.{Note, Participant, Person}

        for resource <- [Participant, Note, Person] do
          resource
          |> Ash.read!(authorize?: false)
          |> Enum.each(&Ash.destroy!(&1, authorize?: false))
        end

        ada = Ash.create!(Person, %{name: "Ada"}, authorize?: false)
        hidden = Ash.create!(Person, %{name: "Hidden", visible: false}, authorize?: false)

        %{ada: ada, hidden: hidden}
      end

      test "URL ctx/q params seed the bootstrap — ctx validated through authorized reads", %{
        conn: conn,
        ada: ada
      } do
        {:ok, _view, _html} =
          live(conn, "/live-renderer/deep-link?ctx[person]=#{ada.id}&q[page]=2")

        assert_receive {:surface_fn, AshA2ui.Test.Links.NotesUI, opts}, 1_000
        assert %{"person" => %{"value" => value, "label" => "Ada"}} = opts[:context_state]
        assert value == ada.id
        assert opts[:query_state] == %{"page" => 2}
        # an :open_surface_url template: link Buttons can navigate
        assert opts[:link_buttons] == true
      end

      test "unreadable deep-linked ids are dropped", %{conn: conn, hidden: hidden} do
        {:ok, _view, _html} = live(conn, "/live-renderer/deep-link?ctx[person]=#{hidden.id}")

        assert_receive {:surface_fn, AshA2ui.Test.Links.NotesUI, opts}, 1_000
        assert opts[:context_state]["person"]["value"] == ""
      end

      test "without URL state the bootstrap opts are unchanged", %{conn: conn} do
        {:ok, _view, _html} = live(conn, "/live-renderer/stubbed")

        assert_receive {:surface_fn, MinimalUI, opts}, 1_000
        refute Keyword.has_key?(opts, :context_state)
        refute Keyword.has_key?(opts, :query_state)
      end

      test "deep_link: a context change push_patches the ctx params", %{conn: conn, ada: ada} do
        {:ok, view, _html} = live(conn, "/live-renderer/deep-link?tab=notes")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        render_hook(
          view,
          "a2ui:message",
          Messages.call("context_select", "notes", %{"context" => "person", "value" => ada.id},
            source: "row_select"
          )
        )

        path = assert_patch(view)
        %URI{path: "/live-renderer/deep-link", query: query} = URI.parse(path)
        params = Query.decode(query)
        assert params["ctx"] == %{"person" => ada.id}
        # other params survive
        assert params["tab"] == "notes"
      end

      test "deep_link: back/forward to other ctx params re-applies them", %{
        conn: conn,
        ada: ada
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/deep-link")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        render_patch(view, "/live-renderer/deep-link?ctx[person]=#{ada.id}")

        assert_receive {:data_model_fn, AshA2ui.Test.Links.NotesUI, opts}, 1_000
        assert opts[:context_state]["person"]["value"] == ada.id
        assert_push_event(view, "a2ui:messages", %{messages: [_data_model]})
      end

      test "a deep-linked mount renders the related tables' rows as the library does",
           %{conn: conn, ada: ada} do
        alias AshA2ui.Test.Links.{Note, Participant}

        kickoff = Ash.create!(Note, %{title: "Kickoff", person_id: ada.id}, authorize?: false)
        Ash.create!(Participant, %{note_id: kickoff.id, person_id: ada.id}, authorize?: false)

        {:ok, view, _html} = live(conn, "/live-renderer/people-deep-link?ctx[person]=#{ada.id}")
        assert_push_event(view, "a2ui:messages", %{messages: messages}, 1_000)
        Enum.each(messages, &SchemaHelper.assert_valid_agent_message/1)

        pushed = Surface.data_model(messages)["records"]

        state = AshA2ui.Info.context_state_for(AshA2ui.Test.Links.PeopleUI, %{"person" => ada.id})

        built =
          AshA2ui.Test.Links.PeopleUI
          |> AshA2ui.Info.build_surface(context_state: state)
          |> Surface.data_model()

        assert pushed == built["records"]
        assert [%{"status" => "Open"}] = pushed["their_notes"]

        assert [%{"_links" => %{"note_title" => %{"surface" => "note"}}}] =
                 pushed["participations"]
      end

      test "a basic-catalog link Button's open_surface action navigates once accepted",
           %{conn: conn, ada: ada} do
        alias AshA2ui.Test.Links.{Note, Participant}

        kickoff = Ash.create!(Note, %{title: "Kickoff", person_id: ada.id}, authorize?: false)
        Ash.create!(Participant, %{note_id: kickoff.id, person_id: ada.id}, authorize?: false)

        {:ok, view, _html} = live(conn, "/live-renderer/people-deep-link")
        assert_push_event(view, "a2ui:messages", %{messages: initial}, 1_000)

        # the real build got link_buttons: true from the URL template
        assert Enum.any?(initial, fn message ->
                 message
                 |> get_in(["createSurface", "components"])
                 |> List.wrap()
                 |> Enum.any?(&(&1["id"] == "table_cell_participations_note_title_value_link"))
               end)

        render_hook(
          view,
          "a2ui:message",
          Messages.call(
            "open_surface",
            "people",
            %{
              "field" => "note_title",
              "surface" => "note",
              "recordId" => kickoff.id
            },
            source: "table_cell_participations_note_title_value_link"
          )
        )

        assert_redirect(view, "/app/r/note/#{kickoff.id}")
      end

      test "an ashAction open_surface call navigates once accepted", %{conn: conn, ada: ada} do
        alias AshA2ui.Test.Links.{Note, Participant}

        kickoff = Ash.create!(Note, %{title: "Kickoff", person_id: ada.id}, authorize?: false)
        Ash.create!(Participant, %{note_id: kickoff.id, person_id: ada.id}, authorize?: false)

        {:ok, view, _html} = live(conn, "/live-renderer/people-deep-link")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        call =
          Messages.call("open_surface", "people", %{
            "field" => "note_title",
            "surface" => "note",
            "recordId" => kickoff.id
          })

        render_hook(view, "a2ui:message", call)

        assert_redirect(view, "/app/r/note/#{kickoff.id}")
      end

      test "a rejected open_surface action pushes its error and stays put", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/people-deep-link")
        assert_push_event(view, "a2ui:messages", %{messages: _initial}, 1_000)

        render_hook(
          view,
          "a2ui:message",
          Messages.call(
            "open_surface",
            "people",
            %{"field" => "note_title", "surface" => "admin", "recordId" => "x"},
            source: "forged"
          )
        )

        assert_push_event(view, "a2ui:messages", %{messages: messages}, 1_000)

        assert Enum.any?(
                 messages,
                 &match?(
                   %{
                     "updateDataModel" => %{
                       "path" => "/ui/feedback",
                       "value" => %{"kind" => "error"}
                     }
                   },
                   &1
                 )
               )

        refute_redirected(view)
      end

      test "a2ui:open_surface navigates to the open_surface_url template", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/deep-link")

        render_hook(view, "a2ui:open_surface", %{"surface" => "person", "recordId" => "a b"})

        assert_redirect(view, "/app/r/person/a%20b")
      end

      test "a2ui:open_surface carries a query map onto the target", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/deep-link")

        render_hook(view, "a2ui:open_surface", %{
          "surface" => "person",
          "recordId" => "p1",
          "query" => %{"ctx" => %{"note" => "n1"}}
        })

        {path, _flash} = assert_redirect(view)

        assert path ==
                 "/app/r/person/p1?" <> Query.encode(%{"ctx" => %{"note" => "n1"}})
      end

      test "an open_surface callback replaces the default navigation", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/open-surface-callback")

        render_hook(view, "a2ui:open_surface", %{"surface" => "person", "recordId" => "p1"})

        assert_receive {:open_surface, %{"surface" => "person", "recordId" => "p1"}}, 1_000
      end

      test "without a URL template or callback the request is acknowledged and ignored", %{
        conn: conn
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        assert render_hook(view, "a2ui:open_surface", %{"surface" => "person"}) =~
                 "ash-a2ui-surface"
      end
    end

    describe "additional surfaces (:surfaces)" do
      setup do
        alias AshA2ui.Test.Links.{Note, Participant, Person}

        for resource <- [Participant, Note, Person] do
          resource
          |> Ash.read!(authorize?: false)
          |> Enum.each(&Ash.destroy!(&1, authorize?: false))
        end

        %{
          ada: Ash.create!(Person, %{name: "Ada"}, authorize?: false),
          grace: Ash.create!(Person, %{name: "Grace"}, authorize?: false)
        }
      end

      test "each surface is built and pushed with its own surfaceId", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/surfaces")

        assert_push_event(
          view,
          "a2ui:messages",
          %{messages: [%{"createSurface" => %{"surfaceId" => "minimal_standalone"}} | _] = main},
          1_000
        )

        assert_push_event(
          view,
          "a2ui:messages",
          %{messages: [%{"createSurface" => %{"surfaceId" => "notes"}} | _] = notes},
          1_000
        )

        SchemaHelper.assert_valid_agent_messages(main ++ notes)
        assert Enum.all?(notes, &(surface_id_of(&1) == "notes"))

        assert_receive {:surface_fn, MinimalUI, main_opts}, 1_000
        assert_receive {:surface_fn, NotesUI, notes_opts}, 1_000

        # The same actor and tenant; the extra surface never draws a header.
        for opts <- [main_opts, notes_opts] do
          assert opts[:actor] == :stub_actor
          assert opts[:tenant] == :stub_tenant
        end

        assert notes_opts[:header] == false
        refute Keyword.has_key?(main_opts, :header)
        # no selection from the context function: built with none
        refute Keyword.has_key?(notes_opts, :context_state)
      end

      test "the context function's selection is validated and used", %{conn: conn, ada: ada} do
        {:ok, _view, _html} = live(conn, "/live-renderer/surfaces?person=#{ada.id}")

        assert_receive {:surface_fn, NotesUI, opts}, 1_000
        assert %{"person" => %{"value" => value, "label" => "Ada"}} = opts[:context_state]
        assert value == ada.id

        # the main surface's URL state is its own: no ctx params, no context
        assert_receive {:surface_fn, MinimalUI, main_opts}, 1_000
        refute Keyword.has_key?(main_opts, :context_state)
      end

      test "an extra surface's action is answered by its UI and leaves the main state alone", %{
        conn: conn,
        ada: ada
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/surfaces")
        await_bootstraps(view)
        before = :sys.get_state(view.pid).socket.assigns

        envelope = context_select("notes", ada.id)
        render_hook(view, "a2ui:message", envelope)

        assert_receive {:action_fn, NotesUI, ^envelope, opts}
        assert opts[:actor] == :stub_actor
        assert opts[:tenant] == :stub_tenant
        refute_receive {:action_fn, MinimalUI, _, _}, 50

        assert_push_event(view, "a2ui:messages", %{
          messages: [%{"updateDataModel" => %{"surfaceId" => "notes", "path" => "/context"}}]
        })

        assigns = :sys.get_state(view.pid).socket.assigns
        assert assigns.ash_a2ui_query_state == before.ash_a2ui_query_state
        assert assigns.ash_a2ui_context_state == before.ash_a2ui_context_state
        assert assigns.ash_a2ui_url_ctx == before.ash_a2ui_url_ctx
        assert assigns.ash_a2ui_surfaces.notes.context_state["person"]["value"] == ada.id
      end

      test "a main-surface action goes to the main UI as before", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/surfaces")
        await_bootstraps(view)
        before = :sys.get_state(view.pid).socket.assigns.ash_a2ui_surfaces

        envelope = Fixtures.action_envelope()
        render_hook(view, "a2ui:message", envelope)

        assert_receive {:action_fn, MinimalUI, ^envelope, _opts}
        refute_receive {:action_fn, NotesUI, _, _}, 50

        assert_push_event(view, "a2ui:messages", %{
          messages: [_, %{"updateDataModel" => %{"path" => "/ui/feedback"}}]
        })

        assert :sys.get_state(view.pid).socket.assigns.ash_a2ui_surfaces == before
      end

      test "a PubSub refresh rebuilds every surface with its own state", %{conn: conn, ada: ada} do
        {:ok, view, _html} = live(conn, "/live-renderer/surfaces")
        await_bootstraps(view)

        render_hook(view, "a2ui:message", context_select("notes", ada.id))
        assert_push_event(view, "a2ui:messages", %{messages: [_context]})

        Phoenix.PubSub.broadcast(
          AshA2ui.Test.PubSub,
          "ash_a2ui_test:surfaces",
          %Ash.Notifier.Notification{resource: AshA2ui.Test.Minimal}
        )

        assert_receive {:data_model_fn, MinimalUI, main_opts}, 1_000
        assert_receive {:data_model_fn, NotesUI, notes_opts}, 1_000
        refute Keyword.has_key?(main_opts, :context_state)
        assert notes_opts[:context_state]["person"]["value"] == ada.id

        assert_push_event(view, "a2ui:messages", %{messages: [main, notes]}, 1_000)
        assert surface_id_of(main) == "minimal_standalone"
        assert surface_id_of(notes) == "notes"
      end

      test "a params change that changes the selection rebuilds the extra surface", %{
        conn: conn,
        ada: ada,
        grace: grace
      } do
        {:ok, view, _html} = live(conn, "/live-renderer/surfaces?person=#{ada.id}")
        await_bootstraps(view)
        assert_receive {:surface_fn, MinimalUI, _opts}, 1_000
        assert_receive {:surface_fn, NotesUI, _opts}, 1_000

        render_patch(view, "/live-renderer/surfaces?person=#{ada.id}&tab=other")
        refute_receive {:surface_fn, _, _}, 100

        render_patch(view, "/live-renderer/surfaces?person=#{grace.id}")
        assert_receive {:surface_fn, NotesUI, opts}, 1_000
        assert opts[:context_state]["person"]["label"] == "Grace"
        refute_received {:surface_fn, MinimalUI, _}

        assert_push_event(
          view,
          "a2ui:messages",
          %{messages: [%{"createSurface" => %{"surfaceId" => "notes"}} | _]},
          1_000
        )
      end

      test "without :surfaces the pushes are exactly the main surface's", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/live-renderer/stubbed")

        assert_push_event(view, "a2ui:messages", payload, 1_000)
        assert payload == %{messages: Fixtures.surface_messages()}
        refute_push_event(view, "a2ui:messages", _, 200)

        assert_receive {:surface_fn, MinimalUI, _opts}
        refute_receive {:surface_fn, _, _}, 50
        assert :sys.get_state(view.pid).socket.assigns.ash_a2ui_surfaces == %{}

        envelope = Fixtures.action_envelope()
        render_hook(view, "a2ui:message", envelope)
        assert_push_event(view, "a2ui:messages", payload)
        assert payload == %{messages: Fixtures.action_ok_messages()}
      end

      test "a :context that is not a 2-arity function is refused" do
        assert_raise ArgumentError, ~r/:context must be a 2-arity function/, fn ->
          AshA2ui.LiveRenderer.build_config(
            ui: MinimalUI,
            surfaces: [notes: [ui: NotesUI, context: fn _socket -> %{} end]]
          )
        end
      end

      defp await_bootstraps(view) do
        assert_push_event(
          view,
          "a2ui:messages",
          %{messages: [%{"createSurface" => %{"surfaceId" => "minimal_standalone"}} | _]},
          1_000
        )

        assert_push_event(
          view,
          "a2ui:messages",
          %{messages: [%{"createSurface" => %{"surfaceId" => "notes"}} | _]},
          1_000
        )
      end

      defp context_select(surface_id, value) do
        Messages.call("context_select", surface_id, %{"context" => "person", "value" => value},
          source: "person_picker"
        )
      end

      defp surface_id_of(message) do
        message |> Map.delete("version") |> Map.values() |> hd() |> Map.fetch!("surfaceId")
      end
    end

    describe "surface_container/1" do
      test "the defaults render the single-surface container unchanged" do
        assert container(%{}) ==
                 ~s(<div id="ash-a2ui-surface" phx-hook="AshA2ui" phx-update="ignore"></div>)
      end

      test "a host's own unrelated id, surface or primary assigns render the defaults" do
        # A host LiveView passing its whole assigns through, with a `@surface`
        # record of its own, must not crash the render or scope the container.
        assert container(%{id: 42, surface: %{id: "host-record"}, primary: "yes"}) ==
                 ~s(<div id="ash-a2ui-surface" phx-hook="AshA2ui" phx-update="ignore"></div>)
      end

      test "a LiveRenderer LiveView renders the default container", %{conn: conn} do
        conn = get(conn, "/live-renderer/stubbed")

        assert html_response(conn, 200) =~
                 ~s(<div id="ash-a2ui-surface" phx-hook="AshA2ui" phx-update="ignore"></div>)
      end

      test "a scoped container names its surface" do
        assert container(%{id: "summary", surface: "order_summary"}) ==
                 ~s(<div id="summary" phx-hook="AshA2ui" phx-update="ignore" data-a2ui-surface="order_summary"></div>)
      end

      test "a primary container carries the flag" do
        assert container(%{id: "orders", surface: "orders", primary: true}) ==
                 ~s(<div id="orders" phx-hook="AshA2ui" phx-update="ignore" data-a2ui-surface="orders" data-a2ui-primary></div>)
      end

      test "the component takes the attrs from HEEx" do
        assigns = %{}

        html =
          rendered_to_string(~H"""
          <AshA2ui.LiveRenderer.surface_container id="summary" surface="order_summary" />
          """)

        assert html =~ ~s(id="summary")
        assert html =~ ~s(data-a2ui-surface="order_summary")
        refute html =~ "data-a2ui-primary"
      end

      defp container(assigns),
        do: rendered_to_string(AshA2ui.LiveRenderer.surface_container(assigns))
    end
  end
end
