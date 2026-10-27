# Records the sortable-header probe fixture (synthetic data only) under the
# admin catalog:
#
#     MIX_ENV=test mix run priv/js/probe/record_sort.exs
#
# PagedNotesUI sorts by title (default asc); the links probe's `sort` case
# replays it.

alias AshA2ui.Test.Links.{Note, PagedNotesUI}

Application.put_env(:ash_a2ui, :catalog, :admin_v1)

for title <- ["Kickoff", "Retro", "Planning"],
    do: Ash.create!(Note, %{title: title, amount: 1}, authorize?: false)

File.write!(
  "priv/js/probe/fixtures/sort_payload.json",
  Jason.encode!(%{messages: AshA2ui.Info.build_surface(PagedNotesUI)})
)

IO.puts("recorded")
