# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRAdapter
          # Encodes a message: a node that holds its place in the order and
          # its drawing facts, and an edge from sender to receiver.
          module Messages
            module_function

            def call(message, sink, ids)
              node = sink.node("message", message.label)
              details(message, node, sink)
              style = message.style
              sink.edge("message", end_node(message.from, node, sink, ids),
                        end_node(message.to, node, sink, ids),
                        parent_id: node.id, properties: markers(style))
            end

            def details(message, node, sink)
              style = message.style
              sink.detail(node, "number", message.number)
              flags(message).each do |role, on|
                sink.detail(node, role, "true") if on
              end
              sink.detail(node, "colour", style.colour)
            end

            def flags(message)
              style = message.style
              { "parallel" => message.parallel?,
                "dashed" => style.dashed,
                "leftward" => style.leftward,
                "hidden" => style.hidden,
                "head_circle" => style.head.circle,
                "tail_circle" => style.tail.circle }
            end

            def markers(style)
              IR::PropertySet.new(source_marker: style.tail.glyph&.to_s,
                                  target_marker: style.head.glyph&.to_s)
            end

            # A participant's node, or a new node for the missing end.
            def end_node(place, message_node, sink, ids)
              return ids.fetch(place) unless place.is_a?(Edge)

              node = sink.node("open_end", nil, parent: message_node)
              sink.detail(node, "side", place.side)
              sink.detail(node, "local", "true") if place.local?
              node
            end
          end
        end
      end
    end
  end
end
