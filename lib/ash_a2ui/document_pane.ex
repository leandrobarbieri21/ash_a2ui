defmodule AshA2ui.DocumentPane do
  @moduledoc """
  Document panes: the document a context's record was read from, drawn
  beside the surface's sections with each value boxed on its page (the
  `document_pane` DSL entity, admin catalog 3.4).

      a2ui do
        context :contract do
          resource MyApp.Contract
        end

        component :detail, :details do
          context :contract
          fields [:name, :payment_term]
        end

        document_pane :document do
          context :contract
          source :page_document
        end

        field :payment_term, do: review(:payment_term_review)
      end

  The pane is bound to the `:detail` cards of its `context`. Each field of
  those cards with a `review` whose citation has `boxes` (see
  `AshA2ui.Review`) is a region of the pane: its boxes, in its review state,
  named by its label, with the field's name as the region id. The field's
  page tag links to it (`region_href/2`), so a person clicking it sees the
  pane open there. The optional `regions` source adds regions no field
  cites.

  ## Data model

  The pane's document travels with its context's record, so every path that
  re-sends the record (a context change, a field action) re-sends the pane
  too. The record carries it at `_document_<name>`:

      %{
        "src" => "/contracts/9/file",      # the address the browser fetches
        "fileName" => "contract.pdf",
        "regions" => [
          %{"id" => "payment_term", "page" => 1, "x" => 0.08, "y" => 0.92,
            "width" => 0.07, "height" => 0.015, "state" => "pending",
            "label" => "Payment term"}
        ]
      }

  or `nil` when the record has no document (the switch is not drawn). The
  pane's own state is at `/ui/documents/<name>`: `%{"shown" => boolean,
  "selected" => region id | nil}`. The renderer writes both as a person
  uses the pane and sends them with the `document_pane` and
  `document_region` actions (`AshA2ui.ActionHandler`), so a host sees them
  like any other action. `AshA2ui.LiveRenderer` keeps `shown` in the
  address: `?<url_param>=shown` while open, no parameter while closed (the
  default).

  ## Region states

  `pending` (read automatically, nobody has checked it), `reviewed` (a
  person checked it), `selected` and `reviewed-selected` (the one a person
  went to, the renderer's), `linked` (the region of the field a person is
  on) and `empty` (looked for and not found, with a place in the
  document). A review field's region takes `pending` or `reviewed` from its
  review state (`missing` is `empty`).
  """

  import AshA2ui.Gettext, only: [msg: 1]

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.L10n
  alias AshA2ui.Label
  alias Spark.Dsl.Extension

  defstruct [
    :name,
    :context,
    :source,
    :regions,
    :label,
    :description,
    :url_param,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          context: atom,
          source: atom,
          regions: atom | nil,
          label: String.t() | nil,
          description: String.t() | nil,
          url_param: String.t() | nil
        }

  @typedoc "One region on the wire."
  @type region :: %{String.t() => String.t() | number}

  @states ~w(pending reviewed selected reviewed-selected linked empty)

  # The value the address carries while a pane is open.
  @shown "shown"

  @doc "The region states."
  @spec states() :: [String.t()]
  def states, do: @states

  @doc "The `document_pane` entities of `resource_or_ui_module`, in order."
  @spec panes(module | Spark.Dsl.t()) :: [t()]
  def panes(resource_or_ui_module) do
    if spark_module?(resource_or_ui_module) do
      resource_or_ui_module
      |> Extension.get_entities([:a2ui])
      |> Enum.filter(&is_struct(&1, __MODULE__))
    else
      []
    end
  end

  # A `LiveRenderer` whose `:ui` is no Spark module (a static page) has no
  # panes.
  defp spark_module?(dsl) when is_map(dsl), do: true

  defp spark_module?(module) do
    is_atom(module) and not is_nil(module) and Code.ensure_loaded?(module) and
      function_exported?(module, :spark_dsl_config, 0)
  end

  @doc "The key of the pane's document in its context's record: `_document_<name>`."
  @spec data_key(t() | atom) :: String.t()
  def data_key(%__MODULE__{name: name}), do: data_key(name)
  def data_key(name) when is_atom(name), do: "_document_#{name}"

  @doc "The data-model path of the pane's own state: `/ui/documents/<name>`."
  @spec ui_path(t() | atom) :: String.t()
  def ui_path(%__MODULE__{name: name}), do: ui_path(name)
  def ui_path(name) when is_atom(name), do: "/ui/documents/#{name}"

  @doc "The address parameter that holds the pane open: `url_param`, else its name."
  @spec url_param(t()) :: String.t()
  def url_param(%__MODULE__{url_param: param}) when is_binary(param) and param != "", do: param
  def url_param(%__MODULE__{name: name}), do: Atom.to_string(name)

  @doc """
  The page-tag address of a region of `pane`: `#<url_param>=<region id>`.
  The renderer opens the pane at that region when a person follows it.
  """
  @spec region_href(t(), String.t() | atom) :: String.t()
  def region_href(pane, id),
    do: "#" <> url_param(pane) <> "=" <> URI.encode_www_form(to_string(id))

  @doc """
  Whether the address `params` hold `pane` open (`?<url_param>=shown`).
  Any other value is the default, closed.
  """
  @spec shown?(t(), map) :: boolean
  def shown?(pane, params) when is_map(params), do: Map.get(params, url_param(pane)) == @shown
  def shown?(_pane, _params), do: false

  @doc """
  The pane state of `resource_or_ui_module` the address `params` ask for:
  `%{"<name>" => true}` for each pane they hold open. Pass it to
  `AshA2ui.Info.build_surface/2` as `:document_state`.
  """
  @spec url_state(module, map) :: %{String.t() => boolean}
  def url_state(resource_or_ui_module, params) do
    for pane <- panes(resource_or_ui_module), shown?(pane, params), into: %{} do
      {Atom.to_string(pane.name), true}
    end
  end

  @doc """
  The address parameters of `params` with `pane` open or closed: open adds
  `<url_param>=shown`, closed removes the parameter (closed is the
  default, so it leaves nothing behind).
  """
  @spec put_param(map, t(), boolean) :: map
  def put_param(params, pane, true), do: Map.put(params, url_param(pane), @shown)
  def put_param(params, pane, false), do: Map.delete(params, url_param(pane))

  @doc "The switch's label: `label`, else \"Show document\", translated."
  @spec label(t(), L10n.t()) :: String.t()
  def label(%__MODULE__{label: label}, l10n) when is_binary(label) and label != "",
    do: Label.translate(l10n, label)

  def label(_pane, l10n), do: L10n.t(l10n, msg("Show document"))

  @doc "The words beside the switch, translated, or `nil`."
  @spec description(t(), L10n.t()) :: String.t() | nil
  def description(%__MODULE__{description: text}, l10n) when is_binary(text) and text != "",
    do: Label.translate(l10n, text)

  def description(_pane, _l10n), do: nil

  @doc """
  The viewer's own words, translated with `l10n`. `pageOf` and `pageLabel`
  keep their `%{page}` and `%{count}` placeholders for the renderer.
  """
  @spec strings(L10n.t()) :: %{String.t() => String.t()}
  def strings(l10n) do
    keep = [page: "%{page}", count: "%{count}"]

    %{
      "loading" => L10n.t(l10n, msg("Opening the document")),
      "failed" => L10n.t(l10n, msg("This document can't be shown here.")),
      "pageOf" => L10n.t(l10n, msg("%{page} of %{count}"), keep),
      "pageLabel" => L10n.t(l10n, msg("Page %{page} of %{count}"), keep),
      "previousPage" => L10n.t(l10n, msg("Previous page")),
      "nextPage" => L10n.t(l10n, msg("Next page")),
      "zoomIn" => L10n.t(l10n, msg("Zoom in")),
      "zoomOut" => L10n.t(l10n, msg("Zoom out")),
      "pending" => L10n.t(l10n, msg("Not reviewed")),
      "reviewed" => L10n.t(l10n, msg("Reviewed")),
      "empty" => L10n.t(l10n, msg("Not found in the document"))
    }
  end

  @doc """
  The document data `record` carries for the panes bound to `context`:
  `%{"_document_<name>" => document | nil}` (see the moduledoc). `fields`
  are the context's detail fields; their reviews give the regions.
  """
  @spec data(AshA2ui.ResolvedView.t(), atom, struct(), [atom]) :: %{String.t() => map | nil}
  def data(view, context, record, fields) do
    for pane <- view.document_panes, pane.context == context, into: %{} do
      {data_key(pane), document(pane, view, record, fields)}
    end
  end

  defp document(pane, view, record, fields) do
    case source(Map.get(record, pane.source)) do
      nil ->
        nil

      source ->
        Map.put(
          source,
          "regions",
          field_regions(view, record, fields) ++ host_regions(pane, record)
        )
    end
  end

  @doc """
  The document a pane's `source` holds, as the wire carries it
  (`%{"src", "fileName"}`), or `nil` without a `url` (or `href`).
  """
  @spec source(term) :: %{String.t() => String.t()} | nil
  def source(value) when is_map(value) and not is_struct(value) do
    case text(get(value, :url)) || text(get(value, :href)) do
      nil -> nil
      url -> %{"src" => url, "fileName" => text(get(value, :name)) || ""}
    end
  end

  def source(_value), do: nil

  # A review field's boxes, each a region named by the field: its review
  # state, its label.
  defp field_regions(view, record, fields) do
    for name <- fields,
        %{review: review_source, label: label} <- [view.fields[name]],
        review_source,
        %{"state" => state, "boxes" => boxes} <-
          [AshA2ui.Review.normalize(Map.get(record, review_source), view.l10n)],
        box <- boxes do
      Map.merge(box, %{
        "id" => Atom.to_string(name),
        "state" => review_region_state(state),
        "label" => label
      })
    end
  end

  defp review_region_state("missing"), do: "empty"
  defp review_region_state(state), do: state

  defp host_regions(%{regions: nil}, _record), do: []

  defp host_regions(%{regions: source}, record) do
    case Map.get(record, source) do
      list when is_list(list) -> list |> Enum.map(&region/1) |> Enum.reject(&is_nil/1)
      _none -> []
    end
  end

  @doc """
  A region as the wire carries it, or `nil` when it is not one: an `id`
  (text or atom), a box (`AshA2ui.Review.box/1`), a `state` among
  `states/0` (`reviewed_selected` is accepted for `reviewed-selected`;
  missing means `pending`) and an optional text `label`.
  """
  @spec region(term) :: region | nil
  def region(value) when is_map(value) and not is_struct(value) do
    with id when is_binary(id) <- id(get(value, :id)),
         %{} = box <- AshA2ui.Review.box(value),
         state when is_binary(state) <- state(get(value, :state)) do
      box
      |> Map.merge(%{"id" => id, "state" => state})
      |> put_present("label", text(get(value, :label)))
    else
      _not_a_region -> nil
    end
  end

  def region(_value), do: nil

  defp id(id) when is_binary(id) and id != "", do: id
  defp id(id) when is_atom(id) and not is_nil(id) and not is_boolean(id), do: Atom.to_string(id)
  defp id(_id), do: nil

  defp state(nil), do: "pending"
  defp state(state) when is_atom(state), do: state |> Atom.to_string() |> state()

  defp state(state) when is_binary(state) do
    state = String.replace(state, "_", "-")
    if state in @states, do: state
  end

  defp state(_state), do: nil

  @doc """
  The initial `/ui/documents` state of `view`'s panes: `%{"<name>" =>
  %{"shown" => boolean, "selected" => nil}}`, open where `document_state`
  (`url_state/2`'s shape) says so.
  """
  @spec ui_state(AshA2ui.ResolvedView.t(), map) :: %{String.t() => map}
  def ui_state(view, document_state) do
    document_state = if is_map(document_state), do: document_state, else: %{}

    Map.new(view.document_panes, fn pane ->
      name = Atom.to_string(pane.name)
      {name, %{"shown" => Map.get(document_state, name) == true, "selected" => nil}}
    end)
  end

  @doc "The loads a pane needs on its context's record: its source and regions."
  @spec loads(t(), module) :: [atom]
  def loads(pane, resource) do
    for field <- [pane.source, pane.regions],
        field,
        calculation_or_aggregate?(resource, field),
        do: field
  end

  defp calculation_or_aggregate?(resource, name) do
    not is_nil(ResourceInfo.calculation(resource, name)) or
      not is_nil(ResourceInfo.aggregate(resource, name))
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
