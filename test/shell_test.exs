defmodule AshA2ui.ShellTest do
  use ExUnit.Case, async: true

  alias AshA2ui.Shell

  @calendar %{
    "id" => "calendar",
    "title" => "Calendar",
    "group" => "My day",
    "description" => "Your events"
  }
  @people %{
    "id" => "people",
    "title" => "People",
    "group" => "My day",
    "description" => "The directory"
  }
  @time_travel %{"id" => "time_travel", "title" => "Time travel", "group" => "Master data"}
  @agent %{"id" => "agent", "title" => "Agent", "group" => "My day", "description" => "Ask"}
  @action_items %{"id" => "action_items", "title" => "Action items", "group" => "My day"}

  @agenda %{
    "name" => "calendar",
    "description" => "Agenda for a window",
    "input" => %{"hint" => "today | tomorrow | week"}
  }
  @help %{"name" => "help", "description" => "This list"}
  @brief %{"name" => "compose brief", "description" => "Compose today's brief"}

  @entries %{
    commands: [@agenda, @help, @brief],
    surfaces: [@calendar, @people, @time_travel, @agent, @action_items]
  }

  describe "keys" do
    test "ctrl+p is the palette and ctrl+k the launcher" do
      assert Shell.keys() == %{"ctrl+p" => :palette, "ctrl+k" => :launcher}
      assert Shell.key_for(:launcher) == "ctrl+k"
    end
  end

  describe "route/2" do
    test "a blank line routes nowhere" do
      assert Shell.route("   ", @entries) == nil
      assert Shell.route("/", @entries) == nil
    end

    test "a line without a slash is a prompt for the agent" do
      assert Shell.route("  what is on today ", @entries) == {:prompt, "what is on today"}
    end

    test "/open names a surface by id, title or a unique prefix" do
      assert Shell.route("/open calendar", @entries) == {:open_surface, @calendar, nil}
      assert Shell.route("/open Time travel", @entries) == {:open_surface, @time_travel, nil}
      assert Shell.route("/open time_travel", @entries) == {:open_surface, @time_travel, nil}
      assert Shell.route("/open peo", @entries) == {:open_surface, @people, nil}
      assert Shell.route("/OPEN action-items", @entries) == {:open_surface, @action_items, nil}
    end

    test "/open takes a row number or a record id" do
      assert Shell.route("/open people 3", @entries) == {:open_surface, @people, {:nth, 3}}

      assert Shell.route("/open people abc-1", @entries) ==
               {:open_surface, @people, {:record, "abc-1"}}

      assert Shell.route("/open time travel 2", @entries) ==
               {:open_surface, @time_travel, {:nth, 2}}
    end

    test "/open and /home with nothing else open the launcher" do
      assert Shell.route("/open", @entries) == :launcher
      assert Shell.route("/home", @entries) == :launcher
    end

    test "an ambiguous or unknown surface is an error, not a guess" do
      assert {:error, message} = Shell.route("/open a", @entries)
      assert message =~ "There is no a surface"
      assert {:error, _} = Shell.route("/open nowhere", @entries)
      assert {:error, _} = Shell.route("/open people 1 2", @entries)
    end

    test "a command's name runs it, with the rest as arguments" do
      assert Shell.route("/calendar week", @entries) == {:command, @agenda, ["week"]}
      assert Shell.route("/help", @entries) == {:command, @help, []}
      # Multi-word names match whole, the longest first.
      assert Shell.route("/compose brief", @entries) == {:command, @brief, []}
    end

    test "a surface named directly opens it" do
      assert Shell.route("/agent", @entries) == {:open_surface, @agent, nil}
      assert Shell.route("/people 2", @entries) == {:open_surface, @people, {:nth, 2}}
    end

    test "anything else after a slash says so" do
      assert {:error, message} = Shell.route("/frobnicate", @entries)
      assert message =~ "/frobnicate"
    end

    test "nothing is offered that the entries do not list" do
      assert {:error, _} = Shell.route("/open calendar", %{commands: [], surfaces: [@people]})
      assert {:error, _} = Shell.route("/calendar", %{commands: [], surfaces: []})
    end
  end

  describe "items/3" do
    test "the launcher lists the surfaces, filtered and grouped" do
      assert [
               %{
                 label: "Calendar",
                 group: "My day",
                 action: {:invoke, {:open_surface, @calendar, nil}}
               }
             ] =
               Shell.items(:launcher, "events", @entries)

      assert length(Shell.items(:launcher, "", @entries)) == 5
    end

    test "an empty palette leads with the launcher, then commands, then surfaces" do
      [launcher | rest] = Shell.items(:palette, "", @entries)
      assert launcher.action == {:mode, :launcher}
      assert launcher.hint == "ctrl+k"

      assert Enum.map(rest, & &1.label) ==
               ~w(/calendar /help) ++
                 ["/compose brief"] ++
                 ["Calendar", "People", "Time travel", "Agent", "Action items"]
    end

    test "a command that takes an argument is completed, not run" do
      assert [
               %{
                 label: "/calendar",
                 action: {:complete, "/calendar "},
                 hint: "today | tomorrow | week"
               }
               | _
             ] =
               Shell.items(:palette, "agenda", @entries)

      assert [%{action: {:invoke, {:command, @help, []}}} | _] =
               Shell.items(:palette, "help", @entries)
    end

    test "typed text always ends with asking the agent" do
      items = Shell.items(:palette, "what is on today", @entries)

      assert List.last(items) == %{
               label: "Ask the agent",
               detail: "what is on today",
               group: "Agent",
               action: {:invoke, {:prompt, "what is on today"}}
             }
    end

    test "a slash line leads with what it runs, then completions" do
      assert [
               %{
                 group: "Run",
                 action: {:invoke, {:open_surface, @calendar, nil}},
                 label: "Open Calendar"
               }
               | _
             ] =
               Shell.items(:palette, "/open calendar", @entries)

      [run | completions] = Shell.items(:palette, "/cal", @entries)
      assert run.action == {:invoke, {:open_surface, @calendar, nil}}
      assert Enum.any?(completions, &(&1.action == {:complete, "/calendar "}))

      assert [%{label: "/open", action: {:complete, "/open "}} | _] =
               Shell.items(:palette, "/op", @entries) |> Enum.drop_while(&(&1.group == "Run"))
    end

    test "an unknown slash line explains itself and runs nothing" do
      assert [%{action: :none, label: label}] = Shell.items(:palette, "/frobnicate", @entries)
      assert label =~ "ctrl+p"
    end
  end
end
