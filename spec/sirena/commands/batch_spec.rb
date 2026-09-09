# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'tmpdir'
require 'sirena/commands/batch'

# Batch's documented promise is that one bad file is reported and the run
# carries on. An exhaustion fault is not a `StandardError`, so before this
# was closed the promise held for every kind of bad file except the kind
# someone would choose on purpose: the run died part way, and the files
# after the bad one were never attempted.
RSpec.describe Sirena::Commands::BatchCommand do
  # 4000 nested subgraphs -- past the depth the flowchart parser can carry,
  # so it fails where a well-formed neighbour does not. `parse_tree`
  # (flowchart.rb:58-60) converts that overflow into a ParseError, so this
  # file exercises the ORDINARY failure path; the widened rescue is driven
  # by the exhaustion examples below, which raise a real `NoMemoryError` at
  # `File.read`.
  #
  # 4000 is well past the boundary rather than close to it: measured to
  # still overflow under a 16MB and a 32MB RUBY_THREAD_VM_STACK_SIZE, where
  # a shallower depth parses cleanly once the stack is that generous. A
  # depth near the boundary would make this file flake with the
  # interpreter's stack size instead of proving the guard.
  def bomb
    opens = (1..4000).map { |i| "subgraph s#{i}" }.join("\n")
    "graph TD\n#{opens}\nA\n#{"end\n" * 4000}"
  end

  # The order matters: a file AFTER the bad one is the only thing that can
  # tell "reported and continued" from "died at the bad one".
  def in_batch_dir
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'in')
      output = File.join(dir, 'out')
      Dir.mkdir(input)
      File.write(File.join(input, '1-ok.mmd'), "graph TD\nAlpha-->Beta\n")
      File.write(File.join(input, '2-bomb.mmd'), bomb)
      File.write(File.join(input, '3-ok.mmd'), "graph TD\nOmega-->Zeta\n")
      yield input, output
    end
  end

  # The rescue in `BatchCommand` is a SECOND widened boundary and needs the
  # same proof as the engine's, in both directions. The exhaustion spec
  # constrains the CONSTANT; `rescue Exception` written at THIS site passes
  # that untouched, and then Ctrl-C, `exit` and a host's `Timeout.timeout`
  # are all swallowed part way through a batch run. `File.read` sits inside
  # the rescued block, which is how a real one of each is driven through it.
  def batching(exception)
    lambda do
      in_batch_dir do |input, output|
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read)
          .with(File.join(input, '2-bomb.mmd')).and_raise(exception)

        run_batch(input, output)
      end
    end
  end

  def run_batch(input, output)
    original = $stdout
    $stdout = StringIO.new
    described_class.new(input: input, output: output).run
    $stdout.string
  ensure
    $stdout = original
  end

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

      expect(report).to include('2-bomb.mmd: Rendering failed: ' \
                                'Diagram nests too deeply to parse.')
    end
  end

  # Exhaustion can arrive from OUTSIDE the engine's boundary: reading the
  # file happens in this class, not in the engine, and a file large enough
  # to exhaust the heap raises here where the engine never sees it. Without
  # this example the widened rescue in BatchCommand is dead code that the
  # engine's own boundary happens to cover.
  it 'survives exhaustion raised while reading a file, not only while rendering' do
    in_batch_dir do |input, output|
      bomb_path = File.join(input, '2-bomb.mmd')
      allow(File).to receive(:read).and_call_original
      exhausted = NoMemoryError.new('failed to allocate memory')
      allow(File).to receive(:read).with(bomb_path).and_raise(exhausted)

      report = run_batch(input, output)

      expect(Dir.children(output).sort).to eq(['1-ok.svg', '3-ok.svg'])
      expect(report).to include('2-bomb.mmd: failed to allocate memory')
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
end
