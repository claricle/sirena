# frozen_string_literal: true

# A task file and its helpers, not library code. The cop wants one
# class per file, which is right for lib/ and wrong for a script whose
# helpers exist only to serve it.
# rubocop:disable Style/OneClassPerFile
require "fileutils"
require "date"
require "digest"
require "json"
require "open3"
require "rexml/document"
require_relative "../scripts/hardened_mmdc"
require_relative "../scripts/mermaid_toolchain"

namespace :mermaid do
  desc "Generate SVG fixtures from mermaid-js for comparison and testing"
  task :generate_fixtures, [:diagram_type] do |_t, args|
    diagram_type = args[:diagram_type] || "all"

    puts "Generating Mermaid.js fixtures for: #{diagram_type}"
    puts "=" * 60

    MermaidToolchain.verify_toolchain
    mmdc_version, status = Open3.capture2e(*MermaidToolchain.version_command)
    raise "pinned mermaid-cli failed: #{mmdc_version}" unless status.success?

    puts "✅ Found pinned mermaid-cli: #{mmdc_version.strip}"
    puts

    generator = MermaidFixtureGenerator.new

    if diagram_type == "all"
      generator.generate_all_fixtures
    else
      generator.generate_fixtures_for_type(diagram_type)
    end
  end

  desc "Generate missing oracle-valid references with pinned provenance"
  task :generate_missing_references do
    generated = MermaidReferenceGenerator.new.generate
    puts "Generated #{generated.length} missing Mermaid reference(s)"
  end

  desc "Check generated Mermaid reference provenance and checksums"
  task :check_reference_provenance do
    checked = MermaidReferenceGenerator.new.verify_provenance!
    puts "Verified #{checked} generated Mermaid reference(s)"
  end

  desc "Compare Sirena output with Mermaid.js reference fixtures"
  task :compare, [:diagram_type] do |_t, args|
    diagram_type = args[:diagram_type] || "all"

    puts "Comparing Sirena vs Mermaid.js output for: #{diagram_type}"
    puts "=" * 60
    puts

    comparator = MermaidOutputComparator.new

    if diagram_type == "all"
      comparator.compare_all_types
    else
      comparator.compare_type(diagram_type)
    end
  end

  desc "Validate all Sirena parsers against Mermaid test suite"
  task :validate do
    puts "Validating Sirena parsers against Mermaid test suite"
    puts "=" * 60
    puts

    validator = MermaidTestValidator.new
    results = validator.validate_all

    puts "\n#{'=' * 60}"
    puts "VALIDATION SUMMARY"
    puts "=" * 60

    results.each do |type, result|
      status = result[:passing] == result[:total] ? "✅" : "⚠️ "
      puts format("%<type>-20s %<status>s %<passing>3d/%<total>3d passing " \
                  "(%<rate>.1f%%)",
                  type: type, status: status, passing: result[:passing],
                  total: result[:total],
                  rate: result[:passing].to_f / result[:total] * 100)
    end

    total_passing = results.values.sum { |r| r[:passing] }
    total_tests = results.values.sum { |r| r[:total] }
    overall_pct = (total_passing.to_f / total_tests * 100)

    puts format("\n%<label>-20s    %<passing>3d/%<total>3d passing " \
                "(%<rate>.1f%%)",
                label: "OVERALL", passing: total_passing,
                total: total_tests, rate: overall_pct)
  end
end

