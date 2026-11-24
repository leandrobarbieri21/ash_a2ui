defmodule AshA2ui.Shell.SearchTest do
  use ExUnit.Case, async: true

  alias AshA2ui.Shell.{Host, Search}
  alias AshA2ui.Test.Search.{Licence, Outage, Run}

  setup do
    holder = %{id: Ash.UUID.generate(), admin?: false}
    admin = %{id: Ash.UUID.generate(), admin?: true}

    licence =
      Ash.create!(Licence, %{clinic: "north", number: "LIC-1042", holder_id: holder.id},
        tenant: "north",
        authorize?: false
      )

    run = Ash.create!(Run, %{name: "renewal"}, authorize?: false)

    %{holder: holder, admin: admin, licence: licence, run: run}
  end

  defp entry(key, resource, fields) do
    %{key: key, resource: resource, fields: fields, path: &"/app/r/#{key}/#{&1}"}
  end

  defp entries do
    [entry(:licences, Licence, [:number, :id]), entry(:runs, Run, [:id])]
  end

  test "finds a record by its business reference, as the actor, in the tenant",
       %{holder: holder, licence: licence} do
    assert %{hits: [hit], failed: []} =
             Search.find("LIC-1042", [entry(:licences, Licence, [:number, :id])],
               actor: holder,
               tenant: "north"
             )

    assert hit.key == :licences
    assert hit.id == licence.id
    assert hit.field == :number
    assert hit.path == "/app/r/licences/#{licence.id}"
    assert hit.entry.resource == Licence
  end

  test "a reference is compared only with the fields it casts to",
       %{admin: admin, licence: licence, run: run} do
    # The licence number does not cast to a UUID, so the runs are never read.
    assert %{hits: [%{key: :licences}], failed: []} =
             Search.find("LIC-1042", entries(), actor: admin, tenant: "north")

    # An id matches the field it casts to, and says which one.
    assert %{hits: [%{key: :licences, field: :id}], failed: []} =
             Search.find(licence.id, entries(), actor: admin, tenant: "north")

    assert %{hits: [%{key: :runs, field: :id, id: id}], failed: []} =
             Search.find(run.id, [entry(:runs, Run, [:id])], actor: admin)

    assert id == run.id

    # A term that casts to nothing reads nothing.
    assert Search.find("not a number", [entry(:licences, Licence, [:renewals])],
             actor: admin,
             tenant: "north"
           ) == %{hits: [], failed: []}
  end

  test "a record the actor may not read is not found, and that is not a failure",
       %{run: run} do
    stranger = %{id: Ash.UUID.generate(), admin?: false}

    assert Search.find("LIC-1042", entries(), actor: stranger, tenant: "north") ==
             %{hits: [], failed: []}

    assert Search.find(run.id, [entry(:runs, Run, [:id])], actor: stranger) ==
             %{hits: [], failed: []}
  end

  test "another tenant's record is not found", %{admin: admin} do
    assert Search.find("LIC-1042", entries(), actor: admin, tenant: "south") ==
             %{hits: [], failed: []}
  end

  test "a blank term reads nothing", %{holder: holder} do
    for term <- ["", "   ", nil] do
      assert Search.find(term, entries(), actor: holder, tenant: "north") ==
               %{hits: [], failed: []}
    end
  end

  test "an entry that could not be searched is reported, not read as no match",
       %{holder: holder, licence: licence} do
    broken = entry(:licences, Licence, [:no_such_attribute])
    down = entry(:outage, Outage, [:number])

    assert %{hits: [], failed: [^broken, ^down]} =
             Search.find("LIC-1042", [broken, down], actor: holder, tenant: "north")

    # The others still answer beside it.
    assert %{hits: [%{id: id}], failed: [^down]} =
             Search.find("LIC-1042", [down, entry(:licences, Licence, [:number])],
               actor: holder,
               tenant: "north"
             )

    assert id == licence.id

    # A read the data layer refuses (no tenant) is a failure too.
    assert %{hits: [], failed: [%{key: :licences}]} =
             Search.find("LIC-1042", [entry(:licences, Licence, [:number])], actor: holder)
  end

  test "limit caps the records read per entry", %{admin: admin} do
    for _ <- 1..3 do
      Ash.create!(Licence, %{clinic: "north", number: "LIC-7", holder_id: admin.id},
        tenant: "north",
        authorize?: false
      )
    end

    found = fn opts ->
      Search.find("LIC-7", [entry(:licences, Licence, [:number])], opts).hits
    end

    assert length(found.(actor: admin, tenant: "north")) == 3
    assert length(found.(actor: admin, tenant: "north", limit: 2)) == 2
  end

  test "extra keys on an entry come back with the hit", %{holder: holder} do
    entry = Map.put(entry(:licences, Licence, [:number]), :surface, %{label: "Licences"})

    assert %{hits: [%{entry: %{surface: %{label: "Licences"}}}]} =
             Search.find("LIC-1042", [entry], actor: holder, tenant: "north")
  end

  test "searchable/1 is an optional host callback" do
    assert {:searchable, 1} in Host.behaviour_info(:optional_callbacks)
  end
end
