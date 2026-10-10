# frozen_string_literal: true

require_relative "../../text_measurement"
require_relative "../../diagram/sequence_text"
require_relative "geometry"

module Sirena
  module Layout
    class Sequence < Base
      # Widens the gap after an actor so the longest message to its right
      # neighbour, and the notes beside or over it, fit between the two
      # (mermaid's getMaxMessageWidthPerActor and calculateActorMargins).
      # Text is measured with TextMeasurement, i.e. in the Arial the
      # diagram is drawn in, so widths differ from mmdc by the font.
      class ActorGaps
        LINE_BREAK = Diagram::SequenceText::LINE_BREAK
        TEXT_PADDING = 10
        WRAP_ON = /\A\s*wrap:/i
        # `wrap:` text is broken into lines this wide at most.
        WRAP_LIMIT = Geometry::ACTOR_WIDTH - (2 * TEXT_PADDING)

        # @param children [Array<Hash>] participants in order: id, width
        # @param edges [Array<Hash>] messages: sources, targets, metadata
        # @param notes [Array<Hash>] note entries: text, position,
        #   participant_ids
        # @param font_size [Numeric] message and note text size
        def initialize(children, edges, notes, font_size:)
          @ids = children.map { |child| child[:id] }
          @widths = children.to_h { |child| [child[:id], child[:width]] }
          @edges = edges
          @notes = notes || []
          @font_size = font_size
        end

        # @param id [String] participant id
        # @return [Numeric] room added to the standard actor margin
        def extra_after(id)
          following = neighbour(id, 1)
          return 0 unless following

          half_boxes = (@widths[id] + @widths[following]) / 2.0
          [claims[id].to_f - half_boxes, 0].max
        end

        private

        def claims
          @claims ||= widest_per_actor(message_claims + note_claims)
        end

        def widest_per_actor(pairs)
          pairs.group_by(&:first).transform_values do |same|
            same.map(&:last).max
          end
        end

        def message_claims
          @edges.flat_map { |edge| message_claim(edge) }
        end

        def message_claim(edge)
          from = edge[:sources].first
          to = edge[:targets].first
          return [] unless @widths.key?(from) && @widths.key?(to)

          width = text_width(edge.dig(:metadata, :message_source))
          return [[from, width / 2.0]] if from == to

          key = adjacent_key(from, to)
          key ? [[key, width]] : []
        end

        def adjacent_key(from, to)
          return to if neighbour(to, 1) == from

          from if neighbour(to, -1) == from
        end

        def note_claims
          @notes.flat_map { |entry| note_claim(entry) }
        end

        def note_claim(entry)
          ids = entry[:participant_ids].select { |id| @widths.key?(id) }
          return [] if ids.empty?

          width = text_width(entry[:text])
          sided_claim(entry[:position], ids.first, ids.last, width)
        end

        def sided_claim(position, from, to, width)
          before = neighbour(to, -1)
          after = neighbour(to, 1)
          case position
          when "right_of" then after ? [[from, width]] : []
          when "left_of" then before ? [[before, width]] : []
          else over_claim(from, before, after, width / 2.0)
          end
        end

        def over_claim(from, before, after, half)
          halves = []
          halves << [before, half] if before
          halves << [from, half] if after
          halves
        end

        def neighbour(id, step)
          index = @ids.index(id)
          return unless index

          at = index + step
          @ids[at] if at >= 0
        end

        def text_width(source)
          body = Diagram::SequenceText.decode(
            source.to_s.sub(Diagram::SequenceText::WRAP_PREFIX, ""),
          )
          width = widest_line(body)
          width = [width, WRAP_LIMIT].min if source.to_s.match?(WRAP_ON)
          width + (2 * TEXT_PADDING)
        end

        def widest_line(body)
          body.split(LINE_BREAK, -1).map do |line|
            TextMeasurement.measure(line, font_size: @font_size)[:width]
          end.max.to_f.round
        end
      end
    end
  end
end
