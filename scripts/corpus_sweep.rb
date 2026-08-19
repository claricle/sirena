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
require 'strscan'
require 'yaml'

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
    if scanner.scan('<!--')
      break unless scanner.skip_until(/-->/)
    elsif scanner.scan('<![CDATA[')
      break unless scanner.skip_until(/\]\]>/)
    elsif scanner.scan('<?')
      # A processing instruction owns its text too. Without this branch a
      # `<!--` inside one opened a comment that ran past the PI's end.
      break unless scanner.skip_until(/\?>/)
    elsif (ref = scanner.scan(/&([^;&<\s]+);/))
      name = ref[1..-2]
      return true unless name.start_with?('#') || PREDEFINED_ENTITIES.include?(name)
    else
      # Not a construct we track: step past this character, then jump to the
      # next one that could start one.
      scanner.getch
      scanner.skip(/[^&<]*/)
    end
  end

  false
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

# Which cases are actually mermaid. A third of the corpus is extraction
# damage or was rejected by mmdc itself, so reporting against every file
# understates compatibility and hides what the number means. Absent verdicts
# means every case counts, which is the old behaviour.
VERDICTS = %w[valid invalid artifact unknown].freeze

def verdicts
  path = File.join(CORPUS_ROOT, 'corpus-verdicts.yml')
  return {} unless File.exist?(path)

  rows = YAML.load_file(path)
  unless rows.is_a?(Array) && rows.all?(Hash)
    warn '  WARNING: corpus-verdicts.yml is not a list of rows; ignoring it.'
    return {}
  end

  # A typo'd verdict used to be accepted as truthy and then quietly dropped
  # from every bucket, so a two-case file holding `valid` and `vlaid` reported
  # "against valid cases only: 1/1 = 100.0%".
  bad = rows.reject { |row| VERDICTS.include?(row['verdict']) }
  unless bad.empty?
    warn "  WARNING: #{bad.size} row(s) carry an unknown verdict " \
         "(#{bad.map { |r| r['verdict'].inspect }.uniq.first(3).join(', ')}); " \
         'ignoring the file rather than reporting over a subset.'
    return {}
  end

  rows.to_h { |row| [row['case'], row['verdict']] }
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
  report_by_verdict(sweep_results)
  return unless list_failing

  # Corpus-relative, not absolute: the base/head comparison this output exists
  # for runs in two different worktrees, and absolute paths made every
  # unchanged failure look like a difference.
  sweep_results.sort.each do |_type, results|
    results.reject { |_, status| status == :pass }
      .each { |path, status| puts "#{status}: #{path.sub("#{CORPUS_ROOT}/", '')}" }
  end
end

# The headline number. Reported alongside the raw total rather than instead
# of it, so the denominator change is visible rather than a silent jump.
def report_by_verdict(sweep_results)
  known = verdicts
  return if known.empty?

  tally = Hash.new { |h, k| h[k] = [0, 0] }
  unmatched = 0
  sweep_results.each do |type, results|
    results.each do |path, status|
      verdict = known[File.join(type, File.basename(path))]
      unless verdict
        unmatched += 1
        next
      end

      tally[verdict][0] += 1 if status == :pass
      tally[verdict][1] += 1
    end
  end
  # Warn before the early return: if NOTHING matched, the tally is empty and a
  # silent return would look like "no verdicts file" rather than "the verdicts
  # file does not cover what was swept".
  if unmatched.positive?
    warn "  WARNING: #{unmatched} swept case(s) have no verdict. Re-run " \
         'scripts/corpus_verdicts.rb --write.'
  end

  return if tally.empty?

  puts "\nBY VERDICT (see scripts/corpus_verdicts.rb)"
  tally.sort.each do |verdict, (passed, total)|
    puts format('  %-9s %5d/%-5d = %5.1f%%', verdict, passed, total,
                100.0 * passed / total)
  end

  # `tally` has a default block, so reading tally['valid'] would materialise
  # [0, 0] and print 0/0 = NaN%. Ask before reading.
  return unless tally.key?('valid')

  valid = tally['valid']
  puts format('  --> against valid cases only: %d/%d = %.1f%%',
              valid[0], valid[1], 100.0 * valid[0] / valid[1])
end

list_failing = !ARGV.delete('--failing').nil?
report(sweep(corpus_types(ARGV)), list_failing: list_failing)
