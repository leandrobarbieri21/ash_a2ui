# Records the manifest probe fixtures (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_manifest.exs
#
# Two surfaces — AshA2ui.Test.ManifestTask (two named tables, a prompt, a
# destroy, visible_when on one value and on a list) and AshA2ui.Test.Referral
# (one table, a visible_when that differs per row) — under both catalogs, and
# ManifestTask under the admin catalog through the pseudo-locale translator.
# Each case writes the surface payload and its AshA2ui.Manifest, which
# priv/js/probe/manifest_probe.mjs checks against the rendered page.

alias AshA2ui.Test.{ManifestTask, PseudoLocale, Referral}

for {title, status} <- [{"Write", :open}, {"Ship", :open}, {"Plan", :done}] do
  Ash.create!(ManifestTask, %{title: title, status: status}, authorize?: false)
end

for {code, status} <- [{"R-PEND", :pending}, {"R-APPR", :approved}, {"R-DECL", :declined}] do
  Ash.create!(Referral, %{code: code, status: status}, authorize?: false)
end

pseudo = [gettext_fn: {PseudoLocale, :translate}, locale: "pseudo"]

cases = [
  {"manifest_tasks_basic", ManifestTask, [catalog: :basic]},
  {"manifest_tasks_admin", ManifestTask, [catalog: :admin_v1]},
  {"manifest_tasks_admin_pseudo", ManifestTask, [catalog: :admin_v1] ++ pseudo},
  {"manifest_referrals_basic", Referral, [catalog: :basic]},
  {"manifest_referrals_admin", Referral, [catalog: :admin_v1]}
]

for {name, module, opts} <- cases do
  File.write!(
    "priv/js/probe/fixtures/#{name}_payload.json",
    Jason.encode!(%{
      messages: AshA2ui.Info.build_surface(module, [authorize?: false] ++ opts),
      manifest: AshA2ui.Manifest.for_surface(module, opts)
    })
  )
end

IO.puts("recorded")