# Generates only missing reference SVGs for the current parity blockers.
class MermaidReferenceGenerator
  class ConflictError < StandardError; end
  class GenerationError < StandardError; end

  TARGETS = {
    class_diagram: "class",
    gantt: "gantt",
    git_graph: "gitgraph",
  }.freeze
  CASE_PATH = %r{\A[a-z0-9_]+/[A-Za-z0-9_.-]+\.mmd\z}
  UNKNOWN_UPSTREAM = "unknown: corpus metadata has no upstream commit SHA"
  Reference = Data.define(
    :cases,
    :source_path,
    :reference_path,
    :source_sha256,
    :metadata,
  )

  def initialize(root: File.expand_path("..", __dir__),
                 toolchain: MermaidToolchain,
                 runner: HardenedMmdc,
                 detector: nil,
                 canary: nil)
    @root = root
    @toolchain = toolchain
    @runner = runner
    @detector = detector || method(:detect_type)
    @canary = canary || -> { toolchain.render_canary }
  end

  def generate
    references = missing_references
    return verify_provenance! && [] if references.empty?

    toolchain_provenance = toolchain.verify_toolchain
    canary.call
    generated = []
    records = references.map do |reference|
      generate_reference(reference).tap { generated << reference.reference_path }
    end
    write_provenance(records, toolchain_provenance)
    references
  rescue StandardError
    generated&.each { |path| FileUtils.rm_f(path) }
    raise
  end

  def verify_provenance!
    records = read_provenance.fetch("references")
    records.each { |record| verify_record!(record) }
    records.length
  rescue Errno::ENOENT, KeyError, JSON::ParserError => e
    raise GenerationError, "invalid reference provenance: #{e.message}"
  end

  def missing_references
    cases = target_cases
    index = existing_reference_index(cases)
    grouped = cases.select { |entry| unresolved_reference?(entry, index) }
      .group_by { |entry| entry[:reference_path] }
    reject_conflicts!(grouped)
    grouped.map { |_path, entries| build_reference(entries) }
      .sort_by(&:reference_path)
  end

  private

  attr_reader :root, :toolchain, :runner, :detector, :canary

  def target_cases
    corpus_rows.filter_map do |row|
      next unless row["verdict"] == "valid" && row["pass"] == true

      target_case(row.fetch("case"))
    end
  end

  def target_case(case_id)
    validate_case_id!(case_id)
    source_path = File.join(root, "spec", "mermaid", case_id)
    source = File.binread(source_path)
    type = detector.call(source).to_sym
    directory = TARGETS[type]
    return unless directory

    basename = "#{File.basename(case_id, '.mmd')}.svg"
    {
      case_id: case_id,
      source_path: source_path,
      source_sha256: Digest::SHA256.hexdigest(source),
      reference_path: File.join(reference_root, directory, basename),
      metadata: source_metadata(source_path),
    }
  end

  def validate_case_id!(case_id)
    return if case_id.match?(CASE_PATH)

    raise GenerationError, "invalid corpus case path: #{case_id.inspect}"
  end

  def corpus_rows
    JSON.parse(File.read(File.join(root, "scoreboard", "corpus.json")))
  end

  def source_metadata(source_path)
    path = source_path.sub(/\.mmd\z/, ".meta.json")
    JSON.parse(File.read(path))
  rescue Errno::ENOENT
    {}
  end

  def detect_type(source)
    require "sirena"
    body = Sirena::Source.split(source).fetch(:body)
    Sirena::Notation::Mermaid.detect_type(body)
  end

  def reject_conflicts!(grouped)
    conflict = grouped.find do |_path, entries|
      entries.map { |entry| entry[:source_sha256] }.uniq.length > 1
    end
    return unless conflict

    path, entries = conflict
    cases = entries.map { |entry| entry[:case_id] }.join(", ")
    raise ConflictError, "conflicting sources target #{relative(path)}: #{cases}"
  end

  def existing_reference_index(cases)
    cases.select { |entry| File.file?(entry[:reference_path]) }
      .group_by { |entry| entry[:source_sha256] }
  end

  def unresolved_reference?(entry, index)
    return false if File.file?(entry[:reference_path])

    twins = index.fetch(entry[:source_sha256], []).select do |candidate|
      File.binread(candidate[:source_path]) == File.binread(entry[:source_path])
    end
    return true if twins.empty?

    twins.map { |candidate| File.binread(candidate[:reference_path]) }
      .uniq.length != 1
  end

  def build_reference(entries)
    first = entries.first
    Reference.new(
      cases: entries.map { |entry| entry[:case_id] }.sort,
      source_path: first[:source_path],
      reference_path: first[:reference_path],
      source_sha256: first[:source_sha256],
      metadata: first[:metadata],
    )
  end

  def generate_reference(reference)
    FileUtils.mkdir_p(File.dirname(reference.reference_path))
    arguments = render_arguments(reference)
    status, diagnostic = runner.run_mmdc(
      reference.source_path,
      reference.reference_path,
    )
    validate_render!(reference.reference_path, status, diagnostic)
    provenance_record(reference, arguments)
  end

  def render_arguments(reference)
    ["-i", reference.source_path, "-o", reference.reference_path]
  end

  def validate_render!(path, status, diagnostic)
    document = REXML::Document.new(File.read(path)) if File.file?(path)
    root_element = document&.root
    valid = status&.success? && root_element&.name == "svg" &&
      root_element.attributes["aria-roledescription"] != "error"
    return if valid

    raise GenerationError, "pinned mmdc failed for #{relative(path)}: #{diagnostic}"
  rescue REXML::ParseException => e
    raise GenerationError, "pinned mmdc wrote invalid SVG for " \
                           "#{relative(path)}: #{e.message}"
  end

  def provenance_record(reference, arguments)
    metadata = reference.metadata
    {
      "reference" => relative(reference.reference_path),
      "cases" => reference.cases,
      "source_sha256" => reference.source_sha256,
      "upstream_sha" => metadata["upstream_sha"],
      "upstream_sha_status" => metadata["upstream_sha"] ? "recorded" : UNKNOWN_UPSTREAM,
      "upstream_source_file" => metadata["source_file"],
      "upstream_line_number" => metadata["line_number"],
      "generated_on" => Date.today.iso8601,
      "command" => reproducible_command(arguments),
      "output_sha256" => Digest::SHA256.file(reference.reference_path).hexdigest,
    }
  end

  def reproducible_command(arguments)
    toolchain.command(*arguments).map { |argument| relative(argument) }
  end

  def write_provenance(new_records, toolchain_provenance)
    current = provenance_file? ? read_provenance.fetch("references") : []
    merged = (current + new_records).sort_by { |record| record.fetch("reference") }
    payload = {
      "schema" => 1,
      "toolchain" => toolchain_provenance,
      "references" => merged,
    }
    atomic_write(provenance_path, "#{JSON.pretty_generate(payload)}\n")
  end

  def atomic_write(path, contents)
    temporary = "#{path}.tmp-#{Process.pid}"
    File.write(temporary, contents)
    File.rename(temporary, path)
  ensure
    FileUtils.rm_f(temporary) if temporary
  end

  def verify_record!(record)
    reference = File.join(root, record.fetch("reference"))
    source = File.join(root, "spec", "mermaid", record.fetch("cases").first)
    verify_hash!(reference, record.fetch("output_sha256"), "output")
    verify_hash!(source, record.fetch("source_sha256"), "source")
    raise GenerationError, "missing exact command for #{relative(reference)}" if record.fetch("command").empty?
  end

  def verify_hash!(path, expected, label)
    actual = Digest::SHA256.file(path).hexdigest
    return if actual == expected

    raise GenerationError, "#{label} checksum mismatch for #{relative(path)}"
  rescue Errno::ENOENT
    raise GenerationError, "missing #{label} file #{relative(path)}"
  end

  def provenance_file?
    File.file?(provenance_path)
  end

  def read_provenance
    JSON.parse(File.read(provenance_path))
  end

  def provenance_path
    File.join(reference_root, "reference-provenance.json")
  end

  def reference_root
    File.join(root, "spec", "fixtures_mermaid")
  end

  def relative(path)
    value = path.to_s
    prefix = "#{root}/"
    value.start_with?(prefix) ? value.delete_prefix(prefix) : value
  end
