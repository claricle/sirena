# frozen_string_literal: true

require "lutaml/model"

raise NameError, "uninitialized constant Sirena::Theme" unless defined?(Sirena::Theme)

# Represents the color palette for diagram theming
module Sirena
  class Theme
    class ColorPalette < Lutaml::Model::Serializable
      attribute :background, :string
      attribute :surface, :string
      attribute :surface_variant, :string
      attribute :foreground, :string
      attribute :foreground_secondary, :string
      attribute :primary, :string
      attribute :secondary, :string
      attribute :accent, :string
      attribute :error, :string
      attribute :warning, :string
      attribute :success, :string
      attribute :info, :string
      attribute :node_fill, :string
      attribute :node_stroke, :string
      attribute :edge_stroke, :string
      attribute :label_text, :string
      attribute :hover_fill, :string
      attribute :active_fill, :string
      attribute :disabled_fill, :string
      attribute :border, :string
      attribute :edge_color, :string
      attribute :field_background, :string
      attribute :field_border, :string
      attribute :field_text, :string
      attribute :group_background, :string
      attribute :highlight, :string
      attribute :node_bg, :string
      attribute :node_text, :string
      attribute :note_fill, :string
      attribute :section_bg, :string
      attribute :title_text, :string
      attribute :card_text, :string
      attribute :xy_axis_line, :string
      attribute :xy_grid_line, :string

      PALETTES = %i[flow xy timeline_fill timeline_text timeline_rule].freeze

      PALETTES.each do |name|
        attribute :"#{name}_palette", :string, collection: true
      end

      yaml do
        map "background", to: :background
        map "surface", to: :surface
        map "surface_variant", to: :surface_variant
        map "foreground", to: :foreground
        map "foreground_secondary", to: :foreground_secondary
        map "primary", to: :primary
        map "secondary", to: :secondary
        map "accent", to: :accent
        map "error", to: :error
        map "warning", to: :warning
        map "success", to: :success
        map "info", to: :info
        map "node_fill", to: :node_fill
        map "node_stroke", to: :node_stroke
        map "edge_stroke", to: :edge_stroke
        map "label_text", to: :label_text
        map "hover_fill", to: :hover_fill
        map "active_fill", to: :active_fill
        map "disabled_fill", to: :disabled_fill
        map "border", to: :border
        map "edge_color", to: :edge_color
        map "field_background", to: :field_background
        map "field_border", to: :field_border
        map "field_text", to: :field_text
        map "group_background", to: :group_background
        map "highlight", to: :highlight
        map "node_bg", to: :node_bg
        map "node_text", to: :node_text
        map "note_fill", to: :note_fill
        map "section_bg", to: :section_bg
        map "title_text", to: :title_text
        map "card_text", to: :card_text
        map "xy_axis_line", to: :xy_axis_line
        map "xy_grid_line", to: :xy_grid_line
        PALETTES.each { |name| map "#{name}_palette", to: :"#{name}_palette" }
      end

      # Picks a colour from a named categorical palette, wrapping past the end.
      #
      # @param name [Symbol] one of PALETTES
      # @param index [Integer] position, counted from 0
      # @return [String] the colour
      # @raise [KeyError] when the name is unknown or the theme lacks it
      def palette(name, index)
        raise KeyError, "unknown palette: #{name.inspect}" unless PALETTES.include?(name)

        colours = public_send(:"#{name}_palette")
        raise KeyError, "theme defines no #{name} palette" if colours.nil? || colours.empty?

        colours.fetch(index % colours.length)
      end
    end
  end
end
