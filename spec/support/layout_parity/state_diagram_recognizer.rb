# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Logical states shared by mmdc references and Sirena renders.
    class StateDiagramRecognizer
      REFERENCE_TERMINAL = /\Astate-.+_(start|end)-\d+\z/
      SIRENA_TERMINAL = /\Astate-(start|end)_\d+\z/
      REFERENCE_STATE = /\Astate-(.+)-\d+\z/
      SIRENA_STATE = /\Astate-(.+)\z/

      def container_kinds
        [:composite]
      end

      def elements(extractor, doc)
        doc.xpath("//g[@id]").filter_map do |group|
          kind, key, identity = identify(group)
          next unless kind

          box = extractor.bbox(group)
          next unless box

          Element.new(kind: kind, key: key, bbox: box,
                      label: extractor.label(group), identity: identity)
        end
      end

      private

      def identify(group)
        id = group["id"]
        terminal(id) || reference_state(group) || sirena_state(group)
      end

      def terminal(id)
        role = id[REFERENCE_TERMINAL, 1] || id[SIRENA_TERMINAL, 1]
        [:"terminal-#{role}", "[*]", :label] if role
      end

      def reference_state(group)
        classes = group["class"].to_s.split
        if classes.include?("statediagram-cluster")
          return [:composite, group["id"], :id]
        end

        key = group["id"][REFERENCE_STATE, 1]
        [:state, key, :id] if key && classes.include?("node")
      end

      def sirena_state(group)
        key = group["id"][SIRENA_STATE, 1]
        return unless key

        kind = nested_state?(group) ? :composite : :state
        [kind, key, :id]
      end

      def nested_state?(group)
        group.xpath(".//g[starts-with(@id, 'state-')]").any?
      end
    end
  end
end
