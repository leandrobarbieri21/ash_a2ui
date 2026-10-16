# The module name mirrors the spec version (v1.0) and follows the same
# naming convention as AshA2ui.Encoder.V0_9_1.
# credo:disable-for-this-file Credo.Check.Readability.ModuleNames
defmodule AshA2ui.Encoder.V1_0 do
  @moduledoc """
  A2UI v1.0 encoder. The component tree and data-model composition are the
  proven `AshA2ui.Encoder.V0_9_1` shapes (same ids, same bindings, same
  reserved paths for records/form/errors/options/select/query/prompt/
  context/detail); this module upgrades them to the v1.0 wire contract:

    * **Inline `createSurface`** — `encode_surface/3` emits a *single*
      message carrying the full component list and initial data model in the
      `createSurface` payload (v1.0's single-message UI instantiation),
      instead of the v0.9.1 `createSurface` → `updateComponents` →
      `updateDataModel` triple. One paint, no create-then-update flash.
    * **`wantResponse` on every action** — each emitted `action.event`
      carries `"wantResponse": true`, so conforming renderers generate an
      `actionId` per interaction and can hold a per-component pending state
      until the server's `actionResponse` arrives (see
      `AshA2ui.ActionHandler` for the response contract).
    * **`/ui/response`** — the v0.9.1 action-result pair
      (`/ui/action_result`, `/ui/action_result_text`) collapses into one
      structured reserved path that also carries the outcome status and
      message. The initial data model carries
      `"ui" => %{"response" => %{"status" => "", "message" => "",
      "result" => %{}, "resultText" => ""}}`; the `action_result_text`
      component binds `/ui/response/resultText` (component ids are unchanged
      so custom themes/catalogs keep working). The `status_text` component
      binds the typed `/ui/feedback/message` on both wire versions; the
      handler writes `/ui/feedback` alongside every `/ui/response` outcome
      (errors, and successes such as report runs and CSV exports).
    * **No wire metadata on function calls** — v1.0 removed `returnType`
      (and `callableFrom`) from wire-level FunctionCall payloads; `formatDate`
      cells are emitted without them.
    * **Markdown headings** — the v1.0 basic catalog dropped the `h1`–`h5`
      `Text` variants (only `caption`/`body` remain); heading text is
      Markdown-rendered instead. Literal headings become `"## Heading"`,
      data-bound headings go through the catalog's `formatString`
      interpolation (`"#### ${/records/title}"`).
    * **v1.0 envelope + catalog** — every message says `"version": "v1.0"`
      and `createSurface` names the v1.0 basic catalog.
    * **`surfaceProperties`** — pass `opts[:surface_properties]` (e.g.
      `%{"agentDisplayName" => "Support Agent"}`) to brand the surface;
      v1.0 renamed the v0.9 `theme` block and dropped `primaryColor`, so
      styling stays entirely on the CSS-variable seam (see the Theming
      topic — AshA2ui never used `theme.primaryColor`).

  Everything documented on `AshA2ui.Encoder.V0_9_1` about component ids,
  action contexts, and the data-model shape applies verbatim, with the
  `/ui/*` differences above. See `documentation/topics/a2ui-1-0.md` for the
  full v1.0 contract and its UX rationale.
  """

  @behaviour AshA2ui.Encoder

  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.Experience

  @version "v1.0"
  @catalog_id "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"

  @initial_response %{"status" => "", "message" => "", "result" => %{}, "resultText" => ""}

  @doc """
  Encodes the full surface bootstrap as a **single** inline `createSurface`
  message (components + initial data model in one payload).

  Options are `AshA2ui.Encoder.V0_9_1.encode_surface/3`'s, plus:

    * `:surface_properties` — an optional map validating against the
      catalog's `surfaceProperties` schema (`"agentDisplayName"`,
      `"iconUrl"`), included in the `createSurface` payload when given.
  """
  @impl true
  def encode_surface(resolved_view, records, opts) do
    {surface_properties, opts} = Keyword.pop(opts, :surface_properties)

    [_create, components_message, data_model_message] =
      V0_9_1.encode_surface(resolved_view, records, opts)

    components = upgrade_components(components_message["updateComponents"]["components"])
    data_model = upgrade_data_model(data_model_message["updateDataModel"]["value"])

    create =
      %{
        "surfaceId" => resolved_view.surface_id,
        "catalogId" => catalog_id(),
        "components" => components,
        "dataModel" => data_model
      }
      |> put_surface_properties(surface_properties)

    [%{"version" => @version, "createSurface" => create}]
  end

  # The admin catalog (`catalog: :admin_v1`) surfaces declare the admin
  # catalog id on their inline createSurface too.
  defp catalog_id do
    if Experience.admin?(), do: Experience.admin_catalog_id(), else: @catalog_id
  end

  @doc """
  Encodes a data-only refresh: a single v1.0 `updateDataModel` message (same
  `:scope` option as the v0.9.1 encoder).
  """
  @impl true
  def encode_data_model(resolved_view, records, opts) do
    resolved_view
    |> V0_9_1.encode_data_model(records, opts)
    |> upgrade_message()
  end

  @doc """
  Upgrades a v0.9.1-shaped server->client message emitted by the shared
  composition code to the v1.0 wire contract: the `"v1.0"` version string,
  `/ui/action_result`-family paths rewritten to the structured
  `/ui/response` path, and full data-model writes upgraded shape-wise. Used by
  `AshA2ui.ActionHandler` for v1.0 follow-up messages.
  """
  @spec upgrade_message(map) :: map
  def upgrade_message(%{"updateDataModel" => update} = message) do
    update =
      case update do
        %{"path" => "/", "value" => value} -> %{update | "value" => upgrade_data_model(value)}
        _scoped -> update
      end

    %{message | "version" => @version, "updateDataModel" => update}
  end

  def upgrade_message(message), do: Map.put(message, "version", @version)

  # --- components -------------------------------------------------------------

  # The v0.9.1 component list carries three v0.9-isms: wire `returnType` on
  # FunctionCall values (dropped in v1.0), no `wantResponse` on action events
  # (added — every AshA2ui action is server-handled and answered), and the
  # /ui/action_result-family bindings (rewritten to /ui/response subpaths).
  defp upgrade_components(components), do: Enum.map(components, &upgrade_value/1)

  # v1.0's basic catalog dropped the h1–h5 Text variants (only "caption" and
  # "body" remain) — headings are Markdown now ("Text should be rendered
  # using a Markdown parser", basic-catalog implementation guide). Literal
  # heading texts get the "#"-prefix; data-bound headings interpolate the
  # path through the catalog's formatString function; FunctionCall texts
  # (e.g. a date-formatted card title) fall back to body text.
  defp upgrade_value(%{"component" => "Text", "variant" => variant} = text_component)
       when variant in ["h1", "h2", "h3", "h4", "h5"] do
    prefix = String.duplicate("#", String.to_integer(String.at(variant, 1)))

    text_component
    |> Map.delete("variant")
    |> Map.update!("text", &markdown_heading(&1, prefix))
    |> upgrade_value()
  end

  defp upgrade_value(%{"call" => _call} = function_call) do
    function_call
    |> Map.drop(["returnType", "callableFrom"])
    |> Map.new(fn {key, value} -> {key, upgrade_value(value)} end)
  end

  defp upgrade_value(%{"event" => %{"name" => _name} = event} = action) do
    event =
      event
      |> Map.new(fn {key, value} -> {key, upgrade_value(value)} end)
      |> Map.put("wantResponse", true)

    Map.put(action, "event", event)
  end

  defp upgrade_value(%{"path" => path} = binding) when is_binary(path) do
    Map.put(binding, "path", upgrade_path(path))
  end

  defp upgrade_value(%{} = map) do
    Map.new(map, fn {key, value} -> {key, upgrade_value(value)} end)
  end

  defp upgrade_value(list) when is_list(list), do: Enum.map(list, &upgrade_value/1)
  defp upgrade_value(other), do: other

  defp markdown_heading(text, prefix) when is_binary(text), do: prefix <> " " <> text

  defp markdown_heading(%{"path" => path}, prefix) when is_binary(path) do
    %{"call" => "formatString", "args" => %{"value" => prefix <> " ${" <> path <> "}"}}
  end

  defp markdown_heading(other, _prefix), do: other

  defp upgrade_path("/ui/action_result_text"), do: "/ui/response/resultText"
  defp upgrade_path("/ui/action_result"), do: "/ui/response/result"
  defp upgrade_path(path), do: path

  # --- data model -------------------------------------------------------------

  # The full data model's reserved "ui" region: the v0.9.1 action-result
  # pair becomes the single structured response object. Every other "ui"
  # key — the experience layer's intent/panel/feedback state, the wizard —
  # passes through untouched.
  defp upgrade_data_model(%{"ui" => ui} = value) do
    ui =
      ui
      |> Map.drop(["action_result", "action_result_text"])
      |> Map.put("response", @initial_response)

    Map.put(value, "ui", ui)
  end

  defp upgrade_data_model(value), do: value

  defp put_surface_properties(create, nil), do: create

  defp put_surface_properties(create, properties) when is_map(properties),
    do: Map.put(create, "surfaceProperties", properties)

  @doc """
  Builds a v1.0 `callFunction` server->client message invoking client
  function `name` with `args` — the server->client RPC introduced in v1.0.
  Push it alongside other messages (e.g. from a LiveView using the shipped
  hook, which executes it against the host-registered function table;
  `openUrl` is built in).

      AshA2ui.Encoder.V1_0.call_function("openUrl", %{"url" => "https://…"})

  Options: `:want_response` (default `false`) asks the client to send a
  `functionResponse` back (the shipped hook pushes it as the
  `"a2ui:function_response"` LiveView event); `:function_call_id` overrides
  the generated unique call id.

  Use sparingly: a function call is imperative and invisible to the data
  model. Anything expressible as data (status, errors, selection) belongs
  in `updateDataModel` — see the A2UI 1.0 topic for the rationale. Also
  note that a message is only spec-valid when the active catalog declares
  the function (the v1.0 basic catalog declares `openUrl`, `formatDate`,
  `formatString`, …); host-registered custom functions need a catalog that
  declares them.
  """
  @spec call_function(String.t(), map, keyword) :: map
  def call_function(name, args \\ %{}, opts \\ []) when is_binary(name) and is_map(args) do
    call = if args == %{}, do: %{"call" => name}, else: %{"call" => name, "args" => args}

    message = %{
      "version" => @version,
      "functionCallId" => Keyword.get_lazy(opts, :function_call_id, &generate_call_id/0),
      "callFunction" => call
    }

    if Keyword.get(opts, :want_response, false) do
      Map.put(message, "wantResponse", true)
    else
      message
    end
  end

  defp generate_call_id do
    "fc_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  @doc false
  # The initial /ui/response value shape (shared with ActionHandler).
  def initial_response, do: @initial_response

  @doc false
  def version, do: @version
end
