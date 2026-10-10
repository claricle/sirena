# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Edge do
  subject(:edge) { described_class.read("[", :left) }

  it "identifies a left diagram edge" do
    expect([edge.global?, edge.left?]).to eq([true, true])
  end
end
