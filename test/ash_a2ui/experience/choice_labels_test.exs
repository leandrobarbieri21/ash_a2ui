defmodule AshA2ui.Experience.ChoiceLabelsTest do
  @moduledoc """
  A field's choices read the same way everywhere on the surface.

  `choice_options/2` has always labelled enum values for form pickers, so a
  select showed "Direct user and team". The grid beside it showed
  `direct_user_and_team`, because a record's value reached the wire as its bare
  atom name. One field, one surface, two vocabularies — and the raw one is the
  one a reader has to decode.

  The interesting case is not the happy path (the golden payloads in
  `encoder_test.exs` and `multi_table_test.exs` pin that). It is the values the
  field does *not* declare: those must pass through untouched rather than be
  rewritten by a guess, because a surface can carry strings that merely look
  like choices.
  """

  use ExUnit.Case, async: false

  alias AshA2ui.Encoder
  alias AshA2ui.ResolvedView
  alias AshA2ui.Test.KitchenSink

  defp records!(record) do
    view = ResolvedView.resolve(KitchenSink)
    message = Encoder.encode_data_model(view, [record], [])
    message["updateDataModel"]["value"]["records"]
  end

  test "a declared enum value is labelled" do
    [row] = records!(%KitchenSink{id: "1", name: "A", status: :published})

    assert row["status"] == "Published"
  end

  test "a free-text field whose value resembles a choice is left alone" do
    # `name` is a plain string. If labelling keyed off the shape of the value
    # rather than off the field's declared choices, this would come back
    # "Under review" — rewriting content the user typed.
    [row] = records!(%KitchenSink{id: "1", name: "under_review", status: :draft})

    assert row["name"] == "under_review"
    assert row["status"] == "Draft"
  end

  test "a nil choice stays nil rather than becoming a label" do
    [row] = records!(%KitchenSink{id: "1", name: "A", status: nil})

    assert row["status"] == nil
  end
end
