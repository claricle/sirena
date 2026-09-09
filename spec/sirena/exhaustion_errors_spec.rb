# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

# `SystemStackError` is not a `StandardError`, so it walked out through
# every rescue in this gem and through any host that catches `StandardError`
# -- taking the process down instead of failing one render.
#
# The fix has to hold in BOTH directions, and the second is the easier one to
# get wrong: widening a boundary until it swallows Ruby's own control flow
# breaks `exit`, Ctrl-C and a host's `Timeout.timeout`, which is a worse
# failure than the one being repaired.
RSpec.describe Sirena::Engine do
  # A class outside StandardError that is NOT exhaustion, standing in for
  # anything a future dependency might raise. `NotImplementedError` is used
  # rather than a `Class.new(Exception)` because `Lint/InheritException`
  # rewrites the latter to `StandardError`, which would quietly turn every
  # example below into a test of nothing.
  let(:foreign) { NotImplementedError }

  def rendering(exception)
    engine = Sirena::Engine.new
    allow(engine).to receive(:detect_diagram_type).and_raise(exception)
    -> { engine.render("graph TD\nA-->B\n") }
  end

  describe 'Sirena::EXHAUSTION_ERRORS' do
    # Ask the loaded hierarchy what exists rather than listing the routes we
    # happened to think of. It decides the two directions a machine can:
    # membership outside `StandardError`, and exclusion of control flow.
    # It cannot decide whether a new class is exhaustion -- Ruby exposes no
    # marker for that -- so do not read these examples as covering it.
    let(:outside_standard_error) do
      ObjectSpace.each_object(Class).select do |klass|
        klass <= Exception && !(klass <= StandardError)
      end
    end

    it 'names only classes that really are outside StandardError' do
      expect(Sirena::EXHAUSTION_ERRORS)
        .to all(satisfy { |klass| klass <= Exception && !(klass <= StandardError) })
    end

    # Ruby raises exactly these two for resource exhaustion. Everything else
    # in the enumeration is control flow, a broken install, or security --
    # none of which mean "this diagram failed to render".
    #
    # A filter of the enumeration by these two names used to stand above this
    # assertion. It could only ever return them, so it proved nothing while
    # reading as a derivation; the assertion on the constant is the whole
    # content and now says so.
    it 'holds the exhaustion family at exactly the two Ruby raises' do
      expect(Sirena::EXHAUSTION_ERRORS)
        .to contain_exactly(SystemStackError, NoMemoryError)
    end

    # Keep this: it constrains the CONSTANT, so nothing can quietly add
    # `exit` or Ctrl-C to what the boundaries are told to swallow. It says
    # nothing about the rescue SITES -- `rescue Exception` written at one of
    # them passes this example untouched. The site examples are what cover
    # that direction: four for the engine below, four more for the batch
    # command in its own spec.
    it 'excludes every control-flow class the hierarchy has' do
      control_flow = [SystemExit, SignalException, Interrupt,
                      Timeout::ExitException]

      expect(outside_standard_error).to include(*control_flow)
      expect(Sirena::EXHAUSTION_ERRORS).not_to include(*control_flow)
    end
  end

  describe 'Sirena::Engine#render' do
    it 'turns a stack overflow into a rescuable pipeline error' do
      overflow = SystemStackError.new('stack level too deep')

      expect(&rendering(overflow))
        .to raise_error(Sirena::Engine::PipelineError,
                        /\ARendering failed: stack level too deep/)
    end

    it 'turns an exhausted heap into a rescuable pipeline error' do
      exhausted = NoMemoryError.new('failed to allocate memory')

      expect(&rendering(exhausted))
        .to raise_error(Sirena::Engine::PipelineError,
                        /\ARendering failed: failed to allocate memory/)
    end

    it 'lets an exit request through untouched' do
      expect(&rendering(SystemExit)).to raise_error(SystemExit)
    end

    it 'lets an interrupt through untouched' do
      expect(&rendering(Interrupt)).to raise_error(Interrupt)
    end

    # A host that wraps a render in `Timeout.timeout` unwinds through this
    # class. Swallowing it would make the timeout report a render failure
    # and never fire.
    it 'lets a host timeout unwind through it' do
      expect(&rendering(Timeout::ExitException.new('too slow')))
        .to raise_error(Timeout::ExitException)
    end

    it 'lets a class outside the exhaustion family through untouched' do
      expect(&rendering(foreign)).to raise_error(foreign)
    end
  end

  # A flowchart nested past the parser's own stack fails one render and
  # nothing else. `Parser::FlowchartParser#parse_tree` (flowchart.rb:58-60)
  # converts that overflow into a ParseError itself, so this example rides
  # the ORDINARY error path and proves the end-to-end shape, not the
  # widened rescue -- the one below proves the rescue.
  #
  # 4000 nested subgraphs is well past the boundary rather than close to
  # it: measured to still overflow under a 16MB and a 32MB
  # RUBY_THREAD_VM_STACK_SIZE, where 400 -- the depth this reads as a first
  # guess -- parses cleanly once the stack is that generous. A depth near
  # the boundary would make this example flake with the interpreter's
  # stack size instead of proving the guard.
  it 'reports a document nested past the parser stack as an ordinary error' do
    opens = (1..4000).map { |i| "subgraph s#{i}" }.join("\n")
    source = "graph TD\n#{opens}\nA\n#{"end\n" * 4000}"

    expect { Sirena.render(source) }
      .to raise_error(Sirena::Engine::PipelineError, /nests too deeply/)
  end

  # A `stateDiagram` parser does not convert an overflow, so this one really
  # does reach SystemStackError and proves the boundary itself.
  #
  # 4000, for the same reason as the flowchart bomb above: measured to
  # still overflow at 16MB and 32MB. 400 -- the depth this reads as a first
  # guess, and what the classDiagram original this was re-vehicled from
  # used -- parses cleanly once the stack is that generous, which flipped
  # this example green-then-red across the three sizes it has to hold
  # under.
  it 'reports a real stack overflow from an unguarded type as an ordinary error' do
    opens = (1..4000).map { |i| "state s#{i} {" }.join("\n")
    source = "stateDiagram-v2\n#{opens}\n[*] --> A\n#{"}\n" * 4000}"

    expect { Sirena.render(source) }
      .to raise_error(Sirena::Engine::PipelineError, /stack level too deep/)
  end
end
