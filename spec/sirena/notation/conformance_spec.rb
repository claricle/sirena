# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples "a conforming notation" do
  let(:unrecognised) { "nothing a notation recognises" }

  it "has a Symbol id" do
    expect(notation.id).to be_a(Symbol)
  end

  it "has an id that is a lowercase identifier" do
    expect(notation.id.to_s).to match(Sirena::Notation::ID_PATTERN)
  end

  it "refuses a source it cannot recognise with its own DiagramTypeError" do
    expect { notation.parse(unrecognised) }.to raise_error(
      Sirena::Engine::DiagramTypeError,
      /\AUnable to detect diagram type from source\. Source must start with/,
    )
  end

  it "does not claim a source it cannot recognise" do
    expect(notation.claims?(unrecognised)).to be(false)
  end

  [
    "\xff\xfe graph TD".b, "\xc3\x28", "é".encode("ISO-8859-1"), "", "\0"
  ].each do |source|
    it "answers true or false from claims? for #{source.inspect}" do
      expect(notation.claims?(source)).to be(true).or be(false)
    end
  end

  it "lists its types as Symbols" do
    expect(notation.types).to all(be_a(Symbol))
  end
end

RSpec.describe Sirena::Notation, ".plugins" do
  described_class.plugins.each do |registered|
    describe "registered notation #{registered.id}" do
      let(:notation) { registered }

      it_behaves_like "a conforming notation"
    end
  end

  describe "the fake notation" do
    let(:notation) do
      FakeNotation::Plugin.new(
        id: :fake, extensions: %w[.fake].freeze, prefix: "@fake",
      )
    end

    it_behaves_like "a conforming notation"
  end
end
