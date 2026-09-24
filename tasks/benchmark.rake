# frozen_string_literal: true

require 'benchmark'
require 'fileutils'
require 'json'
require 'sirena'

namespace :benchmark do
  desc 'Run performance benchmark comparing Sirena vs Mermaid.js CLI'
  task :compare do
    puts "Sirena Performance Benchmark"
    puts "=" * 80
    puts

    benchmarker = PerformanceBenchmarker.new
    results = benchmarker.run_full_benchmark

    # Save results
    benchmarker.save_results(results, 'docs/PERFORMANCE_BENCHMARK.adoc')

    puts "\n✅ Benchmark complete! Results saved to docs/PERFORMANCE_BENCHMARK.adoc"
  end

  desc 'Quick benchmark with sample diagrams'
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
  BENCHMARK_DIR = 'tmp/benchmark'
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
    pie: <<~MERMAID
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

    results = {
      system_info: gather_system_info,
      single_diagram: benchmark_single_renders,
      batch_rendering: benchmark_batch_renders,
      memory_usage: benchmark_memory_usage,
      startup_time: benchmark_startup_time
    }

    results
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
      startup: benchmark_startup_time
    }
  end

  def save_results(results, output_file)
    content = generate_report(results)
    File.write(output_file, content)
  end

  def print_summary(results)
    puts "\n" + "=" * 80
    puts "BENCHMARK SUMMARY"
    puts "=" * 80

    if results[:single]
      puts "\nSingle Diagram Rendering:"
      results[:single].each do |type, data|
        puts "  #{type}:"
        puts "    Sirena:     #{format_time(data[:sirena_time])}"
        if data[:mermaid_time]
          puts "    Mermaid.js: #{format_time(data[:mermaid_time])}"
          speedup = data[:mermaid_time] / data[:sirena_time]
          puts "    Speedup:    #{speedup_label(speedup)}"
        end
      end
    end

    if results[:startup]
      puts "\nStartup Time:"
      puts "  Sirena:     #{format_time(results[:startup][:sirena])}"
      if results[:startup][:mermaid]
        puts "  Mermaid.js: #{format_time(results[:startup][:mermaid])}"
        speedup = results[:startup][:mermaid] / results[:startup][:sirena]
        puts "  Speedup:    #{speedup_label(speedup)}"
      end
    end
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
    system('which mmdc > /dev/null 2>&1')
  end

  def mermaid_cli_version
    return 'not installed' unless mermaid_cli_available?

    version = `mmdc --version 2>/dev/null`.strip
    $?.success? && !version.empty? ? version : 'unknown (mmdc --version failed)'
  end

  def gather_system_info
    {
      ruby_version: RUBY_VERSION,
      platform: RUBY_PLATFORM,
      sirena_version: Sirena::VERSION,
      mermaid_cli_version: mermaid_cli_version,
      cpu_info: `sysctl -n machdep.cpu.brand_string 2>/dev/null || lscpu 2>/dev/null | grep 'Model name' || echo 'Unknown'`.strip,
      timestamp: Time.now.iso8601
    }
  end

  def benchmark_single_renders
    results = {}

    SAMPLE_DIAGRAMS.each do |type, source|
      puts "Benchmarking #{type}..."

      # Benchmark Sirena
      sirena_time = Benchmark.realtime do
        10.times { Sirena.render(source) }
      end
      sirena_avg = sirena_time / 10

      # Benchmark mermaid-cli if available
      mermaid_avg = nil
      if mermaid_cli_available?
        input_file = File.join(BENCHMARK_DIR, "#{type}.mmd")
        output_file = File.join(BENCHMARK_DIR, "#{type}.svg")
        File.write(input_file, source)

        mermaid_ok = true
        mermaid_time = Benchmark.realtime do
          10.times do
            mermaid_ok = false unless system("mmdc -i '#{input_file}' -o '#{output_file}' 2>/dev/null")
          end
        end
        # A failed mmdc invocation (e.g. Chrome unavailable) still exits `system`
        # near-instantly -- timing that as a successful render would publish
        # failure latency as a real speedup (TODO.foundation/11: unattributable
        # benchmarks). Report nothing for mermaid rather than a bogus number.
        mermaid_avg = mermaid_time / 10 if mermaid_ok
      end

      results[type] = {
        sirena_time: sirena_avg,
        mermaid_time: mermaid_avg
      }
    end

    results
  end

  def benchmark_batch_renders
    return {} unless mermaid_cli_available?

    # Create 50 sample diagrams
    puts "Preparing 50 sample diagrams..."
    batch_dir = File.join(BENCHMARK_DIR, 'batch_test')
    FileUtils.mkdir_p(batch_dir)

    50.times do |i|
      type = SAMPLE_DIAGRAMS.keys.sample
      source = SAMPLE_DIAGRAMS[type]
      File.write(File.join(batch_dir, "diagram_#{i}.mmd"), source)
    end

    # Benchmark Sirena
    puts "Benchmarking Sirena batch..."
    sirena_time = Benchmark.realtime do
      Dir.glob(File.join(batch_dir, '*.mmd')).each do |file|
        source = File.read(file)
        Sirena.render(source)
      end
    end

    # Benchmark mermaid-cli
    puts "Benchmarking mermaid-cli batch..."
    mermaid_ok = true
    mermaid_time = Benchmark.realtime do
      Dir.glob(File.join(batch_dir, '*.mmd')).each do |file|
        output = file.sub('.mmd', '.svg')
        mermaid_ok = false unless system("mmdc -i '#{file}' -o '#{output}' 2>/dev/null")
      end
    end

    result = {
      diagram_count: 50,
      sirena_total: sirena_time,
      sirena_per_diagram: sirena_time / 50
    }
    # See benchmark_single_renders: a failed mmdc invocation still exits `system`
    # near-instantly, so never publish its timing as a real batch speedup.
    return result unless mermaid_ok

    result.merge(
      mermaid_total: mermaid_time,
      mermaid_per_diagram: mermaid_time / 50
    )
  end

  def benchmark_memory_usage
    return {} unless mermaid_cli_available?

    # No measurement is taken here: Process::RUSAGE_SELF is unavailable on
    # macOS's Ruby, and adding a profiling gem is out of scope for this
    # task. Report that plainly instead of the fabricated figures this
    # used to hardcode (TODO.foundation/11: "unattributable benchmarks").
    {
      note: "Memory usage was not measured in this run"
    }
  end

  def benchmark_startup_time
    # Benchmark Sirena startup. Unlike mmdc, this command is entirely ours (no
    # external tool, no environment dependency) -- a failure here is a real bug,
    # not a flaky dependency, so raise instead of silently timing the failure.
    sirena_ok = true
    sirena_startup = Benchmark.realtime do
      10.times do
        # Simulate fresh start by requiring in subprocess
        sirena_ok = false unless system("ruby -r sirena -e 'Sirena.render(\"graph TD\\nA-->B\")' 2>/dev/null")
      end
    end
    unless sirena_ok
      raise "Sirena subprocess startup benchmark failed -- a fresh `ruby -r sirena` " \
            "process could not render; this is not the external mmdc tool, so fix " \
            "the gem load rather than trusting any number from this run"
    end

    # Benchmark mermaid-cli startup
    mermaid_startup = nil
    if mermaid_cli_available?
      input_file = File.join(BENCHMARK_DIR, 'startup.mmd')
      output_file = File.join(BENCHMARK_DIR, 'startup.svg')
      File.write(input_file, "graph TD\nA-->B")

      mermaid_ok = true
      mermaid_startup = Benchmark.realtime do
        10.times do
          mermaid_ok = false unless system("mmdc -i '#{input_file}' -o '#{output_file}' 2>/dev/null")
        end
      end
      # See benchmark_single_renders: don't publish a failed mmdc invocation's
      # near-instant exit as a real startup time.
      mermaid_startup = nil unless mermaid_ok
    end

    {
      sirena: sirena_startup / 10,
      mermaid: mermaid_startup ? mermaid_startup / 10 : nil
    }
  end

  def benchmark_sirena_only
    {
      single: SAMPLE_DIAGRAMS.map do |type, source|
        time = Benchmark.realtime do
          10.times { Sirena.render(source) }
        end
        [type, { sirena_time: time / 10, mermaid_time: nil }]
      end.to_h
    }
  end

  def generate_report(results)
    <<~ADOC
