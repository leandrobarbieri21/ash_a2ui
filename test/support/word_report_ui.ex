defmodule AshA2ui.Test.WordReportUI do
  @moduledoc """
  Fixture surface for aggregate/report queries (v0.9.1): a single `:report`
  component running the `:length_report` generic action of
  `AshA2ui.Test.BucketWord` with a `min_length` param — computed rows, not
  resource records.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "word_report"

    component :report, :lengths do
      action :length_report
      params [:min_length]
      fields [:word, :length, :state]
    end
  end
end

defmodule AshA2ui.Test.WordReportV1UI do
  @moduledoc """
  The same report fixture surface as `AshA2ui.Test.WordReportUI`, but with
  `spec_version "1.0"` — validates report surfaces against the v1.0 schemas
  and the structured `/ui/response` + actionResponse result path. Also the
  column-selectable CSV-export proving case (`export` with `column_select`).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "word_report_v1"
    spec_version "1.0"

    component :report, :lengths do
      action :length_report
      params [:min_length]
      fields [:word, :length, :state]

      export do
        filename "word_lengths.csv"
        column_select true
      end
    end
  end
end

defmodule AshA2ui.Test.ExportWordsV1UI do
  @moduledoc """
  Fixture surface for table CSV export (v1.0): a single queried table over
  `AshA2ui.Test.BucketWord` with a plain (no column selection) `export`
  block — the export honors the carried query state but ignores the
  on-screen page.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "export_words_v1"
    spec_version "1.0"

    query :words do
      search_fields [:word]
      page_size 2
    end

    component :table do
      fields [:word, :replacement]
      query :words

      export do
        limit 100
      end
    end
  end
end

defmodule AshA2ui.Test.ExportAppointmentsV1UI do
  @moduledoc """
  Fixture surface for table CSV export of an enum column (v1.0): the table
  renders `status` as its label, the export keeps the stored value.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Appointment
    surface_id "export_appointments_v1"
    spec_version "1.0"

    component :table do
      fields [:title, :status]

      export do
        limit 100
      end
    end
  end
end
