# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'sirena/cli'
require 'sirena/commands/render'

RSpec.describe Sirena::Cli do
  # `RenderCommand#run` builds the theme (a hostile `--theme` YAML file)
  # and reads the input file BEFORE `Engine#render` -- and therefore
  # before the engine's own widened rescue -- ever runs, so this CLI
  # boundary needs the same proof as the engine's and the batch
  # command's: it survives EXHAUSTION_ERRORS and it does not swallow
  # Ruby's own control flow.
  describe 'render command' do
    def rendering(exception)
      fake_command = instance_double(Sirena::Commands::RenderCommand)
      allow(fake_command).to receive(:run).and_raise(exception)
      allow(Sirena::Commands::RenderCommand).to receive(:new)
        .and_return(fake_command)
      -> { described_class.start(['render', 'unused.mmd']) }
    end

    it 'converts a stack overflow into a clean exit instead of a raw crash' do
      overflow = SystemStackError.new('stack level too deep')

      expect(&rendering(overflow))
        .to output(/\AError: stack level too deep\n\z/).to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    it 'converts an exhausted heap into a clean exit instead of a raw crash' do
      exhausted = NoMemoryError.new('failed to allocate memory')

      expect(&rendering(exhausted))
        .to output(/\AError: failed to allocate memory\n\z/).to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    it 'lets an exit request through untouched' do
      expect(&rendering(SystemExit)).to raise_error(SystemExit) do |error|
        expect(error.status).not_to eq(1)
      end
    end

    it 'lets an interrupt through untouched' do
      expect(&rendering(Interrupt)).to raise_error(Interrupt)
    end

    # A host that wraps a CLI invocation in `Timeout.timeout` unwinds
    # through this class. Swallowing it would print a render failure and
    # never let the timeout fire.
    it 'lets a host timeout unwind through it' do
      expect(&rendering(Timeout::ExitException.new('too slow')))
        .to raise_error(Timeout::ExitException)
    end

    # `NotImplementedError` rather than a `Class.new(Exception)`: the
    # `Lint/InheritException` autocorrect rewrites the latter to
    # `StandardError`, which would quietly turn this into a test of
    # nothing.
    it 'lets a class outside the exhaustion family through untouched' do
      expect(&rendering(NotImplementedError)).to raise_error(NotImplementedError)
    end

    # `String.new(capacity:)` fails the allocation at the VM level before
    # Ruby's `raise` machinery ever runs, so the resulting NoMemoryError
    # never gets a backtrace populated -- unlike every other exception in
    # this file, which goes through a real `raise` and always has one.
    # `--verbose` asking `handle_error` to print that backtrace must not
    # itself crash the CLI.
    #
    # The allocation has to happen INSIDE the stubbed call (a block
    # implementation), not via `and_raise(instance)`: `and_raise` performs
    # its own `raise`, and Ruby's `raise` populates a nil backtrace at
    # the point it re-raises from -- which would silently give this
    # example a real backtrace and test nothing. Confirmed directly: an
    # already-nil-backtrace exception handed to `and_raise` arrives at
    # the rescue WITH a backtrace, populated by `and_raise`'s own raise.
    it 'reports a backtrace-less exhaustion under --verbose without crashing' do
      fake_command = instance_double(Sirena::Commands::RenderCommand)
      allow(fake_command).to receive(:run) { String.new(capacity: 2**62) }
      allow(Sirena::Commands::RenderCommand).to receive(:new)
        .and_return(fake_command)

      # `warn error.backtrace&.join("\n")` on a nil backtrace warns nil --
      # an extra blank line, not a crash. That blank line is what proves
      # the `&.` ran rather than raising, so it is asserted here rather
      # than trimmed away.
      expect { described_class.start(['render', 'unused.mmd', '--verbose']) }
        .to output("Error: failed to allocate memory\n\n").to_stderr
        .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end
  end

  describe 'version command' do
    it 'displays version information' do
      expect { described_class.start(['version']) }.to output(
        /sirena version #{Sirena::VERSION}/
      ).to_stdout
    end
  end

  describe 'types command' do
    it 'lists supported diagram types' do
      expect { described_class.start(['types']) }.to output(
        /Supported diagram types:/
      ).to_stdout
    end

    it 'includes all registered types' do
      output = capture_stdout { described_class.start(['types']) }
      expect(output).to include('flowchart')
      expect(output).to include('sequence')
      expect(output).to include('class_diagram')
      expect(output).to include('state_diagram')
      expect(output).to include('er_diagram')
      expect(output).to include('user_journey')
    end
  end

  describe 'help command' do
    it 'displays help information' do
      expect { described_class.start(['help']) }.to output(
        /Commands:/
      ).to_stdout
    end
  end

  def capture_stdout(&block)
    original_stdout = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
