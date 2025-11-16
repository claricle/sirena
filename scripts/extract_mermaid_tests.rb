#!/usr/bin/env ruby
# Comprehensive test extraction from mermaid-js repository
# Extracts ALL Mermaid diagram test cases for sirena validation

require 'fileutils'
require 'json'

MERMAID_JS_ROOT = "/Users/mulgogi/src/external/mermaid-js"
SIRENA_ROOT = File.expand_path('../..', __FILE__)
OUTPUT_DIR = "#{SIRENA_ROOT}/spec/mermaid"

# All Mermaid diagram types discovered from packages/mermaid/src/diagrams/
DIAGRAM_TYPES = {
  architecture: /^architecture/i,
  block: /^block-beta|^block\s/i,
  c4: /^C4/i,
  class: /^classDiagram/i,
  er: /^erDiagram/i,
  error: /^error/i,
  flowchart: /^(?:graph|flowchart)\s/i,
  gantt: /^gantt/i,
  git: /^gitGraph/i,
  info: /^info/i,
  kanban: /^kanban/i,
  mindmap: /^mindmap/i,
  packet: /^packet-beta/i,
  pie: /^pie/i,
  quadrant: /^quadrantChart/i,
  radar: /^radar/i,
  requirement: /^requirementDiagram/i,
  sankey: /^sankey-beta/i,
  sequence: /^sequenceDiagram/i,
  state: /^stateDiagram/i,
  timeline: /^timeline/i,
  treemap: /^treemap/i,
  user_journey: /^journey/i,
  xychart: /^xychart-beta/i,
  zenuml: /^zenuml/i
}.freeze

# Test case structure
class TestCase
  attr_accessor :name, :diagram_type, :source, :source_file, :line_number, :metadata

  def initialize(name:, type:, source:, file:, line:, metadata: {})
    @name = name
    @diagram_type = type
    @source = source
    @source_file = file
    @line_number = line
    @metadata = metadata
  end

  def to_mmd_filename
    safe_name = name.gsub(/[^a-zA-Z0-9_-]/, '_').downcase
    "#{safe_name}.mmd"
  end
end

