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
HTML_ENTITY = /&(?:lt|gt|amp|nbsp|quot|apos|#\d+);/

# Structural truncation: the extractor cut the source mid-construct.
TRUNCATIONS = [
  /\[\s*\z/,          # class C1[
  /\bnamespace\s+\\?\s*\z/,
  /:\s*\z/,           # CAR ||--o{ DRIVER :
  /\bstate\s*\z/
].freeze

def artifact_reason(source)
  return 'literal \\n escape' if source.match?(LITERAL_NEWLINE)
  return 'uninterpolated ${} template' if source.match?(TEMPLATE_PLACEHOLDER)
  return 'html-entity escaped source' if source.match?(HTML_ENTITY)

  stripped = source.rstrip
  return 'truncated source' if TRUNCATIONS.any? { |t| stripped.match?(t) }

  nil
end

def cases(types)
  available = Dir.children(CORPUS_ROOT).select do |d|
    File.directory?(File.join(CORPUS_ROOT, d))
  end
  selected = types.empty? ? available.sort : types
  selected.flat_map do |type|
    Dir.glob(File.join(CORPUS_ROOT, type, '*.mmd')).map do |path|
      { type: type, path: path, base: path.delete_suffix('.mmd') }
    end
  end
end

def reference?(entry)
  name = File.basename(entry[:base])
  File.exist?(File.join(REFERENCE_ROOT, entry[:type], "#{name}.svg"))
end

# Cases repeat across type directories; a twin carries its evidence over.
def index_by_digest(entries)
  entries.group_by { |e| Digest::SHA256.hexdigest(File.read(e[:path])) }
end

def classify(entry, twins)
  source = File.read(entry[:path])
  artifact = artifact_reason(source)
  rendered = File.exist?("#{entry[:base]}.svg") || reference?(entry)
  rejected = File.exist?("#{entry[:base]}.error")

  # Rendering evidence outranks everything: mmdc produced output, so whatever
  # else the source looks like, it is a case mermaid accepts. Without this
  # precedence the buckets are not a partition — 29 cases are both rendered
  # and structurally damaged, because mmdc rendered the corruption rather
  # than rejecting it (flowchart/026 has a node literally named "\nA").
  #
  # Those cases stay `valid` but are flagged, so nobody reads the valid set
  # as clean.
  if rendered
    return ['valid', "mmdc rendered it (source also looks damaged: #{artifact})"] if artifact

    return ['valid', 'mmdc rendered it']
  end

  # The trap. An .error generated from a damaged source is evidence about the
  # damage, not about the diagram.
  return ['artifact', artifact] if artifact
  return ['invalid', 'mmdc rejected it'] if rejected

  twin = twins.find { |t| t[:path] != entry[:path] && (File.exist?("#{t[:base]}.svg") || reference?(t)) }
  return ['valid', "twin rendered: #{File.basename(twin[:base])}"] if twin

  ['unknown', 'no evidence']
end

types = ARGV.reject { |a| a.start_with?('--') }
write = ARGV.include?('--write')

entries = cases(types)
by_digest = index_by_digest(entries)

rows = entries.map do |entry|
  digest = Digest::SHA256.hexdigest(File.read(entry[:path]))
  verdict, evidence = classify(entry, by_digest[digest])
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
