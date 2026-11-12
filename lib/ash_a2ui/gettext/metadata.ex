defmodule AshA2ui.Gettext.Metadata do
  @moduledoc """
  The host display metadata a set of A2UI surfaces shows, as a gettext
  template: what `mix ash_a2ui.gettext.extract_metadata` writes to the
  host's `priv/gettext/a2ui_metadata.pot`.

  Collection runs the runtime's own code, not a copy of it. Each surface is
  resolved (`AshA2ui.ResolvedView.resolve/2`), its sectioned tables are
  expanded without reads (`AshA2ui.Sections.expand_static/1`), and it is
  encoded with no records, with a recording `:gettext_fn` as its
  translator. Every lookup the runtime makes in the metadata domain
  (`AshA2ui.Label`, `AshA2ui.L10n.metadata/3`) is recorded with its
  `msgctxt`, so the template holds exactly the strings a reader sees, and
  display text routed through those functions is collected with no change
  here. Library strings (`AshA2ui.Gettext.msg/1`) are in the shipped
  `ash_a2ui.pot` and are not collected.

  Labels that only a record selects (an enum's choice labels, the `icon_labels`,
  `detail_text`, `badge_text`, `badge_help` and primary action `labels` of a
  row, a column's `caption_text`, a query's empty states) are collected from their declarations, every value once.
  A canvas registry (`AshA2ui.Canvas.Registry`) is collected by building its
  graph and resolving each resource.

  No data layer is touched: section headings and option labels read from
  records are record data, not metadata.
  """

  alias AshA2ui.L10n
  alias AshA2ui.Label
  alias AshA2ui.ResolvedView
  alias AshA2ui.TypeMapper

  @typedoc "A collected message: its `msgctxt` (or `nil`) and its msgid."
  @type key :: {String.t() | nil, String.t()}

  @doc """
  Every surface of `otp_app`: its modules that are Ash resources using the
  `AshA2ui` extension, its `AshA2ui.Standalone` UI modules and its
  `AshA2ui.Canvas.Registry` modules, sorted by name.
  """
  @spec surfaces(atom) :: [module]
  def surfaces(otp_app) do
    case :application.get_key(otp_app, :modules) do
      {:ok, modules} -> modules |> Enum.filter(&surface?/1) |> Enum.sort()
      :undefined -> []
    end
  end

  defp surface?(module) do
    Code.ensure_loaded?(module) and
      (registry?(module) or
         (function_exported?(module, :spark_dsl_config, 0) and
            (Spark.Dsl.is?(module, AshA2ui.Standalone) or
               (Spark.Dsl.is?(module, Ash.Resource) and AshA2ui in Spark.extensions(module)))))
  end

  defp registry?(module),
    do: AshA2ui.Canvas.Registry in Keyword.get(module.module_info(:attributes), :behaviour, [])

  @doc """
  The metadata messages `surfaces` show, each mapped to the sorted source
  `file:line` references (the file relative to the working directory, the
  line the surface's module starts at) of the surfaces showing it.
  """
  @spec messages([module]) :: %{key => [String.t()]}
  def messages(surfaces) do
    surfaces
    |> Enum.flat_map(fn surface ->
      surface |> surface_messages() |> Enum.map(&{&1, source(surface)})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, files} -> {key, files |> Enum.uniq() |> Enum.sort()} end)
  end

  @doc """
  The metadata messages one surface shows, as `{msgctxt, msgid}` keys, in
  the order the runtime resolves them, without duplicates.
  """
  @spec surface_messages(module) :: [key]
  def surface_messages(surface) do
    if registry?(surface) do
      collect_registry(surface)
    else
      view =
        surface
        |> ResolvedView.resolve(gettext_fn: {__MODULE__, :record})
        |> AshA2ui.Sections.expand_static()

      AshA2ui.Info.encoder(view).encode_surface(view, no_records(view), [])
      Enum.each(view.tables, &collect_table(&1, view.l10n))
      Enum.each(view.details, &collect_detail(&1, view))
    end

    drain([]) |> Enum.reverse() |> Enum.uniq()
  end

  defp collect_registry(registry) do
    opts = [gettext_fn: {__MODULE__, :record}]

    for %{kind: :resource, id: id} <-
          registry |> AshA2ui.Canvas.build_graph(opts) |> Map.fetch!(:nodes) |> Map.values() do
      AshA2ui.Canvas.resolve(id, [registry: registry] ++ opts)
    end
  end

  # The labels a table shows only once a record selects them, or only the
  # admin catalog shows: collected from the declarations.
  defp collect_table(table, l10n) do
    %{component: component, resource: resource} = table

    for name <- component.fields || [], do: TypeMapper.choices(resource, name, l10n)

    texts =
      Enum.flat_map(component.columns, &column_texts/1) ++
        layout_texts(component.row_layout, resource) ++
        primary_texts(component.primary_action) ++
        query_texts(table.query) ++
        edited_texts(component)

    Enum.each(texts, fn
      {context, text} -> Label.translate(l10n, text, context)
      text -> Label.translate(l10n, text)
    end)
  end

  # A detail card's badge fields: their texts and help show only once a record
  # selects them, like a row layout's badge.
  defp collect_detail(detail, view) do
    resource = view.contexts[detail.context].resource

    # Only the admin catalog shows the placeholder, so the basic encoder run
    # above never translates it.
    for name <- detail.fields,
        %{empty_text: text} when is_binary(text) <- [view.fields[name]],
        do: Label.translate(view.l10n, text)

    for name <- detail.fields,
        field = view.fields[name],
        ResolvedView.badge_field?(field),
        text <-
          layout_texts(
            %AshA2ui.RowLayout{
              badge: name,
              badge_text: field.badge_text,
              badge_help: field.badge_help
            },
            resource
          ) do
      case text do
        {context, text} -> Label.translate(view.l10n, text, context)
        text -> Label.translate(view.l10n, text)
      end
    end
  end

  defp column_texts(column) do
    help = [
      column.help_title,
      column.help && String.trim(column.help),
      column.more_noun,
      Map.get(column, :caption_text)
    ]

    unlabeled =
      for {value, _icon} <- column.icon_names,
          not Keyword.has_key?(column.icon_labels, value),
          do: Label.humanize(value)

    Enum.reject(help, &is_nil/1) ++
      Keyword.values(column.icon_labels) ++ Keyword.values(column.detail_text) ++ unlabeled
  end

  defp layout_texts(nil, _resource), do: []

  defp layout_texts(layout, resource) do
    values = (layout.badge && TypeMapper.choices(resource, layout.badge)) || []
    context = layout.badge && TypeMapper.choice_context(resource, layout.badge)

    unlabeled =
      for {value, _label} <- values,
          not Keyword.has_key?(layout.badge_text, value),
          do: {context, Label.humanize(value)}

    Keyword.values(layout.badge_text) ++
      Keyword.values(Map.get(layout, :badge_help, [])) ++
      unlabeled
  end

  # "Updated <field>." names the edited field by its humanized name.
  defp edited_texts(%{editable: %{fields: fields}}) when is_list(fields),
    do: Enum.map(fields, &Label.humanize/1)

  defp edited_texts(_component), do: []

  defp primary_texts(nil), do: []

  defp primary_texts(action),
    do: Enum.reject([action.label | Keyword.values(action.labels)], &is_nil/1)

  defp query_texts(nil), do: []

  defp query_texts(query) do
    states = [
      query.empty_state,
      query.no_results_state | Enum.map(query.presets, & &1.empty_state)
    ]

    state_texts =
      for state <- states,
          state,
          key <- [:title, :message],
          text = Keyword.get(state, key),
          text != "",
          do: text

    Enum.reject([query.search_placeholder, clear_action(query)], &is_nil/1) ++
      Keyword.values(query.filter_hints) ++ state_texts
  end

  defp clear_action(%{no_results_state: nil}), do: nil
  defp clear_action(%{no_results_state: state}), do: Keyword.get(state, :clear_action)

  defp no_records(view) do
    if ResolvedView.multi_table?(view), do: Map.new(view.tables, &{&1.name, []}), else: []
  end

  # The recording translator: a `:gettext_fn` of the domain-aware shape. It
  # translates nothing (`nil` falls back to the msgid), so the surface
  # renders exactly as it does untranslated.
  @doc false
  def record(msgid, _bindings, _locale, meta) do
    if meta[:domain] == L10n.default_metadata_domain() do
      send(self(), {__MODULE__, meta[:context], msgid})
    end

    nil
  end

  defp drain(acc) do
    receive do
      {__MODULE__, context, msgid} -> drain([{context, msgid} | acc])
    after
      0 -> acc
    end
  end

  defp source(module) do
    file =
      module.module_info(:compile)
      |> Keyword.fetch!(:source)
      |> to_string()
      |> Path.relative_to_cwd()

    case Code.fetch_docs(module) do
      {:docs_v1, anno, _, _, _, _, _} -> "#{file}:#{:erl_anno.line(anno)}"
      _no_docs -> file
    end
  end

  @doc """
  The `.pot` content for `messages` (from `messages/1`) in `domain`:
  entries sorted by msgid, then `msgctxt`, each with its source files as
  references.
  """
  @spec pot(%{key => [String.t()]}, String.t()) :: String.t()
  def pot(messages, domain) do
    entries =
      messages
      |> Enum.sort_by(fn {{context, msgid}, _files} -> {msgid, context || ""} end)
      |> Enum.map_join("\n", fn {key, files} -> entry(key, files) end)

    header(domain) <> entries
  end

  defp header(domain) do
    """
    ## This file is a PO Template file.
    ##
    ## `msgid`s here are the display labels of this application's A2UI
    ## surfaces, collected by resolving each surface.
    ##
    ## Run `mix ash_a2ui.gettext.extract_metadata` to refresh this file.
    ## Run `mix gettext.merge priv/gettext --locale LOCALE` to merge into a .po file.
    msgid ""
    msgstr ""
    "Content-Type: text/plain; charset=UTF-8\\n"
    "Content-Transfer-Encoding: 8bit\\n"
    "Domain: #{domain}\\n"

    """
  end

  defp entry({context, msgid}, files) do
    [
      Enum.map(files, &"#: #{&1}\n"),
      if(context, do: "msgctxt #{quote_po(context)}\n", else: []),
      "msgid #{quote_po(msgid)}\n",
      "msgstr \"\"\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp quote_po(string) do
    escaped =
      string
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\t", "\\t")

    "\"" <> escaped <> "\""
  end
end
