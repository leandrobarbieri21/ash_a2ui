defmodule AshA2ui.Adoption.ErrorFeedbackTest do
  @moduledoc """
  Errors without a field reach the typed `/ui/feedback` as readable
  sentences, not "Request failed: …" (an Ash error class's first message
  line, often blank) or a bare "Validation failed…" that points at fields
  nobody can see:

    * `Ash.Error.Forbidden` → a not-authorized sentence;
    * an invalid error without a field → its message(s);
    * a plain string from a host `via` function → its text;
    * a raw (non-Ash) exception — from a change, a `via` function or the
      data layer — can carry row values: it reads as "The action failed."
      and its text is only logged;
    * field errors stay on `/errors/<field>`; those on fields the action
      does not show (an invoke without prompt fields, a form without an
      input for the field) are also named in the feedback.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Adoption.{Job, JobsUI, LeakyJobsUI, ViaJobsUI}

  @red %{id: "u-red", team: "red"}

  setup do
    Job |> Ash.read!(actor: @red) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    %{job: Ash.create!(Job, %{title: "Open job", team: "red"}, authorize?: false)}
  end

  defp invoke(ui, surface_id, action, job, values \\ nil) do
    context =
      %{"action" => to_string(action), "recordId" => job.id, "component" => "table"}
      |> then(&if(values, do: Map.put(&1, "values", values), else: &1))

    ActionHandler.handle(
      ui,
      %{
        "version" => "v0.9.1",
        "action" => %{
          "name" => "invoke",
          "surfaceId" => surface_id,
          "sourceComponentId" => "test",
          "timestamp" => "2026-10-16T00:00:00Z",
          "context" => context
        }
      },
      actor: @red
    )
  end

  defp write_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  test "an invalid error without a field reads as its message", %{job: job} do
    assert {:error, messages} = invoke(JobsUI, "adoption_jobs", :lock, job)

    assert write_at(messages, "/ui/feedback") == %{
             "kind" => "error",
             "message" => "This job is locked by another team."
           }

    refute Enum.any?(messages, &match?(%{"updateDataModel" => %{"path" => "/errors/" <> _}}, &1))
  end

  test "a forbidden action reads as not authorized", %{job: job} do
    assert {:error, messages} = invoke(JobsUI, "adoption_jobs", :escalate, job)

    assert write_at(messages, "/ui/feedback") == %{
             "kind" => "error",
             "message" => "You are not authorized to perform this action."
           }
  end

  test "a host function's string refusal reads as the string", %{job: job} do
    assert {:error, messages} = invoke(ViaJobsUI, "adoption_via_jobs", :claim, job)

    assert write_at(messages, "/ui/feedback")["message"] ==
             "Only the holder can complete this task."
  end

  test "a prompt field error stays on its field", %{job: job} do
    assert {:error, messages} =
             invoke(JobsUI, "adoption_jobs", :annotate, job, %{"note" => ""})

    assert write_at(messages, "/errors/note") =~ "required"

    assert write_at(messages, "/ui/feedback") == %{
             "kind" => "error",
             "message" => "Validation failed. Please review the field errors."
           }
  end

  test "a raw exception from a change reads as a generic sentence, not its text", %{job: job} do
    log =
      capture_log(fn ->
        assert {:error, messages} = invoke(LeakyJobsUI, "adoption_leaky_jobs", :explode, job)
        send(self(), {:messages, messages})
      end)

    assert_received {:messages, messages}

    assert write_at(messages, "/ui/feedback") == %{
             "kind" => "error",
             "message" => "The action failed."
           }

    refute inspect(messages) =~ "alice@example.com"
    refute inspect(messages) =~ "23505"
    assert log =~ "alice@example.com"
  end

  test "a raw exception from a host function reads as a generic sentence", %{job: job} do
    log =
      capture_log(fn ->
        assert {:error, messages} = invoke(LeakyJobsUI, "adoption_leaky_jobs", :claim, job)
        send(self(), {:messages, messages})
      end)

    assert_received {:messages, messages}
    assert write_at(messages, "/ui/feedback")["message"] == "The action failed."
    refute inspect(messages) =~ "bob@example.com"
    assert log =~ "bob@example.com"
  end

  test "a form's error on a field it shows no input for is named in the feedback" do
    assert {:error, messages} =
             ActionHandler.handle(
               JobsUI,
               %{
                 "version" => "v0.9.1",
                 "action" => %{
                   "name" => "submit_form",
                   "surfaceId" => "adoption_jobs",
                   "sourceComponentId" => "test",
                   "timestamp" => "2026-10-16T00:00:00Z",
                   "context" => %{"values" => %{"title" => "New job"}}
                 }
               },
               actor: @red
             )

    team_error = write_at(messages, "/errors/team")
    assert is_binary(team_error)
    assert write_at(messages, "/ui/feedback")["message"] == "Team: #{team_error}."
  end

  test "a form's error on a field it shows stays on the field" do
    assert {:error, messages} =
             ActionHandler.handle(
               JobsUI,
               %{
                 "version" => "v0.9.1",
                 "action" => %{
                   "name" => "submit_form",
                   "surfaceId" => "adoption_jobs",
                   "sourceComponentId" => "test",
                   "timestamp" => "2026-10-16T00:00:00Z",
                   "context" => %{"values" => %{"team" => "red"}}
                 }
               },
               actor: @red
             )

    assert is_binary(write_at(messages, "/errors/title"))

    assert write_at(messages, "/ui/feedback")["message"] ==
             "Validation failed. Please review the field errors."
  end

  test "a field error no input shows is named in the feedback", %{job: job} do
    assert {:error, messages} = invoke(JobsUI, "adoption_jobs", :finish, job)

    status_error = write_at(messages, "/errors/status")
    assert is_binary(status_error)
    assert write_at(messages, "/ui/feedback")["message"] == "Status: #{status_error}."
  end
end
