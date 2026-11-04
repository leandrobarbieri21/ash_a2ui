# The avatar stack + nav helper are Phoenix-only renderings, guarded like
# the LiveView transport for the NO_PHOENIX CI job.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.PresenceBar do
    @moduledoc """
    Shipped, host-themeable renderings for `AshA2ui.Presence`: the avatar
    stack ("who else is here") and the nav active-state helper
    (`aria-current="page"`).

    ## The bar

        <AshA2ui.PresenceBar.bar presences={@a2ui_presences} />

    Renders an overlapping avatar stack — initials circles in the shared
    neobrutalist vocabulary (2px borders, hard shadows, `--a2ui-*` tokens
    with fallbacks, zero host CSS), one per presence row (`AshA2ui.list/2`
    rows: `%{key: ..., label: ...}`), each with an aria-label naming the
    person. More than `max_visible` (default 5) collapses into a "+N"
    chip whose aria-label counts the hidden visitors.

    Attributes:

      * `:presences` — the rows assign from `AshA2ui.Presence.mount_surface/4`.
      * `:max_visible` — avatars shown before the "+N" chip, default 5.
      * `:surface_label` — the stack's group aria-label,
        default "People viewing this surface".

    The bar re-renders whenever the host's `handle_info` runs the
    `AshA2ui.Presence` refresh contract (see its moduledoc): every join or
    leave broadcast re-lists `:a2ui_presences` and updates the assign.

    ## The nav active-state contract

        <a href="/clinic/schedule"
           {AshA2ui.PresenceBar.nav_current_attrs(@current_path, "/clinic/schedule")}>
          Schedule
        </a>

    Returns `%{"aria-current" => "page"}` when `current_path == path` (the
    link points at the page currently rendered) and
    `%{"aria-current" => nil}` (omitted from the markup) otherwise. Spread it on EVERY nav link with
    only the destination varying — see `AshA2ui.Presence`'s moduledoc for
    the clinic-demo wiring (`:current_path` from the mount URI).
    """

    use Phoenix.Component

    import AshA2ui.Gettext, only: [msg: 1, msg_plural: 2]

    alias AshA2ui.L10n

    attr(:presences, :list,
      default: [],
      doc: "rows from `AshA2ui.Presence.list/2`: %{key: String.t(), label: String.t()}"
    )

    attr(:max_visible, :integer, default: 5)

    attr(:surface_label, :string,
      default: nil,
      doc: ~s(The bar's accessible name; "People viewing this surface".)
    )

    attr(:locale, :string, default: nil, doc: "The locale for the bar's own text.")
    attr(:gettext_backend, :any, default: nil, doc: "`{backend, domain}`; see `AshA2ui.L10n`.")
    attr(:gettext_fn, :any, default: nil, doc: "`{module, function}`; see `AshA2ui.L10n`.")

    @doc """
    The avatar stack: overlapping initials circles plus the "+N" overflow
    chip. See the moduledoc.
    """
    def bar(assigns) do
      presences = assigns[:presences] || []
      max_visible = assigns[:max_visible] || 5

      l10n =
        L10n.new(
          Enum.reject(
            [
              locale: assigns[:locale],
              gettext_backend: assigns[:gettext_backend],
              gettext_fn: assigns[:gettext_fn]
            ],
            &is_nil(elem(&1, 1))
          )
        )

      surface_label =
        assigns[:surface_label] || L10n.t(l10n, msg("People viewing this surface"))

      overflow = max(0, length(presences) - max_visible)

      assigns =
        assign(assigns,
          visible: Enum.take(presences, max_visible),
          overflow: overflow,
          surface_label: surface_label,
          overflow_label:
            L10n.tn(
              l10n,
              msg_plural(
                "%{count} more people viewing this surface",
                "%{count} more people viewing this surface"
              ),
              overflow
            ),
          overflow_title:
            L10n.t(l10n, msg("%{label}: +%{count}"), label: surface_label, count: overflow),
          l10n: l10n
        )

      ~H"""
      <div class="a2ui-presence-bar" role="group" aria-label={@surface_label} style="display:inline-flex;align-items:center;">
        <span :for={{presence, index} <- Enum.with_index(@visible)}
          role="img"
          aria-label={viewing_label(@l10n, presence.label)}
          title={presence.label}
          style={"display:inline-flex;align-items:center;justify-content:center;
                  width:2rem;height:2rem;border-radius:9999px;
                  border:2px solid var(--a2ui-color-border, currentColor);
                  background:var(--a2ui-color-secondary, rgba(148,163,184,0.3));
                  color:var(--a2ui-color-on-secondary, inherit);
                  box-shadow:2px 2px 0 var(--a2ui-color-border, currentColor);
                  font:700 var(--a2ui-font-size-xs, 0.75rem) var(--a2ui-font-family, inherit);
                  #{index > 0 && "margin-left:-0.5rem;" || ""}"}
        >
          {initials(presence.label)}
        </span>
        <span :if={@overflow > 0}
          role="img"
          aria-label={@overflow_label}
          title={@overflow_title}
          style="display:inline-flex;align-items:center;justify-content:center;
                 height:2rem;border-radius:9999px;padding:0 0.5rem;
                 border:2px solid var(--a2ui-color-border, currentColor);
                 background:var(--a2ui-color-surface, #fff);
                 color:var(--a2ui-color-on-surface, inherit);
                 box-shadow:2px 2px 0 var(--a2ui-color-border, currentColor);
                 font:700 var(--a2ui-font-size-xs, 0.75rem) var(--a2ui-font-family, inherit);"
        >
          +{@overflow}
        </span>
      </div>
      """
    end

    defp viewing_label(l10n, name),
      do: L10n.t(l10n, msg("%{name} is viewing this surface"), name: name)

    @doc """
    The nav active-state attributes: `%{"aria-current" => "page"}` when
    `current_path == path`, `%{"aria-current" => nil}` (omitted from the
    markup) otherwise. String keys, so the spread renders the aria
    attribute verbatim.
    """
    @spec nav_current_attrs(term, term) :: %{String.t() => String.t() | nil}
    def nav_current_attrs(current_path, path)
        when is_binary(current_path) and is_binary(path) do
      %{"aria-current" => (current_path == path && "page") || nil}
    end

    @doc """
    Avatar initials from a display label: the first letter of the first
    two words, uppercased ("Ada Lovelace" -> "AL", "grace" -> "G"); "?"
    when there is nothing to take a letter from.
    """
    @spec initials(term) :: String.t()
    def initials(label) do
      label
      |> to_string()
      |> String.split(~r/\s+/u, trim: true)
      |> Enum.take(2)
      |> Enum.map_join("", &first_upcased_grapheme/1)
      |> case do
        "" -> "?"
        letters -> letters
      end
    end

    defp first_upcased_grapheme(word) do
      word
      |> String.graphemes()
      |> case do
        [] -> ""
        [first | _rest] -> String.upcase(first)
      end
    end
  end
end
