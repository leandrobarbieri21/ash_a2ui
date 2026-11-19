defmodule AshA2ui.DocumentPaneTest do
  @moduledoc """
  Admin catalog 3.4 document panes: the source document of a context's
  record, drawn beside the surface's sections, its regions the boxes of the
  detail fields' review citations (and any the host adds), its own
  show/hide state, and the actions the renderer sends for it.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.DocumentPane
  alias AshA2ui.Review
  alias AshA2ui.Test.{Appointment, Clinic, Messages, Owner, SchemaHelper, VisitDocumentUI}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      for resource <- [Appointment, Clinic, Owner], do: Ets.stop(resource)
    end)

    owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
    clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

    visit =
      Ash.create!(
        Appointment,
        %{title: "Checkup", status: :scheduled, owner_id: owner.id, clinic_id: clinic.id},
        authorize?: false
      )

    %{visit: visit, owner: owner, clinic: clinic}
  end

  defp surface(catalog, visit, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(
        VisitDocumentUI,
        [
          authorize?: false,
          context_state: %{
            "appointment" => %{"search" => "", "value" => visit.id, "label" => "x"}
          }
        ] ++ opts
      )

    catalogs = if catalog == :admin_v1, do: SchemaHelper.admin_catalogs()
    SchemaHelper.assert_valid_agent_message(message, catalogs: catalogs)

    {Map.new(surface["components"], &{&1["id"], &1}), surface["dataModel"]}
  end

  describe "the wire" do
    test "the pane holds the surface's sections beside its viewer", %{visit: visit} do
      {components, _data} = surface(:admin_v1, visit)

      root = components["root"]
      assert "document_pane_referral" in root["children"]

      pane = components["document_pane_referral"]
      assert pane["component"] == "documentPane"
      assert pane["pane"] == "referral"
      assert pane["label"] == "Show referral"
      assert pane["description"] == "Read-only"
      assert pane["document"] == %{"@path" => "/detail/appointment/_document_referral"}
      assert pane["shown"] == %{"@path" => "/ui/documents/referral/shown"}
      assert pane["selected"] == %{"@path" => "/ui/documents/referral/selected"}
      assert pane["regionHref"] == "#document="
      assert pane["viewer"] == "document_viewer_referral"

      assert pane["toggleAction"] == %{
               "name" => "document_pane",
               "context" => %{"pane" => "referral"}
             }

      # the sections moved inside the pane, out of the page
      assert [section] = pane["children"]
      refute section in root["children"]
      assert components[section]

      viewer = components["document_viewer_referral"]
      assert viewer["component"] == "documentViewer"
      assert viewer["src"] == %{"@path" => "/detail/appointment/_document_referral/src"}
      assert viewer["regions"] == %{"@path" => "/detail/appointment/_document_referral/regions"}

      assert viewer["regionAction"] == %{
               "name" => "document_region",
               "context" => %{"pane" => "referral"}
             }

      assert viewer["strings"]["pageOf"] == "%{page} of %{count}"
      assert viewer["strings"]["pending"] == "Not reviewed"
    end

    test "the record carries its document and its regions", %{visit: visit} do
      {_components, data} = surface(:admin_v1, visit)
      detail = data["detail"]["appointment"]

      assert %{"src" => src, "fileName" => "referral.pdf", "regions" => regions} =
               detail["_document_referral"]

      assert src == "/referrals/#{visit.id}/file"

      assert regions == [
               %{
                 "id" => "title",
                 "page" => 1,
                 "x" => 0.1,
                 "y" => 0.2,
                 "width" => 0.3,
                 "height" => 0.025,
                 "state" => "pending",
                 "label" => "Title"
               },
               %{
                 "id" => "status",
                 "page" => 2,
                 "x" => 0.5,
                 "y" => 0.4,
                 "width" => 0.25,
                 "height" => 0.02,
                 "state" => "pending",
                 "label" => "Status"
               },
               %{
                 "id" => "stamp",
                 "page" => 2,
                 "x" => 0.7,
                 "y" => 0.85,
                 "width" => 0.2,
                 "height" => 0.08,
                 "state" => "empty"
               }
             ]

      # a cited review's page tag opens the pane at its region
      assert detail["_review_title"]["href"] == "#document=title"
      assert detail["_review_status"]["href"] == "#document=status"
      assert [%{"page" => 1}] = detail["_review_title"]["boxes"]

      assert data["ui"]["documents"] == %{"referral" => %{"shown" => false, "selected" => nil}}
    end

    test "the address's state opens the pane", %{visit: visit} do
      {_components, data} = surface(:admin_v1, visit, document_state: %{"referral" => true})

      assert data["ui"]["documents"]["referral"]["shown"] == true
    end

    test "a record with no document has none: no switch", %{visit: visit} do
      walk_in = Ash.update!(visit, %{title: "Walk-in"}, authorize?: false)
      {_components, data} = surface(:admin_v1, walk_in)

      assert data["detail"]["appointment"]["_document_referral"] == nil
    end

    test "the basic catalog leaves the pane out", %{visit: visit} do
      {components, _data} = surface(:basic, visit)

      refute Enum.any?(
               Map.values(components),
               &(&1["component"] in ["documentPane", "documentViewer"])
             )
    end

    test "a refresh of the record refreshes the regions' states", %{visit: visit} do
      visit = Ash.update!(visit, %{status: :completed}, authorize?: false)

      {:ok, messages} =
        ActionHandler.handle(
          VisitDocumentUI,
          Messages.call("context_select", "visit_document", %{
            "context" => "appointment",
            "value" => visit.id
          }),
          authorize?: false
        )

      detail =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/detail/appointment", "value" => value}} -> value
          _other -> nil
        end)

      states = Map.new(detail["_document_referral"]["regions"], &{&1["id"], &1["state"]})
      assert states == %{"title" => "pending", "status" => "reviewed", "stamp" => "empty"}
    end
  end

  describe "the actions" do
    defp handle(name, context) do
      ActionHandler.handle(VisitDocumentUI, Messages.call(name, "visit_document", context))
    end

    defp writes(messages) do
      for %{"updateDataModel" => %{"path" => path, "value" => value}} <- messages,
          path != "/ui/feedback",
          do: {path, value}
    end

    test "document_pane writes the pane shown or hidden, quietly" do
      assert {:ok, messages} = handle("document_pane", %{"pane" => "referral", "shown" => true})
      assert writes(messages) == [{"/ui/documents/referral/shown", true}]
      refute Enum.any?(messages, &match?(%{"updateDataModel" => %{"path" => "/ui/feedback"}}, &1))
      assert %{"value" => %{}} = Messages.response(messages)

      assert {:ok, messages} = handle("document_pane", %{"pane" => "referral", "shown" => false})
      assert writes(messages) == [{"/ui/documents/referral/shown", false}]
    end

    test "document_region writes the region a person went to" do
      assert {:ok, messages} =
               handle("document_region", %{"pane" => "referral", "regionId" => "title"})

      assert writes(messages) == [{"/ui/documents/referral/selected", "title"}]
    end

    test "a pane the surface does not declare, or a malformed context, is refused" do
      assert {:error, _messages} = handle("document_pane", %{"pane" => "nope", "shown" => true})

      assert {:error, _messages} =
               handle("document_pane", %{"pane" => "referral", "shown" => "yes"})

      assert {:error, _messages} = handle("document_region", %{"pane" => "referral"})
      assert {:error, _messages} = handle("document_region", %{"pane" => 3, "regionId" => "x"})
    end

    test "both are quiet" do
      assert "document_pane" in ActionHandler.quiet_actions()
      assert "document_region" in ActionHandler.quiet_actions()
    end
  end

  describe "AshA2ui.DocumentPane" do
    test "the address: ?<url_param>=shown holds the pane open, anything else is closed" do
      [pane] = DocumentPane.panes(VisitDocumentUI)

      assert DocumentPane.url_param(pane) == "document"
      assert DocumentPane.shown?(pane, %{"document" => "shown"})

      for value <- ["true", "1", "SHOWN", ""],
          do: refute(DocumentPane.shown?(pane, %{"document" => value}))

      assert DocumentPane.url_state(VisitDocumentUI, %{"document" => "shown", "tab" => "x"}) ==
               %{"referral" => true}

      assert DocumentPane.url_state(VisitDocumentUI, %{}) == %{}

      assert DocumentPane.put_param(%{"tab" => "x"}, pane, true) ==
               %{"tab" => "x", "document" => "shown"}

      assert DocumentPane.put_param(%{"tab" => "x", "document" => "shown"}, pane, false) ==
               %{"tab" => "x"}
    end

    test "a pane's url_param defaults to its name" do
      assert DocumentPane.url_param(%DocumentPane{name: :policy}) == "policy"
    end

    test "a region link encodes its id" do
      [pane] = DocumentPane.panes(VisitDocumentUI)
      assert DocumentPane.region_href(pane, "line 1.price") == "#document=line+1.price"
    end

    test "a source needs a url (or href); the name is optional" do
      assert DocumentPane.source(%{url: "/a.pdf", name: "a.pdf"}) ==
               %{"src" => "/a.pdf", "fileName" => "a.pdf"}

      assert DocumentPane.source(%{"href" => "/a.pdf"}) == %{"src" => "/a.pdf", "fileName" => ""}
      assert DocumentPane.source(%{name: "a.pdf"}) == nil
      assert DocumentPane.source(nil) == nil
      assert DocumentPane.source("/a.pdf") == nil
    end

    test "a region needs an id, a box and a known state; pending by default" do
      box = %{page: 1, x: 0.1, y: 0.1, width: 0.2, height: 0.1}

      assert %{"id" => "sig", "state" => "pending"} = DocumentPane.region(Map.put(box, :id, :sig))

      assert %{"state" => "reviewed-selected", "label" => "Sign here"} =
               DocumentPane.region(
                 Map.merge(box, %{id: "sig", state: :reviewed_selected, label: "Sign here"})
               )

      for state <- DocumentPane.states() do
        assert %{"state" => ^state} =
                 DocumentPane.region(Map.merge(box, %{id: "x", state: state}))
      end

      assert DocumentPane.region(Map.merge(box, %{id: "x", state: :lost})) == nil
      assert DocumentPane.region(box) == nil
      assert DocumentPane.region(Map.merge(box, %{id: "x", page: 0})) == nil
      assert DocumentPane.region(Map.merge(box, %{id: "x", x: 0.9})) == nil
    end

    test "the region states" do
      assert DocumentPane.states() ==
               ~w(pending reviewed selected reviewed-selected linked empty)
    end

    test "the words are library strings" do
      pot = File.read!("priv/gettext/ash_a2ui.pot")

      for words <- Map.values(DocumentPane.strings(nil)) ++ ["Show document"],
          do: assert(pot =~ ~s(msgid "#{words}"), "#{words} is not in the shipped catalog")
    end
  end

  describe "a review's boxes" do
    test "are fractions of a positive page, not past its edge" do
      review =
        Review.normalize(%{
          state: :pending,
          boxes: [
            %{page: 2, x: 0, y: 0.5, width: 1, height: 0.5},
            %{
              "page" => "3",
              "x" => Decimal.new("0.25"),
              "y" => 0.1,
              "width" => 0.5,
              "height" => 0.1
            },
            %{page: 1, x: 0.8, y: 0.1, width: 0.3, height: 0.1},
            %{page: 1, x: 0.1, y: 0.1, width: 0, height: 0.1},
            %{page: -1, x: 0.1, y: 0.1, width: 0.1, height: 0.1},
            "box"
          ]
        })

      assert review["boxes"] == [
               %{"page" => 2, "x" => 0.0, "y" => 0.5, "width" => 1.0, "height" => 0.5},
               %{"page" => 3, "x" => 0.25, "y" => 0.1, "width" => 0.5, "height" => 0.1}
             ]
    end

    test "none that can be placed is no boxes" do
      refute Map.has_key?(Review.normalize(%{state: :pending, boxes: [%{page: 1}]}), "boxes")
      refute Map.has_key?(Review.normalize(%{state: :pending, boxes: "p. 1"}), "boxes")
    end
  end

  describe "compile-time checks" do
    defp compile(name, body) do
      capture_io(:stderr, fn ->
        Code.eval_quoted(
          quote do
            defmodule unquote(Module.concat(__MODULE__, name)) do
              @moduledoc false
              use AshA2ui.Standalone

              a2ui do
                for_resource AshA2ui.Test.Appointment

                context :appointment do
                  resource AshA2ui.Test.Appointment
                  picker false
                end

                unquote(body)
              end
            end
          end
        )
      end)
    end

    test "a pane bound to no detail card" do
      assert compile(
               "PaneNoDetail",
               quote do
                 document_pane :doc do
                   context :appointment
                   source :referral_document
                 end
               end
             ) =~ ~r/no :detail component renders context :appointment/
    end

    test "a source that is not a field of the context's resource" do
      assert compile(
               "PaneBadSource",
               quote do
                 component :detail, :card do
                   context :appointment
                   fields [:title]
                 end

                 document_pane :doc do
                   context :appointment
                   source :nope
                 end
               end
             ) =~ ~r/source names :nope, which is not a public attribute/
    end

    test "two panes on one surface" do
      assert compile(
               "PaneTwice",
               quote do
                 component :detail, :card do
                   context :appointment
                   fields [:title]
                 end

                 document_pane :one do
                   context :appointment
                   source :referral_document
                 end

                 document_pane :two do
                   context :appointment
                   source :referral_document
                 end
               end
             ) =~ ~r/at most one document pane/
    end

    test "an undeclared context" do
      assert compile(
               "PaneNoContext",
               quote do
                 component :detail, :card do
                   context :appointment
                   fields [:title]
                 end

                 document_pane :doc do
                   context :nope
                   source :referral_document
                 end
               end
             ) =~ ~r/context :nope is not a declared context/
    end
  end
end
