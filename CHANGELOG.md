# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.
This changelog is managed by [git_ops](https://hex.pm/packages/git_ops).

<!-- changelog -->

## Unreleased

### Features:

- **The shell (AST-174).** A command palette (`ctrl+p`), a surface
  launcher (`ctrl+k`) and `/open <surface> [id | n]`, generic over any
  host:
  - `AshA2ui.Shell` is the pure half: the key table (`keys/0`), the slash
    grammar (`route/2`: a plain line is a prompt, `/open`, `/home`, a
    command's name, a surface named directly), surface lookup by id, title
    or unique prefix (`find_surface/2`), and the rows a mode lists
    (`items/3`).
  - The host supplies its lists in the ACP wire shapes
    (`AvailableCommand`, `SurfaceEntry`) and what an invocation does,
    through `AshA2ui.Shell.Host`.
  - `AshA2ui.Shell.Component` draws it in a page; mount it in the layout.
    `priv/js/ash_a2ui_shell_hook.js` (`AshA2uiShell`) turns the keys into
    the component's events. `AshA2ui.Shell.Component.open/1` opens it from
    a button.
  - New usage rule: `ash_a2ui:shell`.

- **Time travel (AST-175).** A surface can be read as of an instant over
  Ash temporal resources:
  - `AshA2ui.Info.build_surface/2`, `build_data_model/2` and
    `AshA2ui.ActionHandler.handle/3` take `:as_of`. Every table, option
    list, context, detail and section read runs at that instant, and a
    diagram source receives it as `context.as_of`.
  - A surface pinned to an instant is view-only. Its row actions, bulk
    actions and action metadata are stripped (`AshA2ui.Info.view_only/1`),
    and the action handler refuses writes with `READ_ONLY_AS_OF`.
  - `AshA2ui.AsOf` is the `?as_of=` grammar: `parse/1`, `to_param/1`,
    `from_params/1`, `put_param/2` and `read_opt/1`.
  - `AshA2ui.LiveRenderer` takes `time_travel: true`: it reads `?as_of=`,
    assigns `:ash_a2ui_as_of`, and rebuilds the surface when the instant
    changes.
  - `AshA2ui.TimeScrubber.scrubber/1` is a timeline control: a range input
    over a span, marks that are links to their exact instants (dragging
    snaps to them), "Return to now", and a status readout. Positions are
    resolved server-side with `AshA2ui.TimeScrubber.instant/4`.

  Extracted from clinic-demo's board and revenue time travel, which
  threaded `as_of` through a copy of the surface builder.
  See the `ash_a2ui:time-travel` usage rules.

- **Per-row prompt options (`prompt_options`).** A relationship prompt
  listed every option the actor could read. For example, clinic-demo's
  delegate prompt listed every principal, not only the task's candidates.
  A `prompt_options :field` entity on an `action` now scopes the field to
  the row. Its `read_action` (a read action of the relationship's
  destination) runs as the actor, with the row's primary key as its
  `record_argument`. The scope is server-authoritative:
  - the client sends only the row's id, never a filter;
  - the server re-reads the row through the surface's read action, with
    `visible_when` enforced;
  - the options reach the client only through the `prompt` pre-fill, at
    `/prompt/options/<action>/<field>` (with the row at
    `/prompt/record/<action>`). They are never inlined in the component
    tree or loaded at `/options/<field>`;
  - `option_select`, `option_search` (scoped to the row) and `invoke`
    re-read every picked value through the scope. A value outside it fails
    on `/errors/<field>`.

  The field renders as the option-list composite, with search controls
  when the field declares `option_search`, in both compositions. The
  field, the read action and its argument are checked at compile time,
  and the read action may require no other argument without a default
  (the scope read passes only `record_argument`).

- **A prompt pre-fills a relationship value only when it can be picked.**
  A searchable or scoped prompt select pre-filled the row's stored value
  even when the actor could not pick it (unreadable, or outside the row's
  scope), with an empty label. Confirming without re-picking then failed
  with "is not one of the available options" on a field that showed no
  selection. Such a value is now pre-filled as `""`.

- **Boards in composed surfaces.** The dynamic spec carries
  `"display": "board"` with a `row_layout` and source-less `"sections"`
  (`scope_by`, `values`, `labels`, `swimlanes_by`, `swimlane_values`,
  `swimlane_labels`, `swimlane_tones`). The board rules are the shared
  verifiers' (`VerifySections`, `VerifyLayouts`, `VerifyComponents`,
  `VerifyActions`), so #25's runtime-name and empty-list rules apply to
  composed boards. Composed boards also follow these rules:
  - a board with a `source` is refused;
  - attribute names and label/tone keys are existing-atom lookups;
  - labels are plain text of 1 to 60 characters;
  - tones come from the badge tone set;
  - a board may expand to at most 12 cells
    (`AshA2ui.Dynamic.max_composed_cells/0`), counted by the new
    `AshA2ui.Board.cell_count/2`, which the declared `limit` check now uses
    too.

  Bulk actions stay outside the spec. The importer exports declared boards
  (including swimlanes) instead of rejecting them, and board specs promote
  and serialize back. The importer also exports a sourced sections block's
  non-default `limit`, which it used to drop.

- **Calendars in composed surfaces.** The dynamic spec carries
  `"display": "calendar"` with `"date_field"`, `"end_date_field"` and
  `"granularity"` (`day|week|month`) on a table, plus its required
  `"query"`, so an agent can compose a calendar. The rules are shared with
  the DSL: they moved into `AshA2ui.Calendar.validate/2`, which
  `VerifyCalendar` calls and `AshA2ui.Dynamic` runs on every spec. A
  composed spec is rejected for:
  - a non-date or unknown date field (rejections list the resource's date
    and datetime attributes);
  - the same field twice;
  - a granularity outside the set;
  - a missing query;
  - `sections` or bulk actions on a calendar.

  Date fields are looked up as existing atoms only; `display` and
  `granularity` come from closed vocabularies; `"board"` is not offered.
  `spec_schema/1` describes the new keys. The importer exports declared
  calendars instead of rejecting them, and calendar specs promote to DSL
  source and serialize losslessly.

- **Calendars: `display :calendar` on `:table`.** Declare a `date_field`
  (and optionally `end_date_field` and `granularity :day | :week |
  :month`) and the table's `query` reads only the visible window: the
  table's read, preset, context scope, filters, search, actor and
  pagination apply as for a list, with the window ANDed on (records
  overlapping it when an end field is declared; UTC days). The window
  state lives at `/query/<table>/window` (`anchor`, `from`, `to`,
  `selected`, `label`, `scopeLabel`, and `marks`, the window's days that
  hold records). Moving the window and picking a day are the standard
  `"query"` action with `anchor`, `windowDelta` or `date` in the context;
  the client sends dates only, and malformed ones are rejected before any
  read. A picked day narrows the read; the marks still cover the window.
  Rows carry `_calendar_start`, `_calendar_end` and `_calendar_when`. The
  basic composition is an agenda: Previous/Next/Today, one Button per
  marked day and "All days" above the table's own list. The admin catalog
  (1.3.0, additive) emits a `calendarView` wrapping the table's
  `dataGrid`, rendered with `nb-calendar`, which gains a week view
  (`view="week"`, `nb-week-change`). The calendar moves at once and sends
  the absolute date it shows; replies to earlier requests do not move it
  back. Compile-time checks cover the field types, the closed granularity
  set, the required `query`, and `sections`/`bulk_actions`, which a
  calendar does not take. See the Calendars topic.
- **Live diagrams: the `diagram` entity.** A surface can declare
  `diagram :flight do source MyApp.FlightDiagram end`, where the source
  (an `AshA2ui.Diagram.Source` module or `{module, function, args}`)
  returns a mermaid source and markers for each render, as the actor.
  ash_a2ui has no knowledge of what the diagram shows. Markers (`node_id`,
  `label`, `status` `active|executing|waiting|failed|done`, optional
  `initials`, `tone`, `link`) live at `/diagram/<name>/markers`, keyed by
  node id, with a `nodes` list for fallbacks. Marker links are resolved on
  the server through the `AshA2ui.LinkResolver` and `:open_surface_url`;
  the basic composition's marker link Buttons (`link_buttons: true`)
  dispatch `"open_surface"` with the diagram name, accepted only for a
  surface the diagram's markers link to for the actor. Every build and
  full data-model refresh calls the source again, so a PubSub-driven
  refresh moves the markers; `AshA2ui.Diagram.refresh_messages/2` builds
  just the `/diagram/<name>` writes. The admin catalog (1.4.0, additive)
  renders a `liveDiagram`, which draws the source with mermaid at
  `securityLevel: "strict"`, places markers on their nodes and moves them
  without redrawing. Mermaid loads only when a diagram appears, through
  the new `loadMermaid` dependency and `priv/js/ash_a2ui_mermaid.js`,
  bundled apart from app.js. The basic composition is a List of nodes
  with their markers. `VerifyDiagrams` checks unique names and that the
  source exports its callback. See the Live Diagrams topic, which includes
  an `AshBpmn.FlightView` adapter written as host code.

- **Board swimlanes.** `swimlanes_by` in a board's source-less `sections`
  block splits the board into rows by a second enumerated attribute: the
  stage columns stay side by side under a header row, and every swimlane
  is a row across them, headed by its label and total. `swimlane_values`
  picks a subset and an order, `swimlane_labels` overrides headings and
  `swimlane_tones` gives each swimlane a tone from the `badge_tones`
  vocabulary. Each (swimlane, lane) cell is an expanded table,
  `<key>_<lane>__<swimlane>`, scoped by both attributes (a client filter on
  either cannot widen it), with its own pagination and total; swimlane and
  stage totals are the sums of their cells'. `refreshes` on the template
  key still covers every cell. The tone is data
  (`/_swimlane_tone_<key>__<swimlane>`); the merged catalog paints each
  row from the new `--a2ui-swimlane-<tone>-background` / `-color` tokens
  (AA contrast in light and dark, defaults in `ash_a2ui_theme.css`), and
  the admin catalog's basic board fallback gets the same rows. A board
  without `swimlanes_by` is byte-identical to before. Verified at compile
  time; `priv/js/probe/swimlanes_probe.mjs` is the browser check. On a
  swimlaned board `limit` caps the cells (each one a page read and a
  count on every render and refresh), and the verifier rejects a `limit`
  below the cell count.

- **`label` on the action entity.** `action :confirm_merge do label
  "Confirm match" end` names the action's row button and bulk toolbar
  button in both compositions, its admin `rowActions` entry, its prompt
  heading (unless `prompt_title` is set), its bulk status line and its
  success status ("Confirm match: done."; an action without a label keeps
  `Action "confirm_merge" completed.`). No
  wrapper action is needed just to get a readable button. The dynamic spec
  carries it too (`"label"` on an action; parser, `spec_schema/1`,
  Importer and promotion).
- **Prompt fields get form widgets.** A prompt field over a `belongs_to`
  source attribute (or a `field` with `relationship`) is a ChoicePicker over
  the actor's options, loaded at `/options/<field>` like a form select's; an
  enumerated argument or attribute is a ChoicePicker over its values;
  booleans and dates get CheckBox and DateTimeInput. A relationship field
  with `option_search` renders the searchable-select composite
  (`row_action_<action>_prompt_select_<field>`, state at
  `/prompt/select/<action>/<field>`); its `option_select` carries
  `"prompt"` and writes the picked value to `/prompt/values/<action>/<field>`
  after an authorized re-read. Values are cast and validated server-side as
  before, and a relationship prompt value is re-read as the actor before
  the write: one the picker would not have offered (a spoofed or stale id)
  fails on `/errors/<field>` with "is not one of the available options".
  The merged catalog's combobox upgrades these composites too.
- **`select_context` on boards.** A `display :board` table may declare
  `select_context`: every card gets the "Select <context>" control, so a
  board can fill a `:detail` instead of deep-linking away. List-mode
  sectioned tables still refuse it.

- **Reference links can render in the basic catalog (opt-in).** Rows and
  detail records carried `_links`, but only the admin catalog drew them.
  With the new `link_buttons: true` option to
  `AshA2ui.Info.build_surface/2`, a to-one link (`link :relationship` or
  `link {surface, id_path}`) in the basic composition wraps its value Text
  (same id, same binding) in a borderless `Button`, `<value id>_link`, in
  flat table cells, card-row titles and meta values, and detail values.
  The Button dispatches the new `"open_surface"` action with the field
  name and the bound `_links/<field>` surface and record id.
  `AshA2ui.ActionHandler` accepts it only when the field is a to-one link
  of the surface whose resolved surface, for this actor, is the one sent,
  and returns no messages. It does not check the record id: the opened
  surface authorizes its own read, as for any typed URL.
  `AshA2ui.LiveRenderer` then navigates exactly as for
  `"a2ui:open_surface"` (the `:open_surface` callback, else the
  `:open_surface_url` template), and sets `link_buttons: true` itself when
  it has either. Without the option nothing changes: link values stay
  plain Text, so hosts whose transport does not navigate (a plain
  `ActionHandler.handle/3` call) never show a control that does nothing.
  Only fields the `AshA2ui.LinkResolver` resolves in that render get a
  Button, so a vetoed field keeps its plain value. The Button is in the
  row template, so a row with no link for that field (a nil reference, an
  unreadable target) still gets one; clicking it is acknowledged and
  opens nothing. `links` (to-many) fields stay plain text, and row data is
  unchanged. Built from basic-catalog components only, on v0.9.1 and v1.0
  (the v0.9.1 `openUrl` takes only a literal URL, so it cannot open a
  per-row target). Hosts with their own transport pass `link_buttons:
  true` only once they navigate on an accepted `"open_surface"`.
- **The dynamic spec carries related tables and reference links.** A table
  component takes `"resource"` (an allowlisted name) to read another
  resource, and fields take `"link"` (a relationship name or `{"surface",
  "path"}`), `"links"` and `"link_label"`. `row_layout` takes
  `"badge_tones"`. Parser, `spec_schema/1`, Importer and promotion
  (`to_dsl_source/2`) all handle them, and the related-table and link rules
  are the DSL verifiers'. Link surface keys stay strings; resources only
  come from the allowlist.
- The composer's preview lists a table's `resource` and a field's `link` /
  `links`.

### Bug Fixes:

- **A table's query controls sit on one baseline.** The controls row
  (`query_controls_body`, or `query_<table>_controls_body`) is sent with
  `align: "end"`, so labelled inputs and the label-less Apply button line up
  at the bottom instead of the top, and the merged catalog's Row
  (`<ash-a2ui-row>`) lets that row wrap, so a filter bar with several pickers
  or longer labels stays inside a narrow screen. The board and wizard goldens
  gain only the `align` property.

- **A `{surface, id_path}` link whose path is a single calculation now
  links.** `link {:record, :subject_ref}`, with `:subject_ref` a
  calculation (or aggregate) of the resource, was never loaded: a
  one-step path was assumed to be an attribute. The id read as nil and
  the field was silently missing from the row's `"_links"`. A one-step
  path now loads its terminal when it is a calculation or aggregate.
  Attribute paths still load nothing.

- **View then Cancel no longer leaves the View button spinning (admin
  catalog).** Row-action and action-bar buttons settled only when
  `/ui/feedback/message` changed value. `view_record` and
  `cancel_record_task` write the already-clear feedback, so a View button
  stayed disabled with a spinner until another action reported. The
  renderer now subscribes to the `/ui/feedback` and `/ui/response` objects,
  so every outcome write settles the button, including one that leaves the
  value unchanged. A write that replaces the whole data model (a PubSub
  refresh, a URL-state change) is not an outcome and does not settle it.

- **Prompt dialogs on boards close after a successful confirm.** Board
  cards (and every basic-composed prompt) render their prompt as the basic
  `Modal`, which closed only through its × button. After a successful
  Complete or Delegate the dialog stayed open with its fields cleared. The
  merged basic catalog and the admin catalog now register
  `<ash-a2ui-modal>`, a subclass of the stock element. It closes when an
  `invoke` dispatched from inside it reports `kind == "success"`. Otherwise
  it stays open, showing the field errors and, below the content, the
  outcome's `/ui/feedback` message (so a Forbidden or stale-row error is
  visible inside the dialog), as the admin table dialog already did. A
  whole-model refresh arriving before the outcome does not end the wait. A
  stock basic renderer is unchanged.

