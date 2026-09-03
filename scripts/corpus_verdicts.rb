# frozen_string_literal: true

# Classifies every spec/mermaid case as valid, invalid, artifact or unknown,
# so the corpus pass rate stops being measured against files mermaid itself
# cannot parse.
#
# Usage: ruby scripts/corpus_verdicts.rb [--write] [--verify] [type ...]
#   --write   emit spec/mermaid/corpus-verdicts.yml
#   --verify  re-check every `invalid` verdict against the LOCAL mmdc
#
# The COMMITTED corpus-verdicts.yml is generated WITHOUT --verify, so anyone
# with Ruby can regenerate it byte-for-byte and review the diff. --verify needs
# mmdc installed, which would make the committed artifact unreproducible for
# most people.
#
# One case is known to differ between the two:
# er_diagram/037_parser_should_handle_complex_diagram_with_special_entity_names_36
# carries an .error from an older mermaid that rejected a numeric entity name,
# and mmdc 11.12.0 renders it. Running --verify promotes it, moving the valid
# rate 42.3% -> 42.4%. Recorded here rather than baked in, because the sidecars
# are a foreign machine's and we should not silently prefer ours.
#
# --verify exists because the sidecars are not reproducible here: they were
# generated on another machine by an unpinned toolchain (see PROVENANCE
# below). A case rejected by that mermaid may render in ours. Re-running the
# local mmdc over the `invalid` bucket — a few dozen cases, about a second
# each — turns the weakest evidence in the file into something this machine
# can reproduce.
#
# Evidence, in the order it is trusted:
#
# PROVENANCE, and it matters: these sidecars were generated on another
# machine — all 330 .error files embed /Users/mulgogi/.asdf paths — by an
# UNPINNED toolchain. TODO.foundation/02 records that "mmdc 11.12.0" pins only
# the CLI wrapper, which floats mermaid ^11.0.2. So a sidecar is evidence that
# some real mermaid accepted or rejected the case, not a reproducible verdict.
#
#   1. An .error sidecar means mmdc REJECTED the case — but only if the
#      source it was generated from is artifact-free. Most .error files in this
#      corpus were produced against a source containing a literal backslash-n,
#      so they report the backslash and say nothing about the case underneath.
#      Trusting those would bin hundreds of real diagrams as invalid.
#   2. An .svg sidecar, or a reference under spec/fixtures_mermaid/, means mmdc
#      rendered it. The case is valid.
#   3. A byte-identical case in another type directory inherits its evidence.
#      The corpus holds several extraction generations of the same files.
#   4. Structural damage in the source itself. Detected by shape, never by
#      whether Sirena can parse it — the point is to judge the input, not us.

require 'digest'
require 'open3'
require 'yaml'
require_relative 'mmdc_oracle'

CORPUS_ROOT = File.expand_path('../spec/mermaid', __dir__)
REFERENCE_ROOT = File.expand_path('../spec/fixtures_mermaid', __dir__)

# A JS string escape that survived extraction: the file holds a backslash and
# an "n" where the source had a newline. Mermaid reports it as a syntax error.
LITERAL_NEWLINE = /\\n/

# An uninterpolated JS template literal. The original value is gone.
TEMPLATE_PLACEHOLDER = /\$\{[^}]*\}/

# Extracted from a cypress .html fixture without decoding: the file holds
# `--&gt;` where the source had `-->`. Not mermaid.
# Only the bracket entities. &amp;, &nbsp;, &quot; and numeric references are
# all legal inside a mermaid label — block/004 uses &nbsp; deliberately and
# mmdc renders it. Flagging those libelled a valid diagram.
HTML_ENTITY = /&(?:lt|gt);/

