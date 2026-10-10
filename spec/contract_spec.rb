# frozen_string_literal: true

require "spec_helper"

# The contract every diagram type must honor, checked against
# Notation::Mermaid::TYPES -- the only place a type is declared -- so the
# invariant grows with the table instead of with a hand-kept list living
# apart from it. See TODO.architecture/01-safety-net.md Part A.
RSpec.describe Sirena::Notation::Mermaid do
  let(:types) { described_class::TYPES.keys }
  let(:fixture_dir) { File.join(__dir__, "fixtures", "contract") }

  # An iteration over TYPES cannot notice a deleted row: the row's examples
  # just stop existing. The fixture basenames are the inventory kept outside
  # the table, so a row deleted from either side turns this red.
  it "has exactly one canonical fixture per TYPES row, and no other" do
    basenames = Dir.children(fixture_dir).map { |f| File.basename(f, ".mmd") }

    expect(types.map(&:to_s).sort).to eq(basenames.sort)
  end

  # R2 (RULES.md): an abstract method not walked by a spec is decoration.
  # `def type` was the pre-fix spelling on 5 models; grep is the same check
  # a reviewer would run by hand, kept here so it cannot silently reappear.
  it "has no diagram model still spelling the contract method `type`" do
    diagram_files = Dir.glob(
      File.join(__dir__, "..", "lib", "sirena", "diagram", "**", "*.rb"),
    )
    offenders = diagram_files.select do |path|
      File.readlines(path).any? { |line| line.match?(/^\s*def type$/) }
    end

    expect(offenders)
      .to be_empty, "def type still present in: #{offenders.join(', ')}"
  end

  # Same shape as the `def type` check above, for the other half of this
  # refactor: Layout::Base#call is the ONLY place the validity guard
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
  it "has no registered transform overriding the guarded entry point" do
    guard_methods = %i[call to_graph]
    offenders = types.filter_map do |type|
      transform_class = Sirena::Layout.for(type).class
      owners = guard_methods.filter_map do |method_name|
        owner = transform_class.instance_method(method_name).owner
        "#{method_name} owned by #{owner}" unless owner == Sirena::Layout::Base
      end
      "#{type}: #{owners.join(', ')}" unless owners.empty?
    end
    message = "guard entry point overridden for: #{offenders.join('; ')}"

    expect(offenders).to be_empty, message
  end

  it "has deleted the TreemapParser alias" do
    expect(Sirena::Parser.const_defined?(:TreemapParser, false)).to be(false)
  end

  described_class::TYPES.each_key do |type|
    describe type.inspect do
      it_behaves_like "a diagram type", type, DiagramTypeGaps.for(type)
    end
  end

  # Not a unit test on Layout::Base#to_graph directly — that test would
  # stop meaning anything the moment items 04/06 change what sits inside the
  # pipeline. Driving an invalid model through the real Engine#render is the
  # one form of this assertion that survives both refactors, because it only
  # depends on Engine still calling into something that honors the guard.
  #
  # A hand-built invalid model can't be reached through real Mermaid text for
  # most types (the grammars don't produce semantically-invalid-but-
  # syntactically-valid trees easily), so the parser step alone is stubbed —
  # layout, renderer and model stay the real classes.
  #
  # Deliberately :kanban, not :pie. Pie's transform already called
  # `diagram.valid?` on its own before this change, so a pie-based version of
  # this spec would pass identically against the old per-transform guards and
  # prove nothing about the new centralized one. Kanban's transform did not
  # call `valid?` at all — this is the type that actually exercises the new
  # mechanism.
  describe "an invalid model driven through Engine" do
    it "raises rather than silently producing SVG" do
      invalid_diagram = Sirena::Diagram::Kanban.new.tap do |kanban|
        kanban.columns = [Sirena::Diagram::KanbanColumn.new(id: nil,
                                                            title: nil)]
      end
      stub_parser = Class.new do
        define_method(:parse) { |_source| invalid_diagram }
      end

      allow(Sirena::Parser).to receive(:for).with(:kanban)
        .and_return(stub_parser.new)

      expect { Sirena::Engine.new.render("kanban\n") }
        .to raise_error(Sirena::Layout::LayoutError, /Invalid diagram/)
    end
  end

  # The mirror of the test above: a bare `kanban` header parses to an empty
  # board (no columns), and `Diagram::Kanban#valid?` treats that as valid on
  # purpose (see the comment on that method) -- do not reintroduce a "must
  # have at least one column" check there. This asserts both halves of that
  # guarantee stay true together: the model-level predicate, and the
  # Engine-level guarantee it backs now that Layout::Base#call runs the
  # guard for kanban too.
  describe "a valid, empty model driven through Engine" do
    it "renders rather than raising" do
      expect(Sirena::Diagram::Kanban.new.valid?).to be(true)
      expect(Sirena::Engine.new.render("kanban\n")).to include("<svg")
    end
  end
end
