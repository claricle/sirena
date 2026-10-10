# frozen_string_literal: true

require "svg_conform"
require "rexml/document"
require "yaml"

# Cases and judging for spec/plantuml_svg_conformance_spec.rb.
module PlantUmlConformanceHelpers
  ROOT = File.expand_path("../..", __dir__)

  # The spike's own cases: no oracle verdict, all in scope.
  def spike_sources
    Dir.glob(File.join(ROOT, "spec", "plantuml_spike", "cases", "*.puml"))
  end

  def oracle_verdicts
    YAML.load_file(File.join(ROOT, "spec", "plantuml", "oracle-verdicts.yml"))
      .fetch("verdicts")
  end

  # Corpus cases the oracle accepted. A case the oracle rejected has no
  # valid SVG to match, so the verdict file decides, not a hand list.
  def corpus_sources
    oracle_verdicts.select { |v| v["verdict"] == "valid" }.map do |verdict|
      File.join(ROOT, "spec", "plantuml", "#{verdict.fetch('id')}.puml")
    end
  end

  def render_plantuml(path)
    Sirena::Engine.new.render(File.read(path))
  end

  # @return [String, nil] why the svg is not conformant, or nil
  def conformance_problem(svg)
    begin
      REXML::Document.new(svg)
    rescue REXML::ParseException => e
      return "not well-formed: #{e.message.lines.first.to_s.strip}"
    end
    result = SvgConform.validate(svg, profile: Sirena::Svg::CONFORMANCE_PROFILE)
    return nil if result.valid?

    (result.errors + result.validity_errors).map(&:message).uniq.first(3)
      .join(" | ")
  end

  # One line per non-conformant or non-rendering case.
  def conformance_offenders(paths)
    paths.filter_map do |path|
      name = path.sub("#{ROOT}/", "")
      problem = conformance_problem(render_plantuml(path))
      "#{name}: #{problem}" if problem
    rescue StandardError => e
      "#{name}: raised #{e.class}: #{e.message[0, 80]}"
    end
  end
end
