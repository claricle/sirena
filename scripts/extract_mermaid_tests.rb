#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive test extraction from mermaid-js repository
# Extracts ALL Mermaid diagram test cases for sirena validation

require "fileutils"
require "json"
require_relative "corpus_case_identity"
require_relative "corpus_refresh"

SIRENA_ROOT = File.expand_path("..", __dir__)
OUTPUT_DIR = "#{SIRENA_ROOT}/spec/mermaid".freeze

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
  zenuml: /^zenuml/i,
}.freeze

# naming: :stable writes <type>/<slug>-<hash8>.mmd from CorpusCaseIdentity.
# :ordinal retains the old NNN_<name>.mmd layout only for migration tooling.
# Stable IDs are computed in both modes, so a collision fails before any write.
class MermaidTestExtractor
  class TestCase
    attr_accessor :name,
                  :diagram_type,
                  :source,
                  :source_file,
                  :line_number,
                  :metadata,
                  :stable_id

    def initialize(name:, type:, source:, file:, **properties)
      @name = name
      @diagram_type = type
      @source = source
      @source_file = file
      @line_number = properties.delete(:line) { missing_line! }
      @metadata = properties.delete(:metadata) { {} }
      reject_unknown_properties!(properties)
    end

    # The CorpusCaseIdentity record for this case. The title is the upstream
    # test name when the extractor found one; the rest are identified by
    # path and source alone.
    def identity_record(root:)
      { type: diagram_type.to_s,
        upstream_path: source_file.sub(root, ""),
        title: metadata[:test_name],
        source: source }
    end

    def to_mmd_filename
      safe_name = name.gsub(/[^a-zA-Z0-9_-]/, "_").downcase
      "#{safe_name}.mmd"
    end

    private

    def missing_line!
      raise ArgumentError, "missing keyword: :line"
    end

    def reject_unknown_properties!(properties)
      return if properties.empty?

      keys = properties.keys.map(&:inspect).join(", ")
      noun = properties.size == 1 ? "keyword" : "keywords"
      raise ArgumentError, "unknown #{noun}: #{keys}"
    end
  end

  NAMINGS = %i[ordinal stable].freeze

  def initialize(root:, commit_sha:, output_dir: OUTPUT_DIR,
                 naming: :stable, accept_changes: false)
    validate_options!(naming, commit_sha)
    @root = root
    @output_dir = output_dir
    @naming = naming
    @commit_sha = commit_sha
    @accept_changes = accept_changes
    @test_cases = []
    @stats = Hash.new(0)
    @file_stats = Hash.new(0)
  end

  def validate_options!(naming, commit_sha)
    unless commit_sha
      raise CorpusRefresh::Error, "commit sha is required"
    end

    CorpusRefresh.validate_sha!(commit_sha)
    return if NAMINGS.include?(naming)

    raise ArgumentError, "naming must be one of #{NAMINGS.inspect}"
  end

  def extract_all
    print_extraction_header

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

  def print_extraction_header
    puts "Extracting Mermaid tests from #{@root}"
    puts "=" * 80
    puts "Searching for #{DIAGRAM_TYPES.keys.length} diagram types"
    puts "=" * 80
  end

  def extract_cypress_configuration_tests
    file = "#{@root}/cypress/integration/other/configuration.spec.js"
    return unless File.exist?(file)

    puts "\n[1/7] Extracting from configuration.spec.js..."
    keywords = diagram_keywords(escape_pipes: true)
    count = scan_diagrams(file, /`((?:#{keywords})[^`]*)`/mi,
                          family: "config", minimum: 5)
    @file_stats[file] += count
    puts "  Found #{@file_stats[file]} tests"
  end

  def extract_cypress_rendering_tests
    puts "\n[2/7] Extracting from cypress/integration/rendering/*.{js,ts}..."
    keywords = diagram_keywords
    patterns = [/`((?:#{keywords})[^`]*)`/mi,
                /'((?:#{keywords})[^']*(?:\n[^']*)*?)'/mi]
    extract_files("#{@root}/cypress/integration/rendering/*.{js,ts}",
                  patterns, family: "rendering")
  end

  def extract_cypress_platform_tests
    puts "\n[3/7] Extracting from cypress/platform/*.html..."
    patterns = [/<pre\s+class="mermaid"[^>]*>(.*?)<\/pre>/mi,
                /<div\s+class="mermaid"[^>]*>(.*?)<\/div>/mi]
    extract_files("#{@root}/cypress/platform/**/*.html", patterns,
                  family: "platform", html: true)
  end

  def extract_package_examples
    puts "\n[4/7] Extracting from packages/examples/src/examples/*.ts..."
    keywords = diagram_keywords
    patterns = [/diagram\s*:\s*`((?:#{keywords})[^`]*)`/mi,
                /(?:code|src)\s*:\s*`((?:#{keywords})[^`]*)`/mi]
    extract_files("#{@root}/packages/examples/src/examples/*.ts", patterns,
                  family: "example")
  end

  def extract_diagram_parser_tests
    puts "\n[5/7] Extracting from packages/mermaid/src/diagrams/" \
         "**/*.{spec,test}.{ts,js}..."
    glob = "#{@root}/packages/mermaid/src/diagrams/**/*.{spec,test}.{ts,js}"
    Dir.glob(glob).each do |file|
      content = File.read(file)
      count = scan_parser_callbacks(file, content)
      count += scan_parser_templates(file, content)
      report_file(file, count)
    end
  end

  def scan_parser_callbacks(file, content)
    pattern = /
      (?:it|test)\s*\(\s*['"]([^'"]+)['"]\s*,\s*
      (?:function\s*\(\s*\)\s*\{|\(\s*\)\s*=>|
         async\s*(?:function\s*)?\(\s*\)\s*(?:=>)?\s*\{)
      (.*?)(?:parser\.parse|expect)
    /mix
    scan_diagrams(file, pattern, family: "parser", callback: true,
                                 minimum: 5, content: content)
  end

  def scan_parser_templates(file, content)
    keywords = diagram_keywords
    pattern = /
      (?:it|test)\s*\(\s*['"]([^'"]+)['"]\s*,.*?
      `((?:#{keywords})[^`]*)`
    /mix
    scan_diagrams(file, pattern, family: "parser", content: content)
  end

  def extract_parser_tests
    puts "\n[6/7] Extracting from packages/parser/tests/" \
         "*.{spec,test}.{ts,js}..."
    keywords = diagram_keywords
    extract_files("#{@root}/packages/parser/tests/**/*.{spec,test}.{ts,js}",
                  [/`((?:#{keywords})[^`]*)`/mi], family: "parsertest")
  end

  def extract_rendering_spec_files
    puts "\n[7/7] Scanning additional spec files..."
    patterns = ["#{@root}/cypress/integration/**/*.spec.{js,ts}",
                "#{@root}/packages/mermaid/src/**/*.spec.{ts,js}"]
    patterns.each do |glob|
      Dir.glob(glob).each { |file| extract_additional_file(file) }
    end
  end

  def extract_additional_file(file)
    return if @file_stats[file]&.positive?

    keywords = diagram_keywords
    count = scan_diagrams(file, /[`'"]((?:#{keywords})[^`'"]*)[`'"]/mi,
                          family: "spec", minimum: 5)
    report_file(file, count) if count.positive?
  end

  def extract_files(glob, patterns, **options)
    Dir.glob(glob).each do |file|
      content = File.read(file)
      count = patterns.sum do |pattern|
        scan_diagrams(file, pattern, **options, content: content)
      end
      report_file(file, count)
    end
  end

  def report_file(file, count)
    @file_stats[file] = count
    puts "  #{File.basename(file)}: #{count} tests" if count.positive?
  end

  def scan_diagrams(file, pattern, **options)
    content = options.fetch(:content) { File.read(file) }
    count = 0
    content.scan(pattern) do
      match = Regexp.last_match
      count += 1 if collect_diagram?(file, content, match, options)
    end
    count
  end

  def collect_diagram?(file, content, match, options)
    source = matched_source(match, options)
    type = detect_diagram_type(source)
    return false if unusable_source?(source, type, options)

    title = match[1] if options[:family] == "parser"
    add_test(name: extracted_name(file, type, title, options[:family]),
             type: type, source: source.strip, file: file,
             line: content[0...match.begin(0)].count("\n"),
             metadata: title ? { test_name: title } : {})
    true
  end

  def unusable_source?(source, type, options)
    type == :unknown || source.length < options.fetch(:minimum, 0)
  end

  def matched_source(match, options)
    source = options[:family] == "parser" ? match[2] : match[1]
    return callback_source(source) if options[:callback]

    source = source.strip
    options[:html] ? decode_html(source) : source
  end

  def callback_source(body)
    match = /const\s+str\s*=\s*([^;]+);/mi.match(body)
    match ? extract_concatenated_string(match[1]) : ""
  end

  def decode_html(source)
    source.gsub("&lt;", "<").gsub("&gt;", ">").gsub("&amp;", "&")
  end

  def extracted_name(file, type, title, family)
    return "parser_#{sanitize_test_name(title)}_#{@stats[type]}" if title
    return "config_#{type}_#{@stats[type]}" if family == "config"

    basename = File.basename(file, ".*")
    parts = [family, basename]
    parts << type if %w[rendering platform].include?(family)
    parts << @stats[type]
    parts.join("_")
  end

  def diagram_keywords(escape_pipes: false)
    sources = DIAGRAM_TYPES.values.map do |pattern|
      pattern.source.gsub(/[\\^$]/, "")
    end
    return sources.join("|") unless escape_pipes

    sources.map { |source| source.gsub("|", '\\|') }.join("|")
  end

  def extract_concatenated_string(str_value)
    parts = []
    # Match both single and double quoted strings, handling escaped characters
    str_value.scan(/['"]([^'"\\]*(?:\\.[^'"\\]*)*)['"]/) do |match|
      parts << match[0].gsub("\\n", "\n")
        .gsub("\\t", "\t")
        .gsub('\\"', '"')
        .gsub("\\'", "'")
    end
    parts.join
  end

  def detect_diagram_type(source)
    return :unknown if source.nil? || source.empty?

    # Try each diagram type pattern
    DIAGRAM_TYPES.each do |type, pattern|
      return type if pattern.match?(source.strip)
    end

    :unknown
  end

  def sanitize_test_name(name)
    name.gsub(/[^a-zA-Z0-9_-]/, "_").squeeze("_")
  end

  def add_test(name:, type:, source:, file:, **)
    @test_cases << TestCase.new(
      name: name,
      type: type,
      source: source,
      file: file,
      **,
    )
    @stats[type] += 1
  end

  def organize_and_save
    puts "\n#{'=' * 80}"
    puts "Organizing extracted tests..."
    puts "=" * 80

    assign_stable_ids
    CorpusRefresh.replace(@output_dir, accept_changes: @accept_changes) do |s|
      write_cases(s)
    end
  end

  def write_cases(dir)
    @test_cases.group_by(&:diagram_type).each do |type, cases|
      FileUtils.mkdir_p("#{dir}/#{type}")
      cases.each_with_index { |test_case, idx| save_case(dir, test_case, idx) }
      puts "  ✓ #{type}: #{cases.length} test cases"
    end
  end

  # Raises CorpusCaseIdentity::CollisionError before anything is written.
  def assign_stable_ids
    records = @test_cases.map { |tc| tc.identity_record(root: @root) }
    ids = CorpusCaseIdentity.assign_ids(records).map { |r| r[:id] }
    @test_cases.zip(ids) { |test_case, id| test_case.stable_id = id }
  end

  def save_case(dir, test_case, idx)
    filename = case_basename(dir, test_case, idx)
    File.write("#{filename}.mmd", test_case.source)
    File.write("#{filename}.meta.json",
               JSON.pretty_generate(meta_for(test_case)))
  end

  def case_basename(dir, test_case, idx)
    return "#{dir}/#{test_case.stable_id}" if @naming == :stable

    "#{dir}/#{test_case.diagram_type}/#{format('%03d', idx + 1)}_" \
      "#{test_case.to_mmd_filename.delete_suffix('.mmd')}"
  end

  def meta_for(test_case)
    meta = {
      name: test_case.name,
      type: test_case.diagram_type,
      source_file: test_case.source_file.sub(@root, ""),
      line_number: test_case.line_number,
      metadata: test_case.metadata,
    }
    meta[:case_id] = test_case.stable_id if @naming == :stable
    meta[:upstream_sha] = @commit_sha
    meta
  end

  def print_summary
    puts "\n#{'=' * 80}"
    puts "EXTRACTION COMPLETE"
    puts "=" * 80
    puts "Total test cases extracted: #{@test_cases.length}"
    puts "Files processed: #{@file_stats.length}"
    print_type_summary
    puts "\nOutput directory: #{@output_dir}"
    print_missing_types
    print_next_steps
  end

  def print_type_summary
    puts "\nBy diagram type (sorted by count):"
    @stats.sort_by { |_, count| -count }.each do |type, count|
      puts "  #{sprintf('%-20s', type)}: #{sprintf('%4d', count)} tests"
    end
  end

  def print_missing_types
    missing = DIAGRAM_TYPES.keys - @stats.keys
    return unless missing.any?

    puts "\nDiagram types with no tests found:"
    missing.each { |type| puts "  ⚠ #{type}" }
  end

  def print_next_steps
    puts "\nNext steps:"
    puts "  1. Review extracted tests in spec/mermaid/"
    puts "  2. Run: ruby scripts/create_diagram_inventory.rb"
    puts "  3. Generate fixtures: bundle exec rake " \
         "fixtures:generate_from_mermaidjs"
    puts "  4. Create RSpec tests for each type"
  end
end

TestCase = MermaidTestExtractor::TestCase

if $PROGRAM_NAME == __FILE__
  require "optparse"
  options = { naming: :stable, accept_changes: false }
  OptionParser.new do |o|
    o.on("--root PATH", "mermaid-js checkout") { |v| options[:root] = v }
    o.on("--sha SHA", "checkout commit sha") { |v| options[:commit_sha] = v }
    o.on("--ordinal-ids", "use legacy ordinal names") do
      options[:naming] = :ordinal
    end
    o.on("--accept-changes", "allow counts/provenance to differ") do
      options[:accept_changes] = true
    end
  end.parse!
  abort "--root is required" unless options[:root]
  abort "--sha is required" unless options[:commit_sha]
  begin
    MermaidTestExtractor.new(**options).extract_all
  rescue CorpusRefresh::Error, CorpusCaseIdentity::Error => e
    abort "#{e.class}: #{e.message}"
  end
end
