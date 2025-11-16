# frozen_string_literal: true

require 'fileutils'
require 'json'

namespace :mermaid do
  desc 'Generate SVG fixtures from mermaid-js for comparison and testing'
  task :generate_fixtures, [:diagram_type] do |_t, args|
    diagram_type = args[:diagram_type] || 'all'

    puts "Generating Mermaid.js fixtures for: #{diagram_type}"
    puts "=" * 60

    # Check if mermaid-cli (mmdc) is installed
    unless system('which mmdc > /dev/null 2>&1')
      puts "\n❌ ERROR: mermaid-cli not found!"
      puts "\nPlease install mermaid-cli:"
      puts "  npm install -g @mermaid-js/mermaid-cli"
      puts "\nOr using yarn:"
      puts "  yarn global add @mermaid-js/mermaid-cli"
      exit 1
    end

    # Get mermaid-cli version
    mmdc_version = `mmdc --version`.strip
    puts "✅ Found mermaid-cli: #{mmdc_version}"
    puts

    generator = MermaidFixtureGenerator.new

    if diagram_type == 'all'
      generator.generate_all_fixtures
    else
      generator.generate_fixtures_for_type(diagram_type)
    end
  end

  desc 'Compare Sirena output with Mermaid.js reference fixtures'
  task :compare, [:diagram_type] do |_t, args|
    diagram_type = args[:diagram_type] || 'all'

    puts "Comparing Sirena vs Mermaid.js output for: #{diagram_type}"
    puts "=" * 60
    puts

    comparator = MermaidOutputComparator.new

    if diagram_type == 'all'
      comparator.compare_all_types
    else
      comparator.compare_type(diagram_type)
    end
  end

  desc 'Validate all Sirena parsers against Mermaid test suite'
  task :validate do
    puts "Validating Sirena parsers against Mermaid test suite"
    puts "=" * 60
    puts

    validator = MermaidTestValidator.new
    results = validator.validate_all

    puts "\n" + "=" * 60
    puts "VALIDATION SUMMARY"
    puts "=" * 60

    results.each do |type, result|
      status = result[:passing] == result[:total] ? '✅' : '⚠️ '
      puts format("%-20s %s %3d/%3d passing (%.1f%%)",
                  type, status, result[:passing], result[:total],
                  (result[:passing].to_f / result[:total] * 100))
    end

    total_passing = results.values.sum { |r| r[:passing] }
    total_tests = results.values.sum { |r| r[:total] }
    overall_pct = (total_passing.to_f / total_tests * 100)

    puts "\n%-20s    %3d/%3d passing (%.1f%%)" %
         ["OVERALL", total_passing, total_tests, overall_pct]
  end
end

