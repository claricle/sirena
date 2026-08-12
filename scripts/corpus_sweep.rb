# frozen_string_literal: true

# Renders every spec/mermaid corpus case through Sirena::Engine and
# prints per-type pass rates. Interim measurement tool; the scoreboard
# spec in TODO.foundation/02 replaces it.
#
# Usage: ruby scripts/corpus_sweep.rb [--failing] [type ...]
#   --failing  also list each non-passing case path with its status

require 'bundler/setup'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'sirena'
require 'timeout'

CASE_TIMEOUT = 10
CORPUS_ROOT = File.expand_path('../spec/mermaid', __dir__)

# Interim pass predicate: structurally SVG-shaped output. The item-02
# scoreboard spec replaces this with oracle-backed classification;
# item-04 conformance validates for real. Deliberately stricter than
# "contains <svg>" so garbage prefixes can't count as passes.
def svg_shaped?(output)
  output.is_a?(String) && output.match?(/\A\s*(?:<\?xml[^>]*>\s*)?<svg[\s>]/) &&
    output.rstrip.end_with?('</svg>')
end

def render_result(source)
  svg = Timeout.timeout(CASE_TIMEOUT) { Sirena::Engine.new.render(source) }
  svg_shaped?(svg) ? :pass : :fail
rescue Timeout::Error
  :timeout
rescue StandardError
  :fail
end

def corpus_types(requested)
  available = Dir.children(CORPUS_ROOT).select do |d|
    File.directory?(File.join(CORPUS_ROOT, d)) && !Dir.glob(File.join(CORPUS_ROOT, d, '*.mmd')).empty?
  end
  return available.sort if requested.empty?

  unknown = requested - available
  abort "Unknown corpus type(s): #{unknown.join(', ')}\nAvailable: #{available.sort.join(', ')}" unless unknown.empty?

  requested
end

def sweep(types)
  types.to_h do |type|
    results = Dir.glob(File.join(CORPUS_ROOT, type, '*.mmd'))
      .to_h { |path| [path, render_result(File.read(path))] }
    [type, results]
  end
end

def report(sweep_results, list_failing:)
  puts 'TYPE              PASS   FAIL  TIMEOUT    RATE'
  sweep_results.sort.each do |type, results|
    tally = results.values.tally
    passed = tally.fetch(:pass, 0)
    puts format('%-15s %6d %6d %8d %6.1f%%',
                type, passed, tally.fetch(:fail, 0), tally.fetch(:timeout, 0),
                100.0 * passed / results.size)
  end
  all = sweep_results.values.flat_map(&:values)
  total_passed = all.count(:pass)
  puts format('TOTAL: %d/%d = %.1f%%', total_passed, all.size, 100.0 * total_passed / all.size)
  return unless list_failing

  sweep_results.sort.each do |_type, results|
    results.reject { |_, status| status == :pass }
      .each { |path, status| puts "#{status}: #{path}" }
  end
end

list_failing = !ARGV.delete('--failing').nil?
report(sweep(corpus_types(ARGV)), list_failing: list_failing)