- **A swimlaned board's cell-limit check cannot crash.** `VerifySections`
  matched `{:ok, cells}` from `AshA2ui.Board.cell_count/2`. It now handles
  `:error` (no enumerable values) with a diagnostic, so reordering the
  checks cannot turn it into a `MatchError`. Composed specs are pinned by a
  test: a sections `limit` below a board's lanes or cells is refused with
  the DSL's own message, because the shared verifier runs on every spec.

- **Boards reject runtime names that would collide.** A board's lane (or
  cell, swimlane or stage) runtime name that extends another at an
  underscore (`:high` and `:high_total` both built `lane_board_high_total`),
  or that equals another table's key (sharing its `/records/<name>`), is
  now a compile error, as is an empty `values` or `swimlane_values` list,
  which rendered no board at all. A board whose values did this compiled
  before and now fails to compile.

- **Following a basic-catalog link no longer throws "unsubscribe is not a
  function".** The merged catalog's status banner (`status_text`) called
  its data-model subscription as a function when it left the DOM (a link
  navigation, a LiveView patch). `DataModel.subscribe` returns
  `{value, unsubscribe()}` in @a2ui/web_core 0.10.x and 0.11.x; the banner
  now calls `unsubscribe()`. The admin catalog's action-busy settle
  subscriptions had the same mistake (swallowed by a `try`), so they were
  never released and kept firing on every later feedback change; fixed
  the same way.
