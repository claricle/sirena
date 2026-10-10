# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Package do
  it "ends the chain at an id that names no package" do
    expect(described_class.chain("ghost", [])).to eq(["ghost"])
  end
end
