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

CASE_TIMEOUT = 30

# `ps` is a separate program and it can wedge. A process table prints in
# milliseconds, so five seconds means it is never coming.
PS_TIMEOUT = 5

# `mmdc --version` boots node, which is slow but not this slow.
VERSION_TIMEOUT = 30

# How long to wait for the pipe once mmdc is gone. Only a process that
# escaped the kill still holds the write end, and it will not let go.
DRAIN_GRACE = 1

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
  Timeout.timeout(CASE_TIMEOUT) { Sirena.render(source) }
  :accepts
rescue StandardError, SystemStackError
  :rejects
end

# @return [Symbol] :accepts, :rejects, or :error when mmdc could not be run
def mermaid_verdict(source)
  result = Dir.mktmpdir do |dir|
    input = File.join(dir, 'probe.mmd')
    File.write(input, source)

    MmdcOracle.verdict(input) { |probe, output| run_mmdc(probe, output) }
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

# Its own process group, so a hung Chromium goes down with it rather than
# outliving the deadline.
#
# The output is drained on a thread while we wait. Reading it afterwards
# deadlocked: a probe emitting 80KB of KaTeX warnings filled the 64KB pipe,
# mmdc blocked writing, and a diagram it renders was reported MMDC FAILED
# on the deadline.
#
# The ensure clause kills the tree as well as closing the pipe, or a SIGINT
# left mmdc and its Chromium children running after the harness exited.
#
# The group goes down on every path, not just the deadline. A child that
# stayed in it used to outlive a normally-exiting mmdc, and one of those
# accumulated per case.
#
# The wait on the drain is bounded because the group kill does not reach a
# child that left the group — Chromium does exactly that. Such a child still
# holds the pipe's write end, so reading to EOF waited on THAT process: one
# escaped Chromium held a 30s case open for 301.7s.
#
# The pipe is opened with a block so both ends close however we leave. They
# used to be closed by hand after the spawn, so a spawn that raised leaked
# the write end — measured at one descriptor per failure, 20 for 20.
def run_mmdc(input, output)
  IO.pipe do |stdout_r, stdout_w|
    pid = Process.spawn('mmdc', '-i', input, '-o', output,
                        out: stdout_w, err: stdout_w, pgroup: true)
    stdout_w.close
    drain = Thread.new { stdout_r.read }

    status = wait_with_deadline(pid)
    kill_group_id(pid)
    [status, drain.join(DRAIN_GRACE) ? drain.value : '']
  ensure
    kill_group(pid) if pid && status.nil?
    drain&.kill
  end
end

def wait_with_deadline(pid)
  deadline = monotonic + CASE_TIMEOUT

  loop do
    finished, status = Process.waitpid2(pid, Process::WNOHANG)
    return status if finished
    return kill_group(pid) if monotonic > deadline

    sleep 0.05
  end
end

# Killing mmdc's process group is not enough: puppeteer starts Chromium in
# a group of its own, and after the group kill it survived under PID 1 for
# seconds. The descendants have to be collected BEFORE the kill, because
# once the parent dies they are reparented and the trail is gone. That also
# bounds what this can clean up: a descendant that escapes a normally
# exiting mmdc is already reparented by the time we hold its status, and no
# sweep from here can tell it from anything else on the machine.
#
# Collecting the descendants means running `ps`, and mmdc can finish while
# that runs. The status it finished with is the verdict we came for, so it
# is handed back rather than thrown away — one that exited 7 in this window
# was reported as MMDC FAILED, for a source mermaid had a real answer to.
#
# ECHILD is the second pass over a case that timed out: the deadline already
# reaped mmdc here, and then `run_mmdc` cleans up again on the way out
# because it has no status. There is nothing left to wait for by then.
def kill_group(pid)
  doomed = descendants_of(pid)
  kill_group_id(pid)
  status = status_unless_killed(pid)
  kill_each(doomed)
  status
rescue Errno::ECHILD
  kill_each(doomed)
  nil
end

# What the program ended with, unless the KILL we just sent is what ended
# it: a program we killed never got to answer, and saying it exited nonzero
# would read as mermaid rejecting the source.
def status_unless_killed(pid)
  _, status = Process.waitpid2(pid)
  status.termsig == Signal.list.fetch('KILL') ? nil : status
end

# Programs are spawned into a process group of their own, so a group's id is
# the program's pid. That still holds once the program has been reaped, which
# is why a group can be cleaned up on the way out.
#
# EPERM here means the same as ESRCH: nothing is left that can be signalled.
# Measured — a live leader with a live child signals fine and the child dies,
# a reaped leader gives ESRCH, and a leader that is still an unreaped zombie
# gives EPERM.
def kill_group_id(pid)
  Process.kill('KILL', -pid)
rescue Errno::ESRCH, Errno::EPERM
  nil
end

def kill_each(pids)
  pids.each do |child|
    Process.kill('KILL', child)
  rescue Errno::ESRCH
    nil
  end
end

# The sweep asks another program for the process table, and that program can
# fail us: a sandbox refuses the exec, a wedged one never answers, a garbled
# one breaks the parse. Any of those used to raise or block right here, and
# the caller never reached its kill. Losing the descendants is survivable;
# losing the group kill is not.
def descendants_of(pid)
  subtree_of(pid)
rescue StandardError
  []
end

# The whole subtree, from one `ps` snapshot.
def subtree_of(pid)
  parents = Hash.new { |hash, key| hash[key] = [] }
  capture(['ps', '-eo', 'pid=,ppid='], PS_TIMEOUT).each_line do |line|
    child, parent = line.split.map { |field| Integer(field, exception: false) }
    parents[parent] << child if child&.positive? && parent&.positive?
  end

  found = []
  queue = [pid]
  until queue.empty?
    current = queue.shift
    parents[current].each do |child|
      next if found.include?(child)

      found << child
      queue << child
    end
  end
  found
end

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

# Runs a program and hands back what it printed. Spawned rather than
# backticked so that one which never answers can be killed: a descendant can
# inherit the capture pipe's write end, so leaving it running keeps `io.read`
# from reaching EOF. Measured with a wedged `ps` — the sweep came back in
# 0.30s and the reader waited 21.29s for EOF.
def capture(command, timeout)
  io = IO.popen(command, err: File::NULL, pgroup: true)
  begin
    Timeout.timeout(timeout) { io.read }
  ensure
    # The whole group, not just the program: a wedged one that had already
    # started a child left that child running. Unconditional, because on the
    # normal path the program is at EOF and already on its way out.
    kill_group_id(io.pid)
    io.close
  end
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
  source.scrub.sub(/\r?\n\z/, '').gsub(/\r?\n/, ' | ')
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
  capture(['mmdc', '--version'], VERSION_TIMEOUT).strip
rescue StandardError
  ''
end

return unless $PROGRAM_NAME == __FILE__

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
