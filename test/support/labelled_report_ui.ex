defmodule AshA2ui.Test.LabelledReportUI do
  @moduledoc """
  Fixture surface for declared report labels (v1.0): the same
  `:length_report` report as `AshA2ui.Test.WordReportV1UI`, with `field`
  overrides naming a report param (`:min_length`) and a row key (`:length`)
  that are not fields of `AshA2ui.Test.BucketWord`.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "labelled_report"

    component :report, :lengths do
      action :length_report
      params [:min_length]
      fields [:word, :length, :state]

      export do
        column_select true
      end
    end

    field :min_length do
      label "Minimum length"
    end

    field :length do
      label "Letters"
    end
  end
end
