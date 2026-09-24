# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'timeout'
require 'tmpdir'
require 'sirena/commands/batch'

# `bomb`, `batching`, `run_batch` are ordinary domain words: `include` this
# per example group, never register it globally. It stays `include`d (not
# `module_function`) because most methods use RSpec mocking (`allow`); only
# `exhaustion_message_for` is pure and marked `module_function` in place.
# `run_batch` returns what BatchCommand printed; `batch_command` returns the
# command itself (`#success?`).
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

  # Realistic per-class messages, matching the ones exhaustion_errors_spec.rb
  # raises for the same two classes -- not load-bearing to the assertion
  # below, only to reading the report as a person would.
  def exhaustion_message_for(exhaustion_class)
    exhaustion_class == SystemStackError ? 'stack level too deep' : 'failed to allocate memory'
  end
  module_function :exhaustion_message_for
end

# Batch's documented promise is that one bad file is reported and the run
# carries on. An exhaustion fault is not a `StandardError`, so before this
# was closed the promise held for every kind of bad file except the kind
# someone would choose on purpose: the run died part way, and the files
# after the bad one were never attempted.
RSpec.describe Sirena::Commands::BatchCommand do
  include BatchCommandRunner

  it 'renders the files after a bomb instead of dying at it' do
    in_batch_dir do |input, output|
      run_batch(input, output)

      expect(Dir.children(output).sort).to eq(['1-ok.svg', '3-ok.svg'])
    end
  end

  it 'reports the bomb as one failure and the rest as successes' do
    in_batch_dir do |input, output|
      report = run_batch(input, output)

      expect(report).to include('Success: 2')
      expect(report).to include('Failed:  1')
      expect(report).to include('Total:   3')
    end
  end

  it 'names the file that failed and why' do
    in_batch_dir do |input, output|
      report = run_batch(input, output)

      expect(report).to include('2-bomb.mmd: Diagram nests too deeply to parse.')
    end
  end

  # Exhaustion can arrive from OUTSIDE the engine's boundary: reading the
  # file happens in this class, not in the engine, and a file large enough
  # to exhaust the heap raises here where the engine never sees it. Without
  # this example the widened rescue in BatchCommand is dead code that the
  # engine's own boundary happens to cover.
  #
  # Both members of EXHAUSTION_ERRORS, not just NoMemoryError: pinning only
  # one leaves a rescue narrowed to that single class -- `rescue
  # NoMemoryError, StandardError` -- passing every example here, with a
  # constructed SystemStackError from this same File.read boundary
  # escaping uncaught. The engine spec already drives each member through
  # its own boundary as two separate examples; this loop does the
  # equivalent for the batch boundary, over the constant itself rather
  # than a name copied from it, so a future third member is covered
  # without anyone remembering to add a case.
  Sirena::EXHAUSTION_ERRORS.each do |exhaustion_class|
    it "survives #{exhaustion_class} raised while reading a file, not only while rendering" do
      in_batch_dir do |input, output|
        bomb_path = File.join(input, '2-bomb.mmd')
        message = exhaustion_message_for(exhaustion_class)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read)
          .with(bomb_path).and_raise(exhaustion_class.new(message))

        report = run_batch(input, output)

        expect(Dir.children(output).sort).to eq(['1-ok.svg', '3-ok.svg'])
        expect(report).to include("2-bomb.mmd: #{message}")
      end
    end
  end

  # Reaching the summary is the exit-0 guarantee in observable form: the CLI
  # only gets to its own exit if `run` came back rather than unwinding past
  # it, and `print_summary` is the last thing `run` does.
  it 'reaches the end of the run rather than unwinding past the caller' do
    in_batch_dir do |input, output|
      report = run_batch(input, output)

      expect(report).to include('BATCH RENDERING SUMMARY')
      expect(report).to end_with("Success rate: 66.7%\n")
    end
  end

  it 'lets an exit request through untouched' do
    expect(&batching(SystemExit)).to raise_error(SystemExit)
  end

  it 'lets an interrupt through untouched' do
    expect(&batching(Interrupt)).to raise_error(Interrupt)
  end

  # A host that wraps a batch run in `Timeout.timeout` unwinds through this
  # class. Swallowing it would make the timeout report a file failure, carry
  # on with the next file, and never fire.
  it 'lets a host timeout unwind through it' do
    expect(&batching(Timeout::ExitException.new('too slow')))
      .to raise_error(Timeout::ExitException)
  end

  # `NotImplementedError` rather than a `Class.new(Exception)`: the
  # `Lint/InheritException` autocorrect rewrites the latter to
  # `StandardError`, which would quietly turn this into a test of nothing.
  it 'lets a class outside the exhaustion family through untouched' do
    expect(&batching(NotImplementedError)).to raise_error(NotImplementedError)
  end

  # `-i` naming a single FILE (not a directory) is documented, not
  # incidental (cli.rb's `batch` desc, and this class's own
  # `find_mermaid_files`, both accept either). The relative-path
  # calculation used to assume `input_base` was always a directory: for a
  # file it stripped the path down to '', landing `File.write` on the
  # output directory itself and raising `Errno::EISDIR`, counted as a
  # failure, nothing ever written.
  it 'renders a single file passed via -i, not only a directory' do
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'solo.mmd')
      output = File.join(dir, 'out')
      File.write(input, "graph TD\nAlpha-->Beta\n")

      run_batch(input, output)

      expect(Dir.children(output)).to eq(['solo.svg'])
    end
  end

  # `#success?` is what `Cli#batch` checks after `#run` to decide its exit
  # code (D1: exit 1 if any item failed). Asserted directly here rather
  # than only through the CLI spec, since `BatchCommand` is also used
  # directly by callers that are not the CLI.
  it 'reports success when every item succeeds' do
    in_batch_dir do |input, output|
      # Route around the bomb fixture -- this example wants an all-success
      # run, not the mixed one `in_batch_dir` builds by default.
      FileUtils.rm(File.join(input, '2-bomb.mmd'))

      expect(batch_command(input, output).success?).to be(true)
    end
  end

  it 'reports failure when any item fails' do
    in_batch_dir do |input, output|
      expect(batch_command(input, output).success?).to be(false)
    end
  end

  # `#success?`'s own docstring says a run that found no files at all
  # counts as success -- this is documented INTENT, not a bug, so the gap
  # this closes is coverage, not behavior. Asserted for both an empty
  # directory and a nonexistent one, since `find_mermaid_files` returns
  # `[]` for either (`File.directory?` is false on a path that doesn't
  # exist, falling through to the final `else []` branch).
  it 'reports success on an empty input directory' do
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'empty')
      output = File.join(dir, 'out')
      Dir.mkdir(input)

      expect(batch_command(input, output).success?).to be(true)
    end
  end

  it 'reports success on a nonexistent input path' do
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'does-not-exist')
      output = File.join(dir, 'out')

      expect(batch_command(input, output).success?).to be(true)
    end
  end
end
