# frozen_string_literal: true

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
    sources = Dir.glob("spec/mermaid/#{diagram_type}/*.mmd")
    return print_missing_sources(diagram_type) if sources.empty?

    directories = fixture_directories(diagram_type)
    report = fixture_report
    generate_type_sources(sources, directories, report)
    print_fixture_summary(report, directories[:output], sources.length)
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
    return [true, nil] if status.success?

    [false, fixture_error_message(stderr + stdout)]
  end

  def print_missing_sources(diagram_type)
    puts "⚠️  No .mmd files found for #{diagram_type}"
  end

  def fixture_directories(diagram_type)
    output = File.join(FIXTURE_DIR, diagram_type)
    correct = File.join(output, "correct")
    errors = File.join(output, "expected_errors")
    FileUtils.mkdir_p([correct, errors])
    { output: output, correct: correct, errors: errors }
  end

  def fixture_report
    { stats: { correct_success: 0, correct_unexpected_fail: 0,
               error_expected_fail: 0, error_unexpected_success: 0 },
      unexpected_failures: [], unexpected_successes: [] }
  end

  def generate_type_sources(sources, directories, report)
    sources.each_with_index do |source, index|
      generate_fixture_source(source, directories, report)
      puts " [#{index + 1}/#{sources.length}]" if ((index + 1) % 50).zero?
    end
    puts if sources.length % 50 != 0
  end

  def generate_fixture_source(source, directories, report)
    basename = File.basename(source, ".mmd")
    expected_error = File.exist?(source.sub(".mmd", ".error"))
    target = directories[expected_error ? :errors : :correct]
    output = File.join(target, "#{basename}.svg")
    success, error = generate_svg_with_error(source, output)
    record_fixture_result(report, basename, expected_error, [success, error])
  end

  def record_fixture_result(report, basename, expected_error, result)
    if expected_error
      record_expected_error(report, basename, result.first)
    else
      record_expected_success(report, basename, result)
    end
  end

  def record_expected_error(report, basename, success)
    if success
      report[:stats][:error_unexpected_success] += 1
      report[:unexpected_successes] << { file: basename, note: FAIL_NOTE }
      print "U"
    else
      report[:stats][:error_expected_fail] += 1
      print "E"
    end
  end

  def record_expected_success(report, basename, result)
    success, error = result
    if success
      report[:stats][:correct_success] += 1
      print "."
    else
      report[:stats][:correct_unexpected_fail] += 1
      report[:unexpected_failures] << { file: basename, error: error }
      print "F"
    end
  end

  def print_fixture_summary(report, output_dir, total)
    stats = report[:stats]
    print_correct_summary(stats)
    if unexpected_count(stats).positive?
      print_unexpected_summary(report,
                               output_dir)
    end
    passing = stats[:correct_success] + stats[:error_expected_fail]
    pass_rate = (passing.to_f / total * 100).round(1)
    puts "\n🎯 Pass rate: #{passing}/#{total} (#{pass_rate}%)"
  end

  def print_correct_summary(stats)
    puts "\n#{'=' * 60}"
    puts "RESULTS SUMMARY"
    puts "=" * 60
    correct = stats[:correct_success] + stats[:error_expected_fail]
    puts "✅ Correct behaviors: #{correct}"
    puts "   - Generated fixtures: #{stats[:correct_success]}"
    puts "   - Failed as expected: #{stats[:error_expected_fail]}"
  end

  def print_unexpected_summary(report, output_dir)
    stats = report[:stats]
    puts "\n⚠️  Unexpected behaviors: #{unexpected_count(stats)}"
    puts "   - Should succeed but failed: #{stats[:correct_unexpected_fail]}"
    puts "   - Should fail but succeeded: #{stats[:error_unexpected_success]}"
    print_unexpected_entries(report, stats)
    write_unexpected_logs(report, stats, output_dir)
  end

  def print_unexpected_entries(report, stats)
    if stats[:correct_unexpected_fail].positive?
      puts "\n  Unexpected failures (first 10):"
      print_report_entries(report[:unexpected_failures], :error)
    end
    if stats[:error_unexpected_success].positive?
      puts "\n  Unexpected successes (first 10):"
      print_report_entries(report[:unexpected_successes], :note)
    end
  end

  def print_report_entries(entries, field)
    entries.first(10).each do |entry|
      puts "    #{entry[:file]}: #{entry[field]}"
    end
  end

  def write_unexpected_logs(report, stats, output_dir)
    if stats[:correct_unexpected_fail].positive?
      path = write_report_log(report[:unexpected_failures], :error, output_dir,
                              "_unexpected_failures.log")
      puts "\n📝 Failure log: #{path}"
    end
    if stats[:error_unexpected_success].positive?
      path = write_report_log(report[:unexpected_successes], :note, output_dir,
                              "_unexpected_successes.log")
      puts "📝 Success log: #{path}"
    end
  end

  def write_report_log(entries, field, output_dir, basename)
    path = File.join(output_dir, basename)
    File.write(path, format_log_lines(entries, field).join("\n"))
    path
  end

  def fixture_error_message(output)
    output.lines.reject do |line|
      line.include?("Generating single mermaid chart")
    end.first&.strip || "Unknown error"
  end
end
