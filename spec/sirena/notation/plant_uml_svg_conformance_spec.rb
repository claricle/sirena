# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

# Requiring an external notation registers it; restore the suite baseline and
# register inside the isolated context per example (as plant_uml_spike_spec).
Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML do
  include PlantUmlConformanceHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  describe "spike cases" do
    let(:offenders) { conformance_offenders(spike_sources) }

    it "has cases to render" do
      expect(spike_sources).not_to be_empty
    end

    it "renders every case conformantly" do
      expect(offenders).to be_empty, -> { offenders.join("\n") }
    end
  end

  describe "oracle-valid corpus cases" do
    let(:offenders) { conformance_offenders(corpus_sources) }
    let(:valid_count) do
      oracle_verdicts.count { |v| v["verdict"] == "valid" }
    end

    it "lists one source per valid verdict" do
      expect(corpus_sources.size).to eq(valid_count)
    end

    it "has a file for every source" do
      expect(corpus_sources).to all(satisfy { |path| File.exist?(path) })
    end

    it "has cases to render" do
      expect(corpus_sources).not_to be_empty
    end

    it "renders every case conformantly" do
      expect(offenders).to be_empty, -> { offenders.join("\n") }
    end
  end
end
