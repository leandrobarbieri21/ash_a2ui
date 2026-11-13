defmodule AshA2ui.Export do
  @moduledoc """
  Target struct for the `export` DSL entity (CSV file export): declares that
  a `:table` or `:report` component offers a server-generated CSV download,
  delivered as a `callRendererFunction` to the ash_a2ui catalog's
  `downloadFile` function (the shipped hook implements it).

  ## The `downloadFile` wire contract

  A successful `"export"` action emits one `callRendererFunction` message
  (built by `AshA2ui.Encoder.call_renderer_function/4`):

      {
        "version": "1.0",
        "callRendererFunction": {
          "surfaceId": "words",
          "functionCallId": "fc_…",
          "callFunction": {
            "@call": "downloadFile",
            "catalogId": "https://github.com/lukegalea/ash_a2ui/catalogs/ash_a2ui/v1",
            "args": {
              "filename": "misspellings.csv",
              "mimeType": "text/csv",
              "dataUrl": "data:text/csv;base64,…"
            }
          }
        }
      }

  The renderer function triggers a browser download of `dataUrl` (a hook may
  instead receive a `"url"` arg — a signed one-time URL — for hosts that
  upload instead of inlining; the built-in prefers `dataUrl` and falls back
  to `url`). The renderer answers with a `rendererFunctionResponse`.

  See the `export` entity docs on `AshA2ui` for the DSL options.
  """

  defstruct [
    :filename,
    :columns,
    column_select: false,
    limit: 10_000,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          filename: String.t() | nil,
          columns: [atom] | nil,
          column_select: boolean,
          limit: pos_integer
        }
end
