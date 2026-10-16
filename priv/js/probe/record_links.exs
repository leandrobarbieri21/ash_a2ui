# Records the links probe fixtures (synthetic data only) under the admin catalog:
#
#     MIX_ENV=test mix run priv/js/probe/record_links.exs
#
# (run against a fresh test build — the link fixtures live in shared ETS).

alias AshA2ui.Test.Links.{Note, Participant, Person, NotesUI, PagedNotesUI}

Application.put_env(:ash_a2ui, :catalog, :admin_v1)
Application.put_env(:ash_a2ui, :open_surface_url, "/app/r/{surface}/{recordId}")

ada = Ash.create!(Person, %{name: "Ada"}, authorize?: false)
bob = Ash.create!(Person, %{name: "Bob"}, authorize?: false)
hidden = Ash.create!(Person, %{name: "Hidden", visible: false}, authorize?: false)

kickoff =
  Ash.create!(Note, %{title: "Kickoff", person_id: ada.id, subject_id: bob.id, amount: 1200,
    status: :open, body: "- first point\n- second point\n- third point"}, authorize?: false)

for p <- [ada, bob, hidden], do: Ash.create!(Participant, %{note_id: kickoff.id, person_id: p.id}, authorize?: false)

Ash.create!(Note, %{title: "Retro", person_id: bob.id, amount: 7, status: :closed}, authorize?: false)
for i <- 1..5, do: Ash.create!(Note, %{title: "Zz #{i}", amount: i}, authorize?: false)

out = "priv/js/probe/fixtures"
write = fn name, messages -> File.write!(Path.join(out, name), Jason.encode!(%{messages: messages})) end

write.("links_payload.json", AshA2ui.Info.build_surface(NotesUI))

{:ok, select} =
  AshA2ui.ActionHandler.handle(NotesUI, %{
    "version" => "v0.9.1",
    "action" => %{"name" => "context_select", "surfaceId" => "notes", "sourceComponentId" => "data_grid",
      "timestamp" => "2026-10-12T00:00:00Z", "context" => %{"context" => "note", "value" => kickoff.id}}
  })

write.("links_select_payload.json", select)

# page 4 of 8 — the windowed pager shows 1 … 3 4 5 … 8
paged = AshA2ui.Info.build_surface(PagedNotesUI, query_state: %{"page" => 4})
write.("links_paged_payload.json", paged)
IO.puts("recorded")
