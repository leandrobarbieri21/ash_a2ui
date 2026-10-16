defmodule AshA2ui.Adoption.ErrorFeedbackTest do
  @moduledoc """
  Errors without a field reach the typed `/ui/feedback` as readable
  sentences, not "Request failed: …" (an Ash error class's first message
  line, often blank) or a bare "Validation failed…" that points at fields
  nobody can see:

    * `Ash.Error.Forbidden` → a not-authorized sentence;
    * an invalid error without a field → its message(s);
    * a plain string or exception from a host `via` function → its text;
    * field errors stay on `/errors/<field>`; those on fields the action
      does not show (an invoke without prompt fields) are also named in
      the feedback.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.ActionHandler
  alias AshA2ui.Test.Adoption.{Job, JobsUI, ViaJobsUI}

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

  test "a field error no input shows is named in the feedback", %{job: job} do
    assert {:error, messages} = invoke(JobsUI, "adoption_jobs", :finish, job)

    status_error = write_at(messages, "/errors/status")
    assert is_binary(status_error)
    assert write_at(messages, "/ui/feedback")["message"] == "Status: #{status_error}."
  end
end
