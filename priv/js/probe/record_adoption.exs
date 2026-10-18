# Records the adoption probe fixtures (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_adoption.exs
#
# (run against a fresh test build — the fixtures live in private ETS, so
# every record and reply is made in this one process).

alias AshA2ui.ActionHandler
alias AshA2ui.Test.Adoption.{Clerk, Job, JobBoardUI, JobsUI, PromptBoardUI}

actor = %{id: "u-red", team: "red"}

Ash.create!(Clerk, %{name: "Rhea", team: "red"}, authorize?: false)
Ash.create!(Clerk, %{name: "Ravi", team: "red"}, authorize?: false)

open = Ash.create!(Job, %{title: "Open job", team: "red"}, authorize?: false)
_claimed = Ash.create!(Job, %{title: "Claimed job", team: "red", status: :claimed}, authorize?: false)

# Board cards with long, unbroken-ish titles: lanes must not size to them.
for {title, status} <- [
      {"Replace the rooftop condenser fan motor on building C before the heat wave", :open},
      {"Quarterly fire-panel inspection for every tower in the north portfolio", :open},
      {"Re-key the parking garage access readers after the tenant turnover", :claimed},
      {"Annual backflow preventer certification with the municipal water authority", :done}
    ] do
  Ash.create!(Job, %{title: title, team: "red", status: status}, authorize?: false)
end

out = "priv/js/probe/fixtures"
write = fn name, messages -> File.write!(Path.join(out, name), Jason.encode!(%{messages: messages})) end

envelope = fn surface, name, context ->
  %{
    "version" => "v0.9.1",
    "action" => %{
      "name" => name,
      "surfaceId" => surface,
      "sourceComponentId" => "data_grid",
      "timestamp" => "2026-10-16T00:00:00Z",
      "context" => context
    }
  }
end

reply = fn ui, surface, name, context ->
  {_tag, messages} = ActionHandler.handle(ui, envelope.(surface, name, context), actor: actor)
  messages
end

# A LiveRenderer PubSub refresh: the whole data model rewritten at "/"
# (resetting /ui/feedback), which is not an action's outcome.
refresh = fn ui -> [AshA2ui.Info.build_data_model(ui, actor: actor)] end

# A row that no longer exists: a non-field error (no /errors/<field>).
missing_id = Ash.UUID.generate()

# --- admin catalog: prompts, per-row visibility, the View panel ---------------
Application.put_env(:ash_a2ui, :catalog, :admin_v1)

write.("adoption_admin_payload.json", AshA2ui.Info.build_surface(JobsUI, actor: actor))
write.("adoption_admin_refresh_payload.json", refresh.(JobsUI))

write.(
  "adoption_admin_view_payload.json",
  reply.(JobsUI, "adoption_jobs", "view_record", %{"recordId" => open.id, "component" => "table"})
)

write.(
  "adoption_admin_cancel_payload.json",
  reply.(JobsUI, "adoption_jobs", "cancel_record_task", %{"component" => "table"})
)

write.(
  "adoption_admin_annotate_ok_payload.json",
  reply.(JobsUI, "adoption_jobs", "invoke", %{
    "action" => "annotate",
    "recordId" => open.id,
    "component" => "table",
    "values" => %{"note" => "Called the owner"}
  })
)

write.(
  "adoption_admin_annotate_error_payload.json",
  reply.(JobsUI, "adoption_jobs", "invoke", %{
    "action" => "annotate",
    "recordId" => open.id,
    "component" => "table",
    "values" => %{"note" => ""}
  })
)


# A board's prompt row actions (clinic-demo's Complete / Delegate): the
# dialog closes on a successful confirm and stays open on an error.
board_annotate = fn values, record_id ->
  reply.(PromptBoardUI, "adoption_prompt_board", "invoke", %{
    "action" => "annotate",
    "recordId" => record_id,
    "component" => "board_open",
    "values" => values
  })
end

write.("adoption_prompt_board_admin_payload.json", AshA2ui.Info.build_surface(PromptBoardUI, actor: actor))
write.("adoption_prompt_board_admin_ok_payload.json", board_annotate.(%{"note" => "Called the owner"}, open.id))
write.("adoption_prompt_board_admin_error_payload.json", board_annotate.(%{"note" => ""}, open.id))
write.("adoption_prompt_board_admin_missing_payload.json", board_annotate.(%{"note" => "x"}, missing_id))
write.("adoption_prompt_board_admin_refresh_payload.json", refresh.(PromptBoardUI))

# --- basic catalog: the board, prompt widgets --------------------------------
Application.put_env(:ash_a2ui, :catalog, :basic)

write.("adoption_board_payload.json", AshA2ui.Info.build_surface(JobBoardUI, actor: actor))
write.("adoption_basic_payload.json", AshA2ui.Info.build_surface(JobsUI, actor: actor))

write.("adoption_prompt_board_payload.json", AshA2ui.Info.build_surface(PromptBoardUI, actor: actor))
write.("adoption_prompt_board_ok_payload.json", board_annotate.(%{"note" => "Called the owner"}, open.id))
write.("adoption_prompt_board_error_payload.json", board_annotate.(%{"note" => ""}, open.id))
write.("adoption_prompt_board_missing_payload.json", board_annotate.(%{"note" => "x"}, missing_id))
write.("adoption_prompt_board_refresh_payload.json", refresh.(PromptBoardUI))

write.(
  "adoption_basic_annotate_ok_payload.json",
  reply.(JobsUI, "adoption_jobs", "invoke", %{
    "action" => "annotate",
    "recordId" => open.id,
    "component" => "table",
    "values" => %{"note" => "Called the owner"}
  })
)

write.("adoption_basic_annotate_refresh_payload.json", refresh.(JobsUI))

IO.puts("recorded")
