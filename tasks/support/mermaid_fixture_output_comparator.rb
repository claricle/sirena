# frozen_string_literal: true

# Output comparator class
class MermaidOutputComparator
  def compare_all_types
    MermaidFixtureGenerator::DIAGRAM_TYPES.each do |type|
      compare_type(type)
    end
  end

  def compare_type(diagram_type)
    puts "\n📊 Comparing: #{diagram_type}"
    puts "-" * 60
    reference_dir = "spec/fixtures_mermaid/#{diagram_type}"
    return report_missing_references(diagram_type) unless
      Dir.exist?(reference_dir)

    require "sirena"
    results = compare_sources(diagram_type, reference_dir)
    print_comparison_results(results)
  end

  private

  def similar_structure?(svg1, svg2)
    # Basic structural comparison
    # Check for similar element counts
    svg1_elements = svg1.scan(/<\w+/).length
    svg2_elements = svg2.scan(/<\w+/).length

    # Allow 20% variation
    (svg1_elements - svg2_elements).abs < (svg2_elements * 0.2)
  end

  def report_missing_references(diagram_type)
    puts "⚠️  No reference fixtures found. Run:"
    puts "   rake mermaid:generate_fixtures[#{diagram_type}]"
  end

  def compare_sources(diagram_type, reference_dir)
    results = { matches: 0, differences: 0 }
    Dir.glob("spec/mermaid/#{diagram_type}/*.mmd").each do |file|
      key = comparison_result(file, reference_dir)
      results[key] += 1 if key
    end
    results
  end

  def comparison_result(file, reference_dir)
    reference = File.join(reference_dir, "#{File.basename(file, '.mmd')}.svg")
    return unless File.exist?(reference)

    source = File.read(file)
    source_matches_reference?(source, reference) ? :matches : :differences
  end

  def source_matches_reference?(source, reference)
    similar_structure?(Sirena.render(source), File.read(reference))
  rescue StandardError
    false
  end

  def print_comparison_results(results)
    matches = results[:matches]
    differences = results[:differences]
    total = matches + differences
    return puts "⚠️  No comparisons performed" unless total.positive?

    percentage = (matches.to_f / total * 100)
    puts "✅ #{matches}/#{total} similar (#{percentage.round(1)}%)"
    puts "⚠️  #{differences} differences" if differences.positive?
  end

  # Test validator class
  class TestValidator
    def self.name = "MermaidTestValidator"

    def validate_all
      require "sirena"

      results = {}

      MermaidFixtureGenerator::DIAGRAM_TYPES.each do |type|
        results[type] = validate_type(type)
      end

      results
    end

    private

    def validate_type(diagram_type)
      sources = Dir.glob("spec/mermaid/#{diagram_type}/*.mmd")
      passing = sources.count { |file| source_renderable?(File.read(file)) }
      { total: sources.length, passing: passing,
        failing: sources.length - passing }
    end

    def source_renderable?(source)
      Sirena.render(source)
      true
    rescue StandardError
      false
    end
  end
end

MermaidTestValidator = MermaidOutputComparator::TestValidator