end

# Fixture generator class
class MermaidFixtureGenerator
  FIXTURE_DIR = "spec/fixtures_mermaid"
  FAIL_NOTE = "Should have failed but succeeded"

  # Supported diagram types in Sirena
  DIAGRAM_TYPES = %w[
    flowchart sequence class er state user_journey
    gantt pie timeline quadrant gitgraph
    mindmap radar c4 architecture requirement
    block xychart sankey info error packet treemap kanban
  ].freeze

  def initialize
    FileUtils.mkdir_p(FIXTURE_DIR)
  end

  def generate_all_fixtures
    DIAGRAM_TYPES.each do |type|
      generate_fixtures_for_type(type)
    end
  end

  def generate_fixtures_for_type(diagram_type)
    puts "\n🔄 Generating fixtures for: #{diagram_type}"
    puts "-" * 60

    # Find all mermaid files for this type
    mmd_files = Dir.glob("spec/mermaid/#{diagram_type}/*.mmd")

    if mmd_files.empty?
      puts "⚠️  No .mmd files found for #{diagram_type}"
      return
    end

    # Create output directories
    output_dir = File.join(FIXTURE_DIR, diagram_type)
    correct_dir = File.join(output_dir, "correct")
    expected_errors_dir = File.join(output_dir, "expected_errors")
    FileUtils.mkdir_p([correct_dir, expected_errors_dir])

    stats = {
      correct_success: 0,
      correct_unexpected_fail: 0,
      error_expected_fail: 0,
      error_unexpected_success: 0,
    }
    unexpected_failures = []
    unexpected_successes = []

    mmd_files.each_with_index do |mmd_file, idx|
      basename = File.basename(mmd_file, ".mmd")
      error_marker = mmd_file.sub(".mmd", ".error")
      has_error_marker = File.exist?(error_marker)

      # Determine output location
      target_dir = has_error_marker ? expected_errors_dir : correct_dir
      output_file = File.join(target_dir, "#{basename}.svg")

      # Generate SVG using mermaid-cli
      success, error_msg = generate_svg_with_error(mmd_file, output_file)

      # Evaluate result based on expectations
      if has_error_marker
        # File is EXPECTED to fail
        if success
          # Succeeded but should have failed - UNEXPECTED
          stats[:error_unexpected_success] += 1
          unexpected_successes << { file: basename, note: FAIL_NOTE }
          print "U"  # U = Unexpected success (fail)
        else
          # Failed as expected - this is CORRECT
          stats[:error_expected_fail] += 1
          print "E"  # E = Expected error (pass)
        end
      else
        # File is EXPECTED to succeed
        if success
          # Succeeded as expected - this is CORRECT
          stats[:correct_success] += 1
          print "."  # . = Correct success (pass)
        else
          # Failed but should have succeeded - UNEXPECTED
          stats[:correct_unexpected_fail] += 1
          unexpected_failures << { file: basename, error: error_msg }
          print "F"  # F = Unexpected failure (fail)
        end
      end

      # Progress indicator every 50 files
      if ((idx + 1) % 50).zero?
        puts " [#{idx + 1}/#{mmd_files.length}]"
      end
    end

    puts if mmd_files.length % 50 != 0

    # Print summary
    puts "\n#{'=' * 60}"
    puts "RESULTS SUMMARY"
    puts "=" * 60
    correct = stats[:correct_success] + stats[:error_expected_fail]
    puts "✅ Correct behaviors: #{correct}"
    puts "   - Generated fixtures: #{stats[:correct_success]}"
    puts "   - Failed as expected: #{stats[:error_expected_fail]}"

    total_unexpected = unexpected_count(stats)
    if total_unexpected.positive?
      puts "\n⚠️  Unexpected behaviors: #{total_unexpected}"
      puts "   - Should succeed but failed: #{stats[:correct_unexpected_fail]}"
      puts "   - Should fail but succeeded: #{stats[:error_unexpected_success]}"

      if stats[:correct_unexpected_fail].positive?
        puts "\n  Unexpected failures (first 10):"
        unexpected_failures.first(10).each do |f|
          puts "    #{f[:file]}: #{f[:error]}"
        end
      end

      if stats[:error_unexpected_success].positive?
        puts "\n  Unexpected successes (first 10):"
        unexpected_successes.first(10).each do |f|
          puts "    #{f[:file]}: #{f[:note]}"
        end
      end

      # Save detailed logs
      if stats[:correct_unexpected_fail].positive?
        fail_log = File.join(output_dir, "_unexpected_failures.log")
        failure_lines = format_log_lines(unexpected_failures, :error)
        File.write(fail_log, failure_lines.join("\n"))
        puts "\n📝 Failure log: #{fail_log}"
      end

      if stats[:error_unexpected_success].positive?
        success_log = File.join(output_dir, "_unexpected_successes.log")
        success_lines = format_log_lines(unexpected_successes, :note)
        File.write(success_log, success_lines.join("\n"))
        puts "📝 Success log: #{success_log}"
      end
    end

    # Calculate pass rate
    total = mmd_files.length
    passing = stats[:correct_success] + stats[:error_expected_fail]
    pass_rate = (passing.to_f / total * 100).round(1)
    puts "\n🎯 Pass rate: #{passing}/#{total} (#{pass_rate}%)"
  end

  private

  def unexpected_count(stats)
    stats.values_at(:correct_unexpected_fail, :error_unexpected_success).sum
  end

  def format_log_lines(entries, field)
    entries.map { "#{_1[:file]}: #{_1[field]}" }
  end

  def generate_svg_with_error(input_file, output_file)
    stdout, stderr, status = Open3.capture3(
      MermaidToolchain.environment,
      *MermaidToolchain.command("-i", input_file, "-o", output_file,
                                "-b", "transparent"),
    )

    if status.success?
      [true, nil]
    else
      # Extract meaningful error message
      error_msg = (stderr + stdout).lines
                    .reject do |line|
                      line.include?("Generating single mermaid chart")
                    end
                    .first&.strip || "Unknown error"
      [false, error_msg]
    end
  end
