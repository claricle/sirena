# frozen_string_literal: true

require_relative "../../../layout/state_diagram"
require_relative "hierarchy"
require_relative "look"
require_relative "curve"

module Sirena
  module Notation
    module PlantUML
      module State
        # The state layout for PlantUML's reading of a state diagram. The
        # Mermaid layout it extends places a composite as one box with its
        # children on top of the name and its transitions as lines between
        # centres; this one sizes each composite from its content, puts the
        # name in a header, and routes transitions between borders.
        class Layout < Sirena::Layout::StateDiagram
          # The engine builds a layout with `new` only, so a diagram's flat
          # transitions travel in a class that builds it.
          Flat = Struct.new(:pairs) do
            def new
              Layout.new.tap { |layout| layout.flat = pairs }
            end
          end
          private_constant :Flat

          # @param pairs [Array<Array(String, String)>] the transitions
          #   PlantUML draws on one rank
          # @return [#new] builds a layout that keeps them on one rank
          def self.with_flat(pairs)
            Flat.new(pairs)
          end

          attr_writer :flat

          private

          def scene(diagram)
            graph = build_graph(diagram)
            Hierarchy.new(graph, @flat || []).place
            scene_from_graph(graph)
          end

          # What the diagram draws, apart from Mermaid's reading: a history
          # state is a circle.
          def state_shape_type(state)
            return "history" if history?(state)

            super
          end

          def history?(state)
            %w[H H*].include?(state.label) &&
              state.id.to_s.match?(/_(?:deep_)?history\z/)
          end

          def dimensions_for_shape(state, label_dims, descriptions)
            case state_shape_type(state)
            when "history" then Look::HISTORY_SIZE
            when "start", "end" then Look.terminal(state_shape_type(state))
            when "note" then note_dimensions(state)
            else leaf_dimensions(state, label_dims, descriptions)
            end
          end

          def add_terminal_radius(metadata)
            radius = Look::TERMINAL_RADIUS[metadata[:shape_type]]
            metadata[:shape_radius] = radius if radius
            metadata
          end

          def note_dimensions(state)
            lines = state_texts(state)
            widest = lines.map do |line|
              measure_text(line, font_size: Look::NOTE_FONT)[:width]
            end.max.to_f
            { width: widest + Look::NOTE_PAD_X + Look::NOTE_PAD_RIGHT,
              height: (lines.size * Look::NOTE_LINE) + (2 * Look::NOTE_PAD_Y) }
          end

          # A plain state is a name above a divider; a composite is sized
          # from its children later.
          def leaf_dimensions(state, label_dims, descriptions)
            if state.children.any?
              return calculate_normal_state_dimensions(state, label_dims,
                                                       descriptions)
            end

            lines = descriptions.map do |text|
              measure_text(text, font_size: Look::TEXT_FONT)[:width]
            end
            { width: ([label_dims[:width]] + lines).max + 20.0,
              height: leaf_height(descriptions.size) }
          end

          def leaf_height(lines)
            body = (lines * Look::TEXT_LINE) + 10
            body = Look::EMPTY_BODY if lines.zero?
            Look::LEAF_BAR + body
          end

          # A composite's name is its header, not its centre; a start or end
          # marker carries no text.
          def typed_labels(state)
            case state.dig(:metadata, :shape_type)
            when "start", "end" then []
            when "note" then note_labels(state)
            when "history" then super
            else titled_labels(state)
            end
          end

          def titled_labels(state)
            name, *rest = state[:labels]
            bar = Array(state[:children]).empty? ? Look::LEAF_BAR : Look::BAR
            [text_label(name, state[:x] + (state[:width] / 2.0),
                        state[:y] + (bar / 2.0)),
             *body_labels(state, rest, bar)]
          end

          def body_labels(state, lines, bar)
            lines.each_with_index.map do |line, index|
              text_label(line, state[:x] + Look::TEXT_PAD,
                         state[:y] + bar + 13.0 + (index * Look::TEXT_LINE))
            end
          end

          def note_labels(state)
            state[:labels].each_with_index.map do |line, index|
              text_label(
                line, state[:x] + Look::NOTE_PAD_X,
                state[:y] + Look::NOTE_PAD_Y + (Look::NOTE_LINE / 2.0) +
                (index * Look::NOTE_LINE), size: Look::NOTE_FONT
              )
            end
          end

          def text_label(line, x_position, y_position, size: Look::TEXT_FONT)
            Sirena::Layout::StateDiagram::Label.new(
              text: line[:text], width: line[:width], height: line[:height],
              x: x_position, y: y_position, font_size: size
            )
          end

          def section_path(section)
            Curve.path([section.start_point, *section.bend_points,
                        section.end_point])
          end

          def typed_edge_labels(edge, _source, _target)
            label = (edge[:labels] || []).first
            return [] unless label && edge[:label_at]

            [Sirena::Layout::StateDiagram::Label.new(
              text: label[:text], width: label[:width],
              height: label[:height], x: edge[:label_at][:x],
              y: edge[:label_at][:y], font_size: small_font_size
            )]
          end
        end
      end
    end
  end
end
