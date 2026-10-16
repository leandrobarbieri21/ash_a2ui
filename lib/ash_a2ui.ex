defmodule AshA2ui do
  @field %Spark.Dsl.Entity{
    name: :field,
    describe: """
    Per-field presentation overrides, shared across all components of the surface.
    """,
    examples: [
      """
      field :name do
        label "Provider Name"
        widget :text_field
      end
      """
    ],
    target: AshA2ui.Field,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the resource attribute/calculation/aggregate this field maps to."
      ],
      label: [
        type: :string,
        doc: "Human-readable label. Defaults to a humanized version of the field name."
      ],
      widget: [
        type: :atom,
        doc:
          "Widget override (e.g. `:text_field`, `:check_box`, `:choice_picker`, `:date_time_input`). Defaults via `AshA2ui.TypeMapper`."
      ],
      order: [
        type: :non_neg_integer,
        default: 0,
        doc: "Sort order of the field within components. Lower comes first."
      ],
      hidden: [
        type: :boolean,
        default: false,
        doc: "Hide this field from all components."
      ],
      format: [
        type: :atom,
        doc: "Named formatter hint (e.g. `:date`) applied when rendering values."
      ],
      relationship: [
        type: :atom,
        doc: """
        The `belongs_to` relationship this form field selects a record for. Only needed as
        an explicit override (e.g. action-argument fields); fields whose name matches a
        `belongs_to` relationship's `source_attribute` are inferred automatically.
        """
      ],
      option_label: [
        type: :atom,
        doc: """
        The destination attribute shown as the option label of a relationship select.
        Defaults to the first existing public attribute of `[:name, :title, :label,
        :username, :email]` on the destination, else its primary key.
        """
      ],
      option_value: [
        type: :atom,
        doc: """
        The destination attribute submitted as the option value of a relationship select.
        Defaults to the destination's primary key (required explicitly when that primary
        key is composite).
        """
      ],
      option_sort: [
        type: :atom,
        doc: """
        The destination attribute the options of a relationship select are sorted by
        (ascending). Defaults to the resolved `option_label`.
        """
      ],
      option_limit: [
        type: :pos_integer,
        default: 100,
        doc: """
        Maximum number of options loaded for a relationship select (and returned per
        `option_search` request). Non-searchable option sets larger than this are
        truncated — declare `option_search` for genuinely large sets.
        """
      ],
      option_search: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public string attributes of the destination searched (case-insensitive
        contains, OR'd) by the `"option_search"` client action. Non-empty turns the
        relationship select into a searchable select: a search input plus a result
        list refreshed through `/options/<field>`, instead of a static ChoicePicker.
        """
      ],
      source: [
        type: {:list, :atom},
        doc: """
        A relationship path (e.g. `[:user, :email]`) this table column reads its value
        through. Every step but the last must be a public relationship; the last must be
        a public attribute, calculation or aggregate of the final destination (a
        calculation terminal is loaded through the path — e.g. a decrypted display
        name). Source columns are table-only and not sortable.
        """
      ],
      link: [
        type:
          {:or,
           [
             :atom,
             {:tuple, [{:or, [:atom, :string]}, {:or, [:atom, {:list, :atom}]}]}
           ]},
        doc: """
        Renders this field as a reference link to another record. Either a public
        to-one relationship of the resource (`link :owner` — the link targets the
        loaded related record, so a target the actor cannot read is simply not
        linked), or `{surface_key, id_path}` for bare-id/polymorphic references
        (`link {:person, :subject_id}` — the id is read from `id_path`, a public
        attribute or a relationship path ending in one). Rows carry the link at the
        reserved `_links/<field>` key as `%{"surface", "recordId", "label"}` (plus
        `"href"` when `config :ash_a2ui, :open_surface_url` is set). The surface key
        of a relationship link comes from the configured `AshA2ui.LinkResolver`,
        which may also veto links per actor.
        """
      ],
      links: [
        type: :atom,
        doc: """
        Renders this field as a list of reference links over a public to-many
        relationship (`has_many` / `many_to_many`), e.g. `links :participants`.
        The field may be virtual (not an attribute) — its cell value is then the
        links' labels joined with ", ". Rows carry the list at `_links/<field>`.
        Table/detail only.
        """
      ],
      link_label: [
        type: :atom,
        doc: """
        The destination attribute/calculation used as each link's label for `link
        :relationship` and `links`. Defaults to the cell's own display value for
        single links (when it is not the bare foreign key), else the first public
        attribute of `[:name, :title, :label, :username, :email]` on the
        destination, else its primary key.
        """
      ]
    ]
  }

  @context %Spark.Dsl.Entity{
    name: :context,
    describe: """
    A named, surface-level record selection ("pick a user") whose selected
    record scopes other sections: tables reference it via `context_filter`,
    dependent contexts via `depends_on`, and `:detail` components render the
    selected record. Selection state lives at the reserved `/context/<name>`
    data-model path, option lists at `/options/<name>`, and the client
    interacts through the `"context_search"` / `"context_select"` /
    `"context_clear"` actions — the client only ever sends a record id, and
    every selection round-trips through an authorized read (dependency
    filters included).
    """,
    examples: [
      """
      context :user do
        resource MyApp.Accounts.User
        option_label :email
        option_search [:email, :name]
      end
      """,
      """
      context :practice do
        resource MyApp.Practices.Practice
        option_label :name
        depends_on :user
        depends_on_path [:memberships, :user_id]
        auto_select_single true
      end
      """
    ],
    target: AshA2ui.Context,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: """
        The name of the context: the `<name>` segment of the reserved
        `/context/<name>` and `/options/<name>` data-model paths, and how
        `context_filter` / `depends_on` / `:detail` components reference it.
        Must be unique across the surface's contexts, relationship-select
        fields and nested-form arguments (they share the `/options`
        namespace).
        """
      ],
      resource: [
        type: {:behaviour, Ash.Resource},
        required: true,
        doc: "The Ash resource whose records this context selects."
      ],
      label: [
        type: :string,
        doc: "Heading shown above the picker. Defaults to the humanized context name."
      ],
      option_label: [
        type: :atom,
        doc: """
        The attribute shown as the option/selection label. Defaults like a
        relationship select's `option_label` (first existing public attribute
        of `[:name, :title, :label, :username, :email]`, else the primary
        key).
        """
      ],
      option_value: [
        type: :atom,
        doc: """
        The attribute submitted as the selected value. Defaults to the
        resource's primary key (required explicitly when composite).
        """
      ],
      option_sort: [
        type: :atom,
        doc: "The attribute options are sorted by (ascending). Defaults to `option_label`."
      ],
      option_limit: [
        type: :pos_integer,
        default: 100,
        doc: "Maximum number of options loaded (and returned per `context_search`)."
      ],
      option_search: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public string attributes of the resource searched (case-insensitive
        contains, OR'd) by the `"context_search"` client action. Non-empty
        adds a search input to the emitted picker.
        """
      ],
      depends_on: [
        type: :atom,
        doc: """
        The context this one depends on: its options are filtered by the
        parent's selected value (through `depends_on_path`), its options are
        empty while the parent is unselected, and its selection is cleared
        whenever the parent changes.
        """
      ],
      depends_on_path: [
        type: {:list, :atom},
        doc: """
        The relationship path on this context's resource whose terminal
        attribute must equal the parent context's selected value, e.g.
        `[:memberships, :user_id]` — every step but the last a public
        relationship, the last a public attribute of the final destination
        (to-many paths get `exists` semantics). Required with `depends_on`.
        """
      ],
      auto_select_single: [
        type: :boolean,
        default: false,
        doc: """
        Automatically select this context when a parent selection leaves it
        exactly one option (dependent contexts only).
        """
      ],
      picker: [
        type: :boolean,
        default: true,
        doc: """
        Whether to emit a picker section for this context. Set `false` for
        contexts selected only through a table's `select_context` row button
        (master/detail) — no options are loaded or rendered.
        """
      ]
    ]
  }

  @preset %Spark.Dsl.Entity{
    name: :preset,
    describe: """
    A named, server-side composite filter the client selects by name via the
    `"preset"` query parameter — the predicates themselves never travel over
    the wire. Declare either a declarative keyword `filter` (conditions ANDed;
    `nil` means `is_nil`, a list means membership) or a dedicated
    `read_action` as an escape hatch for predicates the keyword form can't
    express.
    """,
    examples: [
      """
      preset :pending do
        filter status: :pending, deleted_at: nil
      end
      """,
      """
      preset :deleted do
        read_action :deleted
      end
      """
    ],
    target: AshA2ui.Preset,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the preset, sent by the client as the `\"preset\"` query parameter."
      ],
      filter: [
        type: :keyword_list,
        doc: """
        Keyword conditions ANDed onto the table's base query. Keys are public
        attributes or public expression calculations; `nil` values mean
        `is_nil`, list values mean membership, anything else is equality.
        """
      ],
      read_action: [
        type: :atom,
        doc: """
        A read action used instead of the table's `read_action` while this
        preset is selected — the escape hatch for predicates the keyword
        `filter` form can't express. Mutually exclusive with `filter`.
        """
      ]
    ]
  }

  @query %Spark.Dsl.Entity{
    name: :query,
    describe: """
    A named, server-enforced allowlist for search, sorting, equality filters,
    and pagination, referenced by a `:table` component via its `query` option.
    Client `"query"` actions are validated against these lists — anything not
    declared here is rejected before Ash is called.
    """,
    examples: [
      """
      query :default do
        search_fields [:subject, [:author, :email]]
        sortable [:subject, :inserted_at]
        filters [:status]
        default_sort inserted_at: :desc
        page_size 25
        max_page_size 100

        preset :pending do
          filter status: :pending
        end
      end
      """
    ],
    target: AshA2ui.Query,
    args: [:name],
    entities: [presets: [@preset]],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the query, referenced by a table component's `query` option."
      ],
      search_fields: [
        type: {:list, {:or, [:atom, {:list, :atom}]}},
        default: [],
        doc: """
        Fields searched with a case-insensitive contains, OR'd together. Each
        entry is a public string attribute (`:subject`) or a relationship path
        to one (`[:author, :email]` — every step but the last a public
        relationship, the last a public string attribute of the destination).
        Empty means search is rejected.
        """
      ],
      sortable: [
        type: {:list, :atom},
        default: [],
        doc: "Public attributes the client may sort by. Anything else is rejected."
      ],
      range_filters: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public attributes (or expression-backed public calculations) of
        orderable types (date/datetime/numeric) the client may range-filter
        on through `/query/ranges/<field>` (`{"from", "to"}`, each optional).
        Anything else is rejected.
        """
      ],
      filters: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public attributes or public expression calculations the client may
        equality-filter on. Anything else is rejected.
        """
      ],
      default_preset: [
        type: :atom,
        doc: "The preset applied when the client selects none. Must name a declared preset."
      ],
      default_sort: [
        type: {:list, {:tuple, [:atom, {:in, [:asc, :desc]}]}},
        default: [],
        doc:
          "The sort applied when the client requests none, e.g. `default_sort inserted_at: :desc`."
      ],
      page_size: [
        type: :pos_integer,
        default: 25,
        doc: "The page size used when the client requests none."
      ],
      max_page_size: [
        type: :pos_integer,
        default: 100,
        doc: "The hard upper bound client-requested page sizes are clamped to."
      ]
    ]
  }

  @nested_form %Spark.Dsl.Entity{
    name: :nested_form,
    describe: """
    A nested relationship form inside a `:form` component, named by the
    **action argument** a `manage_relationship` change consumes on the form's
    create/update action. The interaction mode is inferred from that change's
    options (via `Ash.Changeset.ManagedRelationshipHelpers`): lookups
    (`on_lookup`, e.g. `type: :append_and_remove`) render as **pick_existing**
    (a select adding existing records, current rows with remove buttons);
    otherwise creates (`on_no_match: :create`, e.g. `type: :direct_control`)
    render as **create_inline** (sub-form rows appended to the argument's
    array of maps).
    """,
    examples: [
      """
      nested_form :notes do
        fields [:body, :rating]
      end
      """,
      """
      nested_form :tags do
        option_search [:name]
      end
      """
    ],
    target: AshA2ui.NestedForm,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: """
        The action argument this nested form edits. Must be consumed by a
        `manage_relationship` change on every create/update action the form
        submits (verified at compile time).
        """
      ],
      label: [
        type: :string,
        doc: "Heading shown above the nested rows. Defaults to the humanized argument name."
      ],
      fields: [
        type: {:list, :atom},
        doc: """
        Destination attributes rendered as sub-form inputs (create_inline
        mode only). Omit to infer from the destination action the
        `manage_relationship` change creates through, minus the relationship's
        destination attribute.
        """
      ],
      option_label: [
        type: :atom,
        doc: """
        The destination attribute shown as the label of pick_existing options
        and rows. Defaults like the `field` entity's `option_label`.
        """
      ],
      option_value: [
        type: :atom,
        doc: """
        The destination attribute submitted as the pick_existing value.
        Defaults to the destination's primary key (required explicitly when
        composite).
        """
      ],
      option_sort: [
        type: :atom,
        doc: """
        The destination attribute pick_existing options are sorted by
        (ascending). Defaults to the resolved `option_label`.
        """
      ],
      option_limit: [
        type: :pos_integer,
        default: 100,
        doc: """
        Maximum number of pick_existing options loaded (and returned per
        `option_search` request).
        """
      ],
      option_search: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public string attributes of the destination searched (case-insensitive
        contains, OR'd) by the `"option_search"` client action. Non-empty
        replaces the pick_existing ChoicePicker with a search input plus a
        result list refreshed through `/options/<argument>`.
        """
      ]
    ]
  }

  @group %Spark.Dsl.Entity{
    name: :group,
    describe: """
    A labeled section of form fields laid out in an N-column grid, declared
    inside a `:form` component. Grouped fields render inside the section (in
    the group's declaration order, chunked into rows of `columns`); ungrouped
    fields keep rendering individually. A group renders at the position of
    its first member in the form's field order.
    """,
    examples: [
      """
      group :scheduling do
        label "Scheduling"
        columns 2
        fields [:trial_days, :expires_at]
      end
      """
    ],
    target: AshA2ui.Group,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the group. Group names must be unique within the form."
      ],
      label: [
        type: :string,
        doc: "Heading shown above the group. Defaults to the humanized group name."
      ],
      columns: [
        type: :pos_integer,
        default: 1,
        doc: """
        Number of grid columns the group's fields are laid out in. Fields are
        chunked into rows of this many equal-weight columns, in the group's
        declaration order; the last row is padded with empty spacer columns.
        """
      ],
      fields: [
        type: {:list, :atom},
        required: true,
        doc: """
        The form fields this group renders. Every entry must be one of the
        form component's fields, and no field may belong to more than one
        group (verified at compile time).
        """
      ]
    ]
  }

  @step %Spark.Dsl.Entity{
    name: :step,
    describe: """
    One step of a wizard: declared (in order) inside a `:form` component,
    splitting its fields across pages over the one form and the one Ash
    action. Next validates the current and earlier steps server-side
    without writing anything; the last step's button is the usual submit.
    A `review?` step has no fields and renders a read-only summary of the
    form. Every form field belongs to exactly one step, and a stepped form
    has at least two steps. Steps are not combined with `group` or
    `nested_form` entities on the same form. See the Wizard Steps topic.
    """,
    examples: [
      """
      step :who do
        label "Who"
        fields [:name, :email]
      end

      step :what do
        fields [:role, :team]
      end

      step :confirm do
        review? true
      end
      """
    ],
    target: AshA2ui.Step,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the step. Step names must be unique within the form."
      ],
      label: [
        type: :string,
        doc: "Heading of the step (and its progress entry). Defaults to the humanized step name."
      ],
      description: [
        type: :string,
        doc: "Optional help text rendered under the step heading."
      ],
      fields: [
        type: {:list, :atom},
        default: [],
        doc: """
        The form fields this step renders, in order. Every entry must be one
        of the form component's fields, and every form field must belong to
        exactly one step (verified at compile time).
        """
      ],
      review?: [
        type: :boolean,
        default: false,
        doc: """
        Render a read-only summary of every form field instead of inputs.
        Only allowed on the last step, and only without `fields`.
        """
      ]
    ]
  }

  @row_layout %Spark.Dsl.Entity{
    name: :row_layout,
    describe: """
    Card-style record layout for a `:table` component. Each record renders as
    a `Card` with a header row — the `title` field (with the row's actions
    alongside, and the `badge` field's display text when declared) — above an
    N-column grid of caption-labeled `meta` values. Without a `row_layout`,
    records keep rendering as flat rows of cells.
    """,
    examples: [
      """
      row_layout do
        title :name
        badge :is_active
        badge_text true: "Active", false: "Inactive"
        meta [:slug, :referral_type, :trial_days]
        columns 3
      end
      """
    ],
    target: AshA2ui.RowLayout,
    schema: [
      title: [
        type: :atom,
        required: true,
        doc: "The field rendered as the card's heading. Must be one of the table's fields."
      ],
      badge: [
        type: :atom,
        doc: """
        A field rendered as a status badge in the card header. Its display
        text is served per row at the reserved `_badge_<field>` row key:
        the `badge_text` mapping when the value matches, else the humanized
        value.
        """
      ],
      badge_text: [
        type: :keyword_list,
        default: [],
        doc: """
        Display text per badge value, matched against atom (including
        boolean) values — e.g. `badge_text true: "Active", false: "Inactive"`.
        Unmatched values fall back to the humanized value.
        """
      ],
      badge_tones: [
        type: :keyword_list,
        default: [],
        doc: """
        Semantic tone per badge value, matched like `badge_text` — e.g.
        `badge_tones true: :success, false: :neutral`. Tones are
        `:neutral`, `:info`, `:success`, `:warning`, `:danger` and `:accent`;
        renderers map them onto theme tokens. Unmatched values render
        `:neutral`. Served per row at the reserved `_badge_tone_<field>` key
        (the admin catalog's badge column binds it as `tonePath`).
        """
      ],
      meta: [
        type: {:list, :atom},
        doc: """
        The fields rendered in the card's labeled metadata grid, in order.
        Defaults to the table's fields minus `title` and `badge`.
        """
      ],
      columns: [
        type: :pos_integer,
        default: 2,
        doc: """
        Number of grid columns the metadata values are laid out in. Values
        are chunked into rows of this many equal-weight columns; the last
        row is padded with empty spacer columns.
        """
      ]
    ]
  }

  @table_sections %Spark.Dsl.Entity{
    name: :sections,
    describe: """
    Dynamic table sets: declares this `:table` component as a **template**
    expanded at runtime into one concrete table per record of a `source`
    resource. Each section's table reads the surface resource scoped by
    `scope_by == <section record's value>`, is headed by the section
    record's `label`, and follows the multi-table data-model contract under
    its runtime name `<component_key>_<sanitized value>`
    (`/records/<runtime name>`, `/query/<runtime name>`). The source read is
    actor-scoped and authorized like any other read. A surface with a
    sectioned table is always a multi-table surface, regardless of how many
    sections the source yields at runtime.

    Without a `source`, the sections are the enumerated values of `scope_by`
    — an `Ash.Type.Enum`'s values or the attribute's `one_of` constraint, in
    declaration order — and no read is issued to enumerate them. `values`
    picks a subset and an order, `labels` overrides headings (otherwise the
    enum's label or the humanized value). Combined with `display :board` on
    the table this renders a board: one lane per value, side by side (see the
    multi-section surfaces topic).
    """,
    examples: [
      """
      sections do
        source MyApp.Dictionary.Bucket
        scope_by :bucket_id
        label :name
      end
      """,
      """
      sections do
        scope_by :status
        values [:open, :claimed, :completed]
        labels open: "To do"
      end
      """
    ],
    target: AshA2ui.Sections,
    schema: [
      source: [
        type: {:behaviour, Ash.Resource},
        doc: """
        The Ash resource whose records enumerate the sections at render time.
        Optional: without it the sections are the enumerated values of
        `scope_by` (see `values` and `labels`).
        """
      ],
      scope_by: [
        type: :atom,
        required: true,
        doc: """
        The public attribute of the **table's** resource each section's reads
        filter on (`scope_by == <section record's value attribute>`). Without a
        `source` it must have enumerable values: an `Ash.Type.Enum` type or a
        `one_of` constraint.
        """
      ],
      values: [
        type: {:list, {:or, [:atom, :string]}},
        doc: """
        Source-less sections only: the enumerated values of `scope_by` that
        become sections, in this order (`values [:open, :claimed]`). Each
        must be one of the enumerated values. Defaults to all of them, in
        declaration order.
        """
      ],
      labels: [
        type: :keyword_list,
        default: [],
        doc: """
        Source-less sections only: heading overrides per value
        (`labels open: "To do"`). Sections without an entry are headed by
        the enum's label, else the humanized value.
        """
      ],
      label: [
        type: :atom,
        doc: """
        The source attribute shown as each section's table heading (requires
        `source`). Defaults like an option label (first existing public attribute of `[:name,
        :title, :label, :username, :email]`, else the section value).
        """
      ],
      value: [
        type: :atom,
        doc: """
        The source attribute providing each section's scope value (matched
        against `scope_by`) and its runtime name (requires `source`). Defaults to the source's
        primary key (required explicitly when composite).
        """
      ],
      read_action: [
        type: :atom,
        doc:
          "The source read action enumerating the sections (requires `source`). Defaults to the primary read."
      ],
      sort: [
        type: :atom,
        doc: """
        The source attribute sections are ordered by (ascending; requires
        `source`). Defaults to the resolved `label`.
        """
      ],
      limit: [
        type: :pos_integer,
        default: 50,
        doc:
          "Maximum number of sections rendered (the source read's limit). Without a source it caps the lanes, not the cards per lane, and may not be below the lane count."
      ]
    ]
  }

  @editable %Spark.Dsl.Entity{
    name: :editable,
    describe: """
    Inline cell editing for a `:table` component: the listed fields render as
    in-row inputs with a per-cell Save button dispatching the `"edit_cell"`
    client action — the server runs `update_action` on the identified record
    with just that field's value (cast against the action like any client
    input). On v1.0 surfaces the per-action `actionResponse` handshake gives
    each cell pending→settled feedback; validation errors are mirrored into
    the failing row's reserved `_error_<field>` key (rendered next to the
    cell) alongside the standard `/errors/<field>` write. Not supported
    together with a `row_layout` (card rows render read-only meta values).
    """,
    examples: [
      """
      editable do
        fields [:replacement]
        update_action :update_replacement
      end
      """
    ],
    target: AshA2ui.Editable,
    schema: [
      fields: [
        type: {:list, :atom},
        required: true,
        doc: """
        The table fields rendered as editable cells. Each must be one of the
        table's fields and accepted by the resolved `update_action`.
        """
      ],
      update_action: [
        type: :atom,
        doc: """
        The update action a cell commit runs (with only the edited field's
        value). Defaults to the resource's primary update.
        """
      ]
    ]
  }

  @export %Spark.Dsl.Entity{
    name: :export,
    describe: """
    CSV file export for a `:table` or `:report` component (**v1.0-only** —
    delivery rides the `callFunction` channel): renders an "Export CSV"
    button dispatching the `"export"` client action; the server re-runs the
    component's data (a table honors its current query state and context
    scope; a report its current params) and answers with a `downloadFile`
    callFunction carrying a base64 `text/csv` data URL (frozen contract —
    see `AshA2ui.Export`). With `column_select`, per-column checkboxes bound
    under the reserved `/export/<name>/columns/<field>` paths let the user
    pick the exported columns.
    """,
    examples: [
      """
      export do
        filename "misspellings.csv"
        column_select true
      end
      """
    ],
    target: AshA2ui.Export,
    schema: [
      filename: [
        type: :string,
        doc: ~s(The downloaded file's name. Defaults to "<component name>.csv".)
      ],
      columns: [
        type: {:list, :atom},
        doc: """
        The exportable columns (header order). Each must be one of the
        component's fields. Defaults to all of the component's fields.
        """
      ],
      column_select: [
        type: :boolean,
        default: false,
        doc: """
        Render one checkbox per exportable column (bound to the reserved
        `/export/<name>/columns/<field>` paths); the export includes only
        the checked columns.
        """
      ],
      limit: [
        type: :pos_integer,
        default: 10_000,
        doc: """
        Row cap of a table export (the export read's page size — a table
        export ignores the on-screen pagination but keeps search, filters
        and preset). Ignored on reports.
        """
      ]
    ]
  }

  @component %Spark.Dsl.Entity{
    name: :component,
    describe: """
    A UI component of the surface. `:table` renders records from a read action;
    `:form` renders create/update forms; `:detail` renders the record selected
    into a `context` as a read-only field grid; `:report` renders the computed
    rows of a declared generic action (aggregate/report queries — see the
    `action` and `params` options). A surface may declare several `:table`,
    `:detail` or `:report` components (sections) by giving each one a
    distinguishing name via the optional second argument, e.g.
    `component :table, :new_items do ... end`.
    """,
    examples: [
      """
      component :table do
        fields [:name, :inserted_at]
        read_action :read
        row_actions [:edit]
      end
      """,
      """
      component :table, :new_items do
        fields [:name]
        read_action :new_items
        row_actions [:approve]
      end
      """
    ],
    target: AshA2ui.Component,
    args: [:name, {:optional, :as}],
    entities: [
      nested_forms: [@nested_form],
      groups: [@group],
      steps: [@step],
      row_layout: [@row_layout],
      sections: [@table_sections],
      editable: [@editable],
      export: [@export]
    ],
    singleton_entity_keys: [:row_layout, :sections, :editable, :export],
    schema: [
      name: [
        type: {:one_of, [:table, :form, :detail, :report]},
        required: true,
        doc: "The kind of component. One of `:table`, `:form`, `:detail` or `:report`."
      ],
      as: [
        type: :atom,
        doc: """
        The distinguishing name of this component on surfaces with several
        `:table` (or `:detail` / `:report`) components (e.g.
        `component :table, :new_items`). Optional — an unnamed component is
        named by its kind. Names must be unique across the surface's
        components; `:form` components cannot be named.
        """
      ],
      fields: [
        type: {:list, :atom},
        doc:
          "Fields shown by this component. Omit to infer (public attributes for tables, action accepts for forms). On `:report` components: the column allowlist, required — each entry is a key of the returned row maps, rendered in this order."
      ],
      resource: [
        type: :atom,
        doc: """
        A **related table**: the Ash resource this `:table` reads, when it is
        not the surface's own (`component :table, :messages do resource
        MyApp.Message; context_filter thread_id: :thread; require_context
        [:thread] end`). Its fields, `read_action`, `query`, `context_filter`
        keys, `source` paths and links are resolved against this resource,
        read as the surface's actor like every other table. Related tables
        are read-only: no `row_actions`, `editable` or `sections`, and a
        `select_context` must name a context over this resource. Defaults to
        the surface resource.
        """
      ],
      read_action: [
        type: :atom,
        doc: "The read action used to load records (tables). Defaults to the primary read."
      ],
      action: [
        type: :atom,
        doc: """
        The generic Ash action a `:report` component runs (actor-scoped,
        authorized like any other invocation). Must return a list of row
        maps; the declared `fields` select and order the rendered columns.
        Required on `:report` components.
        """
      ],
      params: [
        type: {:list, :atom},
        doc: """
        The arguments of a `:report` component's `action` rendered as inputs
        (bound to the reserved `/report/<name>/params/<param>` paths and
        submitted by the Run button). Defaults to all of the action's
        arguments, in declaration order.
        """
      ],
      create_action: [
        type: :atom,
        doc: "The create action submitted by the form."
      ],
      update_action: [
        type: :atom,
        doc: "The update action submitted by the form."
      ],
      row_actions: [
        type: {:list, :atom},
        default: [],
        doc: "Actions rendered as per-row buttons (tables)."
      ],
      bulk_actions: [
        type: {:list, :atom},
        default: [],
        doc: """
        Update, destroy or generic actions run over a row selection (tables).
        Each row gets a CheckBox bound to its reserved `_selected` key, and a
        toolbar above the list carries one button per bulk action plus
        "Select page" and "Clear". The server re-reads the selected ids
        through the table's read under its active query preset, with its
        scope, as the actor, and runs the action once per record;
        `visible_when`, `via` and `refreshes` on the action's `action` entity
        apply per record. A generic bulk action must declare a `:record_id`
        argument. No `prompt_fields`; not on related tables. See the Bulk
        Actions topic.
        """
      ],
      display: [
        type: {:one_of, [:list, :board]},
        default: :list,
        doc: """
        How a sectioned `:table` lays out its sections: `:list` (default)
        stacks them; `:board` renders them side by side as lanes, each with
        its heading and total, card list and pagination. `:board` requires a
        `sections` block and a `row_layout`. Cards move between lanes only
        through row actions (transitions); there is no drag-and-drop.
        """
      ],
      query: [
        type: :atom,
        doc:
          "Name of a `query` entity providing server-enforced search/sort/filter/pagination (tables)."
      ],
      context_filter: [
        type: :keyword_list,
        default: [],
        doc: """
        Context scoping for a `:table`: keys are public attributes of the
        table's resource, values are declared context names
        (`context_filter user_id: :user`). Each context with a selected value
        ANDs `attribute == selected value` onto the table's reads; unselected
        contexts contribute nothing.
        """
      ],
      require_context: [
        type: {:list, :atom},
        default: [],
        doc: """
        Context names (a subset of this table's `context_filter` contexts) of
        which **at least one** must be selected before the table reads —
        otherwise it renders no records (and no read is executed).
        """
      ],
      select_context: [
        type: :atom,
        doc: """
        A declared context (over the same resource as this table) the table's
        per-row "Select <context>" button selects into — the master/detail
        pattern: the button sends `"context_select"` with the row's record id,
        and the detail panels and related tables bound to the context follow.
        On a board (`display :board`) every card carries the button; other
        sectioned tables do not take `select_context`.
        """
      ],
      context: [
        type: :atom,
        doc: """
        The declared context a `:detail` component renders: its selected
        record's fields are written to `/detail/<context>` and displayed as a
        read-only label/value grid. Required on `:detail` components.
        """
      ]
    ]
  }

  @action %Spark.Dsl.Entity{
    name: :action,
    describe: """
    Per-action metadata: the button label, refresh targets, argument
    prompts, per-row visibility conditions, and host-delegated dispatch
    (`via`).
    """,
    examples: [
      """
      action :approve do
        refreshes [:new_items]
        visible_when status: :pending
      end
      """,
      """
      action :decline do
        prompt_fields [:notes]
        prompt_title "Decline referral"
      end
      """,
      """
      action :confirm_merge do
        label "Confirm match"
      end
      """,
      """
      action :check_in do
        # The host's engine facade completes the work (it invokes the Ash
        # action itself); the surface only renders the outcome.
        via {MyApp.Tasks, :check_in, ["board"]}
      end
      """
    ],
    target: AshA2ui.Action,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc:
          "The Ash action this metadata applies to (a row action, or the form's create/update action)."
      ],
      label: [
        type: :string,
        doc: """
        The text of this action's buttons — its row button, bulk toolbar
        button, admin `rowActions` entry and (unless `prompt_title` is set)
        its prompt heading — and the name in its bulk status line. A plain
        string, so a host can pass translated text. Defaults to the
        humanized action name.
        """
      ],
      refreshes: [
        type: {:list, :atom},
        doc: """
        The table components refreshed after this action succeeds, by
        component name (`refreshes [:new_items]`; the unnamed table is
        `:table`). `[]` refreshes no table. Omitted (and for actions without
        an `action` entity) every table is refreshed (the default).
        """
      ],
      prompt_fields: [
        type: {:list, :atom},
        default: [],
        doc: """
        Arguments/accepts of the Ash action collected from the user in a
        per-row Modal prompt before the action is invoked (row actions only).
        Clicking the row button opens the Modal instead of invoking directly;
        its confirm button sends `invoke` with a `"values"` map.
        """
      ],
      prompt_title: [
        type: :string,
        doc: """
        Heading shown inside the prompt Modal. Defaults to the action's
        `label`, else the humanized action name.
        """
      ],
      visible_when: [
        type: :keyword_list,
        default: [],
        doc: """
        Per-record conditions gating this row action, ANDed together
        (`visible_when status: :pending`). Keys are public attributes or
        public expression calculations; `nil` values mean `is_nil`, list
        values mean membership, anything else is equality. Enforced
        server-side on every invoke; rendering hides the button per row.
        A bulk action applies the same check to each selected record and
        counts the records that fail it as skipped.
        """
      ],
      via: [
        type: :mfa,
        doc: """
        Delegate this row action to a host-provided function instead of
        running the mapped Ash action directly (`via {MyApp.Tasks, :check_in, ["board"]}`).
        The framework knows nothing about the host's engine: at click time the
        handler fetches the row's record (with any `visible_when` condition
        calculations loaded, enforced as always) and calls

            apply(module, function, [context | extra_args])

        where `context` is a map carrying the dispatch state:

          * `:record` — the row's record, loaded as the surface loads it
          * `:actor` — the actor the host passed to the handler (`nil` when none)
          * `:tenant` — the tenant the host passed to the handler
          * `:action` — the row-action name (atom)
          * `:surface_id` — the surface's id
          * `:selected` — the surface's context selections (see
            `AshA2ui.ContextRunner.selected/2`; `%{}` without contexts)

        The MFA returns the same shape the direct path does —
        `:ok` | `{:ok, term}` | `{:error, Ash.Error.t()}` (any Ash error class
        or exception; mapped exactly like a direct invocation's failure:
        `Ash.Error.Forbidden` to a not-authorized status, validation errors to
        `/errors/<field>`) — and the result renders through the standard
        success/error channels unchanged: success refreshes the tables
        (honoring `refreshes`) and reports the action's status text; errors go
        to the typed `/ui/feedback` error. The
        client is unaware `via` exists: the emitted button is the ordinary
        `invoke` row action, addressed by the same action name. The named Ash
        action must still exist (it remains the row-action allowlist entry and
        the button's label source); `via` only reroutes the dispatch.
        Mutually exclusive with `prompt_fields` (the prompt exists to collect
        values cast against the direct Ash action). Row and bulk actions
        only; a bulk action calls the MFA once per selected record.
        """
      ]
    ]
  }

  @a2ui %Spark.Dsl.Section{
    name: :a2ui,
    describe: """
    Declare an A2UI surface for this resource (or, in a standalone UI module,
    for the resource named by `for_resource`).
    """,
    examples: [
      """
      a2ui do
        surface_id "promotions_providers"

        component :table do
          fields [:name, :inserted_at]
          read_action :read
        end

        component :form do
          fields [:name]
          create_action :create
          update_action :update
        end

        field :name do
          label "Provider Name"
        end
      end
      """
    ],
    schema: [
      surface_id: [
        type: :string,
        doc:
          "Unique id of the A2UI surface. Defaults to the underscored short name of the resource."
      ],
      title: [
        type: :string,
        doc: """
        The surface's heading — what this page is a page *of*. Defaults to the
        humanized resource short name, which is singular and named after a
        module rather than after the thing: a surface over `Legacy.User` is
        headed "User" though it is a list of users from another application's
        estate. Set it to the words the host already uses in its own navigation.
        """
      ],
      record_label: [
        type: :string,
        doc: """
        The singular noun for one record, used by the derived task labels —
        "Create <record_label>", "Edit <record_label>", "No <record_label>
        records yet." Defaults to the humanized resource short name. Set it
        where the module name is not the word a reader would use.
        """
      ],
      spec_version: [
        type: {:in, ["0.9.1", "1.0"]},
        default: "0.9.1",
        doc:
          ~S(The A2UI protocol version the surface speaks: "0.9.1" - the default - or "1.0" ) <>
            ~S(recommended for new surfaces — inline createSurface, per-action actionResponse ) <>
            ~S(feedback; requires a v1.0-capable renderer or the shipped hook. See the A2UI 1.0 topic.)
      ],
      for_resource: [
        type: {:behaviour, Ash.Resource},
        doc:
          "The Ash resource this surface renders. Only used (and required) in standalone UI modules (`use AshA2ui.Standalone`)."
      ],
      add_render_action?: [
        type: :boolean,
        default: true,
        doc:
          "Whether to automatically add a generic `render_a2ui` action returning the surface's A2UI messages. Ignored in standalone UI modules."
      ]
    ],
    entities: [
      @context,
      @query,
      @component,
      @field,
      @action
    ]
  }

  @sections [@a2ui]

  @transformers [
    AshA2ui.Transformers.InferFields,
    AshA2ui.Transformers.AddRenderAction
  ]

  @verifiers [
    AshA2ui.Verifiers.VerifyComponents,
    AshA2ui.Verifiers.VerifyLayouts,
    AshA2ui.Verifiers.VerifySteps,
    AshA2ui.Verifiers.VerifyContexts,
    AshA2ui.Verifiers.VerifyFields,
    AshA2ui.Verifiers.VerifyActions,
    AshA2ui.Verifiers.VerifyQueries,
    AshA2ui.Verifiers.VerifySections,
    AshA2ui.Verifiers.VerifyEditable,
    AshA2ui.Verifiers.VerifyReports,
    AshA2ui.Verifiers.VerifyExport,
    AshA2ui.Verifiers.VerifyRelationships,
    AshA2ui.Verifiers.VerifyNestedForms,
    AshA2ui.Verifiers.VerifyBulkActions
  ]

  @moduledoc """
  A Spark DSL extension that declares an A2UI (Agent to UI) surface for an Ash
  resource, from which `AshA2ui.Info.build_surface/2` generates A2UI v0.9.1
  protocol messages.

  Use it directly on a resource:

      use Ash.Resource, extensions: [AshA2ui]

  or in a standalone UI module (see `AshA2ui.Standalone`).

  ## Delegating a row action to the host

  A row action dispatches 1:1 to the Ash action named in `row_actions`. When
  the click must instead run through a host-provided function — e.g. an
  engine facade that completes an external task and invokes the Ash action
  itself — declare `via` on the action's `action` entity:

      a2ui do
        component :table do
          fields [:name, :status]
          row_actions [:check_in]
        end

        action :check_in do
          via {MyApp.Tasks, :check_in, ["board"]}
        end
      end

  At click time the handler calls
  `apply(MyApp.Tasks, :check_in, [context, "board"])` with the record, actor,
  tenant, action name, surface id, and context selections in `context`, and
  renders the returned `:ok` / `{:ok, term}` / `{:error, Ash.Error.t()}`
  through the standard success/error channels. The client is unaware `via`
  exists — see the `via` option docs above for the full contract.
  """

  use Spark.Dsl.Extension,
    sections: @sections,
    transformers: @transformers,
    verifiers: @verifiers
end
