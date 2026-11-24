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
        doc: """
        The name of the resource attribute/calculation/aggregate this field
        maps to, or a param or row key of a `:report` component (only `label`
        applies to a report name).
        """
      ],
      label: [
        type: :string,
        doc: """
        Human-readable label. Defaults to a humanized version of the field
        name. When the field names a `:report` component's param or row key,
        the label reaches the param input, the row cell caption, the export
        column and the CSV header; `widget`, `hidden` and `order` apply to
        tables and forms only.
        """
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
        attribute or calculation, or a relationship path ending in one). Rows carry the link at the
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
      link_url: [
        type: :atom,
        doc: """
        Renders this field as a plain link to a page or address rather than to a
        surface's record: `link_url :quote_request_url` names a public attribute
        or calculation of the same resource whose value is the URL (a path such as
        `/requests/42`, or an absolute address). The field's own value is the link
        text; a `nil` or `""` URL means no link. Rows carry `_links/<field>` as
        `%{"href", "label"}` with no `"surface"`, and renderers follow the href
        (admin catalog 1.13). Cannot be combined with `link`, `links` or `source`.
        Table/detail only.
        """
      ],
      pairs: [
        type: :boolean,
        doc: """
        The field's value is a list of `%{"term" => _, "value" => _}` maps (a
        `{:array, :map}` calculation): labeled values whose labels vary per
        record, such as a record's extracted terms. Its admin dataGrid column
        carries `"pairs": true` (admin catalog 1.16), and a renderer draws one
        labeled row per pair; renderers that ignore it show the raw list.
        A pair may also carry its own `review` (`AshA2ui.Review`'s shape), a
        `key` (its stable address in the record) and `action` (whether it
        offers the field's action, `true` when absent): each row carries the
        normalized items at `_pairs_<field>`, bound by the column's `items`
        (admin catalog 3.10, see `AshA2ui.Pairs`). With a `field_action`, a
        table draws its button per item, not per row (the column's
        `pairAction`), and the action receives the item's key as its `:item`
        argument, which it must declare. A review summary counts each item
        whose review still waits.
        """
      ],
      steps: [
        type: :boolean,
        doc: """
        The field's value is a list of steps (an `{:array, :map}` calculation),
        drawn on `:detail` cards as a numbered stepper: an order's fulfilment
        "Placed → Packed → Shipped → Delivered". Each step is a map with a
        `label` (required), an optional `text` (the line under the label: a
        date, "Not yet"), an optional `note` (a smaller line) and a `state`,
        one of `"complete"`, `"current"`, `"upcoming"` or `"overdue"` (atom or
        string keys and values). The step's place in the list gives its
        number. A step without a label is left out (the others are numbered
        without it); a missing or unknown state reads as `"upcoming"`; a value
        that is not a list draws no steps. The record carries the normalized
        steps at `_steps_<field>`, and the admin `fieldDisplay` binds them as
        `steps` (admin catalog 1.17); the basic catalog draws one Text row per
        step. Tables and panels show the raw value. Cannot be combined with
        `pairs`, a badge or a link.
        """
      ],
      download: [
        type: :boolean,
        doc: """
        With `link_url`: the link downloads its address (a file) instead of
        opening it. The link entry carries `"download" => true` (admin catalog
        1.15); the stock renderer draws an `<a download>`. Only with `link_url`.
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
      ],
      note: [
        type: :string,
        doc: """
        A few words beside the field's label on `:detail` cards, saying how
        the value came to be: "Calculated", "From the signed copy". Admin
        catalog (`fieldDisplay`'s `note`); translated in the metadata domain.
        """
      ],
      recalculate: [
        type: :boolean,
        doc: """
        On `:detail` cards, this field's value follows a person's unsaved
        changes to the record's editable cards (admin catalog 3.15): while a
        change waits for the `save_bar`, the server works the value out
        again with the changes applied and the cards show that result, before
        Save. A notice deadline that comes from an expiry date and a notice
        period, say. Discard puts the stored value back.

        The server's own rule decides it, never a copy in the browser: it runs
        each card's `update_action` with the changes, as the save would (its
        changes and the related records' actions included), reads the field
        again with the record, and rolls the transaction back, so nothing is
        written and nothing is notified. The context's resource must have a
        data layer with transactions. The field must be drawn on a `:detail`
        card whose context has an editable card, and must not be an editable
        field of that context. The admin `fieldDisplay` binds the result as
        `preview` (`/ui/preview/<context>/<field>`); the basic catalog shows
        the stored value.
        """
      ],
      review: [
        type: :atom,
        doc: """
        A public attribute, calculation or aggregate of the same resource
        that says how this field's value was filled in, for `:detail`
        cards and table rows: a map with a `state`, one of `"pending"` (filled in
        automatically, nobody has checked it yet), `"reviewed"` (a person
        checked it) or `"missing"` (looked for and not found), and an
        optional citation: `page` (a positive integer, the page of the
        source document the value came from), `href` (an address that
        opens the source at that place), `quote` (the words the value
        was read from) and `boxes` (where the value sits on the source's
        pages, `[%{page, x, y, width, height}]` as fractions of the page:
        the regions of a `document_pane` bound to the card, whose page
        tag then opens the pane there). Keys and the state may be atoms
        or strings. `nil`,
        or a value without a known state, means the field has no review.
        The record carries the normalized review at `_review_<field>` (see
        `AshA2ui.Review`), and the admin `fieldDisplay` binds it as `review`
        (admin catalog 3.1): the value is highlighted while pending, with
        its state in words and a page tag linking to the source. A table
        drawing the field carries each row's review at the same key, bound
        by the admin `dataGrid` column as `review` and by a column subtitle
        as `reviewPath` (admin catalog 3.3); every table drawing the field
        must have the named field too. The basic catalog shows the value
        alone.
        """
      ],
      field_action: [
        type: :atom,
        doc: """
        An update action of the record a `:detail` card shows, offered as a
        button beside this field (admin catalog 3.2), or of the row a table
        draws it in, offered in each row (3.9): choosing it runs the action
        on that record, as the actor, with the field's name (a string) as
        its `:field` argument when the action declares one (an action that
        marks the whole record needs none). The record is re-read first, as
        an authorized read: through the card's context, or through the
        table's own read and its context filters. Afterwards the card's
        record is re-read and re-sent; for a row, the records of the
        contexts its table is filtered by are (a review summary counting
        the table's rows reads them). The `action` entity of the same name
        gives the button its `label` (default: the humanized action name),
        its `icon` and the tables it `refreshes`; its `visible_when` gates
        row actions only. Several fields may share one action. The basic
        catalog draws no button. On a `pairs` field (3.10, tables only) the
        button is per item: the action runs for the item the person chose,
        its key as the `:item` argument, and only while the record offers
        it and the item does (see `pairs`).
        """
      ],
      field_action_visible: [
        type: :atom,
        doc: """
        A public attribute, calculation or aggregate of the same resource
        that says, per record, whether this field's `field_action` is
        offered: `true` offers it, anything else hides it. Enforced on the
        server too: the action is refused for a record it does not offer
        it on. Without it the action is offered on every record.
        """
      ],
      edit: [
        type: {:or, [:atom, {:list, :atom}]},
        doc: """
        The attribute a person edits for this field on an editable `:detail`
        card (admin catalog 3.11), when the field shown is not the stored
        value itself: a display calculation (`:total_text`, a formatted
        amount) is edited as the attribute behind it (`:total`). The input
        starts from the attribute's value and its type picks the input (text,
        number, date, or a choice of an atom's `one_of` values). Defaults to
        the field itself. The card's `editable` `update_action` must accept
        it.

        A value kept on a related record is edited through its relationship:
        `[:term, :ends_on]` names an attribute of the record a `belongs_to` or
        `has_one` relationship leads to. The input starts from, and is typed
        by, that record's attribute (empty while there is no related record).
        A save sends it to the card's
        `update_action` as the relationship's argument: a map of the edited
        attributes and the related record's primary key
        (`%{"term" => %{"id" => ..., "ends_on" => "2027-06-30"}}`), the input
        `manage_relationship` takes, so the action updates the related record
        through an action of its own (`on_match: {:update, :correct}`). The
        `update_action` must take an argument named after the relationship.
        """
      ],
      empty_text: [
        type: :string,
        doc: """
        What a `:detail` card shows for this field when the record has no
        value (`nil` or `""`), instead of a blank: "Not stated", "None". Shown
        muted by the admin catalog (`fieldDisplay`'s `emptyText`); the basic
        catalog shows the blank. A table's admin dataGrid column carries it too
        (catalog 1.14), for list rows ("No scope of work stated"). Translated in
        the metadata domain.
        """
      ],
      badge_text: [
        type: :keyword_list,
        default: [],
        doc: """
        Draws this field as a badge on `:detail` cards, with the display text
        per value, matched like a `row_layout`'s `badge_text` (atom and
        boolean values). Unmatched values show their humanized value, an
        enumerated value its choice label. Declaring any of `badge_text`,
        `badge_tones` or `badge_help` makes the field a badge; its text, tone
        and help are served at `/detail/<context>/_badge_<field>`,
        `_badge_tone_<field>` and `_badge_help_<field>`, the same keys a row
        layout's badge uses.
        """
      ],
      badge_tones: [
        type: :keyword_list,
        default: [],
        doc: """
        The tone per value of a `:detail` badge (see `badge_text`), from the
        row layout badge tones (`AshA2ui.RowLayout.tones/0`). Unmatched values
        are `:neutral`.
        """
      ],
      badge_help: [
        type: :keyword_list,
        default: [],
        doc: """
        A short explanation per value of a `:detail` badge (see `badge_text`),
        shown as its tooltip by the admin catalog. Translated in the metadata
        domain.
        """
      ]
    ]
  }

  @diagram %Spark.Dsl.Entity{
    name: :diagram,
    describe: """
    A live diagram: a mermaid diagram whose nodes carry markers (a person, a
    case, a job) that move as the host's state changes. The host's `source`
    returns the mermaid source and the markers for each render, as the
    actor; ash_a2ui has no knowledge of what the diagram shows. Markers live
    at `/diagram/<name>/markers`, keyed by node id, so a data-model refresh
    (for example a PubSub-driven one) moves them. The admin catalog renders
    the diagram with mermaid, loaded only when the diagram appears; the
    basic catalog renders a list of the nodes with their markers. See the
    Live Diagrams topic.
    """,
    examples: [
      """
      diagram :flight do
        label "Visits in flight"
        source MyApp.FlightDiagram
      end
      """,
      """
      diagram :lineage do
        source {MyApp.Lineage, :diagram, [:orders]}
      end
      """
    ],
    target: AshA2ui.Diagram,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: """
        The name of the diagram: the `<name>` of its `/diagram/<name>`
        data-model path. Unique across the surface's diagrams.
        """
      ],
      label: [
        type: :string,
        doc: "The diagram's heading. Defaults to the humanized name."
      ],
      description: [
        type: :string,
        doc: "Optional help text rendered under the heading."
      ],
      source: [
        type: {:or, [:atom, :mfa]},
        required: true,
        doc: """
        The host callback returning the diagram for a render: a module
        implementing `AshA2ui.Diagram.Source` (`diagram/1`), or
        `{module, function, args}` called as
        `apply(module, function, [context | args])`. It returns
        `{:ok, %{source: mermaid, markers: markers}}` or `{:error, reason}`;
        see `AshA2ui.Diagram` for the marker shape.
        """
      ]
    ]
  }

  @document_pane %Spark.Dsl.Entity{
    name: :document_pane,
    describe: """
    A document pane: the document a context's record was read from, drawn
    beside the surface's sections, with each value boxed where it sits on its
    page. It is bound to the `:detail` cards of its `context`: the boxes are
    the `boxes` of their fields' `review` citations (see `AshA2ui.Review`),
    in the fields' review states, and each field's page tag opens the pane at
    its box. The pane has its own show/hide switch, off by default; on is
    written to the address (`?<url_param>=shown`) by `AshA2ui.LiveRenderer`.
    The admin catalog draws it (catalog 3.4): the document with pdf.js,
    loaded only when a document opens, with a text layer, zoom and page
    navigation. The basic catalog leaves it out. See the Document Panes
    topic and `AshA2ui.DocumentPane`.
    """,
    examples: [
      """
      document_pane :document do
        context :contract
        source :page_document
        label "Show document"
        description "Read-only, for reviewing values"
      end
      """,
      """
      document_pane :policy do
        context :policy
        source :current_version_file
        regions :signature_fields
      end
      """
    ],
    target: AshA2ui.DocumentPane,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: """
        The name of the pane: the `<name>` of its `/ui/documents/<name>`
        state and of its record key `_document_<name>`. A lowercase
        identifier, unique across the surface's panes.
        """
      ],
      context: [
        type: :atom,
        required: true,
        doc: """
        The context whose record holds the document. At least one `:detail`
        component must render it: the pane is bound to those cards.
        """
      ],
      source: [
        type: :atom,
        required: true,
        doc: """
        A public attribute, calculation or aggregate of the context's
        resource holding the document: a map with `url` (the address the
        browser fetches the PDF from, read as the reader; `href` is accepted
        too) and `name` (the file name shown above it), keys atoms or
        strings. `nil`, or a value without a `url`, means the record has no
        document: the switch is not drawn.
        """
      ],
      regions: [
        type: :atom,
        doc: """
        Optional: a public attribute, calculation or aggregate of the
        context's resource holding more regions, ones no field's review
        cites (a signature field, a table value): a list of maps with `id`,
        `page`, `x`, `y`, `width`, `height` (the box, as fractions of the
        page), `state` (`pending`, `reviewed`, `selected`,
        `reviewed_selected`, `linked` or `empty`) and an optional `label`.
        Bad regions are dropped (see `AshA2ui.DocumentPane.region/1`).
        """
      ],
      label: [
        type: :string,
        doc: """
        The switch's label, translated in the metadata domain. Defaults to
        "Show document", the library's own string.
        """
      ],
      description: [
        type: :string,
        doc: "Optional words beside the switch, translated in the metadata domain."
      ],
      url_param: [
        type: :string,
        doc: """
        The address parameter that holds the pane open (`?<url_param>=shown`).
        Defaults to the pane's name.
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

  @empty_state_keys [
    title: [type: :string, doc: "The empty state's heading."],
    message: [type: :string, doc: "The empty state's body text."],
    icon: [
      type: {:in, [:inbox, :search, :archive]},
      doc: "A generic icon name (`:inbox`, `:search`, `:archive`)."
    ]
  ]

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
      """,
      """
      preset :tomorrow do
        read_action :tomorrow
        calendar_anchor 1
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
      ],
      calendar_anchor: [
        type: :integer,
        doc: """
        On a `display :calendar` table: when the client switches to this
        preset, the window moves to the one holding today plus this many
        days (in the calendar time zone) and the picked day is cleared, so a
        preset such as "tomorrow" or "the next two weeks" shows its records
        wherever the user had navigated. `0` is today. Ignored on other
        tables.
        """
      ],
      empty_state: [
        type: {:keyword_list, @empty_state_keys},
        doc: """
        The empty state shown while this preset is selected and nothing
        matches, e.g. `empty_state title: "No archived orders", icon:
        :archive`. Needs the query's own `empty_state`.
        """
      ],
      hide_controls: [
        type: :boolean,
        default: false,
        doc: """
        Whether the query's controls (search and filter pickers) are hidden
        while this preset is selected, e.g. an Archived tab that lists
        without filtering. The `/query` state carries `"controlsHidden"`
        (only on queries with such a preset); renderers that honour it hide
        the controls row.
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
        entry is a public string attribute (`:subject`), a string-typed public
        aggregate or expression calculation (`:supplier_name`, a `first`
        aggregate — searched in the data layer), or a relationship path
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
      hidden_filters: [
        type: {:list, :atom},
        default: [],
        doc: """
        Filters (each one also in `filters`) that get no picker in the query
        controls. Use it when the page around the surface sets the filter
        itself (links to `?q[filters][<name>]=...`): the filter still
        applies, only its picker is not emitted.
        """
      ],
      default_preset: [
        type: :atom,
        doc: "The preset applied when the client selects none. Must name a declared preset."
      ],
      preset_picker: [
        type: :boolean,
        default: true,
        doc: """
        Whether the query controls include the preset picker. Set `false` when
        the page around the surface selects the preset itself (tabs that link
        to `?q[preset]=...`): the presets still apply, only the picker is not
        emitted.
        """
      ],
      apply_on_change: [
        type: :boolean,
        default: false,
        doc: """
        Apply the query as its controls change, instead of on Apply: a picker
        applies when picked, search after a 300 ms pause in typing. The
        `/query` state then carries `autoApply` (`%{"debounceMs" => 300}`);
        a renderer that honours it hides the Apply button and sends its
        envelope on change, and one that doesn't keeps showing Apply.
        """
      ],
      sort_reset: [
        type: :boolean,
        default: false,
        doc: """
        A sortable header cycles through three steps instead of two: its
        first direction, the other, then back to the query's `default_sort`
        (the header sends a `nil` sort, which the runner reads as the
        default). The grid's `sort` binding carries `"reset": true`; a
        renderer without it keeps toggling between the two directions.
        """
      ],
      multi_select_filters: [
        type: {:list, :atom},
        default: [],
        doc: """
        Filters (entries of `filters` or `path_filters`) whose picker selects
        several values: the ChoicePicker is emitted with `"variant":
        "multipleSelection"` and no "All" option, and its value at
        `/query/filters/<name>` is a list (`[]` = inactive). The read keeps
        the records whose value is any of the selected ones.
        """
      ],
      filter_groups: [
        type: :keyword_list,
        default: [],
        doc: """
        Nested options for a filter with declared choices, per field: a
        group value and the leaf values it stands for, e.g.
        `filter_groups status: [due: [:due_today, :due_this_week]]`.
        The group is emitted as an option `{"label", "value", "group": true}`
        right before its leaves, which carry `"parent": "<group>"`. Only leaf
        values are filter values: selecting a group selects its leaves. A
        group value must not also be a leaf value. Needs the AshA2ui (merged
        or admin) catalog, whose ChoicePicker accepts the extra option keys.
        """
      ],
      group_labels: [
        type: :keyword_list,
        default: [],
        doc: """
        The label of each `filter_groups` group, per field, e.g.
        `group_labels status: [due: "Due soon"]`. Defaults to the
        field's choice label for that value, else the humanized value.
        """
      ],
      filter_labels: [
        type: :keyword_list,
        default: [],
        doc: """
        The picker label per filter (`filters` or `path_filters` name), e.g.
        `filter_labels supplier: "Supplier"`. Defaults to the field's declared
        `label`, else the humanized name.
        """
      ],
      filter_hints: [
        type: :keyword_list,
        default: [],
        doc: """
        A short hint per filter, shown with its options (the menu footer),
        e.g. `filter_hints status: "Statuses update nightly."`. Emitted as
        the ChoicePicker's `"hint"`.
        """
      ],
      facet_counts: [
        type: {:or, [:boolean, {:list, :atom}]},
        default: false,
        doc: """
        Count the records behind each filter option. `true` counts every
        picked filter (not `hidden_filters`); a list counts those filters.
        On every run the `/query` state carries
        `"facets" => %{"<filter>" => %{"<value>" => count}}` (a group: the
        sum of its leaves), each counted with search, ranges, the preset,
        the context scope and every *other* filter applied, but not the
        filter's own selection. Each faceted filter costs one aggregate
        query (one filtered count per option, run together).
        """
      ],
      filter_order: [
        type: {:list, :atom},
        default: [],
        doc: """
        The order of the filter pickers in the controls row, by name (entries
        of `filters` or `path_filters`). Filters left out keep their declared
        order after the listed ones. Without it, `filters` come first, then
        the `path_filters`.
        """
      ],
      path_filters: [
        type: :keyword_list,
        default: [],
        doc: """
        Filters over a related value, by name: a relationship path ending in
        an attribute (`warehouse: [:items, :warehouse, :name]`, matching
        records with *any* related value among the selected ones), or a
        single public attribute, aggregate or expression calculation
        (`supplier: :supplier_name`, `field in values`). The client sends them
        under `/query/filters/<name>` like `filters`. Their options are the
        distinct non-nil values the actor can read through the table's read
        (same preset, tenant and context scope), sorted, written on every
        run to the `/query` state's `"options" => %{"<name>" => [...]}`; the
        picker binds them (`"dynamicOptions"`). Incoming values must cast to
        the terminal field's type. Pickers for path filters render under the
        admin catalog only.
        """
      ],
      search_placeholder: [
        type: :string,
        doc: """
        The search box's placeholder, e.g. `"Search orders or suppliers"`.
        Emitted as the search TextField's `"placeholder"`; the field keeps
        its `"label"` (an accessible name).
        """
      ],
      controls_card: [
        type: :boolean,
        default: true,
        doc: """
        Whether the query controls sit in a Card. `false` emits the controls
        Row itself as `query<sfx>_controls` (the id the page references),
        for a page that draws a bare filter bar.
        """
      ],
      empty_state: [
        type: {:keyword_list, @empty_state_keys},
        doc: """
        The admin grid's empty state when there are no records:
        `empty_state title: "No orders yet", message: "...", icon: :inbox`.
        The emptyState component then binds `title`, `message` and `icon` to
        the `/query` state's `"emptyState"`, which the runner fills with this,
        `no_results_state` or the selected preset's `empty_state`.
        """
      ],
      no_results_state: [
        type:
          {:keyword_list,
           @empty_state_keys ++
             [
               clear_action: [
                 type: :string,
                 doc: "The label of a button that clears search and filters."
               ]
             ]},
        doc: """
        The empty state while search, filters or ranges are active and nothing
        matches, e.g. `no_results_state title: "No results", icon: :search,
        clear_action: "Clear search and filters"`. With `clear_action` the
        emptyState carries `clearAction` (`{label, action}`: the query
        envelope at page 1, sent after the client clears search and
        filters), shown while `clearVisible` is true. Needs `empty_state`.
        A `message` may say `{total}`: the read's count before search and
        filters ("There are {total} orders on this account.").
        """
      ],
      page_size_options: [
        type: {:list, :pos_integer},
        default: [],
        doc: """
        Page sizes the reader may pick, e.g. `[10, 20, 50]`. The admin
        pagination carries them as `"pageSizeOptions"` with the current
        `pageSize`; the client sets `/query/pageSize` and applies, and the
        runner accepts a listed size (and no more than `max_page_size`),
        starting again at page 1. Each must be at most `max_page_size`.
        """
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

  @column %Spark.Dsl.Entity{
    name: :column,
    describe: """
    How the data grid draws one of a `:table` component's fields: a second
    line under the value, a leading icon chosen per row, a "+N more" tag
    from a count, and a detail line under the value (under the badge, on
    the `row_layout` badge column). The fields a column reads from must be
    table fields; the grid draws them inside the column rather than as
    columns of their own. Renderers that ignore these hints draw the plain
    value, with the other fields as their own columns.
    """,
    examples: [
      """
      column :title do
        subtitle :assignee_name
        icon :priority
        icon_names high: :alert, low: :check
        icon_tones high: :danger, low: :success
        icon_labels high: "High priority", low: "Low priority"
      end
      """,
      """
      column :status do
        more :tag_count
        detail :status_detail
        detail_date :due_on
        detail_text overdue: "Overdue since {date}", due_soon: "Due {date}"
      end
      """
    ],
    target: AshA2ui.Column,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The table field this column draws. One column per field."
      ],
      subtitle: [
        type: :atom,
        doc: "A table field drawn as a second line under the value."
      ],
      icon: [
        type: :atom,
        doc: """
        A table field whose value picks an icon drawn before the value
        (`icon_names`). Rows carry the icon at the reserved
        `_icon_<column>` key, its tone at `_icon_tone_<column>` and its
        accessible label at `_icon_label_<column>` (`""` when the value has
        no icon).
        """
      ],
      icon_names: [
        type: :keyword_list,
        default: [],
        doc: """
        The icon per `icon` value, from `AshA2ui.Column.icons/0` (`:check`,
        `:x`, `:user_check`, `:user_x`, `:alert`, `:clock`, `:info`,
        `:refresh`, `:extend`). A value without an entry gets no icon.
        """
      ],
      icon_tones: [
        type: :keyword_list,
        default: [],
        doc: """
        The tone per `icon` value, from the badge tone vocabulary
        (`AshA2ui.RowLayout.tones/0`). Unmatched values are `:neutral`.
        """
      ],
      icon_labels: [
        type: :keyword_list,
        default: [],
        doc: """
        The accessible label per `icon` value. Defaults to the humanized
        value.
        """
      ],
      more: [
        type: :atom,
        doc: """
        A table field holding how many values the cell's field has (a
        `count` aggregate beside a `first` one): when it is 2 or more the
        grid adds a "+N more" tag, N being the count minus one. Rows carry
        the tag's text, translated and pluralized, at `_more_text_<column>`
        (the binding's `textPath`).
        """
      ],
      detail: [
        type: :atom,
        doc: """
        A table field whose value picks a detail line drawn under the value
        (`detail_text`). Rows carry the text at the reserved
        `_detail_<column>` key (`""` when the value has none).
        """
      ],
      detail_date: [
        type: :atom,
        doc: """
        A table field holding the date the renderer puts in place of
        `{date}` in the detail text, formatted in the reader's locale.
        """
      ],
      detail_text: [
        type: :keyword_list,
        default: [],
        doc: """
        The detail text per `detail` value, e.g.
        `detail_text overdue: "Overdue since {date}"`. A value without an
        entry gets no detail line.
        """
      ],
      detail_icon_names: [
        type: :keyword_list,
        default: [],
        doc: """
        The icon drawn before the detail line, per `detail` value, from
        `AshA2ui.Column.icons/0`. Decorative (the text says the same). Rows
        carry it at `_detail_icon_<column>`.
        """
      ],
      detail_icon_tones: [
        type: :keyword_list,
        default: [],
        doc: """
        The tone of that icon per `detail` value, from the badge tone
        vocabulary. Unmatched values are `:neutral`.
        """
      ],
      detail_help: [
        type: :atom,
        doc: """
        A table field whose value explains the detail line, drawn as an
        info mark with a tooltip after it. Rows carry the text at the
        reserved `_detail_help_<column>` key (`""` when there is none).
        """
      ],
      width: [
        type: :pos_integer,
        doc: "A fixed column width in pixels. The column carries `\"width\"`."
      ],
      more_values: [
        type: :atom,
        doc: """
        A table field holding all the values behind `more` (a `list`
        aggregate), so the grid can list them. Rows carry them, as strings, at
        the reserved `_more_values_<column>` key. Needs `more`.
        """
      ],
      more_noun: [
        type: :string,
        doc: """
        The plural noun for that list's caption ("3 warehouses"). The column
        carries `\"moreNoun\"`, and each row its caption, translated, at
        `_more_caption_<column>` (the binding's `captionPath`). The caption
        shows only for two values or more, so the noun is always plural.
        """
      ],
      sort_by: [
        type: :atom,
        doc: """
        The field the column's header sorts by, when it is not the column's
        own field (a module calculation shown, a stored copy sorted), e.g.
        `sort_by :status_cache`. Must be in the table query's `sortable`.
        The column carries `"sortable": true` and `"sortField"`.
        """
      ],
      sort_first: [
        type: {:one_of, [:asc, :desc]},
        doc: """
        The direction the column's header sorts in first, when it is not
        ascending — e.g. `sort_first :desc` for a date read newest first.
        The column carries `"sortFirst"`.
        """
      ],
      caption: [
        type: :atom,
        doc: """
        A table field drawn as a third line under the value and its
        `subtitle`, through `caption_text` — e.g. `caption :created_on` with
        `caption_text "Created {date}"`. Like `subtitle`, it is folded into
        the column. The column carries `"caption": {"path", "text"}`.
        """
      ],
      caption_text: [
        type: :string,
        doc: """
        The caption line's words, translated as display metadata. `{date}`
        is replaced with the `caption` field's value formatted as a date and
        `{value}` with the value as is. Without it the line is the value.
        """
      ],
      help_title: [
        type: :string,
        doc: "The title of the column's header help (see `help`)."
      ],
      help: [
        type: :string,
        doc: """
        Help for the column, opened from an info mark after the header label.
        Paragraphs are separated by blank lines; a line
        `**Term** — text` is a definition. The column carries
        `"help": {"title", "body"}`.
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
      badge_help: [
        type: :keyword_list,
        default: [],
        doc: """
        A one-line explanation per badge value, shown as the badge's tooltip,
        matched like `badge_text` — e.g.
        `badge_help active: "Account is currently active"`. Translated as
        display metadata. Served per row at the reserved
        `_badge_help_<field>` key (`""` when unmatched; the admin catalog's
        badge column binds it as `helpPath`).
        """
      ],
      meta: [
        type: {:list, :atom},
        doc: """
        The fields rendered in the card's labeled metadata grid, in order.
        Defaults to the table's fields minus `title`, `badge`, `leading`,
        `trailing`, `expand`, `group_by` and `group_subtitle`.
        """
      ],
      trailing: [
        type: {:list, :atom},
        default: [],
        doc: """
        Fields drawn at the end of the row, right-aligned: an amount over its
        unit, a due date. The admin dataGrid's columns for them carry
        `"placement": "trailing"`; the basic card shows them in its metadata
        grid.
        """
      ],
      expand: [
        type: {:list, :atom},
        default: [],
        doc: """
        Fields shown only when the row is opened: an item's notes, a
        message's full text. Declaring any makes each row a disclosure that
        opens below itself (rows start closed and open independently). The
        admin dataGrid's columns for them carry `"placement": "expand"`;
        renderers that do not draw disclosures show them as columns, and the
        basic card shows them in its metadata grid.
        """
      ],
      expand_label: [
        type: :string,
        doc: """
        The words on the disclosure that opens the `expand` fields ("Show
        notes"). The admin dataGrid carries it as `expandLabel` (admin
        catalog 1.16). Translated in the metadata domain. Only with `expand`
        fields.
        """
      ],
      leading: [
        type: :atom,
        doc: """
        A field drawn before the title as a short code: a file's type
        ("PDF"), a unit. The admin dataGrid's column for it carries
        `"placement": "leading"` (admin catalog 1.15); the basic card shows it
        in its metadata grid.
        """
      ],
      group_by: [
        type: :atom,
        doc: """
        A field whose value heads a group of rows: consecutive rows sharing
        it render under one header (a warehouse over its items). Order the
        rows so each group's rows are together (the table's read action or
        query sort). The admin dataGrid's column for it carries
        `"placement": "group"`; the basic card shows it in its metadata grid.
        """
      ],
      group_subtitle: [
        type: :atom,
        doc: """
        A field drawn under the group's header (a warehouse's address), taken
        from the group's first row. Needs `group_by`. Its admin dataGrid
        column carries `"placement": "groupSubtitle"`.
        """
      ],
      group_icon: [
        type: :string,
        doc: """
        An icon name for the group headers (`"home"`), carried as the admin
        dataGrid's `groupIcon`; renderers resolve it in their own icon set.
        Needs `group_by`.
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

    A board may split into **swimlanes** on a second enumerated attribute
    (`swimlanes_by`): the stage columns stay side by side and every
    swimlane is a row across them, one cell per (swimlane, lane), headed by
    its label on a background coloured by its tone (`swimlane_tones`).
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
      """,
      """
      sections do
        scope_by :stage
        swimlanes_by :severity
        swimlane_values [:emergency, :urgent, :routine]
        swimlane_tones emergency: :danger, urgent: :warning, routine: :success
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
      swimlanes_by: [
        type: :atom,
        doc: """
        Boards only (`display :board`, sections without a `source`): the
        public attribute or calculation of the table's resource that splits
        the board into swimlanes, rows across every lane. It needs
        enumerable values like a source-less `scope_by` (an `Ash.Type.Enum`
        or a `one_of` constraint) and must differ from `scope_by`. Each
        (swimlane, lane) cell is a table of its own, named
        `<component_key>_<lane>__<swimlane>`, whose reads AND
        `scope_by == lane` and `swimlanes_by == swimlane`. Records whose
        swimlane value is nil or not listed appear in no swimlane.
        """
      ],
      swimlane_values: [
        type: {:list, {:or, [:atom, :string]}},
        doc: """
        The enumerated values of `swimlanes_by` that become swimlanes, top
        to bottom (requires `swimlanes_by`). Defaults to all of them, in
        declaration order.
        """
      ],
      swimlane_labels: [
        type: :keyword_list,
        default: [],
        doc: """
        Swimlane heading overrides per value (`swimlane_labels emergency:
        "Emergency"`; requires `swimlanes_by`). Swimlanes without an entry
        are headed by the enum's label, else the humanized value.
        """
      ],
      swimlane_tones: [
        type: :keyword_list,
        default: [],
        doc: """
        The tone per swimlane value, which colours the swimlane's background
        (`swimlane_tones emergency: :danger, routine: :success`; requires
        `swimlanes_by`). Tones are the `badge_tones` vocabulary: `:neutral`,
        `:info`, `:success`, `:warning`, `:danger` and `:accent`; unlisted
        swimlanes are `:neutral`. Served at the reserved
        `/_swimlane_tone_<component_key>__<swimlane>` path; the AshA2ui
        merged catalog maps it onto the `--a2ui-swimlane-<tone>-*` tokens.
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
          "Maximum number of sections rendered (the source read's limit). Without a source it caps the lanes, not the cards per lane, and may not be below the lane count; on a swimlaned board it caps the cells (each one a page read and a count on every render and refresh) and may not be below the cell count."
      ]
    ]
  }

  @editable %Spark.Dsl.Entity{
    name: :editable,
    describe: """
    Editing in place, on a `:table` or a `:detail` card.

    On a `:table`, the listed fields render as in-row inputs with a per-cell
    Save button dispatching the `"edit_cell"` client action — the server
    runs `update_action` on the identified record with just that field's
    value (cast against the action like any client input). The Save's
    outcome is the surface's `/ui/feedback`, like any other write;
    validation errors are mirrored into the failing row's reserved
    `_error_<field>` key (rendered next to the cell) alongside the standard
    `/errors/<field>` write. Not supported together with a `row_layout`
    (card rows render read-only meta values).

    On a `:detail` card (admin catalog 3.11), choosing or focusing a listed
    field's value opens it as an input in place; Enter or leaving it keeps a
    change, Escape drops it. Nothing is written yet: the change waits, with
    every other unsaved change on the surface, until the surface's
    `save_bar` saves them (the `"save_changes"` client action runs each
    card's `update_action` on its record with its changed fields, all in one
    transaction). A field's `edit` names the attribute it edits when the
    field shown is a display calculation. `visible` gates editing per
    record, on the server too. The basic catalog draws the card read-only.
    """,
    examples: [
      """
      editable do
        fields [:replacement]
        update_action :update_replacement
      end
      """,
      """
      component :detail, :facts do
        context :order
        fields [:title, :total_text]

        editable do
          fields [:title, :total_text]
          update_action :correct
          visible :correctable
        end
      end
      """
    ],
    target: AshA2ui.Editable,
    schema: [
      fields: [
        type: {:list, :atom},
        required: true,
        doc: """
        The fields a person edits. Each must be one of the component's
        fields, and its attribute (a detail field's `edit`, else the field)
        accepted by the resolved `update_action`.
        """
      ],
      update_action: [
        type: :atom,
        doc: """
        The update action the edits run (with only the changed fields'
        values). Defaults to the primary update of the record's resource: the
        table's, or the detail card's context's.
        """
      ],
      visible: [
        type: :atom,
        doc: """
        `:detail` only: a public attribute, calculation or aggregate of the
        card's record saying whether a person may edit it: `true` offers
        editing, anything else draws the card read-only. Enforced on the
        server too: a save naming a record that does not offer it is
        refused. Without it every record offers editing.
        """
      ]
    ]
  }

  @save_bar_confirm %Spark.Dsl.Entity{
    name: :confirm,
    describe: """
    The dialog a save opens while fields under review still wait (admin
    catalog 3.11): Cancel (with Escape, the close button and the backdrop)
    closes it with nothing saved; the save choice saves the changes; the
    `then` choice saves them and then runs `then_action` on the bar's
    record, in the same transaction. Nothing waiting, a save saves at once,
    without the dialog.

    `title` and `message` may hold `%{count}`, the number of fields still
    waiting; `title_one` and `message_one` are the forms for one.
    """,
    examples: [
      """
      confirm do
        title "Save with %{count} fields not reviewed?"
        title_one "Save with 1 field not reviewed?"
        message "You can come back to them later."
        save_label "Save progress"
        then_label "Save and mark reviewed"
        then_action :review
        then_visible :review_open
      end
      """
    ],
    target: AshA2ui.SaveBar.Confirm,
    schema: [
      title: [type: :string, required: true, doc: "The dialog's title. Translated."],
      title_one: [type: :string, doc: "The title when one field waits. Translated."],
      message: [type: :string, doc: "The dialog's text. Translated."],
      message_one: [type: :string, doc: "The text when one field waits. Translated."],
      cancel_label: [
        type: :string,
        doc: "The cancel button. Translated. Defaults to the library's \"Cancel\"."
      ],
      save_label: [
        type: :string,
        doc:
          "The choice that saves the changes only. Translated. Defaults to the library's \"Save\"."
      ],
      then_action: [
        type: :atom,
        doc: """
        An update action of the bar's record run after the changes are
        saved, in the same transaction, with no input (marking the record
        reviewed). Without it the dialog offers no second choice.
        """
      ],
      then_label: [
        type: :string,
        doc: "The choice that saves and runs `then_action`. Translated."
      ],
      then_visible: [
        type: :atom,
        doc: """
        A public attribute, calculation or aggregate of the bar's record
        saying whether `then_action` is offered on it: `true` offers it.
        Enforced on the server too. Without it it is always offered.
        """
      ],
      then_saved_message: [
        type: :string,
        doc: "The outcome's message after the `then` choice. Translated. Defaults to the bar's."
      ],
      then_when_clear: [
        type: :boolean,
        default: false,
        doc: """
        Whether a save with nothing waiting runs `then_action` too, without
        the dialog, while the record offers it: the last fields reviewed,
        saving finishes the review.
        """
      ]
    ]
  }

  @save_bar %Spark.Dsl.Entity{
    name: :save_bar,
    describe: """
    The bar pinned to the bottom of the page while a person has unsaved
    changes to the surface's editable `:detail` cards (admin catalog 3.11):
    its message, how many fields under review still wait, Discard (drops
    every change) and Save (saves them all through the `"save_changes"`
    client action, each card's `update_action` on its record, in one
    transaction). A refused save keeps the changes and says why: each
    field's error at its input, the rest as the outcome. A `confirm` asks
    first while fields still wait. Unsaved changes survive a refresh of the
    surface's data. With `show_while_waiting` it also shows while fields
    under review wait, before anything changed (admin catalog 3.14). The
    rows of the context's tables count with its fields, as a
    `review_summary` counts them (3.16).
    With `status_reviewed` it also counts the fields reviewed so far (3.17).
    """,
    examples: [
      """
      save_bar do
        context :order
        message "You have unsaved changes"
        status "%{count} to check"
        saved_message "Changes saved."
      end
      """,
      """
      save_bar do
        context :order
        message "You have unsaved changes"
        message_waiting "Reviewing the order"
        status "%{count} to check"
        status_reviewed "%{count} checked"
        show_while_waiting :correctable
      end
      """
    ],
    target: AshA2ui.SaveBar,
    entities: [confirm: [@save_bar_confirm]],
    singleton_entity_keys: [:confirm],
    schema: [
      context: [
        type: :atom,
        required: true,
        doc: """
        The context whose record the bar reads: its fields under review (a
        `review` field on any `:detail` of the context) are the ones it
        counts, and its `confirm`'s `then_action` runs on it.
        """
      ],
      message: [
        type: :string,
        doc: "The bar's message. Translated."
      ],
      message_waiting: [
        type: :string,
        doc: "The bar's message while fields under review still wait. Translated."
      ],
      status: [
        type: :string,
        doc:
          "A tag counting the fields still waiting, with `%{count}`, shown while any wait. Translated."
      ],
      status_one: [type: :string, doc: "The tag when one field waits. Translated."],
      status_reviewed: [
        type: :string,
        doc: """
        Admin catalog 3.17: a tag counting the fields under review a person
        has reviewed, with `%{count}`, drawn after `status`. A field counts
        while its review state is `"reviewed"` (checked, or a saved
        correction) and, with `edit_reviews`, while it holds an unsaved
        change (saving it reviews it); so does each table row the bar
        counts (3.16) once nothing on it waits and a review is reviewed.
        Shown while the review is open (a field or row still waits) and at
        least one is reviewed.
        Translated.
        """
      ],
      status_reviewed_one: [
        type: :string,
        doc: "The reviewed tag when one field is reviewed. Translated."
      ],
      save_label: [
        type: :string,
        doc: "The Save button. Translated. Defaults to the library's \"Save changes\"."
      ],
      discard_label: [
        type: :string,
        doc: "The Discard button. Translated. Defaults to the library's \"Discard changes\"."
      ],
      saved_message: [
        type: :string,
        doc:
          "The outcome's message after a save. Translated. Defaults to the library's \"Changes saved.\""
      ],
      edit_reviews: [
        type: :boolean,
        default: false,
        doc: """
        Whether saving an edited field reviews it (the host's update action
        records the review), so the count of fields still waiting leaves out
        the ones being edited.
        """
      ],
      show_while_waiting: [
        type: {:or, [:boolean, :atom]},
        default: false,
        doc: """
        Admin catalog 3.14: whether the bar also shows while fields under
        review still wait, before anything changed (a review the person
        works through: the bar reads `message_waiting` with its `status`,
        and Save opens the `confirm`). `true` shows it on every record; a
        public attribute, calculation or aggregate of the bar's record shows
        it where that is `true` (who may save there). Discard shows only
        while a change waits, and a save with no change sends nothing but
        the `confirm`'s `then` choice. Off by default: the bar shows only
        while a change waits.
        """
      ],
      id: [type: :string, doc: "A DOM id for the bar."]
    ]
  }

  @primary_action %Spark.Dsl.Entity{
    name: :primary_action,
    describe: """
    Draws a `:table`'s primary row action (the row click: the
    `select_context` selection, else View) as one button per row in a final
    column, with a label and a variant chosen per row. For a list whose last
    column reads "Review", "Approve" or "View" depending on the record, all
    opening it. The button dispatches exactly what the row click does.

    Rows carry the button's label at the reserved `_primary_label` key and
    its variant at `_primary_variant`. Without `primary_action` nothing
    changes.
    """,
    examples: [
      """
      primary_action do
        label_from :next_step
        labels review: "Review", approve: "Approve", view: "View"
        variants review: :primary, approve: :default, view: :borderless
      end
      """
    ],
    target: AshA2ui.PrimaryAction,
    schema: [
      label_from: [
        type: :atom,
        doc: """
        A public attribute, calculation or aggregate of the table's resource
        whose value picks the row's `labels` and `variants` entries. It is
        loaded for the table; it need not be one of the table's fields.
        """
      ],
      labels: [
        type: :keyword_list,
        default: [],
        doc: """
        The button's label per `label_from` value (atom values, or string
        values by name), e.g. `labels review: "Review", view: "View"`.
        """
      ],
      variants: [
        type: :keyword_list,
        default: [],
        doc: """
        The button's variant per `label_from` value, matched like `labels`:
        `:default`, `:primary` or `:borderless` (the A2UI Button variants).
        """
      ],
      label: [
        type: :string,
        doc: """
        The label for rows whose value has no `labels` entry (and for every
        row without `label_from`). Defaults to the row click's own label.
        """
      ],
      variant: [
        type: {:in, [:default, :primary, :borderless]},
        default: :default,
        doc: "The variant for rows whose value has no `variants` entry."
      ],
      width: [
        type: :pos_integer,
        doc: "A fixed width in pixels for the button column (`rowClick.width`)."
      ]
    ]
  }

  @export %Spark.Dsl.Entity{
    name: :export,
    describe: """
    CSV file export for a `:table` or `:report` component: renders an
    "Export CSV" button dispatching the `"export"` client action; the server
    re-runs the component's data (a table honors its current query state and
    context scope; a report its current params) and answers with a
    `callRendererFunction` to `downloadFile` carrying a base64 `text/csv`
    data URL (see `AshA2ui.Export`). With `column_select`, per-column checkboxes bound
    under the reserved `/export/<name>/columns/<field>` paths let the user
    pick the exported columns.
    """,
    examples: [
      """
      export do
        filename "misspellings.csv"
        column_select true
      end
      """,
      """
      export do
        filename "contracts.csv"
        columns [:name, :value, :status, :currency]
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
        The exportable columns (header order). Defaults to all of the
        component's fields. On a `:report`, each must be one of the report's
        fields. On a `:table`, each is one of the table's fields or any
        public attribute, calculation or aggregate of the table's resource:
        a column the table does not show is loaded for the export read only
        and headed with its humanized name (or its `field` override's
        `label`).
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

  @alert %Spark.Dsl.Entity{
    name: :alert,
    describe: """
    Draws a `:detail` component as an alert instead of a card (admin catalog
    3.5): a title, a message read from the context's record and an optional
    link, toned by `variant`. For a notice about the record the page shows
    ("This order is on hold"), usually declared `lead true` so it sits under
    the page header. Give the component a `visible` field to show it only
    on some records.
    """,
    examples: [
      """
      component :detail, :on_hold do
        context :order
        lead true
        visible :on_hold?

        alert do
          variant :warning
          title "This order is on hold"
          message :hold_note
          link_href :hold_href
          link_label :hold_link
        end
      end
      """
    ],
    target: AshA2ui.Alert,
    schema: [
      variant: [
        type: {:one_of, [:info, :success, :warning, :danger, :neutral]},
        default: :info,
        doc: "The alert's tone."
      ],
      layout: [
        type: {:one_of, [:inline, :section]},
        default: :inline,
        doc: """
        `:inline` sits with the content around it; `:section` spans the page
        with its link at the end, for a notice that is about the whole page.
        """
      ],
      title: [
        type: :string,
        doc: "The alert's title, translated in the metadata domain."
      ],
      message: [
        type: :atom,
        doc: """
        A public attribute, calculation or aggregate of the context's record
        holding the alert's text. Read with the record at
        `/detail/<context>/<field>`.
        """
      ],
      link_href: [
        type: :atom,
        doc: """
        A field of the context's record holding the address of the alert's
        link (a page, or `#<anchor>` for a place on this page). No value, no
        link.
        """
      ],
      link_label: [
        type: :atom,
        doc: "A field of the context's record holding the link's words."
      ]
    ]
  }

  @review_summary %Spark.Dsl.Entity{
    name: :review_summary,
    describe: """
    Sums up, on an `alert` `:detail`, the review of the record its context
    selects (admin catalog 3.6): how many of the surface's `review` fields
    still wait for a person (`pending` or `missing`), and a link to the
    first of them in declaration order, to the section of the card holding
    it (its `section_nav` anchor, else the section's id). With nothing
    waiting the link is `fallback_href`. The alert's `message` stays the
    host's words; the count rides beside it. See `AshA2ui.ReviewSummary`.
    """,
    examples: [
      """
      component :detail, :to_review do
        context :order
        lead true
        visible :to_review?

        alert do
          variant :warning
          title "Check what was read from the document"
          message :review_note
        end

        review_summary do
          link_label "Go to the first field to check"
          fallback_href "#notes"
          fallback_label "Go to notes"
        end
      end
      """
    ],
    target: AshA2ui.ReviewSummary,
    schema: [
      link_label: [
        type: :string,
        doc: """
        The link's words while a field waits, translated in the metadata
        domain. Defaults to "Go to the first field to review".
        """
      ],
      fallback_href: [
        type: :string,
        doc: "Where the link goes once nothing waits (`#notes`). No link without it."
      ],
      fallback_label: [
        type: :string,
        doc: "The link's words once nothing waits, translated in the metadata domain."
      ]
    ]
  }

  @header_crumb %Spark.Dsl.Entity{
    name: :crumb,
    describe: """
    One step of the page header's breadcrumb, before the page's own title
    (which ends the breadcrumb). `page` names a value the host page writes
    at `/page/<key>`: when set, it replaces `href` (a list's address with the
    filters the person left it with). `live` makes the step a live link: on
    a LiveView transport a plain click navigates inside the LiveView instead
    of loading the page.
    """,
    examples: [
      ~s(crumb "Orders", href: "/orders", page: :back),
      ~s(crumb "Orders", href: "/orders", page: :back, live: :navigate)
    ],
    target: AshA2ui.PageHeader.Crumb,
    args: [:label],
    schema: [
      label: [
        type: :string,
        required: true,
        doc: "The step's words, translated in the metadata domain."
      ],
      href: [type: :string, doc: "The step's address."],
      page: [
        type: :atom,
        doc: """
        A key of the host page's values (`/page/<key>`, see
        `AshA2ui.Info.build_surface/2`'s `:page`): its value, when present,
        is the step's address instead of `href`.
        """
      ],
      live: [
        type: {:one_of, [:navigate, :patch]},
        doc: """
        Follow the step inside the LiveView: `:navigate` as `push_navigate`
        (another LiveView; LiveView loads the page when it cannot), `:patch`
        as `push_patch` (this LiveView's own address). The `AshA2ui` hook
        does it on a plain primary click of a same-origin address; a
        modified click, a renderer that does not know the key and a page
        without the hook follow `href` as a normal link.
        """
      ]
    ]
  }

  @header_item_schema [
    field: [
      type: :atom,
      required: true,
      doc: """
      A public attribute, calculation or aggregate of the header's context
      record holding the item's text. An empty value hides the item.
      """
    ],
    tone: [
      type: :atom,
      doc: """
      A field of the record holding the item's tone: `info`, `success`,
      `warning`, `danger`, `neutral`, `pending`, `accent` or `gray`.
      """
    ],
    icon: [type: :string, doc: "An icon drawn before the item's text."],
    icon_field: [
      type: :atom,
      doc: "A field of the record holding the icon's name, instead of `icon`."
    ],
    help: [
      type: :string,
      doc: "A tooltip explaining the item, translated in the metadata domain."
    ],
    help_field: [
      type: :atom,
      doc: "A field of the record holding the tooltip, instead of `help`."
    ],
    help_label: [
      type: :string,
      doc: """
      The accessible name of the tooltip's trigger, when the tooltip hangs
      off an info mark after the text rather than off the item itself.
      """
    ]
  ]

  @header_tag %Spark.Dsl.Entity{
    name: :tag,
    describe: """
    A tag in the page header's line under the title: the record's state in a
    word or two, coloured by `tone`, explained by its `help`. Tags come
    before the `meta` items.
    """,
    examples: [
      """
      tag :status_text do
        tone :status_tone
        help_field :status_help
      end
      """
    ],
    target: AshA2ui.PageHeader.Item,
    args: [:field],
    auto_set_fields: [kind: :tag],
    schema: @header_item_schema
  }

  @header_meta %Spark.Dsl.Entity{
    name: :meta,
    describe: """
    A line of text in the page header's line under the title, after its
    tags: a date, a note, a summary. `tone` colours it.
    """,
    examples: [
      """
      meta :renewal_note do
        icon_field :renewal_icon
        help_field :renewal_help
        help_label "About this renewal"
      end
      """
    ],
    target: AshA2ui.PageHeader.Item,
    args: [:field],
    auto_set_fields: [kind: :meta],
    schema: @header_item_schema
  }

  @header_action %Spark.Dsl.Entity{
    name: :header_action,
    describe: """
    A button in the page header. With `href` it is a link to the address a
    field of the record holds (no address, no button). With `run` it runs
    an update action of the record as the person: offered only while
    `visible` holds and `Ash.can?/3` says the person may run it, re-checked
    on the server when chosen (the `page_action` handler action).
    """,
    examples: [
      """
      header_action :approve do
        run :approve
        visible :awaiting_approval?
        variant :primary
      end
      """,
      """
      header_action :invoice do
        label "Open invoice"
        href :invoice_url
      end
      """
    ],
    target: AshA2ui.PageHeader.Action,
    args: [:name],
    schema: [
      name: [type: :atom, required: true, doc: "The button's name, unique in the header."],
      label: [
        type: :string,
        doc: """
        The button's words, translated in the metadata domain. Defaults to
        the `run` action's label (its `action` entity's, else its humanized
        name), else the humanized name.
        """
      ],
      run: [
        type: :atom,
        doc: "An update action of the header's context record, run with no input."
      ],
      href: [
        type: :atom,
        doc: "A field of the record holding the link's address."
      ],
      visible: [
        type: :atom,
        doc: """
        A boolean field of the record: the button is offered only while it
        is `true`. Without it, a link shows while it has an address and an
        action while the person may run it.
        """
      ],
      variant: [
        type: {:one_of, [:primary, :secondary, :quiet]},
        default: :secondary,
        doc: "The button's emphasis."
      ],
      title: [
        type: :string,
        doc: "A tooltip on the button, translated in the metadata domain."
      ]
    ]
  }

  @page_header %Spark.Dsl.Entity{
    name: :page_header,
    describe: """
    The page's header, drawn by the surface (admin catalog 3.5): a
    breadcrumb, the title, a line of tags and notes, and buttons, all read
    from the record selected into `context`. For a record page whose surface
    is the whole page. The host leaves its own header out (`header: false`
    is then unnecessary: the declared header replaces the surface's plain
    heading).
    """,
    examples: [
      """
      page_header do
        context :order
        title :name
        crumb "Orders", href: "/orders", page: :back

        tag :status_text do
          tone :status_tone
        end

        meta :customer_summary

        header_action :approve do
          run :approve
          variant :primary
        end
      end
      """
    ],
    target: AshA2ui.PageHeader,
    entities: [
      crumbs: [@header_crumb],
      tags: [@header_tag],
      meta: [@header_meta],
      actions: [@header_action]
    ],
    schema: [
      context: [
        type: :atom,
        required: true,
        doc: "The declared context whose selected record the header reads."
      ],
      title: [
        type: :atom,
        required: true,
        doc: "A field of the record holding the page's title."
      ],
      breadcrumb_label: [
        type: :string,
        default: "Breadcrumb",
        doc: "The breadcrumb's accessible name, translated in the metadata domain."
      ]
    ]
  }

  @nav_item %Spark.Dsl.Entity{
    name: :nav_item,
    describe: """
    One entry of the section nav: the section a component heads, its words
    and the `#anchor` that reaches it (a link anywhere on the page to
    `#<anchor>` goes there too).
    """,
    examples: [
      ~s(nav_item :order_lines, label: "Items", anchor: "items")
    ],
    target: AshA2ui.SectionNav.Item,
    args: [:component],
    schema: [
      component: [
        type: :atom,
        required: true,
        doc: """
        The component whose section the entry reaches: the first component
        of a `section`, or a component without one.
        """
      ],
      label: [type: :string, required: true, doc: "The entry's words."],
      anchor: [
        type: :string,
        required: true,
        doc: "The entry's `#anchor`, without the `#`, unique in the nav."
      ],
      id: [type: :string, doc: "A DOM id for the entry (for tests and links)."]
    ]
  }

  @section_nav %Spark.Dsl.Entity{
    name: :section_nav,
    describe: """
    A sticky list of the surface's sections drawn beside them (admin catalog
    3.5), for a long record page. Choosing an entry scrolls its section to
    the line the nav starts on and outlines it for three seconds; the entry
    of the section in view is marked as you read; arriving with `#<anchor>`
    in the address goes there once the section is drawn, however long that
    takes. The nav starts after the page header and any `lead` components.
    """,
    examples: [
      """
      section_nav do
        nav_item :details, label: "Overview", anchor: "overview"
        nav_item :order_lines, label: "Items", anchor: "items"
      end
      """
    ],
    target: AshA2ui.SectionNav,
    entities: [items: [@nav_item]],
    schema: [
      label: [
        type: :string,
        default: "Sections",
        doc: "The nav's accessible name, translated in the metadata domain."
      ],
      id: [type: :string, doc: "A DOM id for the nav."]
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
      columns: [@column],
      sections: [@table_sections],
      editable: [@editable],
      export: [@export],
      primary_action: [@primary_action],
      alert: [@alert],
      review_summary: [@review_summary]
    ],
    singleton_entity_keys: [
      :row_layout,
      :sections,
      :editable,
      :export,
      :primary_action,
      :alert,
      :review_summary
    ],
    schema: [
      name: [
        type: {:one_of, [:table, :form, :detail, :report]},
        required: true,
        doc: "The kind of component. One of `:table`, `:form`, `:detail` or `:report`."
      ],
      section: [
        type: :string,
        doc: """
        The page section this component belongs to: consecutive components
        (in the surface's root order) naming the same section render under
        one heading — "Overview" over its Details and Parties cards — inside
        a wrapper `Column` whose id is `section_<first component's key>`
        (an anchor a section nav can target). A component in a section with
        no `label` of its own draws no heading of its own. Translated in the
        metadata domain.
        """
      ],
      heading: [
        type: :string,
        doc: """
        The header of the table's own card ("Order lines"), drawn above its
        rows, inside the card. Unlike `label`, which names the table's
        section, it is drawn only when declared, so several tables under one
        `section` heading can each carry their own card header. Translated in
        the metadata domain. The admin dataGrid carries it as `heading`
        (catalog 1.18); the basic catalog draws it as a Text before the
        table. Tables only.
        """
      ],
      description: [
        type: :string,
        doc: """
        A one-line caption under the table's card header, above its rows
        ("Each line on this order, newest first."). Static text, translated
        in the metadata domain. The admin dataGrid carries it as
        `description` (catalog 1.18); the basic catalog draws it as a caption
        Text before the table. Tables only.
        """
      ],
      footer_note: [
        type: :atom,
        doc: """
        A field of the table's context record drawn inside the table's card,
        under its rows ("2 versions on file. Details shown come from the
        latest."): read and refreshed with that record, like `section_note`,
        from the one context the table's `context_filter` names. The admin
        dataGrid binds it as `footerNote` (catalog 1.15); the basic catalog
        leaves it out. Tables only.
        """
      ],
      footer_link: [
        type:
          {:keyword_list,
           [href: [type: :string, required: true], label: [type: :string, required: true]]},
        doc: """
        A link drawn beside the `footer_note` (or alone) under the table's
        rows: `footer_link href: "#history", label: "All versions"`. The label
        translates in the metadata domain. The admin dataGrid carries it as
        `footerLink` (`{href, label}`, catalog 1.15); the basic catalog leaves
        it out. Tables only.
        """
      ],
      section_note: [
        type: :atom,
        doc: """
        A field of the component's context record drawn under its section's
        heading, muted ("12 items · 3 warehouses"): a `:detail`'s
        `context`, or the one context a related table's `context_filter`
        names. Read with the context's record at `/detail/<context>/<field>`;
        the section's first component that declares one supplies it. Needs
        `section`.
        """
      ],
      label: [
        type: :string,
        doc: """
        The heading this component's section is shown under: a table's
        heading on multi-table surfaces, a `:detail` or `:report` card's
        heading. Defaults to the humanized component name (`:order_total`
        reads "Order total"), which cannot say "Products & pricing".
        Translated in the metadata domain like a field's `label`. A table's
        own card header is `heading`, not this.
        """
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
        arguments, in declaration order. Each input is labelled by a `field`
        override of the same name, else by the humanized name.
        """
      ],
      param_placeholders: [
        type: :keyword_list,
        doc: """
        A placeholder per `:report` param, e.g.
        `param_placeholders search: "Search suppliers", status: "Any status"`.
        Emitted as that param's TextField `"placeholder"` on the admin
        catalog (the basic TextField takes none); the field keeps its
        `"label"` as its accessible name. Keys must be among `params`.
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
        type: {:one_of, [:list, :rows, :cards, :board, :calendar, :timeline, :matrix]},
        default: :list,
        doc: """
        How a `:table` lays out its records. `:list` (default) renders rows
        (and stacks a sectioned table's sections). `:rows` is a list drawn
        as a stack of rows without a header — a record page's related lines
        — and requires a `row_layout`: the admin dataGrid carries
        `"layout": "rows"`, which renderers may draw as list rows (title and
        subtitle, badge, trailing values, an opening detail); renderers that
        ignore it draw the grid. `:cards` draws each record as its own card
        and also requires a `row_layout`: the layout's title and badge head
        the card, its `meta` fields are labeled rows, and its `expand` fields
        fold under a disclosure named by `expand_label`. The admin dataGrid
        carries `"layout": "cards"`; renderers that ignore it draw the grid.
        `:board` renders a
        sectioned table's sections side by side as lanes, each with its
        heading and total, card list and pagination; it requires a
        `sections` block and a `row_layout`, and cards move between lanes
        only through row actions (transitions). `:calendar` renders the
        records on a month, week or day grid placed by `date_field` (and
        `end_date_field`): the table's `query` reads only the visible window,
        and changing the window or picking a day re-queries. It requires
        `date_field` and a `query`. See the Calendars topic. `:timeline`
        renders the rows in `date_field` order, each led by its date or
        time. `:matrix` renders a grid: one row per `row_field` value, one
        column per `column_field` value, each cell showing `cell_field`.
        Both are basic-catalog compositions. See the Timelines and Matrices
        topic.
        """
      ],
      date_field: [
        type: :atom,
        doc: """
        `display :calendar` and `display :timeline` only: the public `:date`
        or datetime attribute of the table's resource that places each record
        on the calendar (its start) or on the timeline. Required with either.
        """
      ],
      row_field: [
        type: :atom,
        doc: """
        `display :matrix` only: the public attribute whose values are the
        matrix's rows, in the order the table reads them. Required with
        `display :matrix`.
        """
      ],
      column_field: [
        type: :atom,
        doc: """
        `display :matrix` only: the public attribute whose values are the
        matrix's columns: an enumerated attribute's values in declaration
        order, else the values in the order the table reads them. Required
        with `display :matrix`.
        """
      ],
      cell_field: [
        type: :atom,
        doc: """
        `display :matrix` only: the public attribute shown in each cell, from
        the record at that row and column. A cell with no record says so.
        Required with `display :matrix`.
        """
      ],
      end_date_field: [
        type: :atom,
        doc: """
        `display :calendar` only: an optional public `:date` or datetime
        attribute holding each record's end. A record then appears on every
        day from `date_field` to `end_date_field`, and the window read
        matches records that overlap the window. A `nil` end means the
        record covers its start day only.
        """
      ],
      granularity: [
        type: {:one_of, [:day, :week, :month]},
        doc: """
        `display :calendar` only: the size of the visible window — `:month`
        (default), `:week` (Monday to Sunday) or `:day`. Previous/Next move
        the window by one unit. With `granularities`, this is the one the
        calendar opens on (default: the first of them).
        """
      ],
      granularities: [
        type: {:list, {:one_of, [:day, :week, :month]}},
        doc: """
        `display :calendar` only: the window sizes the user may switch
        between (e.g. `[:month, :week]`). The renderer offers a switch, and
        the client names the one it wants (`"granularity"` in a `"query"`
        action); any other is rejected. Defaults to `[granularity]`: no
        switch.
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
      context_record: [
        type: :keyword_list,
        default: [],
        doc: """
        Hands the table's reads the record a context selected, so a row
        calculation can use what is already loaded on it instead of reading
        it again. Keys are context names from this table's `context_filter`,
        values the loads the record must carry
        (`context_record order: [:totals]`). The surface fetches each
        selected record once, with these loads added to those of the
        context's `:detail` components and page header, before the table
        reads, and puts it in the read's query context; a calculation reads
        it with `AshA2ui.ContextRunner.context_record/2`. A context with
        nothing selected hands nothing. `AshA2ui.Info.build_surface/2` and
        `build_data_model/2` hand it; a read the action handler runs alone
        (a page, a sort, a search) does not, so the calculation must still
        work without it.
        """
      ],
      column_order: [
        type: {:one_of, [:layout, :fields]},
        default: :layout,
        doc: """
        The order of the admin data grid's columns on a table with a
        `row_layout`. `:layout` (the default) is the layout's title, badge,
        then meta fields; `:fields` keeps the component's `fields` order
        (the fields `column` entities read from still fold into their
        columns). The badge column keeps its `badge_text`/`badge_tones`
        wherever it sits.
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
      hide_empty: [
        type: {:list, :atom},
        default: [],
        doc: """
        `:detail` components only: fields whose row is left out of the card
        while the record has no value for them (`nil` or `""`), instead of
        showing a blank or the field's `empty_text` — "Cancelled by" on an
        order that was never cancelled. Admin catalog (`fieldDisplay`'s
        `hideWhenEmpty`); the basic catalog shows the row.
        """
      ],
      context: [
        type: :atom,
        doc: """
        The declared context a `:detail` component renders: its selected
        record's fields are written to `/detail/<context>` and displayed as a
        read-only label/value grid. Required on `:detail` components.
        """
      ],
      lead: [
        type: :boolean,
        default: false,
        doc: """
        `:detail` components only: draw it full width right under the page
        header, before the surface's other sections and beside none of them
        (admin catalog 3.5, the entityPage's `lead`). Lead components keep
        their declaration order. The basic catalog draws them in place.
        """
      ],
      visible: [
        type: :atom,
        doc: """
        Lead `:detail` components only: a boolean field of the context's
        record; the component is drawn only while it is `true` (a notice
        about some records, a card some records have nothing for).
        """
      ]
    ]
  }

  @prompt_options %Spark.Dsl.Entity{
    name: :prompt_options,
    describe: """
    The per-row option scope of a relationship prompt field: the prompt
    offers only the options `read_action` (a read action of the
    relationship's destination) returns for the row it is opened on, its
    `record_argument` receiving the row's primary key. Without it a
    relationship prompt lists every option the actor can read.

    Server-authoritative: the read runs as the actor, with the actor's
    tenant, for a row the actor can read through the surface's read action
    (and that passes the action's `visible_when`). The client never sends a
    filter — only the row's id, which the server re-reads. The field renders
    as an option list over `/prompt/options/<action>/<field>` (the `prompt`
    pre-fill writes the row's options there; `option_search` refreshes them
    when the field declares `option_search`), never as options inlined in
    the component tree or loaded surface-wide, and every picked value is
    re-read through the same scope by `option_select` and again by `invoke`
    before the write — a value outside the row's scope is refused as a field
    error.
    """,
    examples: [
      """
      action :delegate do
        prompt_fields [:principal_id]

        prompt_options :principal_id do
          read_action :candidates_for_task
          record_argument :task_id
        end
      end
      """
    ],
    target: AshA2ui.PromptOptions,
    args: [:field],
    schema: [
      field: [
        type: :atom,
        required: true,
        doc:
          "The prompt field this scope applies to: one of the action's `prompt_fields`, a relationship select."
      ],
      read_action: [
        type: :atom,
        required: true,
        doc: """
        A read action of the relationship's destination returning the options
        for one row. Its preparations and policies run as the actor, so it can
        read anything the row's candidates depend on.
        """
      ],
      record_argument: [
        type: :atom,
        required: true,
        doc:
          "The argument of `read_action` that receives the row's primary key. The scope read passes no other input, so any other argument the read action requires needs a default."
      ]
    ]
  }

  @action %Spark.Dsl.Entity{
    name: :action,
    describe: """
    Per-action metadata: the button label, refresh targets, argument
    prompts, per-row visibility conditions, a confirmation (`confirm`), and
    host-delegated dispatch (`via`).
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
      action :delegate do
        prompt_fields [:principal_id]

        # Only the task's candidates, read as the actor.
        prompt_options :principal_id do
          read_action :candidates_for_task
          record_argument :task_id
        end
      end
      """,
      """
      action :confirm_merge do
        label "Confirm match"
      end
      """,
      """
      action :deactivate do
        # Asked through the admin grid's confirmation dialog, as a destroy is.
        confirm :destructive
        visible_when lifecycle_status: :active
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
    entities: [prompt_options: [@prompt_options]],
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
        its prompt heading — and the name in its bulk status line and its
        success status ("<label>: done."). A plain string, so a host can
        pass translated text. Defaults to the humanized action name.
        """
      ],
      icon: [
        type: :string,
        doc: """
        An icon name a renderer may draw this action's button as, its
        label becoming the button's accessible name and tooltip ("check").
        Carried by field actions (a field's `field_action`, admin catalog
        3.2); other buttons draw the label.
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
        its confirm button sends `invoke` with a `"values"` map. A
        relationship prompt field lists every option the actor can read
        unless a `prompt_options` entity scopes it to the row.
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
      confirm: [
        type: {:in, [:destructive]},
        doc: """
        `:destructive` makes the admin catalog's grid ask for confirmation
        through its ConfirmDialog before invoking this row action, as it
        does for every destroy: the row button opens the dialog, and its
        confirm control (labelled with the action's `label`) sends the
        unchanged `invoke`. For an action whose effect is drastic without
        being a destroy (deactivating a person). Unlike a destroy's, the
        dialog does not say the action cannot be undone. Row actions only,
        and not with `prompt_fields`, whose prompt is the confirmation. The
        basic catalog has no confirmation dialog and invokes on click, as it
        does for a destroy.
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
      component_order: [
        type: {:one_of, [:kind, :declared]},
        default: :kind,
        doc: """
        The order of the surface's sections in the admin catalog. `:kind`
        (the default) places every table before the `:detail` and `:report`
        cards; `:declared` places them in the order the components are
        declared, so a record page can interleave its detail cards and
        related tables (Overview, then the items, then the shipping details).
        The basic catalog always uses declaration order.
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
      @diagram,
      @page_header,
      @section_nav,
      @document_pane,
      @save_bar,
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
    AshA2ui.Verifiers.VerifyPrimaryAction,
    AshA2ui.Verifiers.VerifySteps,
    AshA2ui.Verifiers.VerifyContexts,
    AshA2ui.Verifiers.VerifyFields,
    AshA2ui.Verifiers.VerifyActions,
    AshA2ui.Verifiers.VerifyQueries,
    AshA2ui.Verifiers.VerifySections,
    AshA2ui.Verifiers.VerifyCalendar,
    AshA2ui.Verifiers.VerifyTableDisplays,
    AshA2ui.Verifiers.VerifyEditable,
    AshA2ui.Verifiers.VerifySaveBar,
    AshA2ui.Verifiers.VerifyRecalculate,
    AshA2ui.Verifiers.VerifyReports,
    AshA2ui.Verifiers.VerifyExport,
    AshA2ui.Verifiers.VerifyRelationships,
    AshA2ui.Verifiers.VerifyNestedForms,
    AshA2ui.Verifiers.VerifyBulkActions,
    AshA2ui.Verifiers.VerifyDiagrams,
    AshA2ui.Verifiers.VerifyPageLayout,
    AshA2ui.Verifiers.VerifyDocumentPanes
  ]

  @moduledoc """
  A Spark DSL extension that declares an A2UI (Agent to UI) surface for an Ash
  resource, from which `AshA2ui.Info.build_surface/2` generates A2UI 1.0
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
