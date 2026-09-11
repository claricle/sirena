# frozen_string_literal: true

require 'spec_helper'

# The contract every registered diagram type must honor, checked against
# DiagramRegistry — the single source of which class serves a type — so the
# invariant grows with the registry instead of with a hand-kept list living
# apart from it. See TODO.architecture/01-safety-net.md Part A.
RSpec.describe Sirena::DiagramRegistry do
  # Registry/pattern set parity. Without this, a type missing from the
  # registry is invisible to every assertion below (they all iterate
  # DiagramRegistry.types), while Engine can still detect and reject it with
  # its own error. Comparing against Engine::DIAGRAM_TYPE_PATTERNS.keys — a
  # list that does NOT shrink when a registry row is deleted — is what makes
  # deleting a row turn this file red.
  it 'registers exactly the types Engine can detect' do
    expect(described_class.types.sort)
      .to eq(Sirena::Engine::DIAGRAM_TYPE_PATTERNS.keys.sort)
  end

  # R2 (RULES.md): an abstract method not walked by a spec is decoration.
  # `def type` was the pre-fix spelling on 5 models; grep is the same check
  # a reviewer would run by hand, kept here so it cannot silently reappear.
  it 'has no diagram model still spelling the contract method `type`' do
    diagram_files = Dir.glob(
      File.join(__dir__, '..', 'lib', 'sirena', 'diagram', '**', '*.rb')
    )
    offenders = diagram_files.select do |path|
      File.readlines(path).any? { |line| line.match?(/^\s*def type$/) }
    end

    expect(offenders)
      .to be_empty, "def type still present in: #{offenders.join(', ')}"
  end

  # Same shape as the `def type` check above, for the other half of this
  # refactor: Transform::Base#call is the ONLY place the validity guard
  # runs (#to_graph is a thin delegate to it). A concrete transform
  # redefining either would silently shadow the guard and disable it for
  # that one type — the exact "decoration" failure mode R2 (RULES.md)
  # exists to prevent — and nothing else here would notice, since every
  # other assertion drives a VALID diagram.
  #
  # Reflection, not a text grep: a grep on `def call(` / `def to_graph(`
  # misses a subclass that reintroduces either via `define_method` or
  # `alias_method` — no line of source text would match, and the guard
  # would still be gone. `instance_method(...).owner` answers the real
  # question (which class actually defines the method that runs) instead
  # of the proxy question (does this source file contain a matching line).
  it 'has no registered transform overriding the guarded entry point' do
    guard_methods = [:call, :to_graph]
    offenders = described_class.types.filter_map do |type|
      transform_class = described_class.get(type)[:transform]
      owners = guard_methods.filter_map do |method_name|
        owner = transform_class.instance_method(method_name).owner
        "#{method_name} owned by #{owner}" unless owner == Sirena::Transform::Base
      end
      "#{type}: #{owners.join(', ')}" unless owners.empty?
    end
    message = "guard entry point overridden for: #{offenders.join('; ')}"

    expect(offenders).to be_empty, message
  end

  it 'has deleted the Treemap = TreemapParser alias' do
    expect(Sirena::Parser.const_defined?(:Treemap, false)).to be(false)
  end

  described_class.types.each do |type|
    describe type.inspect do
      let(:handlers) { described_class.get(type) }
      let(:fixture_path) do
        File.join(__dir__, 'fixtures', 'contract', "#{type}.mmd")
      end
      let(:source) { File.read(fixture_path) }
      let(:diagram) { handlers[:parser].new.parse(source) }

      it 'has a canonical fixture that parses' do
        expect(File).to exist(fixture_path)
        expect { diagram }.not_to raise_error
      end

      it 'registers a parser inheriting Parser::Base' do
        expect(handlers[:parser].ancestors).to include(Sirena::Parser::Base)
      end

      it 'registers a transform inheriting Transform::Base' do
        expect(handlers[:transform].ancestors)
          .to include(Sirena::Transform::Base)
      end

      it 'registers a renderer inheriting Renderer::Base' do
        expect(handlers[:renderer].ancestors)
          .to include(Sirena::Renderer::Base)
      end

      it 'registers a model inheriting Diagram::Base' do
        expect(handlers[:model].ancestors).to include(Sirena::Diagram::Base)
      end

      it 'returns diagram_type as the registered symbol' do
        expect(diagram.diagram_type).to eq(type)
      end

      # respond_to?(:valid?) alone is not enough: six models responded only
      # because they inherited Diagram::Base#valid?, which raises
      # NotImplementedError when actually invoked. Always call it and check
      # the return value's type, not merely that the call didn't raise —
      # `def valid?; :maybe; end` must fail this and only this assertion
      # catches it.
      it 'answers valid? with an actual boolean' do
        expect(diagram.valid?).to be(true).or be(false)
      end

      it 'has the parser return an instance of the registered model' do
        expect(diagram).to be_a(handlers[:model])
      end
    end
  end

  # Not a unit test on Transform::Base#to_graph directly — that test would
  # stop meaning anything the moment items 04/06 change what sits inside the
  # pipeline. Driving an invalid model through the real Engine#render is the
  # one form of this assertion that survives both refactors, because it only
  # depends on Engine still calling into something that honors the guard.
  #
  # A hand-built invalid model can't be reached through real Mermaid text for
  # most types (the grammars don't produce semantically-invalid-but-
  # syntactically-valid trees easily), so the parser step alone is stubbed —
  # transform, renderer and model stay the real registered classes, and the
  # registration is restored immediately after.
  #
  # Deliberately :kanban, not :pie. Pie's transform already called
  # `diagram.valid?` on its own before this change, so a pie-based version of
  # this spec would pass identically against the old per-transform guards and
  # prove nothing about the new centralized one. Kanban's transform did not
  # call `valid?` at all — this is the type that actually exercises the new
  # mechanism.
  describe 'an invalid model driven through Engine' do
    it 'raises rather than silently producing SVG' do
      original = described_class.get(:kanban)
      invalid_diagram = Sirena::Diagram::Kanban.new.tap do |kanban|
        kanban.columns = [Sirena::Diagram::KanbanColumn.new(id: nil, title: nil)]
      end
      stub_parser = Class.new do
        define_method(:parse) { |_source| invalid_diagram }
      end

      begin
        described_class.register(:kanban, **original, parser: stub_parser)

        expect { Sirena::Engine.new.render("kanban\n") }
          .to raise_error(Sirena::Engine::PipelineError, /Invalid diagram/)
      ensure
        described_class.register(:kanban, **original)
      end
    end
  end
end
