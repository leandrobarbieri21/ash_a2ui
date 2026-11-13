defmodule AshA2ui.TypeMapperTest do
  @moduledoc """
  The Ash type -> default widget table implemented by `AshA2ui.TypeMapper`.

  Widget atoms map to basic-catalog component names in the encoder
  (`AshA2ui.Encoder`), not here.
  """

  use ExUnit.Case, async: true

  alias AshA2ui.TypeMapper

  test "string types map to :text_field" do
    assert TypeMapper.widget_for(Ash.Type.String) == :text_field
    assert TypeMapper.widget_for(Ash.Type.CiString) == :text_field
  end

  test "boolean maps to :check_box" do
    assert TypeMapper.widget_for(Ash.Type.Boolean) == :check_box
  end

  test "numeric types map to :text_field (numeric keyboard hint is the encoder's job)" do
    assert TypeMapper.widget_for(Ash.Type.Integer) == :text_field
    assert TypeMapper.widget_for(Ash.Type.Decimal) == :text_field
    assert TypeMapper.widget_for(Ash.Type.Float) == :text_field
  end

  test "date and datetime types map to :date_time_input" do
    assert TypeMapper.widget_for(Ash.Type.Date) == :date_time_input
    assert TypeMapper.widget_for(Ash.Type.UtcDatetime) == :date_time_input
    assert TypeMapper.widget_for(Ash.Type.UtcDatetimeUsec) == :date_time_input
    assert TypeMapper.widget_for(Ash.Type.NaiveDatetime) == :date_time_input
  end

  test "atom with one_of constraints maps to :choice_picker" do
    assert TypeMapper.widget_for(Ash.Type.Atom, one_of: [:draft, :published]) == :choice_picker
  end

  test "atom without one_of constraints falls back to :text_field" do
    assert TypeMapper.widget_for(Ash.Type.Atom) == :text_field
    assert TypeMapper.widget_for(Ash.Type.Atom, unsafe_to_atom?: true) == :text_field
  end

  test "builtin type aliases resolve like their type modules" do
    assert TypeMapper.widget_for(:string) == :text_field
    assert TypeMapper.widget_for(:boolean) == :check_box
    assert TypeMapper.widget_for(:date) == :date_time_input
    assert TypeMapper.widget_for(:atom, one_of: [:a, :b]) == :choice_picker
  end

  test "unknown types fall back to :text_field" do
    assert TypeMapper.widget_for(Ash.Type.Map) == :text_field
    assert TypeMapper.widget_for(SomeModuleThatIsNotAType) == :text_field
  end
end
