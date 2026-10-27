# Records the primary-action probe fixture (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_primary_action.exs
#
# AshA2ui.Test.Submission under the admin catalog: the row click drawn as a
# button per row, labelled and styled by the `next_step` calculation.
# Driven by priv/js/probe/primary_action_probe.mjs.

alias AshA2ui.Test.Submission

Application.put_env(:ash_a2ui, :catalog, :admin_v1)

for {title, state} <- [{"Draft one", :draft}, {"Sent one", :submitted}, {"Done one", :approved}] do
  Ash.create!(Submission, %{title: title, state: state}, authorize?: false)
end

File.write!(
  "priv/js/probe/fixtures/primary_action_admin_payload.json",
  Jason.encode!(%{messages: AshA2ui.Info.build_surface(Submission, authorize?: false)})
)

IO.puts("recorded")
