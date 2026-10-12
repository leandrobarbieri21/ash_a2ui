defmodule AshA2ui.Links do
  @moduledoc """
  Runtime for reference links (`link` / `links` field options).

  A linked field serializes like any other field (its cell value), and the
  row additionally carries the reserved `"_links"` key:

      %{"_links" => %{"<field>" => link | [link]}}

  where each `link` is

      %{"surface" => "person", "recordId" => "<id>", "label" => "Ada Lovelace"}

  plus `"href"` when `config :ash_a2ui, :open_surface_url` is set (a
  template with `{surface}` and `{recordId}` placeholders, e.g.
  `"/app/r/{surface}/{recordId}"`). Single links (`link`) carry one map,
  multi-valued links (`links`) a list. A field without a link for this row —
  nil reference, a target the actor cannot read, or a surface the
  `AshA2ui.LinkResolver` vetoed — is simply absent from `"_links"`. Rows of
  tables (and detail records) without link fields carry no `"_links"` key at
  all, so link-free surfaces serialize exactly as before.

  Shared by the encoder, `AshA2ui.ActionHandler` refreshes and
  `/detail`/`/ui/panel/record` population, so every path serializes links
  identically.
  """

  alias Ash.Resource.Info, as: ResourceInfo

  @label_fallbacks [:name, :title, :label, :username, :email]

  @typedoc "A prepared per-render link context (see `context/4`)."
  @type t :: %{specs: [map], url: String.t() | nil} | nil

  @doc "Whether a resolved field declares `link` or `links`."
  @spec link_field?(AshA2ui.Field.t() | nil) :: boolean
  def link_field?(%{link: link}) when not is_nil(link), do: true
  def link_field?(%{links: links}) when not is_nil(links), do: true
  def link_field?(_field), do: false

  @doc """
  The `Ash.Query.load/2` entries the link fields among `field_names` need on
  `resource`: the linked relationship (with its label calculation, when the
  label is one) or the relationship prefix of an `id_path`.
  """
  @spec loads(module, [atom] | nil, %{atom => AshA2ui.Field.t()}) :: list
  def loads(resource, field_names, fields) do
    field_names
    |> List.wrap()
    |> Enum.map(&Map.get(fields, &1))
    |> Enum.filter(&link_field?/1)
    |> Enum.flat_map(&field_loads(resource, &1))
    |> Enum.uniq()
  end

  defp field_loads(resource, field) do
    case kind(field) do
      {:relationship, _cardinality, name} ->
        relationship_loads(ResourceInfo.relationship(resource, name), field)

      {:path, _surface, path} ->
        path_loads(resource, path)
    end
  end

  defp relationship_loads(nil, _field), do: []

  defp relationship_loads(relationship, field) do
    label = label_attribute(relationship.destination, field.link_label)

    if loadable?(relationship.destination, label),
      do: [{relationship.name, [label]}],
      else: [relationship.name]
  end

  # [:attr] needs nothing; [:rel, :attr] loads :rel; a calculation/aggregate
  # terminal loads the whole path.
  defp path_loads(_resource, [_attribute]), do: []

  defp path_loads(resource, path) do
    {relationships, [terminal]} = Enum.split(path, -1)

    destination =
      Enum.reduce_while(relationships, resource, fn step, current ->
        case ResourceInfo.relationship(current, step) do
          %{destination: destination} -> {:cont, destination}
          nil -> {:halt, nil}
        end
      end)

    if destination && loadable?(destination, terminal),
      do: [path_to_load(path)],
      else: [path_to_load(relationships)]
  end

  @doc false
  def path_to_load([step]), do: step
  def path_to_load([step | rest]), do: {step, [path_to_load(rest)]}

  defp loadable?(resource, name) do
    not is_nil(ResourceInfo.calculation(resource, name)) or
      not is_nil(ResourceInfo.aggregate(resource, name))
  end

  @doc """
  Prepares the link context for one render: which of `field_names` link,
  how, and to which surface (the `AshA2ui.LinkResolver` is consulted once
  per field here, with `opts[:actor]`/`opts[:tenant]`). `nil` when none of
  the fields link — `row_data/3` then adds nothing.
  """
  @spec context(module, %{atom => AshA2ui.Field.t()}, [atom] | nil, keyword) :: t()
  def context(resource, fields, field_names, opts) do
    resolver_context = %{actor: opts[:actor], tenant: opts[:tenant]}

    specs =
      for name <- field_names |> List.wrap() |> Enum.uniq(),
          field = Map.get(fields, name),
          link_field?(field),
          spec = spec(resource, field, resolver_context),
          do: spec

    case specs do
      [] -> nil
      specs -> %{specs: specs, url: Application.get_env(:ash_a2ui, :open_surface_url)}
    end
  end

  defp spec(resource, field, resolver_context) do
    case kind(field) do
      {:relationship, cardinality, name} ->
        case ResourceInfo.relationship(resource, name) do
          nil ->
            nil

          relationship ->
            destination = relationship.destination

            %{
              field: field.name,
              cardinality: cardinality,
              relationship: name,
              destination: destination,
              primary_key: hd(ResourceInfo.primary_key(destination)),
              label: label_attribute(destination, field.link_label),
              cell_label?: is_nil(field.link_label) and cell_label?(relationship, field),
              surface: AshA2ui.LinkResolver.resolve({:resource, destination}, resolver_context)
            }
        end

      {:path, surface, path} ->
        %{
          field: field.name,
          cardinality: :path,
          path: path,
          surface: AshA2ui.LinkResolver.resolve({:surface, surface}, resolver_context)
        }
    end
  end

  # A single link labels itself with the cell's display value — unless the
  # cell IS the bare foreign key, which is no label at all.
  defp cell_label?(%{type: :belongs_to, source_attribute: attribute}, %{name: attribute}),
    do: false

  defp cell_label?(_relationship, _field), do: true

  defp kind(%{links: name}) when not is_nil(name), do: {:relationship, :many, name}
  defp kind(%{link: name}) when is_atom(name), do: {:relationship, :one, name}

  defp kind(%{link: {surface, path}}),
    do: {:path, to_string(surface), List.wrap(path)}

  @doc """
  The default link label attribute of `destination`: `link_label` when
  given, else the first public attribute of `[:name, :title, :label,
  :username, :email]`, else the primary key.
  """
  @spec label_attribute(module, atom | nil) :: atom
  def label_attribute(_destination, label) when not is_nil(label), do: label

  def label_attribute(destination, nil) do
    Enum.find(
      @label_fallbacks,
      &match?(%{public?: true}, ResourceInfo.attribute(destination, &1))
    ) ||
      hd(ResourceInfo.primary_key(destination))
  end

  @doc """
  The reserved row data for `record`: `%{"_links" => %{field => link |
  [link]}}`, or `%{}` without a link context. `row` is the record's already
  serialized cell values (single links label themselves from them).
  """
  @spec row_data(t(), struct, map) :: map
  def row_data(nil, _record, _row), do: %{}

  def row_data(%{specs: specs, url: url}, record, row) do
    links =
      Enum.reduce(specs, %{}, fn spec, acc ->
        case field_links(spec, record, row, url) do
          nil -> acc
          [] -> acc
          link -> Map.put(acc, to_string(spec.field), link)
        end
      end)

    %{"_links" => links}
  end

  defp field_links(%{surface: nil}, _record, _row, _url), do: nil

  defp field_links(%{cardinality: :one} = spec, record, row, url) do
    case loaded(Map.get(record, spec.relationship)) do
      nil ->
        nil

      related ->
        cell = Map.get(row, to_string(spec.field))

        label =
          if spec.cell_label? and is_binary(cell) and cell != "",
            do: cell,
            else: record_label(related, spec)

        entry(spec.surface, Map.get(related, spec.primary_key), label, url)
    end
  end

  defp field_links(%{cardinality: :many} = spec, record, _row, url) do
    record
    |> Map.get(spec.relationship)
    |> loaded()
    |> List.wrap()
    |> Enum.flat_map(fn related ->
      case entry(
             spec.surface,
             Map.get(related, spec.primary_key),
             record_label(related, spec),
             url
           ) do
        nil -> []
        link -> [link]
      end
    end)
  end

  defp field_links(%{cardinality: :path} = spec, record, row, url) do
    id = walk(record, spec.path)
    cell = Map.get(row, to_string(spec.field))
    label = if is_binary(cell) and cell != "", do: cell, else: id_string(id)
    entry(spec.surface, id, label, url)
  end

  @doc """
  The cell value of a **virtual** link field — one whose name is not an
  attribute, calculation or aggregate of the record's resource and that has
  no `source`: the linked record's label (`link :relationship`), the labels
  joined with ", " (`links`), or the id read from the path (`link {surface,
  path}`). Returns `:not_virtual` for every other field (which serializes as
  usual).
  """
  @spec virtual_value(AshA2ui.Field.t() | nil, struct) :: {:ok, term} | :not_virtual
  def virtual_value(field, record) do
    resource = record.__struct__

    if link_field?(field) and is_nil(field.source) and not resource_field?(resource, field.name) do
      {:ok, virtual(kind(field), field, resource, record)}
    else
      :not_virtual
    end
  end

  defp virtual({:relationship, cardinality, name}, field, resource, record) do
    case ResourceInfo.relationship(resource, name) do
      nil -> ""
      relationship -> join_labels(cardinality, related_labels(relationship, field, record))
    end
  end

  defp virtual({:path, _surface, path}, _field, _resource, record) do
    id_string(walk(record, path)) || ""
  end

  defp related_labels(relationship, field, record) do
    label = label_attribute(relationship.destination, field.link_label)

    record
    |> Map.get(relationship.name)
    |> loaded()
    |> List.wrap()
    |> Enum.map(&label_string(Map.get(&1, label)))
    |> Enum.reject(&(&1 == ""))
  end

  defp join_labels(:many, labels), do: Enum.join(labels, ", ")
  defp join_labels(_one, labels), do: List.first(labels) || ""

  defp resource_field?(resource, name) do
    not is_nil(ResourceInfo.attribute(resource, name)) or
      not is_nil(ResourceInfo.calculation(resource, name)) or
      not is_nil(ResourceInfo.aggregate(resource, name))
  end

  defp record_label(related, spec) do
    case label_string(Map.get(related, spec.label)) do
      "" -> id_string(Map.get(related, spec.primary_key))
      label -> label
    end
  end

  defp entry(_surface, id, _label, _url) when id in [nil, ""], do: nil

  defp entry(surface, id, label, url) do
    id = id_string(id)
    link = %{"surface" => surface, "recordId" => id, "label" => label || id}

    case url do
      template when is_binary(template) -> Map.put(link, "href", href(template, surface, id))
      _none -> link
    end
  end

  @doc """
  Expands an `open_surface_url` template (`{surface}`, `{recordId}`
  placeholders, URI-encoded) — shared with `AshA2ui.LiveRenderer`'s default
  `"a2ui:open_surface"` navigation.
  """
  @spec href(String.t(), String.t(), String.t() | nil) :: String.t()
  def href(template, surface, record_id) do
    template
    |> String.replace("{surface}", encode(surface))
    |> String.replace("{recordId}", encode(record_id || ""))
  end

  defp encode(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)

  defp walk(nil, _path), do: nil
  defp walk(value, []), do: loaded(value)

  defp walk(value, [step | rest]) when is_map(value) do
    value
    |> Map.get(step, Map.get(value, to_string(step)))
    |> loaded()
    |> walk(rest)
  end

  defp walk(_value, _path), do: nil

  defp loaded(%Ash.NotLoaded{}), do: nil
  defp loaded(value), do: value

  defp id_string(nil), do: nil
  defp id_string(value) when is_binary(value), do: value
  defp id_string(value), do: to_string(value)

  defp label_string(nil), do: ""
  defp label_string(%Ash.NotLoaded{}), do: ""
  defp label_string(value) when is_binary(value), do: value
  defp label_string(%Ash.CiString{} = value), do: to_string(value)

  defp label_string(value) when is_atom(value) or is_number(value) or is_struct(value, Decimal),
    do: to_string(value)

  defp label_string(value), do: inspect(value)
end
