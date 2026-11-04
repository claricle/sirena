# frozen_string_literal: true

require_relative "../../../layout/state_diagram"
require_relative "hierarchy"

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
          private

          def scene(diagram)
            graph = build_graph(diagram)
            Hierarchy.new(graph).place
            scene_from_graph(graph)
          end

          # A composite's name is its header, not its centre; a start or end
          # marker carries no text.
          def typed_labels(state)
            return [] if %w[start end].include?(
              state.dig(:metadata, :shape_type),
            )
            return super if Array(state[:children]).empty?

            [header_label(state, state[:labels].first)]
          end

          def header_label(state, name)
            Sirena::Layout::StateDiagram::Label.new(
              text: name[:text], width: name[:width], height: name[:height],
              x: state[:x] + (state[:width] / 2.0), y: state[:y] + 18.0,
              font_size: label_font_sizes[:normal]
            )
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
