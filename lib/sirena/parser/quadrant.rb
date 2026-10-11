# frozen_string_literal: true

require_relative "base"
require_relative "grammars/quadrant"
require_relative "builders/quadrant"
require_relative "../diagram/quadrant"

module Sirena
  module Parser
    # Quadrant chart parser for Mermaid quadrant diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle quadrant chart syntax
    # with axis labels, quadrant labels, and data points.
    #
    # Parses quadrant charts with support for:
    # - Title declarations
    # - X-axis and Y-axis labels
    # - Quadrant labels (1-4)
    # - Data points with normalized coordinates
    # - Point styling (radius, color, stroke)
    # - Comments
    #
    # @example Parse a simple quadrant chart
    #   parser = Quadrant.new
    #   source = <<~MERMAID
    #     quadrantChart
    #       title Product Analysis
    #       x-axis Low Cost --> High Cost
    #       y-axis Low Value --> High Value
    #       Product A: [0.3, 0.7]
    #   MERMAID
    #   diagram = parser.parse(source)
    class Quadrant < Base
      grammar Grammars::Quadrant
      builder Builders::Quadrant

      CLASS_STYLE_KEYS = %w[radius color stroke-color stroke-width].freeze
      private_constant :CLASS_STYLE_KEYS

      # @raise [ParseError] when a classDef uses a style Mermaid rejects
      def parse(source)
        tree = parse_with_grammar(Grammars::Quadrant.new, source)
        validate_class_styles(tree)
        Builders::Quadrant.new.apply(tree)
      end

      private

      def validate_class_styles(tree)
        [tree].flatten.each do |item|
          next unless item.is_a?(Hash) && item.key?(:class_style)

          class_style_keys(item[:class_style]).each do |key|
            next if CLASS_STYLE_KEYS.include?(key)

            raise ParseError, "style named #{key} is not supported."
          end
        end
      end

      def class_style_keys(style)
        style.to_s.split(",").map { |part| part.strip.split(/\s*:\s*/).first }
      end
    end
  end
end
