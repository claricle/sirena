# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Mermaid do
  let(:engine_source) do
    File.read(File.expand_path("../../../lib/sirena/engine.rb", __dir__))
  end
  let(:moved_constants) do
    %w[
      REFUSES_BARE_COMMENT REFUSES_HEADERLESS_DIRECTIVE
      REFUSES_LATE_FRONTMATTER REFUSED_PREAMBLE
    ]
  end
  let(:forbidden) do
    /Source\s*(?:\.|::)\s*(?:split|title)
     |REFUSE|DiagramRegistry|type_handlers/x
  end

  it "keeps the preamble rules out of Engine" do
    leaked = moved_constants.select do |name|
      Sirena::Engine.const_defined?(name, false)
    end

    expect(leaked).to be_empty
  end

  it "keeps Engine's own constants to its two deprecated tables and errors" do
    expect(Sirena::Engine.constants(false)).to contain_exactly(
      :DIAGRAM_TYPE_PATTERNS, :DIAGRAM_TYPE_KEYWORDS,
      :DiagramTypeError, :PipelineError
    )
  end

  it "keeps Engine's deprecated pattern table identical to Mermaid's" do
    expect(Sirena::Engine::DIAGRAM_TYPE_PATTERNS)
      .to equal(described_class::DIAGRAM_TYPE_PATTERNS)
  end

  it "keeps Engine's deprecated keyword table identical to Mermaid's" do
    expect(Sirena::Engine::DIAGRAM_TYPE_KEYWORDS)
      .to equal(described_class::DIAGRAM_TYPE_KEYWORDS)
  end

  it "never reaches for Source, the preamble rules or the type table" do
    expect(engine_source).not_to match(forbidden)
  end

  it "keeps lib/sirena.rb at 40 lines or fewer" do
    path = File.expand_path("../../../lib/sirena.rb", __dir__)

    expect(File.readlines(path).size).to be <= 40
  end
end
