# Records the live-diagram probe fixtures (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_diagram.exs
#
# (run against a fresh test build — the fixtures live in private ETS, so
# every record and reply is made in this one process).

alias AshA2ui.Test.Diagram.{FlowUI, Visit}

actor = %{team: "red"}
Application.put_env(:ash_a2ui, :open_surface_url, "/visits/{recordId}")

ada = Ash.create!(Visit, %{patient: "Ada Lovelace", node: "triage", status: :waiting}, authorize?: false)
Ash.create!(Visit, %{patient: "Alan Turing", node: "triage", status: :active}, authorize?: false)
Ash.create!(Visit, %{patient: "Grace Hopper", node: "exam", status: :executing}, authorize?: false)
Ash.create!(Visit, %{patient: "Margaret Hamilton", node: "finish", status: :done}, authorize?: false)
# Another team's visit: never a marker for this actor.
Ash.create!(Visit, %{patient: "Blue Team", node: "start", team: "blue"}, authorize?: false)

out = "priv/js/probe/fixtures"
write = fn name, messages -> File.write!(Path.join(out, name), Jason.encode!(%{messages: messages})) end

Application.put_env(:ash_a2ui, :catalog, :admin_v1)
write.("diagram_admin_payload.json", AshA2ui.Info.build_surface(FlowUI, actor: actor))

Application.put_env(:ash_a2ui, :catalog, :basic)
write.("diagram_basic_payload.json", AshA2ui.Info.build_surface(FlowUI, actor: actor, link_buttons: true))

# The engine moves Ada to the exam: the /diagram/flow write a refresh pushes.
Ash.update!(ada, %{node: "exam", status: :failed}, authorize?: false)
write.("diagram_moved_payload.json", AshA2ui.Diagram.refresh_messages(FlowUI, actor: actor))

Application.delete_env(:ash_a2ui, :catalog)
Application.delete_env(:ash_a2ui, :open_surface_url)
IO.puts("diagram fixtures written to #{out}")
