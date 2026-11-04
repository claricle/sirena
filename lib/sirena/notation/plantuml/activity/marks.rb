# frozen_string_literal: true

require_relative "canvas"
require_relative "edge_marks"
require_relative "frame_marks"
require_relative "node_marks"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Turns a placed diagram into {Mark}s, back to front: lanes,
        # partitions, edges, nodes, notes, title.
        class Marks
          # @return [Scene]
          attr_reader :scene

          def initialize(diagram, placement, router)
            @diagram = diagram
            @placement = placement
            @canvas = Canvas.new
            @frames = FrameMarks.new(diagram, placement, @canvas)
            @edges = EdgeMarks.new(router, @canvas)
            @nodes = NodeMarks.new(placement.boxes, @canvas)
          end

          # @return [Float] the leftmost x any mark reaches
          def min_x
            @canvas.min_x
          end

          # Fills {#scene}.
          def build
            @frames.title
            @frames.lanes unless @placement.bands.empty?
            @frames.partitions
            @diagram.edges.each { |edge| @edges.draw(edge) }
            @diagram.nodes.each { |node| @nodes.draw(node) }
            notes
            @scene = scene_of(@canvas)
          end

          private

          def notes
            @placement.notes.each do |node, pairs|
              pairs.each { |note, box| @nodes.note(node, note, box) }
            end
          end

          def scene_of(canvas)
            Scene.new(width: canvas.max_x + Layout::MARGIN,
                      height: canvas.max_y + Layout::MARGIN,
                      marks: canvas.marks)
          end
        end
      end
    end
  end
end
