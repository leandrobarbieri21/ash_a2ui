defmodule AshA2ui.DynamicTest.TestDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule AshA2ui.DynamicTest.Guarded do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.DynamicTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :secret, :string, public?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:pending, :done]],
      default: :pending
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :finish do
      change set_attribute(:status, :done)
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end
end

defmodule AshA2ui.DynamicTest do
  use ExUnit.Case, async: false

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.Dynamic
  alias AshA2ui.Dynamic.Error
  alias AshA2ui.DynamicTest.Guarded
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.KitchenSink
  alias AshA2ui.Test.Minimal

  @allowlist Dynamic.allowlist([KitchenSink, Minimal, Guarded])

  defp resolve!(spec, opts \\ []) do
    {:ok, surface} = Dynamic.resolve(spec, Keyword.put_new(opts, :allowlist, @allowlist))
    surface
  end

  defp errors(spec, opts \\ []) do
    {:error, errors} = Dynamic.resolve(spec, Keyword.put_new(opts, :allowlist, @allowlist))
    errors
  end

  defp error_texts(spec, opts \\ []), do: spec |> errors(opts) |> Error.messages()

  defp minimal_spec do
    %{
      "resource" => "Minimal",
      "title" => "Minimal things",
      "components" => [
        %{"kind" => "table", "fields" => ["name"], "read_action" => "read"},
        %{"kind" => "form", "fields" => ["name"], "create_action" => "create"}
      ]
    }
  end

  describe "allowlist/1" do
    test "names resources by short module name" do
      assert @allowlist["Minimal"] == Minimal
      assert @allowlist["KitchenSink"] == KitchenSink
    end

    test "rejects non-resources" do
      assert_raise ArgumentError, ~r/not an Ash resource/, fn ->
        Dynamic.allowlist([Enum])
      end
    end

    test "accepts explicit naming maps and validates the names" do
      assert Dynamic.allowlist(%{"things" => Minimal}) == %{"things" => Minimal}

      assert_raise ArgumentError, ~r/must match/, fn ->
        Dynamic.allowlist(%{"no spaces" => Minimal})
      end
    end
  end

  describe "resolve/2 — happy path" do
    test "resolves a minimal spec into a served surface" do
      surface = resolve!(minimal_spec())

      assert surface.resource == Minimal
      assert surface.title == "Minimal things"
      assert surface.surface_id =~ ~r/^dyn_minimal_[0-9a-f]{8}$/
      assert surface.spec == minimal_spec()
    end

    test "generated surface ids are unique per resolve" do
      refute resolve!(minimal_spec()).surface_id == resolve!(minimal_spec()).surface_id
    end

    test "build_surface emits the schema-valid message triple" do
      Ash.create!(Minimal, %{name: "one"}, authorize?: false)

      messages = minimal_spec() |> resolve!() |> Dynamic.build_surface(authorize?: false)

      assert [%{"createSurface" => _}, %{"updateComponents" => _}, %{"updateDataModel" => _}] =
               messages

      Enum.each(messages, &assert_valid_server_message/1)

      [_create, _components, %{"updateDataModel" => %{"value" => data_model}}] = messages
      assert [%{"name" => "one"}] = data_model["records"]
    end

    test "build_data_model emits a schema-valid refresh" do
      message = minimal_spec() |> resolve!() |> Dynamic.build_data_model(authorize?: false)

      assert %{"updateDataModel" => _} = assert_valid_server_message(message)
    end

    test "omitted table fields are inferred from public attributes" do
      spec = %{"resource" => "Minimal", "components" => [%{"kind" => "table"}]}

      messages = spec |> resolve!() |> Dynamic.build_surface(authorize?: false)
      assert [%{"createSurface" => _} | _rest] = messages
    end

    test "a full spec exercises queries, presets, layouts, and actions" do
      spec = %{
        "resource" => "KitchenSink",
        "components" => [
          %{
            "kind" => "table",
            "fields" => ["name", "status", "count", "inserted_at"],
            "row_actions" => ["update", "destroy"],
            "query" => "default",
            "row_layout" => %{
              "title" => "name",
              "badge" => "status",
              "badge_text" => %{"draft" => "Draft"},
              "meta" => ["count", "inserted_at"],
              "columns" => 2
            }
          },
          %{
            "kind" => "form",
            "fields" => ["name", "status", "count"],
            "create_action" => "create",
            "update_action" => "update",
            "groups" => [
              %{
                "name" => "details",
                "label" => "Details",
                "columns" => 2,
                "fields" => ["status", "count"]
              }
            ]
          }
        ],
        "queries" => [
          %{
            "name" => "default",
            "search_fields" => ["name"],
            "sortable" => ["name", "inserted_at"],
            "filters" => ["status"],
            "default_sort" => [%{"field" => "inserted_at", "direction" => "desc"}],
            "presets" => [%{"name" => "drafts", "filter" => %{"status" => "draft"}}],
            "page_size" => 10
          }
        ],
        "fields" => [
          %{"name" => "inserted_at", "label" => "Created", "format" => "date"}
        ],
        "actions" => [
          %{
            "name" => "destroy",
            "refreshes" => ["table"],
            "visible_when" => %{"status" => "draft"}
          }
        ]
      }

      messages = spec |> resolve!() |> Dynamic.build_surface(authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)
    end

    test "contexts, context_filter, and detail components resolve and scope" do
      allowlist = Dynamic.allowlist([AshA2ui.Test.Appointment, AshA2ui.Test.Owner])

      owner = Ash.create!(AshA2ui.Test.Owner, %{name: "Ada", email: "ada@x"}, authorize?: false)

      Ash.create!(
        AshA2ui.Test.Appointment,
        %{title: "checkup", owner_id: owner.id},
        authorize?: false
      )

      spec = %{
        "resource" => "Appointment",
        "components" => [
          %{
            "kind" => "table",
            "fields" => ["title", "status"],
            "context_filter" => %{"owner_id" => "owner"},
            "require_context" => ["owner"]
          },
          %{"kind" => "detail", "context" => "owner", "fields" => ["name", "email"]}
        ],
        "contexts" => [
          %{"name" => "owner", "resource" => "Owner", "option_label" => "name"}
        ]
      }

      {:ok, surface} = Dynamic.resolve(spec, allowlist: allowlist)

      # Unscoped: require_context unmet, the table renders no records.
      messages = Dynamic.build_surface(surface, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)
      [_create, _components, %{"updateDataModel" => %{"value" => data_model}}] = messages
      assert data_model["records"] == []

      # Scoped to the selected owner, the appointment appears.
      scoped =
        Dynamic.build_surface(surface,
          authorize?: false,
          context_state: %{"owner" => %{"value" => owner.id}}
        )

      [_create, _components, %{"updateDataModel" => %{"value" => scoped_model}}] = scoped
      assert [%{"title" => "checkup"}] = scoped_model["records"]
      assert scoped_model["detail"]["owner"]["name"] == "Ada"
    end

    test "nested forms resolve, render, and submit through the dynamic surface" do
      allowlist = Dynamic.allowlist([AshA2ui.Test.Ticket, AshA2ui.Test.Author, AshA2ui.Test.Tag])

      spec = %{
        "resource" => "Ticket",
        "components" => [
          %{"kind" => "table", "fields" => ["subject"], "read_action" => "read"},
          %{
            "kind" => "form",
            "fields" => ["subject"],
            "create_action" => "create",
            "update_action" => "update",
            "nested_forms" => [
              %{"name" => "notes", "fields" => ["body", "rating"]},
              %{"name" => "tags"}
            ]
          }
        ]
      }

      surface = resolve!(spec, allowlist: allowlist)

      # the resolved view carries both nested forms with their modes
      view = ResolvedView.resolve(surface.dsl_state)
      assert %{notes: notes, tags: tags} = view.nested_forms
      assert notes.mode == :create_inline
      assert notes.fields == [:body, :rating]
      assert tags.mode == :pick_existing

      # the initial /form carries stable empty arrays for both arguments
      messages = Dynamic.build_surface(surface, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      [_create, _components, %{"updateDataModel" => %{"value" => data_model}}] = messages
      assert data_model["form"]["notes"] == []
      assert data_model["form"]["tags"] == []

      # submitting rows round-trips: create_inline maps survive, pick_existing
      # rows reduce to their picked ids (the manage_relationship inputs)
      envelope = %{
        "name" => "submit_form",
        "context" => %{
          "values" => %{
            "subject" => "nested round trip",
            "notes" => [%{"_row" => "r1", "body" => "first", "rating" => "2"}],
            "tags" => []
          }
        }
      }

      assert {:ok, messages} = Dynamic.handle_action(surface, envelope, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      [ticket] = Ash.read!(AshA2ui.Test.Ticket, authorize?: false)
      assert ticket.subject == "nested round trip"
    end

    test "sections resolve into a template and expand into per-section tables" do
      allowlist = Dynamic.allowlist([AshA2ui.Test.BucketWord, AshA2ui.Test.Bucket])

      bucket = Ash.create!(AshA2ui.Test.Bucket, %{name: "a3f4-9"}, authorize?: false)

      Ash.create!(
        AshA2ui.Test.BucketWord,
        %{word: "misspeld", replacement: "misspelled", bucket_id: bucket.id, state: :bucketed},
        authorize?: false
      )

      spec = %{
        "resource" => "BucketWord",
        "components" => [
          %{
            "kind" => "table",
            "name" => "per_bucket",
            "fields" => ["word", "replacement"],
            "read_action" => "bucketed",
            "sections" => %{
              "source" => "Bucket",
              "scope_by" => "bucket_id",
              "label" => "name",
              "sort" => "name"
            }
          }
        ]
      }

      surface = resolve!(spec, allowlist: allowlist)

      # the resolved view carries the template; the surface is multi-table
      # (even before expansion) so the scoped paths are stable
      view = ResolvedView.resolve(surface.dsl_state)
      assert view.sectioned?
      assert ResolvedView.multi_table?(view)

      # expansion yields one concrete table per bucket record under the
      # runtime name <template>_<sanitized value> (the value defaults to the
      # source's primary key), with scoped reads ANDed on
      messages = Dynamic.build_surface(surface, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      runtime_name = "per_bucket_#{String.replace(bucket.id, "-", "_")}"

      [_create, _components, %{"updateDataModel" => %{"value" => data_model}}] = messages
      assert [%{"word" => "misspeld"}] = data_model["records"][runtime_name]
    end

    test "a sections source outside the allowlist is rejected" do
      spec = %{
        "resource" => "BucketWord",
        "components" => [
          %{
            "kind" => "table",
            "sections" => %{"source" => "KitchenSink", "scope_by" => "bucket_id"}
          }
        ]
      }

      assert [text] = error_texts(spec, allowlist: Dynamic.allowlist([AshA2ui.Test.BucketWord]))
      assert text =~ ~s(resource "KitchenSink" is not available to dynamic surfaces)
    end

    test "a nested form argument without a manage_relationship change is rejected" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [
                   %{
                     "kind" => "form",
                     "fields" => ["name"],
                     "create_action" => "create",
                     "nested_forms" => [%{"name" => "bogus"}]
                   }
                 ]
               })

      assert text =~ "nested_form :bogus requires a manage_relationship change"
    end
  end

  describe "resolve/2 — encoding parity with an equivalent DSL surface" do
    test "a spec mirroring the KitchenSink DSL block encodes byte-identically" do
      Ash.create!(
        KitchenSink,
        %{name: "parity", active: true, count: 3, status: :published},
        authorize?: false
      )

      spec = %{
        "resource" => "KitchenSink",
        "components" => [
          %{
            "kind" => "table",
            "fields" => [
              "name",
              "active",
              "count",
              "price",
              "birthday",
              "scheduled_at",
              "status",
              "inserted_at"
            ],
            "read_action" => "read",
            "row_actions" => ["update", "destroy"]
          },
          %{
            "kind" => "form",
            "fields" => ["name", "active", "count", "price", "birthday", "scheduled_at", "status"],
            "create_action" => "create",
            "update_action" => "update"
          }
        ],
        "fields" => [
          %{"name" => "name", "label" => "Name", "widget" => "text_field", "order" => 1},
          %{"name" => "inserted_at", "label" => "Created", "format" => "date", "order" => 99},
          %{"name" => "updated_at", "hidden" => true}
        ]
      }

      surface = resolve!(spec, surface_id: "kitchen_sink")

      assert Dynamic.build_surface(surface, authorize?: false) ==
               AshA2ui.Info.build_surface(KitchenSink, authorize?: false)
    end
  end

  describe "resolve/2 — validation matrix" do
    test "rejects a resource outside the allowlist" do
      assert [%Error{path: "resource", message: message}] =
               errors(%{"resource" => "User", "components" => [%{"kind" => "table"}]})

      assert message =~ "not available to dynamic surfaces"
      assert message =~ "KitchenSink"
    end

    test "rejects a spec without components" do
      assert ["components: the spec must declare at least one component"] =
               error_texts(%{"resource" => "Minimal"})
    end

    test "rejects non-object specs and unknown top-level keys" do
      assert {:error, [%Error{message: "the surface spec must be a JSON object"}]} =
               Dynamic.resolve([], allowlist: @allowlist)

      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table"}],
                 "layout" => "wide"
               })

      assert text =~ ~s(unknown spec key "layout")
    end

    test "the spec linter reports EVERY unknown top-level key, not just the first" do
      assert [%Error{path: "layout", message: layout_message}, %Error{path: "theme"}] =
               errors(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table"}],
                 "theme" => "dark",
                 "layout" => "wide"
               })

      assert layout_message =~ ~s(unknown spec key "layout")
      assert layout_message =~ "resource, title, components, queries, fields, actions, contexts"

      # Unknown keys never reach the parsed entities: a spec that carries
      # ONLY unknown keys still fails with the linter's error (not a
      # missing-components error from silently dropping them).
      assert [%Error{path: "bogus"}] =
               errors(%{"resource" => "Minimal", "bogus" => true})
    end

    test "rejects components without a kind, or with an unsupported kind" do
      assert [text] = error_texts(%{"resource" => "Minimal", "components" => [%{}]})
      assert text =~ ~s(each component must declare a "kind")

      assert [text] =
               error_texts(%{"resource" => "Minimal", "components" => [%{"kind" => "chart"}]})

      assert text =~ "components[0].name"
      assert text =~ "expected one of [:table, :form, :detail, :report]"
    end

    test "rejects malformed names with the format rule" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table", "fields" => ["name; drop tables"]}]
               })

      assert text =~ "not a valid name"
    end

    test "rejects unknown fields with the verifier's field inventory" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table", "fields" => ["nonexistent"]}]
               })

      assert text =~ "a2ui.component.table.fields"
      assert text =~ "references unknown field :nonexistent"
      assert text =~ ":name"
    end

    test "rejects form fields the action does not accept" do
      assert [text] =
               error_texts(%{
                 "resource" => "KitchenSink",
                 "components" => [
                   %{"kind" => "form", "fields" => ["inserted_at"], "create_action" => "create"}
                 ]
               })

      assert text =~ "not accepted by its create/update action"
    end

    test "rejects mistyped and missing actions" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table", "read_action" => "create"}]
               })

      assert text =~ "read_action :create must be of type :read"

      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table", "row_actions" => ["explode"]}]
               })

      assert text =~ "row action :explode does not exist"
    end

    test "rejects query allowlist entries that are not public attributes" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table", "query" => "q"}],
                 "queries" => [%{"name" => "q", "sortable" => ["shoe_size"]}]
               })

      assert text =~ "references unknown field :shoe_size in sortable"
    end

    test "rejects presets declaring both filter and read_action" do
      assert [text] =
               error_texts(%{
                 "resource" => "KitchenSink",
                 "components" => [%{"kind" => "table", "query" => "q"}],
                 "queries" => [
                   %{
                     "name" => "q",
                     "presets" => [
                       %{
                         "name" => "both",
                         "filter" => %{"status" => "draft"},
                         "read_action" => "read"
                       }
                     ]
                   }
                 ]
               })

      assert text =~ "mutually exclusive"
    end

    test "rejects visible_when values that do not cast to the field's type" do
      assert [text] =
               error_texts(%{
                 "resource" => "KitchenSink",
                 "components" => [%{"kind" => "table", "row_actions" => ["destroy"]}],
                 "actions" => [
                   %{"name" => "destroy", "visible_when" => %{"status" => "not_a_status"}}
                 ]
               })

      assert text =~ "does not cast to the field's type"
    end

    test "rejects layout references outside the component's fields" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [
                   %{
                     "kind" => "table",
                     "fields" => ["name"],
                     "row_layout" => %{"title" => "id"}
                   }
                 ]
               })

      assert text =~ "row_layout references field :id"
    end

    test "rejects widgets and formats outside the encoder's vocabulary" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table"}],
                 "fields" => [%{"name" => "name", "widget" => "hologram"}]
               })

      assert text =~ ~s(widget "hologram" is not supported)
      assert text =~ "text_field"
    end

    test "rejects context resources outside the allowlist" do
      assert [text] =
               error_texts(%{
                 "resource" => "Minimal",
                 "components" => [%{"kind" => "table"}],
                 "contexts" => [%{"name" => "user", "resource" => "User"}]
               })

      assert text =~ ~s(resource "User" is not available)
    end

    test "collects several errors in one pass" do
      texts =
        error_texts(%{
          "resource" => "Minimal",
          "components" => [
            %{"kind" => "table", "fields" => ["bogus"], "read_action" => "create"}
          ]
        })

      assert Enum.any?(texts, &(&1 =~ "unknown field :bogus"))
      assert Enum.any?(texts, &(&1 =~ "read_action :create must be of type :read"))
    end

    test "errors are structured and JSON-encodable" do
      [error] = errors(%{"resource" => "Minimal"})

      assert %{"path" => "components", "message" => _} =
               error |> Jason.encode!() |> Jason.decode!()
    end
  end

  describe "handle_action/3 — round trip and tamper cases" do
    test "submit_form creates through the spec's create action and refreshes" do
      surface = resolve!(minimal_spec())

      envelope = %{
        "version" => "v0.9.1",
        "action" => %{
          "name" => "submit_form",
          "surfaceId" => surface.surface_id,
          "context" => %{"values" => %{"name" => "round-trip"}}
        }
      }

      assert {:ok, messages} = Dynamic.handle_action(surface, envelope, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      assert Enum.any?(messages, fn
               %{"updateDataModel" => %{"path" => "/records", "value" => records}} ->
                 Enum.any?(records, &(&1["name"] == "round-trip"))

               _other ->
                 false
             end)

      assert [%{name: "round-trip"}] = Ash.read!(Minimal, authorize?: false)
    end

    test "follow-up messages always carry the server-held surface id" do
      surface = resolve!(minimal_spec())

      envelope = %{
        "version" => "v0.9.1",
        "action" => %{
          "name" => "submit_form",
          # A tampering client claims another surface — it is ignored.
          "surfaceId" => "spoofed_surface",
          "context" => %{"values" => %{"name" => "own-id"}}
        }
      }

      {:ok, messages} = Dynamic.handle_action(surface, envelope, authorize?: false)

      for %{"updateDataModel" => %{"surfaceId" => id}} <- messages do
        assert id == surface.surface_id
      end
    end

    test "invoking an action outside the spec's row_actions is rejected" do
      record = Ash.create!(Minimal, %{name: "keep me"}, authorize?: false)
      surface = resolve!(minimal_spec())

      envelope = %{
        "name" => "invoke",
        "context" => %{"action" => "destroy", "recordId" => record.id}
      }

      assert {:error, [message]} = Dynamic.handle_action(surface, envelope, authorize?: false)

      assert %{
               "updateDataModel" => %{"path" => "/ui/feedback", "value" => %{"message" => status}}
             } = message

      assert status =~ "not listed in the view's row_actions"
      assert [_still_there] = Ash.read!(Minimal, authorize?: false)
    end

    test "query values outside the declared allowlist are rejected" do
      spec = %{
        "resource" => "KitchenSink",
        "components" => [%{"kind" => "table", "query" => "q"}],
        "queries" => [%{"name" => "q", "sortable" => ["name"]}]
      }

      surface = resolve!(spec)

      envelope = %{
        "name" => "query",
        "context" => %{"query" => %{"sort" => "count", "dir" => "asc"}}
      }

      assert {:error, [message]} = Dynamic.handle_action(surface, envelope, authorize?: false)

      assert %{
               "updateDataModel" => %{"path" => "/ui/feedback", "value" => %{"message" => status}}
             } = message

      assert status =~ "sort"
    end

    test "ash policies still gate dynamic surfaces (authorize?: true default)" do
      spec = %{
        "resource" => "Guarded",
        "components" => [
          %{"kind" => "table", "fields" => ["name", "status"]},
          %{"kind" => "form", "fields" => ["name"], "create_action" => "create"}
        ]
      }

      surface = resolve!(spec)

      envelope = %{
        "name" => "submit_form",
        "context" => %{"values" => %{"name" => "sneaky"}}
      }

      assert {:error, [message]} = Dynamic.handle_action(surface, envelope, [])

      assert %{
               "updateDataModel" => %{"path" => "/ui/feedback", "value" => %{"message" => status}}
             } = message

      assert status =~ "not authorized"
      assert [] = Ash.read!(Guarded, authorize?: false)

      assert {:ok, _messages} =
               Dynamic.handle_action(surface, envelope, actor: %{id: "admin"})

      assert [%{name: "sneaky"}] = Ash.read!(Guarded, authorize?: false)
    end

    test "validation errors map to /errors/<field> for the composer's form" do
      spec = %{
        "resource" => "KitchenSink",
        "components" => [
          %{"kind" => "table", "fields" => ["name"]},
          %{"kind" => "form", "fields" => ["name"], "create_action" => "create"}
        ]
      }

      surface = resolve!(spec)

      envelope = %{"name" => "submit_form", "context" => %{"values" => %{}}}

      assert {:error, messages} = Dynamic.handle_action(surface, envelope, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      assert Enum.any?(messages, fn
               %{"updateDataModel" => %{"path" => "/errors/name"}} -> true
               _other -> false
             end)
    end
  end

  describe "resolve/2 — via delegation (the RCE guard)" do
    defp via_spec(mfa, args) do
      %{
        "resource" => "Ticket",
        "components" => [
          %{
            "kind" => "table",
            "fields" => ["name", "status"],
            "read_action" => "read",
            "row_actions" => ["check_in"]
          }
        ],
        "actions" => [%{"name" => "check_in", "via" => %{"mfa" => mfa, "args" => args}}]
      }
    end

    @via_allowlist [AshA2ui.ActionHandlerTest.CheckInFacade]
    @ticket_allowlist Dynamic.allowlist([AshA2ui.ActionHandlerTest.Ticket])

    test "a delegate module outside :via_allowlist is rejected (default: all via)" do
      assert {:error, [%Error{path: "actions[0].via", message: message}]} =
               Dynamic.resolve(
                 via_spec("AshA2ui.ActionHandlerTest.CheckInFacade.complete/2", ["board"]),
                 allowlist: @ticket_allowlist
               )

      assert message =~ "not in the resolve's :via_allowlist"
      assert message =~ "host configuration"
    end

    test "an unknown module or function is rejected at resolve, never called" do
      assert {:error, errors} =
               Dynamic.resolve(via_spec("AshA2ui.DynamicTest.NoSuchModule.explode/1", []),
                 allowlist: @ticket_allowlist,
                 via_allowlist: [AshA2ui.DynamicTest.NoSuchModule]
               )

      assert Enum.any?(Error.messages(errors), &(&1 =~ "is not loaded"))

      assert {:error, errors} =
               Dynamic.resolve(via_spec("AshA2ui.ActionHandlerTest.CheckInFacade.missing/1", []),
                 allowlist: @ticket_allowlist,
                 via_allowlist: @via_allowlist
               )

      assert Enum.any?(Error.messages(errors), &(&1 =~ "missing/1 is not exported"))

      # a real exported function the host never sanctioned stays gated by the
      # allowlist (existence alone is not authorization)
      assert {:error, _errors} =
               Dynamic.resolve(via_spec("System.cmd/2", ["ls"]),
                 allowlist: @ticket_allowlist
               )
    end

    test "arity must equal 1 + length(args)" do
      assert {:error, errors} =
               Dynamic.resolve(via_spec("AshA2ui.ActionHandlerTest.CheckInFacade.complete/2", []),
                 allowlist: @ticket_allowlist,
                 via_allowlist: @via_allowlist
               )

      assert Enum.any?(Error.messages(errors), &(&1 =~ "arity must be 1 + length(args)"))
    end

    test "handle_action delegates an allowlisted via action exactly as declared surfaces do" do
      record =
        Ash.create!(AshA2ui.ActionHandlerTest.Ticket, %{name: "fresh"}, authorize?: false)

      surface =
        resolve!(via_spec("AshA2ui.ActionHandlerTest.CheckInFacade.complete/2", ["board"]),
          allowlist: @ticket_allowlist,
          via_allowlist: @via_allowlist
        )

      envelope = %{
        "name" => "invoke",
        "context" => %{"action" => "check_in", "recordId" => record.id}
      }

      assert {:ok, messages} = Dynamic.handle_action(surface, envelope, authorize?: false)
      Enum.each(messages, &assert_valid_server_message/1)

      # the delegate ran with the dispatch context and its declared extra arg
      assert %{context: context, source: source} =
               Process.get({AshA2ui.ActionHandlerTest.CheckInFacade, :last_call})

      assert context.action == :check_in
      assert context.record.id == record.id
      assert source == "board"

      # and the delegate's own Ash invocation did the work
      assert %{status: "checked_in"} =
               Ash.get!(AshA2ui.ActionHandlerTest.Ticket, record.id, authorize?: false)
    end
  end

  describe "spec_schema/1" do
    test "is a resolvable JSON Schema that accepts valid and rejects invalid specs" do
      schema = @allowlist |> Dynamic.spec_schema() |> ExJsonSchema.Schema.resolve()

      assert ExJsonSchema.Validator.valid?(schema, minimal_spec())

      refute ExJsonSchema.Validator.valid?(schema, %{"resource" => "Minimal"})

      refute ExJsonSchema.Validator.valid?(schema, %{
               "resource" => "Minimal",
               "components" => [%{"kind" => "chart"}]
             })
    end

    test "constrains resource enums to the allowlist" do
      schema = Dynamic.spec_schema(@allowlist)

      assert schema["properties"]["resource"]["enum"] == ["Guarded", "KitchenSink", "Minimal"]
    end
  end

  describe "describe_resources/1" do
    test "describes fields, enums, actions, and relationships" do
      [description] = Dynamic.describe_resources(Dynamic.allowlist([KitchenSink]))

      assert description["resource"] == "KitchenSink"

      status = Enum.find(description["attributes"], &(&1["name"] == "status"))
      assert status["one_of"] == ["draft", "published", "archived"]

      create = Enum.find(description["actions"], &(&1["name"] == "create"))
      assert create["type"] == "create"
      assert "name" in create["accepts"]

      assert description |> Jason.encode!() |> is_binary()
    end
  end
end
