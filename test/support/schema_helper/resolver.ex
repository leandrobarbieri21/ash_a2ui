defmodule AshA2ui.Test.SchemaHelper.Resolver do
  @moduledoc """
  A `JSV.Resolver` that serves every `https://a2ui.org/specification/v1_0/...`
  URI from the vendored copies in `priv/a2ui/v1_0`, never the network.

  The spec schemas name each other by basename (`common_types.json`,
  `agent_to_renderer_list.json`, ...), sometimes under a `json/` path segment
  and sometimes not, so a URI resolves by its basename alone.

  `catalog.json` is an alias, as in the upstream runner
  (`specification/v1_0/test/run_tests.py`): it names whichever catalog the
  messages are validated against. The `:catalogs` option lists the files
  (relative to `priv/a2ui/v1_0`). The default is what every ash_a2ui surface
  uses: the basic catalog and the ash_a2ui catalog, which declares
  `ashAction` and `downloadFile`. One file
  is served as `catalog.json` with its `$id` rewritten to the requested URI,
  so that its relative `common_types.json` refs land on the vendored common
  types. Several files are the mixed-catalog case: each is served as
  `catalog_member_<n>.json`, and `catalog.json` is a composite whose
  `anyComponent` and `anyFunction` are a `oneOf` over the members' own. A
  component or function must then match exactly one catalog's definition.

  Anything else (the JSON Schema meta-schemas) falls through to the next
  resolver in the chain.

  ## Regex dialect

  The spec's regexes are ECMAScript (`u` flag). One of them, the `Extensions`
  key pattern in `common_types.json`, uses the binary properties
  `\\p{XID_Start}` and `\\p{XID_Continue}`, which the PCRE engine in OTP 27
  does not know (JSV translates general categories, not binary properties).
  Every served schema has them rewritten to their general-category
  definitions from UAX #31, inside the character classes where the spec uses
  them: `XID_Start` as `\\p{L}\\p{Nl}`, `XID_Continue` as
  `\\p{L}\\p{Nl}\\p{Mn}\\p{Mc}\\p{Nd}\\p{Pc}`. The two differ only on the
  handful of `Other_ID_Start`/`Other_ID_Continue` code points and the NFKC
  exclusions, none of which any A2UI payload uses. The vendored files stay
  verbatim; this happens at load.
  """

  @behaviour JSV.Resolver

  @base "https://a2ui.org/specification/v1_0/"
  @default_catalogs ["catalogs/basic/v1/catalog.json", "catalogs/ash_a2ui/catalog.json"]

  @doc "The URI prefix every vendored A2UI 1.0 schema lives under."
  def base, do: @base

  @doc "The vendored A2UI 1.0 directory."
  def dir, do: Application.app_dir(:ash_a2ui, ["priv", "a2ui", "v1_0"])

  @doc "Reads and decodes a vendored file, `relative` to `priv/a2ui/v1_0`."
  def read!(relative), do: dir() |> Path.join(relative) |> File.read!() |> Jason.decode!()

  @doc "Rewrites the ECMAScript binary properties PCRE lacks (see the moduledoc)."
  def to_pcre(pattern) do
    pattern
    |> String.replace("\\p{XID_Start}", "\\p{L}\\p{Nl}")
    |> String.replace("\\p{XID_Continue}", "\\p{L}\\p{Nl}\\p{Mn}\\p{Mc}\\p{Nd}\\p{Pc}")
  end

  @impl JSV.Resolver
  def resolve(@base <> _ = uri, opts) do
    case uri |> URI.parse() |> Map.fetch!(:path) |> Path.basename() do
      "catalog.json" ->
        case catalogs(opts) do
          [catalog] -> serve(catalog, uri)
          members -> {:normal, composite(members, uri)}
        end

      "catalog_member_" <> index ->
        {n, ".json"} = Integer.parse(index)
        opts |> catalogs() |> Enum.fetch!(n) |> serve(uri)

      "testing_catalog.json" ->
        {:normal, "test/testing_catalog.json" |> read!() |> translate_patterns()}

      basename ->
        path = Path.join("json", basename)

        if File.exists?(Path.join(dir(), path)),
          do: {:normal, path |> read!() |> translate_patterns()},
          else: {:error, {:not_vendored, uri}}
    end
  end

  def resolve(uri, _opts), do: {:error, {:not_an_a2ui_uri, uri}}

  @doc "The catalog files `opts` (`catalogs:`) selects, the basic and ash_a2ui catalogs by default."
  def catalog_files(opts), do: catalogs(opts)

  @doc "The URI, relative to `base/0`, the `index`th of `files` is served under."
  def catalog_uri([_single], 0), do: "catalog.json"
  def catalog_uri(_files, index), do: "catalog_member_#{index}.json"

  defp catalogs(opts) do
    case Keyword.get(opts, :catalogs) do
      nil -> @default_catalogs
      [_ | _] = files -> files
      file when is_binary(file) -> [file]
    end
  end

  defp serve(file, uri),
    do: {:normal, file |> read!() |> Map.put("$id", uri) |> translate_patterns()}

  defp composite(members, uri) do
    any = fn def ->
      %{
        "oneOf" =>
          members
          |> Enum.with_index()
          |> Enum.map(fn {_, n} -> %{"$ref" => "catalog_member_#{n}.json#/$defs/#{def}"} end)
      }
    end

    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$id" => uri,
      "$defs" => %{"anyComponent" => any.("anyComponent"), "anyFunction" => any.("anyFunction")}
    }
  end

  defp translate_patterns(%{} = schema) do
    Map.new(schema, fn
      {"patternProperties", %{} = props} ->
        {"patternProperties",
         Map.new(props, fn {k, v} -> {to_pcre(k), translate_patterns(v)} end)}

      {"pattern", pattern} when is_binary(pattern) ->
        {"pattern", to_pcre(pattern)}

      {key, value} ->
        {key, translate_patterns(value)}
    end)
  end

  defp translate_patterns(list) when is_list(list), do: Enum.map(list, &translate_patterns/1)
  defp translate_patterns(other), do: other
end
