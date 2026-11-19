# Records the document-pane probe fixtures (synthetic data only):
#
#     MIX_ENV=test mix run priv/js/probe/record_document.exs
#
# (run against a fresh test build — the fixtures live in private ETS, so
# every record and reply is made in this one process).
#
# Writes:
#
#   * fixtures/document_referral.pdf — a two-page, tagged PDF (US Letter,
#     Helvetica): each line of text is a marked-content sequence under a
#     StructTreeRoot (H1 and P), so a screen reader has its structure. Its
#     words sit under the regions VisitDocumentUI's fixture cites.
#   * fixtures/document_admin_payload.json — VisitDocumentUI under admin_v1,
#     the pane hidden, its document pointed at the PDF above.
#   * fixtures/document_shown_payload.json — the same, the pane open (the
#     address's ?document=shown).

alias AshA2ui.Test.{Appointment, Clinic, Owner, VisitDocumentUI}

out = "priv/js/probe/fixtures"

# --- the PDF ---------------------------------------------------------------

# Lines as {page, x, baseline from the page's top, font size, structure, text}.
lines = [
  {1, 61.2, 175, 14, "H1", "Referral for Checkup"},
  {1, 61.2, 220, 12, "P", "Reason for visit: annual checkup, no concerns reported."},
  {2, 306.0, 329, 12, "P", "Status: scheduled"},
  {2, 61.2, 400, 12, "P", "The clinic confirms the visit on the stamp below."},
  {2, 428.4, 700, 12, "P", "Clinic stamp"}
]

escape = fn text -> text |> String.replace("\\", "\\\\") |> String.replace("(", "\\(") |> String.replace(")", "\\)") end

contents =
  for page <- [1, 2] do
    lines
    |> Enum.filter(&(elem(&1, 0) == page))
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {{_page, x, baseline, size, tag, text}, mcid} ->
      "/#{tag} <</MCID #{mcid}>> BDC BT /F1 #{size} Tf #{x} #{792 - baseline} Td (#{escape.(text)}) Tj ET EMC"
    end)
  end

# Struct elements: objects 11.. in line order, each with its page's MCID.
{elems, _} =
  Enum.map_reduce(lines, %{1 => 0, 2 => 0}, fn {page, _x, _b, _s, tag, _text}, mcids ->
    {{page, tag, mcids[page]}, Map.update!(mcids, page, &(&1 + 1))}
  end)

elem_ids = Enum.map(Enum.with_index(elems), fn {_e, i} -> 11 + i end)
page_obj = %{1 => 3, 2 => 4}

parent_tree =
  for page <- [1, 2] do
    refs =
      elems
      |> Enum.zip(elem_ids)
      |> Enum.filter(fn {{p, _t, _m}, _id} -> p == page end)
      |> Enum.map_join(" ", fn {_e, id} -> "#{id} 0 R" end)

    "#{page - 1} [#{refs}]"
  end

objects =
  [
    "<< /Type /Catalog /Pages 2 0 R /MarkInfo << /Marked true >> /StructTreeRoot 8 0 R /Lang (en-US) >>",
    "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R /StructParents 0 /Resources << /Font << /F1 7 0 R >> >> >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R /StructParents 1 /Resources << /Font << /F1 7 0 R >> >> >>"
  ] ++
    Enum.map(contents, &"<< /Length #{byte_size(&1)} >>\nstream\n#{&1}\nendstream") ++
    [
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
      "<< /Type /StructTreeRoot /K 9 0 R /ParentTree 10 0 R /ParentTreeNextKey 2 >>",
      "<< /Type /StructElem /S /Document /P 8 0 R /K [#{Enum.map_join(elem_ids, " ", &"#{&1} 0 R")}] >>",
      "<< /Nums [#{Enum.join(parent_tree, " ")}] >>"
    ] ++
    Enum.map(elems, fn {page, tag, mcid} ->
      "<< /Type /StructElem /S /#{tag} /P 9 0 R /Pg #{page_obj[page]} 0 R /K #{mcid} >>"
    end)

{body, offsets} =
  objects
  |> Enum.with_index(1)
  |> Enum.reduce({"%PDF-1.7\n", []}, fn {object, number}, {pdf, offsets} ->
    {pdf <> "#{number} 0 obj\n#{object}\nendobj\n", [byte_size(pdf) | offsets]}
  end)

xref = byte_size(body)
count = length(objects) + 1

pdf =
  body <>
    "xref\n0 #{count}\n0000000000 65535 f \n" <>
    Enum.map_join(Enum.reverse(offsets), "", &(String.pad_leading("#{&1}", 10, "0") <> " 00000 n \n")) <>
    "trailer\n<< /Size #{count} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"

File.write!(Path.join(out, "document_referral.pdf"), pdf)

# --- the payloads ------------------------------------------------------------

owner = Ash.create!(Owner, %{name: "Ada", email: "ada@example.com"}, authorize?: false)
clinic = Ash.create!(Clinic, %{name: "North"}, authorize?: false)

visit =
  Ash.create!(
    Appointment,
    %{title: "Checkup", status: :scheduled, owner_id: owner.id, clinic_id: clinic.id},
    authorize?: false
  )

context = %{"appointment" => %{"search" => "", "value" => visit.id, "label" => "Checkup"}}

# The probe serves the PDF beside the page.
local = fn [message] ->
  [
    put_in(
      message,
      ["createSurface", "dataModel", "detail", "appointment", "_document_referral", "src"],
      "./fixtures/document_referral.pdf"
    )
  ]
end

write = fn name, messages -> File.write!(Path.join(out, name), Jason.encode!(%{messages: messages})) end

Application.put_env(:ash_a2ui, :catalog, :admin_v1)

write.(
  "document_admin_payload.json",
  local.(AshA2ui.Info.build_surface(VisitDocumentUI, authorize?: false, context_state: context))
)

write.(
  "document_shown_payload.json",
  local.(
    AshA2ui.Info.build_surface(VisitDocumentUI,
      authorize?: false,
      context_state: context,
      document_state: %{"referral" => true}
    )
  )
)

Application.delete_env(:ash_a2ui, :catalog)
IO.puts("document fixtures written to #{out}")
