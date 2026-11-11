defmodule AshA2ui.JsHooksTest do
  use ExUnit.Case, async: true

  # priv/js/hooks.js is the machine-readable export of this package's
  # LiveView hooks: each entry maps the hook's registered name to
  # `{events, load}`, where `events` names every event the hook passes to
  # `handleEvent` (a host that loads the hook lazily subscribes to these
  # before the code arrives). This test parses the JS with regexes — string
  # literals and `const NAME = "..."` constants — and fails when the
  # declared `events` drift from the hook sources: an event handled but not
  # declared, declared but never handled, or a `load` pointing at a file
  # that does not exist.
  @js_dir Path.expand("../priv/js", __DIR__)
  @hook_entry_re ~r/^  (\w+): \{$/
  @hook_end_re ~r/^  \},?$/
  @events_re ~r/events:\s*\[([^\]]*)\]/
  @import_re ~r/import\("([^"]+)"\)/
  @string_re ~r/"([^"]+)"|'([^']+)'/
  @handle_event_re ~r/handleEvent\(\s*("[^"]*"|'[^']*'|[A-Za-z_$][A-Za-z0-9_$]*)/
  @const_re ~r/^const\s+(\w+)\s*=\s*("[^"]*"|'[^']*')/m

  test "hooks.js declares exactly the events each hook handles" do
    hooks = hook_blocks!(hooks_source())

    assert hooks != %{}, "parsed no hook entries from priv/js/hooks.js"

    for {name, block} <- hooks do
      declared = declared_events!(name, block)
      paths = import_paths!(name, block)

      for path <- paths do
        assert File.exists?(Path.join(@js_dir, path)),
               "hooks.js: #{name}'s load imports #{inspect(path)}, which does not exist"
      end

      handled = handled_events(name, paths)

      assert MapSet.new(declared) == MapSet.new(handled),
             "hooks.js drift for #{name}: declared but not handled " <>
               "#{inspect(declared -- handled)}, handled but not declared " <>
               "#{inspect(handled -- declared)}"
    end
  end

  defp hooks_source, do: File.read!(Path.join(@js_dir, "hooks.js"))

  # Each entry in hooks.js is a two-space indented `Name: {` closed by `},`.
  defp hook_blocks!(source) do
    {blocks, unterminated} =
      Enum.reduce(String.split(source, "\n"), {%{}, nil}, fn
        line, {acc, nil} = state ->
          case Regex.run(@hook_entry_re, line, capture: :all_but_first) do
            [name] -> {Map.put(acc, name, ""), name}
            nil -> state
          end

        line, {acc, name} ->
          if Regex.match?(@hook_end_re, line) do
            {acc, nil}
          else
            {Map.update!(acc, name, &(&1 <> line <> "\n")), name}
          end
      end)

    assert is_nil(unterminated),
           "hooks.js: entry #{inspect(unterminated)} is never closed by `},`"

    blocks
  end

  defp declared_events!(name, block) do
    case Regex.run(@events_re, block, capture: :all_but_first) do
      [inner] -> string_literals!(inner)
      nil -> flunk("hooks.js: #{name} has no `events: [...]` array")
    end
  end

  defp import_paths!(name, block) do
    case Regex.scan(@import_re, block, capture: :all_but_first) do
      [] -> flunk("hooks.js: #{name}'s load has no import(\"./...\") call")
      paths -> Enum.map(paths, &hd/1) |> Enum.uniq()
    end
  end

  # Every `handleEvent(` first argument in the hook's sources: a string
  # literal, or a `const NAME = "..."` string in the same file.
  defp handled_events(name, paths) do
    Enum.flat_map(paths, fn path ->
      source = File.read!(Path.join(@js_dir, path))
      consts = const_map(source)

      Regex.scan(@handle_event_re, source, capture: :all_but_first)
      |> Enum.map(&event_name!(name, path, &1, consts))
      |> Enum.uniq()
    end)
    |> Enum.uniq()
  end

  defp event_name!(name, path, [arg], consts) do
    cond do
      String.match?(arg, ~r/^["']/) ->
        unquote_string(arg)

      Map.has_key?(consts, arg) ->
        Map.fetch!(consts, arg)

      true ->
        flunk(
          "hooks.js: #{name}'s #{path} calls handleEvent(#{arg}), which is " <>
            "neither a string literal nor a `const` string in that file"
        )
    end
  end

  defp const_map(source) do
    Regex.scan(@const_re, source, capture: :all_but_first)
    |> Map.new(fn [name, literal] -> {name, unquote_string(literal)} end)
  end

  defp string_literals!(inner) do
    # The capture group is the content between the quotes, not the literal:
    Enum.map(Regex.scan(@string_re, inner, capture: :all_but_first), &hd/1)
  end

  # A quoted literal, `"..."` or `'...'`:
  defp unquote_string(literal) do
    binary_part(literal, 1, byte_size(literal) - 2)
  end
end