end

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

    unless Dir.exist?(reference_dir)
      puts "⚠️  No reference fixtures found. Run:"
      puts "   rake mermaid:generate_fixtures[#{diagram_type}]"
      return
    end

    require "sirena"

    mmd_files = Dir.glob("spec/mermaid/#{diagram_type}/*.mmd")
    matches = 0
    differences = 0

    mmd_files.each do |mmd_file|
      basename = File.basename(mmd_file, ".mmd")
      reference_svg = File.join(reference_dir, "#{basename}.svg")

      next unless File.exist?(reference_svg)

      # Generate with Sirena
      source = File.read(mmd_file)
      begin
        sirena_svg = Sirena.render(source)

        # Basic comparison (structure, not exact match)
        if similar_structure?(sirena_svg, File.read(reference_svg))
          matches += 1
        else
          differences += 1
        end
      rescue StandardError
        differences += 1
      end
    end

    total = matches + differences
    if total.positive?
      pct = (matches.to_f / total * 100)
      puts "✅ #{matches}/#{total} similar (#{pct.round(1)}%)"
      puts "⚠️  #{differences} differences" if differences.positive?
    else
      puts "⚠️  No comparisons performed"
    end
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
end

# Test validator class
class MermaidTestValidator
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
    mmd_files = Dir.glob("spec/mermaid/#{diagram_type}/*.mmd")

    passing = 0
    failing = 0

    mmd_files.each do |file|
      source = File.read(file)
      begin
        Sirena.render(source)
        passing += 1
      rescue StandardError
        failing += 1
      end
    end

    {
      total: mmd_files.length,
      passing: passing,
      failing: failing,
    }
  end
end
# rubocop:enable Style/OneClassPerFile
