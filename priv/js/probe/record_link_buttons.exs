# Records the basic-catalog link-button fixtures (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_link_buttons.exs
#
# (run against a fresh test build — the link fixtures live in shared ETS).
# The basic composition with `link_buttons: true`, as `AshA2ui.LiveRenderer`
# builds it when it has an `:open_surface_url` template; the
# `link_buttons_select` reply fills the link-aware detail. Driven by
# priv/js/probe/link_buttons_probe.mjs.

alias AshA2ui.Test.Links.{Note, Participant, Person, NotesUI}

Application.delete_env(:ash_a2ui, :catalog)

ada = Ash.create!(Person, %{name: "Ada"}, authorize?: false)
bob = Ash.create!(Person, %{name: "Bob"}, authorize?: false)

kickoff =
  Ash.create!(
    Note,
    %{title: "Kickoff", person_id: ada.id, subject_id: bob.id, amount: 1200, status: :open},
    authorize?: false
  )

for p <- [ada, bob],
    do: Ash.create!(Participant, %{note_id: kickoff.id, person_id: p.id}, authorize?: false)

Ash.create!(Note, %{title: "Unlinked", amount: 7, status: :closed}, authorize?: false)

out = "priv/js/probe/fixtures"

write = fn name, messages ->
  File.write!(Path.join(out, name), Jason.encode!(%{messages: messages}))
end

write.("link_buttons_payload.json", AshA2ui.Info.build_surface(NotesUI, link_buttons: true))

{:ok, select} =
  AshA2ui.ActionHandler.handle(
    NotesUI,
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => "context_select",
        "surfaceId" => "notes",
        "sourceComponentId" => "data_grid",
        "timestamp" => "2026-10-17T00:00:00Z",
        "context" => %{"context" => "note", "value" => kickoff.id}
      }
    }
  )

write.("link_buttons_select_payload.json", select)
IO.puts("recorded")
