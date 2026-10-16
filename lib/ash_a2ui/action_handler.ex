defmodule AshA2ui.ActionHandler do
  @moduledoc """
  Consumes A2UI client->server `action` envelope messages and invokes the
  corresponding Ash actions (actor-aware, `authorize?: true` by default).

  FROZEN CONTRACT — the `handle/3` signature is the interface every parallel
  track codes against; do not change outside an integration commit.

  ## Accepted message shapes

  The full client->server envelope from the A2UI v0.9.1 spec
  (`priv/a2ui/v0_9_1/client_to_server.json`):

      %{
        "version" => "v0.9.1",
        "action" => %{
          "name" => "submit_form",
          "surfaceId" => "...",
          "sourceComponentId" => "...",
          "timestamp" => "...",
          "context" => %{...}
        }
      }

  Be liberal in what you accept: a bare inner action map
  (`%{"name" => ..., "context" => ...}`) is also handled, for transports that
  unwrap the envelope before dispatching. Only `"name"` and `"context"` are
  consumed; the `surfaceId` on every follow-up message always comes from the
  resolved view, never from the incoming message.

  ## Supported `action.name` values

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
      placed at `/ui/action_result` and a human-readable rendering (one
      "Humanized key: value" line per key) at `/ui/action_result_text`
      (handler-defined conventions, not part of the A2UI spec). Both paths
      are cleared by every subsequent successful action. When the action's
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
      the trigger button of a prompt Modal (see `AshA2ui.Encoder.V0_9_1`)
      when it opens. The action must be an allowlisted row action declaring
      `prompt_fields`, and its `visible_when` conditions (if any) are
      enforced against the identified record. On success returns
      `updateDataModel` messages pre-filling `/prompt/values/<action>` (each
      prompt field's current record value when it is a public attribute,
      `""` otherwise) and clearing `/errors`. No Ash write happens — the
      write is the subsequent `"invoke"` from the Modal's confirm button.

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
      Buttons (see `AshA2ui.Encoder.V0_9_1`). Accepted when `field` is a
      to-one link field (`link :relationship` or `link {surface, id_path}`)
      of one of the surface's tables or details and the
      `AshA2ui.LinkResolver` resolves it, for this actor, to `surface`;
      anything else is rejected with an error outcome. A missing or empty
      `"surface"` (a row without a link for that field) is acknowledged.
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

  Unknown action names (including the removed `"select_row"`) and malformed
  messages return `{:error, [updateDataModel]}` with an error outcome.

  ## Follow-up messages

  All returned messages are A2UI `updateDataModel` server messages using the
  reserved data-model paths (see `topics/data-model-conventions`). Every
  outcome — success, validation failure, rejection, refusal — is written
  as typed feedback to `/ui/feedback` (`%{"kind" => "success" | "warning" |
  "error", "message" => text}`), the path the status Text and the admin
  statusBanner bind:

    * on success: `/records` (re-read row maps, each including `"id"`;
      `source` columns are re-loaded and walked), `/form` cleared to `%{}`,
      `/errors` cleared to `%{}`, `/ui/feedback` set to a success value, and
      `/ui/action_result` + `/ui/action_result_text` cleared — then set for
      map-returning generic actions. On query-enabled surfaces the re-read
      runs through
      the query (`submit_form`/`invoke` contexts may carry the current
      `/query` map under `"query"`; missing or invalid state falls back to
      the query's defaults) and a `/query` state message is included;
    * on validation errors: `/errors/<field>` per failing field and an
      `/ui/feedback` error;
    * on `Ash.Error.Forbidden`: only an `/ui/feedback` "not authorized" error
      (no field errors, to avoid leaking policy details).

  On v1.0 surfaces the outcome is additionally the structured `/ui/response`
  object and the `actionResponse` handshake (see `AshA2ui.Encoder.V1_0`);
  `/ui/feedback` carries the same message.

  Values are serialized JSON-safe (dates/datetimes to ISO 8601, decimals to
  strings, atoms to strings).
  """

  import Ash.Expr

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Bulk
  alias AshA2ui.Conditions
  alias AshA2ui.ContextRunner
  alias AshA2ui.Csv
  alias AshA2ui.Encoder.V0_9_1
  alias AshA2ui.Encoder.V1_0
  alias AshA2ui.Experience
  alias AshA2ui.QueryRunner
  alias AshA2ui.ResolvedView

  @version "v0.9.1"

  @doc """
  Handles an A2UI client `action` envelope for the surface declared on
  `resource_or_ui_module` (an `Ash.Resource` using the `AshA2ui` extension,
  or an `AshA2ui.Standalone` UI module).

  Returns `{:ok, messages}` with follow-up server->client messages or
  `{:error, messages}` carrying error information on the reserved
  `/errors/<field>` and `/ui/feedback` data-model paths. See the moduledoc for
  the accepted message shapes and emitted messages.

  ## Options

    * `:actor` — the actor for the Ash action invocation (and the refresh
      read).
    * `:tenant` — the tenant for the Ash action invocation.
    * `:authorize?` — whether to authorize the Ash calls. Defaults to `true`.
  """
  @spec handle(module | Spark.Dsl.t(), action_message :: map, opts :: keyword) ::
          {:ok, [map]} | {:error, [map]}
  def handle(resource_or_ui_module, action_message, opts \\ []) do
    view = ResolvedView.resolve(resource_or_ui_module, opts)
    ash_opts = ash_opts(view, opts)

    case parse(action_message) do
      {:ok, name, context, action_id} ->
        case AshA2ui.Sections.expand(view, ash_opts) do
          {:ok, view} ->
            env = %{
              view: view,
              ash_opts: ash_opts,
              refresh: refresh_params(view, context),
              selected: AshA2ui.ContextRunner.selected(view, Map.get(context, "contexts"))
            }

            name
            |> dispatch(context, env)
            |> put_feedback(view)
            |> attach_action_response(view, action_id)

          {:error, error} ->
            {:error, error_messages(view, error)}
            |> put_feedback(view)
            |> attach_action_response(view, action_id)
        end

      {:error, action_id} ->
        {:error, [status(view, "Malformed action message: expected an A2UI action envelope.")]}
        |> put_feedback(view)
        |> attach_action_response(view, action_id)
    end
  end

  # Every outcome reaches the typed /ui/feedback — the path the status Text
  # and the admin statusBanner bind (and the admin catalog's busy buttons
  # settle on). Failed actions get an error whatever the rejection path: on
  # v0.9.1 status/3 already writes it; on v1.0 the outcome lives in the
  # structured /ui/response object (the actionResponse contract), and this
  # mirrors its message. A v1.0 success that wrote only an "ok" /ui/response
  # with a message (report, export) is mirrored as a success the same way.
  defp put_feedback({tag, messages} = result, view) do
    cond do
      Enum.any?(messages, &match?(%{"updateDataModel" => %{"path" => "/ui/feedback"}}, &1)) ->
        result

      tag == :error ->
        feedback = Experience.feedback("error", feedback_message(messages))
        {:error, messages ++ [update_data_model(view, "/ui/feedback", feedback)]}

      true ->
        case find_response_write(messages) do
          %{"status" => "ok", "message" => message} when is_binary(message) and message != "" ->
            feedback = Experience.feedback("success", message)
            {:ok, messages ++ [update_data_model(view, "/ui/feedback", feedback)]}

          _no_outcome ->
            result
        end
    end
  end

  # --- v1.0 actionResponse ----------------------------------------------------

  # On a v1.0 surface, an action that carried an `actionId` (the client set
  # `wantResponse: true` — every action event the v1.0 encoder emits does)
  # gets a synchronous `actionResponse` message prepended to the follow-ups:
  # `{"value": <the /ui/response object>}` on success, `{"error": {code,
  # message}}` on failure. The response mirrors the reserved `/ui/response`
  # data-model write when the batch contains one (see the moduledoc), so
  # programmatic consumers get the exact per-action result without scraping
  # the data model. v0.9.1 surfaces (and v1.0 actions without an actionId)
  # are byte-identical to before.
  defp attach_action_response({tag, messages}, %{spec_version: :v1_0}, action_id)
       when is_binary(action_id) and action_id != "" do
    response =
      case {tag, find_response_write(messages)} do
        {:ok, nil} ->
          %{"value" => %{"status" => "ok", "message" => ""}}

        {:ok, response} ->
          %{"value" => response}

        {:error, %{"code" => code, "message" => message}} ->
          %{"error" => %{"code" => code, "message" => message}}

        {:error, _no_structured_write} ->
          %{"error" => %{"code" => "ACTION_FAILED", "message" => "The action failed."}}
      end

    message = %{"version" => "v1.0", "actionId" => action_id, "actionResponse" => response}

    {tag, [message | messages]}
  end

  defp attach_action_response(result, _view, _action_id), do: result

  defp find_response_write(messages) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => "/ui/response", "value" => value}} -> value
      _other -> nil
    end)
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
      {:error, _reason} -> QueryRunner.default_params(table.query)
    end
  end

  # Parses the envelope into {:ok, name, context, action_id} (action_id is
  # the v1.0 per-call response correlation id, nil when absent) or
  # {:error, action_id} for malformed messages — the id is still extracted
  # best-effort so a v1.0 client's pending action can be answered with an
  # error response instead of hanging.
  defp parse(%{"action" => %{"name" => name} = action}) when is_binary(name),
    do: {:ok, name, Map.get(action, "context") || %{}, action_id(action)}

  defp parse(%{"name" => name} = action) when is_binary(name),
    do: {:ok, name, Map.get(action, "context") || %{}, action_id(action)}

  defp parse(%{"action" => %{} = action}), do: {:error, action_id(action)}
  defp parse(%{} = action), do: {:error, action_id(action)}
  defp parse(_action_message), do: {:error, nil}

  defp action_id(action) do
    case Map.get(action, "actionId") do
      id when is_binary(id) -> id
      _absent_or_invalid -> nil
    end
  end

  defp ash_opts(view, opts) do
    [
      domain: ResourceInfo.domain(view.resource),
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    ]
  end

  # --- dispatch --------------------------------------------------------------

  defp dispatch("submit_form", context, env) do
    values = Map.get(context, "values") || %{}
    env = Map.put(env, :submitted, values)

    case Map.get(context, "recordId") do
      nil -> create(env, values)
      record_id -> update(env, record_id, values)
    end
  end

  defp dispatch("invoke", context, env), do: invoke_dispatch(context, env)

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

  defp dispatch("option_search", context, %{view: view, ash_opts: ash_opts}) do
    name = Map.get(context, "field")
    search = Map.get(context, "search") || ""
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

  defp dispatch("option_select", context, %{view: view, ash_opts: ash_opts}) do
    name = Map.get(context, "field")
    value = unwrap_picked(Map.get(context, "value"))

    select =
      is_binary(name) &&
        Enum.find_value(view.selects, fn {field, select} ->
          to_string(field) == name && {field, select}
        end)

    cond do
      not is_binary(name) ->
        {:error, [status(view, ~s(Malformed option_select action: context is missing "field".))]}

      select in [nil, false] or match?({_f, %{search_fields: []}}, select) ->
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
        {field, select_config} = select
        selected_option_messages(view, field, select_config, value, ash_opts)
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

  defp dispatch(name, _context, %{view: view}) do
    unknown_action(view, name)
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
  # AshA2ui.Encoder.V0_9_1): accepted only for a to-one link field of this
  # view whose LinkResolver answer, for this actor, is the requested
  # surface — compared as strings, nothing from the client becomes an
  # atom. No follow-ups: navigating is the transport's job
  # (AshA2ui.LiveRenderer routes an accepted open_surface to its
  # "a2ui:open_surface" handling). A row without a link for the field binds
  # no surface: acknowledged, nothing to open.
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
    {:error, [status(view, "Unknown action #{inspect(name)}.")]}
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
  defp selected_option_messages(view, field, select_config, value, ash_opts) do
    case fetch_option(select_config, value, ash_opts) do
      {:ok, record} ->
        entry = AshA2ui.Info.option_entry(record, select_config)

        {:ok,
         [
           update_data_model(view, "/form/#{field}", entry["value"]),
           update_data_model(view, "/select/#{field}", %{
             "search" => "",
             "label" => entry["label"]
           })
         ]}

      :not_found ->
        {:error, [status(view, "Option #{inspect(value)} was not found.")]}

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
  defp search_options(source, search, ash_opts) do
    query =
      source.destination
      |> Ash.Query.for_read(
        ResourceInfo.primary_action!(source.destination, :read).name,
        %{},
        destination_opts(source.destination, ash_opts)
      )
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
  # a value the actor cannot read cannot be selected).
  defp fetch_option(source, value, ash_opts) do
    query =
      source.destination
      |> Ash.Query.for_read(
        ResourceInfo.primary_action!(source.destination, :read).name,
        %{},
        destination_opts(source.destination, ash_opts)
      )
      |> Ash.Query.filter(^ref(source.option_value) == ^value)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [record]} -> {:ok, record}
      {:ok, []} -> :not_found
      {:error, error} -> {:error, error}
    end
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
            {:error, [status(view, "Option #{inspect(value)} was not found.")]}

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
      :not_found -> {:error, [status(view, "Option #{inspect(value)} was not found.")]}
      {:error, error} -> {:error, error_messages(view, error)}
    end
  end

  # require_context unmet: an honest empty result without touching Ash.
  defp require_unmet_messages(view, table, params) do
    state = QueryRunner.state(table.query, params, 0, false)

    records_messages(view, table, []) ++ query_state_messages(view, table, state, [])
  end

  defp run_scoped_query(view, table, params, scope, ash_opts) do
    case QueryRunner.run(table, params, ash_opts, scope) do
      {:ok, records, query_state} ->
        rows = rows(view, table, records, ash_opts)

        {:ok,
         records_messages(view, table, rows) ++
           query_state_messages(view, table, query_state, rows)}

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
    view.details
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
        loads = details |> Enum.flat_map(& &1.loads) |> Enum.uniq()
        fields = details |> Enum.flat_map(& &1.fields) |> Enum.uniq()

        case ContextRunner.fetch_selected(view, context, value, selected, ash_opts, loads) do
          {:ok, record} -> {:ok, linked_record_values(view, record, fields, ash_opts)}
          # The selection was just validated; a raced-away record renders empty.
          :not_found -> {:ok, %{}}
          {:error, error} -> {:error, error}
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
  end

  # --- submit_form -----------------------------------------------------------

  defp create(%{view: view} = env, values) do
    env = Map.put(env, :invoked, form_action(view, nil))
    result = with {:ok, changeset} <- form_changeset(env, nil, values), do: Ash.create(changeset)
    after_write(result, env, "Created successfully.")
  end

  defp update(%{view: view} = env, record_id, values) do
    env = Map.put(env, :invoked, form_action(view, record_id))

    result =
      with {:ok, changeset} <- form_changeset(env, record_id, values), do: Ash.update(changeset)

    after_write(result, env, "Updated successfully.")
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

  # --- invoke ----------------------------------------------------------------

  defp invoke(action_name, record_id, values, %{view: view} = env) do
    setting = Map.get(view.actions, action_name)
    env = env |> Map.put(:invoked, action_name) |> Map.put(:setting, setting)

    case enforce_visibility(view, setting, record_id, env.ash_opts) do
      :ok ->
        case setting do
          %{via: {module, function, extra_args}} when not is_nil(module) ->
            invoke_via(module, function, extra_args, record_id, env)

          _direct ->
            params = prompt_params(view, setting, action_name, values)
            dispatch_by_action_type(view, action_name, record_id, params, env)
        end

      {:error, messages} ->
        {:error, messages}
    end
  end

  # The direct path runs the mapped Ash action through run_direct/6 (shared
  # with bulk runs), then renders writes through after_write and generic
  # results through generic_result.
  defp dispatch_by_action_type(view, action_name, record_id, params, %{ash_opts: ash_opts} = env) do
    fetch = fn -> fetch_record(view, record_id, ash_opts) end
    completed = "Action #{inspect(to_string(action_name))} completed."

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

  defp via_result(:ok, %{invoked: action_name} = env),
    do: after_write(:ok, env, "Action #{inspect(to_string(action_name))} completed.")

  defp via_result({:ok, _result}, %{invoked: action_name} = env),
    do: after_write(:ok, env, "Action #{inspect(to_string(action_name))} completed.")

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
          {:error,
           [status(view, "Action #{inspect(to_string(name))} is not available for this record.")]}
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
    loads = Conditions.condition_loads(view.resource, setting.visible_when)

    case fetch_record(view, record_id, ash_opts, loads) do
      {:ok, record} ->
        if Conditions.visible?(view.resource, setting.visible_when, record) do
          {:ok, prompt_prefill_messages(view, setting, record)}
        else
          {:error,
           [
             status(
               view,
               "Action #{inspect(to_string(setting.name))} is not available for this record."
             )
           ]}
        end

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  defp prompt_prefill_messages(view, setting, record) do
    prefill =
      Map.new(setting.prompt_fields, fn field ->
        {Atom.to_string(field), prefill_value(view.resource, record, field)}
      end)

    [
      update_data_model(view, "/prompt/values/#{setting.name}", prefill),
      update_data_model(view, "/errors", %{})
    ]
  end

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

  defp generic_result({:ok, result}, %{view: %{spec_version: :v1_0}} = env, status_text)
       when is_map(result) and not is_struct(result) do
    success(env, status_text, %{
      "result" => json_map(result),
      "resultText" => action_result_text(result)
    })
  end

  defp generic_result({:ok, result}, %{view: view} = env, status_text)
       when is_map(result) and not is_struct(result) do
    extra = [
      update_data_model(view, "/ui/action_result", json_map(result)),
      update_data_model(view, "/ui/action_result_text", action_result_text(result))
    ]

    success(env, status_text, extra)
  end

  defp generic_result({:error, error}, %{view: view}, _status_text) do
    {:error, error_messages(view, error)}
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
         {:ok, ids} <- Bulk.selection(table, context) do
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
    case field_errors(error) do
      [] ->
        view |> error_messages(error) |> feedback_message()

      fields ->
        Enum.map_join(fields, "; ", fn {segments, text} ->
          Enum.map_join(segments, ".", &to_string/1) <> ": " <> text
        end)
    end
  end

  # The run's follow-ups: the /bulk/<table>/result write, then — when at
  # least one record was written — the standard success follow-ups
  # (refreshes honoring `refreshes`, and typed feedback that is
  # "warning" on partial success); otherwise an error status and no refresh.
  defp bulk_messages(table, action_name, selected, result, %{view: view} = env) do
    text = Bulk.status_text(action_name, selected, result)
    result_write = update_data_model(view, Bulk.result_path(table), result)

    if result["ok"] == 0 do
      {:error, [result_write, status(view, text, "ACTION_FAILED")]}
    else
      env = Map.put(env, :feedback_kind, Bulk.feedback_kind(selected, result))
      extra = if view.spec_version == :v1_0, do: %{"result" => result}, else: []

      case success(env, text, extra) do
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

    case Bulk.capped_selection_text(table, count, selected) do
      nil -> []
      text -> notice(view, text)
    end
  end

  # An informational outcome on an otherwise successful action: a typed
  # "warning" /ui/feedback (plus, on v1.0, an "ok" /ui/response carrying the
  # text — the action succeeded, so its actionResponse must not read error).
  defp notice(%{spec_version: :v1_0} = view, text),
    do: [
      update_data_model(view, "/ui/response", %{
        "status" => "ok",
        "message" => text,
        "result" => %{},
        "resultText" => ""
      }),
      update_data_model(view, "/ui/feedback", Experience.feedback("warning", text))
    ]

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

  defp report_status(%{spec_version: :v1_0} = view, count) do
    update_data_model(view, "/ui/response", %{
      "status" => "ok",
      "message" => report_status_text(count),
      "result" => %{"count" => count},
      "resultText" => ""
    })
  end

  defp report_status(view, count) do
    update_data_model(
      view,
      "/ui/feedback",
      Experience.feedback("success", report_status_text(count))
    )
  end

  defp report_status_text(1), do: "Report complete: 1 row."
  defp report_status_text(count), do: "Report complete: #{count} rows."

  # --- export (CSV file export, v1.0-only — see AshA2ui.Export) ----------------

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
      [] -> {:error, [status(view, "Select at least one column to export.")]}
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
        case read_export_table(table, scope, env) do
          # Raw values, not the table's display rows: a CSV export carries
          # stored enum values (as report exports do), not their labels.
          {:ok, records} ->
            {:ok, Enum.map(records, &record_values(view, &1, table_fields(table)))}

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
      (env.refresh[table.name] || QueryRunner.default_params(table.query))
      |> Map.merge(%{page: 1, page_size: table.export.limit})

    case QueryRunner.run(table, params, env.ash_opts, scope) do
      {:ok, records, _query_state} -> {:ok, records}
      {:error, error} -> {:error, error}
    end
  end

  # The delivery: one `downloadFile` callFunction carrying the CSV as a
  # base64 data URL (the frozen wire contract — see AshA2ui.Export), plus
  # the structured success write (mirrored into the actionResponse).
  defp deliver_export(view, target, columns, row_maps) do
    headers = Enum.map(columns, &export_header(view, &1))
    cells = Enum.map(row_maps, fn row -> Enum.map(columns, &Map.get(row, to_string(&1))) end)
    csv = Csv.encode(headers, cells)
    filename = target.export.filename

    call =
      V1_0.call_function("downloadFile", %{
        "filename" => filename,
        "mimeType" => "text/csv",
        "dataUrl" => Csv.data_url(csv)
      })

    response =
      update_data_model(view, "/ui/response", %{
        "status" => "ok",
        "message" => "Exported #{filename} (#{length(cells)} rows).",
        "result" => %{"filename" => filename, "rows" => length(cells)},
        "resultText" => ""
      })

    {:ok, [call, response]}
  end

  defp export_header(view, column) do
    case view.fields[column] do
      %{label: label} when is_binary(label) -> label
      _undeclared -> humanize(to_string(column))
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
        success(env, "Updated #{humanize(to_string(field))}.")

      {:error, error} ->
        {:error,
         error_messages(view, error) ++
           cell_error_mirrors(view, table, field, record_id, value, error, env)}
    end
  end

  defp cell_error_mirrors(view, table, field, record_id, value, error, env) do
    text =
      Enum.find_value(field_errors(error), fn
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
    params = env.refresh[table.name] || QueryRunner.default_params(table.query)

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
        Enum.filter(field_errors(%{errors: changeset.errors}), fn {[field | _rest], _text} ->
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
        [status(view, error_status(field_messages, nil), "VALIDATION_FAILED")]

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
      fields = for {[field | _rest], _text} <- field_errors(error), do: field

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
    messages = error_messages(view, error) ++ nested_error_mirrors(env, error)
    {:error, messages ++ wizard_submit_failure(env, error)}
  end

  # A success re-reads and re-emits every refresh-target table (each table's
  # records path, plus its query state when a query is attached — run
  # through the carried-or-default query params, see refresh_params/2),
  # then the standard /form, /errors and /ui writes.
  #
  # Targets default to *every* table; an `action` entity
  # (`action :approve do refreshes [:new_items] end`) limits the refresh to
  # the named table components. /ui/action_result and /ui/action_result_text
  # are cleared on every successful action before any `extra` writes, so a
  # stale result never outlives the action that produced it (a map-returning
  # generic action clears and then sets them in the same batch).
  defp success(env, status_text, extra \\ [])

  # v1.0 success: the status trio collapses into one structured
  # `/ui/response` write ({"status": "ok", "message": ..., "result": ...,
  # "resultText": ...}); `extra` is the response-object override a
  # map-returning generic action merges in (a map instead of a message
  # list — see generic_result/3). Everything else (refreshes, /form and
  # /errors clears, /select and /prompt resets) is identical to v0.9.1.
  defp success(%{view: %{spec_version: :v1_0} = view} = env, status_text, extra) do
    response =
      %{"status" => "ok", "message" => status_text, "result" => %{}, "resultText" => ""}
      |> Map.merge((is_map(extra) && extra) || %{})

    case refresh_messages(env) do
      {:ok, refresh} ->
        {:ok,
         refresh ++
           [
             update_data_model(view, "/form", ResolvedView.initial_form(view)),
             update_data_model(view, "/errors", %{}),
             update_data_model(view, "/ui/response", response)
           ] ++
           select_clear(view) ++
           prompt_clear(env) ++
           task_success(env, status_text) ++
           success_feedback(env, status_text) ++
           wizard_success_reset(env)}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  defp success(%{view: view} = env, status_text, extra) do
    case refresh_messages(env) do
      {:ok, refresh} ->
        {:ok,
         refresh ++
           [
             update_data_model(view, "/form", ResolvedView.initial_form(view)),
             update_data_model(view, "/errors", %{}),
             update_data_model(view, "/ui/action_result", %{}),
             update_data_model(view, "/ui/action_result_text", "")
           ] ++
           select_clear(view) ++
           prompt_clear(env) ++
           extra ++
           task_success(env, status_text) ++
           success_feedback(env, status_text) ++
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

  # Typed feedback for EVERY successful outcome, invoke and submit alike:
  # the /ui/feedback success value is what the status Text and the admin
  # statusBanner bind. A bulk run passes `:feedback_kind` ("warning" on
  # partial success). Failures get theirs from status/3 (v0.9.1) or
  # put_feedback/2 (v1.0).
  defp success_feedback(%{view: view} = env, status_text) do
    kind = Map.get(env, :feedback_kind, "success")
    [update_data_model(view, "/ui/feedback", Experience.feedback(kind, status_text))]
  end

  # The human-readable text of the batch's outcome write — the /ui/feedback
  # value (v0.9.1) or the /ui/response object (v1.0).
  defp feedback_message(messages) do
    Enum.find_value(messages, "", fn
      %{"updateDataModel" => %{"path" => "/ui/feedback", "value" => %{"message" => message}}} ->
        message

      %{"updateDataModel" => %{"path" => "/ui/response", "value" => %{"message" => message}}} ->
        message

      _other ->
        nil
    end)
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
  defp prompt_clear(%{view: view, setting: %{prompt_fields: [_ | _], name: name}}),
    do: [update_data_model(view, "/prompt/values/#{name}", %{})]

  defp prompt_clear(_env), do: []

  defp refresh_messages(%{view: view, ash_opts: ash_opts, refresh: refresh} = env) do
    view
    |> refresh_targets(env[:invoked])
    |> Enum.reduce_while({:ok, []}, fn table, {:ok, acc} ->
      case table_refresh(view, table, refresh[table.name], ash_opts, env.selected) do
        {:ok, messages} -> {:cont, {:ok, acc ++ messages}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
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
      QueryRunner.state(table.query, params || QueryRunner.default_params(table.query), 0, false)

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
    params = params || QueryRunner.default_params(table.query)

    case QueryRunner.run(table, params, ash_opts, scope) do
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
        |> Experience.with_pagination_sentinels(length(rows))
        |> Experience.with_admin_pagination_booleans(length(rows))
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
    Enum.map(records, &V0_9_1.serialize_row(view, table, &1, links))
  end

  # Human-readable, selectable text for a map-returning generic action:
  # one "Humanized key: value" line per key, sorted by key.
  defp action_result_text(result) do
    result
    |> Enum.map(fn {key, value} -> {to_string(key), json_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} ->
      "#{humanize(key)}: #{display_value(value)}"
    end)
  end

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: Jason.encode!(value)

  defp humanize(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

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

  defp error_messages(view, %Ash.Error.Forbidden{}) do
    [status(view, "You are not authorized to perform this action.", "UNAUTHORIZED")]
  end

  defp error_messages(view, error) do
    field_messages =
      for {segments, text} <- field_errors(error) do
        update_data_model(view, "/errors/" <> Enum.map_join(segments, "/", &to_string/1), text)
      end

    code = if field_messages == [], do: "ACTION_FAILED", else: "VALIDATION_FAILED"

    field_messages ++ [status(view, error_status(field_messages, error), code)]
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
      |> field_errors()
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

  defp error_status([], error) when is_exception(error),
    do: "Request failed: " <> first_line(Exception.message(error))

  defp error_status([], error), do: "Request failed: " <> inspect(error)

  defp error_status(_field_messages, _error),
    do: "Validation failed. Please review the field errors."

  # Walks the error-class `errors` list (as AshPhoenix.Form does) collecting
  # `%{field: f}` / `%{fields: [..]}` sub-errors, interpolating their `vars`
  # into the message text. Each entry is `{segments, text}` where `segments`
  # is the error's `path` (set by Ash for managed-relationship sub-errors,
  # e.g. `[:notes, 0]`) with the field appended — so a top-level error maps
  # to `/errors/<field>` exactly as before, and a nested-row error to
  # `/errors/<argument>/<index>/<field>`.
  defp field_errors(error) do
    error
    |> collect_field_errors()
    |> Enum.group_by(fn {segments, _text} -> segments end, fn {_segments, text} -> text end)
    |> Enum.map(fn {segments, texts} -> {segments, Enum.join(Enum.uniq(texts), "; ")} end)
  end

  defp collect_field_errors(%{errors: errors}) when is_list(errors) do
    Enum.flat_map(errors, &collect_field_errors/1)
  end

  defp collect_field_errors(%{field: field} = error) when not is_nil(field) do
    [{error_path(error) ++ [field], error_text(error)}]
  end

  defp collect_field_errors(%{fields: fields} = error) when is_list(fields) and fields != [] do
    Enum.map(fields, &{error_path(error) ++ [&1], error_text(error)})
  end

  defp collect_field_errors(_error), do: []

  defp error_path(error) do
    case Map.get(error, :path) do
      path when is_list(path) -> path
      _no_path -> []
    end
  end

  defp error_text(%{message: message} = error) when is_binary(message) do
    interpolate(message, Map.get(error, :vars))
  end

  # Splode prepends a "Bread Crumbs:" preamble to Exception.message/1; the
  # human-readable message is the last non-empty line.
  defp error_text(error) when is_exception(error), do: last_line(Exception.message(error))
  defp error_text(error), do: inspect(error)

  defp interpolate(message, vars) do
    Enum.reduce(vars_list(vars), message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", var_string(value))
    end)
  end

  defp vars_list(vars) when is_map(vars), do: Map.to_list(vars)
  defp vars_list(vars) when is_list(vars), do: vars
  defp vars_list(_vars), do: []

  defp var_string(value) when is_binary(value), do: value
  defp var_string(value), do: inspect(value)

  defp first_line(message) do
    message |> String.split("\n", parts: 2) |> hd() |> String.trim()
  end

  defp last_line(message) do
    message
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
    |> Kernel.||("")
  end

  # --- message + value construction ------------------------------------------

  # An error/rejection status: the typed `/ui/feedback` error (v0.9.1 — the
  # path the status Text and the admin statusBanner bind), or (v1.0) the
  # structured `/ui/response` object whose `code` also drives the
  # actionResponse error (see attach_action_response/3; put_feedback/2
  # mirrors it into /ui/feedback). Dispatch rejections default to
  # "INVALID_ACTION"; error_messages/2 passes the mapped code.
  defp status(view, text, code \\ "INVALID_ACTION")

  defp status(%{spec_version: :v1_0} = view, text, code) do
    update_data_model(
      view,
      "/ui/response",
      %{
        "status" => "error",
        "code" => code,
        "message" => text,
        "result" => %{},
        "resultText" => ""
      }
    )
  end

  defp status(view, text, _code),
    do: update_data_model(view, "/ui/feedback", Experience.feedback("error", text))

  defp update_data_model(view, path, value) do
    %{
      "version" => version_string(view),
      "updateDataModel" => %{
        "surfaceId" => view.surface_id,
        "path" => path,
        "value" => value
      }
    }
  end

  defp version_string(%{spec_version: :v1_0}), do: "v1.0"
  defp version_string(_view), do: @version

  defp record_values(view, record, fields) do
    fields
    |> Map.new(fn field -> {Atom.to_string(field), field_value(view, record, field)} end)
    |> Map.put("id", json_value(Map.get(record, :id)))
  end

  # `source` columns read through the loaded relationship path (nil-safe: a
  # nil or unloaded relationship serializes to ""); plain fields read the
  # record key directly.
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

  # record_values/3 plus the reserved "_links" of the linked fields (detail
  # and view-panel records; table rows merge theirs in rows/4).
  defp linked_record_values(view, record, fields, ash_opts) do
    row = record_values(view, record, fields)

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
end
