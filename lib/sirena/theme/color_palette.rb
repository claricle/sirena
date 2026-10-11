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

      EXTRA_COLORS = %i[
        border edge_color field_background field_border field_text
        group_background highlight node_bg node_text note_fill section_bg
        title_text card_text xy_axis_line xy_grid_line
      ].freeze

      EXTRA_COLORS.each { |name| attribute name, :string }

      PALETTES = %i[
        flow git_graph mindmap pie quadrant radar requirement_risk timeline_fill
        timeline_text timeline_rule treemap user_journey_actor
        user_journey_section xy
      ].freeze

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
        EXTRA_COLORS.each { |name| map name.to_s, to: name }
        PALETTES.each { |name| map "#{name}_palette", to: :"#{name}_palette" }
      end

      # Picks a colour from a named categorical palette, wrapping past the end.
      #
      # @param name [Symbol] one of PALETTES
      # @param index [Integer] position, counted from 0
      # @return [String] the colour
      # @raise [KeyError] when the name is unknown or the theme lacks it
      def palette(name, index)
        unless PALETTES.include?(name)
          raise KeyError, "unknown palette: #{name.inspect}"
        end

        colours = public_send(:"#{name}_palette")
        if colours.nil? || colours.empty?
          raise KeyError, "theme defines no #{name} palette"
        end

        colours.fetch(index % colours.length)
      end
    end
  end
end