# Structural truncation: the extractor cut the source mid-construct.
TRUNCATIONS = [
  /\[\s*\z/,          # class C1[
  /:\s*\z/            # CAR ||--o{ DRIVER :
].freeze

# The extractor indented frontmatter bodies, so the closing `---` no longer
# sits at column 0 and mermaid never closes the block: "Diagrams beginning
# with --- are not valid". 44 cases have an indented closer and every one is
# rejected; the single case with a column-0 closer renders fine. That is
# extraction damage, not a diagram mermaid refuses.
INDENTED_FRONTMATTER = /\A---[ \t]*\n(?:.*\n)*?[ \t]+---[ \t]*(?:\n|\z)/

# A placeholder that sits outside every quoted run. Quoted content is label
# text, and mermaid renders it verbatim.
def unquoted_placeholder?(source)
  source.gsub(/"[^"]*"/, '').gsub(/'[^']*'/, '').match?(TEMPLATE_PLACEHOLDER)
end

# An .error sidecar echoes the input it judged. If that echo does not appear in
# the current source, the sidecar was generated against a different (usually
# damaged) version and is not a verdict on what is here now.
def stale_rejection?(base, source)
  path = "#{base}.error"
  return false unless File.exist?(path)

  # mermaid echoes the offending input on the line after "Parse error on
  # line N:", prefixed with "..." when it truncates the left side. Anything
  # else in the file is the message, a caret, or a Node stack trace.
  lines = File.read(path).lines
  marker = lines.index { |l| l.match?(/Parse error on line \d+:/) }
  return false unless marker

  echo = lines[marker + 1].to_s.strip.delete_prefix('...').strip
  return false if echo.length < 12

  # Whitespace differs between the echo and the source, so compare on the
  # non-space characters.
  squash = ->(s) { s.gsub(/\s+/, '') }

  !squash.call(source).include?(squash.call(echo[0, 40]))
end

# spec/mermaid/error/ holds diagrams that are SUPPOSED to fail — mermaid has an
# `error` diagram type and renders one deliberately. An mmdc rejection there is
# the point of the case, not a judgement that the case is invalid.
def intentional_error_type?(entry)
  entry[:type] == 'error'
end

def artifact_reason(source)
  return 'literal \\n escape' if source.match?(LITERAL_NEWLINE)
  # Only outside a quoted string. A quoted `${keyword}` is a label mermaid
  # renders happily — one class note was binned as damage on exactly that.
  return 'uninterpolated ${} template' if unquoted_placeholder?(source)
  return 'html-entity escaped source' if source.match?(HTML_ENTITY)

  return 'indented frontmatter closer' if source.match?(INDENTED_FRONTMATTER)

  stripped = source.rstrip
  return 'truncated source' if TRUNCATIONS.any? { |pattern| stripped.match?(pattern) }

  nil
end

# Mermaid renders a syntax error AS an SVG — the bomb graphic, tagged
# aria-roledescription="error". So the presence of a .svg is not evidence the
# case is valid; 50 references are error graphics, including two info cases
# whose upstream test names say they should throw.
def error_graphic?(path)
  File.exist?(path) && File.read(path).include?('aria-roledescription="error"')
end

# Validated the same way scripts/corpus_sweep.rb validates its arguments.
# Without it a typo silently reports "0 cases" and exits successfully, which
# reads as a measurement rather than a mistake.
def corpus_types(requested)
  available = Dir.children(CORPUS_ROOT).select do |dir|
    File.directory?(File.join(CORPUS_ROOT, dir))
  end
  return available.sort if requested.empty?

  unknown = requested - available
  unless unknown.empty?
    abort "Unknown corpus type(s): #{unknown.join(', ')}\n" \
          "Available: #{available.sort.join(', ')}"
  end

  requested
end

# Each case is read from disk exactly once. The source and its digest are
# carried through rather than recomputed — three separate reads over ~2000
# files is avoidable work.
def cases(types)
  corpus_types(types).flat_map do |type|
    Dir.glob(File.join(CORPUS_ROOT, type, '*.mmd')).map do |path|
      source = File.read(path)
      {
        type: type,
        path: path,
        base: path.delete_suffix('.mmd'),
        source: source,
        digest: Digest::SHA256.hexdigest(source)
      }
    end
  end
end

# Rendering evidence, but only a REAL render. An SVG carrying mermaid's error
# graphic means the opposite of what its existence suggests.
def rendered?(entry)
  name = File.basename(entry[:base])
  sidecar = "#{entry[:base]}.svg"
  reference = File.join(REFERENCE_ROOT, entry[:type], "#{name}.svg")

  [sidecar, reference].any? { |path| File.exist?(path) && !error_graphic?(path) }
end

# mermaid rejected it, by either route: an .error sidecar, or an SVG that is
# actually the error graphic.
def rejected?(entry)
  name = File.basename(entry[:base])
  return false if intentional_error_type?(entry)
  return false if stale_rejection?(entry[:base], entry[:source])
  return true if File.exist?("#{entry[:base]}.error")

  [
    "#{entry[:base]}.svg",
    File.join(REFERENCE_ROOT, entry[:type], "#{name}.svg")
  ].any? { |path| error_graphic?(path) }
end

# Cases repeat across type directories; a twin carries its evidence over.
def index_by_digest(entries)
  entries.group_by { |entry| entry[:digest] }
end

def twins_of(entry, group)
  group.reject { |other| other[:path] == entry[:path] }
end

# Precedence, and the order is the whole design:
#
#   1. A real render, on this case or a byte-identical twin. mmdc produced
#      output, so mermaid accepts it whatever the source looks like.
#   2. Structural damage. This outranks rejection evidence, because 44 of the
#      rejections ARE the damage — an indented frontmatter closer makes mermaid
#      refuse a diagram it otherwise supports.
#   3. Rejection, on this case or a twin.
#   4. Nothing either way.
#
# Twin evidence is checked in both directions at each step. Checking it only
# for renders gave byte-identical files opposite verdicts depending on which
# directory they sat in.
def classify(entry, group)
  twins = twins_of(entry, group)
  artifact = artifact_reason(entry[:source])

  if rendered?(entry)
    return ['valid', "mmdc rendered it (source also looks damaged: #{artifact})"] if artifact

    return ['valid', 'mmdc rendered it']
  end

  twin = twins.find { |other| rendered?(other) }
  return ['valid', "twin rendered: #{File.basename(twin[:base])}"] if twin

  return ['artifact', artifact] if artifact
  return ['invalid', 'mmdc rejected it'] if rejected?(entry)

  twin = twins.find { |other| rejected?(other) }
  return ['invalid', "twin rejected: #{File.basename(twin[:base])}"] if twin

  ['unknown', 'no evidence']
end

# Re-checks one case against the installed mmdc using the shared oracle.
def local_mmdc_verdict(path)
  MmdcOracle.verdict(path) do |input, output|
    stdout, stderr, status = Open3.capture3('mmdc', '-i', input, '-o', output)
    [status, [stdout, stderr].reject(&:empty?).join]
  end.verdict
end

# Promotes an `invalid` row that the local mmdc actually renders. Leaves every
# other verdict alone: rendering evidence already outranks everything, and
# artifact rows are about the source rather than about mermaid's opinion.
def verify_invalid!(rows, entries)
  by_case = entries.to_h { |e| [e[:path].sub("#{CORPUS_ROOT}/", ''), e] }
  checked = 0
  promoted = 0
  errors = 0

  rows.each do |row|
    next unless row['verdict'] == 'invalid'

    entry = by_case[row['case']] or next
    checked += 1
    case local_mmdc_verdict(entry[:path])
    when :accepts
      row['verdict'] = 'valid'
      row['evidence'] = 'local mmdc renders it (sidecar rejection was stale)'
      promoted += 1
    when :rejects
      row['evidence'] = 'local mmdc rejects it too'
    when :error
      row['evidence'] = 'local mmdc could not be run'
      errors += 1
    end
  end

  warn "  checked #{checked} invalid case(s) against local mmdc; " \
       "#{promoted} promoted to valid"
  errors
end

return unless File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)

