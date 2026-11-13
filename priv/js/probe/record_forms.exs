# Records the picker and anatomy probe fixtures (synthetic, empty surfaces):
#
#     MIX_ENV=test mix run priv/js/probe/record_forms.exs
#
# Each `*_open_payload.json` is the start_create reply that opens the
# surface's create panel, which is what makes its form composites render.

alias AshA2ui.ActionHandler
alias AshA2ui.Test.{Paginated, Post, Promotion, TicketSearchUI}
alias AshA2ui.Test.Experience.EstateUser

out = "priv/js/probe/fixtures"
write = fn name, messages -> File.write!(Path.join(out, name), Jason.encode!(%{messages: messages})) end

open = fn ui, surface ->
  {:ok, messages} =
    ActionHandler.handle(
      ui,
      %{
        "version" => "1.0",
        "callAgentFunction" => %{
          "surfaceId" => surface,
          "functionCallId" => "probe-call",
          "callFunction" => %{
            "@call" => "ashAction",
            "catalogId" => AshA2ui.Encoder.ash_catalog_id(),
            "args" => %{
              "name" => "start_create",
              "sourceComponentId" => "create_button",
              "context" => %{
            }
          }
        }
        }
      },
      authorize?: false
    )

  messages
end

for {name, ui, surface} <- [
      {"post", Post, "posts"},
      {"ticket_search", TicketSearchUI, "tickets_search"},
      {"promotion", Promotion, "promotions"}
    ] do
  write.("#{name}_payload.json", AshA2ui.Info.build_surface(ui, authorize?: false))
  write.("#{name}_open_payload.json", open.(ui, surface))
end

write.("estate_user_payload.json", AshA2ui.Info.build_surface(EstateUser, authorize?: false))
write.("paginated_payload.json", AshA2ui.Info.build_surface(Paginated, authorize?: false))
IO.puts("recorded")
