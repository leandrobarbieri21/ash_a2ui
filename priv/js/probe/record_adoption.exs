# Records the adoption probe fixtures (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_adoption.exs
#
# (run against a fresh test build — the fixtures live in private ETS, so
# every record and reply is made in this one process).

alias AshA2ui.ActionHandler
alias AshA2ui.Test.Adoption.{Clerk, Job, JobBoardUI, JobsUI}

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

# --- admin catalog: prompts, per-row visibility, the View panel ---------------
Application.put_env(:ash_a2ui, :catalog, :admin_v1)

write.("adoption_admin_payload.json", AshA2ui.Info.build_surface(JobsUI, actor: actor))

write.(
  "adoption_admin_view_payload.json",
  reply.(JobsUI, "adoption_jobs", "view_record", %{"recordId" => open.id, "component" => "table"})
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

# --- basic catalog: the board, prompt widgets --------------------------------
Application.put_env(:ash_a2ui, :catalog, :basic)

write.("adoption_board_payload.json", AshA2ui.Info.build_surface(JobBoardUI, actor: actor))
write.("adoption_basic_payload.json", AshA2ui.Info.build_surface(JobsUI, actor: actor))

IO.puts("recorded")
