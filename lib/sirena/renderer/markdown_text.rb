# frozen_string_literal: true

require_relative "../markdown_text"
require_relative "../svg/tspan"

module Sirena
  module Renderer
    # Renders `Sirena::MarkdownText`-parsed label text onto an `Svg::Text`
    # element as either plain `content` or `<tspan>` children. The text
    # parsing itself (`parse_lines`, `truncate_runs`, `Run`) lives in the
    # layer-neutral `Sirena::MarkdownText` (required above) so
    # `Layout::Kanban` can size a label without depending on this
    # renderer-only, `Svg::Tspan`-producing half.
    module MarkdownText
      module_function

      # Assigns a markdown-parsed label onto a `Svg::Text` element. A plain
      # label (no markup, no hard line break) keeps setting `content` — no
      # `<tspan>` wrapper, same XML shape existing fixtures expect.
      #
      # @param text_element [Svg::Text] element to assign onto
      # @param lines [Array<Array<Sirena::MarkdownText::Run>>] truncated runs
      #   from `Sirena::MarkdownText.parse_lines`
      # @param x [Numeric] the label's horizontal anchor
      # @param base_font_weight [String, nil] passed to `build_markdown_tspans`
      # @return [void]
      def assign_markdown_text(text_element, lines, base_font_weight: nil,
                               **coordinates)
        x_position = required_x(coordinates)
        if plain_line?(lines)
          text_element.content = lines.first.first&.text.to_s
        else
          text_element.tspans = build_markdown_tspans(
            lines, x: x_position, base_font_weight: base_font_weight
          )
        end
      end

      # True when parsing found no markup and no hard line break: a single
      # line holding at most one run, styled neither bold nor italic.
      #
      # @param lines [Array<Array<Sirena::MarkdownText::Run>>]
      # @return [Boolean]
      # @api private
      def plain_line?(lines)
        return false unless lines.length == 1

        runs = lines.first
        runs.length <= 1 && runs.none? { |run| run.bold || run.italic }
      end

      # Builds the <tspan> runs for a markdown-parsed label. Only the FIRST
      # run of a line after a hard line break needs `x` (reset) and a
      # `line_shift` (lines below the previous placed run) — every other run
      # continues the previous one.
      #
      # @param lines [Array<Array<Sirena::MarkdownText::Run>>] truncated runs
      #   from `Sirena::MarkdownText.parse_lines`
      # @param x [Numeric] the label's horizontal anchor
      # @param base_font_weight [String, nil] "bold" for a bold-by-default
      #   `Svg::Text` (e.g. a kanban column header)
      # @return [Array<Svg::Tspan>]
      # @api private
      def build_markdown_tspans(lines, base_font_weight: nil, **coordinates)
        x_position = required_x(coordinates)
        pending_lines = 0
        lines.each_with_index.flat_map do |runs, line_index|
          pending_lines += 1 if line_index.positive?
          tspans = line_tspans(runs, x_position, pending_lines,
                               base_font_weight)
          pending_lines = 0 unless runs.empty?
          tspans
        end
      end

      def required_x(coordinates)
        return coordinates[:x] if coordinates.key?(:x)

        raise ArgumentError, "missing keyword: :x"
      end

      def line_tspans(runs, x_position, line_shift, base_font_weight)
        runs.map.with_index do |run, index|
          build_tspan(run, x_position, line_shift, base_font_weight,
                      new_line: index.zero? && line_shift.positive?)
        end
      end

      def build_tspan(run, x_position, line_shift, base_font_weight, new_line:)
        Svg::Tspan.new.tap do |tspan|
          apply_line_shift(tspan, x_position, line_shift) if new_line
          if run.bold || base_font_weight == "bold"
            tspan.font_weight = "bold"
          end
          tspan.font_style = "italic" if run.italic
          tspan.content = run.text
        end
      end

      def apply_line_shift(tspan, x_position, line_shift)
        tspan.x = x_position
        tspan.line_shift = line_shift
      end
    end
  end
end
