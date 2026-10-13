# frozen_string_literal: true

# Renders every spec/mermaid corpus case through Sirena::Engine and
# prints per-type pass rates. Interim measurement tool; the scoreboard
# spec in TODO.foundation/02 replaces it.
#
# Usage: ruby scripts/corpus_sweep.rb [--failing] [type ...]
#   --failing  also list each non-passing case path with its status

require "bundler/setup"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "sirena"
require "timeout"
require "rexml/document"
require "strscan"
require "yaml"

CASE_TIMEOUT = 10
CORPUS_ROOT = File.expand_path("../spec/mermaid", __dir__)

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
  return false unless output.rstrip.end_with?("</svg>")
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
# "Entity 'nbsp' not defined". Numeric references pass this scan and are
# left to REXML, which rejects the invalid codepoints among them; nothing
# inside a comment or a CDATA section is a reference at all.
#
# One left-to-right pass, because whichever construct opens first owns the
# text that follows. Comments, CDATA and processing instructions each own
# their contents; entity names carry no length limit in XML, so the scan
# imposes none. Stripping comments and CDATA with two independent
# regexes looked equivalent and was not: in `<![CDATA[<!--]]>&nbsp;<!-- -->`
# the comment pattern started inside the CDATA and swallowed the real
# entity after it.
def undeclared_entity?(output)
  scanner = StringScanner.new(output)
  until scanner.eos?
    return true if scan_entity(scanner) == :undeclared
    break if scanner.eos?
  end
  false
end

def scan_entity(scanner)
  closer = ignored_xml_section(scanner)
  return scanner.skip_until(closer) || scanner.terminate if closer

  reference = scanner.scan(/&([^;&<\s]+);/)
  return :undeclared if reference && unknown_entity?(reference[1..-2])
  return if reference

  scanner.getch
  scanner.skip(/[^&<]*/)
end

def ignored_xml_section(scanner)
  return /-->/ if scanner.scan("<!--")
  return /\]\]>/ if scanner.scan("<![CDATA[")
  return /\?>/ if scanner.scan("<?")

  nil
end

def unknown_entity?(name)
  !name.start_with?("#") && !PREDEFINED_ENTITIES.include?(name)
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
  available = available_corpus_types
  return available.sort if requested.empty?

  unknown = requested - available
  abort unknown_types_message(unknown, available) unless unknown.empty?

  requested
end

def available_corpus_types
  Dir.children(CORPUS_ROOT).select do |directory|
    path = File.join(CORPUS_ROOT, directory)
    File.directory?(path) && !Dir.glob(File.join(path, "*.mmd")).empty?
  end
end

def unknown_types_message(unknown, available)
  "Unknown corpus type(s): #{unknown.join(', ')}\n" \
    "Available: #{available.sort.join(', ')}"
end

def sweep(types)
  types.to_h do |type|
    results = Dir.glob(File.join(CORPUS_ROOT, type, "*.mmd"))
      .to_h { |path| [path, render_result(File.read(path))] }
    [type, results]
  end
end

# Which cases are actually mermaid. A third of the corpus is extraction
# damage or was rejected by mmdc itself, so reporting against every file
# understates compatibility and hides what the number means. Absent verdicts
# means every case counts, which is the old behaviour.
VERDICTS = %w[valid invalid artifact unknown].freeze

def verdicts
  path = File.join(CORPUS_ROOT, "corpus-verdicts.yml")
  return {} unless File.exist?(path)

  rows = YAML.load_file(path)
  return {} unless valid_verdict_rows?(rows)

  rows.to_h { |row| [row["case"], row["verdict"]] }
end

def valid_verdict_rows?(rows)
  unless rows.is_a?(Array) && rows.all?(Hash)
    warn "  WARNING: corpus-verdicts.yml is not a list of rows; ignoring it."
    return false
  end
  bad = rows.reject { |row| VERDICTS.include?(row["verdict"]) }
  return true if bad.empty?

  warn_bad_verdicts(bad)
  false
