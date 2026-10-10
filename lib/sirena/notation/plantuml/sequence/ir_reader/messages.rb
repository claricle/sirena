# frozen_string_literal: true

require_relative "../arrow_style"
require_relative "../edge"
require_relative "../message"
require_relative "../parallel_message"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRReader
          # Rebuilds a message from its node and its edge.
          module Messages
            module_function

            def call(node, index)
              edge = index.edges_of(node).first
              kind = flag(node, "parallel", index) ? ParallelMessage : Message
              number = index.detail(node, "number")
              kind.new(from: place(edge.source_id, index),
                       to: place(edge.target_id, index), label: node.label,
                       style: style(node, edge, index),
                       number: number && number.to_i)
            end

            def style(node, edge, index)
              marks = edge.properties
              ArrowStyle.new(
                head: arrow_end(marks.target_marker, "head", node, index),
                tail: arrow_end(marks.source_marker, "tail", node, index),
                dashed: flag(node, "dashed", index),
                leftward: flag(node, "leftward", index),
                hidden: flag(node, "hidden", index),
                colour: index.detail(node, "colour"),
              )
            end

            def arrow_end(glyph, side, node, index)
              ArrowEnd.new(glyph: glyph&.to_sym,
                           circle: flag(node, "#{side}_circle", index))
            end

            def flag(node, role, index)
              !index.detail(node, role).nil?
            end

            # A participant's id, or the Edge the missing end was.
            def place(node_id, index)
              node = index.node(node_id)
              return index.name(node_id) unless node.role == "open_end"

              Edge.new(side: index.detail(node, "side").to_sym,
                       local: !index.detail(node, "local").nil?)
            end
          end
        end
      end
    end
  end
end
