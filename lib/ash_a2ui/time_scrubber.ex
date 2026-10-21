# The scrubber is a Phoenix rendering, guarded like the LiveView transport
# for the NO_PHOENIX CI job.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.TimeScrubber do
    @moduledoc """
    A timeline control for time-travelled surfaces: drag it, or pick a
    moment on it, and the page moves to that instant through `?as_of=`.

        <AshA2ui.TimeScrubber.scrubber
          id="person-timeline"
          from={@span_from}
          to={@span_to}
          as_of={@as_of}
          marks={@marks}
          path={&person_path(@person.id, &1)}
        />

    The scrubber owns no data. The host supplies the span, the current
    instant and the marks, and a `path` function from an instant (`nil` for
    now) to a URL, typically `AshA2ui.AsOf.put_param/2` over the page's own
    path. Every control is navigation:

      * **the range input** posts its position to the host's `event`
        (default `"as_of_scrub"`). The host turns it into an instant with
        `instant/4` and `push_patch`es to `path`. The position is resolved
        server-side against the host's own span, so the client never names
        an instant directly;
      * **each mark** is a patch link to the mark's exact instant, both on
        the track and in the list of moments under it. Linking to the
        instant a change happened shows the state just after it, because a
        temporal version is valid from its lower bound;
      * **Now** is a patch link to `path.(nil)`.

    Dragging snaps: a position within one step of a mark resolves to the
    mark's instant, so scrubbing onto a merge lands on the merge rather than
    a microsecond before it.

    ## Attributes

      * `:id` (required) — the DOM id; the form, input and list derive theirs.
      * `:from`, `:to` (required) — the span, as `DateTime`s. `to` is usually
        now: the right-hand end then reads "Now".
      * `:as_of` — the instant shown (`nil` for now).
      * `:marks` — `[%{at: DateTime.t(), label: String.t()}]`, with an
        optional `:tone` (`:primary`, `:secondary`, `:danger`, `:neutral`)
        and `:description`. Marks outside the span are left off the track
        but stay in the list.
      * `:path` (required) — `(DateTime.t() | nil -> String.t())`.
      * `:event` — the range input's `phx-change` event, default
        `"as_of_scrub"`.
      * `:format` — `(DateTime.t() -> String.t())` for every instant the
        scrubber prints. Defaults to `format/1` (UTC).
      * `:label` — the group's accessible name, default "Time travel".

    It renders in the shared neobrutalist vocabulary (2px borders, hard
    shadows, `--a2ui-*` tokens with fallbacks) and needs no host CSS.
    """

    use Phoenix.Component

    @steps 1000

    @tones %{
      primary: "var(--a2ui-color-primary, #2563eb)",
      secondary: "var(--a2ui-color-secondary, #7c3aed)",
      danger: "var(--a2ui-color-danger, #dc2626)",
      neutral: "var(--a2ui-color-border, #111827)"
    }

    @typedoc "One moment on the timeline."
    @type mark :: %{
            required(:at) => DateTime.t(),
            required(:label) => String.t(),
            optional(:tone) => :primary | :secondary | :danger | :neutral,
            optional(:description) => String.t()
          }

    @doc "The number of positions the range input has."
    @spec steps() :: pos_integer
    def steps, do: @steps

    @doc """
    The instant a posted position stands for, against the host's span.

    `params` is the event's params (`%{"position" => "0".."#{@steps}"}`).
    A position within one step of a mark resolves to the mark's instant.
    The right-hand end resolves to `nil` (now) when the span ends now
    (`live_end?/1`), so a scrubber dragged all the way right reads live
    data again. An unparseable position is `nil`.
    """
    @spec instant(map, DateTime.t(), DateTime.t(), [mark]) :: DateTime.t() | nil
    def instant(params, from, to, marks \\ []) do
      with value when is_binary(value) <- params["position"],
           {position, _rest} <- Integer.parse(value) do
        position = position |> max(0) |> min(@steps)
        resolve(position, from, to, marks)
      else
        _unparseable -> nil
      end
    end

    defp resolve(@steps, _from, to, _marks), do: if(live_end?(to), do: nil, else: to)

    defp resolve(position, from, to, marks) do
      span = max(DateTime.diff(to, from, :microsecond), 1)
      at = DateTime.add(from, div(span * position, @steps), :microsecond)
      step = max(div(span, @steps), 1)

      marks
      |> Enum.map(& &1.at)
      |> Enum.filter(&(abs(DateTime.diff(&1, at, :microsecond)) <= step))
      |> Enum.min_by(&abs(DateTime.diff(&1, at, :microsecond)), fn -> at end)
    end

    @doc """
    Whether a span's end is "now": at, after, or within a minute before the
    wall clock. A host computes `to` when it renders and again when the
    scrub event arrives, so a span ending "now" ends a moment ago by then.
    """
    @spec live_end?(DateTime.t()) :: boolean
    def live_end?(to), do: DateTime.diff(DateTime.utc_now(), to, :second) < 60

    @doc "The range position (`0..#{@steps}`) an instant sits at; `nil` (now) is the end."
    @spec position(DateTime.t() | nil, DateTime.t(), DateTime.t()) :: non_neg_integer
    def position(nil, _from, _to), do: @steps

    def position(at, from, to) do
      span = max(DateTime.diff(to, from, :microsecond), 1)

      (DateTime.diff(at, from, :microsecond) * @steps / span)
      |> round()
      |> max(0)
      |> min(@steps)
    end

    @doc "The default instant format: `2026-10-17 14:03 UTC`."
    @spec format(DateTime.t()) :: String.t()
    def format(%DateTime{} = at) do
      at
      |> DateTime.shift_zone!("Etc/UTC")
      |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
    end

    attr(:id, :string, required: true)
    attr(:from, DateTime, required: true)
    attr(:to, DateTime, required: true)
    attr(:as_of, DateTime, default: nil)
    attr(:marks, :list, default: [])
    attr(:path, :any, required: true, doc: "(DateTime.t() | nil -> String.t())")
    attr(:event, :string, default: "as_of_scrub")
    attr(:format, :any, default: &__MODULE__.format/1)
    attr(:label, :string, default: "Time travel")

    @doc "The scrubber. See the moduledoc."
    def scrubber(assigns) do
      assigns =
        assign(assigns,
          steps: @steps,
          value: position(assigns.as_of, assigns.from, assigns.to),
          readout: readout(assigns.as_of, assigns.format),
          live_end?: live_end?(assigns.to),
          on_track: Enum.filter(assigns.marks, &within?(&1.at, assigns.from, assigns.to)),
          listed: Enum.sort_by(assigns.marks, & &1.at, {:desc, DateTime})
        )

      ~H"""
      <section
        id={@id}
        role="group"
        aria-label={@label}
        data-as-of={@as_of && AshA2ui.AsOf.to_param(@as_of)}
        style={"display:flex;flex-direction:column;gap:0.75rem;padding:0.75rem 1rem;
                border:2px solid var(--a2ui-color-border, currentColor);
                border-radius:var(--a2ui-radius, 0.5rem);
                background:#{if @as_of, do: "var(--a2ui-color-warning-surface, #fef9c3)", else: "var(--a2ui-color-surface, #fff)"};
                color:var(--a2ui-color-on-surface, inherit);
                box-shadow:4px 4px 0 var(--a2ui-color-border, currentColor);
                font-family:var(--a2ui-font-family, inherit);"}
      >
        <div style="display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:0.5rem;">
          <span
            id={"#{@id}-status"}
            role="status"
            style="display:inline-flex;align-items:center;gap:0.375rem;padding:0.125rem 0.5rem;
                   border:2px solid var(--a2ui-color-border, currentColor);border-radius:9999px;
                   font:700 var(--a2ui-font-size-xs, 0.75rem) var(--a2ui-font-family, inherit);"
          >
            {@readout}
          </span>
          <.link
            :if={@as_of}
            id={"#{@id}-now"}
            patch={@path.(nil)}
            style="padding:0.25rem 0.625rem;border:2px solid var(--a2ui-color-border, currentColor);
                   border-radius:var(--a2ui-radius, 0.5rem);
                   background:var(--a2ui-color-primary, #2563eb);color:var(--a2ui-color-on-primary, #fff);
                   box-shadow:2px 2px 0 var(--a2ui-color-border, currentColor);
                   font:700 var(--a2ui-font-size-sm, 0.875rem) var(--a2ui-font-family, inherit);
                   text-decoration:none;"
          >
            Return to now
          </.link>
        </div>

        <form id={"#{@id}-form"} phx-change={@event} onsubmit="return false;" style="margin:0;">
          <label for={"#{@id}-input"} style="display:block;font:700 var(--a2ui-font-size-sm, 0.875rem) var(--a2ui-font-family, inherit);margin-bottom:0.25rem;">
            Move through time
          </label>
          <input
            type="range"
            id={"#{@id}-input"}
            name="position"
            min="0"
            max={@steps}
            step="1"
            value={@value}
            phx-debounce="200"
            aria-valuetext={@readout}
            style="width:100%;cursor:ew-resize;accent-color:var(--a2ui-color-primary, #2563eb);"
          />
          <div aria-hidden="true" style="position:relative;height:1.25rem;margin-top:0.125rem;">
            <.link
              :for={mark <- @on_track}
              patch={@path.(mark.at)}
              tabindex="-1"
              title={"#{mark.label} — #{@format.(mark.at)}"}
              style={"position:absolute;top:0.25rem;left:calc(#{left(mark.at, @from, @to)}% - 0.3125rem);
                      width:0.625rem;height:0.625rem;transform:rotate(45deg);
                      border:2px solid var(--a2ui-color-border, currentColor);
                      background:#{tone(mark)};"}
            >
            </.link>
          </div>
          <div style="display:flex;justify-content:space-between;font-size:var(--a2ui-font-size-xs, 0.75rem);opacity:0.7;">
            <span>{@format.(@from)}</span>
            <span>{if @live_end?, do: "Now", else: @format.(@to)}</span>
          </div>
        </form>

        <ol
          :if={@listed != []}
          id={"#{@id}-marks"}
          aria-label="Moments"
          style="display:flex;flex-wrap:wrap;gap:0.375rem;margin:0;padding:0;list-style:none;"
        >
          <li :for={{mark, index} <- Enum.with_index(@listed)}>
            <.link
              id={"#{@id}-mark-#{index}"}
              patch={@path.(mark.at)}
              aria-current={current?(mark.at, @as_of) && "true"}
              title={Map.get(mark, :description)}
              style={"display:inline-flex;align-items:center;gap:0.375rem;padding:0.125rem 0.5rem;
                      border:2px solid var(--a2ui-color-border, currentColor);
                      border-radius:var(--a2ui-radius, 0.5rem);text-decoration:none;color:inherit;
                      background:#{if current?(mark.at, @as_of), do: "var(--a2ui-color-secondary-surface, #e0e7ff)", else: "var(--a2ui-color-surface, #fff)"};
                      font-size:var(--a2ui-font-size-xs, 0.75rem);"}
            >
              <span aria-hidden="true" style={"width:0.5rem;height:0.5rem;transform:rotate(45deg);background:#{tone(mark)};"}></span>
              <span style="font-weight:700;">{mark.label}</span>
              <span style="opacity:0.7;">{@format.(mark.at)}</span>
            </.link>
          </li>
        </ol>
      </section>
      """
    end

    defp readout(nil, _format), do: "Live: now"
    defp readout(at, format), do: "As of #{format.(at)}"

    defp within?(at, from, to),
      do: DateTime.compare(at, from) != :lt and DateTime.compare(at, to) != :gt

    defp left(at, from, to), do: Float.round(position(at, from, to) * 100 / @steps, 2)

    defp current?(_at, nil), do: false
    defp current?(at, as_of), do: DateTime.compare(at, as_of) == :eq

    defp tone(mark), do: Map.get(@tones, Map.get(mark, :tone, :primary), @tones.primary)
  end
end
