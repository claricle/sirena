# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Git graph markers, labels, and reference lane lines.
    class GitGraphRecognizer
      MARKER_SHAPES = %w[circle rect path].freeze

      def container_kinds
        []
      end

      def elements(extractor, doc)
        markers = marker_elements(extractor, doc)
        if reference?(doc)
          markers + reference_labels(extractor, doc) +
            reference_lanes(extractor, doc)
        else
          labels = sirena_labels(extractor, doc, markers)
          markers + labels + sirena_lanes(markers, labels)
        end
      end

      private

      def reference?(doc)
        marker_nodes(doc).any?
      end

      def marker_elements(extractor, doc)
        groups = marker_groups(extractor, marker_candidates(doc))
        groups.each_with_index.map do |group, index|
          box = Bbox.union(group.map { |entry| entry[:box] })
          Element.new(kind: :commit, key: "commit-#{index + 1}", bbox: box,
                      identity: :label)
        end
      end

      def marker_candidates(doc)
        reference = marker_nodes(doc)
        reference.empty? ? doc.xpath("//circle") : reference
      end

      def marker_nodes(doc)
        doc.xpath("//*").select do |node|
          MARKER_SHAPES.include?(node.name) && class_token?(node, "commit")
        end
      end

      def marker_groups(extractor, nodes)
        nodes.each_with_object([]) do |node, groups|
          entry = { node: node, box: extractor.bbox(node) }
          next unless entry[:box]

          group = groups.find do |items|
            same_center?(items.first[:box], entry[:box])
          end
          group ? group << entry : groups << [entry]
        end
      end

      def same_center?(left, right)
        distance(left.center, right.center) <= 0.01
      end

      def reference_labels(extractor, doc)
        branch_labels(extractor, doc) + reference_commit_labels(extractor, doc)
      end

      def branch_labels(extractor, doc)
        groups = doc.xpath("//g").select do |group|
          class_token?(group, "branchLabel")
        end
        groups.filter_map do |group|
          label_element(extractor, group, :branch_label)
        end
      end

      def reference_commit_labels(extractor, doc)
        doc.xpath("//text").filter_map do |text|
          kind = reference_label_kind(text)
          label_element(extractor, text, kind) if kind
        end
      end

      def reference_label_kind(text)
        return :commit_label if class_token?(text, "commit-label")

        :tag_label if class_token?(text, "tag-label")
      end

      def reference_lanes(extractor, doc)
        labels = branch_labels(extractor, doc)
        lane_nodes(doc).zip(labels).filter_map do |line, label|
          box = extractor.bbox(line)
          logical_element(:lane, label.key, box) if box && label
        end
      end

      def lane_nodes(doc)
        doc.xpath("//line").select { |line| class_token?(line, "branch") }
      end

      def sirena_labels(extractor, doc, markers)
        return [] if markers.empty?

        orientation = orientation(markers)
        labels = doc.xpath("//text").filter_map do |text|
          sirena_label(extractor, text, markers, orientation)
        end
        deduplicate_branch_labels(labels)
      end

      def sirena_lanes(markers, labels)
        orientation = orientation(markers)
        labels.select { |label| label.kind == :branch_label }.map do |label|
          anchor = nearest_element(label.bbox, markers)
          lane_markers = markers.select do |marker|
            same_lane?(marker.bbox, anchor.bbox, orientation)
          end
          logical_element(
            :lane, label.key, Bbox.union(lane_markers.map(&:bbox))
          )
        end
      end

      def same_lane?(left, right, orientation)
        axis = orientation == :lr ? 1 : 0
        (left.center[axis] - right.center[axis]).abs <= 0.01
      end

      def deduplicate_branch_labels(labels)
        seen = {}
        labels.reject do |label|
          next false unless label.kind == :branch_label

          seen.key?(label.key).tap { seen[label.key] = true }
        end
      end

      def sirena_label(extractor, text, markers, orientation)
        entry = text_entry(extractor, text)
        marker = nearest_element(entry[:box], markers) if entry
        return unless entry && marker && near_marker?(entry[:box], marker.bbox)

        kind = sirena_label_kind(entry[:box], marker.bbox, orientation)
        logical_element(kind, entry[:label], entry[:box])
      end

      def sirena_label_kind(label, marker, orientation)
        return :branch_label if branch_position?(label, marker, orientation)

        tag_position?(label, marker, orientation) ? :tag_label : :commit_label
      end

      def branch_position?(label, marker, orientation)
        delta_x, delta_y = offset(label, marker)
        case orientation
        when :lr then horizontal_branch?(delta_x, delta_y, marker)
        when :tb then downward_branch?(delta_x, delta_y, marker)
        else upward_branch?(delta_x, delta_y, marker)
        end
      end

      def horizontal_branch?(delta_x, delta_y, marker)
        delta_x.positive? && delta_x <= marker.width * 2 &&
          delta_y.abs <= marker.height
      end

      def downward_branch?(delta_x, delta_y, marker)
        delta_x.abs <= marker.width && delta_y > marker.height
      end

      def upward_branch?(delta_x, delta_y, marker)
        delta_x.abs <= marker.width && delta_y < -marker.height / 2
      end

      def tag_position?(label, marker, orientation)
        delta_x, delta_y = offset(label, marker)
        orientation == :lr ? delta_y.negative? : delta_x.negative?
      end

      def near_marker?(label, marker)
        reach = [marker.width, marker.height].max * 4
        distance(label.center, marker.center) <= reach
      end

      def orientation(markers)
        centers = markers.map { |marker| marker.bbox.center }
        return :lr if span(centers, 0) >= span(centers, 1)

        centers.first.last <= centers.last.last ? :tb : :bt
      end

      def span(centers, axis)
        values = centers.map { |center| center[axis] }
        values.max - values.min
      end

      def offset(label, marker)
        [label.center.first - marker.center.first,
         label.center.last - marker.center.last]
      end

      def nearest_element(box, elements)
        elements.min_by { |element| distance(box.center, element.bbox.center) }
      end

      def label_element(extractor, node, kind)
        entry = text_entry(extractor, node)
        logical_element(kind, entry[:label], entry[:box]) if entry
      end

      def text_entry(extractor, node)
        box = extractor.bbox(node)
        label = node.text.gsub(/\s+/, " ").strip
        { box: box, label: label } if box && !label.empty?
      end

      def logical_element(kind, label, box)
        Element.new(kind: kind, key: label, bbox: box, label: label,
                    identity: :label)
      end

      def class_token?(node, token)
        node["class"].to_s.split.include?(token)
      end

      def distance(left, right)
        Math.hypot(left[0] - right[0], left[1] - right[1])
      end
    end
  end
end
