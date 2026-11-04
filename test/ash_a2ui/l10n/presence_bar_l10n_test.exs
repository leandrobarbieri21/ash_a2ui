# Phoenix-only, like the presence bar itself: nothing here compiles under
# NO_PHOENIX.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.L10n.PresenceBarTest do
    @moduledoc """
    The presence bar's text is library text: translated once in the library
    domain, and presence names are data.
    """

    use ExUnit.Case, async: true

    import Phoenix.LiveViewTest

    @presences [%{key: "a", label: "Ada"}, %{key: "b", label: "Grace"}]
    @pseudo [gettext_fn: {AshA2ui.Test.DomainPseudoLocale, :translate}, locale: "pseudo"]

    test "without a translator its text is unchanged" do
      html = render_component(&AshA2ui.PresenceBar.bar/1, presences: @presences, max_visible: 1)

      assert html =~ ~s(aria-label="People viewing this surface")
      assert html =~ ~s(aria-label="Ada is viewing this surface")
      assert html =~ ~s(aria-label="1 more people viewing this surface")
      assert html =~ ~s(title="People viewing this surface: +1")
    end

    test "its chrome is translated once; names are data" do
      html =
        render_component(
          &AshA2ui.PresenceBar.bar/1,
          [presences: @presences, max_visible: 1] ++ @pseudo
        )

      assert html =~ "⟦People viewing this surface⟧"
      assert html =~ "⟦Ada is viewing this surface⟧"
      assert html =~ "⟦1 more people viewing this surface⟧"
      assert html =~ "⟦⟦People viewing this surface⟧: +1⟧"
      refute html =~ "⟪"
    end

    test "the overflow count is a plural message" do
      three = @presences ++ [%{key: "c", label: "Linus"}]

      for {max_visible, count} <- [{2, 1}, {1, 2}] do
        html =
          render_component(
            &AshA2ui.PresenceBar.bar/1,
            [presences: three, max_visible: max_visible] ++ @pseudo
          )

        assert html =~ "⟦#{count} more people viewing this surface⟧"
      end
    end
  end
end
