defmodule AshA2ui.Test.WizardProbe do
  @moduledoc """
  Test change for `AshA2ui.Test.Enrollment`: sends the attributes and
  arguments of every changeset it sees to the calling process as
  `{:wizard_probe, attributes, arguments}`, so wizard tests can assert
  exactly which client keys reached the changeset.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    send(self(), {:wizard_probe, changeset.attributes, changeset.arguments})
    changeset
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
