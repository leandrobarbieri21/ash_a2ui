defmodule AshA2ui.Test.L10nScenarios do
  @moduledoc false
  # The localization golden scenarios (ADR 0060): the initial build, a
  # refresh, option lists and action feedback, with the basic and the admin
  # catalog. Shared by the golden test and the
  # pseudo-locale test, which re-runs them with a translator.

  import AshA2ui.Test.BulkHelpers, only: [rows: 2, contexts: 1]

  alias AshA2ui.ActionHandler
  alias AshA2ui.Info
  alias AshA2ui.Test.BoardTask
  alias AshA2ui.Test.BoardTaskUI
  alias AshA2ui.Test.BulkHelpers
  alias AshA2ui.Test.BulkTasksUI
  alias AshA2ui.Test.EnumRecord
  alias AshA2ui.Test.Experience.Task
  alias AshA2ui.Test.HubContract
  alias AshA2ui.Test.HubUI
  alias AshA2ui.Test.Messages

  # The scenarios, each `{name, catalog, fun}` where `fun.(extra_opts)` returns the
  # messages. `extra_opts` is how the localization tests re-run the same
  # scenarios with a translator.
  def scenarios do
    for {catalog, catalog_tag} <- [basic: "basic", admin_v1: "admin"],
        {name, fun} <- scenario_funs() do
      {"#{name}_#{catalog_tag}", catalog, fun}
    end
  end

  defp scenario_funs do
    [
      {"bulk_build", &bulk_build(&1)},
      {"bulk_refresh", &bulk_refresh(&1)},
      {"bulk_options", &bulk_options(&1)},
      {"bulk_invoke", &bulk_invoke(&1)},
      {"bulk_invoke_one", &bulk_invoke(1, &1)},
      {"bulk_invoke_two", &bulk_invoke(2, &1)},
      {"bulk_select_page", &bulk_select_page(&1)},
      {"task_build", &task_build(&1)},
      {"task_actions", &task_actions(&1)},
      {"hub_build", &hub_build(&1)},
      {"hub_no_results", &hub_no_results(&1)},
      {"board_build", &board_build(&1)},
      {"enum_build", &enum_build(&1)}
    ]
  end

  # Runs one scenario under its catalog and returns the normalized JSON.
  def run({_name, catalog, fun}, extra_opts) do
    Application.put_env(:ash_a2ui, :catalog, catalog)

    try do
      {messages, substitutions} = fun.(extra_opts)
      normalize(messages, substitutions)
    after
      Application.delete_env(:ash_a2ui, :catalog)
    end
  end

  @scenario_names for catalog <- ~w(basic admin),
                      name <-
                        ~w(bulk_build bulk_refresh bulk_options bulk_invoke bulk_invoke_one
                           bulk_invoke_two bulk_select_page
                           task_build task_actions hub_build hub_no_results board_build
                           enum_build),
                      do: "#{name}_#{catalog}"

  def scenario_names, do: @scenario_names

  def scenario(name), do: Enum.find(scenarios(), &(elem(&1, 0) == name))

  # --- scenarios --------------------------------------------------------------

  defp bulk_seed do
    project = BulkHelpers.project!("Apollo")

    tasks =
      for {title, score} <- [{"alpha", 1}, {"bravo", -1}, {"charlie", 2}] do
        BulkHelpers.task!(title, %{project_id: project.id, score: score})
      end

    substitutions =
      [{project.id, "PROJECT_APOLLO"}] ++
        Enum.map(tasks, &{&1.id, "TASK_#{String.upcase(&1.title)}"})

    {project, tasks, substitutions}
  end

  defp bulk_opts(project, extra) do
    [actor: BulkHelpers.actor(), context_state: contexts(project)] ++ extra
  end

  defp bulk_build(extra) do
    {project, _tasks, subs} = bulk_seed()
    {Info.build_surface(BulkTasksUI, bulk_opts(project, extra)), subs}
  end

  defp bulk_refresh(extra) do
    {project, _tasks, subs} = bulk_seed()

    query_state = %{
      "search" => "a",
      "page" => 1,
      "sort" => %{"field" => "title", "dir" => "desc"}
    }

    opts = bulk_opts(project, [query_state: query_state] ++ extra)

    {[Info.build_data_model(BulkTasksUI, opts)], subs}
  end

  defp bulk_options(extra) do
    {project, _tasks, subs} = bulk_seed()

    {_outcome, messages} =
      ActionHandler.handle(
        BulkTasksUI,
        BulkHelpers.envelope("context_search", %{
          "context" => "project",
          "search" => "Apo",
          "contexts" => contexts(project)
        }),
        [actor: BulkHelpers.actor()] ++ extra
      )

    {messages, subs}
  end

  defp bulk_invoke(extra), do: bulk_invoke(3, extra)

  # Approves the first `count` tasks: the status line's counts of 1 and 2.
  defp bulk_invoke(count, extra) do
    {project, all_tasks, subs} = bulk_seed()
    tasks = Enum.take(all_tasks, count)

    {_outcome, messages} =
      ActionHandler.handle(
        BulkTasksUI,
        BulkHelpers.envelope("bulk_invoke", %{
          "action" => "approve",
          "component" => "table",
          "records" => rows(tasks, tasks),
          "contexts" => contexts(project)
        }),
        [actor: BulkHelpers.actor()] ++ extra
      )

    {messages, subs}
  end

  defp bulk_select_page(extra) do
    {project, tasks, subs} = bulk_seed()

    {_outcome, messages} =
      ActionHandler.handle(
        BulkTasksUI,
        BulkHelpers.envelope("bulk_select", %{
          "component" => "table",
          "selected" => true,
          "records" => rows(tasks, []),
          "contexts" => contexts(project)
        }),
        [actor: BulkHelpers.actor()] ++ extra
      )

    {messages, subs}
  end

  # Host display metadata of every kind on one query hub: placeholder,
  # empty states, group and choice labels, column help, a detail line and
  # row labels, over a record whose status is an enumerated value.
  defp hub_build(extra) do
    contract =
      Ash.create!(HubContract, %{name: "alpha", status: :expiring_soon}, authorize?: false)

    opts = [authorize?: false] ++ extra
    {Info.build_surface(HubUI, opts), [{contract.id, "CONTRACT_ALPHA"}]}
  end

  # The state a search with no matches shows: the no-results empty state and
  # its clear action.
  defp hub_no_results(extra) do
    query_state = %{"search" => "zzz", "page" => 1}
    opts = [authorize?: false, query_state: query_state] ++ extra
    {[Info.build_data_model(HubUI, opts)], []}
  end

  # A board whose lanes are an enumerated attribute's values, one heading
  # overridden, and a card whose badge is an enumerated value.
  defp board_build(extra) do
    card = Ash.create!(BoardTask, %{name: "card", status: :open, priority: :high})
    {Info.build_surface(BoardTaskUI, extra), [{card.id, "CARD"}]}
  end

  # An `Ash.Type.Enum` with explicit labels and one without, in the form
  # pickers and the cells.
  defp enum_build(extra) do
    record = Ash.create!(EnumRecord, %{name: "rec", severity: :very_high, stage: :in_progress})
    {Info.build_surface(EnumRecord, extra), [{record.id, "RECORD"}]}
  end

  defp task_seed do
    tasks = for name <- ["one", "two", "three"], do: Ash.create!(Task, %{name: name})
    {tasks, Enum.map(tasks, &{&1.id, "TASK_#{String.upcase(&1.name)}"})}
  end

  defp task_build(extra) do
    {_tasks, subs} = task_seed()
    {Info.build_surface(Task, extra), subs}
  end

  # Every task-panel transition and outcome a reader sees feedback or chrome
  # for: create, a failed create, view, edit, cancel, a query page, a
  # destroy, a malformed message and an unknown action.
  defp task_actions(extra) do
    {[one | _] = _tasks, subs} = task_seed()
    opts = extra

    envelopes = [
      {"start_create", %{}},
      {"submit_form", %{"values" => %{"name" => ""}}},
      {"submit_form", %{"values" => %{"name" => "four"}}},
      {"view_record", %{"recordId" => one.id}},
      {"start_edit", %{"recordId" => one.id}},
      {"submit_form", %{"values" => %{"name" => "uno"}, "recordId" => one.id}},
      {"cancel_record_task", %{}},
      {"query", %{"query" => %{"page" => 1}, "pageDelta" => 1}},
      {"invoke", %{"action" => "destroy", "recordId" => one.id}},
      {"invoke", %{"action" => "nope"}},
      {"bogus", %{}}
    ]

    messages =
      Enum.flat_map(envelopes, fn {name, context} ->
        {outcome, messages} = ActionHandler.handle(Task, envelope(name, context), opts)
        [%{"outcome" => to_string(outcome), "action" => name} | messages]
      end)

    created = Task |> Ash.read!() |> Enum.reject(&(&1.id in Enum.map(subs, fn {id, _} -> id end)))
    {messages, subs ++ Enum.map(created, &{&1.id, "TASK_CREATED"})}
  end

  defp envelope(name, context) do
    Messages.call(name, "experience_task", context, id: "call-#{name}")
  end

  # --- helpers -------------------------------------------------------------------

  defp normalize(messages, substitutions) do
    json = Jason.encode!(messages, pretty: true)

    substitutions
    |> Enum.flat_map(fn {id, tag} ->
      for separator <- ["-", "_", " "], do: {String.replace(id, "-", separator), tag}
    end)
    |> Enum.reduce(json, fn {id, tag}, acc -> String.replace(acc, id, tag) end)
  end
end
