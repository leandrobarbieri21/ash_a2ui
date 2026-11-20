defmodule AshA2ui.Test.DossierPageUI do
  @moduledoc """
  Standalone UI fixture for record pages (admin catalog 3.5): a dossier's
  whole page — its header (breadcrumb, title, state tag, owner, a link to
  its file and "Close"), a lead alert while it is closed, a lead summary
  card while it has one, and two sections reached from a section nav.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Dossier
    surface_id "dossier_page"
    title "Dossier"
    component_order :declared

    context :dossier do
      resource AshA2ui.Test.Dossier
      option_label :name
      picker false
    end

    page_header do
      context :dossier
      title :name
      crumb "Dossiers", href: "/dossiers", page: :back, live: :navigate

      tag :state_text do
        tone :state_tone
        help_field :state_help
      end

      meta :owner do
        icon "user"
        help "Who looks after it"
      end

      header_action :open_file do
        label "Open file"
        href :file_url
        title "Opens the file"
      end

      header_action :close do
        run :close
        visible :open?
        variant :primary
      end
    end

    section_nav do
      id "dossier-sections"
      nav_item :facts, label: "Facts", anchor: "facts", id: "facts-link"
      nav_item :notes, label: "Notes", anchor: "notes"
    end

    component :detail, :closed do
      context :dossier
      lead true
      visible :closed?

      alert do
        variant :neutral
        title "This dossier is closed"
        message :closed_note
      end
    end

    component :detail, :summary do
      context :dossier
      lead true
      visible :has_summary?
      fields [:summary]
    end

    component :detail, :facts do
      section "Facts"
      context :dossier
      fields [:name, :owner]
    end

    component :detail, :notes do
      section "Notes"
      context :dossier
      fields [:notes]
    end

    action :close do
      label "Close"
    end
  end
end
