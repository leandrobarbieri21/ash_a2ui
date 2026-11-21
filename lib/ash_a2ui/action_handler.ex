defmodule AshA2ui.ActionHandler do
  @moduledoc """
  Consumes A2UI 1.0 renderer-to-agent messages and invokes the
  corresponding Ash actions (actor-aware, `authorize?: true` by default).

  ## Accepted messages

  `handle/3` takes one decoded renderer-to-agent message
  (`priv/a2ui/v1_0/json/renderer_to_agent.json`): `"version" => "1.0"` and
  exactly one of the four message keys.

    * `callAgentFunction` calling the ash_a2ui catalog's `ashAction`
      function, which is how every server-handled control the encoder
      emits reaches the agent (see `AshA2ui.Encoder.ash_action/3`):

          %{
            "version" => "1.0",
            "callAgentFunction" => %{
              "surfaceId" => "...",
              "functionCallId" => "...",
              "callFunction" => %{
                "@call" => "ashAction",
                "catalogId" => AshA2ui.Encoder.ash_catalog_id(),
                "args" => %{
                  "name" => "submit_form",
                  "sourceComponentId" => "...",
                  "context" => %{...}
                }
              }
            }
          }

      `args.name` and `args.context` dispatch as described below. The
      follow-ups end with one `agentFunctionResponse` carrying the same
      `functionCallId`: `value` is the settled `/ui/feedback` map on
      success (an empty map for a quiet action, which leaves it alone),
      `error` (`code`, `message`) on failure. Any other function,
      or `ashAction` under another catalog id, is answered with
      `UNKNOWN_FUNCTION`. A call that fails the `callAgentFunction` or the
      `ashAction` argument schema is answered with `INVALID_FUNCTION_CALL`.
      Both refusals settle `/ui/feedback` too. A call without a
      `functionCallId` cannot be answered and is refused like any other
      malformed message.

    * `action`, a plain event, is refused. The encoder never emits an
      event action, so a surface's controls only ever send `ashAction`
      calls. The refusal is logged and settles `/ui/feedback` with an
      `UNKNOWN_FUNCTION` error (the code the spec gives an agent for a
      request it does not run); there is no call to answer.

    * `rendererFunctionResponse`, the renderer's answer to a
      `callRendererFunction` (an export's `downloadFile`). It is validated
      and handed to the `:on_function_response` callback. No follow-ups.

    * `error`, a renderer-side error: `VALIDATION_FAILED`,
      `UNALLOWED_PARENT` or `UNALLOWED_CHILD` with `surfaceId` and `path`,
      or any other code with exactly one of `surfaceId` and
      `functionCallId`. It is logged at warning level with its code,
      surface, path and call id, never its message (which can quote data
      values). No follow-ups.

  Anything else (a `version` other than `"1.0"`, a missing or extra
  top-level key, a malformed body) returns `{:error, []}` and is logged.
  Top-level keys that start with `_` are not part of the message: a
  transport or a browser telemetry client adds them (a `_traceparent`, say)
  to every event it sends, so `handle/3` drops them before it validates
  (`drop_transport_keys/1`). Every other key is still checked strictly.
  The `surfaceId` on every follow-up always comes from the resolved view,
  never from the incoming message.

  ## Supported action names

    * `"submit_form"` — context
      `%{"values" => %{field => value}, "recordId" => id | nil}`. Without
      `"recordId"` the view's create action runs; with it, the update action.
      `values` keys are strings and are cast to the target action's accepted
      attributes and arguments by comparing against their known names (no
      dynamic atom creation); unknown keys are silently dropped. Values from
      single-select ChoicePickers (relationship selects, enums) may arrive as
      one-element string lists — they are unwrapped before Ash casts them to
      the attribute/argument type.

    * `"invoke"` — context
      `%{"action" => name, "recordId" => id | nil, "values" => map | absent}`.
      Invokes a destroy/update/generic action by name. The action **must be
      listed in the resolved view's `row_actions`** — that allowlist is the
      authorization surface for client-triggered actions; anything else is
      rejected with an error outcome before touching Ash. When the
      action's `action` entity declares `visible_when` conditions, the
      identified record is fetched (with any condition calculations loaded)
      and the conditions are evaluated server-side — an invoke on a
      non-visible action is rejected with an error outcome, regardless
      of what the client rendered. Destroy- and
      update-type actions run **the named action** on the record identified
      by `"recordId"`. Params are empty unless the action's `action` entity
      declares `prompt_fields`: then the context's `"values"` map is
      filtered to the declared prompt fields and cast against the Ash
      action's arguments/accepts (unknown keys silently dropped; `"values"`
      is ignored entirely for actions without `prompt_fields`); validation
      errors map to `/errors/<field>` as usual, and a success clears the
      action's `/prompt/values/<action>` state. For generic
      actions that define a `:record_id` argument, the context's `"recordId"`
      is passed through. A generic action returning a map has its raw result
      placed in the success feedback's `result` and a human-readable
      rendering (one "Humanized key: value" line per key) in its
      `resultText` (handler-defined conventions, not part of the A2UI
      spec). Every later outcome rewrites the whole feedback map, so a
      stale result never outlives its action. When the action's
      `action` entity declares `via`, the dispatch is delegated to the
      host-provided MFA instead of running the Ash action (see the `via`
      option docs on `AshA2ui`): the record is fetched as the direct path
      fetches it and passed in the delegate context with the actor, tenant,
      action name, surface id, and context selections; whatever the delegate
      returns — `:ok`, `{:ok, term}`, or `{:error, Ash.Error.t()}` — renders
      through the standard channels (refreshes honoring `refreshes`, status
      text, `/errors/<field>` mapping, `/ui/feedback`) unchanged. The
      client neither knows nor needs to know `via` exists.

    * `"prompt"` — context `%{"action" => name, "recordId" => id}`. Sent by
      the trigger button of a prompt Modal (see `AshA2ui.Encoder`)
      when it opens. The action must be an allowlisted row action declaring
      `prompt_fields`, and its `visible_when` conditions (if any) are
      enforced against the identified record. On success returns
      `updateDataModel` messages pre-filling `/prompt/values/<action>` (each
      prompt field's current record value when it is a public attribute,
      `""` otherwise) and clearing `/errors`. No Ash write happens — the
      write is the subsequent `"invoke"` from the Modal's confirm button.
      A relationship prompt field scoped by the action's `prompt_options`
      also gets the row's options, read as the actor through the scope's
      read action with the row's primary key as its `record_argument`, at
      `/prompt/options/<action>/<field>`, and the row's id at
      `/prompt/record/<action>`. That field's `"option_select"` and
      `"option_search"` (context `"prompt" => action, "recordId" => id`)
      re-read the row through the surface's read action (with the action's
      `visible_when` enforced) and evaluate the same scope: a value outside
      it is refused, and search results go to
      `/prompt/options/<action>/<field>`. `"invoke"` re-reads every picked
      value through the scope of the row it is invoked on before the write.

    * `"field_action"` — context `%{"component" => detail, "field" => name,
      "recordId" => id, "contexts" => selections}`. Runs the `field_action`
      a field of that `:detail` card declares (admin catalog 3.2): the
      client names the card and the field, never the Ash action, so the
      field's declaration is the allowlist. The record is re-read through
      the card's context as the actor (an authorized read, dependency
      filter included) with the field's `field_action_visible` loaded, and
      refused unless the record offers the action. The update action then
      runs on it with the field's name as its `:field` argument (when it
      declares one). A success re-reads the card's record into
      `/detail/<context>` (its review and field-action data included) and
      refreshes the tables the action's `refreshes` names, every table by
      default. With `"component"` naming a table (catalog 3.9) the row is
      re-read through the table's own read and context filters (`"query"`
      carries its state), and a success re-reads the records of the
      contexts the table is filtered by instead of a card's. On a `pairs`
      field (catalog 3.10) the context also carries `"item"`, the key of
      the item chosen: it is refused unless the row's items hold it and it
      offers the action, and the update receives it as its `:item`
      argument.

    * `"page_action"` — context `%{"action" => name, "recordId" => id,
      "contexts" => selections}`. Runs a page header button that runs an
      action (`header_action` with `run`, admin catalog 3.5): the client
      names the button, never the Ash action, so the header's declaration
      is the allowlist. The record is re-read through the header's context
      as the actor, and refused unless the button's `visible` field holds
      and `Ash.can?/3` lets the actor run the action on it. The update
      action then runs on it with no input. A success re-reads the header's
      record into `/detail/<context>` (every detail of that context) and
      refreshes the tables the action's `refreshes` names, every table by
      default.

    * `"save_changes"` — context `%{"edits" => %{card => %{"recordId" =>
      id, "values" => %{field => value}}}, "choice" => "save" | "then",
      "recordId" => id, "contexts" => selections}`. Saves a person's
      unsaved changes to the surface's editable `:detail` cards (admin
      catalog 3.11, the `save_bar`): the client names each card and field,
      never the Ash action, so each card's `editable` is the allowlist. Each
      card's record is re-read through its context as the actor and refused
      unless it offers editing (`editable` `visible`); its `update_action`
      then runs on it with the changed fields' values, cast to the
      attributes they edit (a field's `edit`). Every card's write runs in one
      transaction (on a data layer that has them): one refusal saves
      nothing. `"then"` also runs the save bar `confirm`'s `then_action` on
      the bar's record (`recordId`, refused unless its `then_visible`
      holds), in the same transaction. A success clears `/ui/edits` and
      `/ui/edit_errors`, re-reads each saved card's record into
      `/detail/<context>`, refreshes the tables the update action's
      `refreshes` names (every table by default), and reports the bar's
      `saved_message` (`then_saved_message` after `"then"`). A refusal
      keeps the changes, writes each edited field's message to
      `/ui/edit_errors/<card>/<field>`, and reports the rest as the outcome.

    * `"document_pane"` / `"document_region"` — a `document_pane` (admin
      catalog 3.4, see `AshA2ui.DocumentPane`) shown or hidden, and a region
      of it a person went to. Context `%{"pane" => name, "shown" =>
      boolean}` and `%{"pane" => name, "regionId" => id}`. The pane must be
      one the surface declares; the renderer has already drawn the change,
      and the handler writes it to `/ui/documents/<name>/shown` and
      `/ui/documents/<name>/selected`, so a host sees it like any other
      action (`AshA2ui.LiveRenderer` writes `shown` to the address). Both
      are quiet and read nothing.

    * `"bulk_invoke"` / `"bulk_select"` — bulk actions over a row selection
      on tables declaring `bulk_actions` (see `AshA2ui.Bulk` and the Bulk
      Actions topic). `bulk_invoke` takes `%{"action" => name, "component"
      => table, "records" => rows}`: the action must be in the view's
      `bulk_actions` (else refused before any read), the `"id"`s of rows
      whose `"_selected"` is `true` (non-empty, at most one page) are
      re-read through the table's read action and scope as the actor, ids
      the read does not return are refused, records failing `visible_when`
      are skipped, and every remaining record runs through the same
      dispatch as `invoke` (one call each, no shared transaction). The
      outcome goes to `/bulk/<table>/result` and `/ui/feedback` (kind
      `"warning"` on partial success); targets refresh once,
      and not at all when nothing was written. `bulk_select` takes
      `%{"component", "selected" => boolean}` and rewrites the table's
      re-read rows with `"_selected"` set.

    * `"start_create"` / `"view_record"` / `"start_edit"` /
      `"cancel_record_task"` — the task-panel actions (see
      `AshA2ui.Experience`). `start_create` opens the record panel in create
      mode over a fresh `/form` (rejected without a create action);
      `view_record` and `start_edit` take `%{"recordId" => id}` and fetch the
      record through an authorized read. `view_record` writes the read-only
      display values to `/ui/panel/record` and never touches `/form`;
      `start_edit` (rejected without a declared `update_action`) pre-flights
      the update authorization, so the edit panel never opens on a task the
      server would refuse to commit, then populates `/form` with the
      record's field values (including `"id"` and nested-form rows) and
      `/select` with the searchable selects' labels. The panel state
      (intent, mode, heading, primary label, submit visibility) carries the
      mode. `cancel_record_task` closes the panel, resets `/form`, and
      clears feedback. A successful `submit_form` closes the panel and
      returns to browse; a failed one keeps the mode, panel, and submitted
      values for correction.

    * `"wizard_next"` / `"wizard_back"` — the wizard-step actions of a form
      declaring `step` entities (see `AshA2ui.Wizard`). `wizard_next` takes
      `%{"values" => /form, "recordId" => id | nil, "index" => step}` and
      builds the changeset exactly as `submit_form` does (one shared path:
      the values are filtered to the form's own fields, cast, and run
      through `Ash.Changeset.for_create/4` or `for_update/4` on the record
      read through the surface's read action) **without** submitting it.
      On a stepped form `submit_form` applies the same field filter, so a
      key the action accepts but the form does not render reaches neither
      Next nor Submit. Only errors on fields of the current and earlier steps are
      written to `/errors/<field>` (the index stays), otherwise `/errors`
      clears and `/ui/wizard` moves to the next step. `wizard_back` takes
      `%{"index" => step}` and moves back without validating or touching
      `/form`. The carried index is clamped into the step range; a
      non-integer index is refused. Both also rewrite
      `/ui/panel/primary_label` and `/ui/panel/submit_visible`. A failed
      `submit_form` on a stepped form moves `/ui/wizard` to the earliest
      step owning an erroring field (the last step when none does).
      `start_create`, `view_record`, `start_edit`, `cancel_record_task` and a
      successful `submit_form` reset it to step 0. Surfaces without steps
      reject both names.

    * `"open_surface"` — context `%{"field" => name, "surface" => key,
      "recordId" => id}`, sent by the basic catalog's reference-link
      Buttons (see `AshA2ui.Encoder`). Accepted when `field` is a
      to-one link field (`link :relationship` or `link {surface, id_path}`)
      of one of the surface's tables or details and the
      `AshA2ui.LinkResolver` resolves it, for this actor, to `surface`;
      anything else is rejected with an error outcome. `"recordId"` is
      not checked: the opened surface authorizes its own read. A missing
      or empty `"surface"` (a row without a link for that field) is
      acknowledged.
      A context carrying `"diagram" => name` instead of `"field"` comes
      from a diagram marker (see `AshA2ui.Diagram`): accepted when the
      diagram's source, called again as the actor, returns a marker whose
      server-resolved link opens `surface`.
      Returns no follow-up messages: the transport navigates —
      `AshA2ui.LiveRenderer` hands an accepted request to its
      `"a2ui:open_surface"` handling (the `:open_surface` callback, else
      the `:open_surface_url` template).

    * `"query"` — context `%{"query" => <the /query map>}` plus an optional
      literal `"page"` override or relative `"pageDelta"` (used by the
      emitted Apply / prev / next controls). Requires the surface's table to
      declare a `query`; every requested search/sort/filter/page value is
      validated against that named allowlist by `AshA2ui.QueryRunner` —
      non-allowlisted values are rejected with an error outcome before
      Ash is called. On success returns `updateDataModel` messages for
      `/records` and `/query`.

    * `"context_search"` / `"context_select"` / `"context_clear"` — the
      surface-context actions (see `AshA2ui.ContextRunner` and the
      `context` DSL entity). Context
      `%{"context" => name, "search" => str | "value" => id, "contexts" => <the /context map>}`.
      `context_search` re-derives `/options/<name>` for a searchable
      context (dependency-filtered by the carried parent selections);
      `context_select` validates the picked value through an authorized
      read, cascades (dependents clear / re-derive / auto-select), and
      re-emits `/context`, the changed `/options/<name>` lists, the changed
      `/detail/<context>` records, and every table scoped to a changed
      context; `context_clear` cascades the same way from an unselection.

  On context-enabled surfaces *every* action's context may carry the
  current `/context` map under `"contexts"` — success refreshes and
  `"query"` reads then run under that scope: tables with an unmet
  `require_context` render no records (no read executes), and
  `context_filter` entries become equality filters ANDed onto the read.

  Unknown action names (including the removed `"select_row"`) get an
  `UNKNOWN_ACTION` error outcome.

  ## Follow-up messages

  The follow-ups are A2UI `updateDataModel` agent messages on the reserved
  data-model paths (see `topics/data-model-conventions`), plus an export's
  `callRendererFunction` and, for a function call, the final
  `agentFunctionResponse`. Every outcome (success, validation failure,
  rejection, refusal) writes one whole `/ui/feedback` map, the path the
  status Text and the admin statusBanner bind (see
  `AshA2ui.Experience.feedback/3`): `kind` (`"success"`, `"warning"`,
  `"error"`, or `""` when idle), `message`, `code` (`""` unless an error),
  `functionCallId` (the call's id, `""` when no call is answered), `result` and
  `resultText`.

    * on success: `/records` (re-read row maps, each including `"id"`;
      `source` columns are re-loaded and walked), `/form` cleared to `%{}`,
      `/errors` cleared to `%{}`, and a success `/ui/feedback` (its
      `result` and `resultText` carry a map-returning generic action's
      result, a report's row count, or an export's filename and row
      count). On query-enabled surfaces the re-read runs through
      the query (`submit_form`/`invoke` contexts may carry the current
      `/query` map under `"query"`; missing or invalid state falls back to
      the query's defaults) and a `/query` state message is included;
    * on validation errors: `/errors/<field>` per failing field and a
      `VALIDATION_FAILED` error;
    * on `Ash.Error.Forbidden`: only a `FORBIDDEN` "not authorized" error
      (no field errors, to avoid leaking policy details);
    * on any other error without a field: `ACTION_FAILED` with its message
      when it was written for the user (a string, an Invalid-class error),
      else "The action failed." with the error's text sent to
      `Logger.error/1` only (a raw exception or data-layer error can carry
      row values);
    * on a refused dispatch: `INVALID_ACTION` (a malformed context, an
      action outside the allowlist), `UNKNOWN_ACTION` (an unknown name) or
      `READ_ONLY_AS_OF` (a write on a surface pinned to an instant).

  The quiet actions (`quiet_actions/0`: reads, searches, picker and panel
  steps) leave `/ui/feedback` as it was unless they fail, and their
  function call is answered with an empty `value`. A renderer shows no
  pending state for them, so a page turn or a search keystroke never
  replaces the last outcome.

  Values are serialized JSON-safe (dates/datetimes to ISO 8601, decimals to
  strings, atoms to strings).
  """

  import Ash.Expr
  import AshA2ui.Gettext, only: [msg: 1, msg_plural: 2]

  require Ash.Query
  require Logger

  alias Ash.Error.Changes.InvalidAttribute
  alias Ash.Error.Invalid
  alias Ash.Error.Unknown.UnknownError
  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Bulk
  alias AshA2ui.Conditions
  alias AshA2ui.ContextRunner
  alias AshA2ui.Csv
  alias AshA2ui.DocumentPane
  alias AshA2ui.Encoder
  alias AshA2ui.Experience
  alias AshA2ui.L10n
  alias AshA2ui.Label
  alias AshA2ui.Masked
  alias AshA2ui.QueryRunner
  alias AshA2ui.ResolvedView

  # The ash_a2ui catalog function every server-handled control calls.
  @ash_action "ashAction"

  # The feedback a plain `action` event gets: the encoder never emits one.
  @event_refusal "ash_a2ui runs ashAction function calls, not action events."

  # Renderer error codes that point into a payload (with surfaceId and path).
  @path_error_codes ~w(VALIDATION_FAILED UNALLOWED_PARENT UNALLOWED_CHILD)

  # The field error a relationship prompt value the actor cannot read gets.
  @unavailable "is not one of the available options"

  # Actions that report no outcome of their own: reads, searches, picker and
  # panel steps. The renderer shows no pending state for them and the
  # handler leaves /ui/feedback as it was (see quiet_actions/0).
  @quiet_actions ~w(query option_search context_search option_select nested_add nested_remove
                    bulk_select prompt wizard_next wizard_back open_surface document_pane
                    document_region)

  # Actions that write, or open a form that would. On a surface pinned to an
  # instant (`:as_of`) every one is refused.
  @writes ~w(submit_form invoke field_action page_action save_changes bulk_invoke prompt edit_cell
             nested_add nested_remove start_create start_edit wizard_next wizard_back)

  @pinned_refusal msg(
                    "This view shows an earlier moment, so nothing on it can be changed. Return to now to make changes."
                  )

  @doc """
  The action names that report no outcome of their own: reads, searches,
  pickers and panel steps (`query`, `option_search`, `context_search`,
  `option_select`, `nested_add`, `nested_remove`, `bulk_select`, `prompt`,
  `wizard_next`, `wizard_back`, `open_surface`, `document_pane`,
  `document_region`).

  A renderer writes no pending feedback for an `ashAction` call to one of
  them, and the handler leaves `/ui/feedback` as it was unless the action
  fails, so a page turn or a search keystroke never replaces the last
  outcome. The shipped hook carries the same list (`QUIET_ACTIONS` in
  `priv/js/ash_a2ui_protocol.js`).
  """
  @spec quiet_actions() :: [String.t()]
  def quiet_actions, do: @quiet_actions

  @doc """
  Drops the top-level keys of a renderer-to-agent message that start with
  `_`.

  A2UI gives no top-level key a leading underscore, and transports use that
  prefix for their own metadata: a browser telemetry client, for one, adds
  `_traceparent` to the params of every LiveView event it sees. Such a key
  is not part of the message, so `handle/3` drops it before validating;
  only the top level is cleaned, and every other undeclared key is still
  refused. Anything that is not a map is returned unchanged.

      iex> AshA2ui.ActionHandler.drop_transport_keys(%{"version" => "1.0", "_traceparent" => "00-abc-def-01"})
      %{"version" => "1.0"}
  """
  @spec drop_transport_keys(term) :: term
  def drop_transport_keys(message) when is_map(message),
    do: Map.reject(message, fn {key, _value} -> transport_key?(key) end)

  def drop_transport_keys(message), do: message

  defp transport_key?(key) when is_binary(key), do: String.starts_with?(key, "_")
  defp transport_key?(_key), do: false

  @doc """
  The `callAgentFunction` message a renderer would send to run the
  `ashAction` `name` with `context` on the surface of
  `resource_or_ui_module`, for the server to put through `handle/3` itself.

  Use it when the server runs an action nobody clicked: a LiveView replaying
  the table query its URL names, a page running its reports on arrival, an
  agent transport turning a client request into the call the renderer would
  have made. The message goes through every check a renderer's call does
  (allowlist, authorization, `:as_of`), and `handle/3` answers it the same
  way, ending with an `agentFunctionResponse` (see
  `agent_function_response?/1`).

  The `surfaceId` is the one the surface is built with (its declared
  `surface_id`, or the default), so a LiveView with extra `:surfaces`
  routes the message to the right UI. The `functionCallId` is
  `"server-<name>-<n>"`, unique within the node. The call has no
  `sourceComponentId`, since no component sent it.

      iex> call = AshA2ui.ActionHandler.ash_action_call(AshA2ui.Test.MinimalUI, "query", %{"query" => %{}})
      iex> call["callAgentFunction"]["surfaceId"]
      "minimal_standalone"
      iex> call["callAgentFunction"]["callFunction"]["args"]
      %{"name" => "query", "context" => %{"query" => %{}}}
  """
  @spec ash_action_call(module | Spark.Dsl.t(), String.t(), map) :: map
  def ash_action_call(resource_or_ui_module, name, context)
      when is_binary(name) and name != "" and is_map(context) do
    %{
      "version" => Encoder.version(),
      "callAgentFunction" => %{
        "surfaceId" => ResolvedView.surface_id(resource_or_ui_module),
        "functionCallId" => "server-#{name}-#{System.unique_integer([:positive])}",
        "callFunction" => %{
          "@call" => @ash_action,
          "catalogId" => Encoder.ash_catalog_id(),
          "args" => %{"name" => name, "context" => context}
        }
      }
    }
  end

  @doc """
  Whether `message` is an `agentFunctionResponse`, the follow-up that
  settles a call.

  `handle/3` ends a call's follow-ups with one. A renderer waits on it. A
  server that made its own call (`ash_action_call/3`) and pushes the
  follow-ups to a renderer that never made that call drops it.

      iex> AshA2ui.ActionHandler.agent_function_response?(
      ...>   AshA2ui.Encoder.agent_function_response("call-1", {:ok, %{}})
      ...> )
      true
      iex> AshA2ui.ActionHandler.agent_function_response?(
      ...>   AshA2ui.Encoder.update_data_model("s", "/records", [])
      ...> )
      false
  """
  @spec agent_function_response?(term) :: boolean
  def agent_function_response?(%{"agentFunctionResponse" => _response}), do: true
  def agent_function_response?(_message), do: false

  @doc """
  Handles one A2UI 1.0 renderer-to-agent message for the surface declared on
  `resource_or_ui_module` (an `Ash.Resource` using the `AshA2ui` extension,
  or an `AshA2ui.Standalone` UI module).

  Returns `{:ok, messages}` or `{:error, messages}`, the agent-to-renderer
  follow-ups. An action outcome's messages carry the reserved
  `/errors/<field>` and `/ui/feedback` writes, and a function call's end with
  its `agentFunctionResponse`. A `rendererFunctionResponse` or an `error`
  returns `{:ok, []}`; a malformed message returns `{:error, []}`. Top-level
  keys that start with `_` are dropped first (`drop_transport_keys/1`). See
  the moduledoc for the accepted messages and the follow-ups.

  ## Options

    * `:actor` — the actor for the Ash action invocation (and the refresh
      read).
    * `:tenant` — the tenant for the Ash action invocation.
    * `:authorize?` — whether to authorize the Ash calls. Defaults to `true`.
    * `:as_of` — the instant the surface is pinned to (see
      `AshA2ui.Info.build_surface/2`). Reads (query, contexts, options,
      reports, exports) run at that instant; every action that writes, or
      opens a form that would, is refused with feedback, because the write
      would land on the present while the reader looks at the past.
    * `:locale` / `:gettext_backend` / `:gettext_fn` / `:metadata_domain` / `:errors_domain` —
      translate the feedback, status lines and any re-rendered chrome (see
      `AshA2ui.Info.build_surface/2`). Pass the same values the surface was
      built with.
    * `:catalog` — the catalog the surface was built with (see
      `AshA2ui.Info.build_surface/2`); omitted, the configured one.
    * `:on_function_response` — a 1-arity function called with the body of
      a valid `rendererFunctionResponse` (`%{"functionCallId" => id,
      "value" => value}` or `%{"functionCallId" => id, "error" => %{"code"
      => code, "message" => message}}`). Correlating the id with the call
      that asked for it is the transport's job; `AshA2ui.LiveRenderer`
      does it for the calls it pushed.
  """
  @spec handle(module | Spark.Dsl.t(), message :: map, opts :: keyword) ::
          {:ok, [map]} | {:error, [map]}
  def handle(resource_or_ui_module, message, opts \\ []) do
    case message |> drop_transport_keys() |> parse() do
      {:call, call_id, name, context} ->
        run(resource_or_ui_module, name, context, call_id, opts)

      :refuse_event ->
        Logger.warning(
          "Refused an A2UI action event: ash_a2ui answers ashAction function calls only."
        )

        view = ResolvedView.resolve(resource_or_ui_module, opts)
        {:error, [status(view, @event_refusal, "UNKNOWN_FUNCTION")]}

      {:refuse_call, call_id, code, text} ->
        Logger.warning("Refused A2UI callAgentFunction #{call_id} (#{code}): #{text}")
        view = ResolvedView.resolve(resource_or_ui_module, opts)
        settle({:error, [status(view, text, code)]}, view, call_id, nil)

      {:function_response, response} ->
        callback = opts[:on_function_response]
        if is_function(callback, 1), do: callback.(response)
        {:ok, []}

      {:renderer_error, error} ->
        log_renderer_error(error)
        {:ok, []}

      {:invalid, reason} ->
        Logger.warning("Refused an A2UI renderer message: #{reason}.")
        {:error, []}
    end
  end

  defp run(resource_or_ui_module, name, context, call_id, opts) do
    view = ResolvedView.resolve(resource_or_ui_module, opts)

    result =
      if name in @writes and AshA2ui.AsOf.pinned?(opts) do
        {:error, [status(view, t(view, @pinned_refusal), "READ_ONLY_AS_OF")]}
      else
        expand_and_dispatch(view, ash_opts(view, opts), name, context)
      end

    settle(result, view, call_id, name)
  end

  defp expand_and_dispatch(view, ash_opts, name, context) do
    case AshA2ui.Sections.expand(view, ash_opts) do
      {:ok, view} ->
        env = %{
          view: view,
          ash_opts: ash_opts,
          refresh: refresh_params(view, context),
          selected: ContextRunner.selected(view, Map.get(context, "contexts"))
        }

        dispatch(name, context, env)

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # --- settling an outcome -----------------------------------------------------

  # Every failure settles /ui/feedback, the one path the status Text and the
  # admin statusBanner bind: one without a feedback write gets the generic
  # one. A quiet action's success leaves the feedback as it was. Every other
  # action writes its outcome; should one not, the call settles the feedback
  # to idle, since the renderer showed a pending state under the call's id
  # and that state must not outlive the call.
  #
  # Every feedback write carries the call's id, and the agentFunctionResponse
  # goes last, so the data model (feedback included) is settled before the
  # renderer resolves the call: `value` is the final feedback map (an empty
  # map when the call left the feedback alone), `error` its code and
  # message.
  defp settle({tag, messages}, view, call_id, name) do
    messages =
      cond do
        Enum.any?(messages, &feedback_write?/1) ->
          messages

        tag == :error ->
          messages ++ [status(view, t(view, msg("The action failed.")), "ACTION_FAILED")]

        name not in @quiet_actions ->
          messages ++ [update_data_model(view, "/ui/feedback", Experience.clear_feedback())]

        true ->
          messages
      end

    messages = Enum.map(messages, &stamp_call_id(&1, call_id))
    feedback = messages |> Enum.filter(&feedback_write?/1) |> List.last()
    {tag, messages ++ [function_response(tag, view, call_id, feedback_value(feedback))]}
  end

  defp feedback_write?(message),
    do: match?(%{"updateDataModel" => %{"path" => "/ui/feedback"}}, message)

  defp feedback_value(%{"updateDataModel" => %{"value" => value}}), do: value
  defp feedback_value(nil), do: %{}

  defp stamp_call_id(
         %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => value} = update} = message,
         call_id
       ),
       do: %{
         message
         | "updateDataModel" => %{update | "value" => Map.put(value, "functionCallId", call_id)}
       }

  defp stamp_call_id(message, _call_id), do: message

  defp function_response(:ok, _view, call_id, feedback),
    do: Encoder.agent_function_response(call_id, {:ok, feedback})

  defp function_response(:error, view, call_id, feedback) do
    code = non_empty(feedback["code"]) || "ACTION_FAILED"
    message = non_empty(feedback["message"]) || t(view, msg("The action failed."))
    Encoder.agent_function_response(call_id, {:error, code, message})
  end

  defp non_empty(value) when is_binary(value) and value != "", do: value
  defp non_empty(_value), do: nil

  # --- parsing renderer messages ---------------------------------------------

  # A renderer-to-agent message is "version" => "1.0" plus exactly one of the
  # four message keys (renderer_to_agent.json). The version is checked first,
  # for every kind of message. Returns:
  #
  #   * {:call, call_id, name, context} — dispatch;
  #   * :refuse_event — a plain `action` event, which ash_a2ui does not run;
  #   * {:refuse_call, call_id, code, text} — a function call that can be
  #     answered, with an error (UNKNOWN_FUNCTION, INVALID_FUNCTION_CALL);
  #   * {:function_response, body} / {:renderer_error, body} — no follow-ups;
  #   * {:invalid, reason} — nothing to answer; the reason is logged and
  #     names fields, never their values.
  defp parse(%{"version" => "1.0"} = message) when map_size(message) == 2 do
    case message |> Map.delete("version") |> Map.to_list() do
      [{"action", _body}] -> :refuse_event
      [{"callAgentFunction", body}] -> parse_call(body)
      [{"rendererFunctionResponse", body}] -> parse_function_response(body)
      [{"error", body}] -> parse_renderer_error(body)
      [{_key, _body}] -> {:invalid, "not a renderer-to-agent message"}
    end
  end

  defp parse(%{"version" => "1.0"}),
    do: {:invalid, ~s(expected "version" and exactly one message key)}

  defp parse(%{"version" => _version}), do: {:invalid, ~s(version is not "1.0")}
  defp parse(%{}), do: {:invalid, ~s(no "version")}
  defp parse(_message), do: {:invalid, "not a JSON object"}

  # A call without a functionCallId cannot be answered, since the response
  # must copy it; anything else wrong with the call is answered.
  defp parse_call(%{"functionCallId" => call_id} = body)
       when is_binary(call_id) and call_id != "" do
    case call_function(body) do
      {:ok, name, context} -> {:call, call_id, name, context}
      {:error, code, text} -> {:refuse_call, call_id, code, text}
    end
  end

  defp parse_call(_body),
    do: {:invalid, "callAgentFunction without a functionCallId cannot be answered"}

  defp call_function(body) do
    with :ok <- only_keys(body, ~w(surfaceId functionCallId callFunction), "callAgentFunction"),
         :ok <- non_empty_string(body, "surfaceId", "callAgentFunction"),
         {:ok, call} <- object(body, "callFunction", "callAgentFunction"),
         :ok <- non_empty_string(call, "@call", "callFunction"),
         :ok <- only_keys(call, ~w(@call catalogId args), "callFunction"),
         :ok <- agent_function(call) do
      ash_action_args(Map.get(call, "args"))
    end
  end

  # The agent's only function is ashAction in the ash_a2ui catalog. A call
  # naming no catalog resolves to it by name; a renderer function (any basic
  # catalog function, the agentOnly downloadFile) is not an agent function.
  defp agent_function(%{"@call" => name} = call) do
    catalog_id = Map.get(call, "catalogId", Encoder.ash_catalog_id())

    cond do
      not is_binary(catalog_id) ->
        {:error, "INVALID_FUNCTION_CALL", ~s(callFunction "catalogId" must be a string.)}

      name == @ash_action and catalog_id == Encoder.ash_catalog_id() ->
        :ok

      true ->
        {:error, "UNKNOWN_FUNCTION",
         "#{inspect(String.slice(name, 0, 64))} is not a function this agent runs."}
    end
  end

  defp ash_action_args(args) when is_map(args) do
    with :ok <- only_keys(args, ~w(name sourceComponentId context), "ashAction args"),
         :ok <- non_empty_string(args, "name", "ashAction args"),
         true <-
           optional?(args, "sourceComponentId", &is_binary/1) ||
             invalid_arg("sourceComponentId", "a string"),
         true <- optional?(args, "context", &is_map/1) || invalid_arg("context", "an object") do
      {:ok, args["name"], Map.get(args, "context", %{})}
    end
  end

  defp ash_action_args(_args),
    do: {:error, "INVALID_FUNCTION_CALL", ~s(ashAction needs an "args" object.)}

  defp invalid_arg(key, type),
    do: {:error, "INVALID_FUNCTION_CALL", ~s(ashAction args "#{key}" must be #{type}.)}

  defp only_keys(map, allowed, where) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      _extra -> {:error, "INVALID_FUNCTION_CALL", "#{where} has an undeclared key."}
    end
  end

  defp non_empty_string(map, key, where) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" ->
        :ok

      _other ->
        {:error, "INVALID_FUNCTION_CALL", ~s(#{where} "#{key}" must be a non-empty string.)}
    end
  end

  defp object(map, key, where) do
    case Map.get(map, key) do
      value when is_map(value) -> {:ok, value}
      _other -> {:error, "INVALID_FUNCTION_CALL", ~s(#{where} "#{key}" must be an object.)}
    end
  end

  defp optional?(map, key, valid?), do: not Map.has_key?(map, key) or valid?.(map[key])

  # FunctionResponse: a non-empty functionCallId (nothing correlates an
  # empty one) and exactly one of value or error {code, message}.
  defp parse_function_response(%{"functionCallId" => call_id} = body)
       when is_binary(call_id) and call_id != "" do
    case Map.delete(body, "functionCallId") do
      %{"value" => _value} = rest when map_size(rest) == 1 ->
        {:function_response, body}

      %{"error" => %{"code" => code, "message" => message} = error} = rest
      when map_size(rest) == 1 and map_size(error) == 2 and is_binary(code) and
             is_binary(message) ->
        {:function_response, body}

      _other ->
        {:invalid, "rendererFunctionResponse needs exactly one of value or error {code, message}"}
    end
  end

  defp parse_function_response(_body),
    do: {:invalid, "rendererFunctionResponse needs a non-empty functionCallId"}

  # A path error (VALIDATION_FAILED, UNALLOWED_PARENT, UNALLOWED_CHILD)
  # carries exactly code, message, surfaceId and path; any other code
  # carries exactly one of surfaceId and functionCallId.
  defp parse_renderer_error(%{"code" => code, "message" => message} = error)
       when code in @path_error_codes and is_binary(message) do
    if Map.keys(error) -- ~w(code message surfaceId path) == [] and
         is_binary(error["surfaceId"]) and is_binary(error["path"]) do
      {:renderer_error, error}
    else
      {:invalid, "a #{code} error needs exactly code, message, surfaceId and path"}
    end
  end

  defp parse_renderer_error(%{"code" => code, "message" => message} = error)
       when is_binary(code) and is_binary(message) do
    case {Map.fetch(error, "surfaceId"), Map.fetch(error, "functionCallId")} do
      {{:ok, surface_id}, :error} when is_binary(surface_id) -> {:renderer_error, error}
      {:error, {:ok, call_id}} when is_binary(call_id) -> {:renderer_error, error}
      _neither_or_both -> {:invalid, "an error needs exactly one of surfaceId and functionCallId"}
    end
  end

  defp parse_renderer_error(_error), do: {:invalid, "an error needs a string code and message"}

  # The renderer's message can quote data values, so it stays out of the log.
  defp log_renderer_error(error) do
    fields =
      for key <- ~w(surfaceId path functionCallId), Map.has_key?(error, key) do
        "#{key}=#{inspect(error[key])}"
      end

    Logger.warning(Enum.join(["A2UI renderer error #{error["code"]}" | fields], " "))
  end

  # Success refreshes respect the client's current query state when a table
  # has a `query` configured: any action context may carry the current
  # `/query` value under `"query"` — the single table's state map, or (on
  # multi-table surfaces) the whole per-table state object. Returns
  # `%{table_name => params | nil}` (nil for tables without a query). A
  # missing or invalid carried state falls back to the query's declared
  # defaults (the write itself is never failed over refresh state).
  defp refresh_params(view, context) do
    carried = (is_map(context) && Map.get(context, "query")) || nil

    Map.new(view.tables, fn table ->
      {table.name, table_refresh_params(view, table, carried)}
    end)
  end

  defp table_refresh_params(_view, %{query: nil}, _carried), do: nil

  defp table_refresh_params(view, table, carried) do
    state =
      if ResolvedView.multi_table?(view) do
        is_map(carried) && Map.get(carried, to_string(table.name))
      else
        carried
      end

    case QueryRunner.parse(table, %{"query" => state}) do
      {:ok, params} -> params
      {:error, _reason} -> QueryRunner.default_params(table)
    end
  end

  defp ash_opts(view, opts) do
    [
      domain: ResourceInfo.domain(view.resource),
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    ] ++ AshA2ui.AsOf.read_opt(opts)
  end

  # --- dispatch --------------------------------------------------------------

  defp dispatch("submit_form", context, env) do
    values = Map.get(context, "values") || %{}

    env =
      env
      |> Map.put(:submitted, values)
      |> Map.put(:shown_fields, form_shown_fields(env.view))

    case Map.get(context, "recordId") do
      nil -> create(env, values)
      record_id -> update(env, record_id, values)
    end
  end

  defp dispatch("invoke", context, env), do: invoke_dispatch(context, env)

  defp dispatch("field_action", context, env), do: field_action(context, env)

  defp dispatch("page_action", context, env), do: page_action(context, env)

  defp dispatch("save_changes", context, env), do: save_changes(context, env)

  defp dispatch("bulk_invoke", context, env), do: bulk_invoke(context, env)

  defp dispatch("bulk_select", context, env), do: bulk_select(context, env)

  defp dispatch("prompt", context, %{view: view, ash_opts: ash_opts}) do
    requested = Map.get(context, "action")
    allowed = requested && Enum.find(view.row_actions, &(to_string(&1) == requested))
    setting = allowed && Map.get(view.actions, allowed)
    record_id = Map.get(context, "recordId")

    cond do
      not is_binary(requested) ->
        {:error, [status(view, ~s(Malformed prompt action: context is missing "action".))]}

      is_nil(allowed) ->
        {:error,
         [
           status(
             view,
             "Action #{inspect(requested)} is not allowed: it is not listed in the " <>
               "view's row_actions."
           )
         ]}

      not match?(%{prompt_fields: [_ | _]}, setting) ->
        {:error, [status(view, "Action #{inspect(requested)} does not declare prompt_fields.")]}

      is_nil(record_id) ->
        {:error, [status(view, ~s(Malformed prompt action: context is missing "recordId".))]}

      true ->
        prompt(view, setting, record_id, ash_opts)
    end
  end

  defp dispatch("report", context, %{view: view, ash_opts: ash_opts}) do
    with {:ok, report} <- report_target(view, context) do
      run_report(view, report, Map.get(context, "params"), ash_opts)
    end
  end

  defp dispatch("export", context, %{view: view} = env) do
    with {:ok, target} <- export_target(view, context),
         {:ok, columns} <- export_columns(view, target, context),
         {:ok, row_maps} <- export_row_maps(target, context, env) do
      deliver_export(view, target, columns, row_maps)
    end
  end

  defp dispatch("edit_cell", context, %{view: view} = env) do
    with {:ok, table} <- edit_table(view, context),
         {:ok, field} <- edit_field(view, table, context) do
      case Map.get(context, "recordId") do
        record_id when is_binary(record_id) ->
          edit_cell(table, field, record_id, Map.get(context, "value"), env)

        _missing ->
          {:error, [status(view, ~s(Malformed edit_cell action: context is missing "recordId".))]}
      end
    end
  end

  defp dispatch("query", context, %{view: view, ash_opts: ash_opts, selected: selected}) do
    with {:table, {:ok, table}} <- {:table, query_table(view, context)},
         {:parse, {:ok, params}} <- {:parse, QueryRunner.parse(table, context)} do
      case ContextRunner.table_scope(view, table, selected) do
        :require_unmet -> {:ok, require_unmet_messages(view, table, params)}
        {:ok, scope} -> run_scoped_query(view, table, params, scope, ash_opts)
      end
    else
      {:table, {:error, reason}} -> {:error, [status(view, reason)]}
      {:parse, {:error, reason}} -> {:error, [status(view, reason)]}
    end
  end

  defp dispatch("context_search", context, %{view: view, ash_opts: ash_opts, selected: selected}) do
    search = Map.get(context, "search") || ""

    with {:ok, ctx} <- resolve_context(view, "context_search", context),
         :ok <- validate_context_search(view, ctx, search) do
      case ContextRunner.load_options(view, ctx, selected, search, ash_opts) do
        {:ok, options} ->
          {:ok, [update_data_model(view, "/options/#{ctx.name}", options)]}

        {:error, error} ->
          {:error, error_messages(view, error)}
      end
    end
  end

  defp dispatch("context_select", context, %{view: view} = env) do
    value = unwrap_picked(Map.get(context, "value"))

    with {:ok, ctx} <- resolve_context(view, "context_select", context) do
      if is_binary(value) and value != "" do
        select_context(ctx, value, env)
      else
        {:error, [status(view, ~s(Malformed context_select action: context is missing "value".))]}
      end
    end
  end

  defp dispatch("context_clear", context, %{view: view} = env) do
    with {:ok, ctx} <- resolve_context(view, "context_clear", context) do
      case ContextRunner.clear(view, ctx, env.selected, env.ash_opts) do
        {:ok, change} -> context_change_messages(change, env)
        {:error, error} -> {:error, error_messages(view, error)}
      end
    end
  end

  defp dispatch("option_search", context, %{view: view} = env) do
    name = Map.get(context, "field")
    search = Map.get(context, "search") || ""

    case is_binary(name) && option_select_target(view, name, Map.get(context, "prompt")) do
      {{:prompt, _action}, _field, %{scope: %{}}} = target ->
        scoped_option_search(target, search, context, env)

      _form_or_unscoped ->
        option_search(name, search, env)
    end
  end

  defp dispatch("option_select", context, %{view: view, ash_opts: ash_opts}) do
    name = Map.get(context, "field")
    value = unwrap_picked(Map.get(context, "value"))
    select = is_binary(name) && option_select_target(view, name, Map.get(context, "prompt"))

    cond do
      not is_binary(name) ->
        {:error, [status(view, ~s(Malformed option_select action: context is missing "field".))]}

      not option_selectable?(select) ->
        {:error,
         [
           status(
             view,
             "Field #{inspect(name)} is not a searchable select: it declares no option_search."
           )
         ]}

      not is_binary(value) or value == "" ->
        {:error, [status(view, ~s(Malformed option_select action: context is missing "value".))]}

      true ->
        {target, field, select_config} = select

        with {:ok, row} <- option_row(view, target, select_config, context, ash_opts) do
          selected_option_messages(view, target, field, select_config, value, ash_opts, row)
        end
    end
  end

  defp dispatch("nested_add", context, %{view: view, ash_opts: ash_opts}) do
    with {:ok, argument, nested} <- nested_target(view, context) do
      rows = sanitize_rows(Map.get(context, "rows"))

      case nested.mode do
        :create_inline ->
          {:ok, [update_data_model(view, "/form/#{argument}", rows ++ [blank_row(nested)])]}

        :pick_existing ->
          nested_pick(view, argument, nested, rows, context, ash_opts)
      end
    end
  end

  defp dispatch("nested_remove", context, %{view: view}) do
    with {:ok, argument, _nested} <- nested_target(view, context) do
      row = Map.get(context, "row")

      if is_binary(row) do
        rows =
          context
          |> Map.get("rows")
          |> sanitize_rows()
          |> Enum.reject(&(Map.get(&1, "_row") == row))

        {:ok, [update_data_model(view, "/form/#{argument}", rows)]}
      else
        {:error, [status(view, ~s(Malformed nested_remove action: context is missing "row".))]}
      end
    end
  end

  # --- task panel ------------------------------------------------------------

  defp dispatch("start_create", _context, env), do: start_create(env)
  defp dispatch("view_record", context, env), do: view_record(env, context)
  defp dispatch("start_edit", context, env), do: start_edit(env, context)
  defp dispatch("cancel_record_task", _context, env), do: cancel_record_task(env)

  defp dispatch("wizard_next", context, env), do: wizard_next(env, context)
  defp dispatch("wizard_back", context, env), do: wizard_back(env, context)

  defp dispatch("open_surface", context, env), do: open_surface(context, env)

  defp dispatch("document_pane", context, env), do: document_pane(context, env)
  defp dispatch("document_region", context, env), do: document_region(context, env)

  defp dispatch(name, _context, %{view: view}) do
    unknown_action(view, name)
  end

  # --- document panes ----------------------------------------------------------

  # A pane shown or hidden: the renderer drew it already; the data model
  # keeps it (and the LiveRenderer the address).
  defp document_pane(context, %{view: view}) do
    with {:ok, pane} <- document_pane_named(view, context),
         shown when is_boolean(shown) <- Map.get(context, "shown") do
      {:ok, [update_data_model(view, DocumentPane.ui_path(pane) <> "/shown", shown)]}
    else
      {:error, messages} ->
        {:error, messages}

      _not_boolean ->
        {:error,
         [status(view, ~s(Malformed document_pane action: "shown" must be true or false.))]}
    end
  end

  # A region a person went to. Any id is accepted: it is only ever written
  # back to the pane's own state, never read.
  defp document_region(context, %{view: view}) do
    with {:ok, pane} <- document_pane_named(view, context),
         id when is_binary(id) and id != "" <- Map.get(context, "regionId") do
      {:ok, [update_data_model(view, DocumentPane.ui_path(pane) <> "/selected", id)]}
    else
      {:error, messages} ->
        {:error, messages}

      _not_an_id ->
        {:error, [status(view, ~s(Malformed document_region action: "regionId" must be text.))]}
    end
  end

  defp document_pane_named(view, context) do
    name = Map.get(context, "pane")

    case Enum.find(view.document_panes, &(is_binary(name) and Atom.to_string(&1.name) == name)) do
      nil -> {:error, [status(view, "This surface has no such document pane.")]}
      pane -> {:ok, pane}
    end
  end

  # Opens the create task: the panel in create mode over a fresh /form,
  # prior feedback and stale errors cleared. Rejected on formless surfaces
  # without a create action (the affordance is never emitted there anyway).
  defp start_create(%{view: view} = _env) do
    if view.create_action do
      {:ok,
       [
         update_data_model(view, "/ui/intent", "create"),
         update_data_model(view, "/ui/panel", Experience.panel_state(:create, view, nil)),
         update_data_model(view, "/form", ResolvedView.initial_form(view)),
         update_data_model(view, "/errors", %{}),
         update_data_model(view, "/ui/feedback", Experience.clear_feedback())
       ] ++ wizard_reset(view)}
    else
      {:error, [status(view, "This surface does not declare a create action.")]}
    end
  end

  defp view_record(%{view: view, ash_opts: ash_opts} = _env, context) do
    case Map.get(context, "recordId") do
      nil ->
        {:error, [status(view, ~s(Malformed view_record action: context is missing "recordId".))]}

      record_id ->
        result =
          with {:ok, record} <-
                 fetch_record(view, record_id, ash_opts, view_loads(view)) do
            {:ok,
             task_open_messages(view, :view, record) ++
               panel_record_population(view, record, ash_opts)}
          end

        case result do
          {:ok, messages} -> {:ok, messages}
          {:error, error} -> {:error, error_messages(view, error)}
        end
    end
  end

  # start_edit is the EXPLICIT transition onto the form buffer, gated on a
  # declared update action: no declared update, no edit mode (the encoder
  # never offers the affordance either, and a hand-crafted event gets this
  # rejection instead of the primary-action fallback — or a crash on
  # resources without any update action at all).
  defp start_edit(%{view: %{update_action: nil} = view}, _context) do
    {:error, [status(view, "This surface does not declare an update action.")]}
  end

  # The edit pre-flight runs the update authorization before the panel ever
  # opens (the write itself only happens on the subsequent submit_form): a
  # record the actor may read but not update is rejected here.
  defp start_edit(%{view: view, ash_opts: ash_opts} = _env, context) do
    case Map.get(context, "recordId") do
      nil ->
        {:error, [status(view, ~s(Malformed start_edit action: context is missing "recordId".))]}

      record_id ->
        result =
          with {:ok, record} <-
                 fetch_record(view, record_id, ash_opts, ResolvedView.form_loads(view)),
               :ok <- authorize_update(view, record, ash_opts) do
            {:ok, task_open_messages(view, :edit, record) ++ form_population(view, record)}
          end

        case result do
          {:ok, messages} -> {:ok, messages}
          {:error, error} -> {:error, error_messages(view, error)}
        end
    end
  end

  defp authorize_update(view, record, ash_opts) do
    changeset = Ash.Changeset.for_update(record, view.update_action, %{}, ash_opts)

    if Ash.can?(changeset, ash_opts[:actor]) do
      :ok
    else
      {:error, %Ash.Error.Forbidden{}}
    end
  end

  defp cancel_record_task(%{view: view} = _env) do
    {:ok,
     [
       update_data_model(view, "/ui/intent", "browse"),
       update_data_model(view, "/ui/panel", Experience.panel_state(:hidden)),
       update_data_model(view, "/form", ResolvedView.initial_form(view)),
       update_data_model(view, "/errors", %{}),
       update_data_model(view, "/ui/feedback", Experience.clear_feedback())
     ] ++ wizard_reset(view)}
  end

  # The task-open write set: intent + panel for the mode, stale errors and
  # feedback cleared. The /form population rides along from the caller.
  defp task_open_messages(view, mode, record) do
    [
      update_data_model(view, "/ui/intent", to_string(mode)),
      update_data_model(view, "/ui/panel", Experience.panel_state(mode, view, record.id)),
      update_data_model(view, "/errors", %{}),
      update_data_model(view, "/ui/feedback", Experience.clear_feedback())
    ] ++ wizard_reset(view)
  end

  # A reference-link activation (the basic catalog's link Buttons, see
  # AshA2ui.Encoder): accepted only for a to-one link field of this
  # view whose LinkResolver answer, for this actor, is the requested
  # surface — compared as strings, nothing from the client becomes an
  # atom. No follow-ups: navigating is the transport's job
  # (AshA2ui.LiveRenderer routes an accepted open_surface to its
  # "a2ui:open_surface" handling). A row without a link for the field binds
  # no surface: acknowledged, nothing to open.
  defp open_surface(%{"diagram" => diagram} = context, env) when is_binary(diagram) do
    open_diagram_surface(diagram, Map.get(context, "surface"), env)
  end

  defp open_surface(context, %{view: view, ash_opts: ash_opts}) do
    field = Map.get(context, "field")
    surface = Map.get(context, "surface")

    cond do
      surface in [nil, ""] ->
        {:ok, []}

      not (is_binary(field) and is_binary(surface)) ->
        {:error,
         [
           status(
             view,
             ~s(Malformed open_surface action: context needs "field" and "surface" strings.)
           )
         ]}

      surface in link_surfaces(view, field, ash_opts) ->
        {:ok, []}

      true ->
        {:error,
         [status(view, "Field #{inspect(field)} does not link to #{inspect(surface)} here.")]}
    end
  end

  # A diagram marker's link (the basic composition's marker Buttons):
  # accepted only when the diagram's source, called again as this actor,
  # returns a marker whose server-resolved link opens `surface`. A marker
  # without a link binds no surface: acknowledged, nothing to open.
  defp open_diagram_surface(_diagram, surface, _env) when surface in [nil, ""], do: {:ok, []}

  defp open_diagram_surface(diagram, surface, %{view: view} = env) when is_binary(surface) do
    surfaces = AshA2ui.Diagram.link_surfaces(view, diagram, env.selected, env.ash_opts)

    if surface in surfaces do
      {:ok, []}
    else
      {:error,
       [status(view, "Diagram #{inspect(diagram)} does not link to #{inspect(surface)} here.")]}
    end
  end

  defp open_diagram_surface(_diagram, _surface, %{view: view}) do
    {:error, [status(view, ~s(Malformed open_surface action: "surface" must be a string.))]}
  end

  # The surfaces `field` (a client string) opens on this view: every table
  # and detail listing a to-one link field of that name, resolved like the
  # encoder resolves it for the rows' `_links`.
  defp link_surfaces(view, field, ash_opts) do
    scopes =
      Enum.map(view.tables, &{&1.resource, table_fields(&1)}) ++
        Enum.map(view.details, &{view.contexts[&1.context].resource, &1.fields})

    for {resource, fields} <- scopes,
        name <- fields,
        Atom.to_string(name) == field,
        %{specs: specs} <- [AshA2ui.Links.context(resource, view.fields, [name], ash_opts)],
        %{surface: surface, cardinality: cardinality} <- specs,
        is_binary(surface) and cardinality in [:one, :path],
        do: surface
  end

  defp unknown_action(view, name) do
    {:error, [status(view, "Unknown action #{inspect(name)}.", "UNKNOWN_ACTION")]}
  end

  defp invoke_dispatch(context, %{view: view} = env) do
    requested = Map.get(context, "action")
    allowed = requested && Enum.find(view.row_actions, &(to_string(&1) == requested))

    cond do
      not is_binary(requested) ->
        {:error, [status(view, ~s(Malformed invoke action: context is missing "action".))]}

      is_nil(allowed) ->
        {:error,
         [
           status(
             view,
             "Action #{inspect(requested)} is not allowed: it is not listed in the " <>
               "view's row_actions."
           )
         ]}

      true ->
        invoke(allowed, Map.get(context, "recordId"), Map.get(context, "values"), env)
    end
  end

  # --- option search / nested rows ---------------------------------------------

  # The option_select success path: re-fetch the picked record (policies
  # apply — spoofed / unauthorized ids never reach /form), then write the
  # value and its canonical label.
  defp selected_option_messages(view, target, field, select_config, value, ash_opts, row) do
    case fetch_option(select_config, value, ash_opts, row) do
      {:ok, record} ->
        entry = AshA2ui.Info.option_entry(record, select_config)
        {value_path, state_path} = option_select_paths(target, field)

        {:ok,
         [
           update_data_model(view, value_path, entry["value"]),
           update_data_model(view, state_path, %{"search" => "", "label" => entry["label"]})
         ]}

      :not_found ->
        {:error, [status(view, t(view, msg("The selected option was not found.")))]}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # The searchable select an option_select addresses: a form select by
  # field name, or — with "prompt" — that action's searchable relationship
  # prompt field. Returns {target, field, select config} or nil.
  defp option_select_target(view, name, nil) do
    Enum.find_value(view.selects, fn {field, select} ->
      to_string(field) == name && {:form, field, select}
    end)
  end

  defp option_select_target(view, name, prompt) when is_binary(prompt) do
    Enum.find_value(view.prompts, fn {action, fields} ->
      to_string(action) == prompt &&
        Enum.find_value(fields, fn
          %{widget: :select, name: field, select: select} ->
            to_string(field) == name && {{:prompt, action}, field, select}

          _other_widget ->
            nil
        end)
    end)
  end

  defp option_select_target(_view, _name, _prompt), do: nil

  defp option_select_paths(:form, field), do: {"/form/#{field}", "/select/#{field}"}

  defp option_select_paths({:prompt, action}, field),
    do: {"/prompt/values/#{action}/#{field}", "/prompt/select/#{action}/#{field}"}

  # option_select takes a searchable select, or a prompt field scoped per
  # row (prompt_options) — whose option list is always picked through it.
  defp option_selectable?({_target, _field, %{scope: %{}}}), do: true
  defp option_selectable?({_target, _field, %{search_fields: [_ | _]}}), do: true
  defp option_selectable?(_select), do: false

  # The row a scoped prompt option read evaluates its scope for: the
  # context's "recordId", re-read as the actor (visible_when enforced).
  # Unscoped sources have none.
  defp option_row(view, {:prompt, action}, %{scope: %{}}, context, ash_opts) do
    prompt_row(view, Map.fetch!(view.actions, action), Map.get(context, "recordId"), ash_opts)
  end

  defp option_row(_view, _target, _select_config, _context, _ash_opts), do: {:ok, nil}

  # A form select's (or an unscoped searchable prompt field's) search:
  # results go to the shared /options/<field> list.
  defp option_search(name, search, %{view: view, ash_opts: ash_opts}) do
    source = is_binary(name) && option_source(view, name)

    cond do
      not is_binary(name) ->
        {:error, [status(view, ~s(Malformed option_search action: context is missing "field".))]}

      match?({_name, %{search_fields: [_ | _]}}, source) == false ->
        {:error,
         [
           status(
             view,
             "Field #{inspect(name)} is not a searchable select: it declares no option_search."
           )
         ]}

      not is_binary(search) ->
        {:error, [status(view, ~s(Malformed option_search action: "search" must be a string.))]}

      true ->
        {source_name, source_config} = source

        case search_options(source_config, search, ash_opts) do
          {:ok, options} ->
            {:ok, [update_data_model(view, "/options/#{source_name}", options)]}

          {:error, error} ->
            {:error, error_messages(view, error)}
        end
    end
  end

  # A scoped prompt field's search: within the row's scope, results to the
  # prompt's own /prompt/options/<action>/<field>.
  defp scoped_option_search({{:prompt, action}, field, select}, search, context, env) do
    %{view: view, ash_opts: ash_opts} = env

    cond do
      select.search_fields == [] ->
        {:error,
         [
           status(
             view,
             "Field #{inspect(to_string(field))} is not a searchable select: it declares no option_search."
           )
         ]}

      not is_binary(search) ->
        {:error, [status(view, ~s(Malformed option_search action: "search" must be a string.))]}

      true ->
        with {:ok, row} <- option_row(view, {:prompt, action}, select, context, ash_opts) do
          scoped_search_messages(view, {action, field, select}, search, row, ash_opts)
        end
    end
  end

  defp scoped_search_messages(view, {action, field, select}, search, row, ash_opts) do
    case search_options(select, search, ash_opts, row) do
      {:ok, options} ->
        {:ok, [update_data_model(view, "/prompt/options/#{action}/#{field}", options)]}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  defp option_source(view, name) do
    view
    |> ResolvedView.option_sources()
    |> Enum.find(fn {source_name, _source} -> to_string(source_name) == name end)
  end

  # Runs the allowlisted option search: a case-insensitive contains over the
  # declared option_search fields (OR'd), through the destination's primary
  # read with the surface's actor/tenant/authorize? opts, sorted by
  # option_sort and capped at option_limit. An empty search returns the
  # default first page (same as the initial load).
  defp search_options(source, search, ash_opts, row \\ nil) do
    query =
      source
      |> option_query(ash_opts, row)
      |> apply_option_search(source.search_fields, search)
      |> Ash.Query.sort([{source.option_sort, :asc}])
      |> Ash.Query.limit(source.option_limit)

    case Ash.read(query) do
      {:ok, records} -> {:ok, Enum.map(records, &AshA2ui.Info.option_entry(&1, source))}
      {:error, error} -> {:error, error}
    end
  end

  defp apply_option_search(query, _fields, ""), do: query

  defp apply_option_search(query, fields, search) do
    ci_search = Ash.CiString.new(search)

    condition =
      fields
      |> Enum.map(&expr(contains(^ref(&1), ^ci_search)))
      |> Enum.reduce(&expr(^&2 or ^&1))

    Ash.Query.filter(query, ^condition)
  end

  # Reads the destination record behind a picked option value (authorized —
  # a value the actor cannot read cannot be selected; through the row's
  # scope when the source is scoped — a value outside it cannot either).
  defp fetch_option(source, value, ash_opts, row \\ nil) do
    query =
      source
      |> option_query(ash_opts, row)
      |> Ash.Query.filter(^ref(source.option_value) == ^value)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [record]} -> {:ok, record}
      {:ok, []} -> :not_found
      {:error, error} -> {:error, error}
    end
  end

  # The read every option list and option re-read goes through: the
  # destination's primary read, or — for a prompt field scoped per row
  # (prompt_options) — the scope's read action with the row's primary key
  # as its record_argument. Both run with the surface's actor, tenant and
  # authorize? opts; the client contributes no filter.
  defp option_query(
         %{scope: %{read_action: action, record_argument: argument}} = source,
         ash_opts,
         row
       ) do
    Ash.Query.for_read(
      source.destination,
      action,
      %{argument => row_key(row)},
      destination_opts(source.destination, ash_opts)
    )
  end

  defp option_query(source, ash_opts, _row) do
    Ash.Query.for_read(
      source.destination,
      ResourceInfo.primary_action!(source.destination, :read).name,
      %{},
      destination_opts(source.destination, ash_opts)
    )
  end

  defp destination_opts(destination, ash_opts) do
    Keyword.put(
      ash_opts,
      :domain,
      ResourceInfo.domain(destination) || ash_opts[:domain]
    )
  end

  defp nested_target(view, context) do
    name = Map.get(context, "argument")

    nested =
      is_binary(name) &&
        Enum.find_value(view.nested_forms, fn {argument, nested} ->
          to_string(argument) == name && {argument, nested}
        end)

    cond do
      not is_binary(name) ->
        {:error, [status(view, ~s(Malformed nested action: context is missing "argument".))]}

      nested in [nil, false] ->
        {:error,
         [
           status(
             view,
             "Argument #{inspect(name)} is not a nested form on this surface."
           )
         ]}

      true ->
        {argument, config} = nested
        {:ok, argument, config}
    end
  end

  # Client-carried rows are display/form state only (the Ash action is the
  # authority at submit) — but they must at least be maps.
  defp sanitize_rows(rows) when is_list(rows), do: Enum.filter(rows, &is_map/1)
  defp sanitize_rows(_rows), do: []

  # A fresh create_inline row: the server-generated "_row" key (the remove
  # button's identity) plus one default per sub-form field (false for
  # booleans, "" otherwise).
  defp blank_row(nested) do
    nested.fields
    |> Map.new(&{Atom.to_string(&1), blank_value(nested.destination, &1)})
    |> Map.put("_row", Ash.UUID.generate())
  end

  defp blank_value(destination, field) do
    case ResourceInfo.attribute(destination, field) do
      %{type: type} -> if Ash.Type.get_type(type) == Ash.Type.Boolean, do: false, else: ""
      nil -> ""
    end
  end

  # pick_existing add: validates the picked value against the destination
  # (authorized read), dedupes by "id", and appends the
  # %{"_row", "id", "label"} row.
  defp nested_pick(view, argument, nested, rows, context, ash_opts) do
    value = unwrap_picked(Map.get(context, "value"))

    cond do
      not is_binary(value) or value == "" ->
        {:error, [status(view, ~s(Malformed nested_add action: context is missing "value".))]}

      Enum.any?(rows, &(Map.get(&1, "id") == value)) ->
        {:ok, [update_data_model(view, "/form/#{argument}", rows)]}

      true ->
        case fetch_option(nested, value, ash_opts) do
          {:ok, record} ->
            entry = AshA2ui.Info.option_entry(record, nested)

            row = %{"_row" => entry["value"], "id" => entry["value"], "label" => entry["label"]}

            {:ok, [update_data_model(view, "/form/#{argument}", rows ++ [row])]}

          :not_found ->
            {:error, [status(view, t(view, msg("The selected option was not found.")))]}

          {:error, error} ->
            {:error, error_messages(view, error)}
        end
    end
  end

  # ChoicePickers bind string lists; picked values may arrive as
  # one-element lists.
  defp unwrap_picked([value]), do: value
  defp unwrap_picked([]), do: nil
  defp unwrap_picked(value), do: value

  # The table a "query" action targets: the only table on single-table
  # surfaces; on multi-table surfaces the context must carry the source
  # "component" (the emitted controls always do). A surface without tables
  # resolves to the view itself — its nil query makes QueryRunner.parse
  # reject with the usual "no query configured" message.
  defp query_table(%ResolvedView{tables: [table]}, _context), do: {:ok, table}
  defp query_table(%ResolvedView{tables: []} = view, _context), do: {:ok, view}

  defp query_table(view, context) do
    case Map.get(context, "component") do
      component when is_binary(component) ->
        case Enum.find(view.tables, &(to_string(&1.name) == component)) do
          nil -> {:error, "Unknown table component #{inspect(component)}."}
          table -> {:ok, table}
        end

      _missing ->
        {:error,
         ~s(Malformed query action: multi-table surfaces require "component" in the context.)}
    end
  end

  # --- context follow-ups ------------------------------------------------------

  defp surface_context(view, name) do
    Enum.find_value(view.contexts, fn {context_name, context} ->
      to_string(context_name) == name && context
    end)
  end

  # Shared entry validation of the three context actions: a string "context"
  # key naming a declared context.
  defp resolve_context(view, action, context) do
    case Map.get(context, "context") do
      name when is_binary(name) ->
        case surface_context(view, name) do
          nil ->
            {:error, [status(view, "Context #{inspect(name)} is not declared on this surface.")]}

          ctx ->
            {:ok, ctx}
        end

      _missing ->
        {:error, [status(view, ~s(Malformed #{action} action: context is missing "context".))]}
    end
  end

  defp validate_context_search(view, ctx, search) do
    cond do
      ctx.search_fields == [] ->
        {:error,
         [
           status(
             view,
             "Context #{inspect(to_string(ctx.name))} is not searchable: it declares no " <>
               "option_search."
           )
         ]}

      not is_binary(search) ->
        {:error, [status(view, ~s(Malformed context_search action: "search" must be a string.))]}

      true ->
        :ok
    end
  end

  defp select_context(ctx, value, %{view: view} = env) do
    case ContextRunner.select(view, ctx, value, env.selected, env.ash_opts) do
      {:ok, change} -> context_change_messages(change, env)
      :not_found -> {:error, [status(view, t(view, msg("The selected option was not found.")))]}
      {:error, error} -> {:error, error_messages(view, error)}
    end
  end

  # require_context unmet: an honest empty result without touching Ash.
  defp require_unmet_messages(view, table, params) do
    state = QueryRunner.state(table.query, params, 0, false, view.l10n)

    records_messages(view, table, []) ++ query_state_messages(view, table, state, [])
  end

  defp run_scoped_query(view, table, params, scope, ash_opts) do
    case QueryRunner.run(table, params, ash_opts, scope, view.l10n) do
      {:ok, records, query_state} ->
        rows = rows(view, table, records, ash_opts)

        {:ok,
         view
         |> records_messages(table, rows)
         |> Kernel.++(query_state_messages(view, table, query_state, rows))
         |> with_swimlane_totals(view)}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # A selection change rewrites /context wholesale, re-emits /options/<name>
  # for every dependent picker context the cascade re-derived,
  # re-fetches /detail/<context> for changed contexts that detail components
  # render (%{} when the context ended up unselected), and refreshes every
  # table whose context_filter references a changed context (through the
  # carried-or-default query params, like any other refresh).
  defp context_change_messages(change, %{view: view} = env) do
    with {:ok, detail_messages} <- context_detail_messages(view, change, env.ash_opts),
         {:ok, table_messages} <- context_table_messages(view, change, env) do
      option_messages =
        for {name, options} <- change.options do
          update_data_model(view, "/options/#{name}", options)
        end

      # A settled selection clears the previous outcome (as task open/cancel
      # do), so a stale error does not outlive it and the admin dataGrid's
      # busy "Select <context>" row action settles.
      {:ok,
       [update_data_model(view, "/context", ContextRunner.state(view, change.selected))] ++
         option_messages ++
         detail_messages ++
         table_messages ++
         [update_data_model(view, "/ui/feedback", Experience.clear_feedback())]}
    else
      {:error, error} -> {:error, error_messages(view, error)}
    end
  end

  # One /detail/<context> write per changed context that has detail
  # components (details of the same context share the path — loads and
  # fields are unioned).
  defp context_detail_messages(view, change, ash_opts) do
    view
    |> ResolvedView.detail_sources()
    |> Enum.filter(&(&1.context in change.changed))
    |> Enum.group_by(& &1.context)
    |> Enum.reduce_while({:ok, []}, fn {context_name, details}, {:ok, acc} ->
      case context_detail_value(view, context_name, details, change.selected, ash_opts) do
        {:ok, value} ->
          {:cont, {:ok, acc ++ [update_data_model(view, "/detail/#{context_name}", value)]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp context_detail_value(view, context_name, details, selected, ash_opts) do
    case Map.get(selected, context_name) do
      nil ->
        {:ok, %{}}

      %{value: value} ->
        context = view.contexts[context_name]

        loads =
          details
          |> Enum.flat_map(& &1.loads)
          |> Kernel.++(ResolvedView.document_loads(view, context_name))
          |> Enum.uniq()

        fields = details |> Enum.flat_map(& &1.fields) |> Enum.uniq()

        case ContextRunner.fetch_selected(view, context, value, selected, ash_opts, loads) do
          {:ok, record} ->
            {:ok,
             view
             |> linked_record_values(record, fields, ash_opts)
             |> Map.merge(ResolvedView.detail_badge_data(view, record, fields))
             |> Map.merge(ResolvedView.detail_steps_data(view, record, fields))
             |> Map.merge(ResolvedView.detail_review_data(view, record, fields, context_name))
             |> Map.merge(ResolvedView.detail_field_action_data(view, record, fields))
             |> Map.merge(ResolvedView.detail_edit_data(view, details, record))
             |> Map.merge(ResolvedView.detail_document_data(view, context_name, record, fields))
             |> Map.merge(ResolvedView.detail_context_data(view, context_name, record, ash_opts))}

          # The selection was just validated; a raced-away record renders empty.
          :not_found ->
            {:ok, %{}}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp context_table_messages(view, change, env) do
    view.tables
    |> Enum.filter(fn table ->
      Enum.any?(table.context_filter, fn {_attribute, name} -> name in change.changed end)
    end)
    |> Enum.reduce_while({:ok, []}, fn table, {:ok, acc} ->
      case table_refresh(view, table, env.refresh[table.name], env.ash_opts, change.selected) do
        {:ok, messages} -> {:cont, {:ok, acc ++ messages}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> with_swimlane_totals(view)
  end

  # --- submit_form -----------------------------------------------------------

  defp create(%{view: view} = env, values) do
    env = Map.put(env, :invoked, form_action(view, nil))
    result = with {:ok, changeset} <- form_changeset(env, nil, values), do: Ash.create(changeset)
    after_write(result, env, t(view, msg("Created successfully.")))
  end

  defp update(%{view: view} = env, record_id, values) do
    env = Map.put(env, :invoked, form_action(view, record_id))

    result =
      with {:ok, changeset} <- form_changeset(env, record_id, values), do: Ash.update(changeset)

    after_write(result, env, t(view, msg("Updated successfully.")))
  end

  # The one changeset path for a form write. submit_form (create/update)
  # and wizard_next both build it here, so Next validates exactly what
  # Submit writes: the same action, the same values and the same atom-free
  # cast. A stepped form keeps only its own fields' keys (see
  # AshA2ui.Wizard.form_values/2); a form without steps casts every key the
  # action accepts, as it always has.
  defp form_changeset(%{view: view, ash_opts: ash_opts}, record_id, values) do
    action = form_action(view, record_id)
    cast = cast_values(view.resource, action, form_write_values(view, values))

    case record_id do
      nil ->
        {:ok, Ash.Changeset.for_create(view.resource, action, cast, ash_opts)}

      record_id ->
        with {:ok, record} <- fetch_record(view, record_id, ash_opts) do
          {:ok, Ash.Changeset.for_update(record, action, cast, ash_opts)}
        end
    end
  end

  defp form_action(view, nil), do: view.create_action || primary_action(view.resource, :create)

  defp form_action(view, _record_id),
    do: view.update_action || primary_action(view.resource, :update)

  defp form_write_values(view, values) do
    if AshA2ui.Wizard.stepped?(view),
      do: AshA2ui.Wizard.form_values(view, values),
      else: prepare_nested_values(view, values)
  end

  # Nested-form argument values are prepared before the Ash cast:
  # create_inline rows drop their client-state underscore keys ("_row",
  # "_error_*" — real record "id"s stay, so on_match updates work);
  # pick_existing rows reduce to their picked "id" values (the
  # manage_relationship lookup input).
  defp prepare_nested_values(view, values) when is_map(values) do
    Enum.reduce(view.nested_forms, values, fn {name, nested}, acc ->
      key = Atom.to_string(name)

      case Map.fetch(acc, key) do
        {:ok, rows} when is_list(rows) -> Map.put(acc, key, prepare_rows(nested, rows))
        _absent_or_not_a_list -> acc
      end
    end)
  end

  defp prepare_nested_values(_view, values), do: values

  defp prepare_rows(%{mode: :pick_existing}, rows) do
    rows
    |> Enum.map(fn
      %{} = row -> Map.get(row, "id")
      value when is_binary(value) -> value
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp prepare_rows(%{mode: :create_inline}, rows) do
    Enum.map(rows, fn
      %{} = row ->
        Map.reject(row, fn {key, _value} -> String.starts_with?(to_string(key), "_") end)

      other ->
        other
    end)
  end

  # --- field_action ----------------------------------------------------------

  # A field's action (catalog 3.2 on a detail card, 3.9 in a table's rows):
  # the field's declaration names the Ash action, the card's context (or
  # the table's scoped read) re-reads the record, and
  # `field_action_visible` gates it on the server as on the screen.
  defp field_action(context, %{view: view} = env) do
    with {:ok, target, field} <- field_action_target(view, context),
         {:ok, record_id} <- field_action_record_id(view, context),
         {:ok, record} <- field_action_record(view, target, field, record_id, env),
         {:ok, item} <- field_action_item(view, field, record, context) do
      action = field.field_action

      env =
        env
        |> Map.put(:invoked, action)
        |> Map.put(:setting, Map.get(view.actions, action))
        |> Map.put(:shown_fields, [])

      params = record |> field_action_params(action, field) |> put_item(item)
      result = update_record(record, action, params, env.ash_opts)

      with {:ok, messages} <- after_write(result, env, completed_text(view, action)),
           {:ok, detail_messages} <- field_action_detail(view, target, record_id, env) do
        {:ok, detail_messages ++ messages}
      end
    end
  end

  # The field's name, as the action's `:field` argument when it declares one
  # (an action that marks the whole record needs none).
  defp field_action_params(record, action, field) do
    case ResourceInfo.action(record.__struct__, action) do
      %{arguments: arguments} ->
        if Enum.any?(arguments, &(&1.name == :field)),
          do: %{field: Atom.to_string(field.name)},
          else: %{}

      _other ->
        %{}
    end
  end

  # Catalog 3.10: a `pairs` field's action runs for one of its items, named
  # by its key (`"item"`): the record's own items, read again, must hold it
  # and offer the action. Any other field's action takes no item.
  defp field_action_item(view, %AshA2ui.Field{pairs: true} = field, record, context) do
    with key when is_binary(key) and key != "" <- Map.get(context, "item"),
         %{"action" => true} <-
           record
           |> Map.get(field.name)
           |> AshA2ui.Pairs.normalize(nil, true)
           |> AshA2ui.Pairs.find(key) do
      {:ok, key}
    else
      _unoffered -> {:error, [status(view, unavailable_text(view, field.field_action))]}
    end
  end

  defp field_action_item(_view, _field, _record, _context), do: {:ok, nil}

  # The item's key as the action's `:item` argument (the verifier makes a
  # `pairs` field's action declare one).
  defp put_item(params, nil), do: params
  defp put_item(params, key), do: Map.put(params, :item, key)

  # The card (or table) and the field the client named, when that field of
  # that card (or table) declares a field action.
  defp field_action_target(view, context) do
    component = Map.get(context, "component")
    name = Map.get(context, "field")

    target =
      is_binary(component) and is_binary(name) and
        (Enum.find_value(
           view.details,
           &declared_target(view, :detail, &1, &1.fields, component, name)
         ) ||
           Enum.find_value(
             view.tables,
             &declared_target(view, :table, &1, &1.component.fields || [], component, name)
           ))

    case target do
      {target, field} ->
        {:ok, target, field}

      _none ->
        {:error,
         [
           status(
             view,
             "Field action #{inspect(name)} on #{inspect(component)} is not allowed: no field " <>
               "of that card declares a field_action."
           )
         ]}
    end
  end

  # `{{kind, card_or_table}, field}` when `source` is the named component and
  # one of its `fields` is the named field declaring a field action.
  defp declared_target(view, kind, source, fields, component, name) do
    if to_string(source.name) == component do
      case Enum.find_value(fields, &declared_field_action(view, &1, name)) do
        nil -> nil
        field -> {{kind, source}, field}
      end
    end
  end

  defp declared_field_action(view, field, name) do
    case view.fields[field] do
      %{field_action: action} = declared when not is_nil(action) ->
        if to_string(field) == name, do: declared

      _other ->
        nil
    end
  end

  defp field_action_record_id(view, context) do
    case Map.get(context, "recordId") do
      id when is_binary(id) and id != "" ->
        {:ok, id}

      _missing ->
        {:error, [status(view, ~s(Malformed field_action: context is missing "recordId".))]}
    end
  end

  defp field_action_record(view, {:detail, detail}, field, record_id, env) do
    context = view.contexts[detail.context]

    view
    |> ContextRunner.fetch_selected(
      context,
      record_id,
      env.selected,
      env.ash_opts,
      detail.loads
    )
    |> offered_record(view, field)
  end

  # A row is re-read through its table's own read, scoped as the table is
  # (its context filters): a row the table would not show is refused.
  defp field_action_record(view, {:table, table}, field, record_id, env) do
    case ContextRunner.table_scope(view, table, env.selected) do
      {:ok, scope} ->
        table
        |> QueryRunner.preset_read(nil, env.ash_opts)
        |> ContextRunner.apply_scope(scope)
        |> Ash.Query.filter(id == ^record_id)
        |> Ash.Query.load(table.loads)
        |> Ash.read_one()
        |> found()
        |> offered_record(view, field)

      :require_unmet ->
        offered_record(:not_found, view, field)
    end
  end

  defp found({:ok, nil}), do: :not_found
  defp found(result), do: result

  defp offered_record({:ok, record}, view, field) do
    if ResolvedView.field_action_offered?(field, record),
      do: {:ok, record},
      else: {:error, [status(view, unavailable_text(view, field.field_action))]}
  end

  defp offered_record(:not_found, view, field),
    do: {:error, [status(view, unavailable_text(view, field.field_action))]}

  defp offered_record({:error, error}, view, _field), do: {:error, error_messages(view, error)}

  # The card's record again, as a context change writes it: every detail of
  # the same context shares the path.
  defp field_action_detail(view, {:detail, detail}, record_id, %{ash_opts: ash_opts} = env) do
    details =
      view |> ResolvedView.detail_sources() |> Enum.filter(&(&1.context == detail.context))

    selected =
      Map.update(
        env.selected,
        detail.context,
        %{value: record_id},
        &Map.put(&1, :value, record_id)
      )

    case context_detail_value(view, detail.context, details, selected, ash_opts) do
      {:ok, value} -> {:ok, [update_data_model(view, "/detail/#{detail.context}", value)]}
      {:error, error} -> {:error, error_messages(view, error)}
    end
  end

  # A row's action re-sends the records of the contexts its table is
  # filtered by: what their cards show may count its rows (a review summary).
  defp field_action_detail(view, {:table, table}, _record_id, %{ash_opts: ash_opts} = env) do
    sources = ResolvedView.detail_sources(view)

    table.context_filter
    |> Enum.map(fn {_attribute, context} -> context end)
    |> Enum.uniq()
    |> Enum.map(fn context -> {context, Enum.filter(sources, &(&1.context == context))} end)
    |> Enum.filter(fn {context, details} ->
      details != [] and Map.has_key?(env.selected, context)
    end)
    |> Enum.reduce_while({:ok, []}, fn {context, details}, {:ok, acc} ->
      case context_detail_value(view, context, details, env.selected, ash_opts) do
        {:ok, value} ->
          {:cont, {:ok, acc ++ [update_data_model(view, "/detail/#{context}", value)]}}

        {:error, error} ->
          {:halt, {:error, error_messages(view, error)}}
      end
    end)
  end

  # --- save_changes ----------------------------------------------------------

  # Catalog 3.11: a person's unsaved changes to the surface's editable cards,
  # saved at once through each card's declared update action, in one
  # transaction; `"then"` runs the save bar's then_action after them.
  defp save_changes(context, %{view: view} = env) do
    with {:ok, bar} <- declared_save_bar(view),
         {:ok, choice} <- save_choice(bar, Map.get(context, "choice", "save"), view),
         {:ok, targets} <- save_targets(view, Map.get(context, "edits"), choice),
         {:ok, saves} <- fetch_save_records(view, targets, env),
         {:ok, then} <- then_target(view, bar, choice, Map.get(context, "recordId"), env) do
      run_saves(view, bar, saves, then, env)
    end
  end

  defp declared_save_bar(%{save_bar: nil} = view),
    do: {:error, [status(view, "save_changes is not allowed: the surface declares no save_bar.")]}

  defp declared_save_bar(%{save_bar: bar}), do: {:ok, bar}

  defp save_choice(_bar, "save", _view), do: {:ok, :save}

  defp save_choice(%{confirm: %{then_action: action}}, "then", _view) when action != nil,
    do: {:ok, :then}

  defp save_choice(_bar, choice, view),
    do: {:error, [status(view, "save_changes choice #{inspect(choice)} is not allowed.")]}

  # The changed fields of each card the client named: every card must be an
  # editable :detail and every field one of its editable fields.
  defp save_targets(view, edits, choice) when is_map(edits) do
    edits
    |> Enum.reduce_while({:ok, []}, fn {card, entry}, {:ok, acc} ->
      case save_target(view, card, entry) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, target} -> {:cont, {:ok, [target | acc]}}
        {:error, _messages} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, []} when choice == :save -> {:error, [status(view, t(view, msg("Nothing to save.")))]}
      {:ok, targets} -> {:ok, Enum.reverse(targets)}
      error -> error
    end
  end

  defp save_targets(_view, nil, :then), do: {:ok, []}

  defp save_targets(view, _edits, _choice),
    do: {:error, [status(view, ~s(Malformed save_changes: context is missing "edits".))]}

  defp save_target(view, card, entry) when is_map(entry) do
    detail = Enum.find(view.details, &(to_string(&1.name) == card and &1[:editable]))
    values = Map.get(entry, "values") || %{}
    record_id = Map.get(entry, "recordId")

    cond do
      is_nil(detail) ->
        {:error,
         [status(view, "save_changes on #{inspect(card)} is not allowed: no editable :detail.")]}

      values == %{} ->
        {:ok, nil}

      not (is_binary(record_id) and record_id != "") ->
        {:error, [status(view, ~s(Malformed save_changes: #{inspect(card)} has no "recordId".))]}

      true ->
        with {:ok, params} <- edited_params(view, detail, values) do
          {:ok, %{detail: detail, record_id: record_id, params: params, values: values}}
        end
    end
  end

  defp save_target(view, card, _entry),
    do: {:error, [status(view, "Malformed save_changes: #{inspect(card)} is not a map.")]}

  # Each changed field's value under the attribute its input edits, cast
  # against the card's update action. A cleared input is no value.
  defp edited_params(view, %{editable: editable} = detail, values) do
    by_name = Map.new(editable.fields, &{to_string(&1), &1})

    Enum.reduce_while(values, {:ok, %{}}, fn {field, value}, {:ok, acc} ->
      case Map.fetch(by_name, field) do
        {:ok, name} ->
          attr = Map.fetch!(editable.edits, name)
          {:cont, {:ok, Map.put(acc, to_string(attr), blank_to_nil(value))}}

        :error ->
          {:halt,
           {:error,
            [
              status(
                view,
                "save_changes field #{inspect(field)} of #{inspect(to_string(detail.name))} " <>
                  "is not allowed: it is not an editable field of that card."
              )
            ]}}
      end
    end)
    |> case do
      {:ok, params} ->
        resource = view.contexts[detail.context].resource
        {:ok, cast_values(resource, editable.update_action, params)}

      error ->
        error
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # Each card's record, re-read through its context as the actor, refused
  # unless it offers editing.
  defp fetch_save_records(view, targets, env) do
    targets
    |> Enum.reduce_while({:ok, []}, fn target, {:ok, acc} ->
      case fetch_save_record(view, target, env) do
        {:ok, save} -> {:cont, {:ok, [save | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, saves} -> {:ok, Enum.reverse(saves)}
      error -> error
    end
  end

  defp fetch_save_record(view, %{detail: detail} = target, %{ash_opts: ash_opts} = env) do
    unavailable =
      {:error, [status(view, t(view, msg("Editing is not available for this record.")))]}

    case ContextRunner.fetch_selected(
           view,
           view.contexts[detail.context],
           target.record_id,
           env.selected,
           ash_opts,
           detail.loads
         ) do
      {:ok, record} ->
        if ResolvedView.editable_offered?(detail.editable, record),
          do: {:ok, Map.put(target, :record, record)},
          else: unavailable

      :not_found ->
        unavailable

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # The bar's record `"then"` runs its then_action on, refused unless the
  # record offers it.
  defp then_target(_view, _bar, :save, _record_id, _env), do: {:ok, nil}

  defp then_target(view, bar, :then, record_id, %{ash_opts: ash_opts} = env)
       when is_binary(record_id) and record_id != "" do
    confirm = bar.confirm
    context = view.contexts[bar.context]

    loads =
      if confirm.then_visible, do: then_loads(context.resource, confirm.then_visible), else: []

    unavailable = [status(view, unavailable_text(view, confirm.then_action))]

    case ContextRunner.fetch_selected(view, context, record_id, env.selected, ash_opts, loads) do
      {:ok, record} ->
        if is_nil(confirm.then_visible) or Map.get(record, confirm.then_visible) == true,
          do:
            {:ok,
             %{
               resource: context.resource,
               record_id: record_id,
               action: confirm.then_action,
               context: context,
               loads: loads
             }},
          else: {:error, unavailable}

      :not_found ->
        {:error, unavailable}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  defp then_target(view, _bar, :then, _record_id, _env),
    do: {:error, [status(view, ~s(Malformed save_changes: context is missing "recordId".))]}

  defp then_loads(resource, field) do
    if Ash.Resource.Info.calculation(resource, field) ||
         Ash.Resource.Info.aggregate(resource, field),
       do: [field],
       else: []
  end

  # Every write in one transaction: the cards' saves, then the then_action
  # on the bar's record read again (a save may have changed it).
  defp run_saves(view, bar, saves, then, %{ash_opts: ash_opts} = env) do
    resources =
      (Enum.map(saves, &view.contexts[&1.detail.context].resource) ++
         List.wrap(then && then.resource))
      |> Enum.uniq()

    result =
      Ash.DataLayer.transaction(resources, fn ->
        with :ok <- write_saves(saves, ash_opts),
             :ok <- write_then(view, then, env) do
          :ok
        else
          {:error, _failure} = error -> abandon(resources, error)
        end
      end)

    case result do
      {:ok, :ok} -> saved(view, bar, saves, then, env)
      {:ok, {:error, failure}} -> {:error, save_failure(view, failure)}
      {:error, {:error, failure}} -> {:error, save_failure(view, failure)}
      {:error, error} -> {:error, error_messages(view, error)}
    end
  end

  # A data layer with transactions undoes the writes made so far; one
  # without has nothing to undo them with.
  defp abandon([resource | _] = _resources, error) do
    if Ash.DataLayer.data_layer_can?(resource, :transact),
      do: Ash.DataLayer.rollback(resource, error),
      else: error
  end

  defp write_saves(saves, ash_opts) do
    Enum.reduce_while(saves, :ok, fn save, :ok ->
      case update_record(save.record, save.detail.editable.update_action, save.params, ash_opts) do
        {:ok, _record} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, {save, error}}}
      end
    end)
  end

  defp write_then(_view, nil, _env), do: :ok

  defp write_then(view, then, %{ash_opts: ash_opts} = env) do
    with {:ok, record} <-
           ContextRunner.fetch_selected(
             view,
             then.context,
             then.record_id,
             env.selected,
             ash_opts,
             then.loads
           ),
         {:ok, _record} <- update_record(record, then.action, %{}, ash_opts) do
      :ok
    else
      :not_found -> {:error, {:unavailable, then.action}}
      {:error, error} -> {:error, {nil, error}}
    end
  end

  # A refused save: each edited field's message at its input
  # (`/ui/edit_errors/<card>/<field>`), the standard field and outcome
  # writes for the rest.
  defp save_failure(view, {:unavailable, action}),
    do: [status(view, unavailable_text(view, action))]

  defp save_failure(view, {nil, error}), do: error_messages(view, error)

  defp save_failure(view, {%{detail: detail, values: values}, error}) do
    edited =
      for {field, attr} <- detail.editable.edits,
          Map.has_key?(values, to_string(field)),
          into: %{},
          do: {to_string(attr), to_string(field)}

    field_messages =
      for {[attr | _rest], text} <- field_errors(view.l10n, error),
          field = Map.get(edited, to_string(attr)),
          into: %{},
          do: {field, text}

    [update_data_model(view, "/ui/edit_errors", %{to_string(detail.name) => field_messages})] ++
      error_messages(view, error, Map.keys(edited))
  end

  defp saved(view, bar, saves, then, env) do
    action =
      (then && then.action) ||
        (List.first(saves) && List.first(saves).detail.editable.update_action)

    env =
      env
      |> Map.put(:invoked, action)
      |> Map.put(:setting, action && Map.get(view.actions, action))
      |> Map.put(:shown_fields, [])

    text =
      case {then, bar.confirm} do
        {%{}, %{then_saved_message: message}} when is_binary(message) -> message
        _save -> bar.saved_message
      end

    contexts =
      (Enum.map(saves, & &1.detail.context) ++ List.wrap(then && then.context.name))
      |> Enum.uniq()

    record_ids =
      Map.new(saves, &{&1.detail.context, &1.record_id})
      |> then_record_id(then)

    with {:ok, messages} <- success(env, text),
         {:ok, details} <- saved_details(view, contexts, record_ids, env) do
      {:ok,
       [
         update_data_model(view, "/ui/edits", %{}),
         update_data_model(view, "/ui/edit_errors", %{})
       ] ++ details ++ messages}
    end
  end

  defp then_record_id(ids, nil), do: ids
  defp then_record_id(ids, then), do: Map.put_new(ids, then.context.name, then.record_id)

  defp saved_details(view, contexts, record_ids, %{ash_opts: ash_opts} = env) do
    Enum.reduce_while(contexts, {:ok, []}, fn context, {:ok, acc} ->
      details =
        view |> ResolvedView.detail_sources() |> Enum.filter(&(&1.context == context))

      record_id = Map.fetch!(record_ids, context)

      selected =
        Map.update(env.selected, context, %{value: record_id}, &Map.put(&1, :value, record_id))

      case context_detail_value(view, context, details, selected, ash_opts) do
        {:ok, value} ->
          {:cont, {:ok, acc ++ [update_data_model(view, "/detail/#{context}", value)]}}

        {:error, error} ->
          {:halt, {:error, error_messages(view, error)}}
      end
    end)
  end

  # --- page_action -----------------------------------------------------------

  # A page header's button that runs an action (catalog 3.5): the header's
  # declaration names the Ash action, its context re-reads the record, and
  # the button's `visible` field and `Ash.can?/3` gate it on the server as
  # on the screen.
  defp page_action(context, %{view: view} = env) do
    header = view.page_header

    with {:ok, action} <- page_action_target(view, header, context),
         {:ok, record_id} <- page_action_record_id(view, context),
         {:ok, record} <- page_action_record(view, header, action, record_id, env) do
      env =
        env
        |> Map.put(:invoked, action.run)
        |> Map.put(:setting, Map.get(view.actions, action.run))
        |> Map.put(:shown_fields, [])

      result = update_record(record, action.run, %{}, env.ash_opts)

      with {:ok, messages} <- after_write(result, env, page_action_done(view, action)),
           {:ok, detail_messages} <- page_action_detail(view, header, record_id, env) do
        {:ok, detail_messages ++ messages}
      end
    end
  end

  defp page_action_target(view, header, context) do
    name = Map.get(context, "action")

    case AshA2ui.PageHeader.runnable(header, name) do
      nil ->
        {:error,
         [
           status(
             view,
             "Page action #{inspect(name)} is not allowed: the page header declares no " <>
               "header_action of that name that runs an action."
           )
         ]}

      action ->
        {:ok, action}
    end
  end

  defp page_action_record_id(view, context) do
    case Map.get(context, "recordId") do
      id when is_binary(id) and id != "" ->
        {:ok, id}

      _missing ->
        {:error, [status(view, ~s(Malformed page_action: context is missing "recordId".))]}
    end
  end

  defp page_action_record(view, header, action, record_id, %{ash_opts: ash_opts} = env) do
    context = view.contexts[header.context]
    loads = if action.visible, do: [action.visible], else: []
    loads = Enum.filter(loads, &ResolvedView.calculation_or_aggregate?(context.resource, &1))

    case ContextRunner.fetch_selected(view, context, record_id, env.selected, ash_opts, loads) do
      {:ok, record} ->
        if AshA2ui.PageHeader.offered?(action, record, ash_opts),
          do: {:ok, record},
          else: {:error, [status(view, unavailable_text(view, action.run))]}

      :not_found ->
        {:error, [status(view, unavailable_text(view, action.run))]}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # "<button>: done.", in the header button's own words.
  defp page_action_done(view, action),
    do: t(view, msg("%{action}: done."), action: action.label)

  # The header's record again, with every detail of its context.
  defp page_action_detail(view, header, record_id, %{ash_opts: ash_opts} = env) do
    details =
      view |> ResolvedView.detail_sources() |> Enum.filter(&(&1.context == header.context))

    selected =
      Map.update(
        env.selected,
        header.context,
        %{value: record_id},
        &Map.put(&1, :value, record_id)
      )

    case context_detail_value(view, header.context, details, selected, ash_opts) do
      {:ok, value} -> {:ok, [update_data_model(view, "/detail/#{header.context}", value)]}
      {:error, error} -> {:error, error_messages(view, error)}
    end
  end

  # --- invoke ----------------------------------------------------------------

  defp invoke(action_name, record_id, values, %{view: view} = env) do
    setting = Map.get(view.actions, action_name)

    env =
      env
      |> Map.put(:invoked, action_name)
      |> Map.put(:setting, setting)
      |> Map.put(:shown_fields, (setting && setting.prompt_fields) || [])

    case enforce_visibility(view, setting, record_id, env.ash_opts) do
      :ok ->
        case setting do
          %{via: {module, function, extra_args}} when not is_nil(module) ->
            invoke_via(module, function, extra_args, record_id, env)

          _direct ->
            invoke_direct(view, setting, action_name, record_id, values, env)
        end

      {:error, messages} ->
        {:error, messages}
    end
  end

  defp invoke_direct(view, setting, action_name, record_id, values, env) do
    with :ok <- check_prompt_options(view, setting, record_id, values, env.ash_opts) do
      params = prompt_params(view, setting, action_name, values)
      dispatch_by_action_type(view, action_name, record_id, params, env)
    end
  end

  # The direct path runs the mapped Ash action through run_direct/6 (shared
  # with bulk runs), then renders writes through after_write and generic
  # results through generic_result.
  defp dispatch_by_action_type(view, action_name, record_id, params, %{ash_opts: ash_opts} = env) do
    fetch = fn -> fetch_record(view, record_id, ash_opts) end
    completed = completed_text(view, action_name)

    case run_direct(view, action_name, record_id, fetch, params, ash_opts) do
      {:write, result} ->
        after_write(result, env, completed)

      {:generic, result} ->
        generic_result(result, env, completed)

      :not_invocable ->
        {:error,
         [
           status(
             view,
             "Action #{inspect(action_name)} cannot be invoked as a row action."
           )
         ]}
    end
  end

  # One direct (non-`via`) call of `action_name`, shared by a single-row
  # invoke and each record of a bulk run so both dispatch identically:
  # destroy and update actions run on the record `fetch` yields (invoke
  # fetches it by id, a bulk run passes its re-read record), generic actions
  # get the record id. Returns the raw Ash result tagged `:write` or
  # `:generic`, or `:not_invocable` for any other action type.
  defp run_direct(view, action_name, record_id, fetch, params, ash_opts) do
    case ResourceInfo.action(view.resource, action_name) do
      %{type: :destroy} ->
        {:write,
         with(
           {:ok, record} <- fetch.(),
           do: destroy_record(record, action_name, params, ash_opts)
         )}

      %{type: :update} ->
        {:write,
         with({:ok, record} <- fetch.(), do: update_record(record, action_name, params, ash_opts))}

      %{type: :action} = action ->
        {:generic, run_generic(view, action, record_id, params, ash_opts)}

      _other ->
        :not_invocable
    end
  end

  # A `via` row action delegates to a host-provided MFA instead of running
  # the mapped Ash action (see the `via` option docs on `AshA2ui`): the
  # record is fetched exactly as the direct path fetches it, the MFA
  # receives the dispatch context plus its extra args, and its return value
  # — the same shapes a direct invocation produces — renders through the
  # standard channels (status text, refreshes honoring the action entity,
  # typed /ui/feedback) unchanged.
  defp invoke_via(_module, _function, _extra_args, nil, %{view: view, invoked: action_name}) do
    {:error,
     [
       status(
         view,
         "Action #{inspect(to_string(action_name))} declares via and " <>
           ~s(requires a "recordId" to fetch the record it delegates with.)
       )
     ]}
  end

  defp invoke_via(
         module,
         function,
         extra_args,
         record_id,
         %{view: view, ash_opts: ash_opts} = env
       ) do
    case fetch_record(view, record_id, ash_opts) do
      {:ok, record} ->
        module
        |> call_via(function, extra_args, record, env)
        |> via_result(env)

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # The delegate call itself, shared by a single-row invoke and each record
  # of a bulk run: the raw MFA return, no follow-ups.
  defp call_via(module, function, extra_args, record, %{view: view, ash_opts: ash_opts} = env) do
    context = %{
      record: record,
      actor: ash_opts[:actor],
      tenant: ash_opts[:tenant],
      action: env.invoked,
      surface_id: view.surface_id,
      selected: env.selected
    }

    apply(module, function, [context | List.wrap(extra_args)])
  end

  defp via_result(:ok, %{view: view, invoked: action_name} = env),
    do: after_write(:ok, env, completed_text(view, action_name))

  defp via_result({:ok, _result}, %{view: view, invoked: action_name} = env),
    do: after_write(:ok, env, completed_text(view, action_name))

  defp via_result({:error, error}, env),
    do: after_write({:error, error}, env, "")

  # A malformed return is a host bug; report it through the error channel
  # rather than crashing the renderer.
  defp via_result(other, %{view: view, invoked: action_name}) do
    {:error,
     [
       status(
         view,
         "Via delegate for action #{inspect(to_string(action_name))} returned an invalid " <>
           "result (expected :ok, {:ok, term}, or {:error, Ash.Error.t()}): " <> inspect(other)
       )
     ]}
  end

  # The success status of a single-row invoke: "<label>: done." when the
  # action entity declares a `label` (the name its button shows, as the bulk
  # status line uses), else "<humanized name> completed.".
  defp completed_text(view, action_name) do
    case Map.get(view.actions, action_name) do
      %{label: label} when is_binary(label) ->
        t(view, msg("%{action}: done."), action: Label.translate(view.l10n, label))

      _no_label ->
        t(view, msg("%{action} completed."), action: ResolvedView.action_label(view, action_name))
    end
  end

  defp unavailable_text(view, action_name) do
    t(view, msg("%{action} is not available for this record."),
      action: ResolvedView.action_label(view, action_name)
    )
  end

  # Handler-side visible_when enforcement (mandatory — rendering hides
  # buttons best-effort, but the server is the authority): the identified
  # record is fetched with any condition calculations loaded, and every
  # condition must hold or the invoke is rejected before touching the write.
  defp enforce_visibility(_view, nil, _record_id, _ash_opts), do: :ok
  defp enforce_visibility(_view, %{visible_when: []}, _record_id, _ash_opts), do: :ok

  defp enforce_visibility(view, %{name: name}, nil, _ash_opts) do
    {:error,
     [
       status(
         view,
         "Action #{inspect(to_string(name))} declares visible_when conditions and " <>
           ~s(requires a "recordId" to evaluate them.)
       )
     ]}
  end

  defp enforce_visibility(view, %{visible_when: conditions, name: name}, record_id, ash_opts) do
    loads = Conditions.condition_loads(view.resource, conditions)

    case fetch_record(view, record_id, ash_opts, loads) do
      {:ok, record} ->
        if Conditions.visible?(view.resource, conditions, record) do
          :ok
        else
          {:error, [status(view, unavailable_text(view, name))]}
        end

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # The invoke params: empty unless the action declares prompt_fields — then
  # the client-sent "values" map is filtered to the declared prompt fields
  # (nothing outside them ever reaches the changeset) and cast against the
  # Ash action's arguments/accepts. "values" on prompt-less actions is
  # ignored entirely.
  defp prompt_params(view, %{prompt_fields: [_ | _] = fields}, action_name, values)
       when is_map(values) do
    allowed = MapSet.new(fields, &Atom.to_string/1)
    filtered = Map.filter(values, fn {key, _value} -> normalize_key(key) in allowed end)
    cast_values(view.resource, action_name, filtered)
  end

  defp prompt_params(_view, _setting, _action_name, _values), do: %{}

  # Relationship prompt values are re-read as the actor before the write, as
  # option_select re-reads a picked option: the picker offers only the
  # options the actor can read, and a value it would not have offered (a
  # spoofed or stale id) is refused as a field error on that prompt field.
  # A field scoped per row (prompt_options) is re-read through the scope of
  # the row being invoked on, so a value outside it is refused the same way.
  defp check_prompt_options(
         view,
         %{name: action, prompt_fields: [_ | _] = fields} = setting,
         record_id,
         values,
         opts
       )
       when is_map(values) do
    picked =
      for %{name: name, select: %{} = select} <- Map.get(view.prompts, action, []),
          (picks = prompt_option_values(values, name)) != [],
          do: {name, select, picks}

    with {:ok, row} <- scope_row_for(view, setting, record_id, picked, opts) do
      unavailable =
        for {name, select, picks} <- picked,
            Enum.any?(picks, &(not match?({:ok, _record}, fetch_option(select, &1, opts, row)))),
            do: InvalidAttribute.exception(field: name, message: @unavailable)

      case unavailable do
        [] ->
          :ok

        errors ->
          {:error, error_messages(view, Invalid.exception(errors: errors), fields)}
      end
    end
  end

  defp check_prompt_options(_view, _setting, _record_id, _values, _opts), do: :ok

  # The invoked row, read once when a scoped field has a picked value.
  defp scope_row_for(view, setting, record_id, picked, opts) do
    if Enum.any?(picked, fn {_name, select, _picks} -> scoped_select?(select) end),
      do: prompt_row(view, setting, record_id, opts),
      else: {:ok, nil}
  end

  # A prompt field's picked values: a ChoicePicker binds a list, a
  # searchable select a single value; blanks are left to the action's own
  # validation.
  defp prompt_option_values(values, name) do
    values
    |> Map.get(Atom.to_string(name), Map.get(values, name))
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp destroy_record(record, action_name, params, ash_opts) do
    record
    |> Ash.Changeset.for_destroy(action_name, params, ash_opts)
    |> Ash.destroy()
  end

  # An update-type row action runs *that* action on the identified record —
  # with empty params (touch-style actions whose changes come from `change`
  # blocks / defaults), or with the cast prompt values when the action
  # declares prompt_fields. Never the form's update action.
  defp update_record(record, action_name, params, ash_opts) do
    record
    |> Ash.Changeset.for_update(action_name, params, ash_opts)
    |> Ash.update()
  end

  defp run_generic(view, action, record_id, params, ash_opts) do
    view.resource
    |> Ash.ActionInput.for_action(
      action.name,
      Map.merge(generic_params(action, record_id), params),
      ash_opts
    )
    |> Ash.run_action()
  end

  # --- prompt ----------------------------------------------------------------

  # Pre-fills /prompt/values/<action> when the prompt Modal opens: each
  # prompt field's current record value when it is a public attribute of the
  # resource, "" otherwise (arguments have no stored value). Clears /errors
  # so stale validation messages don't show inside a fresh prompt.
  defp prompt(view, setting, record_id, ash_opts) do
    with {:ok, record} <- prompt_row(view, setting, record_id, ash_opts) do
      prompt_prefill_messages(view, setting, record, ash_opts)
    end
  end

  # The row a prompt (or a scoped prompt option read) is about: read
  # through the surface's read action as the actor, with the action's
  # visible_when conditions enforced — the same gate invoke applies.
  defp prompt_row(view, _setting, record_id, _ash_opts) when record_id in [nil, ""] do
    {:error, [status(view, ~s(Malformed prompt option action: context is missing "recordId".))]}
  end

  defp prompt_row(view, setting, record_id, ash_opts) do
    loads = Conditions.condition_loads(view.resource, setting.visible_when)

    case fetch_record(view, record_id, ash_opts, loads) do
      {:ok, record} ->
        if Conditions.visible?(view.resource, setting.visible_when, record) do
          {:ok, record}
        else
          {:error,
           [
             status(view, unavailable_text(view, setting.name))
           ]}
        end

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  defp prompt_prefill_messages(view, setting, record, ash_opts) do
    stored =
      Map.new(setting.prompt_fields, fn field ->
        {Atom.to_string(field), prefill_value(view.resource, record, field)}
      end)

    {prefill, select_state} = prompt_select_prefill(view, setting.name, stored, record, ash_opts)

    with {:ok, scoped} <- prompt_scope_prefill(view, setting.name, record, ash_opts) do
      {:ok,
       [
         update_data_model(view, "/prompt/values/#{setting.name}", prefill),
         update_data_model(view, "/errors", %{})
       ] ++ select_state ++ scoped}
    end
  end

  # Searchable and scoped relationship prompt fields show the pre-filled
  # value's label, read as the actor (through the row's scope when scoped).
  # A stored value the actor could not pick (unreadable, or outside the
  # row's scope) is not pre-filled: the field shows no selection and
  # submits none, rather than a blank selection invoke would refuse as
  # unavailable. Returns {prefill, messages}.
  defp prompt_select_prefill(view, action, prefill, record, ash_opts) do
    composite =
      for %{widget: :select, select: %{} = select} = field <- Map.get(view.prompts, action, []),
          match?(%{search_fields: [_ | _]}, select) or scoped_select?(select),
          do: {Atom.to_string(field.name), select}

    if composite == [] do
      {prefill, []}
    else
      {prefill, state} =
        Enum.reduce(composite, {prefill, %{}}, fn {name, select}, {prefill, state} ->
          {value, label} = prefill_option(select, prefill[name], record, ash_opts)

          {Map.put(prefill, name, value),
           Map.put(state, name, %{"search" => "", "label" => label})}
        end)

      {prefill, [update_data_model(view, "/prompt/select/#{action}", state)]}
    end
  end

  # Scoped relationship prompt fields (prompt_options): the row's options,
  # read as the actor through the scope, and the row the prompt is open on
  # (which the field's option_select / option_search carry back).
  defp prompt_scope_prefill(view, action, record, ash_opts) do
    case scoped_prompt_selects(view, action) do
      [] ->
        {:ok, []}

      scoped ->
        with {:ok, options} <- scoped_option_lists(view, scoped, record, ash_opts) do
          {:ok,
           [
             update_data_model(view, "/prompt/options/#{action}", options),
             update_data_model(view, "/prompt/record/#{action}", row_id(record))
           ]}
        end
    end
  end

  defp scoped_option_lists(view, scoped, record, ash_opts) do
    Enum.reduce_while(scoped, {:ok, %{}}, fn {name, select}, {:ok, acc} ->
      case search_options(select, "", ash_opts, record) do
        {:ok, options} -> {:cont, {:ok, Map.put(acc, Atom.to_string(name), options)}}
        {:error, error} -> {:halt, {:error, error_messages(view, error)}}
      end
    end)
  end

  defp scoped_prompt_selects(view, action) do
    for %{widget: :select, select: %{scope: %{}} = select} = field <-
          Map.get(view.prompts, action, []),
        do: {field.name, select}
  end

  defp scoped_select?(%{scope: %{}}), do: true
  defp scoped_select?(_select), do: false

  # {value, label} of a pre-filled option: unchanged with its label when
  # the actor can pick it, {"", ""} when the read finds nothing. A read
  # that fails keeps the value, without a label.
  defp prefill_option(select, value, record, ash_opts) when is_binary(value) and value != "" do
    case fetch_option(select, value, ash_opts, record) do
      {:ok, option} -> {value, AshA2ui.Info.option_entry(option, select)["label"]}
      :not_found -> {"", ""}
      {:error, _error} -> {value, ""}
    end
  end

  defp prefill_option(_select, value, _record, _ash_opts), do: {value, ""}

  # The row's primary key: what a scope's record_argument receives, and (as
  # a string) the id written to /prompt/record/<action>.
  defp row_key(record) do
    [key | _rest] = ResourceInfo.primary_key(record.__struct__)
    Map.get(record, key)
  end

  defp row_id(record), do: to_string(row_key(record))

  defp prefill_value(resource, record, field) do
    if ResourceInfo.attribute(resource, field) do
      case json_value(Map.get(record, field)) do
        nil -> ""
        value -> value
      end
    else
      ""
    end
  end

  defp generic_result({:ok, result}, env, status_text)
       when is_map(result) and not is_struct(result) do
    success(env, status_text, %{
      "result" => json_map(result),
      "resultText" => action_result_text(result)
    })
  end

  defp generic_result({:error, error}, %{view: view} = env, _status_text) do
    {:error, error_messages(view, error, shown_fields(env))}
  end

  defp generic_result(_ok_or_other, env, status_text) do
    success(env, status_text)
  end

  # If the generic action declares a `:record_id` argument, pass the
  # context's "recordId" through to it.
  defp generic_params(action, record_id) do
    if record_id && Enum.any?(action.arguments, &(&1.name == :record_id)) do
      %{record_id: record_id}
    else
      %{}
    end
  end

  # --- bulk actions ----------------------------------------------------------

  # A bulk run over a row selection (see AshA2ui.Bulk). The allowlist is
  # checked first, so nothing is read for a refused action; then the target
  # table, the selection (non-empty, page-capped), the authorized re-read
  # through the table's read action and scope, and one single-row dispatch
  # per re-read record (the same `via` / destroy / update / generic calls an
  # `invoke` makes). Records do not share a transaction: one failure never
  # rolls back the others. The targets refresh once, as `invoke` does —
  # and not at all when no record was written.
  defp bulk_invoke(context, %{view: view} = env) do
    with {:ok, action_name} <- Bulk.allowed_action(view, context),
         {:ok, table} <- Bulk.target_table(view, context, action_name, "bulk_invoke"),
         {:ok, ids} <- Bulk.selection(table, context, view.l10n) do
      setting = Map.get(view.actions, action_name)
      env = env |> Map.put(:invoked, action_name) |> Map.put(:setting, setting)

      bulk_run(table, action_name, setting, ids, env)
    else
      {:error, text} -> {:error, [status(view, text)]}
    end
  end

  defp bulk_run(table, action_name, setting, ids, %{view: view} = env) do
    conditions = (setting && setting.visible_when) || []
    loads = Enum.uniq(table.loads ++ Conditions.condition_loads(view.resource, conditions))

    case bulk_records(view, table, ids, loads, env) do
      {:ok, records} ->
        outcomes = Enum.map(records, &bulk_outcome(action_name, setting, conditions, &1, env))
        bulk_messages(table, action_name, length(ids), Bulk.result(length(ids), outcomes), env)

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # An unmet require_context means the table shows nothing: every id is
  # refused, without a read. The re-read runs under the table's active
  # preset (the carried query state, parsed like a refresh's, else the
  # default preset), so a preset that swaps the read action — a "deleted"
  # view, say — re-reads the rows it showed.
  defp bulk_records(view, table, ids, loads, env) do
    case ContextRunner.table_scope(view, table, env.selected) do
      :require_unmet ->
        {:ok, []}

      {:ok, scope} ->
        Bulk.read_selected(table, env.refresh[table.name], ids, scope, loads, env.ash_opts)
    end
  end

  # visible_when is the single-row predicate (Conditions.visible?/3) applied
  # to each re-read record; records that fail it are skipped, never written.
  defp bulk_outcome(action_name, setting, conditions, record, %{view: view} = env) do
    if Conditions.visible?(view.resource, conditions, record) do
      action_name
      |> bulk_dispatch(setting, record, env)
      |> bulk_record_outcome(record, view)
    else
      :skipped
    end
  end

  defp bulk_dispatch(_action_name, %{via: {module, function, extra_args}}, record, env)
       when not is_nil(module) do
    call_via(module, function, extra_args, record, env)
  end

  defp bulk_dispatch(action_name, _setting, record, %{view: view, ash_opts: ash_opts}) do
    case run_direct(
           view,
           action_name,
           Map.get(record, :id),
           fn -> {:ok, record} end,
           %{},
           ash_opts
         ) do
      {_kind, result} -> result
      :not_invocable -> {:error, "cannot run as a bulk action"}
    end
  end

  defp bulk_record_outcome(:ok, _record, _view), do: :ok
  defp bulk_record_outcome({:ok, _result}, _record, _view), do: :ok

  defp bulk_record_outcome({:error, error}, record, view),
    do: {:failed, bulk_record_id(record), bulk_error_text(view, error)}

  defp bulk_record_outcome(other, record, _view) do
    {:failed, bulk_record_id(record),
     "returned an invalid result (expected :ok, {:ok, term}, or {:error, term}): " <>
       inspect(other)}
  end

  defp bulk_record_id(record), do: json_value(Map.get(record, :id))

  # One line per failed record: its field errors ("score: must be ..."), or
  # the status text a single-row invoke would have shown.
  defp bulk_error_text(_view, text) when is_binary(text), do: text

  defp bulk_error_text(view, error) do
    case field_errors(view.l10n, error) do
      [] ->
        view |> error_messages(error) |> List.last() |> feedback_value() |> Map.fetch!("message")

      fields ->
        view.l10n
        |> L10n.join(
          for(
            {segments, text} <- fields,
            do:
              t(view, msg("%{field}: %{message}"),
                field: Enum.map_join(segments, ".", &to_string/1),
                message: text
              )
          ),
          msg("%{first}; %{rest}")
        )
    end
  end

  # The run's follow-ups: the /bulk/<table>/result write, then — when at
  # least one record was written — the standard success follow-ups
  # (refreshes honoring `refreshes`, and typed feedback that is
  # "warning" on partial success); otherwise an error status and no refresh.
  defp bulk_messages(table, action_name, selected, result, %{view: view} = env) do
    text =
      Bulk.status_text(
        action_name,
        selected,
        result,
        ResolvedView.action_label(view, action_name),
        view.l10n
      )

    result_write = update_data_model(view, Bulk.result_path(table), result)

    if result["ok"] == 0 do
      {:error, [result_write, status(view, text, "ACTION_FAILED")]}
    else
      env = Map.put(env, :feedback_kind, Bulk.feedback_kind(selected, result))

      case success(env, text, %{"result" => result}) do
        {:ok, messages} -> {:ok, [result_write | messages]}
        {:error, messages} -> {:error, messages}
      end
    end
  end

  # "Select page" / "Clear": the table is re-read exactly as a refresh
  # would read it (carried query state, context scope, as the actor) and its
  # rows are rewritten with "_selected" set — the client's rows are never
  # echoed back.
  defp bulk_select(context, %{view: view} = env) do
    selected = Map.get(context, "selected")

    with {:ok, table} <- Bulk.target_table(view, context, nil, "bulk_select"),
         :ok <- bulk_selected_flag(selected) do
      case table_refresh(view, table, env.refresh[table.name], env.ash_opts, env.selected) do
        {:ok, messages} ->
          messages = Enum.map(messages, &mark_selected(&1, table, selected))
          {:ok, messages ++ capped_selection_status(view, table, messages, selected)}

        {:error, error} ->
          {:error, error_messages(view, error)}
      end
    else
      {:error, text} -> {:error, [status(view, text)]}
    end
  end

  defp bulk_selected_flag(selected) when is_boolean(selected), do: :ok

  defp bulk_selected_flag(_selected),
    do: {:error, ~s(Malformed bulk_select action: "selected" must be true or false.)}

  defp capped_selection_status(view, table, messages, selected) do
    count =
      Enum.find_value(messages, 0, fn
        %{"updateDataModel" => %{"path" => path, "value" => rows}}
        when path == table.records_path and is_list(rows) ->
          length(rows)

        _other ->
          nil
      end)

    case Bulk.capped_selection_text(table, count, selected, view.l10n) do
      nil -> []
      text -> notice(view, text)
    end
  end

  # An informational outcome on an otherwise successful action: "warning"
  # feedback. The action succeeded, so a function call's response is a value.
  defp notice(view, text),
    do: [update_data_model(view, "/ui/feedback", Experience.feedback("warning", text))]

  defp mark_selected(
         %{"updateDataModel" => %{"path" => path, "value" => rows} = update} = message,
         %{records_path: path} = table,
         selected
       )
       when is_list(rows) do
    rows = Bulk.mark_rows(table, rows, selected)
    %{message | "updateDataModel" => %{update | "value" => rows}}
  end

  defp mark_selected(message, _table, _selected), do: message

  # --- record population -----------------------------------------------------

  # The /form population of the start_edit task: the record's field values
  # plus one row array per nested-form argument (loaded through the
  # argument's relationship), then the searchable selects' label rewrite
  # (/select).
  defp form_population(view, record) do
    form =
      view
      |> record_values(record, form_fields(view))
      |> Map.merge(nested_row_values(view, record))

    [update_data_model(view, "/form", form) | select_state_messages(view, record)]
  end

  # The VIEW task's population — the read-only half of the state machine.
  # The record is rendered from the derived `/ui/panel/record` display
  # values; `/form` (the edit buffer) is never written, so view mode cannot
  # masquerade as edit-minus-save. Same field values the form would have
  # shown (nested-form rows are edit machinery and stay out of the display).
  defp panel_record_population(view, record, ash_opts) do
    [
      update_data_model(
        view,
        "/ui/panel/record",
        linked_record_values(view, record, form_fields(view), ash_opts)
      )
    ]
  end

  # The view task loads the form's relationship loads plus whatever its
  # linked fields need (the display record carries "_links").
  defp view_loads(view) do
    Enum.uniq(
      ResolvedView.form_loads(view) ++
        AshA2ui.Links.loads(view.resource, form_fields(view), view.fields)
    )
  end

  # The /form/<argument> rows of the record's currently-related records:
  # pick_existing rows are %{"_row", "id", "label"}; create_inline rows carry
  # the destination's primary key fields plus the sub-form field values, with
  # "_row" derived from the primary key (keeping "id" lets the
  # manage_relationship on_match path update instead of recreate).
  defp nested_row_values(view, record) do
    Map.new(view.nested_forms, fn {name, nested} ->
      related = related_list(record, nested.relationship)
      {Atom.to_string(name), Enum.map(related, &nested_row(nested, &1))}
    end)
  end

  defp related_list(record, relationship) do
    case Map.get(record, relationship) do
      %Ash.NotLoaded{} -> []
      nil -> []
      related when is_list(related) -> related
      related -> [related]
    end
  end

  defp nested_row(%{mode: :pick_existing} = nested, related) do
    entry = AshA2ui.Info.option_entry(related, nested)
    %{"_row" => entry["value"], "id" => entry["value"], "label" => entry["label"]}
  end

  defp nested_row(%{mode: :create_inline} = nested, related) do
    pk_fields = Ash.Resource.Info.primary_key(nested.destination)

    row =
      Map.new(pk_fields ++ nested.fields, fn field ->
        {Atom.to_string(field), json_value(Map.get(related, field))}
      end)

    Map.put(row, "_row", Enum.map_join(pk_fields, "-", &to_string(Map.get(related, &1))))
  end

  # One wholesale /select rewrite: searchable selects get their current
  # selection's label (through the loaded belongs_to), pickers reset.
  defp select_state_messages(view, record) do
    case ResolvedView.select_state(view) do
      state when state == %{} ->
        []

      state ->
        filled =
          Enum.reduce(view.selects, state, fn
            {name, %{search_fields: [_ | _]} = select}, acc ->
              label = related_label(record, select)
              Map.put(acc, to_string(name), %{"search" => "", "label" => label})

            _plain_select, acc ->
              acc
          end)

        [update_data_model(view, "/select", filled)]
    end
  end

  defp related_label(record, select) do
    case Map.get(record, select.relationship) do
      %Ash.NotLoaded{} -> ""
      nil -> ""
      related -> AshA2ui.Info.option_entry(related, select)["label"]
    end
  end

  # --- report (aggregate/report queries) ---------------------------------------

  # The report a "report" action targets: the only report on single-report
  # surfaces; otherwise the context must carry the source "component" (the
  # emitted Run buttons always do).
  defp report_target(%ResolvedView{reports: [report]}, _context), do: {:ok, report}

  defp report_target(%ResolvedView{reports: []} = view, _context) do
    {:error, [status(view, "This surface declares no :report components.")]}
  end

  defp report_target(view, context) do
    case Map.get(context, "component") do
      component when is_binary(component) ->
        case Enum.find(view.reports, &(to_string(&1.name) == component)) do
          nil -> {:error, [status(view, "Unknown report component #{inspect(component)}.")]}
          report -> {:ok, report}
        end

      _missing ->
        {:error,
         [
           status(
             view,
             ~s(Malformed report action: multi-report surfaces require "component" in the context.)
           )
         ]}
    end
  end

  # Runs the report's declared generic action (actor-scoped, authorized like
  # any invocation) with the client params filtered to the declared `params`
  # allowlist (blank inputs are unset — a "" never reaches the argument
  # cast) and cast against the action's arguments. The action must return a
  # list of row maps; rows are serialized down to the declared `fields`
  # (atom or string keys accepted) and written wholesale to the reserved
  # /report/<name>/rows path.
  defp run_report(view, report, params, ash_opts) do
    case invoke_report(view, report, params, ash_opts) do
      {:ok, serialized} ->
        {:ok,
         [
           update_data_model(view, "#{report.path}/rows", serialized),
           report_status(view, length(serialized))
         ]}

      {:error, messages} ->
        {:error, messages}
    end
  end

  # The shared report invocation ("report" runs + report exports): filters
  # the client params to the declared allowlist (blank inputs are unset),
  # casts them against the action's arguments, runs the action and
  # serializes the returned row maps down to the declared fields. Errors
  # come back as ready-made error messages.
  defp invoke_report(view, report, params, ash_opts) do
    allowed = MapSet.new(report.params, &Atom.to_string/1)

    filtered =
      ((is_map(params) && params) || %{})
      |> Map.filter(fn {key, value} -> normalize_key(key) in allowed and value != "" end)

    view.resource
    |> Ash.ActionInput.for_action(
      report.action,
      cast_values(view.resource, report.action, filtered),
      ash_opts
    )
    |> Ash.run_action()
    |> case do
      {:ok, rows} when is_list(rows) ->
        {:ok, Enum.map(rows, &report_row(report, &1))}

      {:ok, _not_a_list} ->
        {:error,
         [
           status(
             view,
             "Report #{inspect(to_string(report.name))} did not return a list of rows."
           )
         ]}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  defp report_row(report, row) when is_map(row) and not is_struct(row) do
    Map.new(report.fields, fn field ->
      value =
        case Map.fetch(row, field) do
          {:ok, value} -> value
          :error -> Map.get(row, Atom.to_string(field))
        end

      {Atom.to_string(field), json_value(value)}
    end)
  end

  defp report_row(report, _not_a_map) do
    Map.new(report.fields, &{Atom.to_string(&1), ""})
  end

  defp report_status(view, count) do
    update_data_model(
      view,
      "/ui/feedback",
      Experience.feedback("success", report_status_text(view, count), %{
        "result" => %{"count" => count}
      })
    )
  end

  defp report_status_text(view, count),
    do:
      L10n.tn(
        view.l10n,
        msg_plural("Report complete: %{count} row.", "Report complete: %{count} rows."),
        count
      )

  # --- export (CSV file export, see AshA2ui.Export) ---------------------------

  # The table or report an "export" action targets: the only exporting
  # component when there is exactly one; otherwise the context must carry
  # the source "component" (the emitted Export buttons always do).
  defp export_target(view, context) do
    exporting = Enum.filter(view.tables ++ view.reports, & &1.export)

    case {exporting, Map.get(context, "component")} do
      {[], _any} ->
        {:error, [status(view, "This surface declares no exports.")]}

      {[only], nil} ->
        {:ok, only}

      {_several, component} when is_binary(component) ->
        case Enum.find(exporting, &(to_string(&1.name) == component)) do
          nil -> {:error, [status(view, "Unknown export component #{inspect(component)}.")]}
          target -> {:ok, target}
        end

      {_several, _missing} ->
        {:error,
         [
           status(
             view,
             ~s(Malformed export action: surfaces with several exports require "component" ) <>
               "in the context."
           )
         ]}
    end
  end

  # The exported columns: the declared allowlist, narrowed by the carried
  # column selection (`"columns"` — the /export/<name>/columns booleans)
  # when the export declares column_select. Unknown keys are ignored (the
  # allowlist is the declared columns, never client input); an
  # every-column-unchecked selection is rejected.
  defp export_columns(_view, %{export: %{column_select: false} = export}, _context) do
    {:ok, export.columns}
  end

  defp export_columns(view, %{export: export}, context) do
    selection = Map.get(context, "columns")

    columns =
      if is_map(selection) do
        Enum.filter(export.columns, &(Map.get(selection, to_string(&1)) == true))
      else
        export.columns
      end

    case columns do
      [] -> {:error, [status(view, t(view, msg("Select at least one column to export.")))]}
      columns -> {:ok, columns}
    end
  end

  # A table export re-reads the table under its context scope and — when a
  # query is configured — the carried query state's search/filters/preset,
  # but always page 1 at the export row cap (an export is the filtered set,
  # not the on-screen page). A report export re-runs the generic action
  # with the carried params. Both serialize through the standard row
  # serialization, so CSV cells match what the table/report renders.
  defp export_row_maps(
         %{component: %AshA2ui.Component{name: :report}} = report,
         context,
         %{view: view, ash_opts: ash_opts}
       ) do
    invoke_report(view, report, Map.get(context, "params"), ash_opts)
  end

  defp export_row_maps(table, _context, %{view: view} = env) do
    case ContextRunner.table_scope(view, table, env.selected) do
      :require_unmet ->
        {:ok, []}

      {:ok, scope} ->
        # Columns the table does not show are loaded for this read only.
        export_table = %{table | loads: Enum.uniq(table.loads ++ table.export.loads)}
        fields = Enum.uniq(table_fields(table) ++ table.export.columns)

        case read_export_table(export_table, scope, env) do
          # Raw values, not the table's display rows: a CSV export carries
          # stored enum values (as report exports do), not their labels.
          {:ok, records} ->
            {:ok, Enum.map(records, &record_values(view, &1, fields))}

          {:error, error} ->
            {:error, error_messages(view, error)}
        end
    end
  end

  defp read_export_table(%{query: nil} = table, scope, env) do
    case read_table(table, env.ash_opts, scope) do
      {:ok, records} -> {:ok, Enum.take(records, table.export.limit)}
      {:error, error} -> {:error, error}
    end
  end

  defp read_export_table(table, scope, env) do
    params =
      (env.refresh[table.name] || QueryRunner.default_params(table))
      |> Map.merge(%{page: 1, page_size: table.export.limit})

    case QueryRunner.run(table, params, env.ash_opts, scope) do
      {:ok, records, _query_state} -> {:ok, records}
      {:error, error} -> {:error, error}
    end
  end

  # The delivery: one `downloadFile` callRendererFunction carrying the CSV
  # as a base64 data URL (see AshA2ui.Export), then the success feedback.
  defp deliver_export(view, target, columns, row_maps) do
    headers = Enum.map(columns, &export_header(view, &1))
    cells = Enum.map(row_maps, fn row -> Enum.map(columns, &Map.get(row, to_string(&1))) end)
    csv = Csv.encode(headers, cells)
    filename = target.export.filename

    call =
      Encoder.call_renderer_function(
        view.surface_id,
        "downloadFile",
        %{"filename" => filename, "mimeType" => "text/csv", "dataUrl" => Csv.data_url(csv)},
        []
      )

    text =
      L10n.tn(
        view.l10n,
        msg_plural(
          "Exported %{filename} (%{count} rows).",
          "Exported %{filename} (%{count} rows)."
        ),
        length(cells),
        filename: filename
      )

    feedback =
      Experience.feedback("success", text, %{
        "result" => %{"filename" => filename, "rows" => length(cells)}
      })

    {:ok, [call, update_data_model(view, "/ui/feedback", feedback)]}
  end

  defp export_header(view, column) do
    case view.fields[column] do
      %{label: label} when is_binary(label) -> label
      _undeclared -> Label.resolve(view.l10n, nil, column)
    end
  end

  # --- edit_cell (inline cell editing) ----------------------------------------

  # The table an "edit_cell" action targets: the only table on single-table
  # surfaces; otherwise the context must carry the source "component" (the
  # emitted Save buttons always do).
  defp edit_table(%ResolvedView{tables: [table]}, _context), do: {:ok, table}

  defp edit_table(view, context) do
    case Map.get(context, "component") do
      component when is_binary(component) ->
        case Enum.find(view.tables, &(to_string(&1.name) == component)) do
          nil -> {:error, [status(view, "Unknown table component #{inspect(component)}.")]}
          table -> {:ok, table}
        end

      _missing ->
        {:error,
         [
           status(
             view,
             ~s(Malformed edit_cell action: multi-table surfaces require "component" in the context.)
           )
         ]}
    end
  end

  # The edited field must be in the table's declared editable allowlist —
  # like row_actions, that allowlist is the authorization surface for
  # client-triggered cell commits.
  defp edit_field(view, table, context) do
    requested = Map.get(context, "field")
    editable = Map.get(table, :editable)

    allowed =
      is_binary(requested) && editable &&
        Enum.find(editable.fields, &(to_string(&1) == requested))

    cond do
      not is_binary(requested) ->
        {:error, [status(view, ~s(Malformed edit_cell action: context is missing "field".))]}

      is_nil(editable) ->
        {:error,
         [status(view, "Table #{inspect(to_string(table.name))} declares no editable fields.")]}

      allowed in [nil, false] ->
        {:error,
         [
           status(
             view,
             "Field #{inspect(requested)} is not editable: it is not listed in the table's " <>
               "editable fields."
           )
         ]}

      true ->
        {:ok, allowed}
    end
  end

  # Commits one cell: the table's editable update_action runs on the
  # identified record with just the edited field's value (cast like any
  # client input). Success follows the standard refresh conventions (the
  # update_action's `refreshes` metadata applies). A validation error emits
  # the standard /errors/<field> + status writes plus a row-scoped mirror:
  # the table's records are re-read and the failing row gets the submitted
  # value back and the message at its reserved `_error_<field>` key — the
  # only template-relative place a per-row error Text can bind.
  defp edit_cell(table, field, record_id, value, %{view: view, ash_opts: ash_opts} = env) do
    action = table.editable.update_action
    env = Map.put(env, :invoked, action)

    result =
      with {:ok, record} <- fetch_record(view, record_id, ash_opts) do
        params = cast_values(view.resource, action, %{to_string(field) => value})

        record
        |> Ash.Changeset.for_update(action, params, ash_opts)
        |> Ash.update()
      end

    case result do
      {:ok, _record} ->
        success(
          env,
          t(view, msg("Updated %{field}."), field: Label.resolve(view.l10n, nil, field))
        )

      {:error, error} ->
        {:error,
         error_messages(view, error) ++
           cell_error_mirrors(view, table, field, record_id, value, error, env)}
    end
  end

  defp cell_error_mirrors(view, table, field, record_id, value, error, env) do
    text =
      Enum.find_value(field_errors(view.l10n, error), fn
        {[^field], text} -> text
        _other_field -> nil
      end)

    with true <- is_binary(text),
         {:ok, scope} <- ContextRunner.table_scope(view, table, env.selected),
         {:ok, records} <- read_edited_table(table, scope, env) do
      rows =
        view
        |> rows(table, records, env.ash_opts)
        |> Enum.map(&patch_errored_row(&1, record_id, field, value, text))

      [update_data_model(view, table.records_path, rows)]
    else
      _no_field_error_or_unreadable -> []
    end
  end

  defp patch_errored_row(%{"id" => record_id} = row, record_id, field, value, text) do
    row
    |> Map.put(to_string(field), value)
    |> Map.put("_error_#{field}", text)
  end

  defp patch_errored_row(row, _record_id, _field, _value, _text), do: row

  # The mirror re-read honors the client's current query state (page,
  # search, filters), like any refresh.
  defp read_edited_table(%{query: nil} = table, scope, env) do
    read_table(table, env.ash_opts, scope)
  end

  defp read_edited_table(table, scope, env) do
    params = env.refresh[table.name] || QueryRunner.default_params(table)

    case QueryRunner.run(table, params, env.ash_opts, scope) do
      {:ok, records, _query_state} -> {:ok, records}
      {:error, error} -> {:error, error}
    end
  end

  # --- wizard steps ----------------------------------------------------------

  # wizard_next / wizard_back (see AshA2ui.Wizard). Next builds the FULL
  # changeset over the carried /form through form_changeset/3 — the same
  # path submit_form writes through (filtered to the form's own fields, no
  # atoms from client input) — without submitting it, and keeps only the
  # errors on fields of the current and earlier steps. Nothing is written to the data layer. Back never
  # validates and never touches /form.
  defp wizard_next(%{view: view} = env, context) do
    with {:ok, index} <- wizard_index(view, context),
         {:ok, changeset} <-
           form_changeset(env, Map.get(context, "recordId"), Map.get(context, "values")) do
      reached = AshA2ui.Wizard.reached_fields(view, index)

      errors =
        Enum.filter(field_errors(view.l10n, %{errors: changeset.errors}), fn {[field | _rest],
                                                                              _text} ->
          MapSet.member?(reached, field)
        end)

      wizard_next_result(env, context, index, errors)
    else
      {:error, messages} when is_list(messages) -> {:error, messages}
      {:error, error} -> {:error, error_messages(view, error)}
    end
  end

  defp wizard_next_result(%{view: view}, context, index, []) do
    next = min(index + 1, AshA2ui.Wizard.last_index(view))

    {:ok,
     [update_data_model(view, "/errors", %{})] ++
       wizard_moves(view, Map.get(context, "recordId"), next)}
  end

  defp wizard_next_result(%{view: view}, context, index, errors) do
    field_messages =
      for {segments, text} <- errors do
        update_data_model(view, "/errors/" <> Enum.map_join(segments, "/", &to_string/1), text)
      end

    messages =
      [update_data_model(view, "/errors", %{}) | field_messages] ++
        [status(view, error_status(view, field_messages, []), "VALIDATION_FAILED")]

    {:error, messages ++ wizard_moves(view, Map.get(context, "recordId"), index)}
  end

  defp wizard_back(%{view: view}, context) do
    with {:ok, index} <- wizard_index(view, context) do
      {:ok, wizard_moves(view, Map.get(context, "recordId"), max(index - 1, 0))}
    end
  end

  defp wizard_index(view, context) do
    if AshA2ui.Wizard.stepped?(view) do
      case AshA2ui.Wizard.parse_index(view, Map.get(context, "index")) do
        {:ok, index} ->
          {:ok, index}

        :error ->
          {:error,
           [status(view, ~s(Malformed wizard action: "index" must be an integer step index.))]}
      end
    else
      {:error, [status(view, "This surface's form does not declare steps.")]}
    end
  end

  # The /ui/wizard state for `index` plus the panel's primary label and
  # submit gate for that step (create without a record id, edit with one).
  defp wizard_moves(view, record_id, index) do
    mode = if is_nil(record_id), do: :create, else: :edit
    state = Experience.panel_state(mode, view, record_id, index)

    [
      update_data_model(view, "/ui/wizard", AshA2ui.Wizard.state(view, index)),
      update_data_model(view, "/ui/panel/primary_label", state["primary_label"]),
      update_data_model(view, "/ui/panel/submit_visible", state["submit_visible"])
    ]
  end

  # Every /form reset (task open/cancel, a successful submit) returns a
  # stepped form to its first step. A no-op without steps.
  defp wizard_reset(view) do
    if AshA2ui.Wizard.stepped?(view),
      do: [update_data_model(view, "/ui/wizard", AshA2ui.Wizard.state(view, 0))],
      else: []
  end

  # A failed submit_form on a stepped form jumps to the earliest step owning
  # an erroring field; an error on no step's field stays on the last step.
  # The submitted /form carries "id" on edit tasks (it only picks the
  # panel label — the write already ran against the context's recordId).
  defp wizard_submit_failure(%{submitted: submitted, view: view}, error) do
    if AshA2ui.Wizard.stepped?(view) do
      fields = for {[field | _rest], _text} <- field_errors(view.l10n, error), do: field

      index =
        AshA2ui.Wizard.earliest_owning_index(view, fields) || AshA2ui.Wizard.last_index(view)

      record_id = if is_map(submitted), do: Map.get(submitted, "id")
      wizard_moves(view, record_id, index)
    else
      []
    end
  end

  defp wizard_submit_failure(_env, _error), do: []

  # A successful submit_form ends the stepped form's run: back to step 0
  # (the panel is closed by task_success/2 in the same batch). Any other
  # success (a row action) leaves the open task alone: its step and the
  # panel's primary label and submit gate stay in step with each other.
  defp wizard_success_reset(%{view: view, submitted: _values}), do: wizard_reset(view)
  defp wizard_success_reset(_env), do: []

  # --- success follow-ups ----------------------------------------------------

  defp after_write(:ok, env, status_text), do: success(env, status_text)
  defp after_write({:ok, _record}, env, status_text), do: success(env, status_text)

  defp after_write({:error, error}, %{view: view} = env, _status_text) do
    messages = error_messages(view, error, shown_fields(env)) ++ nested_error_mirrors(env, error)
    {:error, messages ++ wizard_submit_failure(env, error)}
  end

  # A success re-reads and re-emits every refresh-target table (each table's
  # records path, plus its query state when a query is attached — run
  # through the carried-or-default query params, see refresh_params/2),
  # then the standard /form, /errors and /ui writes.
  #
  # Targets default to *every* table; an `action` entity
  # (`action :approve do refreshes [:new_items] end`) limits the refresh to
  # the named table components. `extra` is merged into the success
  # feedback: a map-returning generic action's `result` and `resultText`, a
  # bulk run's `result`.
  defp success(%{view: view} = env, status_text, extra \\ %{}) do
    case refresh_messages(env) do
      {:ok, refresh} ->
        {:ok,
         refresh ++
           [
             update_data_model(view, "/form", ResolvedView.initial_form(view)),
             update_data_model(view, "/errors", %{})
           ] ++
           select_clear(view) ++
           prompt_clear(env) ++
           task_success(env, status_text) ++
           success_feedback(env, status_text, extra) ++
           wizard_success_reset(env)}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # A successful task submission (submit_form) closes the panel and
  # returns to browse. The typed success feedback itself is written for
  # EVERY success (see success_feedback/2).
  defp task_success(%{submitted: _values, view: view}, _status_text) do
    [
      update_data_model(view, "/ui/intent", "browse"),
      update_data_model(view, "/ui/panel", Experience.panel_state(:hidden))
    ]
  end

  defp task_success(_env, _status_text), do: []

  # Feedback for EVERY successful outcome, invoke and submit alike: the
  # /ui/feedback success value is what the status Text and the admin
  # statusBanner bind. A bulk run passes `:feedback_kind` ("warning" on
  # partial success). Failures get theirs from status/3.
  defp success_feedback(%{view: view} = env, status_text, extra) do
    kind = Map.get(env, :feedback_kind, "success")
    [update_data_model(view, "/ui/feedback", Experience.feedback(kind, status_text, extra))]
  end

  # Surfaces with searchable selects / pick_existing pickers reset their
  # /select state alongside the /form clear.
  defp select_clear(view) do
    case ResolvedView.select_state(view) do
      state when state == %{} -> []
      state -> [update_data_model(view, "/select", state)]
    end
  end

  # A successful prompt-backed invoke resets its /prompt/values/<action>
  # state so the next prompt starts clean.
  defp prompt_clear(%{view: view, setting: %{prompt_fields: [_ | _], name: name}}) do
    fields = Map.get(view.prompts, name, [])

    selects =
      if Enum.any?(fields, &match?(%{select: %{search_fields: [_ | _]}}, &1)) or
           Enum.any?(fields, &match?(%{select: %{scope: %{}}}, &1)),
         do: [update_data_model(view, "/prompt/select/#{name}", %{})],
         else: []

    [update_data_model(view, "/prompt/values/#{name}", %{}) | selects] ++ scope_clear(view, name)
  end

  defp prompt_clear(_env), do: []

  # A scoped prompt's options and row reset with its values: the next
  # prompt reads its own row's options.
  defp scope_clear(view, action) do
    case scoped_prompt_selects(view, action) do
      [] ->
        []

      scoped ->
        [
          update_data_model(
            view,
            "/prompt/options/#{action}",
            Map.new(scoped, fn {field, _select} -> {Atom.to_string(field), []} end)
          ),
          update_data_model(view, "/prompt/record/#{action}", "")
        ]
    end
  end

  defp refresh_messages(%{view: view, ash_opts: ash_opts, refresh: refresh} = env) do
    view
    |> refresh_targets(env[:invoked])
    |> Enum.reduce_while({:ok, []}, fn table, {:ok, acc} ->
      case table_refresh(view, table, refresh[table.name], ash_opts, env.selected) do
        {:ok, messages} -> {:cont, {:ok, acc ++ messages}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> with_swimlane_totals(view)
  end

  # A swimlaned board's swimlane-row and stage-column totals follow the
  # cell totals a batch rewrote: every row or column whose cells all
  # refreshed gets its sum (see AshA2ui.Board.aggregate_totals/2); the
  # others keep theirs. A no-op without swimlaned boards.
  defp with_swimlane_totals({:ok, messages}, view),
    do: {:ok, with_swimlane_totals(messages, view)}

  defp with_swimlane_totals({:error, _error} = error, _view), do: error

  defp with_swimlane_totals(messages, view) when is_list(messages) do
    cell_totals =
      for %{"updateDataModel" => %{"path" => "/_lane_total_" <> name, "value" => text}} <-
            messages,
          into: %{},
          do: {name, text}

    aggregates =
      if cell_totals == %{},
        do: [],
        else: AshA2ui.Board.aggregate_totals(view.tables, cell_totals)

    messages ++ Enum.map(aggregates, fn {path, text} -> update_data_model(view, path, text) end)
  end

  defp refresh_targets(view, invoked) do
    case invoked && Map.get(view.refreshes, invoked) do
      nil -> view.tables
      names -> Enum.filter(view.tables, &(&1.name in names))
    end
  end

  # Every table refresh runs under the current context scope: tables whose
  # require_context is unmet render no records (no read executes), scoped
  # tables get their context filters ANDed onto the read.
  defp table_refresh(view, table, params, ash_opts, selected) do
    case ContextRunner.table_scope(view, table, selected) do
      :require_unmet -> {:ok, empty_table_messages(view, table, params)}
      {:ok, scope} -> scoped_table_refresh(view, table, params, ash_opts, scope)
    end
  end

  defp empty_table_messages(view, %{query: nil} = table, _params) do
    records_messages(view, table, [])
  end

  defp empty_table_messages(view, table, params) do
    state =
      QueryRunner.state(
        table.query,
        params || QueryRunner.default_params(table),
        0,
        false,
        view.l10n
      )

    records_messages(view, table, []) ++ query_state_messages(view, table, state, [])
  end

  defp scoped_table_refresh(view, %{query: nil} = table, _params, ash_opts, scope) do
    case read_table(table, ash_opts, scope) do
      {:ok, records} ->
        {:ok, records_messages(view, table, rows(view, table, records, ash_opts))}

      {:error, error} ->
        {:error, error}
    end
  end

  defp scoped_table_refresh(view, table, params, ash_opts, scope) do
    params = params || QueryRunner.default_params(table)

    case QueryRunner.run(table, params, ash_opts, scope, view.l10n) do
      {:ok, records, query_state} ->
        rows = rows(view, table, records, ash_opts)

        {:ok,
         records_messages(view, table, rows) ++
           query_state_messages(view, table, query_state, rows)}

      {:error, error} ->
        {:error, error}
    end
  end

  # The records rewrite, plus the table's `_empty_visible` sentinel so the
  # empty state stays data-driven across refreshes.
  defp records_messages(view, table, rows) do
    [update_data_model(view, table.records_path, rows)]
    |> Kernel.++(empty_state_messages(view, table, rows))
    |> Kernel.++(lane_total_messages(view, table, rows, nil))
    |> Kernel.++(matrix_messages(view, table, rows))
  end

  # A matrix rewrites its grid at /_matrix_<table> beside its records (see
  # AshA2ui.Matrix).
  defp matrix_messages(view, table, rows) do
    if AshA2ui.Matrix.matrix?(table),
      do: [
        update_data_model(
          view,
          AshA2ui.Matrix.path(table),
          Encoder.matrix_data(view, table, rows)
        )
      ],
      else: []
  end

  # Board lanes rewrite their /_lane_total_<lane> beside their records (see
  # AshA2ui.Board). A lane with a query takes its total from the query state,
  # so its records rewrite leaves the total to query_state_messages/4.
  defp lane_total_messages(view, table, rows, state) do
    if AshA2ui.Board.lane?(table) and (is_nil(table.query) or not is_nil(state)) do
      text = AshA2ui.Board.total_text(length(rows), state)
      [update_data_model(view, AshA2ui.Board.total_path(table), text)]
    else
      []
    end
  end

  defp empty_state_messages(view, table, rows) do
    [
      update_data_model(
        view,
        Experience.empty_visible_path(view, table),
        Experience.sentinel(rows == [])
      )
    ]
  end

  # The query-state rewrite, with the pagination sentinels re-derived
  # from the refreshed rows and — when the admin catalog is effective — the
  # plain boolean pagination props (both adornments are gated no-ops
  # outside their mode; the handler learns no new actions for either).
  defp query_state_messages(view, table, state, rows) do
    [
      update_data_model(
        view,
        table.query_path,
        state
        |> Experience.with_pagination_sentinels(length(rows), view.l10n)
        |> Experience.with_admin_pagination_booleans(length(rows), view)
      )
    ] ++ lane_total_messages(view, table, rows, state)
  end

  # Table rows go through the encoder's own row serialization, so a refresh
  # emits exactly the row the initial render did: display values (enum
  # labels), the per-row visibility data (`"_actions"` + `"_visible_<action>"`,
  # see AshA2ui.Conditions), the row_layout badge text, `_links` and the bulk
  # `_selected` flag.
  defp rows(view, table, records, ash_opts) do
    links = AshA2ui.Links.context(table.resource, view.fields, table_fields(table), ash_opts)
    Enum.map(records, &Encoder.serialize_row(view, table, &1, links))
  end

  # Human-readable, selectable text for a map-returning generic action:
  # one "Humanized key: value" line per key, sorted by key.
  defp action_result_text(result) do
    result
    |> Enum.map(fn {key, value} -> {to_string(key), json_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} ->
      "#{Label.humanize(key)}: #{display_value(value)}"
    end)
  end

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: Jason.encode!(value)

  # --- Ash invocation helpers ------------------------------------------------

  defp read_table(table, ash_opts, scope) do
    # A related table reads a resource that may live in another domain.
    ash_opts =
      Keyword.put(ash_opts, :domain, ResourceInfo.domain(table.resource) || ash_opts[:domain])

    table.resource
    |> Ash.Query.for_read(
      table.read_action || primary_action(table.resource, :read),
      %{},
      ash_opts
    )
    |> ContextRunner.apply_scope(scope)
    |> Ash.Query.load(table.loads)
    |> Ash.read()
  end

  # Record lookups (updates, destroys, view/edit tasks) go through the single
  # table's read action; on multi-table surfaces — where per-table reads may
  # be filtered slices — through the resource's primary read. `loads` covers
  # visible_when condition calculations when enforcement needs them.
  defp fetch_record(view, record_id, ash_opts, loads \\ []) do
    opts =
      ash_opts
      |> Keyword.put(:action, read_action(view))
      |> Keyword.put(:load, loads)

    Ash.get(view.resource, record_id, opts)
  end

  defp read_action(view), do: view.read_action || primary_action(view.resource, :read)

  defp primary_action(resource, type) do
    ResourceInfo.primary_action!(resource, type).name
  end

  # Cast string-keyed client values to the action's accepted attributes and
  # arguments by matching against their known names — never creating atoms
  # from client input. Unknown keys are dropped. Single-select ChoicePickers
  # bind string lists, so a list value targeting a non-array attribute or
  # argument is unwrapped ([v] -> v, [] -> nil) before Ash casts it.
  defp cast_values(resource, action_name, values) do
    action = ResourceInfo.action(resource, action_name)

    known =
      action.arguments
      |> Enum.map(& &1.name)
      |> Kernel.++(List.wrap(Map.get(action, :accept)))
      |> Map.new(&{Atom.to_string(&1), &1})

    values
    |> Enum.flat_map(fn {key, value} ->
      case Map.fetch(known, normalize_key(key)) do
        {:ok, name} -> [{name, unwrap_single(value, target_type(resource, action, name))}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key

  defp target_type(resource, action, name) do
    case Enum.find(action.arguments, &(&1.name == name)) do
      %{type: type} -> type
      nil -> ResourceInfo.attribute(resource, name).type
    end
  end

  defp unwrap_single(value, {:array, _type}), do: value
  defp unwrap_single([], _type), do: nil
  defp unwrap_single([value], _type), do: value
  defp unwrap_single(value, _type), do: value

  # --- field selection -------------------------------------------------------

  defp table_fields(table) do
    case table.component.fields do
      fields when is_list(fields) -> fields
      _no_declared_fields -> public_attribute_names(table.resource)
    end
  end

  defp form_fields(view) do
    case Enum.find(view.components, &(&1.name == :form)) do
      %{fields: fields} when is_list(fields) -> fields
      _no_form -> default_row_fields(view)
    end
  end

  defp default_row_fields(%{tables: [table | _rest]}), do: table_fields(table)
  defp default_row_fields(view), do: public_attribute_names(view.resource)

  defp public_attribute_names(resource) do
    resource |> ResourceInfo.public_attributes() |> Enum.map(& &1.name)
  end

  # --- error mapping ---------------------------------------------------------

  # Maps an action's failure onto the reserved paths: field errors to
  # `/errors/<field>` (always — the inputs bind them), and one readable
  # sentence to the typed feedback:
  #
  #   * a Forbidden error class (also when the error only becomes one as a
  #     class, e.g. a host function's Forbidden exception) → not authorized;
  #   * errors without a field (an invalid change, a host function's
  #     string refusal, an unknown error) → their messages;
  #   * field errors on fields the action shows no input for (`shown`: the
  #     invoked action's prompt fields, or the submitted form's fields) →
  #     "<Label>: <message>", so they are not lost;
  #   * only shown field errors → "Validation failed. Please review the
  #     field errors."
  defp error_messages(view, error, shown \\ :all) do
    error = error_class(error)

    if match?(%Ash.Error.Forbidden{}, error) do
      [
        status(
          view,
          t(view, msg("You are not authorized to perform this action.")),
          "FORBIDDEN"
        )
      ]
    else
      field_errors = field_errors(view.l10n, error)

      field_messages =
        for {segments, text} <- field_errors do
          update_data_model(view, "/errors/" <> Enum.map_join(segments, "/", &to_string/1), text)
        end

      unshown =
        for {[field | _rest] = segments, text} <- field_errors,
            not shown_field?(shown, field),
            do:
              t(view, msg("%{field}: %{message}"),
                field: error_field_label(view, segments),
                message: text
              )

      code = if field_messages == [], do: "ACTION_FAILED", else: "VALIDATION_FAILED"

      field_messages ++
        [
          status(
            view,
            error_status(view, field_messages, general_messages(view, error) ++ unshown),
            code
          )
        ]
    end
  end

  defp error_class(error) do
    Ash.Error.to_error_class(error)
  rescue
    _not_an_error -> error
  end

  defp shown_field?(:all, _field), do: true
  defp shown_field?(shown, field), do: Enum.any?(shown, &(to_string(&1) == to_string(field)))

  defp error_field_label(view, [field | _rest]) do
    case Enum.find(view.fields, fn {name, _field} -> to_string(name) == to_string(field) end) do
      {_name, %{label: label}} when is_binary(label) -> label
      _undeclared -> Label.resolve(view.l10n, nil, field)
    end
  end

  # The fields the failed action shows inputs for: an invoke records its
  # prompt fields (none for a plain row action, see invoke/4), a
  # submit_form its form's (form_shown_fields/1); anything else counts
  # every field as shown.
  defp shown_fields(env), do: Map.get(env, :shown_fields, :all)

  # A form shows inputs for its declared fields (a stepped form's fields are
  # its steps' — a failed submit moves to the step owning the error) and for
  # its nested forms' arguments. A form without declared fields shows all.
  defp form_shown_fields(view) do
    case Enum.find(view.components, &(&1.name == :form)) do
      %{fields: fields} when is_list(fields) ->
        fields ++ Enum.map(view.nested_forms, fn {name, _nested} -> name end)

      _no_declared_fields ->
        :all
    end
  end

  # Validation errors on create_inline rows are additionally mirrored INTO
  # the submitted rows as "_error_<field>" keys (one /form/<argument>
  # rewrite), so the emitted row template's error Texts — which can only
  # bind template-relative paths — display them. The frozen
  # /errors/<argument>/<index>/<field> messages stay the programmatic
  # contract.
  defp nested_error_mirrors(%{view: view, submitted: submitted}, error)
       when is_map(submitted) do
    indexed =
      error
      |> then(&field_errors(view.l10n, &1))
      |> Enum.filter(&match?({[_argument, index, _field], _text} when is_integer(index), &1))
      |> Enum.group_by(fn {[argument, _index, _field], _text} -> to_string(argument) end)

    view.nested_forms
    |> Enum.filter(fn {_name, nested} -> nested.mode == :create_inline end)
    |> Enum.flat_map(fn {name, _nested} ->
      key = Atom.to_string(name)
      rows = submitted |> Map.get(key) |> sanitize_rows()
      row_errors = Map.get(indexed, key, [])

      if rows == [] or row_errors == [] do
        []
      else
        [update_data_model(view, "/form/#{name}", mirror_rows(rows, row_errors))]
      end
    end)
  end

  defp nested_error_mirrors(_env, _error), do: []

  defp mirror_rows(rows, row_errors) do
    cleared =
      Enum.map(
        rows,
        &Map.reject(&1, fn {k, _v} -> String.starts_with?(to_string(k), "_error_") end)
      )

    Enum.reduce(row_errors, cleared, fn {[_argument, index, field], text}, acc ->
      if index < length(acc) do
        List.update_at(acc, index, &Map.put(&1, "_error_#{field}", text))
      else
        acc
      end
    end)
  end

  defp error_status(_view, _field_messages, [_ | _] = sentences),
    do: sentences |> Enum.uniq() |> Enum.map_join(" ", &sentence/1)

  defp error_status(view, [], []), do: t(view, msg("The action failed."))

  defp error_status(view, _field_messages, []),
    do: t(view, msg("Validation failed. Please review the field errors."))

  # Messages end in a full stop when they do not end in punctuation already,
  # so several read as sentences side by side.
  defp sentence(text) do
    text = String.trim(text)
    if text =~ ~r/[.!?:]$/u, do: text, else: text <> "."
  end

  # The messages of the error's field-less leaves (an error class's
  # `errors`, or the error itself) that someone wrote for the user to read:
  # a bare string, an UnknownError carrying one, and an Invalid-class leaf
  # (its message text with `vars` interpolated). Any other leaf — a raw
  # exception Splode wrapped as an UnknownError (its `error` is then the
  # `Exception.format/2` text, "** (Module) ..."), a data-layer error, a
  # Framework-class error, an arbitrary term — can carry row values or
  # internals: it is logged server-side and reads as "The action failed."
  defp general_messages(view, error) do
    error
    |> leaf_messages(view.l10n)
    |> Enum.map(fn
      :concealed -> t(view, msg("The action failed."))
      message -> message
    end)
  end

  defp leaf_messages(%{errors: errors}, l10n) when is_list(errors),
    do: Enum.flat_map(errors, &leaf_messages(&1, l10n))

  defp leaf_messages(%{field: field}, _l10n) when not is_nil(field), do: []
  defp leaf_messages(%{fields: [_ | _]}, _l10n), do: []
  defp leaf_messages(message, _l10n) when is_binary(message), do: [message]

  defp leaf_messages(%UnknownError{error: message} = error, _l10n)
       when is_binary(message) do
    if String.starts_with?(message, ["** (", "unknown error: "]),
      do: concealed_message(error),
      else: [message]
  end

  defp leaf_messages(%{class: :invalid} = error, l10n) when is_exception(error) do
    case error_text(l10n, error) do
      "" -> []
      text -> [text]
    end
  end

  defp leaf_messages(error, _l10n), do: concealed_message(error)

  defp concealed_message(error) do
    Logger.error(fn ->
      "AshA2ui.ActionHandler: an action failed with an error not shown to the user: " <>
        concealed_detail(error)
    end)

    [:concealed]
  end

  defp concealed_detail(%UnknownError{error: message}), do: message
  defp concealed_detail(error) when is_exception(error), do: Exception.message(error)
  defp concealed_detail(error), do: inspect(error)

  # Walks the error-class `errors` list (as AshPhoenix.Form does) collecting
  # `%{field: f}` / `%{fields: [..]}` sub-errors, interpolating their `vars`
  # into the message text. Each entry is `{segments, text}` where `segments`
  # is the error's `path` (set by Ash for managed-relationship sub-errors,
  # e.g. `[:notes, 0]`) with the field appended — so a top-level error maps
  # to `/errors/<field>` exactly as before, and a nested-row error to
  # `/errors/<argument>/<index>/<field>`.
  defp field_errors(l10n, error) do
    error
    |> collect_field_errors(l10n)
    |> Enum.group_by(fn {segments, _text} -> segments end, fn {_segments, text} -> text end)
    |> Enum.map(fn {segments, texts} ->
      {segments, L10n.join(l10n, Enum.uniq(texts), msg("%{first}; %{rest}"))}
    end)
  end

  defp collect_field_errors(%{errors: errors}, l10n) when is_list(errors) do
    Enum.flat_map(errors, &collect_field_errors(&1, l10n))
  end

  defp collect_field_errors(%{field: field} = error, l10n) when not is_nil(field) do
    [{error_path(error) ++ [field], error_text(l10n, error)}]
  end

  defp collect_field_errors(%{fields: fields} = error, l10n)
       when is_list(fields) and fields != [] do
    Enum.map(fields, &{error_path(error) ++ [&1], error_text(l10n, error)})
  end

  defp collect_field_errors(_error, _l10n), do: []

  defp error_path(error) do
    case Map.get(error, :path) do
      path when is_list(path) -> path
      _no_path -> []
    end
  end

  # A missing required field has no message of its own: Ash's catalog has
  # the msgid "is required" for it. Without a translation the error's own
  # sentence is shown, as without a translator.
  defp error_text(l10n, %Ash.Error.Changes.Required{} = error), do: required_text(l10n, error)

  defp error_text(
         l10n,
         %Ash.Error.Changes.InvalidAttribute{required?: true, message: nil} = error
       ),
       do: required_text(l10n, error)

  # The message is the error's template: translated in the errors domain
  # under its own msgid (Ash's), with its `vars` as bindings.
  defp error_text(l10n, %{message: message} = error) when is_binary(message) do
    L10n.error(l10n, message, vars_bindings(Map.get(error, :vars)))
  end

  # Splode prepends a "Bread Crumbs:" preamble to Exception.message/1; the
  # human-readable message is the last non-empty line.
  defp error_text(_l10n, error) when is_exception(error),
    do: last_line(Exception.message(error))

  defp error_text(_l10n, error), do: inspect(error)

  defp required_text(l10n, error) do
    case L10n.error(l10n, "is required", []) do
      "is required" -> last_line(Exception.message(error))
      translated -> translated
    end
  end

  defp vars_bindings(vars) when is_map(vars) or is_list(vars) do
    for {key, value} <- vars, is_atom(key), do: {key, var_string(value)}
  end

  defp vars_bindings(_vars), do: []

  defp var_string(value) when is_binary(value), do: value
  defp var_string(value), do: inspect(value)

  defp last_line(message) do
    message
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
    |> Kernel.||("")
  end

  # --- message + value construction ------------------------------------------

  # An error/rejection status: the whole /ui/feedback error map. Dispatch
  # rejections default to "INVALID_ACTION"; error_messages/3 passes the
  # mapped code.
  defp status(view, text, code \\ "INVALID_ACTION"),
    do:
      update_data_model(
        view,
        "/ui/feedback",
        Experience.feedback("error", text, %{"code" => code})
      )

  defp update_data_model(view, path, value),
    do: Encoder.update_data_model(view.surface_id, path, value)

  # The FORM variant of the record's values: the /form edit buffer
  # (`form_population/2`) and the CSV export cells. A forbidden field stays
  # `null` — submitting the form unchanged must never write the masked word
  # into the column, and an export keeps the empty cell it always had. The
  # display paths mask instead (`display_record_values/3`).
  defp record_values(view, record, fields) do
    fields
    |> Map.new(fn field -> {Atom.to_string(field), field_value(view, record, field)} end)
    |> Map.put("id", json_value(Map.get(record, :id)))
  end

  # `source` columns read through the loaded relationship path (nil-safe: a
  # nil or unloaded relationship serializes to ""); plain fields read the
  # record key directly. Forbidden values serialize as `nil` here — see
  # `record_values/3` — never as the inspected placeholder struct.
  defp field_value(view, record, field) do
    case view.fields[field] do
      %{source: [_ | _] = source} ->
        case walk_source(record, source) do
          nil -> ""
          value -> json_value(value)
        end

      declared ->
        case AshA2ui.Links.virtual_value(declared, record) do
          {:ok, value} -> value
          :not_virtual -> json_value(Map.get(record, field))
        end
    end
  end

  # The DISPLAY variant of `record_values/3`: a field the actor's field
  # policies forbid draws the masked text (`AshA2ui.Masked`) — never `null`,
  # which would read as known-and-empty — and the record carries the
  # reserved `"_masked"` key with the field's reason. Shared by the detail
  # refresh and the view panel's record, through `linked_record_values/4`.
  defp display_record_values(view, record, fields) do
    {row, masked_fields} =
      fields
      |> Enum.reduce({%{}, []}, fn field, {row, masked_fields} ->
        case display_field_value(view, record, field) do
          {:masked, text} ->
            {Map.put(row, Atom.to_string(field), text), [field | masked_fields]}

          {:value, value} ->
            {Map.put(row, Atom.to_string(field), value), masked_fields}
        end
      end)

    row
    |> Map.put("id", json_value(Map.get(record, :id)))
    |> Map.merge(Masked.row_data(Enum.reverse(masked_fields), view.l10n))
  end

  # `display_record_values/3`'s field reader: the same treatment the
  # encoder's `field_value/3` gives a table row.
  defp display_field_value(view, record, field) do
    case view.fields[field] do
      %{source: [_ | _] = source} ->
        source_value(view, record, source)

      declared ->
        case AshA2ui.Links.virtual_value(declared, record) do
          {:ok, value} -> {:value, value}
          :not_virtual -> stored_value(view, record, field)
        end
    end
  end

  defp source_value(view, record, source) do
    if Masked.forbidden_source?(record, source) do
      {:masked, Masked.text(view.l10n)}
    else
      case walk_source(record, source) do
        nil -> {:value, ""}
        value -> {:value, json_value(value)}
      end
    end
  end

  defp stored_value(view, record, field) do
    value = Map.get(record, field)

    if Masked.masked?(value),
      do: {:masked, Masked.text(view.l10n)},
      else: {:value, json_value(value)}
  end

  # record_values plus the reserved "_links" of the linked fields (detail
  # and view-panel records; table rows merge theirs in rows/4).
  defp linked_record_values(view, record, fields, ash_opts) do
    row = display_record_values(view, record, fields)

    record.__struct__
    |> AshA2ui.Links.context(view.fields, fields, ash_opts)
    |> AshA2ui.Links.row_data(record, row)
    |> Map.merge(row)
  end

  defp walk_source(record, [attribute]), do: Map.get(record, attribute)

  defp walk_source(record, [relationship | rest]) do
    case Map.get(record, relationship) do
      %Ash.NotLoaded{} -> nil
      nil -> nil
      related -> walk_source(related, rest)
    end
  end

  defp json_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_value(value)} end)
  end

  # A calculation/aggregate that slipped past `loads` must not leak an
  # inspect()-ed struct onto the wire.
  defp json_value(%Ash.NotLoaded{}), do: nil
  # A field the actor's field policies forbid serializes as empty, never as
  # the inspected placeholder struct.
  defp json_value(%Ash.ForbiddenField{}), do: nil
  defp json_value(%Ash.CiString{} = value), do: to_string(value)
  defp json_value(%Decimal{} = value), do: Decimal.to_string(value)
  defp json_value(%Date{} = value), do: Date.to_iso8601(value)
  defp json_value(%Time{} = value), do: Time.to_iso8601(value)
  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp json_value(value) when is_struct(value), do: inspect(value)
  defp json_value(value) when is_map(value), do: json_map(value)
  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp json_value(value), do: value

  # A library-owned string for the reader, translated with the surface's
  # translator (see AshA2ui.L10n) exactly once, where the message is made.
  defp t(%{l10n: l10n}, msgid, bindings \\ []), do: L10n.t(l10n, msgid, bindings)
end
