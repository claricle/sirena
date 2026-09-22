# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "sirena/commands/batch"

# Fixtures and runners for BatchCommand specs. `bomb`, `batching` and
# `run_batch` are ordinary domain words, so this is included per example
# group (the convention in this suite -- see spec/fixtures_spec.rb:6 and
# nine others) rather than globally via RSpec.configure, which would put
# six such names on every group in the suite.
#
# BatchCommand prints a per-file progress line and a summary, so an example
# that does not assert on that text still has to swallow it or the suite
# output becomes unreadable. One runner does the silencing, and two views
# read off it: `run_batch` for what was printed, `batch_command` for the
# command itself (`#success?`, the D1 exit-code verdict).
module BatchCommandRunner
  # 4000 nested subgraphs -- past the depth the flowchart parser can carry,
  # so it fails where a well-formed neighbour does not. `parse_tree`
  # (flowchart.rb:58-60) converts that overflow into a ParseError, so this
  # is the ORDINARY failure path; the exhaustion examples raise a real
  # `NoMemoryError` at `File.read` instead.
  #
  # 4000 is well past the boundary rather than close to it: measured to
  # still overflow under a 16MB and a 32MB RUBY_THREAD_VM_STACK_SIZE, where
  # a shallower depth parses cleanly once the stack is that generous. A
  # depth near the boundary would make these specs flake with the
  # interpreter's stack size instead of proving the guard.
  def bomb
    opens = (1..4000).map { |i| "subgraph s#{i}" }.join("\n")
    "graph TD\n#{opens}\nA\n#{"end\n" * 4000}"
  end

  # The order matters: a file AFTER the bad one is the only thing that can
  # tell "reported and continued" from "died at the bad one".
  def in_batch_dir
    Dir.mktmpdir do |dir|
      input = File.join(dir, "in")
      output = File.join(dir, "out")
      Dir.mkdir(input)
      File.write(File.join(input, "1-ok.mmd"), "graph TD\nAlpha-->Beta\n")
      File.write(File.join(input, "2-bomb.mmd"), bomb)
      File.write(File.join(input, "3-ok.mmd"), "graph TD\nOmega-->Zeta\n")
      yield input, output
    end
  end

  # The rescue in `BatchCommand` is a SECOND widened boundary and needs the
  # same proof as the engine's, in both directions. The exhaustion spec
  # constrains the CONSTANT; `rescue Exception` written at THIS site passes
  # that untouched, and then Ctrl-C, `exit` and a host's `Timeout.timeout`
  # are all swallowed part way through a batch run. `File.read` sits inside
  # the rescued block, which is how a real one of each is driven through it.
  # Hands back a lambda so the example decides whether the exception should
  # propagate or be swallowed.
  def batching(exception)
    lambda do
      in_batch_dir do |input, output|
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read)
          .with(File.join(input, "2-bomb.mmd")).and_raise(exception)

        run_batch(input, output)
      end
    end
  end

  # @return [Array(Sirena::Commands::BatchCommand, String)] the command
  #   after #run, and everything the run printed to stdout
  def batch_capture(input, output)
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    command = Sirena::Commands::BatchCommand.new(input: input, output: output)
    command.run
    [command, captured.string]
  ensure
    $stdout = original
  end

  # @return [Sirena::Commands::BatchCommand] the command, after #run
  def batch_command(input, output)
    batch_capture(input, output).first
  end

  # @return [String] everything the run printed to stdout
  def run_batch(input, output)
    batch_capture(input, output).last
  end
end
