# frozen_string_literal: true

# Classifies every spec/mermaid case as valid, invalid, artifact or unknown,
# so the corpus pass rate stops being measured against files mermaid itself
# cannot parse.
#
# Usage: ruby scripts/corpus_verdicts.rb [--write] [type ...]
#   --write  emit spec/mermaid/corpus-verdicts.yml
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
require 'yaml'

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
INDENTED_FRONTMATTER = /\A---\s*\n(?:.*\n)*?[ \t]+---\s*$/

def artifact_reason(source)
  return 'literal \\n escape' if source.match?(LITERAL_NEWLINE)
  return 'uninterpolated ${} template' if source.match?(TEMPLATE_PLACEHOLDER)
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

types = ARGV.reject { |a| a.start_with?('--') }
write = ARGV.include?('--write')

# Checked before doing any work: a filtered --write would replace the whole
# committed file with a fraction of it.
if write && !types.empty?
  abort '--write needs the whole corpus; a type filter would truncate the file.'
end

entries = cases(types)
by_digest = index_by_digest(entries)

rows = entries.map do |entry|
  verdict, evidence = classify(entry, by_digest[entry[:digest]])
  {
    'case' => entry[:path].sub("#{CORPUS_ROOT}/", ''),
    'verdict' => verdict,
    'evidence' => evidence
  }
end

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
