defmodule AshA2ui.L10n do
  @moduledoc """
  Message templates for the text ash_a2ui writes for a reader: feedback,
  status lines and chrome built from parts (`"Exported %{filename} (%{count}
  rows)."`), and the host's display metadata (labels).

  A template's `%{key}` placeholders are filled from a keyword list of
  bindings, the way Gettext interpolates. Each placeholder is replaced
  once, in a single pass, so a value that itself contains `%{...}` is never
  interpolated again. A placeholder with no binding is left as written.

  ## Two domains, by owner

  Text is looked up in the domain of whoever owns it:

    * **Library strings** (`AshA2ui.Gettext.msg/1`: buttons, pagination,
      feedback templates) are ash_a2ui's own. They ship in
      `priv/gettext/ash_a2ui.pot` and are translated with `t/3`.
    * **Host display metadata** (declared labels, and labels humanized from
      field, action and component names) belongs to the application. It is
      in no shipped catalog: `mix ash_a2ui.gettext.extract_metadata` writes
      it to the host's `priv/gettext/a2ui_metadata.pot`. It is translated
      with `metadata/3`, in the `:metadata_domain`.

  A metadata message may carry a context (`msgctxt`), so a homograph
  translates separately: an enum value's label is looked up under
  `"enum:" <> Atom.to_string(EnumModule)`, e.g. `"enum:Elixir.MyApp.Status"`.

  ## Translators

  `new/1` builds a translator from the localization options that
  `AshA2ui.Info.build_surface/2`, `AshA2ui.Info.build_data_model/2` and
  `AshA2ui.ActionHandler.handle/3` accept:

    * `:gettext_backend` — `{backend, domain}`, e.g.
      `{MyAppWeb.Gettext, "ash_a2ui"}`. `domain` is the library domain.
      Messages are looked up with `Gettext.dgettext/4`,
      `Gettext.dpgettext/5` when they carry a context, or
      `Gettext.dngettext/6` when they are plural, inside
      `Gettext.with_locale/3`, so `:locale` is required with it.
    * `:gettext_fn` — `{module, function}`, for a translation layer that is
      not Gettext. Returns the translated, interpolated string. Called in
      one of two shapes:
        * when `function/4` is exported, as
          `module.function(msgid, bindings, locale, meta)` for every
          message. `locale` is the `:locale` option, or `nil`. `meta` is a
          keyword list: `:domain` (`"ash_a2ui"` for library strings, the
          `:metadata_domain` for host metadata), and `:context` when the
          message has a `msgctxt`. One function tells the owners apart by
          `meta[:domain]`.
        * otherwise as `module.function(msgid, bindings)`, or
          `module.function(msgid, bindings, locale)` when `:locale` is
          given. This shape receives both owners' messages without their
          domain or context (as before the split).
      `bindings` is a keyword list. A plural message (`tn/5`) is called the
      same way, with the singular msgid, `count` among the bindings, and
      `:plural` (the plural msgid) and `:count` added to `meta`: the function
      picks the form. The arity-2 and -3 shapes receive the msgid already
      chosen by `count` (singular for `1`, plural otherwise), as English
      plural rules do.
    * `:metadata_domain` — the domain host display metadata is looked up
      in. Defaults to `"a2ui_metadata"`, with either translator.
    * `:errors_domain` — the domain an Ash error's message is looked up in,
      by its own msgid (the error's message template, e.g. `"must be more
      than or equal to %{min}"`) with the error's `vars` as bindings.
      Defaults to `"errors"`, where `mix ash.gen.gettext` puts Ash's
      catalog. Only the field errors shown to the reader are translated.
    * `:verbatim` — a `MapSet` of display strings the metadata translator
      returns as written: text authored by a person or agent for this one
      surface (see `AshA2ui.Dynamic`), which no catalog holds.
    * `:locale` — the locale to translate into, as a string (`"fr"`,
      `"fr_CA"`). ash_a2ui never reads the process's ambient Gettext
      locale: pass the one the request resolved.

  The two translators are exclusive. Without either, the msgid is only
  interpolated and output is unchanged. A translator that returns `nil`,
  `""` or a non-string falls back to the interpolated msgid. ash_a2ui does
  not depend on `:gettext`: the backend translator calls it only when the
  host configures one.
  """

  @placeholder ~r/%\{(\w+)\}/

  @library_domain "ash_a2ui"
  @default_metadata_domain "a2ui_metadata"
  @default_errors_domain "errors"

  defstruct [:translate, :locale, :domain, :metadata_domain, :errors_domain, verbatim: nil]

  @typedoc "`nil` for a singular message, else its plural msgid and the count."
  @type plural :: nil | {String.t(), non_neg_integer}

  @typedoc "A translator built by `new/1`, or `nil` for none."
  @type t ::
          nil
          | %__MODULE__{
              translate: (String.t(), String.t() | nil, String.t(), keyword, plural -> term),
              locale: String.t() | nil,
              domain: String.t(),
              metadata_domain: String.t(),
              errors_domain: String.t(),
              verbatim: nil | MapSet.t(String.t())
            }

  @option_keys [
    :gettext_fn,
    :gettext_backend,
    :metadata_domain,
    :errors_domain,
    :locale,
    :verbatim
  ]

  @doc "The option keys `new/1` reads."
  @spec option_keys() :: [atom]
  def option_keys, do: @option_keys

  @doc "The domain host display metadata is looked up in by default."
  @spec default_metadata_domain() :: String.t()
  def default_metadata_domain, do: @default_metadata_domain

  @doc """
  Builds a translator from `opts` (see the moduledoc), or `nil` when no
  translator is configured. Raises `ArgumentError` on an invalid
  combination.

      iex> AshA2ui.L10n.new([])
      nil

      iex> AshA2ui.L10n.new(locale: "fr")
      nil
  """
  @spec new(keyword) :: t
  def new(opts) do
    locale = optional_string!(opts, :locale)
    metadata_domain = optional_string!(opts, :metadata_domain) || @default_metadata_domain
    errors_domain = optional_string!(opts, :errors_domain) || @default_errors_domain

    case translator(opts[:gettext_fn], opts[:gettext_backend], locale) do
      nil ->
        nil

      {translate, domain} ->
        %__MODULE__{
          translate: translate,
          locale: locale,
          domain: domain,
          metadata_domain: metadata_domain,
          errors_domain: errors_domain,
          verbatim: opts[:verbatim]
        }
    end
  end

  defp optional_string!(opts, key) do
    case Keyword.get(opts, key) do
      value when is_nil(value) or (is_binary(value) and value != "") -> value
      other -> raise ArgumentError, ":#{key} must be a non-empty string, got: #{inspect(other)}"
    end
  end

  defp translator(nil, nil, _locale), do: nil
  defp translator(fun, nil, locale), do: {function_translator(fun, locale), @library_domain}
  defp translator(nil, backend, locale), do: backend_translator(backend, locale)

  defp translator(_fun, _backend, _locale),
    do: raise(ArgumentError, "pass either :gettext_fn or :gettext_backend, not both")

  defp function_translator({module, function}, locale)
       when is_atom(module) and is_atom(function) do
    cond do
      Code.ensure_loaded?(module) and function_exported?(module, function, 4) ->
        fn domain, context, msgid, bindings, plural ->
          apply(module, function, [msgid, bindings, locale, meta(domain, context, plural)])
        end

      is_nil(locale) ->
        ensure_exported!(module, function, 2)

        fn _domain, _context, msgid, bindings, plural ->
          apply(module, function, [pick(msgid, plural), bindings])
        end

      true ->
        ensure_exported!(module, function, 3)

        fn _domain, _context, msgid, bindings, plural ->
          apply(module, function, [pick(msgid, plural), bindings, locale])
        end
    end
  end

  defp function_translator(other, _locale) do
    raise ArgumentError, ":gettext_fn must be a {module, function} tuple, got: #{inspect(other)}"
  end

  defp meta(domain, context, plural) do
    [domain: domain] ++
      if(context, do: [context: context], else: []) ++
      case plural do
        nil -> []
        {msgid_plural, count} -> [plural: msgid_plural, count: count]
      end
  end

  # English plural rule, for the translators that do not pick a form.
  defp pick(msgid, nil), do: msgid
  defp pick(msgid, {_plural, 1}), do: msgid
  defp pick(_msgid, {plural, _count}), do: plural

  defp backend_translator({backend, domain}, locale)
       when is_atom(backend) and is_binary(domain) do
    if is_nil(locale) do
      raise ArgumentError,
            ":gettext_backend needs an explicit :locale; ash_a2ui never reads the ambient locale"
    end

    # Resolved at runtime: ash_a2ui has no :gettext dependency, the host does.
    gettext = Module.concat(["Gettext"])

    if not Code.ensure_loaded?(gettext) do
      raise ArgumentError, ":gettext_backend needs the :gettext dependency"
    end

    translate = fn domain, context, msgid, bindings, plural ->
      gettext.with_locale(backend, locale, fn ->
        lookup(gettext, backend, domain, context, msgid, plural, Map.new(bindings))
      end)
    end

    {translate, domain}
  end

  defp backend_translator(other, _locale) do
    raise ArgumentError,
          ":gettext_backend must be a {backend, domain} tuple, got: #{inspect(other)}"
  end

  defp lookup(gettext, backend, domain, nil, msgid, nil, bindings),
    do: gettext.dgettext(backend, domain, msgid, bindings)

  defp lookup(gettext, backend, domain, context, msgid, nil, bindings),
    do: gettext.dpgettext(backend, domain, context, msgid, bindings)

  defp lookup(gettext, backend, domain, nil, msgid, {plural, count}, bindings),
    do: gettext.dngettext(backend, domain, msgid, plural, count, bindings)

  defp ensure_exported!(module, function, arity) do
    if not (Code.ensure_loaded?(module) and function_exported?(module, function, arity)) do
      raise ArgumentError,
            ":gettext_fn #{inspect(module)}.#{function}/#{arity} is not defined"
    end
  end

  @doc """
  Translates the library string `msgid` with `l10n`, in the library domain,
  and fills its placeholders from `bindings`. Without a translator (`nil`)
  the msgid is only interpolated. A translation that comes back `nil`,
  empty or not a string falls back to the interpolated msgid.

      iex> AshA2ui.L10n.t(nil, "Updated %{field}.", field: "Name")
      "Updated Name."
  """
  @spec t(t, String.t(), keyword) :: String.t()
  def t(l10n, msgid, bindings \\ [])
  def t(nil, msgid, bindings) when is_binary(msgid), do: interpolate(msgid, bindings)

  def t(%__MODULE__{domain: domain} = l10n, msgid, bindings) when is_binary(msgid),
    do: translate(l10n, domain, nil, msgid, bindings, nil)

  @doc """
  Translates the plural library string `msgid` / `msgid_plural` for `count`
  with `l10n`, in the library domain. `count` is bound as `%{count}`, as
  Gettext's `ngettext` does. Without a translator the form is chosen as in
  English: `msgid` for `1`, `msgid_plural` otherwise.

      iex> AshA2ui.L10n.tn(nil, "%{count} row", "%{count} rows", 1, [])
      "1 row"

      iex> AshA2ui.L10n.tn(nil, "%{count} row", "%{count} rows", 2, [])
      "2 rows"
  """
  @spec tn(t, String.t(), String.t(), non_neg_integer, keyword) :: String.t()
  def tn(l10n, msgid, msgid_plural, count, bindings)
      when is_binary(msgid) and is_binary(msgid_plural) and is_integer(count) and count >= 0 do
    bindings = Keyword.put(bindings, :count, count)
    plural = {msgid_plural, count}

    case l10n do
      nil -> interpolate(pick(msgid, plural), bindings)
      %__MODULE__{domain: domain} -> translate(l10n, domain, nil, msgid, bindings, plural)
    end
  end

  @doc """
  `tn/5` for a `AshA2ui.Gettext.msg_plural/2` pair.

      iex> AshA2ui.L10n.tn(nil, {"%{count} row", "%{count} rows"}, 3)
      "3 rows"
  """
  @spec tn(t, {String.t(), String.t()}, non_neg_integer, keyword) :: String.t()
  def tn(l10n, {msgid, msgid_plural}, count, bindings \\ []),
    do: tn(l10n, msgid, msgid_plural, count, bindings)

  @doc """
  Translates the host display string `msgid` (a label) with `l10n`, in the
  metadata domain, under the `msgctxt` `context` when it is not `nil`.
  Display metadata carries no placeholders. Without a translator, or
  without a translation, `msgid` is returned unchanged.

      iex> AshA2ui.L10n.metadata(nil, "Due date")
      "Due date"
  """
  @spec metadata(t, String.t(), String.t() | nil) :: String.t()
  def metadata(l10n, msgid, context \\ nil)
  def metadata(nil, msgid, _context) when is_binary(msgid), do: msgid

  def metadata(%__MODULE__{metadata_domain: domain, verbatim: verbatim} = l10n, msgid, context)
      when is_binary(msgid) do
    if verbatim && MapSet.member?(verbatim, msgid),
      do: msgid,
      else: translate(l10n, domain, context, msgid, [], nil)
  end

  @doc """
  Translates the message template `msgid` of an Ash (Splode) error with
  `l10n`, in the errors domain, filling `bindings` (the error's `vars`).
  Without a translator, or without a translation, the interpolated `msgid`
  is returned.

      iex> AshA2ui.L10n.error(nil, "must be more than %{min}", min: "3")
      "must be more than 3"
  """
  @spec error(t, String.t(), keyword) :: String.t()
  def error(nil, msgid, bindings) when is_binary(msgid), do: interpolate(msgid, bindings)

  def error(%__MODULE__{errors_domain: domain} = l10n, msgid, bindings) when is_binary(msgid),
    do: translate(l10n, domain, nil, msgid, bindings, nil)

  @doc """
  Joins `parts` with `template`, a message with `%{first}` and `%{rest}`
  placeholders (`msg("%{first}; %{rest}")`), so the separator is the
  catalog's to translate. One part is returned as is; none is `""`.

      iex> AshA2ui.L10n.join(nil, ["a", "b", "c"], "%{first}, %{rest}")
      "a, b, c"
  """
  @spec join(t, [String.t()], String.t()) :: String.t()
  def join(_l10n, [], _template), do: ""
  def join(_l10n, [only], _template), do: only

  def join(l10n, [first | rest], template),
    do: t(l10n, template, first: first, rest: join(l10n, rest, template))

  defp translate(%__MODULE__{translate: translate}, domain, context, msgid, bindings, plural) do
    case translate.(domain, context, msgid, bindings, plural) do
      translated when is_binary(translated) and translated != "" -> translated
      _missing -> interpolate(pick(msgid, plural), bindings)
    end
  end

  @doc """
  Fills `template`'s `%{key}` placeholders from `bindings`.

      iex> AshA2ui.L10n.interpolate("Updated %{field}.", field: "Name")
      "Updated Name."

      iex> AshA2ui.L10n.interpolate("%{a} and %{b}", a: "%{b}", b: "x")
      "%{b} and x"
  """
  @spec interpolate(String.t(), keyword | map) :: String.t()
  def interpolate(template, bindings) when bindings == [] or bindings == %{}, do: template

  def interpolate(template, bindings) when is_binary(template) do
    values = Map.new(bindings, fn {key, value} -> {to_string(key), value} end)

    Regex.replace(@placeholder, template, fn whole, key ->
      case Map.fetch(values, key) do
        {:ok, value} -> to_string(value)
        :error -> whole
      end
    end)
  end
end
