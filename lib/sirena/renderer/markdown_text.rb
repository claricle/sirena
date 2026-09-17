# frozen_string_literal: true

require_relative "../markdown_text"
require_relative "../svg/tspan"

module Sirena
  module Renderer
    # Renders `Sirena::MarkdownText`-parsed label text onto an `Svg::Text`
    # element as either plain `content` or `<tspan>` children. The text
    # parsing itself (`parse_lines`, `truncate_runs`, `Run`) lives in the
    # layer-neutral `Sirena::MarkdownText` (required above) so
    # `Transform::Kanban` can size a label without depending on this
    # renderer-only, `Svg::Tspan`-producing half.
    module MarkdownText
      module_function

      # Assigns a markdown-parsed label onto a `Svg::Text` element. A label
      # with no markup and no hard line break keeps setting plain
      # `content` — no `<tspan>` wrapper, same XML shape existing fixtures
      # expect. Only a label needing per-run styling or a line break pays
      # for `<tspan>` children.
      #
      # @param text_element [Svg::Text] element to assign onto
      # @param lines [Array<Array<Sirena::MarkdownText::Run>>] from
      #   `Sirena::MarkdownText.parse_lines`, truncated
      # @param x [Numeric] the label's horizontal anchor
      # @param base_font_weight [String, nil] passed to `build_markdown_tspans`
      # @return [void]
      def assign_markdown_text(text_element, lines, x:, base_font_weight: nil)
        if plain_line?(lines)
          text_element.content = lines.first.first&.text.to_s
        else
          text_element.tspans = build_markdown_tspans(lines, x: x, base_font_weight: base_font_weight)
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

      # Builds the <tspan> runs for a markdown-parsed label. Only the
      # FIRST run of a line that followed a hard line break needs `x`
      # (reset to the label's left/center) and `dy` (one line height) —
      # every other run continues immediately after the previous one.
      #
      # @param lines [Array<Array<Sirena::MarkdownText::Run>>] from
      #   `Sirena::MarkdownText.parse_lines`, truncated
      # @param x [Numeric] the label's horizontal anchor
      # @param base_font_weight [String, nil] "bold" for a bold-by-default
      #   `Svg::Text` (e.g. a kanban column header)
      # @return [Array<Svg::Tspan>]
      # @api private
      def build_markdown_tspans(lines, x:, base_font_weight: nil)
        pending_lines = 0

        lines.each_with_index.flat_map do |runs, line_index|
          pending_lines += 1 if line_index.positive?

          runs.each_with_index.map do |run, run_index|
            new_line = run_index.zero? && pending_lines.positive?

            Svg::Tspan.new.tap do |t|
              if new_line
                t.x = x
                t.dy = line_height_dy(pending_lines)
                pending_lines = 0
              end
              t.font_weight = "bold" if run.bold || base_font_weight == "bold"
              t.font_style = "italic" if run.italic
              t.content = run.text
            end
          end
        end
      end

      # `line_count * 1.2em`, computed in tenths rather than `Float`
      # multiplication: `3 * 1.2` is `3.5999999999999996` in binary
      # floating point, which would put a wrong `dy` in the SVG.
      #
      # @param line_count [Integer] number of accumulated line-heights
      # @return [String]
      # @api private
      def line_height_dy(line_count)
        tenths = line_count * 12
        "#{tenths / 10}.#{tenths % 10}em"
      end
    end
  end
end