- **Basic-catalog reference links look like links.** The merged catalog
  draws a `<value id>_link` borderless Button (`link_buttons: true`) in the
  surrounding text's font (it used the browser's button font), in the ink
  colour with a primary-coloured underline, with no padding, border or
  shadow, and with a focus ring on keyboard focus. The text stays ink
  because hosts often use primary as a fill colour, which can fall below
  4.5:1 contrast as text. New tokens: `--a2ui-link-color`,
  `--a2ui-link-hover-color`, `--a2ui-link-decoration`,
  `--a2ui-link-hover-decoration`, `--a2ui-link-decoration-color`,
  `--a2ui-link-decoration-thickness`,
  `--a2ui-link-hover-decoration-thickness`, `--a2ui-link-underline-offset`,
  `--a2ui-focus-ring-color`, `--a2ui-focus-ring-width`. The payload is
  unchanged. Checked on @a2ui/lit 0.10.x (shadow DOM) and 0.11.0 (light
  DOM) by `priv/js/probe/link_buttons_probe.mjs`, which also checks that
  removing the surface after following a link logs no console error.
- **Security: every read carries the surface's actor, tenant and
  `authorize?`.** A `:table` without a `query`, the option lists of
  relationship selects and a `sections` source were read with
  `Ash.Query.for_read/2` without them (passed only to `Ash.read`), so the
  read action's preparations ran with no actor or tenant: clinic-demo's
  worklist preparation saw nobody and had to declare a query to work
  around it. The opts now go to `for_read/4`. Audited: every other read in
  `AshA2ui.Info`, `AshA2ui.Sections`, `AshA2ui.ContextRunner`,
  `AshA2ui.QueryRunner`, `AshA2ui.Bulk` and `AshA2ui.ActionHandler` already
  built its query with them, and `AshA2ui.LiveRenderer` passes the mounted
  actor and tenant to every build and action call.
- **Admin catalog (1.2.0, additive): prompts, per-row visibility, the View
  panel.** Prompt row actions dispatched `invoke` with empty values and
  failed with "Validation failed": the dataGrid's entry now carries a
  `prompt` (a grid child holding the inputs, the heading and the pre-fill
  envelope) and the grid collects the values in a dialog. Entries of
  `visible_when` actions carry `visiblePath` (`_visible_<action>`), so the
  grid offers them only on the rows they apply to. The read-only View panel
  shows the action bar's Cancel, which closes it. Row action buttons wrap
  inside their cell. The prompt dialog keeps Tab and Shift+Tab inside it.
  See the contract note's 1.2 addendum.
- **Board lanes no longer size to their cards.** Lanes were a horizontal
  `List`, whose items shrink-wrap their content (a three-lane board rendered
  2266px wide on a 1280px viewport). They are now a `Row` of lane Columns at
  `weight` 1, sharing the board's width on any renderer; the merged catalog
  scrolls them inside the board below `--a2ui-board-lane-min-width`
  (default 18rem). The `board_<template>_lanes` component is a `Row` (was a
  `List` with `direction: "horizontal"`).
- **Readable error feedback.** Errors without a field rendered as "Request
  failed: …" (an Ash error class's first message line, often blank) or a
  bare "Validation failed…". `/ui/feedback` now carries the error's own
  message for field-less errors (an invalid change, a `via` function's
  string refusal), "You are not authorized to perform this action." for any
  Forbidden class, and names field errors the action shows no input for
  ("Status: must equal :claimed.") — an invoke's non-prompt fields and a
  submitted form's fields without an input. Field errors stay on
  `/errors/<field>`. Only messages someone wrote for the user are shown: a
  bare string, an UnknownError carrying one, an Invalid-class error. Any
  other error — a raw exception Splode wrapped (its text is the
  `Exception.format/2` output), a data-layer error, a Framework-class
  error — can carry row values or PII, so it reads "The action failed." and
  its text goes to `Logger.error/1`.

- **Importing a master/detail surface dropped its related tables and
  links.** The Importer silently dropped a table's `resource`, every
  `link` / `links` / `link_label` field option and `badge_tones`, so an
  imported master/detail surface (contexts plus related tables) no longer
  resolved. They now import as spec vocabulary, and the imported spec
  renders exactly like the declared surface (tested on initial render, a
  context selection, v1.0, serialization and promotion).
- **Tests now pin the related-table fixes of #18** on a surface with
  create and update actions, two related tables and a related query: no
  View/Edit row controls and no second create button on related tables
  (basic and admin_v1), the "Select <context>" label in both compositions,
  and identical related-table rows on the initial render, a deep-linked
  mount, back/forward, a `context_select` refresh and a related query
  refresh.

### Breaking Changes:

