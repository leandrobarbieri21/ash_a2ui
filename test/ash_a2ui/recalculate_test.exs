defmodule AshA2ui.RecalculateTest do
  @moduledoc """
  Recalculating values from unsaved changes (admin catalog 3.15): a
  `recalculate` field on a `:detail` card follows a person's unsaved changes
  to the record's editable cards. `preview_changes` runs each card's update
  action with the changes, as the save would, reads the field again, and
  rolls the transaction back: the result goes to `/ui/preview`, nothing is
  written and nothing is notified.
  """

  # Not async: capture_io(:stderr) captures a global device, the catalog is
  # application config, and the Mnesia tables are node-global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.DataLayer.Mnesia
  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.{Lease, LeaseEditUI, LeaseTerm, Messages, SchemaHelper}

  setup_all do
    Mnesia.start(AshA2ui.Test.Domain)
    :ok
  end

  setup do
    on_exit(fn -> Application.put_env(:ash_a2ui, :catalog, :basic) end)

    lease =
      Ash.create!(Lease, %{title: "Unit #{System.unique_integer([:positive])}", rent: 1000},
        authorize?: false
      )

    term =
      Ash.create!(
        LeaseTerm,
        %{
          lease_id: lease.id,
          ends_on: ~D[2027-06-30],
          notice_days: 30,
          notice_by: ~D[2027-05-31]
        },
        authorize?: false
      )

    flush_notifications()
    %{lease: lease, term: term}
  end

  defp flush_notifications do
    receive do
      {:lease_notified, _resource, _action} -> flush_notifications()
    after
      0 -> :ok
    end
  end

  defp contexts(lease), do: %{"lease" => %{"value" => lease.id, "label" => lease.title}}

  defp surface(lease) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    [%{"createSurface" => surface} = message] =
      AshA2ui.Info.build_surface(LeaseEditUI,
        authorize?: false,
        context_state: %{"lease" => %{"search" => "", "value" => lease.id, "label" => "x"}}
      )

    SchemaHelper.assert_valid_agent_message(message, catalogs: SchemaHelper.admin_catalogs())
    Map.new(surface["components"], &{&1["id"], &1})
  end

  defp preview(lease, values, opts \\ []) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    edits =
      if values == %{},
        do: %{},
        else: %{"terms" => %{"recordId" => lease.id, "values" => values}}

    ActionHandler.handle(
      LeaseEditUI,
      Messages.call("preview_changes", "lease_edit", %{
        "edits" => edits,
        "contexts" => contexts(lease)
      }),
      Keyword.merge([authorize?: false], opts)
    )
  end

  defp save(lease, values) do
    Application.put_env(:ash_a2ui, :catalog, :admin_v1)

    ActionHandler.handle(
      LeaseEditUI,
      Messages.call("save_changes", "lease_edit", %{
        "edits" => %{"terms" => %{"recordId" => lease.id, "values" => values}},
        "choice" => "save",
        "recordId" => lease.id,
        "contexts" => contexts(lease)
      }),
      authorize?: false
    )
  end

  defp write(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> {:ok, value}
      _other -> nil
    end)
  end

  defp reload(record), do: Ash.get!(record.__struct__, record.id, authorize?: false)

  describe "the wire" do
    test "a recalculated field binds its preview, on every card of the context",
         %{lease: lease} do
      components = surface(lease)

      assert components["detail_terms_field_notice_by_text"]["preview"] ==
               %{"@path" => "/ui/preview/lease/notice_by_text"}

      assert components["detail_terms_field_yearly_text"]["preview"] ==
               %{"@path" => "/ui/preview/lease/yearly_text"}

      assert components["detail_timeline_field_timeline"]["preview"] ==
               %{"@path" => "/ui/preview/lease/timeline"}

      refute Map.has_key?(components["detail_terms_field_ends_text"], "preview")
      refute Map.has_key?(components["detail_terms_field_title"], "preview")
    end

    test "the save bar sends the unsaved changes for a preview", %{lease: lease} do
      bar = surface(lease)["save_bar"]

      assert bar["preview"] == %{
               "action" => "preview_changes",
               "context" => %{
                 "edits" => %{"@path" => "/ui/edits"},
                 "contexts" => %{"@path" => "/context"}
               }
             }
    end

    test "a surface without recalculated fields sends no preview" do
      statement = Ash.create!(AshA2ui.Test.Statement, %{title: "Fee"}, authorize?: false)
      Application.put_env(:ash_a2ui, :catalog, :admin_v1)

      [%{"createSurface" => surface}] =
        AshA2ui.Info.build_surface(AshA2ui.Test.StatementTermEditUI,
          authorize?: false,
          context_state: %{"statement" => %{"search" => "", "value" => statement.id}}
        )

      bar = Enum.find(surface["components"], &(&1["id"] == "save_bar"))
      refute Map.has_key?(bar, "preview")
    end
  end

  describe "preview_changes" do
    test "works the values out with the changes, through the actions a save runs",
         %{lease: lease} do
      assert {:ok, messages} =
               preview(lease, %{
                 "ends_text" => "2028-01-31",
                 "notice_text" => "60",
                 "rent" => "1500"
               })

      assert {:ok, %{"lease" => preview}} = write(messages, "/ui/preview")

      # notice_by is stored by the term's own :correct: only running it gives it
      assert preview["notice_by_text"] == %{"value" => "Notice by 2027-12-02"}
      assert preview["yearly_text"] == %{"value" => "$18000 a year"}

      assert %{"value" => _, "steps" => [notice, ends]} = preview["timeline"]
      assert notice["label"] == "Notice by" and notice["text"] == "2027-12-02"
      assert ends["label"] == "Ends" and ends["text"] == "2028-01-31"
    end

    test "writes nothing and notifies nothing", %{lease: lease, term: term} do
      assert {:ok, _messages} =
               preview(lease, %{"ends_text" => "2028-01-31", "rent" => "1500", "title" => "New"})

      saved = reload(term)
      assert saved.ends_on == ~D[2027-06-30]
      assert saved.notice_by == ~D[2027-05-31]
      assert reload(lease).rent == 1000
      assert reload(lease).title == lease.title

      refute_received {:lease_notified, _resource, _action}
      assert Process.get(:ash_notifications) in [nil, []]
    end

    test "is quiet: the outcome line is left alone", %{lease: lease} do
      assert {:ok, messages} = preview(lease, %{"rent" => "1500"})
      refute write(messages, "/ui/feedback")
      assert "preview_changes" in ActionHandler.quiet_actions()
    end

    test "no change previews nothing", %{lease: lease} do
      assert {:ok, messages} = preview(lease, %{})
      assert {:ok, %{}} = write(messages, "/ui/preview")
    end

    test "an update the action refuses previews nothing, and saves nothing",
         %{lease: lease, term: term} do
      assert {:ok, messages} = preview(lease, %{"notice_text" => "-5"})
      assert {:ok, %{}} = write(messages, "/ui/preview")
      assert reload(term).notice_days == 30
    end

    test "a record that does not offer editing previews nothing", %{lease: lease} do
      Ash.update!(lease, %{locked: true}, authorize?: false)
      assert {:ok, messages} = preview(lease, %{"rent" => "1500"})
      assert {:ok, %{}} = write(messages, "/ui/preview")
    end

    test "a field outside the card's editable fields is refused", %{lease: lease} do
      assert {:error, messages} = preview(lease, %{"yearly_text" => "1"})
      assert Messages.feedback(messages)["message"] =~ "is not an editable field"
    end

    test "a save clears the preview", %{lease: lease, term: term} do
      assert {:ok, messages} = save(lease, %{"ends_text" => "2028-01-31"})
      assert {:ok, %{}} = write(messages, "/ui/preview")
      assert reload(term).notice_by == ~D[2028-01-01]

      assert {:ok, detail} = write(messages, "/detail/lease")
      assert detail["notice_by_text"] == "Notice by 2028-01-01"
    end

    test "a surface pinned to an instant refuses it", %{lease: lease} do
      assert {:error, messages} =
               preview(lease, %{"rent" => "1500"}, as_of: ~U[2026-01-01 00:00:00Z])

      assert Messages.feedback(messages)["code"] == "READ_ONLY_AS_OF"
    end
  end

  describe "the verifier" do
    test "a recalculated field needs a context with an editable card" do
      result =
        capture_io(:stderr, fn ->
          defmodule RecalculateNothingToFollow do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Lease

              context :lease do
                resource AshA2ui.Test.Lease
                picker false
              end

              component :detail, :terms do
                context :lease
                fields [:yearly_text]
              end

              field :yearly_text, do: recalculate(true)
            end
          end
        end)

      assert result =~ ~r/no :detail card draws it\s+in a context with an editable card/
    end

    test "a recalculated field is not an editable field" do
      result =
        capture_io(:stderr, fn ->
          defmodule RecalculateEditable do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Lease

              context :lease do
                resource AshA2ui.Test.Lease
                picker false
              end

              component :detail, :terms do
                context :lease
                fields [:rent]

                editable do
                  fields [:rent]
                  update_action :correct
                end
              end

              field :rent, do: recalculate(true)

              save_bar do
                context :lease
              end
            end
          end
        end)

      assert result =~ ~r/it is an editable field of :terms/
    end

    test "a recalculated field needs a data layer with transactions" do
      result =
        capture_io(:stderr, fn ->
          defmodule RecalculateNoTransactions do
            @moduledoc false
            use AshA2ui.Standalone

            a2ui do
              for_resource AshA2ui.Test.Statement

              context :statement do
                resource AshA2ui.Test.Statement
                picker false
              end

              component :detail, :facts do
                context :statement
                fields [:title, :amount_text]

                editable do
                  fields [:title]
                  update_action :correct
                end
              end

              field :amount_text, do: recalculate(true)

              save_bar do
                context :statement
              end
            end
          end
        end)

      assert result =~ ~r/has a data layer without\s+transactions/
    end
  end
end
