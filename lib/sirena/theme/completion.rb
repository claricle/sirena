# frozen_string_literal: true

require_relative "../theme"
require_relative "registry"

module Sirena
  class Theme
    # Fills every colour a theme leaves unset from the default theme.
    # Renderers read colours and palettes with no hardcoded fallback, so a
    # partial custom theme would otherwise draw unfilled shapes or raise on a
    # missing palette.
    module Completion
      module_function

      # @param theme [Theme, nil] the caller's theme, possibly partial
      # @param base [Theme, nil] where unset colours come from
      # @return [Theme, nil] the theme itself when every colour is set,
      #   otherwise a filled copy; the caller's theme is never modified
      def call(theme, base = Registry.get(:default))
        return base if theme.nil?
        return theme if base.nil? || complete?(theme.colors)

        completed = theme.dup
        completed.colors = filled_colors(theme.colors, base.colors)
        completed
      end

      def complete?(colors)
        ColorPalette.attributes.keys.all? do |key|
          set_value(colors&.public_send(key))
        end
      end

      def filled_colors(colors, defaults)
        values = ColorPalette.attributes.keys.to_h do |key|
          [key, set_value(colors&.public_send(key)) || defaults.public_send(key)]
        end
        ColorPalette.new(**values)
      end

      def set_value(value)
        value unless value.respond_to?(:empty?) && value.empty?
      end
    end
  end
end
