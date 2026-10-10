# frozen_string_literal: true

require_relative "../theme"
require_relative "registry"

module Sirena
  class Theme
    # Fills the categorical palettes a theme leaves unset from the default
    # theme: a chart cannot pick series colours from an empty list. Single
    # colours stay as given, so a theme that names no colour for something
    # still draws it unpainted.
    module Completion
      PALETTE_KEYS = ColorPalette::PALETTES.map do |name|
        :"#{name}_palette"
      end.freeze

      module_function

      # @param theme [Theme, nil] the caller's theme, possibly partial
      # @param base [Theme, nil] where unset palettes come from
      # @return [Theme, nil] the theme itself when every palette is set,
      #   otherwise a filled copy; the caller's theme is never modified
      def call(theme, base = Registry.get(:default))
        return base if theme.nil?
        return theme if base.nil? || complete?(theme.colors)

        completed = theme.dup
        completed.colors = filled_colors(theme.colors, base.colors)
        completed
      end

      def complete?(colors)
        PALETTE_KEYS.all? { |key| set_value(colors&.public_send(key)) }
      end

      def filled_colors(colors, defaults)
        values = ColorPalette.attributes.keys.to_h do |key|
          given = set_value(colors&.public_send(key))
          fill = PALETTE_KEYS.include?(key) && defaults.public_send(key)
          [key, given || fill || nil]
        end
        ColorPalette.new(**values)
      end

      def set_value(value)
        value unless value.respond_to?(:empty?) && value.empty?
      end
    end
  end
end
