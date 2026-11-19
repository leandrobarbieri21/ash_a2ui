defmodule AshA2ui.RecordPageTest do
  @moduledoc """
  Admin catalog 3.5: a record page the surface draws whole. The entityPage
  carries the declared page header (read from the context's record, its
  buttons gated by `visible` and `Ash.can?/3`), the lead components and
  their gates, and the section nav; a `:detail` may be drawn as an
  `alertBanner`; the host page's values ride at `/page`; and a header
  button that runs an action goes through the `page_action` ashAction.
  """

  # Not async: capture_io(:stderr) captures a global device, and the catalog
  # is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Ets
  alias AshA2ui.ActionHandler
  alias AshA2ui.Gettext.Metadata
  alias AshA2ui.Test.{Dossier, DossierPageUI, Messages, SchemaHelper}

  @manager %{id: "m1", role: :manager}
  @clerk %{id: "c1", role: :clerk}

  setup do
    on_exit(fn ->
      Application.put_env(:ash_a2ui, :catalog, :basic)
      Ets.stop(Dossier)
    end)

    dossier =
      Ash.create!(
        Dossier,
        %{name: "Harbour lease", owner: "Ana", file_url: "/files/7", notes: "Renewed once"},
        authorize?: false
      )

    %{dossier: dossier}
  end

  defp selection(dossier),
    do: %{"dossier" => %{"search" => "", "value" => dossier.id, "label" => dossier.name}}

  defp surface(catalog, dossier, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(
        DossierPageUI,
        [actor: Keyword.get(opts, :actor, @manager), context_state: selection(dossier)] ++
          Keyword.take(opts, [:page, :as_of])
      )

    catalogs = if catalog == :admin_v1, do: SchemaHelper.admin_catalogs()
    SchemaHelper.assert_valid_agent_message(message, catalogs: catalogs)

    {Map.new(surface["components"], &{&1["id"], &1}), surface["dataModel"]}
  end

  defp page_action(dossier, name, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    context = %{
      "action" => name,
      "recordId" => Keyword.get(opts, :record_id, dossier.id),
      "contexts" => %{"dossier" => %{"value" => dossier.id, "label" => dossier.name}}
    }

    ActionHandler.handle(
      DossierPageUI,
      Messages.call("page_action", "dossier_page", context),
      [actor: Keyword.get(opts, :actor, @manager)] ++ Keyword.take(opts, [:as_of])
    )
  end

  defp state(dossier), do: Ash.get!(Dossier, dossier.id, authorize?: false).state

  describe "the page header" do
    test "rides on the entityPage, every value named by the field it reads", %{dossier: dossier} do
      {components, _model} = surface(:admin_v1, dossier)

      assert components["root"]["header"] == %{
               "context" => "dossier",
               "path" => "/detail/dossier",
               "title" => "name",
               "breadcrumbLabel" => "Breadcrumb",
               "breadcrumb" => [
                 %{"label" => "Dossiers", "href" => "/dossiers", "pagePath" => "/page/back"}
               ],
               "tags" => [
                 %{"field" => "state_text", "tone" => "state_tone", "helpField" => "state_help"}
               ],
               "meta" => [%{"field" => "owner", "icon" => "user", "help" => "Who looks after it"}],
               "actions" => [
                 %{
                   "name" => "open_file",
                   "label" => "Open file",
                   "variant" => "secondary",
                   "href" => "file_url",
                   "title" => "Opens the file"
                 },
                 %{
                   "name" => "close",
                   "label" => "Close",
                   "variant" => "primary",
                   "visible" => "_header_action_close",
                   "action" => %{
                     "label" => "Close",
                     "action" => "page_action",
                     "context" => %{
                       "action" => "close",
                       "recordId" => %{"@path" => "/detail/dossier/id"},
                       "contexts" => %{"@path" => "/context"}
                     }
                   }
                 }
               ]
             }
    end

    test "its record carries what it reads, and whether each action is offered",
         %{dossier: dossier} do
      {_components, model} = surface(:admin_v1, dossier)
      record = model["detail"]["dossier"]

      assert record["name"] == "Harbour lease"
      assert record["state_text"] == "Open"
      assert record["state_tone"] == "info"
      assert record["state_help"] == "Still being worked on"
      assert record["file_url"] == "/files/7"
      assert record["_header_action_close"] == true
      # A link has no computed gate: its address is its gate.
      refute Map.has_key?(record, "_header_action_open_file")
    end

    test "an action shows only to a person allowed to run it, and only while visible holds",
         %{dossier: dossier} do
      {_components, model} = surface(:admin_v1, dossier, actor: @clerk)
      assert model["detail"]["dossier"]["_header_action_close"] == false

      closed = Ash.update!(dossier, %{state: :closed}, authorize?: false)
      {_components, model} = surface(:admin_v1, closed)
      assert model["detail"]["dossier"]["_header_action_close"] == false
    end

    test "the host page's values ride at /page, as text", %{dossier: dossier} do
      {_components, model} = surface(:admin_v1, dossier, page: %{back: "/dossiers?q=lease", n: 2})
      assert model["page"] == %{"back" => "/dossiers?q=lease", "n" => "2"}

      {_components, model} = surface(:admin_v1, dossier)
      assert model["page"] == %{}
    end

    test "a surface pinned to an earlier moment offers no action", %{dossier: dossier} do
      {components, model} = surface(:admin_v1, dossier, as_of: DateTime.utc_now())

      assert Enum.map(components["root"]["header"]["actions"], & &1["name"]) == ["open_file"]
      refute Map.has_key?(model["detail"]["dossier"], "_header_action_close")
    end

    test "the basic catalog keeps its plain heading", %{dossier: dossier} do
      {components, _model} = surface(:basic, dossier)
      refute Enum.any?(Map.values(components), &Map.has_key?(&1, "header"))
    end
  end

  describe "lead components and the section nav" do
    test "lead components sit under the header, out of the children, gated by their field",
         %{dossier: dossier} do
      {components, model} = surface(:admin_v1, dossier)
      root = components["root"]

      assert root["lead"] == ["detail_closed", "detail_summary"]

      assert root["leadVisible"] == %{
               "detail_closed" => "/detail/dossier/closed?",
               "detail_summary" => "/detail/dossier/has_summary?"
             }

      refute "detail_closed" in root["children"]
      refute "detail_summary" in root["children"]
      assert "section_facts" in root["children"]

      record = model["detail"]["dossier"]
      assert record["closed?"] == false
      assert record["has_summary?"] == false
    end

    test "a detail drawn as an alert is an alertBanner bound to its record",
         %{dossier: dossier} do
      {components, _model} = surface(:admin_v1, dossier)

      assert components["detail_closed"] == %{
               "id" => "detail_closed",
               "component" => "alertBanner",
               "variant" => "neutral",
               "layout" => "inline",
               "title" => "This dossier is closed",
               "message" => %{"@path" => "/detail/dossier/closed_note"}
             }

      closed = Ash.update!(dossier, %{state: :closed}, authorize?: false)
      {_components, model} = surface(:admin_v1, closed)
      assert model["detail"]["dossier"]["closed_note"] == "Nothing more is done on it."
      assert model["detail"]["dossier"]["closed?"] == true
    end

    test "an alert infers no field rows: its record reads only what the alert names",
         %{dossier: dossier} do
      {components, _model} = surface(:admin_v1, dossier)

      refute Enum.any?(Map.keys(components), &String.starts_with?(&1, "detail_closed_field_"))
      assert [] == Enum.find(AshA2ui.Info.components(DossierPageUI), &(&1.as == :closed)).fields
    end

    test "the basic catalog draws an alert as a card with its title and message",
         %{dossier: dossier} do
      {components, _model} = surface(:basic, dossier)

      assert components["detail_closed"]["component"] == "Card"
      assert components["detail_closed_title"]["text"] =~ "This dossier is closed"

      assert components["detail_closed_message"]["text"] == %{
               "@path" => "/detail/dossier/closed_note"
             }
    end

    test "the nav names each section's wrapper and anchor", %{dossier: dossier} do
      {components, _model} = surface(:admin_v1, dossier)

      assert components["root"]["nav"] == %{
               "label" => "Sections",
               "id" => "dossier-sections",
               "items" => [
                 %{
                   "label" => "Facts",
                   "anchor" => "facts",
                   "target" => "section_facts",
                   "id" => "facts-link"
                 },
                 %{"label" => "Notes", "anchor" => "notes", "target" => "section_notes"}
               ]
             }

      assert components["section_facts"]["component"] == "Column"
      assert components["section_notes"]["component"] == "Column"
    end
  end

  describe "page_action" do
    test "runs the header's action as the person, and sends the record again",
         %{dossier: dossier} do
      assert {:ok, messages} = page_action(dossier, "close")
      assert state(dossier) == :closed

      record =
        Enum.find_value(messages, fn
          %{"updateDataModel" => %{"path" => "/detail/dossier", "value" => value}} -> value
          _other -> nil
        end)

      assert record["state_text"] == "Closed"
      assert record["closed?"] == true
      assert record["_header_action_close"] == false
      # Every detail of the context is sent again, the header's fields with them.
      assert record["notes"] == "Renewed once"
      assert Messages.response(messages)["value"]["kind"] == "success"
    end

    test "is refused to a person not allowed to run it, and changes nothing",
         %{dossier: dossier} do
      assert {:error, messages} = page_action(dossier, "close", actor: @clerk)
      assert Messages.response(messages)["error"]
      assert state(dossier) == :open
    end

    test "is refused while the button's visible field is false", %{dossier: dossier} do
      closed = Ash.update!(dossier, %{state: :closed}, authorize?: false)
      assert {:error, _messages} = page_action(closed, "close")
    end

    test "only a button the header declares that runs an action", %{dossier: dossier} do
      assert {:error, _messages} = page_action(dossier, "open_file")
      assert {:error, _messages} = page_action(dossier, "destroy")
      assert {:error, _messages} = page_action(dossier, "close", record_id: "")
      assert {:error, _messages} = page_action(dossier, "close", record_id: Ash.UUID.generate())
      assert state(dossier) == :open
    end

    test "a surface pinned to an earlier moment refuses it", %{dossier: dossier} do
      assert {:error, _messages} = page_action(dossier, "close", as_of: DateTime.utc_now())
      assert state(dossier) == :open
    end
  end

  test "the metadata template collects the header's, the nav's and the alert's words" do
    keys = Metadata.surface_messages(DossierPageUI) |> Enum.map(&elem(&1, 1))

    for text <- [
          "Dossiers",
          "Breadcrumb",
          "Who looks after it",
          "Open file",
          "Opens the file",
          "Close",
          "Sections",
          "Facts",
          "Notes",
          "This dossier is closed"
        ] do
      assert text in keys, "#{text} is not collected"
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
                for_resource AshA2ui.Test.Dossier

                context :dossier do
                  resource AshA2ui.Test.Dossier
                  picker false
                end

                component :detail, :facts do
                  section "Facts"
                  context :dossier
                  fields [:name]
                end

                unquote(body)
              end
            end
          end
        )
      end)
    end

    test "a header field that is not a field of the context's record" do
      body =
        quote do
          page_header do
            context :dossier
            title :nope
          end
        end

      assert compile("UnknownTitle", body) =~ ~r/:nope is not a public attribute/
    end

    test "a header action needs one of run and href" do
      body =
        quote do
          page_header do
            context :dossier
            title :name
            header_action(:both, run: :close, href: :file_url)
            header_action(:neither, label: "Neither")
          end
        end

      assert compile("BothAndNeither", body) =~ ~r/declares both `run` and `href`/
    end

    test "a header action that runs something other than an update action" do
      body =
        quote do
          page_header do
            context :dossier
            title :name
            header_action(:remove, run: :destroy)
          end
        end

      assert compile("NotUpdate", body) =~ ~r/:destroy is not an update action/
    end

    test "a nav entry must start a section" do
      body =
        quote do
          section_nav do
            nav_item(:elsewhere, label: "Elsewhere", anchor: "elsewhere")
          end
        end

      assert compile("NotASection", body) =~ ~r/does not name the first component of a section/
    end

    test "a lead component takes no section" do
      body =
        quote do
          component :detail, :leading do
            section "Facts"
            context :dossier
            lead(true)
            fields [:name]
          end
        end

      assert compile("LeadInSection", body) =~ ~r/takes no `section`/
    end

    test "visible gates lead components only" do
      body =
        quote do
          component :detail, :gated do
            context :dossier
            visible(:open?)
            fields [:name]
          end
        end

      assert compile("VisibleNotLead", body) =~ ~r/gates lead components only/
    end
  end
end
