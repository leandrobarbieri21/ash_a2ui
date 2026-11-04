defmodule AshA2ui.L10n do
  @moduledoc """
  Message templates for the text ash_a2ui writes for a reader: feedback,
  status lines and chrome built from parts (`"Exported %{filename} (%{count}
  rows)."`).

  A template's `%{key}` placeholders are filled from a keyword list of
  bindings, the way Gettext interpolates. Each placeholder is replaced
  once, in a single pass, so a value that itself contains `%{...}` is never
  interpolated again. A placeholder with no binding is left as written.

  ## Translators

  `new/1` builds a translator from the localization options that
  `AshA2ui.Info.build_surface/2`, `AshA2ui.Info.build_data_model/2` and
  `AshA2ui.ActionHandler.handle/3` accept:

    * `:gettext_backend` — `{backend, domain}`, e.g.
      `{MyAppWeb.Gettext, "ash_a2ui"}`. Messages are looked up with
      `Gettext.dgettext/4` inside `Gettext.with_locale/3`, so `:locale` is
      required with it.
    * `:gettext_fn` — `{module, function}`. Called as
      `module.function(msgid, bindings)`, or as
      `module.function(msgid, bindings, locale)` when `:locale` is given.
      `bindings` is a keyword list; the function returns the translated,
      interpolated string. Use it for a translation layer that is not
      Gettext.
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

  defstruct [:translate, :locale]

  @typedoc "A translator built by `new/1`, or `nil` for none."
  @type t :: nil | %__MODULE__{translate: (String.t(), keyword -> term), locale: String.t() | nil}

  @option_keys [:gettext_fn, :gettext_backend, :locale]

  @doc "The option keys `new/1` reads."
  @spec option_keys() :: [atom]
  def option_keys, do: @option_keys

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
    locale = Keyword.get(opts, :locale)

    if not (is_nil(locale) or (is_binary(locale) and locale != "")) do
      raise ArgumentError, ":locale must be a non-empty string, got: #{inspect(locale)}"
    end

    case {Keyword.get(opts, :gettext_fn), Keyword.get(opts, :gettext_backend)} do
      {nil, nil} ->
        nil

      {fun, nil} ->
        %__MODULE__{translate: function_translator(fun, locale), locale: locale}

      {nil, backend} ->
        %__MODULE__{translate: backend_translator(backend, locale), locale: locale}

      _both ->
        raise ArgumentError, "pass either :gettext_fn or :gettext_backend, not both"
    end
  end

  defp function_translator({module, function}, nil) when is_atom(module) and is_atom(function) do
    ensure_exported!(module, function, 2)
    fn msgid, bindings -> apply(module, function, [msgid, bindings]) end
  end

  defp function_translator({module, function}, locale)
       when is_atom(module) and is_atom(function) do
    ensure_exported!(module, function, 3)
    fn msgid, bindings -> apply(module, function, [msgid, bindings, locale]) end
  end

  defp function_translator(other, _locale) do
    raise ArgumentError, ":gettext_fn must be a {module, function} tuple, got: #{inspect(other)}"
  end

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

    fn msgid, bindings ->
      gettext.with_locale(backend, locale, fn ->
        gettext.dgettext(backend, domain, msgid, Map.new(bindings))
      end)
    end
  end

  defp backend_translator(other, _locale) do
    raise ArgumentError,
          ":gettext_backend must be a {backend, domain} tuple, got: #{inspect(other)}"
  end

  defp ensure_exported!(module, function, arity) do
    if not (Code.ensure_loaded?(module) and function_exported?(module, function, arity)) do
      raise ArgumentError,
            ":gettext_fn #{inspect(module)}.#{function}/#{arity} is not defined"
    end
  end

  @doc """
  Translates `msgid` with `l10n` and fills its placeholders from `bindings`.
  Without a translator (`nil`) the msgid is only interpolated. A
  translation that comes back `nil`, empty or not a string falls back to
  the interpolated msgid.

      iex> AshA2ui.L10n.t(nil, "Updated %{field}.", field: "Name")
      "Updated Name."
  """
  @spec t(t, String.t(), keyword) :: String.t()
  def t(l10n, msgid, bindings \\ [])
  def t(nil, msgid, bindings) when is_binary(msgid), do: interpolate(msgid, bindings)

  def t(%__MODULE__{translate: translate}, msgid, bindings) when is_binary(msgid) do
    case translate.(msgid, bindings) do
      translated when is_binary(translated) and translated != "" -> translated
      _missing -> interpolate(msgid, bindings)
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
