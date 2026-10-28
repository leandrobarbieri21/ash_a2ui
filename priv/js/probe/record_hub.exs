# Records the hub filter-bar probe fixture (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_hub.exs
#
# AshA2ui.Test.HubUI under the admin catalog: multi-select and grouped
# pickers with counts and a hint, path filters with bound options, a search
# placeholder, bare controls, page sizes, column help, a detail line with
# help, a header sorted by another field, toned badges, widths, the more
# values list and the empty states (a second fixture, searched for nothing).
# Driven by priv/js/probe/hub_probe.mjs.

alias AshA2ui.Test.{HubContract, HubLine, HubRole}

Application.put_env(:ash_a2ui, :catalog, :admin_v1)

contracts = [
  {"Roofing", :active, ["Elm", "Oak"], "Roofs Inc", nil},
  {"Plumbing", :expiring_soon, ["Oak"], "Pipes Ltd", nil},
  {"HVAC", :renewal_scheduled, ["Pine"], "Air Co", "Renews unless cancelled 30 days ahead."},
  {"Windows", :expired, ["Elm"], "Glass Co", nil},
  {"Painting", :draft, ["Oak"], "Paint Co", nil}
]

for {name, status, properties, vendor, help} <- contracts do
  contract =
    Ash.create!(HubContract, %{name: name, status: status, status_help: help}, authorize?: false)

  for property <- properties,
      do: Ash.create!(HubLine, %{property: property, contract_id: contract.id}, authorize?: false)

  Ash.create!(HubRole, %{role: :vendor, party_name: vendor, contract_id: contract.id},
    authorize?: false
  )

  Ash.create!(HubRole, %{role: :pmc, party_name: "Acme PMC", contract_id: contract.id},
    authorize?: false
  )
end

File.write!(
  "priv/js/probe/fixtures/hub_admin_payload.json",
  Jason.encode!(%{messages: AshA2ui.Info.build_surface(AshA2ui.Test.HubUI, authorize?: false)})
)

# The same surface searched for nothing: the no-results empty state.
File.write!(
  "priv/js/probe/fixtures/hub_admin_no_results_payload.json",
  Jason.encode!(%{
    messages:
      AshA2ui.Info.build_surface(AshA2ui.Test.HubUI,
        authorize?: false,
        query_state: %{"search" => "zzz", "filters" => %{"status" => ["draft"]}}
      )
  })
)

IO.puts("recorded")