= Sirena Performance Benchmark Report
:toc:
:toclevels: 2

== Overview

This document presents comprehensive performance benchmarks comparing Sirena
(Ruby-native Mermaid renderer) with the official Mermaid.js CLI (mmdc).

== System Information

*Benchmark Date:* #{results[:system_info][:timestamp]}

*System Configuration:*

* Ruby Version: #{results[:system_info][:ruby_version]}
* Platform: #{results[:system_info][:platform]}
* Sirena Version: #{results[:system_info][:sirena_version]}
* Mermaid CLI Version: #{results[:system_info][:mermaid_cli_version]}
* CPU: #{results[:system_info][:cpu_info]}

== Benchmark Methodology

All benchmarks were performed:

* Single-diagram and startup timings: 10 iterations per test (averaged)
* Batch rendering: one timed pass over 50 diagrams (not averaged across repeats)
* Using identical input diagrams
* On the same system
* With default settings for both tools
* Cold start for startup time tests

== Single Diagram Rendering

Performance for rendering individual diagrams:

[cols="2,2,2,2"]
|===
|Diagram Type |Sirena |Mermaid.js |Speedup

#{results[:single_diagram].map do |type, data|
  speedup = data[:mermaid_time] ? speedup_label(data[:mermaid_time] / data[:sirena_time]) : 'N/A'
  "
