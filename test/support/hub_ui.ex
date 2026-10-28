defmodule AshA2ui.Test.HubUI do
  @moduledoc """
  Standalone UI fixture for the hub filter bar: multi-select and grouped
  status options with counts and a hint, path filters over a to-many path
  and over a filtered aggregate, an aggregate search field, a placeholder,
  bare controls, page size options, column help, a detail line with help,
  a column sorted by another field, and the fields' own column order.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.HubContract
    surface_id "hub"

    query :default do
      search_fields [:name, :vendor_name]
      search_placeholder "Search contracts or vendors"
      sortable [:name, :status]
      filters [:status, :verified]
      path_filters property: [:lines, :property], vendor: :vendor_name
      multi_select_filters [:status, :property, :vendor]
      filter_groups status: [expiring: [:expiring_soon, :renewal_scheduled]]
      group_labels status: [expiring: "Expiring soon"]
      filter_labels property: "Property"
      filter_hints status: "Statuses update nightly."
      facet_counts true
      controls_card false
      apply_on_change true
      page_size 2
      page_size_options [2, 10]
      max_page_size 10
      default_sort name: :asc
      default_preset :all
      preset_picker false

      empty_state title: "No contracts yet",
                  message: "Contracts you add show here.",
                  icon: :inbox

      no_results_state title: "No results",
                       message: "Try other words or filters.",
                       icon: :search,
                       clear_action: "Clear search and filters"

      preset :all do
        read_action :active
      end

      preset :archived do
        read_action :archived
        empty_state title: "No archived contracts", icon: :archive
      end
    end

    context :contract do
      resource AshA2ui.Test.HubContract
      picker false
    end

    component :table do
      fields [
        :name,
        :property_name,
        :status_text,
        :vendor_name,
        :line_count,
        :property_names,
        :status,
        :status_help
      ]

      read_action :active
      query :default
      column_order :fields

      row_layout do
        title :name
        badge :status_text
        badge_tones expired: :gray, draft: :pending
        meta [:property_name]
      end

      select_context :contract

      primary_action do
        label "Open"
        width 96
      end

      column :name do
        subtitle :vendor_name
        width 320
      end

      column :property_name do
        more :line_count
        more_values :property_names
        more_noun "properties"
        help_title "Property"
        help "Where the work happens.\n\n**Portfolio** — every property of the PMC."
      end

      column :status_text do
        sort_by :status
        detail :status
        detail_text expiring_soon: "Ends soon", renewal_scheduled: "Renews soon"
        detail_help :status_help
      end
    end

    field :vendor_name do
      label "Vendor"
    end

    field :status_text do
      label "Status"
    end

    field :status do
      label "Contract status"
    end
  end
end
