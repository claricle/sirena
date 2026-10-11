# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Git graph markers, labels, and reference lane lines.
    class GitGraphRecognizer
      MARKER_SHAPES = %w[circle rect path].freeze
      GENERATED_COMMIT_LABEL = /\A(?:\d+-[0-9a-f]{7}|commit-\d+)\z/i

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
          markers + labels + sirena_lanes(labels)
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
            same_marker?(items, entry)
          end
          group ? group << entry : groups << [entry]
        end
      end

      def same_marker?(items, entry)
        same_center?(items.first[:box], entry[:box]) ||
          cherry_pick_component?(items, entry)
      end

      def cherry_pick_component?(items, entry)
        return false unless class_token?(entry[:node], "commit-cherry-pick")

        items.any? do |item|
          class_token?(item[:node], "commit-cherry-pick") &&
            overlapping?(item[:box], entry[:box])
        end
      end

      def overlapping?(left, right)
        left.min_x <= right.max_x && right.min_x <= left.max_x &&
          left.min_y <= right.max_y && right.min_y <= left.max_y
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
          entry = text_entry(extractor, text) if kind
          next unless entry
          next if generated_commit_label?(kind, entry[:label])

          logical_element(kind, entry[:label], entry[:box])
        end
      end

      def reference_label_kind(text)
        return :commit_label if class_token?(text, "commit-label")

        :tag_label if class_token?(text, "tag-label")
      end

      def reference_lanes(extractor, doc)
        labels = branch_labels(extractor, doc)
        lane_nodes(doc).zip(labels).filter_map do |line, label|
          next unless label && extractor.bbox(line)

          logical_element(:lane, label.key, lane_anchor(label.bbox))
        end
      end

      def lane_nodes(doc)
        doc.xpath("//line").select { |line| class_token?(line, "branch") }
      end

      def sirena_labels(extractor, doc, markers)
        return [] if markers.empty?

        orientation = orientation(extractor, doc, markers)
        labels = doc.xpath("//text").filter_map do |text|
          sirena_label(extractor, text, markers, orientation)
        end
        deduplicate_branch_labels(labels)
      end

      def sirena_lanes(labels)
        labels.filter_map do |label|
          next unless label.kind == :branch_label

          logical_element(:lane, label.key, lane_anchor(label.bbox))
        end
      end

      def lane_anchor(box)
        x, y = box.center
        Bbox.new(x, y, x, y)
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
        return unless marker

        explicit_kind = explicit_label_kind(text)
        kind = explicit_kind ||
          sirena_label_kind(entry[:box], marker.bbox, markers, orientation,
                            text["font-weight"] == "bold",
                            text["text-anchor"])
        return unless explicit_kind ||
          recognized_label_position?(kind, entry[:box], marker)

        logical_sirena_label(kind, entry)
      end

      def logical_sirena_label(kind, entry)
        return if generated_commit_label?(kind, entry[:label])

        logical_element(kind, entry[:label], entry[:box])
      end

      def explicit_label_kind(text)
        return :commit_label if class_token?(text, "commit-label")
        return :tag_label if class_token?(text, "tag-label")
      end

      def recognized_label_position?(kind, label, marker)
        kind == :branch_label || near_marker?(label, marker.bbox)
      end

      def generated_commit_label?(kind, label)
        kind == :commit_label && label.match?(GENERATED_COMMIT_LABEL)
      end

      def sirena_label_kind(label, marker, markers, orientation, bold, anchor)
        if bold && (anchor == "start" ||
                    branch_position?(label, markers, orientation))
          return :branch_label
        end

        tag_position?(label, marker, orientation) ? :tag_label : :commit_label
      end

      def branch_position?(label, markers, orientation)
        x_coordinate, y_coordinate = label.center
        clearance = marker_clearance(markers)
        left, top, bottom = marker_boundaries(markers, clearance)
        { lr: x_coordinate < left, tb: y_coordinate < top,
          bt: y_coordinate > bottom }.fetch(orientation)
      end

      def marker_clearance(markers)
        markers.map(&:bbox)
          .map { |box| [box.width, box.height].max }.max / 4.0
      end

      def marker_boundaries(markers, clearance = 0)
        centers = markers.map { |marker| marker.bbox.center }
        x_coordinates = centers.map(&:first)
        y_coordinates = centers.map(&:last)
        [x_coordinates.min - clearance, y_coordinates.min - clearance,
         y_coordinates.max + clearance]
      end

      def tag_position?(label, marker, orientation)
        delta_x, delta_y = offset(label, marker)
        orientation == :lr ? delta_y.negative? : delta_x.negative?
      end

      def near_marker?(label, marker)
        reach = [marker.width, marker.height].max * 4
        distance(label.center, marker.center) <= reach
      end

      def orientation(extractor, doc, markers)
        label_orientation(extractor, doc, markers) ||
          marker_orientation(markers)
      end

      def label_orientation(extractor, doc, markers)
        labels = bold_label_boxes(extractor, doc)
        return if labels.empty?

        orientation, distance = boundary_distances(labels, markers)
          .max_by { |_, value| value }

        orientation if distance.positive?
      end

      def bold_label_boxes(extractor, doc)
        doc.xpath("//text").filter_map do |text|
          next unless text["font-weight"] == "bold"

          text_entry(extractor, text)&.fetch(:box)
        end
      end

      def boundary_distances(labels, markers)
        marker_left, marker_top, marker_bottom = marker_boundaries(markers)
        { lr: marker_left - labels.map(&:min_x).min,
          tb: marker_top - labels.map(&:min_y).min,
          bt: labels.map(&:max_y).max - marker_bottom }
      end

      def marker_orientation(markers)
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
