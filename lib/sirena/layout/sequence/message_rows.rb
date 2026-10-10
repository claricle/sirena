# frozen_string_literal: true

require_relative "../../diagram/sequence_text"
require_relative "geometry"
require_relative "text_wrap"

module Sirena
  module Layout
    class Sequence < Base
      # The text lines of every message, and how much taller each row grows
      # for them. A message wraps when mermaid wraps it, at the wider of
      # the room between its two actors and one actor box.
      class MessageRows
        # mmdc's measured height of one 16px line, per pixel of font size.
        LINE_ADVANCE_RATIO = 1.09
        ACTIVATION_EDGE = 2
        HEAD_INSET = 3
        PADDING = 20
        SELF_DROP = 30
        MIN_LIMIT = Geometry::ACTOR_WIDTH
        FLAT_HEADS = %w[none stick_top stick_bottom].freeze
        TURNED_HEADS = %w[half_top half_bottom].freeze

        # @param edges [Array<Hash>] messages: sources, targets, metadata
        # @param positions [Hash] participant id to its center_x
        # @param font_size [Numeric] message text size
        # @param wrap [Boolean] the diagram's wrap setting
        # @param closers [Array<Integer>] messages a frame ends right after
        def initialize(edges, positions, font_size:, wrap: false,
                       closers: [])
          @edges = edges || []
          @positions = positions
          @font_size = font_size
          @wrap = wrap
          @closers = closers
        end

        # @return [Boolean] the diagram's wrap setting
        def wrap?
          @wrap ? true : false
        end

        # @param index [Integer] message index
        # @return [Array<String>] the lines mermaid draws, entities decoded
        def lines(index)
          return [] unless index

          all_lines.fetch(index, [])
        end

        # @param index [Integer] message index
        # @return [Numeric] height the message's extra lines add to its row
        def extra(index)
          [lines(index).length - 1, 0].max * line_advance
        end

        # @return [Numeric] height added by the messages above `index`
        def extra_before(index)
          (0...index).sum { |at| extra(at) + self_drop(at) }
        end

        # @return [Numeric] height added above and within `index`'s own row;
        #   its self-loop pushes down the rows below it, not its own
        def extra_through(index)
          extra_before(index) + extra(index)
        end

        # @return [Numeric] height added by every message
        def total_extra
          extra_before(@edges.length)
        end

        # @return [Numeric] distance between two drawn lines of a message
        def line_pitch
          (@font_size * 1.2).round
        end

        private

        # mmdc leaves 30 below a message to itself, for the loop, and 30
        # more when a frame ends right after it.
        def self_drop(index)
          edge = @edges[index]
          return 0 unless edge && edge[:sources].first == edge[:targets].first

          @closers.include?(index) ? 2 * SELF_DROP : SELF_DROP
        end

        def line_advance
          (@font_size * LINE_ADVANCE_RATIO).round
        end

        def all_lines
          @all_lines ||= @edges.map { |edge| edge_lines(edge) }
        end

        def edge_lines(edge)
          source = edge.dig(:metadata, :message_source).to_s
          body = TextWrap.body(source)
          raw = if TextWrap.wrapped?(source, @wrap)
                  TextWrap.lines(body, limit(edge), @font_size)
                else
                  body.split(TextWrap::LINE_BREAK, -1)
                end
          raw.map { |line| Diagram::SequenceText.decode(line) }
        end

        def limit(edge)
          [bounded_width(edge) + PADDING, MIN_LIMIT].max
        end

        def bounded_width(edge)
          from, to = edge.values_at(:sources, :targets).map(&:first)
          return 0 if from == to

          centres = [from, to].map { |id| @positions.dig(id, :center_x) }
          return 0 if centres.any?(&:nil?)

          [(centres.first - centres.last).abs - trims(edge[:metadata]), 0].max
        end

        def trims(metadata)
          style = (metadata || {})[:head_style]
          side = (metadata || {})[:head_side]
          trim = ACTIVATION_EDGE
          trim += HEAD_INSET unless FLAT_HEADS.include?(style) || reverse?(side)
          trim + (starts_inset?(style, side) ? HEAD_INSET : 0)
        end

        def reverse?(side)
          side == "source"
        end

        def starts_inset?(style, side)
          side == "both" || (reverse?(side) && TURNED_HEADS.include?(style))
        end
      end
    end
  end
end
