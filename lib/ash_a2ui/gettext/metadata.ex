defmodule AshA2ui.Gettext.Metadata do
  @moduledoc """
  The host display metadata a set of A2UI surfaces shows, as a gettext
  template: what `mix ash_a2ui.gettext.extract_metadata` writes to the
  host's `priv/gettext/a2ui_metadata.pot`.

  Collection runs the runtime's own code, not a copy of it. Each surface is
  resolved (`AshA2ui.ResolvedView.resolve/2`), its sectioned tables are
  expanded without reads (`AshA2ui.Sections.expand_static/1`), and it is
  encoded with no records, with a recording `:gettext_fn` as its
  translator. Every lookup the runtime makes in the metadata domain
  (`AshA2ui.Label`, `AshA2ui.L10n.metadata/3`) is recorded with its
  `msgctxt`, so the template holds exactly the strings a reader sees, and
  display text routed through those functions is collected with no change
  here. Library strings (`AshA2ui.Gettext.msg/1`) are in the shipped
  `ash_a2ui.pot` and are not collected.

  No data layer is touched: section headings and option labels read from
  records are record data, not metadata.
  """

  alias AshA2ui.L10n
  alias AshA2ui.ResolvedView

  @typedoc "A collected message: its `msgctxt` (or `nil`) and its msgid."
  @type key :: {String.t() | nil, String.t()}

  @doc """
  Every surface of `otp_app`: its modules that are Ash resources using the
  `AshA2ui` extension, and its `AshA2ui.Standalone` UI modules, sorted by
  name.
  """
  @spec surfaces(atom) :: [module]
  def surfaces(otp_app) do
    case :application.get_key(otp_app, :modules) do
      {:ok, modules} -> modules |> Enum.filter(&surface?/1) |> Enum.sort()
      :undefined -> []
    end
  end

  defp surface?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0) and
      (Spark.Dsl.is?(module, AshA2ui.Standalone) or
         (Spark.Dsl.is?(module, Ash.Resource) and AshA2ui in Spark.extensions(module)))
  end

  @doc """
  The metadata messages `surfaces` show, each mapped to the sorted source
  files (relative to the working directory) of the surfaces showing it.
  """
  @spec messages([module]) :: %{key => [String.t()]}
  def messages(surfaces) do
    surfaces
    |> Enum.flat_map(fn surface ->
      surface |> surface_messages() |> Enum.map(&{&1, source(surface)})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, files} -> {key, files |> Enum.uniq() |> Enum.sort()} end)
  end

  @doc """
  The metadata messages one surface shows, as `{msgctxt, msgid}` keys, in
  the order the runtime resolves them, without duplicates.
  """
  @spec surface_messages(module) :: [key]
  def surface_messages(surface) do
    view =
      surface
      |> ResolvedView.resolve(gettext_fn: {__MODULE__, :record})
      |> AshA2ui.Sections.expand_static()

    AshA2ui.Info.encoder(view).encode_surface(view, no_records(view), [])

    drain([]) |> Enum.reverse() |> Enum.uniq()
  end

  defp no_records(view) do
    if ResolvedView.multi_table?(view), do: Map.new(view.tables, &{&1.name, []}), else: []
  end

  # The recording translator: a `:gettext_fn` of the domain-aware shape. It
  # translates nothing (`nil` falls back to the msgid), so the surface
  # renders exactly as it does untranslated.
  @doc false
  def record(msgid, _bindings, _locale, meta) do
    if meta[:domain] == L10n.default_metadata_domain() do
      send(self(), {__MODULE__, meta[:context], msgid})
    end

    nil
  end

  defp drain(acc) do
    receive do
      {__MODULE__, context, msgid} -> drain([{context, msgid} | acc])
    after
      0 -> acc
    end
  end

  defp source(module) do
    module.module_info(:compile)
    |> Keyword.fetch!(:source)
    |> to_string()
    |> Path.relative_to_cwd()
  end

  @doc """
  The `.pot` content for `messages` (from `messages/1`) in `domain`:
  entries sorted by msgid, then `msgctxt`, each with its source files as
  references.
  """
  @spec pot(%{key => [String.t()]}, String.t()) :: String.t()
  def pot(messages, domain) do
    entries =
      messages
      |> Enum.sort_by(fn {{context, msgid}, _files} -> {msgid, context || ""} end)
      |> Enum.map_join("\n", fn {key, files} -> entry(key, files) end)

    header(domain) <> entries
  end

  defp header(domain) do
    """
    ## This file is a PO Template file.
    ##
    ## `msgid`s here are the display labels of this application's A2UI
    ## surfaces, collected by resolving each surface.
    ##
    ## Run `mix ash_a2ui.gettext.extract_metadata` to refresh this file.
    ## Run `mix gettext.merge priv/gettext --locale LOCALE` to merge into a .po file.

    msgid ""
    msgstr ""
    "Content-Type: text/plain; charset=UTF-8\\n"
    "Content-Transfer-Encoding: 8bit\\n"
    "Domain: #{domain}\\n"

    """
  end

  defp entry({context, msgid}, files) do
    [
      Enum.map(files, &"#: #{&1}\n"),
      if(context, do: "msgctxt #{quote_po(context)}\n", else: []),
      "msgid #{quote_po(msgid)}\n",
      "msgstr \"\"\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp quote_po(string) do
    escaped =
      string
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\t", "\\t")

    "\"" <> escaped <> "\""
  end
end