- **Removed experience v1 and the version switch.** The experience layer
  (`AshA2ui.Experience`: task panel, View/Edit row controls, create button,
  conditional pagination, empty states, typed feedback, h1 title, carded
  form) is now the only composition. Removed outright, with no shim and no
  deprecation path:
  - the `:experience_version` setting and `AshA2ui.Experience.version/0`,
    `v2?/0` and `effective_admin?/0` (use `admin?/0`; the admin catalog is
    active exactly when `catalog: :admin_v1` is selected). A leftover
    `experience_version` in host config is ignored.
  - the pre-experience composition it pinned: the always-visible form with
    a "Save" button, the per-row "Select" button (`row_select_button`) and
    the always-present pagination row.
  - the `"select_row"` client action (dispatch, AG-UI decoding and docs).
    It is now an unknown action. Send `"start_edit"` to load a record into
    the form, or `"view_record"` to show it read-only.
  - the `/ui/status` path, on both wire versions. Every outcome is the
    typed `/ui/feedback` value (`%{"kind" => "success" | "warning" |
    "error", "message" => text}`); the status Text binds
    `/ui/feedback/message`. v1.0 surfaces keep `/ui/response` and the
    `actionResponse` handshake, and write `/ui/feedback` alongside every
    `/ui/response` outcome (report runs and CSV exports included).
  - `/ui/wizard/nav/submit_visible` (the panel's
    `/ui/panel/submit_visible` gates the stepped form's submit).

  Migration: drop `config :ash_a2ui, :experience_version, ...`; move
  anything bound to `/ui/status` to `/ui/feedback/message` (or the whole
  `/ui/feedback` value); replace `select_row` with `start_edit` /
  `view_record`.

### Bug Fixes:

- **Rejections on v0.9.1 surfaces reached no visible path.** Many
  rejections (a forbidden `start_edit`, a malformed envelope, a query
  allowlist refusal, context, prompt, inline-edit and report errors) wrote
  only `/ui/status`, which no component bound once the status Text read
  `/ui/feedback/message`. Every error path now writes a typed
  `/ui/feedback` error (on v1.0 alongside `/ui/response`).
- **v1.0 report and export successes left the status line stale.** A
  report run or CSV export on a v1.0 surface wrote only `/ui/response`, so
  the status Text (bound to `/ui/feedback/message`) kept the previous
  outcome. Its "ok" message is now mirrored into a `"success"`
  `/ui/feedback`.
- **The v1.0 capped-selection notice answered as an error.** A
  `bulk_select` capped at the bulk limit succeeds, but on v1.0 its notice
  wrote an `"error"`/`INVALID_ACTION` `/ui/response`, so the
  `actionResponse` read as a failure. It now writes an `"ok"` response
  carrying the text, beside the `"warning"` `/ui/feedback`.
- **A context selection could leave an admin row action spinning.**
  `context_select` and `context_clear` wrote no outcome, so the admin
  dataGrid's "Select <context>" button stayed busy until some later action.
  A settled selection now clears `/ui/feedback` (as opening or cancelling a
  task does), which also removes a stale error.
- **Related tables offered controls that could not work.** A related table
  (a `:table` with its own `resource`) got View/Edit row controls that
  failed with "Request failed" and a second "Create <surface resource>"
  button under it. Related tables are read-only views and now render
  neither, in the basic and admin compositions.
- **The `select_context` row button read "View <context>"** right next to
  the task panel's "View". It now reads "Select <context>", in the basic
  and admin compositions.
- **Refreshed rows read differently from the initial render.** After a
  context selection, query or action refresh, table rows showed raw enum
  values (`scheduled`) where the initial render showed labels
  (`Scheduled`). The handler's refresh now uses the encoder's own row
  serializer, so both emit identical rows.

### Features:

- **Bulk actions** (A2UI-104) — `bulk_actions [:approve, :reject]` on a
  `:table` runs update, destroy or generic actions over a row selection.
  Rows carry the reserved `_selected` key (bound by a row CheckBox), a
  toolbar adds one button per bulk action plus Select page / Clear, and
  `/bulk/<table>/result` reports `ok`/`failed`/`refused`/`skipped` and
  per-record errors. The new `bulk_invoke` action checks the
  `bulk_actions` allowlist, re-reads the selected ids through the table's
  read under its active query preset (a `read_action` preset swaps the
  read, a `filter` preset ANDs on) and context/section scope as the actor
  (ids it does not return are refused), skips records failing
  `visible_when`, and runs each remaining record through the same dispatch
  as `invoke` with no shared transaction; `bulk_select` rewrites the
  page's selection from an authorized re-read, marking at most the bulk
  cap on a table without a query. Typed feedback gains `"warning"` for
  partial success (the admin catalog's `statusBanner` documents it).
  Compile-time checks reject read/create actions, generic actions without
  a `:record_id` argument, `prompt_fields` and related tables. Basic-composed on both spec versions and under the
  admin catalog. Prior art: PyroManiac's bulk actions. Surfaces without
  bulk actions serialize unchanged. See the Bulk Actions topic.
- **Boards** — `sections` no longer requires a `source`: without one, the
  sections are the enumerated values of `scope_by` (an `Ash.Type.Enum` or a
  `one_of` constraint), narrowed and ordered by the new `values` option and
  headed per the new `labels` option, with no read to enumerate them. The
  new `:table` option `display :board` renders such a set as lanes side by
  side (a horizontal `List` of lane `Column`s, each with its heading, a
  total at the reserved `/_lane_total_<lane>` path, its card list and its
  pagination), on v0.9.1 and v1.0. Cards move through transition row
  actions (`visible_when` + `refreshes` on the template key); there is no
  drag-and-drop. The lane scope is ANDed onto every read, so a client
  filter cannot widen it. Compile-time rules cover enumerability,
  `values`/`labels` membership, lanes that would share a runtime name
  (a repeated value, or values that sanitize alike), a `limit` below the
  lane count (on a board `limit` caps lanes, not cards per lane),
  source-only options and the board's `sections` + `row_layout`
  requirement. ChoicePicker options, choice text in rows and lane headings
  share one labelling rule (`AshA2ui.TypeMapper.choices/2`). `display :list` (the default)
  output is unchanged. The kanban vocabulary comes from PyroManiac
  (frankdugan3/pyro_maniac); see
  `notes/2026-10-15-pyro-maniac-borrowings.md`.
- **Wizard steps on forms** (A2UI-106) — `step` entities on a `:form`
  component (`name`, `label`, `description`, `fields`, `review?`) split it
  into pages over the one form and the one Ash action. New client actions
  `"wizard_next"` (builds the full changeset over the carried `/form`
  without submitting it and keeps only errors on fields of reached steps)
  and `"wizard_back"` (no validation). Next and the final `submit_form`
  build the changeset through one shared path, so on a stepped form both
  drop `/form` keys outside the form's fields. A failed `submit_form`
  jumps to the earliest step owning an erroring field; task open/cancel,
  a successful submit and (under experience v1) a row select or any other
  success reset to step 0. The review step shows a searchable select's
  label. New reserved path `/ui/wizard`
  (`index`, `steps`, `<step>_visible`, `nav`). Composed from basic
  components on v0.9.1 and v1.0; under experience v2 the panel primary
  label reads "Next" until the last step; the admin catalog falls back to
  the basic composition. Compile-time checks in `VerifySteps`; the dynamic
  importer rejects steps visibly. The step vocabulary is borrowed from
  PyroManiac. Forms without steps serialize unchanged.
- **Related tables** — a `:table` component may name its own `resource`
  (`component :table, :messages do resource MyApp.Message; context_filter
  thread_id: :thread; require_context [:thread] end`): fields, read action,
  query, context filters, `source` paths and links resolve against that
  resource, and reads run as the surface's actor in its domain. Read-only
  (no row actions, editable or sections). Surfaces without `resource`
  serialize unchanged.
- **Reference links** — `field` gains `link :relationship` (to-one),
  `link {surface_key, id_path}` (bare-id/polymorphic) and `links
  :relationship` (to-many), plus `link_label`. Rows, `/detail/<context>`
  and `/ui/panel/record` carry the reserved `"_links"` key
  (`%{field => %{"surface", "recordId", "label"[, "href"]} | [..]}`),
  pruned per actor by the authorized relationship load and the host's
  `AshA2ui.LinkResolver` (`config :ash_a2ui, :link_resolver`);
  `config :ash_a2ui, :open_surface_url` adds server-built hrefs. Link-free
  surfaces serialize unchanged.
- **`source` may end in a calculation/aggregate** of the final destination
  (loaded through the path) — e.g. a decrypted display name.
- **Admin catalog 1.1 (additive)** — DataGrid columns gain
  `format`/`align`/`mono`/`badge`/`link` hints and the grid a `rowClick`
  envelope; FieldDisplay gains `link`; a new `openSurface` client function.
  Renderer: sticky header in a token-driven scroll frame (no hardcoded
  1px/uppercase header), numbers end-aligned with tabular figures, ids in
  mono, toned badge pills (`row_layout badge_tones`, served per row at
  `_badge_tone_<field>`; fixes `badge_text` being lost under admin_v1),
  whole-row click, windowed pagination, link anchors (modifier-clicks keep
  open-in-new-tab), list-aware FieldDisplay values. Admin `:detail`
  components render FieldDisplays.
- **Deep links** — `AshA2ui.Info.context_state_for/3` validates carried
  context ids through authorized reads; `AshA2ui.LiveRenderer` seeds the
  bootstrap from `?ctx[...]`/`?q[...]`, and with `deep_link: true`
  push_patches context changes and re-applies them on back/forward.
- **`"a2ui:open_surface"`** — the hook forwards reference-link
  activations; `AshA2ui.LiveRenderer` navigates to `:open_surface_url` by
  default (or calls the `:open_surface` callback).
- Details may render declared `source`/`link`/`links` fields when their
  context selects the surface's own resource.

### Bug Fixes:

- **Sectioned tables under the admin catalog** — with `catalog: :admin_v1`,
  any surface with a `sections` block raised `KeyError` (key `:sections`
  not found) while encoding, because the expanded section tables no longer
  carry the template's `sections` key. They now fall back to the basic
  composition, as the admin catalog contract describes.

- The admin Pagination now reads the encoder's `previousAction` envelope
  (it only declared `prevAction`, falling back to a reconstructed envelope).

- **Master/detail on admin grids** — under `catalog: :admin_v1` a table's
  `select_context` row button was dropped: the admin `dataGrid` carried
  View/Edit and the declared row actions but no `context_select` entry, so a
  pickerless context (and every `:detail` bound to it) could never be filled
  on an admin surface. The grid now carries a `View <context>` row action
  dispatching the same `context_select` envelope the basic composition's
  per-row button sends (context name, the row's id, the table's `component`,
  plus the query/context bindings), so the handler contract is unchanged.

### Features:

- **Dynamic-spec vocabulary for nested forms, sections, and `via`** — the
  composer's Import now carries the common declared features losslessly
  instead of rejecting them. Components gain a `nested_forms` key (mirroring
  the `nested_form` entity: the managed action argument, sub-form `fields`,
  and the pick-existing `option_*` vocabulary — resource checks stay with
  `VerifyNestedForms`, which resolves run unchanged), a `sections` key (the
  dynamic-section config verbatim, the `source` resolved through the
  allowlist so a spec can only enumerate sections of offered resources), and
  actions gain a `via` key (`"Mod.fun/arity"` + args, arity = 1 + length of
  args since the dispatch context is prepended). `via` runs host code, so it
  is guarded twice: the parser validates the delegate exists at resolve time
  (module loaded, function exported at the applied arity — nothing is ever
  called), and `AshA2ui.Dynamic.resolve/2` gains `:via_allowlist` (default:
  none) — host configuration with the same discipline as the resource
  allowlist; existence alone is not authorization. Import rejections for
  these features are gone (rejections shrink to the truly unrepresentable:
  editable, export, section options; an `action` entity reachable only
  through a rejected `editable` block is rejected with it, since otherwise
  the spec would not resolve). `to_dsl_source` emits all three back,
  `spec_schema/1` documents them (composer editor rows follow
  automatically), and spec diffs cover nested forms (named sub-entities) and
  section options (flattened like `row_layout`).

- **Admin catalog v1** (`config :ash_a2ui, :catalog, :admin_v1`) — a
  semantic admin component vocabulary for experience v2 surfaces, selected
  app-wide (requires `experience_version 2`; an `:admin_v1` selection under
  v1 is ignored, keeping output byte-identical — see the precedence rules
  in `notes/2026-09-07-admin-catalog-contract.md`). The encoder upgrades
  the core subtree — root → `entityPage`, each core table → `dataGrid`
  (columns derived from the resolved field order, rowAction envelopes
  reusing the existing `view_record`/`start_edit`/`invoke` contexts with
  `destructive: true` on destroys) with `emptyState` + `pagination`
  children, the form → `recordPanel` (`fieldDisplay` children for view
  mode, `formSection` + `actionBar` for create/edit), and the status Text
  → `statusBanner` bound to `/ui/feedback/kind`/`message`. Query states
  additionally carry plain booleans `paginationVisible`/`previousVisible`/
  `nextVisible` for the semantic Pagination (the v2 sentinels remain for
  basic renderers); prev/next dispatch the existing `query` envelope with
  `pageDelta`. Surfaces using sections, reports, export, editable fields,
  or nested forms keep those subtrees byte-equal to the basic-v2
  composition — only the core upgrades. The catalog definition ships at
  `priv/a2ui/admin_v1/catalog.json` (catalog id
  `https://ash-a2ui.dev/catalogs/admin/v1`); the Lit renderer registration
  ships separately as `priv/js/ash_admin_catalog.js`
  (`createAshAdminCatalog(deps)`). The action handler learns nothing new —
  zero new action names or dispatch clauses.

- **Experience v2** (`AshA2ui.Experience`) — an opt-in UX layer behind
  `config :ash_a2ui, :experience_version, 2` (default `1` is byte-identical
  to the previous release). Surfaces gain explicit task modes: rows offer
  semantic **View**/`view_record` and (when the view has an update action)
  **Edit**/`start_edit` controls instead of **Select**, a
  **Create <Resource>**/`start_create` affordance appears near the query
  controls, and the form renders inside a task panel — gated behind the
  `/ui/panel/visible` sentinel, headed by `/ui/panel/title`, with the
  submit label bound to `/ui/panel/primary_label` and hidden in view mode
  via `/ui/panel/submit_visible`. `cancel_record_task` returns to browse
  and resets the form. Pagination becomes conditional (sentinels on the
  `/query` state hide the row when there is nothing to page; the page
  number becomes a result-range text, `"1–5 of 42"` or `"Showing 1–5"`),
  tables gain a data-driven empty state ("No <Resource> records yet."),
  and action outcomes carry typed feedback at `/ui/feedback`
  (`{"kind": "success" | "error", "message": ...}` — a successful task
  submission closes the panel; validation failures retain the open task,
  its values, and its mode). Forged task events run the same authorized
  actions as before (`start_edit` pre-flights the update authorization).
  The v1.0 encoder passes the new `/ui/*` state through its
  `/ui/response` collapse unchanged.

- **Canvas graph & objects** (`AshA2ui.Canvas.*`) — the naked-objects
  foundation, purely additive and gated behind a host-implemented registry:
  `AshA2ui.Canvas.Registry` (`domains/0`, optional `label/1`) defines the
  entire discovery surface — what it does not list does not exist. The
  canonical graph (`Canvas.build_graph/1`) introspects Ash metadata directly
  (`Ash.Domain.Info`, `Ash.Resource.Info`, `Ash.Policy.Info`, and
  `AshStateMachine.Info` when the optional `ash_state_machine` dependency is
  present) into an application → domain → resource containment tree with
  named relationship edges between registered resources; behavioral layers
  (actions, policies, state machines) ride as addressable typed
  sub-entities in node metadata (`resource:x#action:create`,
  `#policy:0`, `#state_machine`), and the revision is a deterministic
  sha256 over the canonicalized semantic content — registration and
  definition order cannot move it. `Graph.Diff.diff/2` reports exact
  deltas, with sub-entity changes surfacing as `changed_nodes`. Object
  resolution (`Canvas.resolve/2`) turns opaque refs
  (`application:`, `domain:`, `resource:`, `record:`) into labeled
  Objects with provenance, presence-derived resource capabilities,
  `Ash.can?`-derived record capabilities (actor/tenant-scoped), and
  declared projections — no records are ever materialized as graph nodes
  and structural resolution performs zero record reads. Client input is
  never converted to atoms or modules, and every failure mode collapses to
  `{:error, :unknown_object}`.

### Bug Fixes:

- The merged catalog asset (`priv/js/ash_a2ui_catalog.js`) bundles against
  every published `@a2ui` release again. Its Text/Button anatomy overrides
  statically imported `A2uiBasicTextElement` and `A2uiBasicButtonElement`
  from `@a2ui/web_core/v0_9/basic_catalog`, which only 0.11.0 exports; on
  0.10.x and 0.12.0 the host's esbuild failed outright. The classes are now
  resolved at runtime from the custom-element registry under the basic
  catalog's own tag names (`customElements.get(basicCatalog.components.get("Text").tagName)`),
  and an override is skipped with a warning if its upstream element is not
  registered.

- Formless surfaces no longer render a per-row **Select** button.
  `select_row`'s only effect is populating `/form` for editing, so on
  surfaces without a `:form` component the button succeeded silently with
  no visible result (found on a formless v1.0 master/detail screen where
  it sat next to the context-select button and read as broken). Row
  selection on such surfaces is the `select_context` button; the
  `select_row` handler itself is unchanged.

### Features:

- **AG-UI transport** (`AshA2ui.AgUi`) — surfaces are now consumable by
  AG-UI clients (CopilotKit chat UIs and anything else speaking the
  protocol) from any HTTP host, joining the AG-UI/A2UI interoperability
  stack. The module is framework-free (Jason only; compiled under
  `NO_PHOENIX`): AG-UI event builders (run lifecycle, streamed text, tool
  calls, custom), the `a2ui-surface` `ACTIVITY_SNAPSHOT` binding carrying
  A2UI message lists under `a2ui_operations`, SSE frame encoding,
  `RunAgentInput` decoding, and `decode_action/1` converting AG-UI client
  actions into the spec-valid v0.9.1 envelopes
  `AshA2ui.ActionHandler`/`AshA2ui.Dynamic` consume. The new
  [External Transports](documentation/topics/external-transports.md) topic
  documents the endpoint contract, event mapping, the CopilotKit
  `selfManagedAgents` client wiring (no Node middleman), the
  authentication/actor contract, and the **designed** (deferred) A2A
  binding (`DataPart` + `application/a2ui+json`).
- **Per-resolve `spec_version:` override** —
  `AshA2ui.Info.build_surface/2`, `build_data_model/2`, and
  `AshA2ui.ActionHandler.handle/3` now accept `spec_version: "0.9.1" |
  "1.0"`, overriding the surface's declared version for that call.
  Transports pin the wire version to what their renderer actually speaks
  (CopilotKit's shipped A2UI renderer processes v0.9 messages only)
  without touching surface DSLs.
- **Dynamic table sets** — a `sections` block on a `:table` component turns
  it into a template expanded at render time into one concrete table per
  record of a `source` resource (`scope_by` filters each section's reads,
  `label` heads it). Runtime tables follow the frozen multi-table contract
  under `<template_key>_<sanitized value>` names (`/records/<name>`,
  `/query/<name>`, `"component"` action contexts, per-section
  search/pagination); a sectioned surface is always multi-table so path
  shapes never change between renders; `refreshes` naming the template key
  fans out to the whole set. Source reads are actor-scoped and authorized;
  `AshA2ui.Verifiers.VerifySections` checks the block at compile time. See
  the multi-section-surfaces topic.
- **Inline cell editing** — an `editable` block on a `:table` component
  renders allowlisted fields as in-row TextField + Save cells committing
  per cell through the new `"edit_cell"` client action (context: `recordId`,
  `component`, `field`, `value`); the server runs the declared
  `update_action` with just that field's value. Validation errors keep the
  submitted value in the row and mirror the message into the failing row's
  reserved `_error_<field>` key (the only template-relative place a per-row
  error Text can bind) alongside the standard `/errors/<field>` write; on
  v1.0 surfaces the actionResponse handshake drives per-cell
  pending→settled feedback. `AshA2ui.Verifiers.VerifyEditable` checks the
  block at compile time (table-only, no `row_layout`, fields accepted by
  the action).
- **Aggregate/report surfaces** — the new `:report` component kind renders
  the computed rows of a declared generic (`:action`-type) Ash action:
  param TextFields bound under the reserved `/report/<name>/params` paths,
  a Run button dispatching the new `"report"` client action, and a result
  list templated over `/report/<name>/rows`. Params are filtered to the
  declared allowlist and cast against the action's arguments; the action
  runs actor-scoped/authorized; returned row maps are trimmed to the
  declared `fields` column allowlist. `AshA2ui.Verifiers.VerifyReports`
  checks reports at compile time (generic action, argument params, explicit
  fields, no table/form options). See the new reports-and-exports topic and
  the `ash_a2ui:reports` usage rules.
- **CSV file export (v1.0-only)** — an `export` block on a `:table` or
  `:report` component renders an Export CSV button; the server re-runs the
  component's data (tables honor search/filters/preset + context scope but
  ignore pagination, up to `limit`; reports re-run with the carried params)
  and answers with the frozen **`downloadFile`** callFunction contract
  (`{"filename", "mimeType", "dataUrl"}`, `url` variant for signed-URL
  hosts) — the first shipped use of the v1.0 server→client RPC channel.
  `column_select true` adds per-column checkboxes bound under the reserved
  `/export/<name>/columns` paths. The shipped hook implements
  `downloadFile` as a built-in; the new AshA2ui extension catalog
  (`priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json`) declares it for
  validating renderers; `AshA2ui.Csv` does RFC-4180 encoding.
  Declaring `export` on a 0.9.1 surface is a compile-time error
  (`AshA2ui.Verifiers.VerifyExport`) — 0.9.1 has no RPC channel to carry a
  download.

- **A2UI v1.0 (RC) support** — to our knowledge the first framework
  shipping a v1.0 conformance suite. `spec_version "1.0"` (DSL) /
  `spec_version: "1.0"` (`AshA2ui.Dynamic.resolve/2`) opts a surface into
  the v1.0 wire contract; v0.9.1 stays the default and its output is
  byte-identical. See the new [A2UI 1.0](documentation/topics/a2ui-1-0.md)
  topic for the full contract and UX rationale.
  - `AshA2ui.Encoder.V1_0`: single inline `createSurface` (components +
    initial data model in one message — no create-then-update flash, one
    payload for HTTP/agent-tool transports), `wantResponse: true` on every
    action event, v1.0 catalog/envelope, `surface_properties` option
    (v1.0's rename of `theme`; `primaryColor` is gone and was never our
    seam), automatic Markdown headings (the v1.0 basic catalog dropped the
    `h1`–`h5` Text variants; literal headings become `"## …"`, data-bound
    ones interpolate via `formatString`), wire `returnType`/`callableFrom`
    stripped from function calls, and `call_function/3` for judicious
    server→client RPC.
  - `AshA2ui.ActionHandler`: the v1.0 **actionResponse contract** — actions
    carrying an `actionId` are answered first with an `actionResponse`
    echoing the id (`{"value": …}` / `{"error": {code, message}}` with
    stable codes: `VALIDATION_FAILED`, `UNAUTHORIZED`, `INVALID_ACTION`,
    `ACTION_FAILED`); the v0.9.1 status trio (`/ui/status`,
    `/ui/action_result`, `/ui/action_result_text`) collapses into one
    structured `/ui/response` object mirrored by the response.
  - The shipped JS hook is the v1.0-capable client layer (no published
    `@a2ui/lit`/`@a2ui/web_core` release ships a v1.0 runtime yet): it
    expands inline `createSurface` for the v0_9 renderer, generates the
    `actionId` handshake with **0-RTT optimistic pending state** on
    `/ui/response` plus a timeout watchdog, dispatches
    `"ash-a2ui:action-response"` DOM events, and executes `callFunction`
    against a host-registered function table (`openUrl` built in;
    responses return via the `"a2ui:function_response"` LiveView event).
  - The executable spec: vendored v1.0 schemas/catalog/conformance cases
    (pinned commit in `priv/a2ui/v1_0/NOTES.md`), the upstream schema
    suites running in `test/v1_0_conformance_test.exs` (draft-7-invisible
    `unevaluatedProperties` cases pinned explicitly), and encoder/handler
    conformance suites asserting the semantic rules schemas can't express
    (explicit `value` on every `updateDataModel` — v1.0 deletes on omitted
    value; UAX #31 identifier rules on all generated names; actionId echo).

- Agent-composed surfaces: `AshA2ui.Dynamic` resolves a runtime,
  JSON-serializable surface spec — a declarative mirror of the DSL
  vocabulary an LLM can emit as structured tool output, never raw A2UI —
  into a served surface with the same rigor as the compile-time DSL. Specs
  are gated by a host-configured resource allowlist
  (`AshA2ui.Dynamic.allowlist/1`, `extension_resources/1`), built through
  Spark's own entity schemas, field-inferred by the existing transformer,
  and validated by the *same* verifier modules the DSL compiles with (run
  at runtime over a synthetic DSL state — same checks, same messages).
  `spec_schema/1` ships a JSON Schema for LLM tool parameters,
  `describe_resources/1` a prompt-ready resource vocabulary, and validation
  failures return structured `AshA2ui.Dynamic.Error`s that reuse the
  verifier texts so an agent loop can self-correct. Serving is
  stateless-but-tamper-proof: hosts hold the resolved
  `AshA2ui.Dynamic.Surface` server-side and route envelopes through
  `handle_action/3` on the server-held struct — the row-action allowlist,
  query allowlists, `visible_when` enforcement, and actor-based
  `authorize?: true` authorization apply exactly as on declared surfaces.
  See the new `agent-composed-surfaces` topic and the `ash_a2ui:dynamic`
  usage rules.
- The spec-as-artifact lifecycle: agent-composed specs are now first-class,
  persistable, reviewable artifacts.
  - `AshA2ui.Dynamic.serialize/1` / `deserialize/2` — a canonical stored
    form (versioned `{"spec": ..., "spec_format": 1}` envelope, object keys
    sorted at every level, so identical specs serialize byte-identically)
    plus `fingerprint/1` (`"sha256:..."`) as the content identity. Loading
    **re-validates against the current resource state** through
    `resolve/2`: fields/actions/resources removed since a spec was saved
    surface as the same structured `AshA2ui.Dynamic.Error` list a fresh
    spec would produce — drift becomes reviewable errors, not a crash.
  - `AshA2ui.Dynamic.diff/2` — the change summary a ratifying human reads:
    computed at the spec vocabulary level (components, queries and their
    presets, fields, actions, contexts matched by name; option-level
    changes with old and new values; `row_layout` flattened to dotted
    options), never a raw JSON diff. `AshA2ui.Dynamic.Diff.summary/1`
    renders per-change review lines; changes are Jason-encodable for
    review UIs.
  - `AshA2ui.Dynamic.to_dsl_source/2` — promote a validated spec into the
    source of a checked-in `AshA2ui.Standalone` module: formatted with the
    DSL's own `locals_without_parens`, compile-ready, provenance-commented
    with the spec fingerprint. Resolving the promoted module is equivalent
    to resolving the spec directly (held as a round-trip property in the
    test suite).
- Section card chrome: context picker sections, `:detail` panels, and query
  controls now emit as a basic-catalog `Card` over a `_body` container
  (`context_<name>` > `context_<name>_body`, `detail_<name>` >
  `detail_<name>_body`, `query<sfx>_controls` > `query<sfx>_controls_body`)
  — the same shape as form groups and card-style table rows, so every
  renderer gets consistent section chrome via the `--a2ui-card-*` theme
  variables. Root children ids are unchanged.
- Typeahead comboboxes for search pickers: the merged catalog
  (`priv/js/ash_a2ui_catalog.js`) now also overrides `Column` (opt-in by
  passing `ColumnApi` in the deps). The override renders exactly like the
  basic Column unless the component is an AshA2ui picker composite —
  detected via the frozen id contract (`context_<name>_body`,
  `form_select_<field>`) plus structural verification of the live
  component tree. Searchable composites become a real combobox: debounced
  search-as-you-type dispatching the existing `context_search` /
  `option_search` wire actions, results in an anchored overlay with
  keyboard navigation (arrows/Enter/Escape), a "Type to search…" hint
  instead of the pre-search option dump, and the selection collapsed to a
  chip with Clear. Non-searchable context pickers render their option page
  as a chip group with the selection highlighted. The wire format is
  unchanged (plain basic catalog) — renderers without the merged catalog
  fall back to the flat composite. New theme knobs: `--a2ui-combobox-*`
  and `--a2ui-chip-*`.

- Surface contexts: the new `context` DSL entity declares a named,
  server-validated record selection over any Ash resource that scopes the
  rest of the surface. Picker contexts emit a searchable surface-level
  picker (state at `/context/<name>`, options at `/options/<name>`) driven
  by the new `"context_search"` / `"context_select"` / `"context_clear"`
  client actions — every selection round-trips through an **authorized
  read**. `depends_on` + `depends_on_path` make dependent option sources
  (a parent's selection filters the child's options; changes cascade —
  dependents clear, re-derive, and `auto_select_single` re-selects sole
  options). Tables scope to selections with `context_filter` (equality
  ANDed onto every read) and `require_context` (no selection → no read,
  empty table); `select_context` adds a per-row button selecting a
  (typically pickerless) context — the master half of master/detail. All
  compile-verified by the new `AshA2ui.Verifiers.VerifyContexts`;
  context-less surfaces are byte-for-byte unchanged.
- `:detail` components: render a context's selected record as a
  field-by-field card bound to `/detail/<context>` (fields default to the
  context resource's public attributes; calculations/aggregates load like
  table fields) — the detail half of master/detail.
- Client-driven range filters: the `query` entity gains `range_filters`
  (public attributes only). The `/query` state gains a per-field
  `"ranges"` map (`{"from": "", "to": ""}`, inclusive bounds cast to the
  attribute's type before any read; plain `YYYY-MM-DD` bounds on datetime
  fields expand to day start/end), and the encoder emits from/to
  TextFields at `/query/ranges/<field>/from|to`.
- The LiveView transport tracks the last pushed `/context` state and
  passes it to PubSub refreshes as `:context_state` (like `:query_state`),
  so live refreshes preserve the user's selections;
  `AshA2ui.Info.build_surface/2` / `build_data_model/2` accept
  `:context_state` for custom transports.
- Form field groups: the new `group` DSL entity inside `:form` components
  (`group :scheduling do label "Scheduling"; columns 2; fields [...] end`)
  renders a labeled section — a Card wrapping a heading Text (h3) over the
  group's fields laid out in rows of `columns` equal-weight Columns (the
  last row padded with empty spacers; single-column groups skip the grid
  wrappers). Inputs, bindings, and submit semantics are unchanged — groups
  only re-arrange containers. Ordering contract: ungrouped fields render in
  place and a group renders whole at the position of its first member in
  the form's field order. Compile-verified (group fields ⊆ form fields,
  unique group names, no field in two groups) by the new
  `AshA2ui.Verifiers.VerifyLayouts`; group-less forms emit byte-identical
  payloads.
- Card-style table rows: the new singleton `row_layout` entity inside
  `:table` components (`row_layout do title :name; badge :is_active;
  badge_text true: "Active"; meta [...]; columns 3 end`) turns the templated
  record row into a Card — a header Row of the title Text (h4, weight 1)
  and a right-hand Row of the badge Text plus the row's actions/select
  button, over an N-column grid of caption-labeled meta values (honoring
  field `format`). The badge binds the new computed `_badge_<field>` row
  key (the `badge_text` entry matching the value, else the humanized value)
  serialized identically on initial render and every handler refresh; the
  raw field value stays untouched. `title`/`badge`/`meta` references are
  compile-verified against the table's fields (each at most once);
  layout-less tables keep the flat labeled-cell rows.
- Theming toolkit for `@a2ui/lit`-rendered surfaces (see the new
  [Theming](documentation/topics/theming.md) topic):
  - `priv/js/ash_a2ui_theme.css` — a neutral, dependency-free CSS-variable
    theme for the basic catalog (`--a2ui-*` tokens; shadow DOM makes CSS
    custom properties the only styling seam), designed to be imported and
    then overridden with the host app's design tokens.
  - `priv/js/ash_a2ui_catalog.js` — `createAshA2uiCatalog(deps)` builds a
    merged catalog registered under the basic catalog id whose
    ChoicePicker renders a native, token-themed `<select>` for
    `mutuallyExclusive` pickers (checkbox list for `multipleSelection`);
    the basic catalog has no dropdown display style through spec v1.0.
  - `configureAshA2ui` accepts an optional
    `markdown: {ContextProvider, context, render}` entry; the hook mounts
    a Lit context provider on its container so Text headings render as
    real headings instead of literal `## ...` markdown
    (upstream renders raw markdown without an injected renderer —
    google/A2UI#1226).
- Encoder: each table record now renders as a `Card` (`record_row`)
  wrapping `record_row_content` (the `Row` of cells), and every cell is a
  labeled pair — `table_cell_<field>` is a `Row` of a caption `Text`
  (`table_cell_<field>_label`, humanized field name) and the value `Text`
  (`table_cell_<field>_value`) — giving themed surfaces card chrome and
  readable "Label: value" rows with no DSL changes.
- Searchable relationship selects: the `field` entity gains `option_search`
  (a list of public string-typed destination attributes, compile-verified).
  Non-empty `option_search` swaps the static ChoicePicker for a composite —
  a selection-label Text (`/select/<field>/label`), a search TextField
  (`/select/<field>/search`) with a Search button dispatching the new
  `"option_search"` client action (case-insensitive contains OR'd across
  the allowlisted fields, actor/tenant-scoped destination read, clamped to
  `option_limit`, answered with one `updateDataModel` at
  `/options/<field>`), and an option List templated over `/options/<field>`
  whose per-option Buttons dispatch the new `"option_select"` action — the
  server re-fetches the picked record (policies apply), writes the value to
  `/form/<field>` and the canonical label to `/select/<field>`.
  Non-searchable selects are unchanged.
- Nested relationship forms: the new `nested_form` DSL entity inside `:form`
  components, named by the **action argument** a `manage_relationship`
  change consumes (compile-verified on every action the form submits by the
  new `AshA2ui.Verifiers.VerifyNestedForms`). The interaction mode is
  inferred from the change's options via
  `Ash.Changeset.ManagedRelationshipHelpers` — lookups (e.g.
  `type: :append_and_remove`) render as **pick_existing** (a picker adding
  existing records — searchable via `option_search` — and current rows with
  remove buttons), creates (e.g. `type: :direct_control`) as
  **create_inline** (sub-form rows; `fields` defaults to the destination
  create action's accepts minus the relationship's destination attribute).
  `/form/<argument>` is an always-present array of row maps mutated through
  the new server-mediated `"nested_add"`/`"nested_remove"` client actions
  (rows carry server-stamped `"_row"` identity keys); `select_row`
  populates the rows from the record's related records, `submit_form`
  strips underscore keys / reduces pick rows to ids before the argument
  cast, and nested validation errors map to
  `/errors/<argument>/<index>/<field>` plus `"_error_<field>"` in-row
  mirrors. Surfaces using these features carry a new `/select/<name>` state
  path. Deferred: many_to_many join-resource fields, recursive nesting,
  in-picker pagination.
- Row-action prompts: `action` entities gain `prompt_fields` (arguments/
  accepts of the Ash action, compile-verified) and `prompt_title`. Prompt
  actions render as a basic-catalog `Modal` (`row_action_<action>_modal`
  wrapping the trigger button and a content Column of TextFields bound to
  the new reserved `/prompt/values/<action>/<field>` paths). The trigger
  dispatches the new `"prompt"` client action (allowlist + `visible_when`
  enforced; pre-fills `/prompt/values/<action>` from the record and clears
  `/errors`); the Modal's Confirm sends `"invoke"` whose context now may
  carry a `"values"` map — filtered to the declared prompt fields, cast
  against the action's arguments/accepts, and passed as the action params
  (ignored entirely on prompt-less actions). Successful prompt invokes
  clear `/prompt/values/<action>`; validation errors land on
  `/errors/<field>` as usual. `refreshes` on `action` entities is now
  optional (omitted = refresh every table).
- Relationship-path search: `search_fields` entries may be relationship
  paths to public string attributes (`[:referrer, :email]`) — every step but
  the last a public relationship, verified at compile time; matched with the
  same case-insensitive contains through the path (`exists` semantics on
  to-many paths).
- Calculation filters: query `filters` may name expression-backed public
  calculations (equality on the calc value, cast against the calculation's
  type/constraints); module-based calculations are rejected at compile time,
  mirroring the sorting rule.
- Named filter presets: `preset` entities inside `query` declare server-side
  composite predicates the client selects by name only —
  `preset :pending do filter status: :pending, deleted_at: nil end`
  (keyword conditions ANDed; `nil` = `is_nil`, list = membership) or
  `preset :deleted do read_action :deleted end` (the escape hatch for
  predicates the keyword form can't express). `default_preset` applies when
  the client selects none and closes the preset set. `/query` state gains a
  `"preset"` key (only on preset-declaring queries) and the encoder emits a
  `query_preset_picker` ChoicePicker.
- Conditional row-action visibility: `action` entities gain `visible_when`
  (keyword equality/is_nil/membership conditions on public attributes or
  expression calculations, compile-verified castable). The handler enforces
  the conditions on every `invoke`/`prompt` (fetching the record with any
  condition calculations loaded; non-visible actions rejected via
  `/ui/status`). Rendering is best-effort: rows of affected tables gain
  `"_actions"` (visible action names) and `"_visible_<action>"`
  (`[{"id": ...}]`/`[]`) keys, and conditional actions render inside a
  `List` slot templated over the row-relative `_visible_<action>` path —
  the v0.9.1 basic catalog has no visibility property, so renderers without
  nested-template support fall back to `"_actions"`.
- Multi-key calculation sorting verified: `default_sort` and client sorts
  compose expression calculations with attributes
  (`default_sort status_priority: :asc, code: :asc`); no new machinery,
  pinned by test.

- `Ash.Type.Enum` attributes render as ChoicePickers: the TypeMapper now
  detects `Ash.Type.Enum` implementations (previously they fell back to
  TextField because their values live in the module, not in a `one_of`
  constraint), and form inputs and query filter pickers source their options
  from the enum's `values/0`, labeled via `label/1` when declared and
  humanized otherwise.

- Calculation & aggregate columns: table (and display) fields may name
  public calculations and aggregates. They are `Ash.Query.load`ed on every
  read path (initial render, post-action refreshes, `query` reads) and
  serialized through the JSON-safe serializer like attributes. Query
  `sortable`/`default_sort` allowlists accept public aggregates and
  expression-based calculations (anything `Ash.Resource.Info.sortable?/3`
  approves); module-based calculations and any calculation/aggregate in
  `search_fields`/`filters` are rejected at compile time with tailored
  messages, as are calculations/aggregates in form components (not
  writable).
- Multiple named table components: `component :table, :new_items do ... end`
  declares additional, independently configured table sections (own
  `fields`/`read_action`/`row_actions`/`query` each); the unnamed
  `component :table` keeps working (implicit name `:table`). Multi-table
  surfaces scope the data model per table (`/records/<component_name>`,
  `/query/<component_name>`), infix component ids with the table name, and
  render humanized section headings; single-table surfaces are entirely
  unchanged. `invoke`/`select_row` contexts additively carry
  `"component"`; `query` contexts require it on multi-table surfaces. New
  `AshA2ui.Verifiers.VerifyComponents` enforces unique component names,
  table-only naming, and a single `:form`.
- `refreshes` action metadata: `action :approve do refreshes [:new_items] end`
  limits which table components a successful action rewrites (default stays
  refresh-everything); targets and action reachability are compile-time
  verified. `/form`/`/errors`/`/ui/*` follow-up semantics are unchanged.

### Bug Fixes:

- `invoke` on an update-type action in `row_actions` now calls that action
  argument-less on the identified record. Previously it silently routed to
  the form's `update_action` with empty params — a no-op unless the invoked
  action happened to be the form's update action.

- Relationship rendering, part 1 — `belongs_to` form selects: a form field
  whose name matches a `belongs_to` relationship's `source_attribute` renders
  as a `ChoicePicker` automatically (options loaded from the destination's
  primary read action with the surface's `actor:`/`tenant:`/`authorize?:`
  opts). New `field` entity options `relationship` (explicit override),
  `option_label` (default: first existing public attribute of
  `[:name, :title, :label, :username, :email]`, else the destination PK),
  `option_value` (default: destination PK; composite PKs require it
  explicitly), `option_sort` (default: the resolved label, ascending) and
  `option_limit` (default: 100). Options are emitted inline in the picker and
  mirrored at the new reserved `/options/<field>` data-model path;
  single-select string-list submissions are unwrapped before casting.
  Compile-time verification via `AshA2ui.Verifiers.VerifyRelationships`.
- Relationship rendering, part 2 — `source` table columns: the new `source`
  field option (e.g. `source [:user, :email]`) renders a column read through
  the loaded relationship path. Record loading gains the needed
  `Ash.Query.load` statements on every read path; serialization walks the
  path nil-safely (nil/unloaded relationship -> `""`). Source columns are
  table-only and rejected in `ui_query` allowlists at compile time.
- Generic action results are now visible: `AshA2ui.ActionHandler` serializes
  map results to display text at the new reserved `/ui/action_result_text`
  path (one "Humanized key: value" line per key; the raw map stays at
  `/ui/action_result`), the encoder emits an always-present
  `action_result_panel` (Column wrapping a Text bound to it), and both paths
  are cleared on every subsequent successful action.

- Ship [`usage_rules`](https://hexdocs.pm/usage_rules)-compatible LLM usage
  rules: `usage-rules.md` plus `usage-rules/actions.md` and
  `usage-rules/liveview.md` sub-rules, included in the hex package so
  consumers can sync them with `mix usage_rules.sync`.
- `query` DSL entity: named, server-enforced allowlists for search
  (case-insensitive contains OR'd across `search_fields`), sorting
  (`sortable`), equality filters (`filters`), and pagination
  (`page_size`/`max_page_size`, limit/offset with a look-ahead `hasMore`).
  Tables reference a query via the new `query` component option; the encoder
  emits search/filter/pagination controls wired to the new `"query"` client
  action; `AshA2ui.ActionHandler` validates every request against the
  allowlist and rejects anything undeclared via `/ui/status`. The reserved
  `/query` data-model path carries the authoritative query state, and
  `submit_form`/`invoke` success refreshes respect the client's active query.
  Compile-time verification via `AshA2ui.Verifiers.VerifyQueries`.
- PubSub live refreshes preserve the user's query: `AshA2ui.LiveRenderer`
  tracks the last `/query` state pushed to the client and passes it to
  `AshA2ui.Info.build_data_model/2` via the new `:query_state` option
  (validated against the query allowlist; invalid state falls back to the
  declared defaults), so a refresh re-runs the current
  search/filters/sort/page instead of resetting the surface.

### Bug Fixes:

- A `multipleSelection` ChoicePicker reset to its "All" option submits
  `[""]`, which was cast to `field in []` (matching nothing) — empty-string
  list filter values are now treated as inactive, like `""` and `nil`.
