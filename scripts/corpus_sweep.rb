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
require 'rexml/document'

CASE_TIMEOUT = 10
CORPUS_ROOT = File.expand_path('../spec/mermaid', __dir__)

# Interim pass predicate: SVG-shaped AND well-formed XML. The item-02
# scoreboard spec replaces this with oracle-backed classification;
# item-04 conformance validates for real.
#
# Shape alone was not enough. A case emitting an unescaped <br> inside <text>
# still opens with <svg and closes with </svg>, so it scored as a pass while
# being unparseable — which overstated the totals rather than understating
# them. Parsing is the cheapest way to refuse that.
def well_formed_svg?(output)
  return false unless output.is_a?(String)
  return false unless output.match?(/\A\s*(?:<\?xml[^>]*>\s*)?<svg[\s>]/)
  return false unless output.rstrip.end_with?('</svg>')
  return false if undeclared_entity?(output)

  REXML::Document.new(output)
  true
rescue REXML::ParseException
  false
end

# XML predefines exactly these five. Anything else needs a DTD, and the SVG
# output carries none.
PREDEFINED_ENTITIES = %w[amp lt gt quot apos].freeze

# REXML is lenient about undeclared entity references, so `&nbsp;` parsed
# clean and still counted as a pass. xmllint refuses the same string with
# "Entity 'nbsp' not defined". Numeric references are always legal.
#
# Comments and CDATA are cut first because nothing inside them is an entity
# reference. Without that, a label rendering `<!-- &nbsp; -->` produced valid
# SVG that this refused.
def undeclared_entity?(output)
  scannable = output.gsub(/<!--.*?-->/m, '').gsub(/<!\[CDATA\[.*?\]\]>/m, '')
  scannable.scan(/&([^;&\s]+);/).flatten.any? do |ref|
    !ref.start_with?('#') && !PREDEFINED_ENTITIES.include?(ref)
  end
end

def render_result(source)
  svg = Timeout.timeout(CASE_TIMEOUT) { Sirena::Engine.new.render(source) }
  well_formed_svg?(svg) ? :pass : :fail
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
  # An empty corpus otherwise printed "0/0 = NaN%" and exited 0, which reads
  # as a successful measurement of nothing.
  abort 'No corpus cases found; nothing to measure.' if sweep_results.values.all?(&:empty?)

  puts 'TYPE              PASS   FAIL  TIMEOUT    RATE'
  sweep_results.sort.each do |type, results|
    # Type discovery only keeps directories that hold cases, so an empty one
    # means the files went away mid-run. Report it rather than dividing by
    # zero on the way to saying nothing.
    if results.empty?
      warn "#{type}: no cases at sweep time; skipped"
      next
    end

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

  # Corpus-relative, not absolute: the base/head comparison this output exists
  # for runs in two different worktrees, and absolute paths made every
  # unchanged failure look like a difference.
  sweep_results.sort.each do |_type, results|
    results.reject { |_, status| status == :pass }
      .each { |path, status| puts "#{status}: #{path.sub("#{CORPUS_ROOT}/", '')}" }
  end
end

list_failing = !ARGV.delete('--failing').nil?
report(sweep(corpus_types(ARGV)), list_failing: list_failing)
