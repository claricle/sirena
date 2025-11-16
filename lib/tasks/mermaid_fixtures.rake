namespace :fixtures do
  desc "Generate reference SVGs using mermaid-js CLI"
  task :generate_from_mermaidjs do
    require "fileutils"

    examples_dir = File.expand_path("../../examples", __dir__)
    fixtures_dir = File.expand_path("../../spec/fixtures", __dir__)

    diagram_mappings = {
      "flowchart_example.mmd" => "flowchart",
      "sequence_example.mmd" => "sequence",
      "class_diagram_example.mmd" => "class_diagram",
      "state_diagram_example.mmd" => "state_diagram",
      "er_diagram_example.mmd" => "er_diagram",
      "user_journey_example.mmd" => "user_journey"
    }

    puts "Generating reference SVGs using mermaid-js CLI..."

    diagram_mappings.each do |input_file, diagram_type|
      input_path = File.join(examples_dir, input_file)
      output_dir = File.join(fixtures_dir, diagram_type)
      output_path = File.join(output_dir, "expected.svg")

      unless File.exist?(input_path)
        puts "  Warning: Input file not found: #{input_path}"
        next
      end

      FileUtils.mkdir_p(output_dir)

      command = "mmdc -i #{input_path} -o #{output_path}"
      puts "  Generating #{diagram_type}/expected.svg..."

      system(command)

      if $?.success?
        puts "    ✓ Generated #{output_path}"
      else
        puts "    ✗ Failed to generate #{output_path}"
      end
    end

    puts "\nDone! Generated reference SVGs for testing."
  end
end