# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRAdapter
          # Encodes every item that is not a message.
          module Blocks
            module_function

            def note(note, sink, ids)
              node = sink.node("note", note.text)
              sink.detail(node, "shape", note.shape)
              sink.detail(node, "side", note.side)
              sink.detail(node, "parallel", "true") if note.parallel?
              Fills.call(node, note.fill, sink)
              targets(node, note.targets, sink, ids)
            end

            def ref(ref, sink, ids)
              targets(sink.node("ref", ref.label), ref.targets, sink, ids)
            end

            def fragment(fragment, sink, _ids)
              node = sink.node("fragment", fragment.label)
              sink.detail(node, "phase", fragment.phase)
              sink.detail(node, "keyword", fragment.keyword)
              sink.detail(node, "parallel", "true") if fragment.parallel?
            end

            def divider(divider, sink, _ids)
              sink.node("divider", divider.label)
            end

            def activation(activation, sink, ids)
              node = sink.node("activation")
              sink.detail(node, "phase", activation.phase)
              sink.detail(node, "colour", activation.color)
              targets(node, [activation.participant], sink, ids)
            end

            def destroy(destroy, sink, ids)
              targets(sink.node("destroy"), [destroy.participant], sink, ids)
            end

            def page_break(_break, sink, _ids)
              sink.node("page_break")
            end

            def targets(node, names, sink, ids)
              names.each do |name|
                sink.edge("target", node, ids.fetch(name), parent_id: node.id)
              end
            end
          end
        end
      end
    end
  end
end
