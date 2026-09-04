#!/usr/bin/env ruby
# frozen_string_literal: true

# Reports where sirena and mermaid disagree about a source.
#
# The corpus cannot answer this. It holds the sources mermaid's own test
# suite happens to contain, so a construct nobody wrote a test for is
# invisible to the sweep — sirena can accept input mermaid refuses, or refuse
# input mermaid renders, and every gate stays green.
#
# Usage:
#   ruby scripts/mermaid_diff.rb scripts/probes/flowchart.txt
#   ruby scripts/mermaid_diff.rb --only-gaps scripts/probes/*.txt
#
# Probe files hold one source per record, separated by a line that is exactly
# `%%%%`. A source that needs such a line writes `\%%%%`, and one that needs
# THAT line writes `\\%%%%` — a leading run of backslashes loses one.
# `---` cannot be the separator: it opens a frontmatter block.
#
# Exits nonzero on any disagreement, and on any infrastructure failure.
# Needs a POSIX system and mmdc on PATH.

# The verdicts are only worth as much as the sirena that produced them, so
# the Gemfile decides which one that is rather than whatever is installed.
require 'bundler/setup'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'sirena'
require 'timeout'
require 'tmpdir'
require_relative 'mmdc_oracle'
require_relative 'hardened_mmdc'

# `mmdc --version` boots node, which is slow but not this slow.
VERSION_TIMEOUT = 30

# The oracle these probes were written against. It is the only version mmdc
# will tell us: mmdc floats its mermaid dependency, so a matching CLI can
# still resolve a different renderer underneath. The pin catches the CLI
# moving, which is the part we can see.
EXPECTED_CLI = '11.12.0'

LABELS = { gap: 'GAP', over_acceptance: 'OVER-ACCEPTANCE',
           infrastructure: 'MMDC FAILED' }.freeze

Verdict = Struct.new(:source, :sirena, :mermaid) do
  def agree?
    sirena == mermaid
  end

  def kind
    return :infrastructure if mermaid == :error
    return :agree if agree?

    sirena == :accepts ? :over_acceptance : :gap
  end
end

# Sirena gets the same deadline mmdc has. Only mmdc had one, and a source
# sirena grinds on stalled every verdict after it: `packet-beta` with a
# 2,000,000 column range is accepted by mmdc in 7.2s and was still rendering
# in sirena 60s in. A source sirena cannot finish inside the deadline is a
# rejection as far as this harness is concerned — no diagram comes out
# either way.
#
# SystemStackError is not a StandardError, and parslet recurses once per
# nesting level: 400 nested subgraphs blew the stack and took the run with it.
def sirena_verdict(source)
  Timeout.timeout(HardenedMmdc::CASE_TIMEOUT) { Sirena.render(source) }
  :accepts
rescue StandardError, SystemStackError
  :rejects
end

# @return [Symbol] :accepts, :rejects, or :error when mmdc could not be run
def mermaid_verdict(source)
  result = Dir.mktmpdir do |dir|
    input = File.join(dir, 'probe.mmd')
    File.write(input, source)

    MmdcOracle.verdict(input) { |probe, output| HardenedMmdc.run_mmdc(probe, output) }
  end

  warn "  mmdc: #{result.diagnostic}" if result.verdict == :error
  result.verdict
rescue SystemCallError => e
  # Spawning mmdc can fail long after the version check passed — the process
  # table fills up while Chromium is being started 60 times over. That is one
  # probe we could not measure, not a reason to abandon the run.
  warn "  mmdc: #{e.message}"
  :error
end

# Records are kept byte for byte. Stripping them changed what was compared —
# an indented frontmatter probe became a different source and the
# disagreement it existed to catch vanished.
# The separator is a line that is EXACTLY `%%%%`. Anything else on that line
# is content: mermaid reads any `%%` line as a comment, and mmdc accepts both
# `%%%%comment` and `%%%%` followed by blanks. Each of those split one probe
# into two, and the halves got verdicts the real source never had.
#
# The escape drops ONE backslash from a run of them, so every line is
# writable: `\%%%%` is the separator escaped, `\\%%%%` is a source whose own
# line is `\%%%%`. It used to rewrite `\%%%%` and leave `\\%%%%` doubled, so
# the one source you could not write was `\%%%%` — which mmdc 11.12.0 renders
# and sirena rejects. The probe silently became a source with a bare `%%%%`
# line instead, which both accept.
#
# Matching blanks here would strip the backslash off a `\%%%%   ` that no
# longer needs one.
SEPARATOR = /^%%%%\r?(?:\n|\z)/
ESCAPED_SEPARATOR = /^\\(\\*%%%%)(?=\r?$)/

# Read as bytes and tagged UTF-8 only once the splitting is done. Reading it
# as text put an ArgumentError from String#split between the harness and every
# verdict in the file: one probe that is not valid UTF-8 took the whole sweep
# down before a single case ran. That probe is a gap, not noise — mmdc renders
# `A[\xFF\xFE]` and sirena rejects it — so the bytes are handed to both tools
# exactly as written.
def probes(paths)
  paths.flat_map do |path|
    File.binread(path).split(SEPARATOR)
      .reject { |record| record.strip.empty? }
      .map { |record| record.gsub(ESCAPED_SEPARATOR, '\1').force_encoding(Encoding::UTF_8) }
  end
end

def report(verdicts, only_gaps:)
  shown = verdicts.reject { |v| v.kind == :agree }
  shown = shown.select { |v| v.kind == :gap } if only_gaps

  shown.each do |verdict|
    label = LABELS.fetch(verdict.kind)
    puts format('%-16s %s', label, one_line(verdict.source))
  end

  tally = verdicts.group_by(&:kind).transform_values(&:size)
  puts
  puts format('%d probes: %d agree, %d gaps, %d over-accepted, %d mmdc failures',
              verdicts.size, tally[:agree].to_i, tally[:gap].to_i,
              tally[:over_acceptance].to_i, tally[:infrastructure].to_i)
end

# Leading whitespace is often the whole point of a probe — the indented
# frontmatter case was displayed without the indentation responsible for
# its verdict. Only the trailing newline goes, and a stray \r with it.
#
# Scrubbed for the display and nowhere else: a probe may hold bytes UTF-8
# cannot name, and both tools were asked about the real ones.
def one_line(source)
  folded = source.scrub.sub(/\r?\n\z/, '').gsub(/\r?\n/, ' | ')
  folded.gsub(/[\x00-\x1F\x7F]/) { |control| format('\\x%02X', control.ord) }
end

def check_oracle
  version = mmdc_version
  return if version == EXPECTED_CLI

  abort "  mmdc is #{version.empty? ? 'missing or not answering' : version}, " \
        "expected #{EXPECTED_CLI}. These probes were written against that " \
        'oracle; a different one makes the verdicts meaningless.'
end

# This runs before any of the per-case deadlines apply, so an mmdc that never
# answers used to hang the whole harness here and outlive it afterwards.
def mmdc_version
  HardenedMmdc.capture(['mmdc', '--version'], VERSION_TIMEOUT).strip
rescue StandardError
  ''
end

return unless File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)

only_gaps = !ARGV.delete('--only-gaps').nil?
paths = ARGV
abort 'usage: mermaid_diff.rb [--only-gaps] <probe file>...' if paths.empty?

check_oracle

records = probes(paths)
abort '  no probe records found — check the file and its separators' if records.empty?

verdicts = records.map do |source|
  Verdict.new(source, sirena_verdict(source), mermaid_verdict(source))
end

report(verdicts, only_gaps: only_gaps)
exit(verdicts.all? { |v| v.kind == :agree } ? 0 : 1)