# Fixture generator class
class MermaidFixtureGenerator
  FIXTURE_DIR = 'spec/fixtures_mermaid'

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
    correct_dir = File.join(output_dir, 'correct')
    expected_errors_dir = File.join(output_dir, 'expected_errors')
    FileUtils.mkdir_p([correct_dir, expected_errors_dir])

    stats = {
      correct_success: 0,
      correct_unexpected_fail: 0,
      error_expected_fail: 0,
      error_unexpected_success: 0
    }
    unexpected_failures = []
    unexpected_successes = []

    mmd_files.each_with_index do |mmd_file, idx|
      basename = File.basename(mmd_file, '.mmd')
      error_marker = mmd_file.sub('.mmd', '.error')
      has_error_marker = File.exist?(error_marker)

      # Determine output location
      target_dir = has_error_marker ? expected_errors_dir : correct_dir
      output_file = File.join(target_dir, "#{basename}.svg")

      # Generate SVG using mermaid-cli
      success, error_msg = generate_svg_with_error(mmd_file, output_file)

      # Evaluate result based on expectations
      if has_error_marker
        # File is EXPECTED to fail
        if !success
          # Failed as expected - this is CORRECT
          stats[:error_expected_fail] += 1
          print 'E'  # E = Expected error (pass)
        else
          # Succeeded but should have failed - UNEXPECTED
          stats[:error_unexpected_success] += 1
          unexpected_successes << { file: basename, note: 'Should have failed but succeeded' }
          print 'U'  # U = Unexpected success (fail)
        end
      else
        # File is EXPECTED to succeed
        if success
          # Succeeded as expected - this is CORRECT
          stats[:correct_success] += 1
          print '.'  # . = Correct success (pass)
        else
          # Failed but should have succeeded - UNEXPECTED
          stats[:correct_unexpected_fail] += 1
          unexpected_failures << { file: basename, error: error_msg }
          print 'F'  # F = Unexpected failure (fail)
        end
      end

      # Progress indicator every 50 files
      if (idx + 1) % 50 == 0
        puts " [#{idx + 1}/#{mmd_files.length}]"
      end
    end

    puts if mmd_files.length % 50 != 0

    # Print summary
    puts "\n" + "=" * 60
    puts "RESULTS SUMMARY"
    puts "=" * 60
    puts "✅ Correct behaviors: #{stats[:correct_success] + stats[:error_expected_fail]}"
    puts "   - Generated fixtures: #{stats[:correct_success]}"
    puts "   - Failed as expected: #{stats[:error_expected_fail]}"

    total_unexpected = stats[:correct_unexpected_fail] + stats[:error_unexpected_success]
    if total_unexpected > 0
      puts "\n⚠️  Unexpected behaviors: #{total_unexpected}"
      puts "   - Should succeed but failed: #{stats[:correct_unexpected_fail]}"
      puts "   - Should fail but succeeded: #{stats[:error_unexpected_success]}"

      if stats[:correct_unexpected_fail] > 0
        puts "\n  Unexpected failures (first 10):"
        unexpected_failures.first(10).each do |f|
          puts "    #{f[:file]}: #{f[:error]}"
        end
      end

      if stats[:error_unexpected_success] > 0
        puts "\n  Unexpected successes (first 10):"
        unexpected_successes.first(10).each do |f|
          puts "    #{f[:file]}: #{f[:note]}"
        end
      end

      # Save detailed logs
      if stats[:correct_unexpected_fail] > 0
        fail_log = File.join(output_dir, '_unexpected_failures.log')
        File.write(fail_log, unexpected_failures.map { |f|
          "#{f[:file]}: #{f[:error]}"
        }.join("\n"))
        puts "\n📝 Failure log: #{fail_log}"
      end

      if stats[:error_unexpected_success] > 0
        success_log = File.join(output_dir, '_unexpected_successes.log')
        File.write(success_log, unexpected_successes.map { |f|
          "#{f[:file]}: #{f[:note]}"
        }.join("\n"))
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

  def generate_svg_with_error(input_file, output_file)
    # Use mermaid-cli to generate SVG, capture stderr for errors
    require 'open3'

    cmd = "mmdc -i '#{input_file}' -o '#{output_file}' -b transparent"
    stdout, stderr, status = Open3.capture3(cmd)

    if status.success?
      [true, nil]
    else
      # Extract meaningful error message
      error_msg = (stderr + stdout).lines
                    .reject { |l| l.include?('Generating single mermaid chart') }
                    .first&.strip || 'Unknown error'
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

    require 'sirena'

    mmd_files = Dir.glob("spec/mermaid/#{diagram_type}/*.mmd")
    matches = 0
    differences = 0

    mmd_files.each do |mmd_file|
      basename = File.basename(mmd_file, '.mmd')
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
      rescue => e
        differences += 1
      end
    end

    total = matches + differences
    if total > 0
      pct = (matches.to_f / total * 100)
      puts "✅ #{matches}/#{total} similar (#{pct.round(1)}%)"
      puts "⚠️  #{differences} differences" if differences > 0
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
    require 'sirena'

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
      rescue => e
        failing += 1
      end
    end

    {
      total: mmd_files.length,
      passing: passing,
      failing: failing
    }
  end
end