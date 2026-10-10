# frozen_string_literal: true

require "json"

module SpecSupport
  module LayoutParity
    # Selects the live parity cohort and assembles one CaseResult per
    # oracle-valid, currently renderable corpus case. Reference-backed cases
    # are compared; missing references become explicit completeness failures.
    class CohortRunner
      ROOT = File.expand_path("../../..", __dir__)
      SCOREBOARD_PATH = File.join(ROOT, "scoreboard/corpus.json")
      CORPUS_ROOT = File.join(ROOT, "spec/mermaid")
      REFERENCE_ROOT = File.join(ROOT, "spec/fixtures_mermaid")
      PATHS = {
        scoreboard: SCOREBOARD_PATH,
        corpus: CORPUS_ROOT,
        references: REFERENCE_ROOT,
      }.freeze
      CASE_PATH = %r{\A[a-z0-9_]+/[A-Za-z0-9_.-]+\.mmd\z}

      Candidate = Data.define(
        :case_id,
        :source,
        :type,
        :recognizer,
        :measurement_policy,
        :reference,
        :reference_path,
      ) do
        def reference?
          File.file?(reference_path)
        end
      end

      def initialize(paths: PATHS,
                     comparator: CaseComparator,
                     renderer: Sirena::Engine.new,
                     detector: Sirena::Notation::Mermaid.method(:detect_type))
        @scoreboard_path = paths.fetch(:scoreboard)
        @corpus_root = paths.fetch(:corpus)
        @reference_root = paths.fetch(:references)
        @comparator = comparator
        @renderer = renderer
        @detector = detector
      end

      def candidate_cases
        @candidate_cases ||= selected_rows.map { |row| build_candidate(row) }
      end

      def comparison_cases
        @comparison_cases ||= candidate_cases.select(&:reference?)
      end

      def missing_reference_cases
        @missing_reference_cases ||= candidate_cases.reject(&:reference?)
      end

      def run
        comparison_cases.map { |candidate| compare(candidate) } +
          missing_reference_cases.map { |candidate| missing(candidate) }
      end

      private

      attr_reader :scoreboard_path, :corpus_root, :reference_root, :comparator,
                  :renderer, :detector

      def selected_rows
        JSON.parse(File.read(scoreboard_path)).select do |row|
          row["verdict"] == "valid" && row["pass"] == true
        end
      end

      def build_candidate(row)
        case_id = row.fetch("case")
        validate_case_id!(case_id)
        source = source_for(case_id)
        entry = recognizer_for(source)
        relative_reference, reference_path = reference_paths(case_id, entry)

        Candidate.new(case_id: case_id, source: source, type: entry.type,
                      recognizer: entry.recognizer,
                      measurement_policy: entry.measurement_policy,
                      reference: relative_reference,
                      reference_path: reference_path)
      end

      def source_for(case_id)
        File.read(File.join(corpus_root, case_id))
      end

      def recognizer_for(source)
        body = Sirena::Source.split(source).fetch(:body)
        RecognizerRegistry.fetch(detector.call(body))
      end

      def reference_paths(case_id, entry)
        name = "#{File.basename(case_id, '.mmd')}.svg"
        directory = entry.reference_directory
        relative = File.join("spec/fixtures_mermaid", directory, name)

        [relative, File.join(reference_root, directory, name)]
      end

      def validate_case_id!(case_id)
        return if case_id.match?(CASE_PATH)

        raise ArgumentError, "invalid corpus case path: #{case_id.inspect}"
      end

      def compare(candidate)
        sirena_svg, render_error = render(candidate.source)
        comparator.compare(
          **comparison_arguments(candidate),
          reference_svg: File.read(candidate.reference_path),
          sirena_svg: sirena_svg,
          render_error: render_error,
        )
      end

      def missing(candidate)
        comparator.compare(
          **comparison_arguments(candidate),
          reference_svg: nil,
          sirena_svg: nil,
        )
      end

      def comparison_arguments(candidate)
        {
          case_id: candidate.case_id,
          type: candidate.type.to_s,
          reference: candidate.reference,
          reproduce: reproduce(candidate.case_id),
          recognizer: candidate.recognizer,
          analog_measurements: candidate.measurement_policy.analog_measurements,
          spatial_kinds: candidate.measurement_policy.spatial_kinds,
        }
      end

      def reproduce(case_id)
        directory = case_id.split("/", 2).first
        "bundle exec rake 'corpus[#{directory},valid]'"
      end

      def render(source)
        [renderer.render(source), nil]
      rescue StandardError => e
        [nil, render_error(e)]
      end

      def render_error(error)
        {
          error_stage: error_stage(error),
          exception_class: error.class.name,
          message: error.message.to_s.each_line.first.to_s.chomp,
        }
      end

      def error_stage(error)
        case error
        when Sirena::Engine::DiagramTypeError then "detect"
        when Sirena::Parser::ParseError then "parse"
        when Sirena::Layout::LayoutError then "layout"
        when Sirena::Renderer::RenderError then "render"
        else "unknown"
        end
      end
    end
  end
end
