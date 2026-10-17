# Records the calendar probe fixtures (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_calendar.exs
#
# (run against a fresh test build — the fixtures live in private ETS, so
# every record and reply is made in this one process). The window is pinned
# to October 2026 through the carried query state, so the fixtures do not
# depend on the day they are recorded.

alias AshA2ui.ActionHandler
alias AshA2ui.Test.Calendar.{Event, MonthUI}

actor = %{team: "red"}

for {title, starts_on, ends_on, status} <- [
      {"Kickoff", ~D[2026-10-03], nil, :booked},
      {"Boiler service", ~D[2026-10-16], nil, :booked},
      {"Offsite", ~D[2026-10-16], ~D[2026-10-18], :confirmed},
      {"Roof inspection", ~D[2026-11-04], nil, :booked},
      {"Year-end walk", ~D[2026-12-09], nil, :cancelled}
    ] do
  Ash.create!(Event, %{title: title, starts_on: starts_on, ends_on: ends_on, status: status, team: "red"},
    authorize?: false
  )
end

# Another team's event on a marked day: never read for this actor.
Ash.create!(Event, %{title: "Blue team only", starts_on: ~D[2026-10-03], team: "blue"}, authorize?: false)

out = "priv/js/probe/fixtures"
write = fn name, messages -> File.write!(Path.join(out, name), Jason.encode!(%{messages: messages})) end
october = %{"window" => %{"anchor" => "2026-10-01", "selected" => ""}, "page" => 1}

envelope = fn name, context ->
  %{
    "version" => "v0.9.1",
    "action" => %{
      "name" => name,
      "surfaceId" => "calendar_month",
      "sourceComponentId" => "calendar",
      "timestamp" => "2026-10-16T00:00:00Z",
      "context" => Map.merge(%{"component" => "schedule", "query" => october}, context)
    }
  }
end

reply = fn context ->
  {_tag, messages} = ActionHandler.handle(MonthUI, envelope.("query", context), actor: actor)
  messages
end

for catalog <- [:admin_v1, :basic] do
  Application.put_env(:ash_a2ui, :catalog, catalog)
  prefix = if catalog == :admin_v1, do: "calendar_admin", else: "calendar_basic"

  write.("#{prefix}_payload.json", AshA2ui.Info.build_surface(MonthUI, actor: actor, query_state: october))
  write.("#{prefix}_pick_payload.json", reply.(%{"date" => "2026-10-16"}))
  write.("#{prefix}_november_payload.json", reply.(%{"anchor" => "2026-11-01"}))
  write.("#{prefix}_december_payload.json", reply.(%{"anchor" => "2026-12-01"}))
end

Application.delete_env(:ash_a2ui, :catalog)
IO.puts("calendar fixtures written to #{out}")
