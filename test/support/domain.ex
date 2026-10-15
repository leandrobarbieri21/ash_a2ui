defmodule AshA2ui.Test.Domain do
  @moduledoc """
  Test domain for the shared Ets-backed fixture resources.

  FROZEN CONTRACT — parallel tracks share these fixtures; extend only via an
  integration commit.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.KitchenSink
    resource AshA2ui.Test.Minimal
    resource AshA2ui.Test.Paginated
    resource AshA2ui.Test.Author
    resource AshA2ui.Test.Post
    resource AshA2ui.Test.Article
    resource AshA2ui.Test.Comment
    resource AshA2ui.Test.ReviewItem
    resource AshA2ui.Test.Referral
    resource AshA2ui.Test.EnumRecord
    resource AshA2ui.Test.Ticket
    resource AshA2ui.Test.TicketNote
    resource AshA2ui.Test.Tag
    resource AshA2ui.Test.Promotion
    resource AshA2ui.Test.Owner
    resource AshA2ui.Test.Clinic
    resource AshA2ui.Test.ClinicMembership
    resource AshA2ui.Test.Appointment
    resource AshA2ui.Test.Bucket
    resource AshA2ui.Test.BucketWord
    resource AshA2ui.Test.BulkProject
    resource AshA2ui.Test.BulkTask
  end
end
