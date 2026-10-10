# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Declares the non-bbox measurements and node-like spatial kinds that the
    # settled metric contract assigns to each Mermaid type.
    class MeasurementPolicy
      Policy = Data.define(:analog_measurements, :spatial_kinds)

      SPATIAL_KINDS = {
        architecture: %i[architecture_group architecture_service],
        block: %i[block_container block_leaf],
        c4: %i[c4_boundary c4_element],
        class_diagram: %i[class],
        er_diagram: %i[entity],
        flowchart: %i[node cluster],
        gantt: %i[task],
        kanban: %i[section card],
        mindmap: %i[mindmap_node],
        packet: %i[field],
        requirement: %i[requirement element],
        sequence: %i[participant-top participant-bottom],
        state_diagram: %i[composite state terminal-start terminal-end],
        treemap: %i[treemap_section treemap_leaf],
        user_journey: %i[journey_section journey_task],
      }.transform_values(&:freeze).freeze

      TYPES = %i[
        architecture block c4 class_diagram er_diagram error flowchart gantt
        git_graph info kanban mindmap packet pie quadrant radar requirement
        sankey sequence state_diagram timeline treemap user_journey xychart
      ].freeze

      ANALOGS = {
        git_graph: lambda do |**arguments|
          guarded_measurements(:git_graph) do
            git_graph_measurements(**arguments)
          end
        end,
        pie: lambda do |**arguments|
          guarded_measurements(:pie) { pie_measurements(**arguments) }
        end,
        quadrant: lambda do |**arguments|
          guarded_measurements(:quadrant) do
            quadrant_measurements(**arguments)
          end
        end,
        radar: lambda do |**arguments|
          guarded_measurements(:radar) { radar_measurements(**arguments) }
        end,
      }.freeze

      EXPECTED_MISMATCHES = {
        git_graph: ["marker counts differ", "marker keys differ"],
        pie: ["pie sector and label counts differ",
              "pie sector labels differ"],
        quadrant: ["point counts differ", "point labels differ"],
        radar: ["graticule counts differ"],
      }.transform_values(&:freeze).freeze

      POLICIES = TYPES.to_h do |type|
        policy = Policy.new(
          analog_measurements: ANALOGS[type],
          spatial_kinds: SPATIAL_KINDS.fetch(type, [].freeze),
        ).freeze
        [type, policy]
      end.freeze

      def self.for(type)
        POLICIES.fetch(type.to_sym) do
          raise KeyError, "no parity measurement policy for #{type}"
        end
      end

      def self.quadrant_measurements(reference_svg:, sirena_svg:)
        QuadrantPointGeometry.compare(reference: reference_svg,
                                      sirena: sirena_svg).map do |comparison|
          measurement_row(comparison.key, :radius, comparison.error)
        end
      end
      private_class_method :quadrant_measurements

      def self.radar_measurements(reference_svg:, sirena_svg:)
        RadarGraticuleGeometry.compare(reference: reference_svg,
                                       sirena: sirena_svg)
          .each_with_index.map do |comparison, index|
            measurement_row("graticule-#{index + 1}", :radius,
                            comparison.error)
          end
      end
      private_class_method :radar_measurements

      def self.git_graph_measurements(reference_svg:, sirena_svg:)
        reference = GitGraphMarkerGeometry.extract(reference_svg)
        sirena = GitGraphMarkerGeometry.extract(sirena_svg)
        GitGraphMarkerGeometry.compare(reference: reference,
                                       sirena: sirena).map do |comparison|
          measurement_row(comparison.key, :radius, comparison.error)
        end
      end
      private_class_method :git_graph_measurements

      def self.pie_measurements(reference_svg:, sirena_svg:)
        reference = labeled_pie_measurements(reference_svg)
        sirena = labeled_pie_measurements(sirena_svg)
        pair_by_label(reference, sirena).flat_map do |label, expected, actual|
          comparison = PieSectorGeometry.compare(reference: expected,
                                                 sirena: actual)
          [measurement_row(label, :radius, comparison.radius_error),
           measurement_row(label, :sweep_angle, comparison.sweep_error)]
        end
      end
      private_class_method :pie_measurements

      def self.labeled_pie_measurements(svg)
        labels = SvgFigureExtractor.new(PieRecognizer.new).extract(svg)
          .elements.map(&:key)
        measurements = PieSectorGeometry.extract(svg)
        unless labels.size == measurements.size
          raise ArgumentError, "pie sector and label counts differ"
        end

        labels.zip(measurements)
      end
      private_class_method :labeled_pie_measurements

      def self.pair_by_label(reference, sirena)
        expected = measurements_by_label(reference)
        actual = measurements_by_label(sirena)
        validate_label_counts(expected, actual)

        expected.keys.sort.flat_map do |label|
          pair_label(label, expected.fetch(label), actual.fetch(label))
        end
      end
      private_class_method :pair_by_label

      def self.measurements_by_label(measurements)
        measurements.group_by(&:first)
      end
      private_class_method :measurements_by_label

      def self.validate_label_counts(expected, actual)
        return if label_counts(expected) == label_counts(actual)

        raise ArgumentError, "pie sector labels differ"
      end
      private_class_method :validate_label_counts

      def self.label_counts(measurements)
        measurements.transform_values(&:size)
      end
      private_class_method :label_counts

      def self.pair_label(label, expected, actual)
        expected.zip(actual).map do |left, right|
          [label, left.last, right.last]
        end
      end
      private_class_method :pair_label

      def self.measurement_row(key, metric, error)
        { key: [key, metric], error: error }
      end
      private_class_method :measurement_row

      def self.guarded_measurements(type)
        yield
      rescue ArgumentError => e
        raise unless EXPECTED_MISMATCHES.fetch(type).include?(e.message)

        [{ key: [type, :measurement_error, e.message],
           error: Float::INFINITY }]
      end
      private_class_method :guarded_measurements
    end
  end
end
