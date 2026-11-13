defmodule AshA2ui.SurfaceConformanceTest do
  @moduledoc """
  Builds every surface the test support declares, under the basic catalog,
  the admin catalog and the link-button options, and checks each
  `createSurface` against the rules a renderer enforces on the whole
  message:

    * it validates against `agent_to_renderer.json` with the catalogs the
      surface uses, so every component resolves to a catalog that declares
      it and every property is one that catalog allows;
    * its component ids are unique (a2ui_protocol.md, "The component
      object": the id identifies one component instance; the upstream
      `MessageProcessor` rejects a batch with a duplicate id).
  """

  use ExUnit.Case, async: true

  alias AshA2ui.Test.SchemaHelper

  @option_sets [[], [catalog: :admin_v1], [link_buttons: true, header: false]]

  # Every AshA2ui surface module with components the test support compiles:
  # resources using the extension and standalone UI modules.
  defp surface_modules do
    {:ok, modules} = :application.get_key(:ash_a2ui, :modules)

    Enum.filter(modules, fn module ->
      String.starts_with?(inspect(module), "AshA2ui.Test.") and
        Code.ensure_loaded?(module) and
        function_exported?(module, :spark_dsl_config, 0) and
        AshA2ui in Spark.extensions(module) and
        AshA2ui.Info.components(module) != []
    end)
  end

  defp surfaces do
    for module <- surface_modules(), opts <- @option_sets do
      [message] = AshA2ui.Info.build_surface(module, [authorize?: false] ++ opts)
      {"#{inspect(module)} #{inspect(opts)}", opts, message}
    end
  end

  test "the test support declares the surfaces this test walks" do
    assert length(surface_modules()) >= 80
  end

  test "every surface validates against the catalogs it uses" do
    failures =
      for {label, opts, message} <- surfaces(),
          catalogs = if(opts[:catalog] == :admin_v1, do: SchemaHelper.admin_catalogs()),
          {:error, errors} <- [SchemaHelper.validate_agent_message(message, catalogs: catalogs)] do
        "#{label}: #{errors |> Enum.take(3) |> Enum.join("; ")}"
      end

    assert failures == [], Enum.join(failures, "\n")
  end

  test "every surface's component ids are unique" do
    failures =
      for {label, _opts, message} <- surfaces(),
          ids = Enum.map(message["createSurface"]["components"], & &1["id"]),
          {id, count} <- Enum.frequencies(ids),
          count > 1 do
        "#{label}: #{id} x#{count}"
      end

    assert failures == [], Enum.join(failures, "\n")
  end
end
