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
        groups = doc.xpath("//g[@id]")
        region_keys = reference_region_keys(groups)
        groups.filter_map do |group|
          kind, key, identity = identify(group, region_keys)
          next unless kind

          box = extractor.bbox(group)
          next unless box

          Element.new(kind: kind, key: key, bbox: box,
                      label: extractor.label(group), identity: identity)
        end
      end

      private

      def identify(group, region_keys)
        id = group["id"]
        terminal(id) || reference_state(group, region_keys) ||
          sirena_state(group)
      end

      def terminal(id)
        role = id[REFERENCE_TERMINAL, 1] || id[SIRENA_TERMINAL, 1]
        [:"terminal-#{role}", "[*]", :id] if role
      end

      def reference_state(group, region_keys)
        classes = group["class"].to_s.split
        if classes.include?("statediagram-cluster")
          key = region_keys.fetch(group["id"], group["id"])
          return [:composite, key, :id]
        end

        key = group["id"][REFERENCE_STATE, 1]
        [:state, key, :id] if key && classes.include?("node")
      end

      def sirena_state(group)
        key = group["id"][SIRENA_STATE, 1]
        return unless key

        key = concurrent_region_key(key)
        kind = nested_state?(group) ? :composite : :state
        [kind, key, :id]
      end

      def reference_region_keys(groups)
        regions = groups.select do |group|
          group["class"].to_s.split.include?("statediagram-cluster-alt")
        end
        regions.each_with_index.to_h do |group, index|
          [group["id"], "concurrent-region-#{index + 1}"]
        end
      end

      def concurrent_region_key(key)
        index = key[/\Aconcurrent_region_(\d+)\z/, 1]
        index ? "concurrent-region-#{index}" : key
      end

      def nested_state?(group)
        group.xpath(".//g[starts-with(@id, 'state-')]").any?
      end
    end
  end
end
