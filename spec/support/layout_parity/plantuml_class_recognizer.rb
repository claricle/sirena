# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Logical class nodes, contents, and relations shared by pinned PlantUML
    # references and Sirena's PlantUML renderer.
    class PlantumlClassRecognizer
      REFERENCE_CLASS = "entity"
      REFERENCE_RELATION = "link"
      SIRENA_CLASS = "class-"
      SIRENA_RELATION = "relation-"
      SIRENA_JUNCTION = "junction-"
      UNRESOLVED_ENDPOINT = "unresolved-endpoint"
      ENDPOINT_TOLERANCE = 6.0
      VISIBILITY = {
        "PUBLIC" => "+", "PRIVATE" => "-", "PROTECTED" => "#",
        "PACKAGE" => "~"
      }.freeze
      ClassGroup = Data.define(:node, :name, :bbox, :reference_id)
      private_constant :ClassGroup

      def container_kinds
        []
      end

      def elements(extractor, doc)
        classes = class_groups(extractor, doc)
        class_elements(classes) + relation_elements(extractor, doc, classes)
      end

      private

      def class_groups(extractor, doc)
        doc.xpath("//g").filter_map do |group|
          name = class_name(group)
          next unless name

          box = extractor.bbox(group)
          next unless box

          ClassGroup.new(node: group, name: name, bbox: box,
                         reference_id: group["id"])
        end
      end

      def class_name(group)
        return group["data-qualified-name"] if reference_class?(group)

        group["id"].to_s.delete_prefix(SIRENA_CLASS) if sirena_class?(group)
      end

      def reference_class?(group)
        classes(group).include?(REFERENCE_CLASS) &&
          group.key?("data-qualified-name") && !reference_note_group?(group)
      end

      def reference_note_group?(group)
        group["data-qualified-name"].to_s.match?(/\AGMN\d+\z/) &&
          group.at_xpath("./rect").nil?
      end

      def sirena_class?(group)
        group["id"].to_s.start_with?(SIRENA_CLASS)
      end

      def class_elements(groups)
        groups.flat_map do |group|
          [element(:class, group.name, group.bbox, group.name),
           element(:class_content, content_key(group), group.bbox,
                   content_rows(group).join(" "))]
        end
      end

      def content_key(group)
        [group.name, *content_rows(group)]
      end

      def content_rows(group)
        rows = group.node.xpath(".//text").map do |text|
          normalize(text.text)
        end.reject(&:empty?)
        rows = reference_rows(group.node, rows) if reference_class?(group.node)

        rows.reject { |row| stereotype?(row) }
      end

      def stereotype?(row)
        row.match?(/\A(?:<<.+>>|«.+»)\z/)
      end

      def reference_rows(group, rows)
        rows.map.with_index do |row, index|
          index.zero? ? row : "#{visibility_for(group, index)}#{row}"
        end
      end

      def visibility_for(group, text_index)
        text = group.xpath(".//text")[text_index]
        modifier = text.xpath("preceding-sibling::*[1]").first
        kind = modifier&.[]("data-visibility-modifier").to_s.split("_").first
        VISIBILITY.fetch(kind, "")
      end

      def relation_elements(extractor, doc, groups)
        ordinals = Hash.new(0)
        relation_groups(doc).filter_map do |group|
          endpoints = endpoints_for(group, groups)
          ordinal = ordinals[endpoints]
          ordinals[endpoints] += 1
          relation_element(extractor, group, endpoints, ordinal)
        end
      end

      def relation_groups(doc)
        doc.xpath("//g").select do |group|
          classes(group).include?(REFERENCE_RELATION) ||
            group["id"].to_s.start_with?(SIRENA_RELATION, SIRENA_JUNCTION)
        end
      end

      def endpoints_for(group, groups)
        if classes(group).include?(REFERENCE_RELATION)
          reference_endpoints(group, groups)
        else
          sirena_endpoints(group, groups)
        end
      end

      def reference_endpoints(group, groups)
        names = groups.to_h { |entry| [entry.reference_id, entry.name] }
        %w[data-entity-1 data-entity-2].map do |attribute|
          names.fetch(group[attribute], UNRESOLVED_ENDPOINT)
        end
      end

      def sirena_endpoints(group, groups)
        path = group.at_xpath(".//path[@d]")
        points = transformed_path_points(path)
        return [UNRESOLVED_ENDPOINT] * 2 if points.empty?

        [points.first, points.last].map do |point|
          nearest_class(point, groups) || UNRESOLVED_ENDPOINT
        end
      end

      def transformed_path_points(path)
        return [] unless path

        matrix = path_matrix(path)
        PathPoints.new(path["d"]).points.map { |point| matrix.apply(*point) }
      end

      def path_matrix(path)
        nodes = path.ancestors.reverse_each
        ancestors = nodes.reduce(Matrix.identity) do |ctm, node|
          ctm * Matrix.parse(node["transform"])
        end
        ancestors * Matrix.parse(path["transform"])
      end

      def nearest_class(point, groups)
        distances = groups.map { |entry| [distance(point, entry.bbox), entry] }
        nearest, runner_up = distances.sort_by(&:first).first(2)
        return unless resolved_nearest?(nearest, runner_up)

        nearest.last.name
      end

      def resolved_nearest?(nearest, runner_up)
        return false unless nearest
        return false if nearest.first > ENDPOINT_TOLERANCE

        !runner_up || (runner_up.first - nearest.first).abs >= 1e-6
      end

      def distance(point, box)
        dx = axis_distance(point[0], box.min_x, box.max_x)
        dy = axis_distance(point[1], box.min_y, box.max_y)
        Math.hypot(dx, dy)
      end

      def axis_distance(point, minimum, maximum)
        [minimum - point, 0, point - maximum].max
      end

      def relation_element(extractor, group, endpoints, ordinal)
        labels = group.xpath(".//text").map { |text| normalize(text.text) }
          .reject(&:empty?)
        key = [*endpoints, ordinal, *labels]
        element(:relation, key, extractor.bbox(group), labels.join(" "))
      end

      def element(kind, key, box, label)
        Element.new(kind: kind, key: key, bbox: box, label: label)
      end

      def classes(group)
        group["class"].to_s.split
      end

      def normalize(text)
        text.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
