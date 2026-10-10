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

  it "renders every spike case conformantly" do
    expect(spike_sources).not_to be_empty
    offenders = conformance_offenders(spike_sources)
    expect(offenders).to be_empty, -> { offenders.join("\n") }
  end

  it "renders every oracle-valid corpus case conformantly" do
    verdicts = oracle_verdicts.map { |v| v["verdict"] }
    expect(corpus_sources.size).to eq(verdicts.count("valid"))
    expect(corpus_sources).to all(satisfy { |path| File.exist?(path) })
    expect(corpus_sources).not_to be_empty
    offenders = conformance_offenders(corpus_sources)
    expect(offenders).to be_empty, -> { offenders.join("\n") }
  end
end
