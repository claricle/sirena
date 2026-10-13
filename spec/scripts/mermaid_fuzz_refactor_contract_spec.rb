# frozen_string_literal: true

require "spec_helper"
require_relative "../../scripts/mermaid_fuzz"

RSpec.describe MermaidFuzz do
  context "with seeded identifier generation" do
    let(:generator) do
      template = ->(id) { "diagram #{id}" }
      described_class::IdentifierGenerator.new(
        Random.new(42), wild_chars: %w[! ?], template: template
      )
    end
    let(:generated) do
      generator.cases(5).map { |item| [item.id, item.source] }
    end
    let(:expected) do
      [["gen-1", "diagram !!sk"], ["gen-2", "diagram ?!??u"],
       ["gen-3", "diagram v"], ["gen-4", "diagram W!B!U"],
       ["gen-5", "diagram 2!Y!d?"]]
    end

    it "keeps the seeded random draws, case identifiers and source template" do
      expect(generated).to eq(expected)
    end

    it "reports both character pools reached by the generated batch" do
      generated
      expect(generator.exercised_both_pools?).to be(true)
    end
  end

  context "with safe identifiers in a template containing wild characters" do
    let(:safe_generator) do
      Class.new(described_class::IdentifierGenerator) do
        private

        def random_char
          "A"
        end
      end.new(Random.new(42), wild_chars: ["!"],
                              template: ->(id) { "diagram !#{id}" })
    end

    it "measures exploration from raw identifiers rather than template text" do
      safe_generator.cases(5)
      expect(safe_generator.exercised_both_pools?).to be(false)
    end
  end

  context "with required runner oracle options" do
    let(:options) do
      { label: "probe", generator_factory: ->(_) {}, known_divergences: [],
        sirena_verdict_for: ->(_) {}, mermaid_getter: nil,
        mermaid_preflight: "flowchart TD\nA" }
    end

    it "accepts an explicitly omitted structural getter" do
      expect(described_class::Runner.new(**options).label).to eq("probe")
    end

    it "rejects missing oracle preflight before running either side" do
      arguments = options.except(:mermaid_preflight)
      expect { described_class::Runner.new(**arguments) }
        .to raise_error(ArgumentError, "missing keyword: :mermaid_preflight")
    end

    it "rejects an unknown option before running either side" do
      expect { described_class::Runner.new(**options, unknown: true) }
        .to raise_error(ArgumentError, "unknown keyword: :unknown")
    end
  end
end
