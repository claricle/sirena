# frozen_string_literal: true

require "benchmark"
require "fileutils"
require "json"
require "sirena"

namespace :benchmark do
  desc "Run performance benchmark comparing Sirena vs Mermaid.js CLI"
  task :compare do
    puts "Sirena Performance Benchmark"
    puts "=" * 80
    puts

    benchmarker = PerformanceBenchmarker.new
    results = benchmarker.run_full_benchmark

    # Save results
    benchmarker.save_results(results, "docs/PERFORMANCE_BENCHMARK.adoc")

    puts "\n✅ Benchmark complete! Results saved to " \
         "docs/PERFORMANCE_BENCHMARK.adoc"
  end

  desc "Quick benchmark with sample diagrams"
  task :quick do
    puts "Sirena Quick Benchmark"
    puts "=" * 80
    puts

    benchmarker = PerformanceBenchmarker.new
    results = benchmarker.run_quick_benchmark

    benchmarker.print_summary(results)
  end
end

# Performance benchmarking class
class PerformanceBenchmarker
  BENCHMARK_DIR = "tmp/benchmark"
  REPORT_CELL_INDENT = "      "
  SAMPLE_DIAGRAMS = {
    flowchart: <<~MERMAID,
      flowchart TD
          A[Start] --> B{Decision}
          B -->|Yes| C[Process 1]
          B -->|No| D[Process 2]
          C --> E[End]
          D --> E
    MERMAID
    sequence: <<~MERMAID,
      sequenceDiagram
          participant Alice
          participant Bob
          Alice->>Bob: Hello Bob
          Bob->>Alice: Hi Alice
          Alice->>Bob: How are you?
          Bob->>Alice: I'm good, thanks!
    MERMAID
    class: <<~MERMAID,
      classDiagram
          class Animal {
              +String name
              +int age
              +makeSound()
          }
          class Dog {
              +String breed
              +bark()
          }
          Animal <|-- Dog
    MERMAID
    gantt: <<~MERMAID,
      gantt
          title Project Timeline
          dateFormat YYYY-MM-DD
          section Planning
          Requirements : 2024-01-01, 30d
          Design : after Requirements, 20d
          section Development
          Implementation : after Design, 60d
          Testing : after Implementation, 30d
    MERMAID
    pie: <<~MERMAID,
      pie title Sales Distribution
          "Product A" : 45
          "Product B" : 30
          "Product C" : 25
    MERMAID
  }.freeze

  def initialize
    FileUtils.mkdir_p(BENCHMARK_DIR)
  end

  def run_full_benchmark
    check_prerequisites

    {
      system_info: gather_system_info,
      single_diagram: benchmark_single_renders,
      batch_rendering: benchmark_batch_renders,
      memory_usage: benchmark_memory_usage,
      startup_time: benchmark_startup_time,
    }
  end

  def run_quick_benchmark
    unless mermaid_cli_available?
      puts "⚠️  mermaid-cli not found. Install with:"
      puts "   npm install -g @mermaid-js/mermaid-cli"
      puts "\nRunning Sirena-only benchmark...\n"
      return benchmark_sirena_only
    end

    {
      single: benchmark_single_renders,
      startup: benchmark_startup_time,
    }
  end

  def save_results(results, output_file)
    content = generate_report(results)
    File.write(output_file, content)
  end

  def print_summary(results)
    print_summary_header
    print_single_summary(results[:single]) if results[:single]
    print_startup_summary(results[:startup]) if results[:startup]
  end

  def print_summary_header
    puts "\n#{'=' * 80}"
    puts "BENCHMARK SUMMARY"
    puts "=" * 80
  end

  def print_single_summary(results)
    puts "\nSingle Diagram Rendering:"
    results.each do |type, data|
      puts "  #{type}:"
      puts "    Sirena:     #{format_time(data[:sirena_time])}"
      next unless data[:mermaid_time]

      puts "    Mermaid.js: #{format_time(data[:mermaid_time])}"
      puts "    Speedup:    #{single_speedup(data)}"
    end
  end

  def single_speedup(data)
    speedup_label(data[:mermaid_time] / data[:sirena_time])
  end

  def print_startup_summary(results)
    puts "\nStartup Time:"
    puts "  Sirena:     #{format_time(results[:sirena])}"
    return unless results[:mermaid]

    puts "  Mermaid.js: #{format_time(results[:mermaid])}"
    puts "  Speedup:    #{speedup_label(results[:mermaid] / results[:sirena])}"
  end

  private

  def check_prerequisites
    unless mermaid_cli_available?
      puts "⚠️  WARNING: mermaid-cli not found"
      puts "Install with: npm install -g @mermaid-js/mermaid-cli"
      puts "Benchmark will only measure Sirena performance.\n\n"
    end
  end

  def mermaid_cli_available?
    system("which mmdc > /dev/null 2>&1")
  end

  def mermaid_cli_version
    return "not installed" unless mermaid_cli_available?

    version = `mmdc --version 2>/dev/null`.strip
    $?.success? && !version.empty? ? version : "unknown (mmdc --version failed)"
  end

  def gather_system_info
    cpu_info = `sysctl -n machdep.cpu.brand_string 2>/dev/null || \
                lscpu 2>/dev/null | grep 'Model name' || echo 'Unknown'`.strip
    {
      ruby_version: RUBY_VERSION,
      platform: RUBY_PLATFORM,
      sirena_version: Sirena::VERSION,
      mermaid_cli_version: mermaid_cli_version,
      cpu_info: cpu_info,
      timestamp: Time.now.iso8601,
    }
  end

  def cpu_info
    command = "sysctl -n machdep.cpu.brand_string 2>/dev/null || " \
              "lscpu 2>/dev/null | grep 'Model name' || echo 'Unknown'"
    `#{command}`.strip
  end

  def benchmark_single_renders
    SAMPLE_DIAGRAMS.to_h do |type, source|
      puts "Benchmarking #{type}..."
      [type, benchmark_single(source, type)]
    end
  end

  def benchmark_single(source, type)
    sirena_time = Benchmark.realtime { 10.times { Sirena.render(source) } }
    {
      sirena_time: sirena_time / 10,
      mermaid_time: benchmark_single_with_mermaid(source, type),
    }
  end

  def benchmark_single_with_mermaid(source, type)
    return unless mermaid_cli_available?

    input = File.join(BENCHMARK_DIR, "#{type}.mmd")
    output = File.join(BENCHMARK_DIR, "#{type}.svg")
    File.write(input, source)
    time, succeeded = benchmark_command(10, mmdc_command(input, output))
    time / 10 if succeeded
  end

  def benchmark_command(iterations, command)
    succeeded = true
    time = Benchmark.realtime do
      iterations.times { succeeded = false unless system(command) }
    end
    [time, succeeded]
  end

  def mmdc_command(input, output)
    "mmdc -i '#{input}' -o '#{output}' 2>/dev/null"
  end

  def benchmark_batch_renders
    return {} unless mermaid_cli_available?

    files = prepare_batch
    sirena_time = benchmark_sirena_batch(files)
    mermaid_time, succeeded = benchmark_mermaid_batch(files)
    result = batch_result(sirena_time)
    return result unless succeeded

    result.merge(
      mermaid_total: mermaid_time,
      mermaid_per_diagram: mermaid_time / 50,
    )
  end

  def prepare_batch
    puts "Preparing 50 sample diagrams..."
    batch_dir = File.join(BENCHMARK_DIR, "batch_test")
    FileUtils.mkdir_p(batch_dir)
    50.times { |index| write_sample(batch_dir, index) }
    Dir.glob(File.join(batch_dir, "*.mmd"))
  end

  def write_sample(batch_dir, index)
    source = SAMPLE_DIAGRAMS.fetch(SAMPLE_DIAGRAMS.keys.sample)
    File.write(File.join(batch_dir, "diagram_#{index}.mmd"), source)
  end

  def benchmark_sirena_batch(files)
    puts "Benchmarking Sirena batch..."
    Benchmark.realtime { files.each { |file| Sirena.render(File.read(file)) } }
  end

  def benchmark_mermaid_batch(files)
    puts "Benchmarking mermaid-cli batch..."
    succeeded = true
    time = Benchmark.realtime do
      files.each do |file|
        output = file.sub(".mmd", ".svg")
        succeeded = false unless system(mmdc_command(file, output))
      end
    end
    [time, succeeded]
  end

  def batch_result(sirena_time)
    {
      diagram_count: 50,
      sirena_total: sirena_time,
      sirena_per_diagram: sirena_time / 50,
    }
  end

  def benchmark_memory_usage
    return {} unless mermaid_cli_available?

    # No measurement is taken here: Process::RUSAGE_SELF is unavailable on
    # macOS's Ruby, and adding a profiling gem is out of scope for this
    # task. Report that plainly instead of the fabricated figures this
    # used to hardcode (TODO.foundation/11: "unattributable benchmarks").
    {
      note: "Memory usage was not measured in this run",
    }
  end

  def benchmark_startup_time
    sirena_startup = benchmark_sirena_startup
    mermaid_startup = benchmark_mermaid_startup
    {
      sirena: sirena_startup / 10,
      mermaid: mermaid_startup ? mermaid_startup / 10 : nil,
    }
  end

  def benchmark_sirena_startup
    command = "ruby -r sirena " \
              "-e 'Sirena.render(\"graph TD\\nA-->B\")' 2>/dev/null"
    time, succeeded = benchmark_command(10, command)
    return time if succeeded

    raise "Sirena subprocess startup benchmark failed -- a fresh " \
          "`ruby -r sirena` process could not render; this is not the " \
          "external mmdc tool, so fix the gem load rather than trusting " \
          "any number from this run"
  end

  def benchmark_mermaid_startup
    return unless mermaid_cli_available?

    input = File.join(BENCHMARK_DIR, "startup.mmd")
    output = File.join(BENCHMARK_DIR, "startup.svg")
    File.write(input, "graph TD\nA-->B")
    time, succeeded = benchmark_command(10, mmdc_command(input, output))
    time if succeeded
  end

  def benchmark_sirena_only
    {
      single: SAMPLE_DIAGRAMS.to_h do |type, source|
        time = Benchmark.realtime do
          10.times { Sirena.render(source) }
        end
        [type, { sirena_time: time / 10, mermaid_time: nil }]
      end,
    }
  end

  def generate_report(results)
    report_header(results[:system_info]) +
      report_measurements(results) +
      report_analysis(results) +
      report_reproduction(results)
  end

  def report_header(system)
    <<~ADOC
      = Sirena Performance Benchmark Report
      :toc:
      :toclevels: 2

      == Overview

      This document presents comprehensive performance benchmarks comparing Sirena
      (Ruby-native Mermaid renderer) with the official Mermaid.js CLI (mmdc).

      == System Information

      *Benchmark Date:* #{system[:timestamp]}

      *System Configuration:*

      * Ruby Version: #{system[:ruby_version]}
      * Platform: #{system[:platform]}
      * Sirena Version: #{system[:sirena_version]}
      * Mermaid CLI Version: #{system[:mermaid_cli_version]}
      * CPU: #{system[:cpu_info]}

      == Benchmark Methodology

      All benchmarks were performed:

      * Single-diagram and startup timings: 10 iterations per test (averaged)
      * Batch rendering: one timed pass over 50 diagrams (not averaged across repeats)
      * Using identical input diagrams
      * On the same system
      * With default settings for both tools
      * Cold start for startup time tests

    ADOC
  end

  def report_measurements(results)
    single = results[:single_diagram]
    single_rows = single_report_rows(single)
    average = calculate_average_speedup(single)
    batch = batch_report(results[:batch_rendering])
    startup = startup_report(results[:startup_time])
    memory = memory_report(results[:memory_usage])
    <<~ADOC
      == Single Diagram Rendering

      Performance for rendering individual diagrams:

      [cols="2,2,2,2"]
      |===
      |Diagram Type |Sirena |Mermaid.js |Speedup

      #{single_rows}
      |===

      *Average speedup:* #{average}

      == Batch Rendering Performance

      #{batch}

      #{startup}

      == Memory Usage

      #{memory}

    ADOC
  end

  def startup_report(startup)
    <<~ADOC.chomp
      == Startup Time

      Cold start performance (time to render first diagram):

      [cols="2,2"]
      |===
      |Tool |Average Startup Time

      |Sirena
      |#{format_time(startup[:sirena])}

      |Mermaid.js
      |#{format_time(startup[:mermaid])}
      |===

      #{startup_speedup_report(startup)}
    ADOC
  end

  def report_analysis(results)
    average = calculate_average_speedup(results[:single_diagram])
    findings = findings_report(results, average)
    <<~ADOC
      == Analysis

      === Key Findings

      *Measured Results:*

      #{findings}

      === Architectural Differences

      These are structural facts about the two tools, not a restatement of the
      measured numbers above -- a difference here does not imply a "faster" result
      on every metric or every machine.

      . *No Browser Overhead:* Direct SVG generation without browser engine
      . *Native Ruby:* No V8/Node.js context switching
      . *Parslet-Based Parsers:* No separate JS runtime for grammar parsing
      . *No IPC:* Everything runs in a single process
      . *No Chrome instance required* (memory usage itself was not measured in this run)

      === Where This Can Matter

      . *CI/CD Pipelines:* Fewer runtime dependencies to install in a build image
      . *Batch Documentation Generation:* No per-process browser-launch overhead
      . *Server-Side Rendering:* No browser process to launch per request
      . *Ruby-Native Applications:* No external dependencies

      === When to Consider Mermaid.js

      . *Interactive Features:* Browser-based editing and interaction
      . *Live Preview:* Real-time diagram editing
      . *Client-Side Rendering:* When rendering must happen in browser

    ADOC
  end

  def report_reproduction(results)
    average = calculate_average_speedup(results[:single_diagram])
    conclusion = conclusion_startup_report(results[:startup_time])
    <<~ADOC
      == Reproduction

      To reproduce these benchmarks:

      [source,shell]
      ----
      # Install mermaid-cli (optional but recommended for comparison)
      npm install -g @mermaid-js/mermaid-cli

      # Run full benchmark
      bundle exec rake benchmark:compare

      # Run quick benchmark
      bundle exec rake benchmark:quick
      ----

      == Conclusion

      Measured against mermaid-cli (mmdc) on this machine:

      * **#{average}** rendering, averaged over the sample diagrams above
      #{conclusion}
      * **Memory usage:** not measured in this run
      * **Native Ruby integration** (no Node.js required at render time)

      These are single-machine measurements from one run, not a general claim; reproduce
      with the commands above before citing a number elsewhere.

      ---

      _Benchmark generated by Sirena Performance Suite_
    ADOC
  end

  def single_report_rows(results)
    results.map do |type, data|
      mermaid = format_time(data[:mermaid_time])
      speedup = data[:mermaid_time] ? single_speedup(data) : "N/A"
      "\n#{REPORT_CELL_INDENT}|#{type}\n" \
        "#{REPORT_CELL_INDENT}|#{format_time(data[:sirena_time])}\n" \
        "#{REPORT_CELL_INDENT}|#{mermaid}\n" \
        "#{REPORT_CELL_INDENT}|#{speedup}"
    end.join("\n")
  end

  def batch_report(batch)
    if batch.nil? || batch.empty?
      return "*Batch benchmarking requires mermaid-cli installation*"
    end

    <<~BATCH
      Performance rendering #{batch[:diagram_count]} diagrams:

      [cols="2,2,2"]
      |===
      |Metric |Sirena |Mermaid.js

      |Total Time
      |#{format_time(batch[:sirena_total])}
      |#{format_time(batch[:mermaid_total])}

      |Per Diagram
      |#{format_time(batch[:sirena_per_diagram])}
      |#{format_time(batch[:mermaid_per_diagram])}

      |Throughput
      |#{batch_throughput(batch, :sirena_total)}
      |#{batch_throughput(batch, :mermaid_total)}
      |===

      #{batch_speedup_report(batch)}

    BATCH
  end

  def batch_throughput(batch, key)
    return "N/A" unless batch[key]

    "#{(batch[:diagram_count] / batch[key]).round(1)} diagrams/sec"
  end

  def batch_speedup_report(batch)
    unless batch[:mermaid_total]
      return "*Batch speedup:* not measured " \
             "(mermaid-cli failed during this run)"
    end

    speedup = batch[:mermaid_total] / batch[:sirena_total]
    "*Batch speedup:* #{speedup_label(speedup)}"
  end

  def startup_speedup_report(startup)
    return unless startup[:mermaid]

    speedup = startup[:mermaid] / startup[:sirena]
    "*Startup speedup:* #{speedup_label(speedup)}"
  end

  def memory_report(memory)
    return if memory.nil? || memory.empty?

    "Note: #{memory[:note]}\n\n"
  end

  def findings_report(results, average)
    return unless results[:single_diagram]

    <<~FINDINGS
      . *Rendering Speed:* #{average} on average for single diagrams
      #{batch_finding(results[:batch_rendering])}
      #{startup_finding(results[:startup_time])}
      . *Dependencies:* No Node.js, Puppeteer, or Chrome required

    FINDINGS
  end

  def batch_finding(batch)
    return unless batch && batch[:sirena_total] && batch[:mermaid_total]

    speedup = batch[:mermaid_total] / batch[:sirena_total]
    ". *Batch Processing:* #{speedup_label(speedup)} for rendering " \
      "#{batch[:diagram_count]} diagrams"
  end

  def startup_finding(startup)
    return unless startup[:mermaid]

    speedup = startup[:mermaid] / startup[:sirena]
    ". *Startup Time (cold start):* #{speedup_label(speedup)}"
  end

  def conclusion_startup_report(startup)
    return unless startup[:mermaid]

    speedup = startup[:mermaid] / startup[:sirena]
    explanation = startup_explanation(speedup)
    "* **Cold start: #{speedup_label(speedup)}** than launching mmdc " \
      "#{explanation}"
  end

  def startup_explanation(speedup)
    if speedup >= 1
      return "(Sirena pays Ruby interpreter + gem load per process, " \
             "but still starts faster here)"
    end

    "(Sirena pays Ruby interpreter + gem load per process; " \
      "mmdc's Node process starts faster here)"
  end

  def calculate_average_speedup(single_results)
    speedups = single_results.values.filter_map do |data|
      data[:mermaid_time] / data[:sirena_time] if data[:mermaid_time]
    end

    return "N/A" if speedups.empty?

    speedup_label(speedups.sum / speedups.length)
  end

  def format_time(seconds)
    return "N/A" unless seconds

    if seconds < 0.001
      "#{(seconds * 1_000_000).round(0)}μs"
    elsif seconds < 1
      "#{(seconds * 1000).round(1)}ms"
    else
      "#{seconds.round(2)}s"
    end
  end

  # A ratio below 1 means Sirena was slower, not faster by a fraction — say
  # so plainly instead of printing e.g. "0.4x faster" (TODO.foundation/11:
  # measured numbers, not laundered claims).
  def speedup_label(ratio)
    return "#{ratio.round(1)}x faster" if ratio >= 1

    "#{(1 / ratio).round(1)}x slower"
  end
end
