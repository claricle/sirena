require "fileutils"
require_relative "../scripts/mermaid_toolchain"

module MermaidFixtureTasks
  DIAGRAM_MAPPINGS = {
    "flowchart_example.mmd" => "flowchart",
    "sequence_example.mmd" => "sequence",
    "class_diagram_example.mmd" => "class_diagram",
    "state_diagram_example.mmd" => "state_diagram",
    "er_diagram_example.mmd" => "er_diagram",
    "user_journey_example.mmd" => "user_journey",
  }.freeze

  module_function

  def generate
    puts "Generating reference SVGs using mermaid-js CLI..."
    DIAGRAM_MAPPINGS.each { |input, type| generate_fixture(input, type) }
    puts "\nDone! Generated reference SVGs for testing."
  end

  def generate_fixture(input_file, diagram_type)
    input_path = File.expand_path("../examples/#{input_file}", __dir__)
    output_dir = File.expand_path("../spec/fixtures/#{diagram_type}", __dir__)
    return warn_missing(input_path) unless File.exist?(input_path)

    FileUtils.mkdir_p(output_dir)
    output_path = File.join(output_dir, "expected.svg")
    puts "  Generating #{diagram_type}/expected.svg..."
    puts generation_result(input_path, output_path)
  end

  def warn_missing(input_path)
    puts "  Warning: Input file not found: #{input_path}"
  end

  def generation_result(input_path, output_path)
    generated = system(
      MermaidToolchain.environment,
      *MermaidToolchain.command("-i", input_path, "-o", output_path),
    )
    if generated
      "    ✓ Generated #{output_path}"
    else
      "    ✗ Failed to generate #{output_path}"
    end
  end
end

namespace :fixtures do
  desc "Generate reference SVGs using mermaid-js CLI"
  task :generate_from_mermaidjs do
    MermaidFixtureTasks.generate
  end
end