types = ARGV.reject { |a| a.start_with?('--') }
write = ARGV.include?('--write')
verify = ARGV.include?('--verify')

# Checked before doing any work: a filtered --write would replace the whole
# committed file with a fraction of it.
if write && !types.empty?
  abort '--write needs the whole corpus; a type filter would truncate the file.'
end

entries = cases(types)

# The twin index always spans the WHOLE corpus, even on a filtered run.
# Building it from the selection alone made `class_diagram` on its own report
# 68/11/90/115 against its committed 162/6/90/26 — 129 rows differing purely
# because the twins were out of scope.
by_digest = index_by_digest(types.empty? ? entries : cases([]))

rows = entries.map do |entry|
  verdict, evidence = classify(entry, by_digest[entry[:digest]])
  {
    'case' => entry[:path].sub("#{CORPUS_ROOT}/", ''),
    'verdict' => verdict,
    'evidence' => evidence
  }
end

verification_errors = verify_invalid!(rows, entries) if verify
abort "mmdc verification failed for #{verification_errors} case(s)" if verification_errors&.positive?

tally = rows.group_by { |r| r['verdict'] }.transform_values(&:size)
puts 'TYPE       VALID    INVALID  ARTIFACT  UNKNOWN'
rows.group_by { |r| r['case'].split('/').first }.sort.each do |type, list|
  t = list.group_by { |r| r['verdict'] }.transform_values(&:size)
  puts format('%-10s %-8d %-8d %-9d %d', type, t.fetch('valid', 0),
              t.fetch('invalid', 0), t.fetch('artifact', 0), t.fetch('unknown', 0))
end
puts format("\nTOTAL %d cases: valid=%d invalid=%d artifact=%d unknown=%d",
            rows.size, tally.fetch('valid', 0), tally.fetch('invalid', 0),
            tally.fetch('artifact', 0), tally.fetch('unknown', 0))

if write
  out = File.join(CORPUS_ROOT, 'corpus-verdicts.yml')
  File.write(out, rows.to_yaml)
  puts "wrote #{out}"
end
