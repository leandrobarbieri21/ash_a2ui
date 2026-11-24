defmodule AshA2ui.Test.LeaseNotifier do
  @moduledoc """
  Fixture notifier: sends `{:lease_notified, resource, action}` to the
  process that ran the action, so a test sees every notification sent.
  """

  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{resource: resource, action: action}) do
    send(self(), {:lease_notified, resource, action.name})
    :ok
  end
end
