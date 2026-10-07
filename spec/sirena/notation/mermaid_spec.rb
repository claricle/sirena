# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Mermaid do
  describe ".id" do
    it "names the notation" do
      expect(described_class.id).to eq(:mermaid)
    end
  end

  describe ".parse" do
    let!(:pie_handlers) { described_class.type_handlers(:pie) }
    let(:defaulted_handlers) do
      Hash.new { |_hash, key| pie_handlers.fetch(key) }
        .merge(parser: pie_handlers.fetch(:parser))
    end

    it "reads :transform and :renderer through the handler hash's own lookup" do
      allow(described_class).to receive(:type_handlers) { defaulted_handlers }
      parsed = described_class.parse("pie\n\"a\": 1")

      expect(parsed.to_h.values_at(:transform, :renderer))
        .to eq(pie_handlers.values_at(:transform, :renderer))
    end
  end

  describe ".type_registered?" do
    it "is true for a registered type" do
      expect(described_class.type_registered?(:pie)).to be(true)
    end

    it "is false for an unknown type" do
      expect(described_class.type_registered?(:no_such_type)).to be(false)
    end
  end

  describe ".clear_types" do
    around do |example|
      snapshot = described_class.types.to_h do |type|
        [type, described_class.type_handlers(type).dup]
      end
      example.run
    ensure
      snapshot.each do |type, handlers|
        described_class.register_type(type, **handlers)
      end
    end

    it "empties the type table" do
      described_class.clear_types

      expect(described_class.types).to be_empty
    end

    it "replaces the table, so a hash an earlier clear returned stays as it was" do
      returned = described_class.clear_types
      described_class.register_type(
        :probe, parser: Object, transform: Object, renderer: Object,
                model: Object
      )
      described_class.clear_types

      expect(returned).to include(:probe)
    end

    it "is what DiagramRegistry.clear empties" do
      Sirena::DiagramRegistry.clear

      expect(described_class.types).to be_empty
    end

    it "makes a rendering fail until the types are registered again" do
      described_class.clear_types

      expect { Sirena.render("pie\n\"a\": 1") }.to raise_error(
        Sirena::Engine::DiagramTypeError,
        /No handlers registered for diagram type: pie/,
      )
    end
  end
end
