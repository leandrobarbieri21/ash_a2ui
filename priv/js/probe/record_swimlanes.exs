# Records the board-swimlanes probe fixture (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_swimlanes.exs
#
# (run against a fresh test build — the fixture resource lives in private
# ETS, so every record is made in this one process). The swimlaned
# AshA2ui.Test.SwimlaneBoardUI (stages open/claimed/completed, swimlanes
# very_high "Critical" (danger) and low (success)), driven by
# priv/js/probe/swimlanes_probe.mjs; swimlanes_admin is the same board on an
# admin_v1 surface.

alias AshA2ui.Test.{BoardTask, SwimlaneBoardUI}

Application.delete_env(:ash_a2ui, :catalog)

for {name, status, severity} <- [
      {"Chest pain, short of breath", :open, :very_high},
      {"Allergic reaction after the second dose of the new prescription", :claimed, :very_high},
      {"Sprained ankle", :open, :low},
      {"Repeat prescription", :completed, :low},
      {"Routine check-up", :open, :low},
      # A third open low-severity task: that cell (page_size 2) pages, so
      # its pager text sits on the band.
      {"Twisted wrist", :open, :low}
    ] do
  Ash.create!(BoardTask, %{name: name, status: status, severity: severity, priority: :high},
    authorize?: false
  )
end

out = "priv/js/probe/fixtures"

File.write!(
  Path.join(out, "swimlanes_payload.json"),
  Jason.encode!(%{messages: AshA2ui.Info.build_surface(SwimlaneBoardUI, authorize?: false)})
)

# The same board on an admin_v1 surface: the board falls back to the basic
# composition inside the admin entityPage.
Application.put_env(:ash_a2ui, :catalog, :admin_v1)

File.write!(
  Path.join(out, "swimlanes_admin_payload.json"),
  Jason.encode!(%{messages: AshA2ui.Info.build_surface(SwimlaneBoardUI, authorize?: false)})
)

Application.delete_env(:ash_a2ui, :catalog)

IO.puts("recorded")