end

def warn_bad_verdicts(bad)
  bad_verdicts = bad.map { |row| row["verdict"].inspect }.uniq.first(3)
  warn "  WARNING: #{bad.size} row(s) carry an unknown verdict " \
       "(#{bad_verdicts.join(', ')}); " \
       "ignoring the file rather than reporting over a subset."
end

def report(sweep_results, list_failing:)
  abort "No corpus cases found; nothing to measure." if
    sweep_results.values.all?(&:empty?)

  puts "TYPE              PASS   FAIL  TIMEOUT    RATE"
  sweep_results.sort.each { |type, results| report_type(type, results) }
  report_total(sweep_results)
  report_by_verdict(sweep_results)
  report_failures(sweep_results) if list_failing
end

def report_type(type, results)
  if results.empty?
    warn "#{type}: no cases at sweep time; skipped"
    return
  end
  puts type_summary(type, results)
end

def type_summary(type, results)
  tally = results.values.tally
  passed = tally.fetch(:pass, 0)
  format(
    "%<type>-15s %<passed>6d %<failed>6d %<timeout>8d %<rate>6.1f%%",
    type: type, passed: passed, failed: tally.fetch(:fail, 0),
    timeout: tally.fetch(:timeout, 0), rate: 100.0 * passed / results.size
  )
end

def report_total(sweep_results)
  all = sweep_results.values.flat_map(&:values)
  passed = all.count(:pass)
  puts format("TOTAL: %<passed>d/%<total>d = %<rate>.1f%%",
              passed: passed, total: all.size, rate: 100.0 * passed / all.size)
end

# Relative paths remain comparable across two different worktrees.
def report_failures(sweep_results)
  sweep_results.sort.each do |_type, results|
    results.reject { |_, status| status == :pass }.each do |path, status|
      puts "#{status}: #{path.sub("#{CORPUS_ROOT}/", '')}"
    end
  end
end

# The headline number. Reported alongside the raw total rather than instead
# of it, so the denominator change is visible rather than a silent jump.
def report_by_verdict(sweep_results)
  known = verdicts
  return if known.empty?

  tally, unmatched = tally_verdicts(sweep_results, known)
  warn_unmatched_verdicts(unmatched) if unmatched.positive?
  return if tally.empty?

  puts "\nBY VERDICT (see scripts/corpus_verdicts.rb)"
  tally.sort.each { |verdict, counts| report_verdict(verdict, counts) }
  report_valid_cases(tally["valid"]) if tally.key?("valid")
end

def tally_verdicts(sweep_results, known)
  tally = Hash.new { |hash, verdict| hash[verdict] = [0, 0] }
  unmatched = 0
  sweep_results.each do |type, results|
    results.each do |path, status|
      verdict = known[File.join(type, File.basename(path))]
      verdict ? count_verdict(tally[verdict], status) : unmatched += 1
    end
  end
  [tally, unmatched]
end

def count_verdict(counts, status)
  counts[0] += 1 if status == :pass
  counts[1] += 1
end

def warn_unmatched_verdicts(unmatched)
  warn "  WARNING: #{unmatched} swept case(s) have no verdict. Re-run " \
       "scripts/corpus_verdicts.rb --write."
end

def report_verdict(verdict, counts)
  passed, total = counts
  puts format("  %<verdict>-9s %<passed>5d/%<total>-5d = %<rate>5.1f%%",
              verdict: verdict, passed: passed, total: total,
              rate: 100.0 * passed / total)
end

def report_valid_cases(counts)
  passed, total = counts
  puts format(
    "  --> against valid cases only: %<passed>d/%<total>d = %<rate>.1f%%",
    passed: passed, total: total, rate: 100.0 * passed / total,
  )
end

return unless File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)

list_failing = !ARGV.delete("--failing").nil?
report(sweep(corpus_types(ARGV)), list_failing: list_failing)
