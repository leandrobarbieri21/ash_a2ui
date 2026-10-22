defmodule AshA2ui.Shell.Host do
  @moduledoc """
  What a host application supplies to the shell (`AshA2ui.Shell`): the
  entries a person may use, and what an invocation does.

      defmodule MyAppWeb.Shell do
        @behaviour AshA2ui.Shell.Host

        @impl true
        def entries(actor) do
          %{commands: MyApp.commands_for(actor), surfaces: MyApp.surfaces_for(actor)}
        end

        @impl true
        def invoke({:open_surface, %{"id" => id}, _target}, _actor, socket),
          do: {:ok, Phoenix.LiveView.push_navigate(socket, to: "/app/" <> id)}

        def invoke({:prompt, text}, _actor, socket), do: ...
      end

  `context` is whatever the host passed the component as `context` —
  usually the actor. `entries/1` runs when the shell first opens, not when
  the page mounts, so a page that is never asked for its palette never reads
  anything for it.
  """

  @doc "The commands and surfaces `context` may use, in the ACP wire shapes."
  @callback entries(context :: term()) :: AshA2ui.Shell.entries()

  @doc """
  Run an invocation. `{:ok, socket}` closes the shell (navigate, push an
  event, send the parent a message); `{:error, message}` keeps it open and
  shows the message.
  """
  @callback invoke(AshA2ui.Shell.invocation(), context :: term(), socket :: term()) ::
              {:ok, term()} | {:error, String.t()}
end