class MermaidTestExtractor
  def initialize
    @test_cases = []
    @stats = Hash.new(0)
    @file_stats = Hash.new(0)
  end

  def extract_all
    puts "Extracting Mermaid tests from #{MERMAID_JS_ROOT}"
    puts "=" * 80
    puts "Searching for #{DIAGRAM_TYPES.keys.length} diagram types"
    puts "=" * 80

    extract_cypress_configuration_tests
    extract_cypress_rendering_tests
    extract_cypress_platform_tests
    extract_package_examples
    extract_diagram_parser_tests
    extract_parser_tests
    extract_rendering_spec_files

    organize_and_save
    print_summary
  end

  private

  # 1. cypress/integration/other/configuration.spec.js - all diagram types
  def extract_cypress_configuration_tests
    file = "#{MERMAID_JS_ROOT}/cypress/integration/other/configuration.spec.js"
    return unless File.exist?(file)

    puts "\n[1/7] Extracting from configuration.spec.js..."
    content = File.read(file)

    # Build regex pattern for all diagram keywords
    keywords = DIAGRAM_TYPES.values.map { |r| r.source.gsub(/[\\^$]/, '').gsub(/\|/, '\\|') }.join('|')

    # Find all backtick diagram blocks
    content.scan(/`((?:#{keywords})[^`]*)`/mi) do
      match_pos = $~.begin(0)
      diagram_src = $1.strip
      next if diagram_src.length < 5

      type = detect_diagram_type(diagram_src)
      next if type == :unknown

      add_test(
        name: "config_#{type}_#{@stats[type]}",
        type: type,
        source: diagram_src,
        file: file,
        line: content[0...match_pos].count("\n")
      )
      @file_stats[file] += 1
    end

    puts "  Found #{@file_stats[file]} tests"
  end

  # 2. cypress/integration/rendering/*.{js,ts} - all rendering tests
  def extract_cypress_rendering_tests
    puts "\n[2/7] Extracting from cypress/integration/rendering/*.{js,ts}..."

    Dir.glob("#{MERMAID_JS_ROOT}/cypress/integration/rendering/*.{js,ts}").each do |file|
      content = File.read(file)
      file_count = 0

      # Pattern 1: Backtick strings
      keywords_pattern = DIAGRAM_TYPES.values.map { |r| r.source.gsub(/[\\^$]/, '') }.join('|')
      content.scan(/`((?:#{keywords_pattern})[^`]*)`/mi) do
        match_pos = $~.begin(0)
        diagram_src = $1.strip
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "rendering_#{File.basename(file, '.*')}_#{type}_#{@stats[type]}",
          type: type,
          source: diagram_src,
          file: file,
          line: content[0...match_pos].count("\n")
        )
        file_count += 1
      end

      # Pattern 2: Single-quoted strings
      content.scan(/'((?:#{keywords_pattern})[^']*(?:\n[^']*)*?)'/mi) do
        match_pos = $~.begin(0)
        diagram_src = $1.strip
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "rendering_#{File.basename(file, '.*')}_#{type}_#{@stats[type]}",
          type: type,
          source: diagram_src,
          file: file,
          line: content[0...match_pos].count("\n")
        )
        file_count += 1
      end

      @file_stats[file] = file_count
      puts "  #{File.basename(file)}: #{file_count} tests" if file_count > 0
    end
  end

  # 3. cypress/platform/*.html - all HTML embedded diagrams
  def extract_cypress_platform_tests
    puts "\n[3/7] Extracting from cypress/platform/*.html..."

    Dir.glob("#{MERMAID_JS_ROOT}/cypress/platform/**/*.html").each do |file|
      content = File.read(file)
      file_count = 0

      # Pattern 1: <pre class="mermaid"> blocks
      content.scan(/<pre\s+class="mermaid"[^>]*>(.*?)<\/pre>/mi) do
        match_pos = $~.begin(0)
        diagram_src = $1.strip
        diagram_src = diagram_src.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/, '&')
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "platform_#{File.basename(file, '.html')}_#{type}_#{@stats[type]}",
          type: type,
          source: diagram_src,
          file: file,
          line: content[0...match_pos].count("\n")
        )
        file_count += 1
      end

      # Pattern 2: <div class="mermaid"> blocks
      content.scan(/<div\s+class="mermaid"[^>]*>(.*?)<\/div>/mi) do
        match_pos = $~.begin(0)
        diagram_src = $1.strip
        diagram_src = diagram_src.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/, '&')
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "platform_#{File.basename(file, '.html')}_#{type}_#{@stats[type]}",
          type: type,
          source: diagram_src,
          file: file,
          line: content[0...match_pos].count("\n")
        )
        file_count += 1
      end

      @file_stats[file] = file_count
      puts "  #{File.basename(file)}: #{file_count} tests" if file_count > 0
    end
  end

  # 4. packages/examples/src/examples/*.ts - official examples
  def extract_package_examples
    puts "\n[4/7] Extracting from packages/examples/src/examples/*.ts..."

    Dir.glob("#{MERMAID_JS_ROOT}/packages/examples/src/examples/*.ts").each do |file|
      content = File.read(file)
      file_count = 0

      # Pattern 1: diagram: `...`
      keywords_pattern = DIAGRAM_TYPES.values.map { |r| r.source.gsub(/[\\^$]/, '') }.join('|')
      content.scan(/diagram\s*:\s*`((?:#{keywords_pattern})[^`]*)`/mi) do
        match_pos = $~.begin(0)
        diagram_src = $1.strip
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "example_#{File.basename(file, '.ts')}_#{@stats[type]}",
          type: type,
          source: diagram_src,
          file: file,
          line: content[0...match_pos].count("\n")
        )
        file_count += 1
      end

      # Pattern 2: code: `...` or src: `...`
      content.scan(/(?:code|src)\s*:\s*`((?:#{keywords_pattern})[^`]*)`/mi) do
        match_pos = $~.begin(0)
        diagram_src = $1.strip
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "example_#{File.basename(file, '.ts')}_#{@stats[type]}",
          type: type,
          source: diagram_src,
          file: file,
          line: content[0...match_pos].count("\n")
        )
        file_count += 1
      end

      @file_stats[file] = file_count
      puts "  #{File.basename(file)}: #{file_count} tests" if file_count > 0
    end
  end

  # 5. packages/mermaid/src/diagrams/**/*.{spec,test}.{ts,js} - parser tests
  def extract_diagram_parser_tests
    puts "\n[5/7] Extracting from packages/mermaid/src/diagrams/**/*.{spec,test}.{ts,js}..."

    Dir.glob("#{MERMAID_JS_ROOT}/packages/mermaid/src/diagrams/**/*.{spec,test}.{ts,js}").each do |file|
      content = File.read(file)
      file_count = 0

      # Pattern 1: it/test with const str = string concatenation
      content.scan(/(?:it|test)\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:function\s*\(\s*\)\s*\{|\(\s*\)\s*=>|async\s*(?:function\s*)?\(\s*\)\s*(?:=>)?\s*\{)(.*?)(?:parser\.parse|expect)/mi) do
        match_pos = $~.begin(0)
        test_name = $1
        test_body = $2
        if test_body =~ /const\s+str\s*=\s*([^;]+);/mi
          str_value = $1
          diagram_src = extract_concatenated_string(str_value)
          type = detect_diagram_type(diagram_src)
          next if type == :unknown || diagram_src.length < 5

          add_test(
            name: "parser_#{sanitize_test_name(test_name)}_#{@stats[type]}",
            type: type,
            source: diagram_src.strip,
            file: file,
            line: content[0...match_pos].count("\n"),
            metadata: { test_name: test_name }
          )
          file_count += 1
        end
      end

      # Pattern 2: Direct backtick strings in tests
      keywords_pattern = DIAGRAM_TYPES.values.map { |r| r.source.gsub(/[\\^$]/, '') }.join('|')
      content.scan(/(?:it|test)\s*\(\s*['"]([^'"]+)['"]\s*,.*?`((?:#{keywords_pattern})[^`]*)`/mi) do
        match_pos = $~.begin(0)
        test_name = $1
        diagram_src = $2
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "parser_#{sanitize_test_name(test_name)}_#{@stats[type]}",
          type: type,
          source: diagram_src.strip,
          file: file,
          line: content[0...match_pos].count("\n"),
          metadata: { test_name: test_name }
        )
        file_count += 1
      end

      @file_stats[file] = file_count
      puts "  #{File.basename(file)}: #{file_count} tests" if file_count > 0
    end
  end

  # 6. packages/parser/tests/*.{spec,test}.{ts,js} - parser package tests
  def extract_parser_tests
    puts "\n[6/7] Extracting from packages/parser/tests/*.{spec,test}.{ts,js}..."

    Dir.glob("#{MERMAID_JS_ROOT}/packages/parser/tests/**/*.{spec,test}.{ts,js}").each do |file|
      content = File.read(file)
      file_count = 0

      keywords_pattern = DIAGRAM_TYPES.values.map { |r| r.source.gsub(/[\\^$]/, '') }.join('|')

      # Backtick strings
      content.scan(/`((?:#{keywords_pattern})[^`]*)`/mi) do
        match_pos = $~.begin(0)
        diagram_src = $1.strip
        type = detect_diagram_type(diagram_src)
        next if type == :unknown

        add_test(
          name: "parsertest_#{File.basename(file, '.*')}_#{@stats[type]}",
          type: type,
          source: diagram_src,
          file: file,
          line: content[0...match_pos].count("\n")
        )
        file_count += 1
      end

      @file_stats[file] = file_count
      puts "  #{File.basename(file)}: #{file_count} tests" if file_count > 0
    end
  end

  # 7. Additional rendering spec files
  def extract_rendering_spec_files
    puts "\n[7/7] Scanning additional spec files..."

    # Check for any missed spec files
    additional_patterns = [
      "#{MERMAID_JS_ROOT}/cypress/integration/**/*.spec.{js,ts}",
      "#{MERMAID_JS_ROOT}/packages/mermaid/src/**/*.spec.{ts,js}"
    ]

    additional_patterns.each do |pattern|
      Dir.glob(pattern).each do |file|
        next if @file_stats[file] && @file_stats[file] > 0 # Skip already processed

        content = File.read(file)
        file_count = 0

        keywords_pattern = DIAGRAM_TYPES.values.map { |r| r.source.gsub(/[\\^$]/, '') }.join('|')

        content.scan(/[`'"]((?:#{keywords_pattern})[^`'"]*)[`'"]/mi) do
          match_pos = $~.begin(0)
          diagram_src = $1.strip
          type = detect_diagram_type(diagram_src)
          next if type == :unknown || diagram_src.length < 5

          add_test(
            name: "spec_#{File.basename(file, '.*')}_#{@stats[type]}",
            type: type,
            source: diagram_src,
            file: file,
            line: content[0...match_pos].count("\n")
          )
          file_count += 1
        end

        if file_count > 0
          @file_stats[file] = file_count
          puts "  #{File.basename(file)}: #{file_count} tests"
        end
      end
    end
  end

  def extract_concatenated_string(str_value)
    parts = []
    # Match both single and double quoted strings, handling escaped characters
    str_value.scan(/['"]([^'"\\]*(?:\\.[^'"\\]*)*)['"]/) do |match|
      parts << match[0].gsub(/\\n/, "\n").gsub(/\\t/, "\t").gsub(/\\"/, '"').gsub(/\\'/, "'")
    end
    parts.join('')
  end

  def detect_diagram_type(source)
    return :unknown if source.nil? || source.empty?

    # Try each diagram type pattern
    DIAGRAM_TYPES.each do |type, pattern|
      return type if source.strip =~ pattern
    end

    :unknown
  end

  def sanitize_test_name(name)
    name.gsub(/[^a-zA-Z0-9_-]/, '_').gsub(/_+/, '_')
  end

  def add_test(name:, type:, source:, file:, line:, metadata: {})
    @test_cases << TestCase.new(
      name: name,
      type: type,
      source: source,
      file: file,
      line: line,
      metadata: metadata
    )
    @stats[type] += 1
  end

  def organize_and_save
    puts "\n" + "=" * 80
    puts "Organizing extracted tests..."
    puts "=" * 80

    FileUtils.mkdir_p(OUTPUT_DIR)

    by_type = @test_cases.group_by(&:diagram_type)

    by_type.each do |type, cases|
      type_dir = "#{OUTPUT_DIR}/#{type}"
      FileUtils.mkdir_p(type_dir)

      cases.each_with_index do |test_case, idx|
        filename = "#{type_dir}/#{sprintf('%03d', idx+1)}_#{test_case.to_mmd_filename}"
        File.write(filename, test_case.source)

        # Write metadata
        meta_file = filename.sub('.mmd', '.meta.json')
        File.write(meta_file, JSON.pretty_generate({
          name: test_case.name,
          type: test_case.diagram_type,
          source_file: test_case.source_file.sub(MERMAID_JS_ROOT, ''),
          line_number: test_case.line_number,
          metadata: test_case.metadata
        }))
      end

      puts "  ✓ #{type}: #{cases.length} test cases"
    end
  end

  def print_summary
    puts "\n" + "=" * 80
    puts "EXTRACTION COMPLETE"
    puts "=" * 80
    puts "Total test cases extracted: #{@test_cases.length}"
    puts "Files processed: #{@file_stats.length}"
    puts "\nBy diagram type (sorted by count):"
    @stats.sort_by { |_,v| -v }.each do |type, count|
      puts "  #{sprintf('%-20s', type)}: #{sprintf('%4d', count)} tests"
    end
    puts "\nOutput directory: #{OUTPUT_DIR}"

    # Show diagram types with no tests
    missing = DIAGRAM_TYPES.keys - @stats.keys
    if missing.any?
      puts "\nDiagram types with no tests found:"
      missing.each { |type| puts "  ⚠ #{type}" }
    end

    puts "\nNext steps:"
    puts "  1. Review extracted tests in spec/mermaid/"
    puts "  2. Run: ruby scripts/create_diagram_inventory.rb"
    puts "  3. Generate fixtures: bundle exec rake fixtures:generate_from_mermaidjs"
    puts "  4. Create RSpec tests for each type"
  end
end

# Run extraction
extractor = MermaidTestExtractor.new
extractor.extract_all