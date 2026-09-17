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

    # A real allocation can reach the VM's C-level memory error path
    # before `raise` ever runs, and that path skips backtrace
    # population -- so `NoMemoryError#backtrace` can be nil, unlike
    # every other exception in this file. `--verbose` asking
    # `handle_error` to print that backtrace must not itself crash the
    # CLI.
    #
    # `String.new(capacity: 2**62)` used to be how this was forced, but
    # that depends on the platform's C `long`: on Windows (`LLP64`,
    # 32-bit `long`) the same call fails converting the argument and
    # raises `RangeError: bignum too big to convert into 'long'`
    # instead, WITH a normal backtrace, never reaching the allocator at
    # all -- confirmed on PR #36's Windows CI (Ruby 3.3/3.4/4.0, all
    # three windows-latest jobs failed on the message and the missing
    # blank line; macOS and ubuntu, all three Rubies, passed). So the
    # old version pinned a platform's argument-conversion behaviour,
    # not the property this example is named for.
    #
    # Stubbing `#backtrace` on the exception instance is the portable
    # replacement: it overrides the reader, so it returns nil no matter
    # how the exception is raised. `and_raise(instance)` performs its
    # own `raise`, which sets a real backtrace internally, but the
    # stub is a method override and wins regardless -- confirmed
    # directly, `e.backtrace` still reads nil after the exception has
    # passed through `and_raise`'s `raise`. No VM allocation, no
    # platform dependency.
    it 'reports a backtrace-less exhaustion under --verbose without crashing' do
      exhausted = NoMemoryError.new('failed to allocate memory')
      allow(exhausted).to receive(:backtrace).and_return(nil)
      fake_command = instance_double(Sirena::Commands::RenderCommand)
      allow(fake_command).to receive(:run).and_raise(exhausted)
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
