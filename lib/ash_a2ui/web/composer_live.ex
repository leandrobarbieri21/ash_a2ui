# AshA2ui.Web.ComposerLive is the self-hosted surface editor. Like the other
# shipped LiveView surfaces, the whole module is guarded so the NO_PHOENIX CI
# job (which strips the Phoenix stack) still compiles the protocol core.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Web.ComposerLive do
    @moduledoc """
    The self-hosted **surface editor**: browse a host's declared surfaces,
    import one into the dynamic spec vocabulary, edit it as structured rows,
    watch it resolve live, and export the equivalent standalone module —
    the whole `AshA2ui.Dynamic` pipeline with the honesty as UI.

    This is the human counterpart to the agent flow in
    `AshA2ui.Dynamic` (`spec_schema/1` + `resolve/2`): the same spec, the
    same parser, the same verifiers, the same error messages — validated on
    **every change**, inline.

    ## Mounting

        use AshA2ui.Web.ComposerLive,
          surfaces: [MyApp.UI.FeedbackUI, MyApp.Feedback],
          allowlist: [MyApp.User],
          export_module: "MyApp.UI.ComposedFeedback"

    ### `use` options

      * `:surfaces` (required) — the UI modules or resources offered for
        import: anything carrying an `a2ui` section (a standalone
        `AshA2ui.Standalone` module or a resource with the extension).
      * `:allowlist` (optional) — controls the resources the spec may
        reference. A `%{"name" => module}` map is **the** allowlist, verbatim
        — the escape hatch when two surfaces' resources collide on their
        short module name (imports of those surfaces then resolve once the
        operator picks the disambiguated name in the resource select). A
        list of modules is extra resources (e.g. context destinations)
        merged into the allowlist derived from `:surfaces`. Without it, the
        allowlist is the surfaces' resources named by short module name
        (`AshA2ui.Dynamic.allowlist/1`, raising on collisions).
      * `:export_module` (optional) — the module name shown in the Export
        pane's generated source. Defaults to the imported module name with
        `.Composed` appended (e.g. `MyApp.UI.FeedbackUI.Composed`).
      * `:via_allowlist` (optional) — the modules a spec's `via`-delegated
        row actions may dispatch to (as `AshA2ui.Dynamic.resolve/2`).
        Defaults to none: a spec carrying `via` then resolves only after
        the host opts the delegate module in.

    The editor's allowlist is derived from `:surfaces` (each surface's
    resource, named by short module name — `AshA2ui.Dynamic.allowlist/1`).
    A surface that also reads other resources — context destinations,
    related tables (`resource` on a `:table`), section sources — imports
    them by name; pass those resources in `:allowlist` so the imported spec
    resolves (until then the resolve names the missing resource).

    ## The flow

      1. **Browse** — one card per configured surface (module, resource,
         declared title), each with an Import button.
      2. **Import** — `AshA2ui.Dynamic.Importer.import/1` turns the
         declared `a2ui` section into a spec. Features the spec vocabulary
         cannot carry are **rejections**, rendered in full via
         `AshA2ui.Dynamic.Importer.Rejection.messages/1` — never silently
         dropped.
      3. **Edit** — the spec as structured rows per collection
         (components/queries/fields/actions/contexts). The rows are derived
         from `AshA2ui.Dynamic.spec_schema/1` itself: add spec vocabulary
         and the editor grows it. Every change rebuilds the spec and runs
         `AshA2ui.Dynamic.resolve/2`; validation errors render inline with
         their spec paths. A structured field whose value is not valid JSON
         reports the decode error and is left out of the resolve.
      4. **Preview** — when the spec resolves, the resolved surface's
         components/queries/fields/actions/contexts render structurally
         (the entities the encoder will encode). The client-rendered
         surface itself is served by the host's transport —
         `AshA2ui.LiveRenderer` or the JS hook.
      5. **Export** — `AshA2ui.Dynamic.to_dsl_source/2` renders the
         formatted, compile-ready standalone module source, copyable from
         a readonly textarea.

    ## Events (client -> server)

      * `"import"` with `phx-value-module` — import the named surface.
      * `"validate"` (the form's `phx-change`) — rebuild + re-resolve the
        spec from the form params under `"spec"`.
      * `"add-row"` with `phx-value-section` — append a seed row.
      * `"remove-row"` with `phx-value-section` + `phx-value-index`.
      * `"reset"` — back to Browse.

    ## Host integration

    All callbacks are `defoverridable` (`mount/3`, `render/1`,
    `handle_event/3`, `handle_info/2`). Hosts that layer presence or other
    socket machinery override `mount/3` and/or `handle_info/2` and delegate
    to `AshA2ui.Web.ComposerLive`.

    Export is intentionally **export-first**: the editor shows the DSL
    source, it does not write modules back to disk. Promoting a spec is a
    human, checked-in act (paste the source into a new module) — v1 keeps
    the composer from mutating the host's code.
    """

    use Phoenix.Component

    alias AshA2ui.Dynamic
    alias AshA2ui.Dynamic.Error
    alias AshA2ui.Dynamic.Importer
    alias Spark.Dsl.Extension

    @composed_suffix "Composed"
    @default_export_module "AshA2ui.ComposedSurface"

    @doc false
    defmacro __using__(opts) do
      quote do
        use Phoenix.LiveView

        @doc false
        def __composer_config__ do
          unquote(__MODULE__).build_config(unquote(opts))
        end

        @impl true
        def mount(params, session, socket) do
          unquote(__MODULE__).mount(__composer_config__(), params, session, socket)
        end

        @impl true
        def render(assigns) do
          unquote(__MODULE__).composer_shell(assigns)
        end

        @impl true
        def handle_event(event, params, socket) do
          unquote(__MODULE__).handle_event(event, params, __composer_config__(), socket)
        end

        @impl true
        def handle_info(message, socket) do
          unquote(__MODULE__).handle_info(message, socket)
        end

        defoverridable mount: 3, render: 1, handle_event: 3, handle_info: 2
      end
    end

    @doc false
    def build_config(opts) do
      surfaces = Keyword.fetch!(opts, :surfaces)

      %{
        surfaces: Enum.map(surfaces, &surface_entry/1),
        module_index: Map.new(surfaces, fn module -> {module_name(module), module} end),
        allowlist: build_allowlist(surfaces, Keyword.get(opts, :allowlist)),
        via_allowlist: Keyword.get(opts, :via_allowlist, []),
        export_module: Keyword.get(opts, :export_module)
      }
    end

    defp module_name(module), do: module |> inspect()

    # --- lifecycle ----------------------------------------------------------------------

    @doc false
    def mount(config, _params, _session, socket) do
      {:ok,
       assign(socket,
         composer_config: config,
         sections: editor_sections(config.allowlist),
         resource_options: Enum.sort(Map.keys(config.allowlist)),
         surfaces: config.surfaces,
         page: :browse,
         imported: nil,
         spec: %{},
         rejections: [],
         errors: [],
         surface: nil,
         export: nil,
         export_module: @default_export_module
       )}
    end

    @doc false
    def handle_event("import", %{"module" => module_name}, config, socket) do
      module = Map.fetch!(config.module_index, module_name)

      {spec, rejections} =
        case Importer.import(module) do
          {:ok, spec, rejections} -> {spec, rejections}
          {:error, rejection} -> {%{}, [rejection]}
        end

      socket =
        assign(socket,
          page: :editor,
          imported: module_name,
          spec: spec,
          rejections: rejections,
          export_module: export_module_name(config.export_module, module)
        )

      {:noreply, apply_resolution(socket, spec, [])}
    end

    def handle_event("validate", params, _config, socket) do
      form_spec = params["spec"] || %{}
      {spec, build_errors} = build_spec(form_spec, socket.assigns.sections)

      {:noreply, socket |> assign(spec: spec) |> apply_resolution(spec, build_errors)}
    end

    def handle_event("add-row", %{"section" => key}, _config, socket) do
      section = Enum.find(socket.assigns.sections, &(&1.key == key))
      seed = (section && section.seed) || %{}
      rows = Map.get(socket.assigns.spec, key, [])
      spec = Map.put(socket.assigns.spec, key, rows ++ [seed])

      {:noreply, socket |> assign(spec: spec) |> apply_resolution(spec, [])}
    end

    def handle_event("remove-row", %{"section" => key, "index" => index}, _config, socket) do
      rows = List.delete_at(Map.get(socket.assigns.spec, key, []), String.to_integer(index))
      spec = Map.put(socket.assigns.spec, key, rows)

      {:noreply, socket |> assign(spec: spec) |> apply_resolution(spec, [])}
    end

    def handle_event("reset", _params, _config, socket) do
      {:noreply,
       assign(socket,
         page: :browse,
         imported: nil,
         spec: %{},
         rejections: [],
         errors: [],
         surface: nil,
         export: nil
       )}
    end

    @doc false
    def handle_info(_message, socket), do: {:noreply, socket}

    # --- resolution ---------------------------------------------------------------------

    # Every edit runs the same pipeline an LLM-composed spec runs: resolve
    # (parser + field inference + the compile-time verifiers). Errors are
    # the editor's first-class content; a resolved surface enables the
    # preview and the export.
    defp apply_resolution(socket, spec, extra_errors) do
      config = socket.assigns.composer_config

      resolve_opts = [
        allowlist: config.allowlist,
        via_allowlist: config.via_allowlist
      ]

      case Dynamic.resolve(spec, resolve_opts) do
        {:ok, surface} ->
          assign(socket,
            surface: surface,
            errors: extra_errors,
            export: export_source(config, spec, socket.assigns.export_module)
          )

        {:error, errors} ->
          assign(socket,
            surface: nil,
            export: nil,
            errors: Enum.sort_by(extra_errors ++ errors, &{&1.path, &1.message})
          )
      end
    end

    defp export_source(config, spec, module_name) do
      module = Module.concat(String.split(module_name, "."))

      case Dynamic.to_dsl_source(spec,
             module: module,
             allowlist: config.allowlist,
             via_allowlist: config.via_allowlist
           ) do
        {:ok, source} -> source
        {:error, _errors} -> nil
      end
    end

    defp export_module_name(nil, imported) do
      case imported do
        nil ->
          @default_export_module

        module ->
          module |> Module.split() |> Enum.concat([@composed_suffix]) |> Enum.join(".")
      end
    end

    defp export_module_name(name, _imported) when is_binary(name), do: name
    defp export_module_name(module, _imported) when is_atom(module), do: inspect(module)

    # --- host config --------------------------------------------------------------------

    defp surface_entry(module) do
      resource = surface_resource(module)

      %{
        module: module,
        name: module |> Module.split() |> List.last(),
        resource: resource && resource |> Module.split() |> List.last(),
        title: surface_title(module)
      }
    end

    defp surface_title(module) do
      case Extension.get_opt(module, [:a2ui], :title, nil) do
        title when is_binary(title) -> title
        _other -> nil
      end
    rescue
      _not_a_spark_module -> nil
    end

    # The allowlist is host configuration:
    #
    #   * no `:allowlist` option — derive it from the surfaces' resources,
    #     named by short module name;
    #   * a `%{"name" => module}` map — THE allowlist, verbatim: the host
    #     names everything (the escape hatch when two surfaces' resources
    #     collide on their short name, e.g. two different `Definition`s —
    #     imports of those surfaces then resolve once the operator picks the
    #     disambiguated name in the resource select);
    #   * a list of modules — extra resources merged into the derived ones.
    defp build_allowlist(surfaces, nil), do: derive_allowlist(surfaces)
    defp build_allowlist(_surfaces, %{} = named), do: Dynamic.allowlist(named)

    defp build_allowlist(surfaces, extras) when is_list(extras) do
      merge_allowlists(derive_allowlist(surfaces), Dynamic.allowlist(extras))
    end

    defp derive_allowlist(surfaces) do
      surfaces
      |> Enum.map(&surface_resource/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Dynamic.allowlist()
    end

    defp surface_resource(module) do
      AshA2ui.Info.resource!(module)
    rescue
      _not_an_a2ui_surface -> nil
    end

    defp merge_allowlists(base, extras) do
      Enum.reduce(extras, base, fn {name, resource}, acc ->
        case Map.fetch(acc, name) do
          {:ok, ^resource} ->
            acc

          {:ok, other} ->
            raise ArgumentError,
                  "allowlist name #{inspect(name)} is already taken by " <>
                    "#{inspect(other)} — pass a %{\"name\" => module} map to disambiguate"

          :error ->
            Map.put(acc, name, resource)
        end
      end)
    end

    # --- the editor's schema-derived rows -------------------------------------------------

    @section_keys ["components", "queries", "fields", "actions", "contexts"]

    @section_labels %{
      "components" => "components",
      "queries" => "queries",
      "fields" => "fields",
      "actions" => "actions",
      "contexts" => "contexts"
    }

    @section_singular %{
      "components" => "component",
      "queries" => "query",
      "fields" => "field",
      "actions" => "action",
      "contexts" => "context"
    }

    # The editor is generated from `Dynamic.spec_schema/1` itself: the
    # schema is the single definition of the spec vocabulary, so the form
    # can never drift from what the parser accepts.
    defp editor_sections(allowlist) do
      properties = Dynamic.spec_schema(allowlist)["properties"]

      Enum.map(@section_keys, fn key ->
        item_schema = properties[key]["items"]
        fields = item_schema |> Map.fetch!("properties") |> Enum.map(&field_meta/1)
        required = Map.get(item_schema, "required", [])

        %{
          key: key,
          label: Map.fetch!(@section_labels, key),
          singular: Map.fetch!(@section_singular, key),
          fields: fields,
          required: required,
          seed: seed_row(item_schema),
          label_key: hd(required ++ [hd(Enum.map(fields, & &1.key))])
        }
      end)
    end

    defp field_meta({key, schema}) do
      case input_type(schema) do
        {:select, options} -> %{key: key, type: :select, options: options}
        type -> %{key: key, type: type, options: []}
      end
    end

    defp input_type(%{"type" => "string", "enum" => enum}), do: {:select, enum}
    defp input_type(%{"type" => "string"}), do: :text
    defp input_type(%{"type" => "integer"}), do: :number
    defp input_type(%{"type" => "boolean"}), do: :checkbox

    # A plain name schema (`type: string`) is the comma-separated names
    # input; anything richer (relationship paths, anyOf, objects) is a raw
    # JSON input — validated on change like everything else.
    defp input_type(%{"type" => "array", "items" => %{"type" => "string"}}), do: :list
    defp input_type(_schema), do: :json

    defp seed_row(item_schema) do
      properties = item_schema["properties"]

      item_schema
      |> Map.get("required", [])
      |> Map.new(fn key ->
        case input_type(properties[key]) do
          {:select, [first | _rest]} -> {key, first}
          _other -> {key, ""}
        end
      end)
    end

    # --- form -> spec -------------------------------------------------------------------

    # The form speaks the spec's JSON vocabulary; this side rebuilds the
    # string-keyed spec map the parser consumes. Keys the operator left
    # empty are omitted (silence = default, exactly like the DSL); values
    # that do not survive coercion (bad JSON, non-numeric numbers) become
    # structured errors and are left out of the resolve.
    defp build_spec(form_spec, sections) do
      {base, errors} = top_level_spec(form_spec)

      Enum.reduce(sections, {base, errors}, fn section, {spec, errors} ->
        {rows, row_errors} =
          form_spec
          |> section_rows(section.key)
          |> Enum.with_index()
          |> Enum.map_reduce([], fn {row, index}, acc ->
            {built, errs} = build_row(row, section, index)
            {built, acc ++ errs}
          end)

        spec = if rows == [], do: spec, else: Map.put(spec, section.key, rows)
        {spec, errors ++ row_errors}
      end)
    end

    defp top_level_spec(form_spec) do
      spec =
        %{"resource" => form_spec["resource"] || ""}
        |> put_optional("title", form_spec["title"])

      {spec, []}
    end

    defp put_optional(map, _key, nil), do: map
    defp put_optional(map, _key, ""), do: map
    defp put_optional(map, key, value), do: Map.put(map, key, value)

    # Browsers deliver repeated inputs as maps keyed by index ("%{0 => ...}");
    # tests (and any programmatic client) may send lists. Normalize to rows.
    defp section_rows(form_spec, key) do
      case Map.get(form_spec, key) do
        rows when is_list(rows) -> rows
        rows when is_map(rows) -> rows |> Enum.sort_by(&index_of/1) |> Enum.map(&elem(&1, 1))
        _other -> []
      end
    end

    defp index_of({key, _row}) do
      case Integer.parse(to_string(key)) do
        {index, _rest} -> index
        :error -> 0
      end
    end

    defp build_row(form_row, section, index) do
      path = "#{section.key}[#{index}]"

      {row, errors} =
        Enum.reduce(section.fields, {%{}, []}, fn field, {row, errors} ->
          case coerce(field.type, form_row[field.key]) do
            :omit ->
              {row, errors}

            {:ok, value} ->
              {Map.put(row, field.key, value), errors}

            {:error, message} ->
              {row, errors ++ [Error.new("#{path}.#{field.key}", message)]}
          end
        end)

      {row, errors}
    end

    defp coerce(_type, nil), do: :omit
    defp coerce(_type, ""), do: :omit
    defp coerce(:checkbox, value), do: {:ok, value == "true"}

    defp coerce(:number, value) do
      case Integer.parse(String.trim(value)) do
        {integer, ""} -> {:ok, integer}
        _other -> {:error, "must be a whole number, got: #{inspect(value)}"}
      end
    end

    defp coerce(:list, value) do
      {:ok, value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))}
    end

    defp coerce(:json, value) do
      case Jason.decode(value) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, error} -> {:error, "invalid JSON — #{Exception.message(error)}"}
      end
    end

    defp coerce(_type, value), do: {:ok, value}

    # --- markup helpers -------------------------------------------------------------------

    defp rows_of(spec, section), do: Map.get(spec, section.key, [])

    defp row_title(section, row, index) do
      title = row[section.label_key]

      if title in [nil, ""],
        do: "new #{section.singular} ##{index + 1}",
        else: title
    end

    defp input_name(section_key, index, key), do: "spec[#{section_key}][#{index}][#{key}]"
    defp input_id(section_key, index, key), do: "composer-#{section_key}-#{index}-#{key}"

    defp humanize(key), do: key |> String.replace("_", " ")

    defp input_value(:checkbox, value), do: value == true

    defp input_value(:list, value) when is_list(value),
      do: Enum.map_join(value, ", ", fn entry -> to_string(entry) end)

    defp input_value(:json, value) when is_map(value) or is_list(value),
      do: Jason.encode!(value)

    defp input_value(:number, value) when is_integer(value), do: Integer.to_string(value)
    defp input_value(_type, nil), do: ""
    defp input_value(_type, value) when is_binary(value), do: value
    defp input_value(_type, value), do: to_string(value)

    defp selected?(option, value), do: to_string(value) == option and value not in [nil, ""]

    # The preview renders the RESOLVED entities — the structs the shared
    # verifiers accepted and the encoder will encode (read straight off the
    # surface's synthetic DSL state through the same `AshA2ui.Info` the
    # declared surfaces use).
    defp preview_components(surface), do: AshA2ui.Info.components(surface.dsl_state)
    defp preview_queries(surface), do: AshA2ui.Info.queries(surface.dsl_state)
    defp preview_fields(surface), do: AshA2ui.Info.fields(surface.dsl_state)
    defp preview_actions(surface), do: AshA2ui.Info.action_settings(surface.dsl_state)
    defp preview_contexts(surface), do: AshA2ui.Info.contexts(surface.dsl_state)

    defp component_title(%AshA2ui.Component{name: kind, as: nil}), do: to_string(kind)
    defp component_title(%AshA2ui.Component{name: kind, as: as}), do: "#{kind} (#{as})"

    defp names(nil), do: "inferred at render"
    defp names([]), do: "inferred at render"
    defp names(list) when is_list(list), do: Enum.map_join(list, ", ", &to_string/1)

    defp opt_text(_label, nil), do: []
    defp opt_text(label, value), do: ["#{label}: #{to_string(value)}"]

    defp list_text(_label, nil), do: []
    defp list_text(_label, []), do: []

    defp list_text(label, list) when is_list(list),
      do: ["#{label}: #{Enum.map_join(list, ", ", &to_string/1)}"]

    defp component_summary(component) do
      Enum.join(
        List.flatten([
          "fields: #{names(component.fields)}",
          opt_text("resource", component.resource && inspect(component.resource)),
          opt_text("read", component.read_action),
          opt_text("create", component.create_action),
          opt_text("update", component.update_action),
          list_text("row actions", component.row_actions),
          opt_text("query", component.query),
          opt_text("context", component.context)
        ]),
        " · "
      )
    end

    defp query_summary(query) do
      Enum.join(
        List.flatten([
          list_text("search", query.search_fields),
          list_text("sortable", query.sortable),
          list_text("filters", query.filters),
          list_text("range filters", query.range_filters),
          opt_text("default preset", query.default_preset),
          opt_text("page size", query.page_size)
        ]),
        " · "
      )
    end

    defp action_summary(action) do
      texts =
        List.flatten([
          list_text("refreshes", action.refreshes),
          list_text("prompt fields", action.prompt_fields),
          opt_text("via", via_text(action))
        ])

      case texts do
        [] -> "metadata only"
        texts -> Enum.join(texts, " · ")
      end
    end

    defp via_text(%{via: nil}), do: nil

    defp via_text(%{via: {module, function, args}}),
      do: "#{inspect(module)}.#{function}/#{1 + length(args)}"

    # The preview is structural by design: the wire payload and its
    # client-side rendering belong to the host's transport.
    defp structural_note do
      "Structural preview — the entities the verifiers accepted. The rendered " <>
        "surface is served by the host's transport (LiveRenderer or the JS hook)."
    end

    defp export_note do
      "Export is export-first: paste this into a checked-in module to promote " <>
        "the spec. The composer does not write to your code."
    end

    defp required?(section, key), do: key in section.required

    # --- render ---------------------------------------------------------------------------

    @doc false
    def composer_shell(assigns) do
      ~H"""
      <div class="a2ui-composer">
        <style>
          .a2ui-composer {
            --ac-border: var(--a2ui-color-border, #1c1917);
            --ac-surface: var(--a2ui-color-surface, #ffffff);
            --ac-background: var(--a2ui-color-background, #fafaf9);
            --ac-primary: var(--a2ui-color-primary, #4f46e5);
            --ac-on-primary: var(--a2ui-color-on-primary, #ffffff);
            --ac-danger: #dc2626;
            --ac-warn: #d97706;
            --ac-radius: var(--a2ui-border-radius, 0.375rem);
            color: var(--a2ui-color-on-background, #1c1917);
            font-family: var(--a2ui-font-family, inherit);
            font-size: var(--a2ui-font-size-sm, 0.925rem);
          }
          .a2ui-composer h1, .a2ui-composer h2, .a2ui-composer h3, .a2ui-composer h4 {
            margin: 0 0 0.5rem; letter-spacing: 0.02em;
          }
          .a2ui-composer h1 { text-transform: uppercase; font-size: 1.35rem; }
          .a2ui-composer h3 { font-size: 1rem; text-transform: uppercase; }
          .a2ui-composer h4 { font-size: 0.9rem; }
          .a2ui-composer-card {
            background: var(--ac-surface);
            border: 2px solid var(--ac-border);
            border-radius: var(--ac-radius);
            box-shadow: 3px 3px 0 var(--ac-border);
            padding: 1rem;
          }
          .a2ui-composer-btn {
            display: inline-block; cursor: pointer;
            background: var(--ac-primary); color: var(--ac-on-primary);
            border: 2px solid var(--ac-border);
            border-radius: var(--ac-radius);
            box-shadow: 2px 2px 0 var(--ac-border);
            padding: 0.3rem 0.8rem; font-weight: 700;
            font-size: var(--a2ui-font-size-xs, 0.8rem); text-transform: uppercase;
          }
          .a2ui-composer-btn--ghost { background: var(--ac-surface); color: inherit; }
          .a2ui-composer-grid { display: grid; gap: 1.25rem; margin-top: 1.25rem;
            grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr); }
          @media (max-width: 60rem) { .a2ui-composer-grid { grid-template-columns: minmax(0, 1fr); } }
          .a2ui-composer-input, .a2ui-composer select, .a2ui-composer textarea {
            width: 100%; box-sizing: border-box;
            border: 2px solid var(--ac-border); border-radius: var(--ac-radius);
            background: var(--ac-surface); color: inherit;
            font: inherit; padding: 0.3rem 0.5rem;
          }
          .a2ui-composer-field { margin: 0.5rem 0; }
          .a2ui-composer-field > label {
            display: block; font-weight: 700; font-size: var(--a2ui-font-size-xs, 0.75rem);
            text-transform: uppercase; margin-bottom: 0.15rem;
          }
          .a2ui-composer-row { border-top: 2px dashed var(--ac-border); padding-top: 0.75rem; margin-top: 0.75rem; }
          .a2ui-composer-rowhead { display: flex; justify-content: space-between; align-items: center; }
          .a2ui-composer-panel { margin-top: 1rem; }
          .a2ui-composer-errors { border-color: var(--ac-danger); box-shadow: 3px 3px 0 var(--ac-danger); }
          .a2ui-composer-errors li strong { color: var(--ac-danger); }
          .a2ui-composer-rejections { border-color: var(--ac-warn); box-shadow: 3px 3px 0 var(--ac-warn); }
          .a2ui-composer ul { margin: 0.25rem 0; padding-left: 1.1rem; }
          .a2ui-composer .meta { opacity: 0.75; font-size: var(--a2ui-font-size-xs, 0.8rem); }
          .a2ui-composer-browse { display: grid; gap: 1rem; margin-top: 1.25rem;
            grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr)); }
          .a2ui-composer-toolbar { display: flex; align-items: center; gap: 0.75rem; margin-top: 1.25rem; }
          .a2ui-composer-section { border: 2px solid var(--ac-border); border-radius: var(--ac-radius);
            margin: 1rem 0 0; padding: 0.75rem; }
          .a2ui-composer-section > legend { font-weight: 700; text-transform: uppercase;
            font-size: var(--a2ui-font-size-xs, 0.75rem); padding: 0 0.4rem; }
        </style>
        <header>
          <h1>Surface editor</h1>
          <p class="meta">
            Browse a declared surface, import it into the dynamic spec, edit with live
            validation, preview the resolve, export the standalone module.
          </p>
        </header>
        <%= if @page == :browse do %>
          <.browse_page surfaces={@surfaces} />
        <% else %>
          <.editor_page
            imported={@imported}
            sections={@sections}
            spec={@spec}
            resource_options={@resource_options}
            rejections={@rejections}
            errors={@errors}
            surface={@surface}
            export={@export}
            export_module={@export_module}
          />
        <% end %>
      </div>
      """
    end

    def browse_page(assigns) do
      ~H"""
      <section class="a2ui-composer-browse" aria-label="Surfaces">
        <div
          :for={{surface, index} <- Enum.with_index(@surfaces)}
          class="a2ui-composer-card"
          id={"composer-surface-#{index}"}
        >
          <h2>{surface.name}</h2>
          <p class="meta">
            {surface.resource && "resource: #{surface.resource}" || "no a2ui section"}
            {surface.title && " · " <> surface.title || ""}
          </p>
          <button
            type="button"
            class="a2ui-composer-btn"
            phx-click="import"
            phx-value-module={inspect(surface.module)}
          >
            Import
          </button>
        </div>
      </section>
      """
    end

    def editor_page(assigns) do
      ~H"""
      <div class="a2ui-composer-toolbar">
        <button type="button" class="a2ui-composer-btn a2ui-composer-btn--ghost" phx-click="reset">
          ← Browse
        </button>
        <span class="meta">imported from {imported_module(@imported)}</span>
      </div>
      <div class="a2ui-composer-grid">
        <div>
          <.rejections_panel rejections={@rejections} />
          <section class="a2ui-composer-card a2ui-composer-panel" aria-label="Spec editor">
            <h3>Spec</h3>
            <form phx-change="validate" id="composer-spec-form">
              <div class="a2ui-composer-field">
                <label for="composer-spec-resource">Resource</label>
                <select id="composer-spec-resource" name="spec[resource]">
                  <option value="">—</option>
                  <option
                    :for={name <- @resource_options}
                    value={name}
                    selected={name == @spec["resource"]}
                  >
                    {name}
                  </option>
                </select>
              </div>
              <div class="a2ui-composer-field">
                <label for="composer-spec-title">Title</label>
                <input id="composer-spec-title" name="spec[title]" type="text" value={@spec["title"] || ""} />
              </div>
              <.section_editor :for={section <- @sections} section={section} spec={@spec} />
            </form>
          </section>
        </div>
        <div>
          <.errors_panel errors={@errors} />
          <.preview_pane surface={@surface} />
          <.export_pane export={@export} export_module={@export_module} />
        </div>
      </div>
      """
    end

    defp imported_module(imported), do: imported || "—"

    def rejections_panel(assigns) do
      ~H"""
      <section
        :if={@rejections != []}
        class="a2ui-composer-card a2ui-composer-rejections a2ui-composer-panel"
        aria-label="Import rejections"
      >
        <h3>Import rejections</h3>
        <p class="meta">
          Declared features the spec vocabulary cannot carry — kept in the promoted
          module, never silently dropped:
        </p>
        <ul>
          <li :for={message <- AshA2ui.Dynamic.Importer.Rejection.messages(@rejections)}>
            {message}
          </li>
        </ul>
      </section>
      """
    end

    def errors_panel(assigns) do
      ~H"""
      <section
        :if={@errors != []}
        class="a2ui-composer-card a2ui-composer-errors a2ui-composer-panel"
        aria-label="Validation errors"
      >
        <h3>Does not resolve</h3>
        <ul aria-live="polite">
          <li :for={error <- @errors}>
            <strong>{error.path}</strong> — {error.message}
          </li>
        </ul>
      </section>
      """
    end

    def preview_pane(assigns) do
      ~H"""
      <section
        :if={@surface}
        class="a2ui-composer-card a2ui-composer-panel"
        aria-label="Resolved preview"
        id="composer-preview"
      >
        <h3>Preview — resolves</h3>
        <p class="meta">
          id {@surface.surface_id} · resource {inspect(@surface.resource)}
          {title_text(@surface.title)}
        </p>
        <div :for={{component, index} <- Enum.with_index(preview_components(@surface))}>
          <h4 id={"composer-preview-component-#{index}"}>
            {component_title(component)}
          </h4>
          <p class="meta">{component_summary(component)}</p>
        </div>
        <div :for={query <- preview_queries(@surface)}>
          <h4>query {query.name}</h4>
          <p class="meta">{query_summary(query)}</p>
        </div>
        <div :for={field <- preview_fields(@surface)}>
          <h4>field {field.name}</h4>
          <p class="meta">{field_summary(field)}</p>
        </div>
        <div :for={action <- preview_actions(@surface)}>
          <h4>action {action.name}</h4>
          <p class="meta">{action_summary(action)}</p>
        </div>
        <div :for={context <- preview_contexts(@surface)}>
          <h4>context {context.name}</h4>
          <p class="meta">{context.resource && "resource: #{inspect(context.resource)}"}</p>
        </div>
        <p class="meta">{structural_note()}</p>
      </section>
      """
    end

    defp link_text(nil), do: nil
    defp link_text({surface, path}), do: "#{surface} via #{names(List.wrap(path))}"
    defp link_text(relationship), do: relationship

    defp title_text(nil), do: ""
    defp title_text(title), do: "· #{title}"

    defp field_summary(field) do
      Enum.join(
        List.flatten([
          opt_text("label", field.label),
          opt_text("widget", field.widget),
          opt_text("format", field.format),
          opt_text("order", field.order),
          list_text("source", field.source),
          opt_text("relationship", field.relationship),
          opt_text("link", link_text(field.link)),
          opt_text("links", field.links)
        ]),
        " · "
      )
    end

    def export_pane(assigns) do
      ~H"""
      <section
        :if={@export}
        class="a2ui-composer-card a2ui-composer-panel"
        aria-label="Export"
        id="composer-export"
      >
        <h3>Export — DSL source</h3>
        <p class="meta">module {@export_module}</p>
        <textarea
          id="composer-export-source"
          readonly
          rows="12"
          aria-label="Standalone module source"
        ><%= @export %></textarea>
        <p class="meta">{export_note()}</p>
      </section>
      """
    end

    # The section editor renders one collection (components, queries, ...)
    # as rows, one input per vocabulary key, exactly as `spec_schema/1`
    # declares it.
    def section_editor(assigns) do
      ~H"""
      <fieldset class="a2ui-composer-section" id={"composer-section-#{@section.key}"}>
        <legend>
          <strong>{@section.label}</strong>
        </legend>
        <div
          :for={{row, index} <- Enum.with_index(rows_of(@spec, @section))}
          class="a2ui-composer-row"
          id={"composer-#{@section.key}-#{index}"}
        >
          <div class="a2ui-composer-rowhead">
            <h4>{row_title(@section, row, index)}</h4>
            <button
              type="button"
              class="a2ui-composer-btn a2ui-composer-btn--ghost"
              phx-click="remove-row"
              phx-value-section={@section.key}
              phx-value-index={index}
            >
              Remove
            </button>
          </div>
          <.row_field
            :for={field <- @section.fields}
            section={@section}
            index={index}
            field={field}
            value={row[field.key]}
          />
        </div>
        <button
          type="button"
          class="a2ui-composer-btn a2ui-composer-btn--ghost"
          phx-click="add-row"
          phx-value-section={@section.key}
        >
          + Add {@section.singular}
        </button>
      </fieldset>
      """
    end

    def row_field(assigns) do
      assigns =
        assign(assigns,
          name: input_name(assigns.section.key, assigns.index, assigns.field.key),
          id: input_id(assigns.section.key, assigns.index, assigns.field.key),
          text: input_value(assigns.field.type, assigns.value),
          required: required?(assigns.section, assigns.field.key)
        )

      ~H"""
      <div class="a2ui-composer-field">
        <label for={@id}>
          {humanize(@field.key)}{required_text(@required)}
        </label>
        <select :if={@field.type == :select} id={@id} name={@name}>
          <option value="">—</option>
          <option :for={option <- @field.options} value={option} selected={selected?(option, @value)}>
            {option}
          </option>
        </select>
        <input :if={@field.type == :text} id={@id} name={@name} type="text" value={@text} />
        <input :if={@field.type == :number} id={@id} name={@name} type="number" value={@text} />
        <input :if={@field.type == :list} id={@id} name={@name} type="text" value={@text} />
        <span :if={@field.type == :checkbox}>
          <input type="hidden" name={@name} value="false" />
          <input id={@id} name={@name} type="checkbox" value="true" checked={@text == true} />
        </span>
        <textarea :if={@field.type == :json} id={@id} name={@name} rows="2"><%= @text %></textarea>
      </div>
      """
    end

    defp required_text(true), do: " *"
    defp required_text(false), do: ""
  end
end