|#{type}
|#{format_time(data[:sirena_time])}
|#{data[:mermaid_time] ? format_time(data[:mermaid_time]) : 'N/A'}
|#{speedup}"
end.join("\n")}
|===

*Average speedup:* #{calculate_average_speedup(results[:single_diagram])}

== Batch Rendering Performance

#{if results[:batch_rendering] && !results[:batch_rendering].empty?
  batch = results[:batch_rendering]
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
|#{(batch[:diagram_count] / batch[:sirena_total]).round(1)} diagrams/sec
|#{batch[:mermaid_total] ? "#{(batch[:diagram_count] / batch[:mermaid_total]).round(1)} diagrams/sec" : 'N/A'}
|===

#{if batch[:mermaid_total]
  "*Batch speedup:* #{speedup_label(batch[:mermaid_total] / batch[:sirena_total])}"
else
  "*Batch speedup:* not measured (mermaid-cli failed during this run)"
end}

  BATCH
else
  "*Batch benchmarking requires mermaid-cli installation*"
end}

== Startup Time

Cold start performance (time to render first diagram):

[cols="2,2"]
|===
|Tool |Average Startup Time

|Sirena
|#{format_time(results[:startup_time][:sirena])}

|Mermaid.js
|#{results[:startup_time][:mermaid] ? format_time(results[:startup_time][:mermaid]) : 'N/A'}
|===

#{if results[:startup_time][:mermaid]
  speedup = results[:startup_time][:mermaid] / results[:startup_time][:sirena]
  "*Startup speedup:* #{speedup_label(speedup)}"
end}

== Memory Usage

#{if results[:memory_usage] && !results[:memory_usage].empty?
  mem = results[:memory_usage]
  <<~MEMORY
Note: #{mem[:note]}

  MEMORY
end}

== Analysis

=== Key Findings

*Measured Results:*

#{if results[:single_diagram]
  avg_speedup = calculate_average_speedup(results[:single_diagram])
  <<~FINDINGS
. *Rendering Speed:* #{avg_speedup} on average for single diagrams
#{if results[:batch_rendering] && results[:batch_rendering][:sirena_total] && results[:batch_rendering][:mermaid_total]
  batch_speedup = results[:batch_rendering][:mermaid_total] / results[:batch_rendering][:sirena_total]
  ". *Batch Processing:* #{speedup_label(batch_speedup)} for rendering #{results[:batch_rendering][:diagram_count]} diagrams"
end}
#{if results[:startup_time][:mermaid]
  startup_speedup = results[:startup_time][:mermaid] / results[:startup_time][:sirena]
  ". *Startup Time (cold start):* #{speedup_label(startup_speedup)}"
end}
. *Dependencies:* No Node.js, Puppeteer, or Chrome required

  FINDINGS
end}

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

* **#{calculate_average_speedup(results[:single_diagram])}** rendering, averaged over the sample diagrams above
#{if results[:startup_time][:mermaid]
  startup_speedup = results[:startup_time][:mermaid] / results[:startup_time][:sirena]
  explanation = if startup_speedup >= 1
    "(Sirena pays Ruby interpreter + gem load per process, but still starts faster here)"
  else
    "(Sirena pays Ruby interpreter + gem load per process; mmdc's Node process starts faster here)"
  end
  "* **Cold start: #{speedup_label(startup_speedup)}** than launching mmdc #{explanation}"
end}
* **Memory usage:** not measured in this run
* **Native Ruby integration** (no Node.js required at render time)

These are single-machine measurements from one run, not a general claim; reproduce
with the commands above before citing a number elsewhere.

---

_Benchmark generated by Sirena Performance Suite_
    ADOC
  end

  def calculate_average_speedup(single_results)
    speedups = single_results.values.map do |data|
      next unless data[:mermaid_time]
      data[:mermaid_time] / data[:sirena_time]
    end.compact

    return 'N/A' if speedups.empty?

    speedup_label(speedups.sum / speedups.length)
  end

  def format_time(seconds)
    return 'N/A' unless seconds

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